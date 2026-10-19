"""Pi agent adapter: one long-lived `pi --mode rpc` process per session.

Protocol framing: strict JSONL (split on \\n only).
Features: live model list with reasoning effort levels, streaming text and thinking,
tool execution (lowercase read, bash, edit, write, grep, find, ls), image input/output,
artifact detection, usage events, session resume and fork.
"""
from __future__ import annotations

import asyncio
import base64
import collections
import json
import logging
import os
import shutil
import time
import uuid

from .base import Media, kind_of, paths_in

log = logging.getLogger("linkup.pi")


def pi_bin() -> str:
    override = os.environ.get("LINKUP_PI")
    if override:
        return override
    default = os.path.expanduser("~/.local/bin/pi")
    if os.path.exists(default):
        return default
    return "pi"


def pi_env() -> dict[str, str]:
    env = dict(os.environ)
    local_bin = os.path.expanduser("~/.local/bin")
    current_path = env.get("PATH", "")
    paths = [local_bin, "/usr/bin", "/usr/local/bin"]
    env["PATH"] = ":".join(paths) + (":" + current_path if current_path else "")
    return env


async def _spawn(args: list[str], cwd: str) -> asyncio.subprocess.Process:
    bin_path = pi_bin()
    env = pi_env()
    return await asyncio.create_subprocess_exec(
        bin_path, *args, cwd=cwd,
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        limit=64 << 20,
        env=env,
    )


class PiAgent:
    id = "pi"
    name = "Pi"

    def __init__(self, store, media: Media):
        self.store = store
        self.media = media
        self._catalog: dict | None = None
        self._catalog_at = 0.0

    async def catalog(self, force: bool = False) -> dict:
        if self._catalog and not force and time.time() - self._catalog_at < 600:
            return self._catalog

        bin_path = pi_bin()
        env = pi_env()
        if not os.path.exists(bin_path) and not shutil.which(bin_path, path=env.get("PATH")):
            return {"id": self.id, "name": self.name, "available": False, "error": f"Pi binary not found at {bin_path}"}

        version = None
        try:
            proc_ver = await asyncio.create_subprocess_exec(
                bin_path, "--version",
                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE, env=env
            )
            v_out, _ = await asyncio.wait_for(proc_ver.communicate(), timeout=5.0)
            if v_out:
                version = v_out.decode(errors="replace").strip().splitlines()[0]
        except Exception as exc:
            log.debug("pi --version failed: %s", exc)

        responses: dict[str, dict] = {}
        try:
            proc = await _spawn(["--mode", "rpc", "--no-session"], os.path.expanduser("~"))
            reqs = [
                {"id": "m", "type": "get_available_models"},
                {"id": "s", "type": "get_state"},
                {"id": "c", "type": "get_commands"},
            ]
            for r in reqs:
                proc.stdin.write((json.dumps(r) + "\n").encode())
            await proc.stdin.drain()

            while len(responses) < len(reqs):
                line = await asyncio.wait_for(proc.stdout.readline(), timeout=30.0)
                if not line:
                    break
                try:
                    msg = json.loads(line)
                except ValueError:
                    continue
                if msg.get("type") == "response" and msg.get("id") in ("m", "s", "c"):
                    responses[msg["id"]] = msg.get("data") or {}

            proc.kill()
            await proc.wait()
        except Exception as exc:
            log.error("pi catalog failed: %s", exc)
            return self._catalog or {"id": self.id, "name": self.name, "available": False, "error": str(exc)}

        raw_models = responses.get("m", {}).get("models", [])
        models = []
        for raw_m in raw_models:
            prov = raw_m.get("provider")
            mid = raw_m.get("id")
            fid = f"{prov}/{mid}" if prov else mid
            models.append({
                "id": fid,
                "name": raw_m.get("name") or mid,
                "description": prov,
                "efforts": ["off", "minimal", "low", "medium", "high", "xhigh"] if raw_m.get("reasoning") else [],
            })

        state_m = responses.get("s", {}).get("model") or {}
        state_prov = state_m.get("provider")
        state_mid = f"{state_prov}/{state_m.get('id')}" if state_prov else state_m.get("id")
        def_idx = next((i for i, m in enumerate(models) if m["id"] == state_mid), None)
        if def_idx is not None and def_idx > 0:
            models.insert(0, models.pop(def_idx))
        default_model = state_mid if def_idx is not None else (models[0]["id"] if models else None)

        kind_map = {"skill": "skill", "prompt": "prompt", "extension": "command"}
        cmds = []
        for rc in responses.get("c", {}).get("commands", []):
            name = rc.get("name")
            if name:
                cmds.append({
                    "name": name,
                    "description": rc.get("description") or "",
                    "kind": kind_map.get(rc.get("source"), "command"),
                })

        self._catalog = {
            "id": self.id,
            "name": self.name,
            "available": bool(models),
            "models": models,
            "defaultModel": default_model,
            "version": version,
            "commands": cmds,
            "supportsImages": True,
            "supportsInterrupt": True,
            "supportsPermissions": False,
        }
        self._catalog_at = time.time()
        return self._catalog

    def open(self, session: dict, emit) -> PiSession:
        return PiSession(self, session, emit)


class PiSession:
    def __init__(self, agent: PiAgent, session: dict, emit):
        self.agent = agent
        self.session = session
        self.emit = emit
        self.proc: asyncio.subprocess.Process | None = None
        self.reader: asyncio.Task | None = None
        self.stderr_reader: asyncio.Task | None = None
        self.stderr_lines: collections.deque[str] = collections.deque(maxlen=20)
        self.running = False
        self.turn_ended = False
        self.turn_started: float | None = None
        self.turn_cost_usd = 0.0
        self.current_model: str | None = None
        self.current_effort: str | None = None
        self.blocks: dict[int, str] = {}             # contentIndex -> block id
        self.tool_calls: dict[int, str] = {}         # contentIndex -> toolCallId
        self.tools: dict[str, dict] = {}             # toolCallId -> {name, input}
        self.turn_texts: list[str] = []
        self.first_event_seen = False
        self.interrupted = False
        self._pending_responses: dict[str, asyncio.Future] = {}

    @property
    def pid(self) -> int | None:
        return self.proc.pid if self.proc and self.proc.returncode is None else None

    async def _write(self, obj: dict):
        if not self.proc or self.proc.returncode is not None:
            raise RuntimeError("Pi isn't running")
        self.proc.stdin.write((json.dumps(obj) + "\n").encode())
        await self.proc.stdin.drain()

    async def _ensure(self):
        s = self.session
        if self.proc and self.proc.returncode is None:
            # Check model change
            target_model = s.get("model")
            if target_model and target_model != self.current_model and target_model != "default":
                provider, model_id = target_model.split("/", 1) if "/" in target_model else (None, target_model)
                if provider:
                    await self._write({"type": "set_model", "provider": provider, "modelId": model_id})
                    self.current_model = target_model
            # Check effort change
            target_effort = s.get("effort")
            if target_effort and target_effort != self.current_effort:
                await self._write({"type": "set_thinking_level", "level": target_effort})
                self.current_effort = target_effort
            return

        await self.close()

        session_dir = os.path.expanduser("~/.linkup/pi-sessions")
        os.makedirs(session_dir, exist_ok=True)

        args = ["--mode", "rpc"]
        if s.get("model") and s["model"] != "default":
            args += ["--model", s["model"]]
        if s.get("effort"):
            args += ["--thinking", s["effort"]]

        if s.get("native_id"):
            args += ["--session", s["native_id"]]
        elif s.get("fork_from"):
            args += ["--fork", s["fork_from"], "--session-dir", session_dir]
        else:
            args += ["--session-dir", session_dir]

        cwd = s.get("cwd") or os.path.expanduser("~")
        os.makedirs(cwd, exist_ok=True)

        self.stderr_lines.clear()
        self.proc = await _spawn(args, cwd)
        self.current_model = s.get("model")
        self.current_effort = s.get("effort")
        self.reader = asyncio.create_task(self._read())
        self.stderr_reader = asyncio.create_task(self._drain_stderr(self.proc))
        log.info("pi session %s started (pid %s, model %s, effort %s)",
                 s["id"], self.proc.pid, s.get("model"), s.get("effort"))

        await self._init_state()

    async def _init_state(self):
        req_id = f"init_{uuid.uuid4().hex[:8]}"
        fut = asyncio.get_running_loop().create_future()
        self._pending_responses[req_id] = fut
        try:
            await self._write({"id": req_id, "type": "get_state"})
            resp = await asyncio.wait_for(fut, timeout=10.0)
            data = (resp.get("data") or {}) if isinstance(resp, dict) else {}
            session_file = data.get("sessionFile")
            if session_file and session_file != self.session.get("native_id"):
                self.session["native_id"] = session_file
                self.agent.store.update_session(self.session["id"], native_id=session_file)
        except Exception as exc:
            log.warning("failed to fetch initial state for pi session %s: %s", self.session["id"], exc)
        finally:
            self._pending_responses.pop(req_id, None)

    async def _drain_stderr(self, proc: asyncio.subprocess.Process):
        while True:
            line = await proc.stderr.readline()
            if not line:
                return
            decoded = line.decode(errors="replace").rstrip()
            self.stderr_lines.append(decoded)
            log.debug("pi stderr: %s", decoded)

    async def close(self):
        if self.proc and self.proc.returncode is None:
            try:
                self.proc.stdin.close()
                await asyncio.wait_for(self.proc.wait(), timeout=3.0)
            except Exception:
                self.proc.kill()
        if self.reader:
            self.reader.cancel()
        if self.stderr_reader:
            self.stderr_reader.cancel()
        self.proc = None
        self.running = False

    async def interrupt(self):
        if self.proc and self.proc.returncode is None and self.running:
            self.interrupted = True
            try:
                await self._write({"type": "abort"})
            except Exception as exc:
                log.debug("abort write failed: %s", exc)

    async def resolve_permission(self, pid: str, allow: bool, message: str | None = None):
        pass

    async def set_mode(self, mode: str):
        pass

    async def send(self, text: str, attachments: list[dict]):
        await self._ensure()
        images = []
        notes = []
        for a in attachments:
            path = a.get("path")
            mime = a.get("mime") or ""
            if path and mime.startswith("image/") and os.path.isfile(path) and os.path.getsize(path) < 20 << 20:
                with open(path, "rb") as f:
                    b64 = base64.b64encode(f.read()).decode()
                images.append({"type": "image", "data": b64, "mimeType": mime})
            elif path:
                notes.append(f"Attached file: {path}")

        body = "\n".join(notes + [text]) if notes else text

        payload: dict = {"type": "prompt", "message": body}
        if images:
            payload["images"] = images
        if self.running:
            payload["streamingBehavior"] = "steer"

        self.blocks.clear()
        self.tool_calls.clear()
        self.turn_texts.clear()
        self.turn_cost_usd = 0.0
        self.running = True
        self.turn_ended = False
        self.interrupted = False
        self.first_event_seen = False
        self.turn_started = time.time()

        await self.emit({"type": "turn.start"})
        await self.emit({"type": "status", "state": "requesting"})

        await self._write(payload)

    def _save_image(self, b64_data: str, mime: str) -> str:
        ext = mime.split("/")[-1] if "/" in mime else "png"
        folder = os.path.expanduser("~/.linkup/media/pi")
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, f"{uuid.uuid4().hex}.{ext}")
        with open(path, "wb") as f:
            f.write(base64.b64decode(b64_data))
        return self.agent.media.url(path)

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
                    log.exception("pi event handling failed: %s", exc)
        finally:
            code = await proc.wait() if proc else None
            if self.running and not self.turn_ended:
                self.turn_ended = True
                self.running = False
                err_detail = " ".join(self.stderr_lines) if self.stderr_lines else f"exit code {code}"
                await self.emit({"type": "error", "message": f"Pi process died unexpectedly: {err_detail}"})
                await self.emit({
                    "type": "turn.end",
                    "stopReason": "exited",
                    "isError": True,
                    "durationMs": int((time.time() - (self.turn_started or time.time())) * 1000),
                })
                await self.emit({"type": "status", "state": "idle", "detail": f"Pi exited ({code})"})

    async def _handle(self, msg: dict):
        mtype = msg.get("type")

        # Emit status running on first agent event received during this turn
        if self.running and not self.first_event_seen and mtype != "response":
            self.first_event_seen = True
            await self.emit({"type": "status", "state": "running"})

        if mtype == "response":
            rid = msg.get("id")
            if rid in self._pending_responses:
                fut = self._pending_responses.get(rid)
                if fut and not fut.done():
                    fut.set_result(msg)
            if not msg.get("success"):
                err = msg.get("error") or "Pi command failed"
                log.warning("pi response failure: %s", err)
                if msg.get("command") == "prompt" and self.running and not self.turn_ended:
                    self.turn_ended = True
                    self.running = False
                    await self.emit({"type": "error", "message": str(err)})
                    await self.emit({"type": "turn.end", "stopReason": "error", "isError": True, "durationMs": 0})
                    await self.emit({"type": "status", "state": "idle"})
            return

        if mtype == "message_update":
            ev = msg.get("assistantMessageEvent") or {}
            et = ev.get("type")
            idx = ev.get("contentIndex", 0)

            if et == "text_start":
                bid = uuid.uuid4().hex[:12]
                self.blocks[idx] = bid
                await self.emit({"type": "text.start", "block": bid})
            elif et == "text_delta":
                bid = self.blocks.get(idx)
                if not bid:
                    bid = uuid.uuid4().hex[:12]
                    self.blocks[idx] = bid
                    await self.emit({"type": "text.start", "block": bid})
                delta = ev.get("delta") or ""
                if delta:
                    self.turn_texts.append(delta)
                    await self.emit({"type": "text.delta", "block": bid, "text": delta})
            elif et == "text_end":
                bid = self.blocks.get(idx)
                if bid:
                    await self.emit({"type": "text.end", "block": bid})
                    self.blocks.pop(idx, None)
            elif et == "thinking_start":
                bid = uuid.uuid4().hex[:12]
                self.blocks[idx] = bid
                await self.emit({"type": "thinking.start", "block": bid})
            elif et == "thinking_delta":
                bid = self.blocks.get(idx)
                if not bid:
                    bid = uuid.uuid4().hex[:12]
                    self.blocks[idx] = bid
                    await self.emit({"type": "thinking.start", "block": bid})
                delta = ev.get("delta") or ""
                if delta:
                    await self.emit({"type": "thinking.delta", "block": bid, "text": delta})
            elif et == "thinking_end":
                bid = self.blocks.get(idx)
                if bid:
                    await self.emit({"type": "thinking.end", "block": bid})
                    self.blocks.pop(idx, None)
            elif et == "toolcall_start":
                tc = ev.get("toolCall")
                if not tc:
                    partial = ev.get("partial") or {}
                    c_list = partial.get("content") or []
                    if isinstance(c_list, list) and idx < len(c_list):
                        tc = c_list[idx]
                tc = tc or {}
                tid = tc.get("id") or uuid.uuid4().hex[:12]
                tname = tc.get("name") or "tool"
                tinput = tc.get("arguments") or {}
                self.tool_calls[idx] = tid
                self.tools[tid] = {"name": tname, "input": tinput}
                await self.emit({"type": "tool.start", "id": tid, "name": tname, "input": tinput})
            elif et == "toolcall_delta":
                tid = self.tool_calls.get(idx)
                delta = ev.get("delta") or ""
                if tid and delta:
                    await self.emit({"type": "tool.input", "id": tid, "partial": delta})
            elif et == "toolcall_end":
                tc = ev.get("toolCall") or {}
                tid = tc.get("id") or self.tool_calls.get(idx)
                tname = tc.get("name") or self.tools.get(tid, {}).get("name") or "tool"
                tinput = tc.get("arguments") or {}
                if tid:
                    self.tools[tid] = {"name": tname, "input": tinput}
                    await self.emit({"type": "tool.update", "id": tid, "name": tname, "input": tinput})
            elif et == "error":
                err = ev.get("error") or ev.get("message")
                if err:
                    await self.emit({"type": "error", "message": str(err)})
            return

        if mtype == "tool_execution_start":
            await self.emit({"type": "status", "state": "running"})
            return

        if mtype == "tool_execution_update":
            return

        if mtype == "tool_execution_end":
            tid = msg.get("toolCallId")
            tool = self.tools.get(tid, {})
            result = msg.get("result") or {}
            content = result.get("content") or []
            is_error = bool(msg.get("isError"))
            texts = [p.get("text", "") for p in content if isinstance(p, dict) and p.get("type") == "text"]
            output = "".join(texts)
            images = []
            for p in content:
                if isinstance(p, dict) and p.get("type") == "image":
                    data = p.get("data")
                    mime = p.get("mimeType") or "image/png"
                    if data:
                        url = self._save_image(data, mime)
                        if url:
                            images.append(url)
            await self.emit({
                "type": "tool.end",
                "id": tid,
                "output": output[:60000],
                "isError": is_error,
                "images": images,
            })

            # Detect artifacts from tool results and file writes
            candidates = []
            if tool.get("name") in ("write", "edit", "Write", "Edit"):
                t_input = tool.get("input") or {}
                path = t_input.get("path") or t_input.get("filePath") or t_input.get("file_path")
                if path:
                    if not os.path.isabs(path) and self.session.get("cwd"):
                        path = os.path.join(self.session["cwd"], path)
                    if os.path.isfile(path):
                        candidates.append(path)
            candidates += [p for p in paths_in(output) if p not in candidates]
            for path in candidates:
                if kind_of(path) != "file" or tool.get("name") in ("write", "edit", "Write", "Edit"):
                    art = self.agent.media.artifact(path)
                    if art:
                        await self.emit({**art, "tool": tid})
            return

        if mtype == "message_end":
            message = msg.get("message") or {}
            if message.get("role") == "assistant":
                usage = message.get("usage") or {}
                cost = usage.get("cost") or {}
                cost_usd = float(cost.get("total") or 0.0)
                self.turn_cost_usd += cost_usd
                inp = usage.get("input", 0)
                out = usage.get("output", 0)
                cread = usage.get("cacheRead", 0)
                cwrite = usage.get("cacheWrite", 0)
                ctx = usage.get("totalTokens", inp + cread)
                await self.emit({
                    "type": "usage",
                    "inputTokens": inp,
                    "outputTokens": out,
                    "cacheRead": cread,
                    "cacheWrite": cwrite,
                    "costUsd": cost_usd,
                    "contextTokens": ctx,
                })
                if message.get("stopReason") == "error":
                    err_msg = message.get("errorMessage") or "Assistant error"
                    await self.emit({"type": "error", "message": str(err_msg)})
            return

        if mtype == "agent_end":
            if not self.turn_ended:
                self.turn_ended = True
                self.running = False
                messages = msg.get("messages", [])
                last_assistant = next((m for m in reversed(messages) if m.get("role") == "assistant"), {})
                if last_assistant.get("stopReason") == "error":
                    err_msg = last_assistant.get("errorMessage") or "Assistant error"
                    await self.emit({"type": "error", "message": str(err_msg)})

                stop_reason = "interrupted" if self.interrupted else (last_assistant.get("stopReason") or "stop")
                if stop_reason == "aborted":
                    stop_reason = "interrupted"
                is_error = stop_reason in ("error", "aborted")
                duration_ms = int((time.time() - (self.turn_started or time.time())) * 1000)

                final_content = last_assistant.get("content") or []
                if isinstance(final_content, list):
                    final_text = "".join(p.get("text", "") for p in final_content
                                         if isinstance(p, dict) and p.get("type") == "text")
                else:
                    final_text = str(final_content)
                if not final_text:
                    final_text = "".join(self.turn_texts)

                await self.emit({
                    "type": "turn.end",
                    "stopReason": stop_reason,
                    "durationMs": duration_ms,
                    "costUsd": self.turn_cost_usd,
                    "isError": is_error,
                    "text": final_text,
                })
                await self.emit({"type": "status", "state": "idle"})
            return

        if mtype == "auto_retry_start":
            attempt = msg.get("attempt", 1)
            max_attempts = msg.get("maxAttempts", 3)
            err_msg = msg.get("errorMessage", "")
            await self.emit({"type": "notice", "text": f"Retrying ({attempt}/{max_attempts}): {err_msg}"})
            return

        if mtype == "auto_retry_end":
            if msg.get("success"):
                await self.emit({"type": "notice", "text": "Retry succeeded"})
            else:
                await self.emit({"type": "notice", "text": f"Retry failed: {msg.get('finalError', '')}"})
            return

        if mtype == "compaction_start":
            await self.emit({"type": "notice", "text": "Compacting conversation context..."})
            return

        if mtype == "compaction_end":
            await self.emit({"type": "notice", "text": "Conversation compacted to save context"})
            return

        if mtype == "extension_error":
            err = msg.get("error") or "Unknown error"
            await self.emit({"type": "notice", "text": f"Extension error: {err}"})
            return

        if mtype == "extension_ui_request":
            req_id = msg.get("id")
            method = msg.get("method")
            if method in ("select", "confirm", "input", "editor"):
                log.info("pi extension_ui_request %s (%s) cancelled", req_id, method)
                try:
                    await self._write({"type": "extension_ui_response", "id": req_id, "cancelled": True})
                except Exception as exc:
                    log.warning("failed to answer extension_ui_request %s: %s", req_id, exc)
            elif method == "notify" and msg.get("message"):
                await self.emit({"type": "notice", "text": str(msg["message"])})
            return
