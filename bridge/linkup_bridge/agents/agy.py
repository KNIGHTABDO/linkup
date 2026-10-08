"""Antigravity through the signed-in `agy` CLI: one `agy -p … --output-format stream-json` run per turn, continued
with `--conversation <id>` (its step_update events carry text deltas, tool calls with parameters and output, usage)."""
from __future__ import annotations

import asyncio
import json
import logging
import os
import time

log = logging.getLogger("linkup.agy")
AGY = os.environ.get("LINKUP_AGY", "agy")


class AgyAgent:
    id = "agy"
    name = "Antigravity"

    def __init__(self, store, media):
        self.store = store
        self.media = media
        self._catalog = None
        self._catalog_at = 0.0

    async def catalog(self, force: bool = False) -> dict:
        if self._catalog and not force and time.time() - self._catalog_at < 600:
            return self._catalog
        try:
            proc = await asyncio.create_subprocess_exec(AGY, "models", stdout=asyncio.subprocess.PIPE,
                                                        stderr=asyncio.subprocess.STDOUT)
            out, _ = await asyncio.wait_for(proc.communicate(), 60)
            models = []
            for line in out.decode(errors="replace").splitlines():
                if "\t" in line:
                    mid, name = line.split("\t", 1)
                    models.append({"id": mid.strip(), "name": name.strip(), "description": None, "efforts": []})
            agents = []
            proc = await asyncio.create_subprocess_exec(AGY, "agents", stdout=asyncio.subprocess.PIPE,
                                                        stderr=asyncio.subprocess.STDOUT)
            out, _ = await asyncio.wait_for(proc.communicate(), 60)
            for line in out.decode(errors="replace").splitlines():
                line = line.strip()
                if line and not line.lower().startswith(("fetching", "available", "usage")):
                    agents.append(line)
        except Exception as exc:
            log.error("agy catalog failed: %s", exc)
            return self._catalog or {"id": self.id, "name": self.name, "available": False, "error": str(exc)}
        default = next((m["id"] for m in models if m["id"] == "gemini-3.8-flash-high"), models[0]["id"] if models else None)
        self._catalog = {"id": self.id, "name": self.name, "available": bool(models), "models": models,
                         "defaultModel": default, "agents": agents[:20], "supportsImages": False,
                         "supportsInterrupt": True, "supportsPermissions": False}
        self._catalog_at = time.time()
        return self._catalog

    def open(self, session: dict, emit) -> "AgySession":
        return AgySession(self, session, emit)


class AgySession:
    def __init__(self, agent: AgyAgent, session: dict, emit):
        self.agent = agent
        self.session = session
        self.emit = emit
        self.proc = None
        self.running = False
        self.turn = 0

    async def send(self, text: str, attachments: list[dict]):
        self.turn += 1
        turn = self.turn
        notes = [f"Attached file: {a['path']}" for a in attachments]
        prompt = "\n".join(notes + [text]) if notes else text
        args = ["-p", prompt, "--output-format", "stream-json", "--dangerously-skip-permissions", "--print-timeout", "0"]
        if self.session.get("model"):
            args += ["--model", self.session["model"]]
        if self.session.get("native_id"):
            args += ["--conversation", self.session["native_id"]]
        cwd = self.session.get("cwd") or os.path.expanduser("~")
        self.running = True
        started = time.time()
        await self.emit({"type": "turn.start"})
        await self.emit({"type": "status", "state": "requesting"})
        self.proc = await asyncio.create_subprocess_exec(AGY, *args, cwd=cwd, stdout=asyncio.subprocess.PIPE,
                                                         stderr=asyncio.subprocess.PIPE, limit=64 << 20)
        asyncio.create_task(self._read(self.proc, started, turn))

    async def _read(self, proc, started: float, turn: int):
        open_text: set[int] = set()
        open_thinking: set[int] = set()
        result_seen = False
        errors = []
        try:
            while True:
                line = await proc.stdout.readline()
                if not line:
                    break
                try:
                    msg = json.loads(line)
                except ValueError:
                    continue
                ev = msg.get("event")
                if ev == "init":
                    cid = msg.get("conversation_id")
                    if cid and cid != self.session.get("native_id"):
                        self.session["native_id"] = cid
                        self.agent.store.update_session(self.session["id"], native_id=cid)
                    await self.emit({"type": "notice", "kind": "init",
                                     "model": (msg.get("init") or {}).get("model"), "cwd": (msg.get("init") or {}).get("cwd")})
                elif ev == "step_update":
                    await self._step(msg.get("step_update") or {}, open_text, open_thinking, turn)
                elif ev == "result":
                    result_seen = True
                    r = msg.get("result") or {}
                    for idx in sorted(open_thinking):
                        await self.emit({"type": "thinking.end", "block": f"t{turn}-th{idx}"})
                    open_thinking.clear()
                    for idx in sorted(open_text):
                        await self.emit({"type": "text.end", "block": f"t{turn}-s{idx}"})
                    open_text.clear()
                    u = r.get("usage") or {}
                    await self.emit({"type": "usage",
                                     "inputTokens": u.get("input_tokens", 0) or u.get("prompt_tokens", 0),
                                     "outputTokens": u.get("output_tokens", 0) or u.get("candidates_tokens", 0) or u.get("completion_tokens", 0),
                                     "thinkingTokens": u.get("thinking_tokens", 0),
                                     "cacheRead": u.get("cache_read_tokens", 0) or u.get("cached_content_token_count", 0)})
                    ok = (r.get("status") or "").upper() == "SUCCESS"
                    if not ok and r.get("error"):
                        await self.emit({"type": "error", "message": str(r["error"])})
                    await self.emit({"type": "turn.end", "stopReason": r.get("status"), "isError": not ok,
                                     "durationMs": int((r.get("duration_seconds") or (time.time() - started)) * 1000),
                                     "text": None if ok else (r.get("response") or r.get("error"))})
                elif ev in ("error", "failed"):
                    errors.append(json.dumps(msg)[:500])
        finally:
            for idx in sorted(open_thinking):
                await self.emit({"type": "thinking.end", "block": f"t{turn}-th{idx}"})
            open_thinking.clear()
            for idx in sorted(open_text):
                await self.emit({"type": "text.end", "block": f"t{turn}-s{idx}"})
            open_text.clear()
            stderr = (await proc.stderr.read()).decode(errors="replace").strip()
            code = await proc.wait()
            self.running = False
            if not result_seen:
                detail = (errors[-1] if errors else stderr[-800:]) or f"agy exited ({code})"
                if code not in (0, -15, -9):
                    await self.emit({"type": "error", "message": detail})
                await self.emit({"type": "turn.end", "stopReason": "interrupted" if code in (-15, -9) else "exited",
                                 "isError": code not in (0, -15, -9),
                                 "durationMs": int((time.time() - started) * 1000)})
            await self.emit({"type": "status", "state": "idle"})

    async def _step(self, s: dict, open_text: set[int], open_thinking: set[int], turn: int):
        kind = s.get("step_type")
        idx = s.get("step_index", 0)
        state = (s.get("state") or "").upper()
        if kind == "agent_response":
            block = f"t{turn}-s{idx}"
            th_block = f"t{turn}-th{idx}"
            thinking = s.get("thinking_delta") or s.get("thinking")
            if thinking:
                if idx not in open_thinking:
                    open_thinking.add(idx)
                    await self.emit({"type": "thinking.start", "block": th_block})
                await self.emit({"type": "thinking.delta", "block": th_block, "text": thinking})
            if s.get("text_delta"):
                if idx in open_thinking:
                    open_thinking.discard(idx)
                    await self.emit({"type": "thinking.end", "block": th_block})
                if idx not in open_text:
                    open_text.add(idx)
                    await self.emit({"type": "text.start", "block": block})
                await self.emit({"type": "text.delta", "block": block, "text": s["text_delta"]})
            if state in ("DONE", "COMPLETED", "FINISHED"):
                if idx in open_thinking:
                    open_thinking.discard(idx)
                    await self.emit({"type": "thinking.end", "block": th_block})
                if idx in open_text:
                    open_text.discard(idx)
                    await self.emit({"type": "text.end", "block": block})
            if s.get("usage"):
                u = s["usage"]
                await self.emit({"type": "usage",
                                 "inputTokens": u.get("input_tokens", 0) or u.get("prompt_tokens", 0),
                                 "outputTokens": u.get("output_tokens", 0) or u.get("candidates_tokens", 0) or u.get("completion_tokens", 0),
                                 "thinkingTokens": u.get("thinking_tokens", 0),
                                 "cacheRead": u.get("cache_read_tokens", 0) or u.get("cached_content_token_count", 0)})
            elif state in ("ACTIVE", "RUNNING"):
                await self.emit({"type": "status", "state": "running"})
        elif kind in ("user_input", "error_message"):
            return  # agy reports the error text in its final result
        else:
            # "tool" and any other step kind (sub-agents, browser, image generation…) render as a tool card.
            info = s.get("tool_info") or {}
            tid = f"{self.session.get('native_id') or self.session['id']}:t{turn}-{idx}"
            name = s.get("tool_name") or info.get("name") or (kind if kind and kind != "tool" else "tool")
            if kind != "tool" and not info:
                info = {k: v for k, v in s.items() if k not in ("conversation_id", "step_index", "state", "step_type",
                                                                "duration_seconds", "usage")}
                info = {"parameters": info} if info else {}
            if state == "ACTIVE":
                await self.emit({"type": "tool.start", "id": tid, "name": name, "input": info.get("parameters") or {}})
                await self.emit({"type": "status", "state": "running"})
            elif state in ("DONE", "ERROR", "FAILED", "CANCELED", "CANCELLED"):
                output = info.get("output")
                if not isinstance(output, str):
                    output = json.dumps(output, indent=1) if output is not None else ""
                await self.emit({"type": "tool.update", "id": tid, "name": name, "input": info.get("parameters") or {}})
                await self.emit({"type": "tool.end", "id": tid, "output": output[:60000], "isError": state != "DONE",
                                 "images": []})
            if s.get("usage"):
                u = s["usage"]
                await self.emit({"type": "usage",
                                 "inputTokens": u.get("input_tokens", 0) or u.get("prompt_tokens", 0),
                                 "outputTokens": u.get("output_tokens", 0) or u.get("candidates_tokens", 0) or u.get("completion_tokens", 0),
                                 "thinkingTokens": u.get("thinking_tokens", 0),
                                 "cacheRead": u.get("cache_read_tokens", 0) or u.get("cached_content_token_count", 0)})

    async def interrupt(self):
        if self.proc and self.proc.returncode is None:
            self.proc.terminate()

    async def resolve_permission(self, pid, allow, message=None):
        return

    async def set_mode(self, mode):
        return

    async def close(self):
        await self.interrupt()
