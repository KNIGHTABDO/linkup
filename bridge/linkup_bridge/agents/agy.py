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

    async def send(self, text: str, attachments: list[dict]):
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
        asyncio.create_task(self._read(self.proc, started))

    async def _read(self, proc, started: float):
        open_text: set[int] = set()
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
                    await self._step(msg.get("step_update") or {}, open_text)
                elif ev == "result":
                    result_seen = True
                    r = msg.get("result") or {}
                    for idx in sorted(open_text):
                        await self.emit({"type": "text.end", "block": f"s{idx}"})
                    open_text.clear()
                    u = r.get("usage") or {}
                    await self.emit({"type": "usage", "inputTokens": u.get("input_tokens", 0),
                                     "outputTokens": u.get("output_tokens", 0),
                                     "thinkingTokens": u.get("thinking_tokens", 0),
                                     "cacheRead": u.get("cache_read_tokens", 0)})
                    ok = (r.get("status") or "").upper() == "SUCCESS"
                    await self.emit({"type": "turn.end", "stopReason": r.get("status"), "isError": not ok,
                                     "durationMs": int((r.get("duration_seconds") or (time.time() - started)) * 1000),
                                     "text": None if ok else r.get("response")})
                elif ev in ("error", "failed"):
                    errors.append(json.dumps(msg)[:500])
        finally:
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

    async def _step(self, s: dict, open_text: set[int]):
        kind = s.get("step_type")
        idx = s.get("step_index", 0)
        state = (s.get("state") or "").upper()
        if kind == "agent_response":
            block = f"s{idx}"
            thinking = s.get("thinking_delta") or s.get("thinking")
            if thinking:
                await self.emit({"type": "thinking.delta", "block": f"t{idx}", "text": thinking})
            if s.get("text_delta"):
                if idx not in open_text:
                    open_text.add(idx)
                    await self.emit({"type": "text.start", "block": block})
                await self.emit({"type": "text.delta", "block": block, "text": s["text_delta"]})
            if state == "DONE" and idx in open_text:
                open_text.discard(idx)
                await self.emit({"type": "text.end", "block": block})
            if state == "DONE" and s.get("usage"):
                await self.emit({"type": "status", "state": "running"})
        elif kind == "tool":
            info = s.get("tool_info") or {}
            tid = f"{self.session.get('native_id')}:{idx}"
            name = s.get("tool_name") or info.get("name") or "tool"
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

    async def interrupt(self):
        if self.proc and self.proc.returncode is None:
            self.proc.terminate()

    async def resolve_permission(self, pid, allow, message=None):
        return

    async def set_mode(self, mode):
        return

    async def close(self):
        await self.interrupt()
