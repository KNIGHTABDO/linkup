"""Hermes Agent through its local API server (127.0.0.1:8642, key from ~/.hermes/.env): durable runs streamed as
server-sent events (tool.started / tool.completed / message.delta / reasoning.available / run.completed)."""
from __future__ import annotations

import asyncio
import json
import logging
import os
import time
import uuid

import aiohttp

log = logging.getLogger("linkup.hermes")


def _env() -> dict:
    out = {}
    try:
        with open(os.path.expanduser("~/.hermes/.env")) as f:
            for line in f:
                if "=" in line and not line.lstrip().startswith("#"):
                    k, v = line.strip().split("=", 1)
                    out[k] = v.strip().strip('"')
    except OSError:
        pass
    return out


class HermesAgent:
    id = "hermes"
    name = "Hermes"

    def __init__(self, store, media):
        self.store = store
        self.media = media
        env = _env()
        host = env.get("API_SERVER_HOST", "127.0.0.1")
        self.base = os.environ.get("LINKUP_HERMES_URL", f"http://{host}:{env.get('API_SERVER_PORT', '8642')}")
        self.key = os.environ.get("LINKUP_HERMES_KEY", env.get("API_SERVER_KEY", ""))
        self._catalog = None
        self._catalog_at = 0.0

    @property
    def headers(self):
        return {"Authorization": f"Bearer {self.key}", "Content-Type": "application/json"}

    async def catalog(self, force: bool = False) -> dict:
        if self._catalog and not force and time.time() - self._catalog_at < 120:
            return self._catalog
        try:
            async with aiohttp.ClientSession() as http:
                async with http.get(f"{self.base}/health", timeout=aiohttp.ClientTimeout(total=6)) as r:
                    health = await r.json(content_type=None)
                async with http.get(f"{self.base}/v1/models", headers=self.headers,
                                    timeout=aiohttp.ClientTimeout(total=6)) as r:
                    data = await r.json(content_type=None)
            models = [{"id": m["id"], "name": m["id"].replace("-", " ").title(), "description": None, "efforts": []}
                      for m in data.get("data", [])]
            self._catalog = {"id": self.id, "name": self.name, "available": bool(models), "models": models,
                             "defaultModel": models[0]["id"] if models else None, "version": health.get("version"),
                             "supportsImages": False, "supportsInterrupt": True, "supportsPermissions": False}
        except Exception as exc:
            return {"id": self.id, "name": self.name, "available": False, "error": f"Hermes isn't reachable: {exc}"}
        self._catalog_at = time.time()
        return self._catalog

    def open(self, session: dict, emit) -> "HermesSession":
        return HermesSession(self, session, emit)


class HermesSession:
    def __init__(self, agent: HermesAgent, session: dict, emit):
        self.agent = agent
        self.session = session
        self.emit = emit
        self.run_id = None
        self.task = None

    async def send(self, text: str, attachments: list[dict]):
        if not self.session.get("native_id"):
            self.session["native_id"] = f"linkup-{self.session['id']}"
            self.agent.store.update_session(self.session["id"], native_id=self.session["native_id"])
        notes = [f"Attached file: {a['path']}" for a in attachments]
        payload = {"model": self.session.get("model") or "hermes-knight",
                   "input": "\n".join(notes + [text]) if notes else text,
                   "session_id": self.session["native_id"]}
        await self.emit({"type": "turn.start"})
        await self.emit({"type": "status", "state": "requesting"})
        self.task = asyncio.create_task(self._run(payload))

    async def _run(self, payload: dict):
        started = time.time()
        block = None
        tools: dict[str, list[str]] = {}
        ended = False
        try:
            async with aiohttp.ClientSession() as http:
                async with http.post(f"{self.agent.base}/v1/runs", headers=self.agent.headers, json=payload,
                                     timeout=aiohttp.ClientTimeout(total=30)) as r:
                    start = await r.json(content_type=None)
                self.run_id = start.get("run_id")
                async with http.get(f"{self.agent.base}/v1/runs/{self.run_id}/events", headers=self.agent.headers,
                                    timeout=aiohttp.ClientTimeout(total=None, sock_read=900)) as r:
                    async for raw in r.content:
                        line = raw.decode(errors="replace").strip()
                        if not line.startswith("data:"):
                            continue
                        try:
                            e = json.loads(line[5:].strip())
                        except ValueError:
                            continue
                        ev = e.get("event")
                        if ev == "message.delta":
                            if not block:
                                block = uuid.uuid4().hex[:12]
                                await self.emit({"type": "text.start", "block": block})
                                await self.emit({"type": "status", "state": "running"})
                            await self.emit({"type": "text.delta", "block": block, "text": e.get("delta", "")})
                        elif ev == "reasoning.available" and e.get("text"):
                            tb = uuid.uuid4().hex[:12]
                            await self.emit({"type": "thinking.start", "block": tb})
                            await self.emit({"type": "thinking.delta", "block": tb, "text": e["text"]})
                            await self.emit({"type": "thinking.end", "block": tb})
                        elif ev == "tool.started":
                            if block:
                                await self.emit({"type": "text.end", "block": block})
                                block = None
                            tid = uuid.uuid4().hex[:12]
                            tools.setdefault(e.get("tool", "tool"), []).append(tid)
                            await self.emit({"type": "tool.start", "id": tid, "name": e.get("tool"),
                                             "input": {"preview": e.get("preview")} if e.get("preview") else {}})
                            await self.emit({"type": "status", "state": "running"})
                        elif ev == "tool.completed":
                            ids = tools.get(e.get("tool", "tool")) or [uuid.uuid4().hex[:12]]
                            tid = ids.pop(0)
                            await self.emit({"type": "tool.end", "id": tid, "output": e.get("preview") or "",
                                             "isError": bool(e.get("error")), "images": []})
                        elif ev in ("run.completed", "run.failed", "run.cancelled", "run.stopped"):
                            if block:
                                await self.emit({"type": "text.end", "block": block})
                                block = None
                            u = e.get("usage") or {}
                            if u:
                                await self.emit({"type": "usage", "inputTokens": u.get("input_tokens", 0),
                                                 "outputTokens": u.get("output_tokens", 0),
                                                 "cacheRead": u.get("cache_read_tokens", 0),
                                                 "cacheWrite": u.get("cache_write_tokens", 0)})
                            failed = ev != "run.completed"
                            if ev == "run.failed":
                                await self.emit({"type": "error", "message": e.get("error") or "Hermes run failed"})
                            await self.emit({"type": "turn.end", "stopReason": ev.split(".")[1], "isError": failed,
                                             "durationMs": int((time.time() - started) * 1000)})
                            ended = True
                            break
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            await self.emit({"type": "error", "message": f"Hermes: {exc}"})
        finally:
            if not ended:
                await self.emit({"type": "turn.end", "stopReason": "exited", "isError": True,
                                 "durationMs": int((time.time() - started) * 1000)})
            await self.emit({"type": "status", "state": "idle"})

    async def interrupt(self):
        if not self.run_id:
            return
        try:
            async with aiohttp.ClientSession() as http:
                await http.post(f"{self.agent.base}/v1/runs/{self.run_id}/stop", headers=self.agent.headers,
                                timeout=aiohttp.ClientTimeout(total=10))
        except Exception as exc:
            log.warning("hermes stop failed: %s", exc)

    async def resolve_permission(self, pid, allow, message=None):
        return

    async def set_mode(self, mode):
        return

    async def close(self):
        return
