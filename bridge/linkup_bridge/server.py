"""Linkup bridge: one WebSocket (`/linkup/ws`) multiplexing every agent session to every connected device.

Client -> bridge (JSON, `op` field; optional `rid` echoed back in the reply):
  hello {since:{sessionId: lastSeq}}      -> hello {server, sessions, catalog} + missed events for those sessions
  catalog {force?}                        -> catalog {agents:[...], usage}
  sessions                                -> sessions {sessions:[...]}
  subscribe {session, since}              -> events after `since`, then live
  create {agent, model?, effort?, cwd?, title?, permissionMode?}  -> session {session}
  send {session, text, attachments:[{path, name, mime}]}
  interrupt {session}      permission {session, id, allow, message?}
  update {session, title?, pinned?, model?, effort?, permissionMode?}   delete {session}   read {session}
  projects                                -> projects {projects:[{name, path}]}
  history                                 -> history {sessions:[...]}   (Claude Code sessions started on the PC)
  import {nativeId}                       -> session {session}
  ping                                    -> pong
Bridge -> client: event {session, event} · session {session} · sessions · catalog · usage · error {message}
HTTP: GET /linkup/health · GET /linkup/files/<id>/<name> · POST /linkup/upload?name= (raw body)
Auth: ?token= or `Authorization: Bearer` (and a cookie for HTML artifacts loading their own assets).
"""
from __future__ import annotations

import asyncio
import json
import logging
import mimetypes
import os
import secrets
import time
import uuid

from aiohttp import WSMsgType, web

from . import history
from .agents.agy import AgyAgent
from .agents.base import Media, paths_in
from .agents.claude import ClaudeAgent
from .agents.hermes import HermesAgent
from .store import HOME, Store

log = logging.getLogger("linkup")
VERSION = "1.0.0"
PORT = int(os.environ.get("LINKUP_PORT", "8890"))
PROJECTS = os.path.expanduser(os.environ.get("LINKUP_PROJECTS", "~/Desktop/projects"))


def load_token() -> str:
    path = os.path.join(HOME, "token")
    if not os.path.exists(path):
        os.makedirs(HOME, exist_ok=True)
        with open(path, "w") as f:
            f.write(secrets.token_urlsafe(32))
        os.chmod(path, 0o600)
    with open(path) as f:
        return f.read().strip()


class Hub:
    def __init__(self):
        self.store = Store()
        self.media = Media(self.store)
        self.agents = {a.id: a for a in (ClaudeAgent(self.store, self.media), AgyAgent(self.store, self.media),
                                         HermesAgent(self.store, self.media))}
        self.runtimes: dict[str, object] = {}         # session id -> adapter session
        self.clients: dict[web.WebSocketResponse, set[str]] = {}
        self.text_buffers: dict[tuple[str, str], list[str]] = {}
        self.locks: dict[str, asyncio.Lock] = {}
        self.artifact_paths: dict[str, set[str]] = {}   # session -> artifact paths already announced
        self.token = load_token()
        for s in self.store.sessions():                # a crash mid-turn must not leave sessions "running"
            if s["status"] != "idle":
                self.store.update_session(s["id"], status="idle")

    # -- broadcasting -----------------------------------------------------------------------------------------
    async def broadcast(self, payload: dict, session: str | None = None):
        """Events go to the devices subscribed to that session; everything else (session list, usage) to all."""
        data = json.dumps(payload, separators=(",", ":"))
        for ws, subs in list(self.clients.items()):
            if payload.get("op") == "event" and session not in subs:
                continue
            try:
                await ws.send_str(data)
            except Exception:
                self.clients.pop(ws, None)

    async def push_session(self, sid: str):
        s = self.store.session(sid)
        if s:
            await self.broadcast({"op": "session", "session": s})

    def emitter(self, sid: str):
        async def emit(event: dict):
            await self.record(sid, event)
        return emit

    async def record(self, sid: str, event: dict):
        if event["type"] == "artifact":
            seen = self.artifact_paths.setdefault(sid, set())
            key = f"{event.get('path')}:{event.get('size')}"
            if key in seen:
                return
            seen.add(key)
        event = self.store.append(sid, event)
        await self.broadcast({"op": "event", "session": sid, "event": event}, session=sid)
        await self._side_effects(sid, event)

    async def _side_effects(self, sid: str, e: dict):
        t = e["type"]
        if t == "text.delta":
            self.text_buffers.setdefault((sid, e.get("block") or ""), []).append(e.get("text", ""))
        elif t == "text.end":
            text = "".join(self.text_buffers.pop((sid, e.get("block") or ""), []))
            if text.strip():
                preview = " ".join(text.split())[:160]
                self.store.update_session(sid, preview=preview)
                for path in paths_in(text):
                    await self.record(sid, {**self.media.artifact(path), "fromText": True})
        elif t == "status":
            state = e.get("state")
            self.store.update_session(sid, status="idle" if state in ("idle", "error", "interrupted") else "running")
            await self.push_session(sid)
        elif t == "usage":
            s = self.store.session(sid) or {}
            u = s.get("usage") or {}
            for k in ("inputTokens", "outputTokens", "cacheRead", "cacheWrite", "thinkingTokens"):
                u[k] = (u.get(k) or 0) + (e.get(k) or 0)
            if e.get("costUsd") is not None:
                u["costUsd"] = round((u.get("costUsd") or 0) + e["costUsd"], 6)
            u["lastInput"] = (e.get("inputTokens") or 0) + (e.get("cacheRead") or 0) + (e.get("cacheWrite") or 0)
            self.store.update_session(sid, usage=json.dumps(u))
        elif t == "ratelimit":
            await self.broadcast({"op": "usage", "usage": self.usage()})
        elif t == "turn.end":
            s = self.store.session(sid) or {}
            self.store.update_session(sid, unread=1)
            await self.push_session(sid)

    def usage(self) -> dict:
        claude = self.agents["claude"].ratelimit
        totals = {}
        for s in self.store.sessions():
            u = s.get("usage") or {}
            a = totals.setdefault(s["agent"], {"inputTokens": 0, "outputTokens": 0, "costUsd": 0.0, "sessions": 0})
            a["inputTokens"] += (u.get("inputTokens") or 0) + (u.get("cacheRead") or 0) + (u.get("cacheWrite") or 0)
            a["outputTokens"] += u.get("outputTokens") or 0
            a["costUsd"] = round(a["costUsd"] + (u.get("costUsd") or 0), 4)
            a["sessions"] += 1
        return {"claude": claude, "totals": totals, "at": time.time()}

    # -- runtime ----------------------------------------------------------------------------------------------
    def runtime(self, sid: str):
        rt = self.runtimes.get(sid)
        if rt is None:
            s = self.store.session(sid)
            if not s:
                raise KeyError("No such session")
            rt = self.agents[s["agent"]].open(s, self.emitter(sid))
            self.runtimes[sid] = rt
        return rt

    async def catalog(self, force=False) -> dict:
        agents = await asyncio.gather(*(a.catalog(force) for a in self.agents.values()), return_exceptions=True)
        out = []
        for a, c in zip(self.agents.values(), agents):
            out.append(c if isinstance(c, dict) else {"id": a.id, "name": a.name, "available": False, "error": str(c)})
        return {"agents": out}

    def projects(self) -> list[dict]:
        out = [{"name": "Home", "path": os.path.expanduser("~")}]
        try:
            for name in sorted(os.listdir(PROJECTS), key=lambda n: -os.path.getmtime(os.path.join(PROJECTS, n))):
                p = os.path.join(PROJECTS, name)
                if os.path.isdir(p) and not name.startswith("."):
                    out.append({"name": name, "path": p})
        except OSError:
            pass
        return out

    # -- ops --------------------------------------------------------------------------------------------------
    async def handle(self, ws, msg: dict) -> dict | None:
        op = msg.get("op")
        subs = self.clients.setdefault(ws, set())
        if op == "ping":
            return {"op": "pong", "t": msg.get("t")}
        if op == "hello":
            since = msg.get("since") or {}
            for sid, seq in since.items():
                if self.store.session(sid):
                    subs.add(sid)
                    for e in self.store.events(sid, int(seq or 0)):
                        await ws.send_str(json.dumps({"op": "event", "session": sid, "event": e}, separators=(",", ":")))
            return {"op": "hello", "server": {"version": VERSION, "name": os.uname().nodename},
                    "sessions": self.store.sessions(), "usage": self.usage()}
        if op == "catalog":
            cat = await self.catalog(bool(msg.get("force")))
            return {"op": "catalog", **cat, "usage": self.usage()}
        if op == "sessions":
            return {"op": "sessions", "sessions": self.store.sessions()}
        if op == "projects":
            return {"op": "projects", "projects": self.projects()}
        if op == "history":
            return {"op": "history", "sessions": await asyncio.to_thread(history.list_sessions)}
        if op == "subscribe":
            sid = msg["session"]
            subs.add(sid)
            for e in self.store.events(sid, int(msg.get("since") or 0)):
                await ws.send_str(json.dumps({"op": "event", "session": sid, "event": e}, separators=(",", ":")))
            return {"op": "subscribed", "session": sid}
        if op == "unsubscribe":
            subs.discard(msg.get("session"))
            return None
        if op == "create":
            agent = msg.get("agent") or "claude"
            if agent not in self.agents:
                raise ValueError(f"Unknown agent {agent}")
            s = self.store.create_session(agent, msg.get("model"), msg.get("effort"), msg.get("cwd"), msg.get("title"),
                                          permission_mode=msg.get("permissionMode"))
            subs.add(s["id"])
            await self.broadcast({"op": "session", "session": s})
            return {"op": "session", "session": s}
        if op == "import":
            native = msg["nativeId"]
            existing = next((s for s in self.store.sessions() if s["agent"] == "claude" and s["native_id"] == native), None)
            if existing:
                return {"op": "session", "session": existing}
            info = next((h for h in await asyncio.to_thread(history.list_sessions, 200) if h["nativeId"] == native), {})
            s = self.store.create_session("claude", "default", None, info.get("cwd"), info.get("title"), native_id=native)
            for e in await asyncio.to_thread(history.events, native):
                self.store.append(s["id"], e)
            s = self.store.session(s["id"])
            subs.add(s["id"])
            await self.broadcast({"op": "session", "session": s})
            return {"op": "session", "session": s}
        if op == "send":
            sid = msg["session"]
            s = self.store.session(sid)
            if not s:
                raise KeyError("No such session")
            text = msg.get("text") or ""
            atts = [a for a in (msg.get("attachments") or []) if a.get("path") and os.path.isfile(a["path"])]
            shown = [{"name": a.get("name") or os.path.basename(a["path"]), "mime": a.get("mime"),
                      "url": self.media.url(a["path"])} for a in atts]
            if not s.get("title"):
                title = " ".join(text.split())[:60] or (shown[0]["name"] if shown else "New session")
                self.store.update_session(sid, title=title)
            await self.record(sid, {"type": "user", "text": text, "attachments": shown, "client": msg.get("clientId")})
            await self.push_session(sid)
            lock = self.locks.setdefault(sid, asyncio.Lock())
            async with lock:
                rt = self.runtime(sid)
                rt.session.update({k: v for k, v in self.store.session(sid).items() if k in ("model", "effort", "permission_mode", "native_id", "cwd")})
                try:
                    await rt.send(text, atts)
                except Exception as exc:
                    log.exception("send failed")
                    await self.record(sid, {"type": "error", "message": str(exc)})
                    await self.record(sid, {"type": "turn.end", "stopReason": "error", "isError": True})
                    await self.record(sid, {"type": "status", "state": "idle"})
            return None
        if op == "interrupt":
            rt = self.runtimes.get(msg["session"])
            if rt:
                await rt.interrupt()
                await self.record(msg["session"], {"type": "notice", "text": "Stopped"})
            return None
        if op == "permission":
            rt = self.runtimes.get(msg["session"])
            if rt:
                await rt.resolve_permission(msg["id"], bool(msg.get("allow")), msg.get("message"))
            return None
        if op == "update":
            sid = msg["session"]
            fields = {}
            for key, col in (("title", "title"), ("model", "model"), ("effort", "effort"),
                             ("permissionMode", "permission_mode"), ("cwd", "cwd")):
                if key in msg:
                    fields[col] = msg[key]
            if "pinned" in msg:
                fields["pinned"] = 1 if msg["pinned"] else 0
            self.store.update_session(sid, **fields)
            rt = self.runtimes.get(sid)
            if rt and "permission_mode" in fields:
                await rt.set_mode(fields["permission_mode"])
            await self.push_session(sid)
            return None
        if op == "read":
            self.store.update_session(msg["session"], unread=0)
            await self.push_session(msg["session"])
            return None
        if op == "delete":
            sid = msg["session"]
            rt = self.runtimes.pop(sid, None)
            if rt:
                await rt.close()
            self.store.delete_session(sid)
            await self.broadcast({"op": "deleted", "session": sid})
            return None
        raise ValueError(f"Unknown op {op}")


# -- HTTP -------------------------------------------------------------------------------------------------------
def authorized(request: web.Request, hub: Hub) -> bool:
    supplied = request.query.get("token") or request.cookies.get("linkup")
    header = request.headers.get("Authorization", "")
    if header.startswith("Bearer "):
        supplied = header[7:]
    return bool(supplied) and secrets.compare_digest(supplied, hub.token)


def make_app() -> web.Application:
    hub = Hub()
    app = web.Application(client_max_size=200 << 20)
    app["hub"] = hub

    async def health(request):
        return web.json_response({"ok": True, "name": "linkup", "version": VERSION})

    async def ws_handler(request):
        if not authorized(request, hub):
            return web.json_response({"error": "unauthorized"}, status=401)
        ws = web.WebSocketResponse(heartbeat=20, max_msg_size=64 << 20, compress=False)
        await ws.prepare(request)
        hub.clients[ws] = set()
        log.info("client connected (%d)", len(hub.clients))
        try:
            async for raw in ws:
                if raw.type != WSMsgType.TEXT:
                    continue
                try:
                    msg = json.loads(raw.data)
                except ValueError:
                    continue

                async def run(msg=msg):
                    try:
                        reply = await hub.handle(ws, msg)
                    except Exception as exc:
                        log.warning("op %s failed: %s", msg.get("op"), exc)
                        reply = {"op": "error", "message": str(exc), "for": msg.get("op")}
                    if reply is not None:
                        if msg.get("rid"):
                            reply["rid"] = msg["rid"]
                        await ws.send_str(json.dumps(reply, separators=(",", ":")))
                asyncio.create_task(run())
        finally:
            hub.clients.pop(ws, None)
            log.info("client disconnected (%d)", len(hub.clients))
        return ws

    async def files(request):
        if not authorized(request, hub):
            return web.Response(status=401, text="unauthorized")
        fid, name = request.match_info["fid"], request.match_info["name"]
        found = hub.store.file(fid)
        if not found:
            return web.Response(status=404)
        path, mime = found
        if os.path.basename(path) != name:
            # An HTML artifact asking for its own assets (style.css, img/x.png) next to it.
            base = os.path.dirname(path)
            candidate = os.path.normpath(os.path.join(base, name))
            if not candidate.startswith(base + os.sep) or not os.path.isfile(candidate):
                return web.Response(status=404)
            path, mime = candidate, mimetypes.guess_type(candidate)[0]
        resp = web.FileResponse(path, headers={"Content-Type": mime or "application/octet-stream",
                                               "Cache-Control": "private, max-age=3600"})
        if request.query.get("token"):
            resp.set_cookie("linkup", request.query["token"], httponly=True, secure=True, samesite="Lax",
                            path="/linkup/files/")
        return resp

    async def upload(request):
        if not authorized(request, hub):
            return web.json_response({"error": "unauthorized"}, status=401)
        name = os.path.basename(request.query.get("name") or "file")
        folder = os.path.join(HOME, "uploads", uuid.uuid4().hex[:12])
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, name)
        with open(path, "wb") as f:
            async for chunk in request.content.iter_chunked(1 << 20):
                f.write(chunk)
        mime = request.headers.get("Content-Type") or mimetypes.guess_type(name)[0]
        return web.json_response({"path": path, "name": name, "mime": mime, "url": hub.media.url(path),
                                  "size": os.path.getsize(path)})

    app.router.add_get("/linkup/health", health)
    app.router.add_get("/linkup/ws", ws_handler)
    app.router.add_get("/linkup/files/{fid}/{name:.+}", files)
    app.router.add_post("/linkup/upload", upload)

    async def warm(app):
        async def go():
            try:
                await hub.catalog(force=True)
                log.info("catalog ready")
            except Exception as exc:
                log.warning("catalog warmup failed: %s", exc)
        asyncio.create_task(go())
    app.on_startup.append(warm)
    return app


def main():
    logging.basicConfig(level=os.environ.get("LINKUP_LOG", "INFO"), format="%(asctime)s %(levelname)s %(name)s %(message)s")
    web.run_app(make_app(), host=os.environ.get("LINKUP_HOST", "127.0.0.1"), port=PORT, access_log=None)
