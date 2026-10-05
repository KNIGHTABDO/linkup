"""Claude Code through the `claude` CLI that is already signed in on this PC (no API keys): one long-lived
`claude -p --input-format stream-json --output-format stream-json` process per open session.

The CLI's control channel gives the live model list (initialize), interrupts, model switches and tool permission
prompts (--permission-prompt-tool stdio), and `rate_limit_event` carries the subscription's 5-hour / 7-day usage."""
from __future__ import annotations

import asyncio
import base64
import json
import logging
import os
import time
import uuid

from .base import Media, paths_in

log = logging.getLogger("linkup.claude")
CLAUDE = os.environ.get("LINKUP_CLAUDE", "claude")
WRITE_TOOLS = {"Write", "Edit", "MultiEdit", "NotebookEdit"}
_CARDS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "cards.md")
CARDS_PROMPT = open(_CARDS).read() if os.path.exists(_CARDS) else ""


async def _spawn(args: list[str], cwd: str) -> asyncio.subprocess.Process:
    return await asyncio.create_subprocess_exec(
        CLAUDE, *args, cwd=cwd, stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE, limit=64 << 20,
        env={**os.environ, "CLAUDE_CODE_ENTRYPOINT": "linkup"})


class ClaudeAgent:
    id = "claude"
    name = "Claude Code"

    def __init__(self, store, media: Media):
        self.store = store
        self.media = media
        self._catalog: dict | None = None
        self._catalog_at = 0.0
        self.ratelimit: dict | None = None

    async def catalog(self, force: bool = False) -> dict:
        if self._catalog and not force and time.time() - self._catalog_at < 600:
            return self._catalog
        try:
            proc = await _spawn(["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose"],
                                os.path.expanduser("~"))
            req = {"type": "control_request", "request_id": "init", "request": {"subtype": "initialize"}}
            proc.stdin.write((json.dumps(req) + "\n").encode())
            await proc.stdin.drain()
            data = None
            while True:
                line = await asyncio.wait_for(proc.stdout.readline(), 45)
                if not line:
                    break
                try:
                    msg = json.loads(line)
                except ValueError:
                    continue
                if msg.get("type") == "control_response":
                    data = msg.get("response", {}).get("response", {})
                    break
            proc.kill()
            await proc.wait()
        except Exception as exc:
            log.error("claude catalog failed: %s", exc)
            return self._catalog or {"id": self.id, "name": self.name, "available": False, "error": str(exc)}
        models = [{"id": m["value"], "name": m.get("displayName") or m["value"], "description": m.get("description"),
                   "resolved": m.get("resolvedModel"), "efforts": m.get("supportedEffortLevels") or []}
                  for m in (data or {}).get("models", [])]
        commands = [{"name": c.get("name"), "description": c.get("description")} for c in (data or {}).get("commands", [])]
        self._catalog = {
            "id": self.id, "name": self.name, "available": bool(models), "models": models,
            "defaultModel": "default", "account": (data or {}).get("account"), "commands": commands,
            "permissionModes": ["default", "acceptEdits", "plan", "bypassPermissions"],
            "supportsImages": True, "supportsInterrupt": True, "supportsPermissions": True,
        }
        self._catalog_at = time.time()
        return self._catalog

    def open(self, session: dict, emit) -> "ClaudeSession":
        return ClaudeSession(self, session, emit)


class ClaudeSession:
    def __init__(self, agent: ClaudeAgent, session: dict, emit):
        self.agent = agent
        self.session = session
        self.emit = emit
        self.proc: asyncio.subprocess.Process | None = None
        self.reader: asyncio.Task | None = None
        self.blocks: dict[str, str] = {}          # stream block key -> block id
        self.block_kind: dict[str, str] = {}
        self.tools: dict[str, dict] = {}          # tool_use id -> {name, input}
        self.pending_permissions: dict[str, str] = {}   # our id -> CLI request_id
        self.turn_started: float | None = None
        self.running = False
        self.spawned_model = None
        self.spawned_effort = None

    # -- process ----------------------------------------------------------------------------------------------
    async def _ensure(self):
        s = self.session
        if self.proc and self.proc.returncode is None and \
                (self.spawned_model, self.spawned_effort) == (s.get("model"), s.get("effort")):
            return
        await self.close()
        args = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                "--include-partial-messages", "--permission-prompt-tool", "stdio"]
        if s.get("model") and s["model"] != "default":
            args += ["--model", s["model"]]
        if s.get("effort"):
            args += ["--effort", s["effort"]]
        mode = s.get("permission_mode") or "bypassPermissions"
        args += ["--permission-mode", mode]
        if s.get("native_id"):
            args += ["--resume", s["native_id"]]
        elif s.get("fork_from"):
            args += ["--resume", s["fork_from"], "--fork-session"]
        if s.get("mode") == "chat":
            args += ["--append-system-prompt", CARDS_PROMPT]
        cwd = s.get("cwd") or os.path.expanduser("~")
        os.makedirs(cwd, exist_ok=True)
        self.proc = await _spawn(args, cwd)
        self.spawned_model, self.spawned_effort = s.get("model"), s.get("effort")
        self.reader = asyncio.create_task(self._read())
        asyncio.create_task(self._drain_stderr(self.proc))
        log.info("claude session %s started (pid %s, model %s, effort %s, mode %s)", s["id"], self.proc.pid,
                 s.get("model"), s.get("effort"), mode)

    async def _drain_stderr(self, proc):
        while True:
            line = await proc.stderr.readline()
            if not line:
                return
            log.debug("claude stderr: %s", line.decode(errors="replace").rstrip())

    async def _write(self, obj: dict):
        if not self.proc or self.proc.returncode is not None:
            raise RuntimeError("Claude Code isn't running")
        self.proc.stdin.write((json.dumps(obj) + "\n").encode())
        await self.proc.stdin.drain()

    async def close(self):
        if self.proc and self.proc.returncode is None:
            try:
                self.proc.stdin.close()
                await asyncio.wait_for(self.proc.wait(), 3)
            except Exception:
                self.proc.kill()
        if self.reader:
            self.reader.cancel()
        self.proc = None

    # -- commands from the phone ------------------------------------------------------------------------------
    async def warm(self):
        """Starts the CLI before the first message (the user is still typing): the reply starts instantly."""
        try:
            await self._ensure()
        except Exception as exc:
            log.warning("claude warm-up failed: %s", exc)

    async def send(self, text: str, attachments: list[dict]):
        await self._ensure()
        content = []
        notes = []
        for a in attachments:
            path, mime = a["path"], a.get("mime") or ""
            if mime.startswith("image/") and os.path.getsize(path) < 20 << 20:
                with open(path, "rb") as f:
                    content.append({"type": "image", "source": {"type": "base64", "media_type": mime,
                                                                 "data": base64.b64encode(f.read()).decode()}})
            else:
                notes.append(f"Attached file: {path}")
        body = "\n".join(notes + [text]) if notes else text
        content.append({"type": "text", "text": body})
        self.running = True
        self.turn_started = time.time()
        await self.emit({"type": "turn.start"})
        await self.emit({"type": "status", "state": "requesting"})
        await self._write({"type": "user", "message": {"role": "user", "content": content},
                           "parent_tool_use_id": None, "session_id": self.session.get("native_id") or "default"})

    async def interrupt(self):
        if self.proc and self.proc.returncode is None and self.running:
            await self._write({"type": "control_request", "request_id": uuid.uuid4().hex,
                               "request": {"subtype": "interrupt"}})

    async def resolve_permission(self, pid: str, allow: bool, message: str | None = None):
        request_id = self.pending_permissions.pop(pid, None)
        if not request_id:
            return
        tool = self.tools.get(pid, {})
        if allow:
            response = {"behavior": "allow", "updatedInput": tool.get("input") or {}}
        else:
            response = {"behavior": "deny", "message": message or "The user denied this from Linkup."}
        await self._write({"type": "control_response",
                           "response": {"subtype": "success", "request_id": request_id, "response": response}})
        await self.emit({"type": "permission.resolved", "id": pid, "allow": allow})

    async def set_mode(self, mode: str):
        self.session["permission_mode"] = mode
        if self.proc and self.proc.returncode is None:
            await self._write({"type": "control_request", "request_id": uuid.uuid4().hex,
                               "request": {"subtype": "set_permission_mode", "mode": mode}})

    # -- CLI output -> normalized events ----------------------------------------------------------------------
    async def _read(self):
        proc = self.proc
        try:
            while True:
                line = await proc.stdout.readline()
                if not line:
                    break
                try:
                    msg = json.loads(line)
                except ValueError:
                    continue
                try:
                    await self._handle(msg)
                except Exception as exc:
                    log.exception("claude event handling failed: %s", exc)
        finally:
            code = await proc.wait()
            if self.running:
                self.running = False
                await self.emit({"type": "turn.end", "stopReason": "exited", "isError": code != 0,
                                 "durationMs": int((time.time() - (self.turn_started or time.time())) * 1000)})
                await self.emit({"type": "status", "state": "error" if code else "idle",
                                 "detail": f"Claude Code exited ({code})" if code else None})

    def _key(self, msg: dict, index) -> str:
        return f"{msg.get('parent_tool_use_id') or ''}:{index}"

    async def _handle(self, msg: dict):
        t = msg.get("type")
        parent = msg.get("parent_tool_use_id")
        if t == "system":
            sub = msg.get("subtype")
            if sub == "init":
                if msg.get("session_id") and msg["session_id"] != self.session.get("native_id"):
                    self.session["native_id"] = msg["session_id"]
                    self.agent.store.update_session(self.session["id"], native_id=msg["session_id"])
                await self.emit({"type": "notice", "kind": "init", "model": msg.get("model"),
                                 "cwd": msg.get("cwd"), "permissionMode": msg.get("permissionMode")})
            elif sub == "status" and msg.get("status"):
                await self.emit({"type": "status", "state": "requesting" if msg["status"] == "requesting" else "running"})
            elif sub == "compact_boundary":
                await self.emit({"type": "notice", "text": "Conversation compacted to save context"})
            return
        if t == "stream_event":
            await self._stream(msg["event"], msg, parent)
            return
        if t == "assistant":
            for block in msg.get("message", {}).get("content", []):
                if block.get("type") == "tool_use":
                    self.tools[block["id"]] = {"name": block["name"], "input": block.get("input") or {}}
                    await self.emit({"type": "tool.update", "id": block["id"], "name": block["name"],
                                     "input": block.get("input") or {}, "parent": parent})
            return
        if t == "user":
            content = msg.get("message", {}).get("content")
            if isinstance(content, list):
                for block in content:
                    if block.get("type") == "tool_result":
                        await self._tool_result(block, parent)
            return
        if t == "rate_limit_event":
            info = msg.get("rate_limit_info", {})
            windows = info.get("unifiedWindows") or {}
            rl = {"type": "ratelimit", "status": info.get("status"),
                  "fiveHour": windows.get("five_hour"), "sevenDay": windows.get("seven_day"),
                  "resetsAt": info.get("resetsAt"), "limitType": info.get("rateLimitType")}
            self.agent.ratelimit = {**rl, "at": time.time()}
            await self.emit(rl)
            return
        if t == "result":
            self.running = False
            usage = msg.get("usage") or {}
            u = {"type": "usage", "inputTokens": usage.get("input_tokens", 0),
                 "outputTokens": usage.get("output_tokens", 0),
                 "cacheRead": usage.get("cache_read_input_tokens", 0),
                 "cacheWrite": usage.get("cache_creation_input_tokens", 0),
                 "costUsd": msg.get("total_cost_usd")}
            await self.emit(u)
            await self.emit({"type": "turn.end", "stopReason": msg.get("stop_reason") or msg.get("subtype"),
                             "durationMs": msg.get("duration_ms"), "costUsd": msg.get("total_cost_usd"),
                             "isError": bool(msg.get("is_error")), "numTurns": msg.get("num_turns")})
            await self.emit({"type": "status", "state": "idle"})
            return
        if t == "control_request":
            req = msg.get("request", {})
            if req.get("subtype") == "can_use_tool":
                pid = req.get("tool_use_id") or uuid.uuid4().hex
                self.pending_permissions[pid] = msg["request_id"]
                self.tools.setdefault(pid, {"name": req.get("tool_name"), "input": req.get("input") or {}})
                self.tools[pid]["input"] = req.get("input") or {}
                await self.emit({"type": "permission.request", "id": pid, "tool": req.get("tool_name"),
                                 "input": req.get("input") or {}, "reason": req.get("decision_reason")})
            return

    async def _stream(self, ev: dict, msg: dict, parent):
        et = ev.get("type")
        if et == "content_block_start":
            block = ev.get("content_block", {})
            key = self._key(msg, ev.get("index"))
            kind = block.get("type")
            bid = block.get("id") or uuid.uuid4().hex[:12]
            self.blocks[key], self.block_kind[key] = bid, kind
            if kind in ("thinking", "redacted_thinking"):
                await self.emit({"type": "thinking.start", "block": bid, "parent": parent})
            elif kind == "text":
                await self.emit({"type": "text.start", "block": bid, "parent": parent})
            elif kind in ("tool_use", "server_tool_use"):
                self.tools[bid] = {"name": block.get("name"), "input": {}}
                await self.emit({"type": "tool.start", "id": bid, "name": block.get("name"), "input": {},
                                 "parent": parent})
        elif et == "content_block_delta":
            key = self._key(msg, ev.get("index"))
            bid = self.blocks.get(key)
            delta = ev.get("delta", {})
            dt = delta.get("type")
            if dt == "text_delta" and delta.get("text"):
                await self.emit({"type": "text.delta", "block": bid, "text": delta["text"], "parent": parent})
            elif dt == "thinking_delta" and delta.get("thinking"):
                await self.emit({"type": "thinking.delta", "block": bid, "text": delta["thinking"], "parent": parent})
            elif dt == "input_json_delta" and delta.get("partial_json"):
                await self.emit({"type": "tool.input", "id": bid, "partial": delta["partial_json"]})
        elif et == "content_block_stop":
            key = self._key(msg, ev.get("index"))
            kind = self.block_kind.get(key)
            bid = self.blocks.get(key)
            if kind in ("thinking", "redacted_thinking"):
                await self.emit({"type": "thinking.end", "block": bid, "parent": parent})
            elif kind == "text":
                await self.emit({"type": "text.end", "block": bid, "parent": parent})
        elif et == "message_start":
            await self.emit({"type": "status", "state": "running"})

    async def _tool_result(self, block: dict, parent):
        tid = block.get("tool_use_id")
        tool = self.tools.get(tid, {})
        raw = block.get("content")
        texts, images = [], []
        if isinstance(raw, str):
            texts.append(raw)
        elif isinstance(raw, list):
            for part in raw:
                if part.get("type") == "text":
                    texts.append(part.get("text", ""))
                elif part.get("type") == "image" and part.get("source", {}).get("type") == "base64":
                    images.append(self._save_image(part["source"]))
        output = "\n".join(texts)
        await self.emit({"type": "tool.end", "id": tid, "output": output[:60000], "truncated": len(output) > 60000,
                         "isError": bool(block.get("is_error")), "images": images, "parent": parent})
        # Files the tool wrote or mentioned become artifacts / images the phone can open.
        candidates = []
        if tool.get("name") in WRITE_TOOLS:
            path = (tool.get("input") or {}).get("file_path") or (tool.get("input") or {}).get("notebook_path")
            if path and os.path.isfile(path):
                candidates.append(path)
        candidates += [p for p in paths_in(output) if p not in candidates]
        for path in candidates:
            from .base import kind_of
            if kind_of(path) != "file" or tool.get("name") in WRITE_TOOLS:
                await self.emit({**self.agent.media.artifact(path), "tool": tid, "parent": parent})

    def _save_image(self, source: dict) -> str:
        ext = (source.get("media_type") or "image/png").split("/")[-1]
        folder = os.path.join(os.path.expanduser("~/.linkup/media"))
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, f"{uuid.uuid4().hex}.{ext}")
        with open(path, "wb") as f:
            f.write(base64.b64decode(source.get("data", "")))
        return self.agent.media.url(path)
