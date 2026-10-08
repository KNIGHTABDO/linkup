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

from . import commands, history, workspace
from . import usage as plan_usage
from .scheduler import Scheduler
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
    home_dir = os.path.expanduser(os.environ.get("LINKUP_HOME") or HOME)
    path = os.path.join(home_dir, "token")
    if os.path.isfile(path):
        with open(path, "r", encoding="utf-8") as f:
            tok = f.read().strip()
        if not tok:
            raise RuntimeError(f"Refusing empty token in {path}")
        return tok

    os.makedirs(home_dir, exist_ok=True)
    new_token = secrets.token_urlsafe(32)
    tmp_path = os.path.join(home_dir, f"token.tmp.{uuid.uuid4().hex}")
    fd = os.open(tmp_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(new_token)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_path, path)
    except Exception:
        if os.path.exists(tmp_path):
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
        raise
    return new_token


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
        self.plan = None            # Claude plan usage (polled)
        self.agy_quota = None       # Antigravity credits / quota (polled)
        self.home = os.path.expanduser(os.environ.get("LINKUP_HOME") or HOME)
        self.scheduler = Scheduler(self.home, self.run_schedule)
        self.active_readers: dict[str, float] = {}
        self.import_locks: dict[str, asyncio.Lock] = {}
        for s in self.store.sessions():                # a crash mid-turn must not leave sessions "running"
            if s["status"] != "idle":
                sid = s["id"]
                self.store.append(sid, {"type": "error", "message": "Bridge restarted"})
                self.store.append(sid, {"type": "turn.end", "stopReason": "error", "isError": True})
                self.store.update_session(sid, status="idle")

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
                    art = self.media.artifact(path)
                    if art:
                        await self.record(sid, {**art, "fromText": True})
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
            last_focus = self.active_readers.get(sid, 0.0)
            has_active_subscriber = any(sid in subs for subs in self.clients.values())
            if not (has_active_subscriber and (time.time() - last_focus < 60.0)):
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
        return {"claude": claude, "claudePlan": self.plan, "agy": self.agy_quota, "totals": totals, "at": time.time()}

    async def poll_usage(self):
        """Plan usage every minute (Antigravity's every 5), pushed to every device the moment it changes."""
        tick = 0
        while True:
            changed = False
            try:
                plan = await plan_usage.claude_plan()
                if plan and plan != self.plan:
                    self.plan, changed = plan, True
            except Exception as exc:
                log.warning("claude usage poll failed: %s", exc)
            if tick % 5 == 0:
                try:
                    quota = await plan_usage.agy_usage()
                    if quota and quota != self.agy_quota:
                        self.agy_quota, changed = quota, True
                except Exception as exc:
                    log.warning("agy usage poll failed: %s", exc)
            if changed:
                await self.broadcast({"op": "usage", "usage": self.usage()})
            tick += 1
            await asyncio.sleep(60)

    def transcript_text(self, sid: str, limit_chars: int = 14000) -> str:
        """The conversation as plain text, for handing it to another agent."""
        lines, texts = [], {}
        for e in self.store.events(sid):
            if e["type"] == "user" and e.get("text"):
                lines.append(f"User: {e['text']}")
            elif e["type"] == "text.delta":
                texts.setdefault(e.get("block"), []).append(e.get("text", ""))
            elif e["type"] == "text.end" and e.get("block") in texts:
                lines.append("Assistant: " + "".join(texts.pop(e["block"])))
        text = "\n\n".join(lines)
        return text[-limit_chars:]

    async def start_session(self, ws, agent: str, model=None, effort=None, cwd=None, title=None,
                            permission_mode=None, mode=None, fork_from=None, context=None) -> dict:
        if agent not in self.agents:
            raise ValueError(f"Unknown agent {agent}")
        if mode == "chat" and not cwd:
            cwd = os.path.join(HOME, "chat")
            os.makedirs(cwd, exist_ok=True)
        s = self.store.create_session(agent, model, effort, cwd, title, permission_mode=permission_mode, mode=mode,
                                      fork_from=fork_from, context=context)
        if ws is not None:
            self.clients.setdefault(ws, set()).add(s["id"])
        await self.broadcast({"op": "session", "session": s})
        rt = self.runtime(s["id"])
        if hasattr(rt, "warm"):
            asyncio.create_task(rt.warm())
        return s

    async def submit(self, sid: str, text: str, atts: list[dict], client_id=None):
        """Records the user's message and hands it to the agent (one turn at a time per session)."""
        s = self.store.session(sid)
        if not s:
            raise KeyError("No such session")
        shown = [{"name": a.get("name") or os.path.basename(a["path"]), "mime": a.get("mime"),
                  "url": self.media.url(a["path"])} for a in atts]
        if not s.get("title"):
            title = " ".join(text.split())[:60] or (shown[0]["name"] if shown else "New session")
            self.store.update_session(sid, title=title)
        await self.record(sid, {"type": "user", "text": text, "attachments": shown, "client": client_id})
        await self.push_session(sid)
        prompt = text
        s = self.store.session(sid)
        if s.get("context"):
            prompt = f"{s['context']}\n\n---\n\n{text}"
            self.store.update_session(sid, context=None)
        if s.get("mode") == "chat" and s["agent"] != "claude" and not s.get("native_id"):
            from .agents.claude import CARDS_PROMPT
            prompt = f"{CARDS_PROMPT}\n\n---\n\nUser message:\n{prompt}"
        lock = self.locks.setdefault(sid, asyncio.Lock())
        async with lock:
            rt = self.runtime(sid)
            rt.session.update({k: v for k, v in self.store.session(sid).items()
                               if k in ("model", "effort", "permission_mode", "native_id", "cwd", "mode", "fork_from")})
            try:
                await rt.send(prompt, atts)
            except Exception as exc:
                log.exception("send failed")
                await self.record(sid, {"type": "error", "message": str(exc)})
                await self.record(sid, {"type": "turn.end", "stopReason": "error", "isError": True})
                await self.record(sid, {"type": "status", "state": "idle"})

    async def run_schedule(self, schedule: dict) -> dict:
        s = await self.start_session(None, schedule["agent"], schedule.get("model"), None, schedule.get("cwd"),
                                     f"\u23F0 {schedule.get('title') or 'Scheduled'}")
        asyncio.create_task(self.submit(s["id"], schedule["prompt"], []))
        return s

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
        for c in out:
            try:
                if c["id"] == "agy" and not c.get("commands"):
                    c["commands"] = await commands.agy_commands()
                elif c["id"] == "hermes" and not c.get("commands"):
                    c["commands"] = commands.hermes_commands()
            except Exception as exc:
                log.warning("commands for %s failed: %s", c["id"], exc)
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
            sid = msg.get("session")
            if sid:
                subs.discard(sid)
            return {"op": "unsubscribed", "session": sid} if msg.get("rid") else None
        if op == "create":
            s = await self.start_session(ws, msg.get("agent") or "claude", msg.get("model"), msg.get("effort"),
                                         msg.get("cwd"), msg.get("title"), msg.get("permissionMode"), msg.get("mode"))
            return {"op": "session", "session": s}
        if op == "import":
            native = msg.get("nativeId", "")
            if not history.is_valid_native_id(native):
                raise ValueError(f"Invalid nativeId: {native!r}")
            import_lock = self.import_locks.setdefault(native, asyncio.Lock())
            async with import_lock:
                existing = next((s for s in self.store.sessions() if s["agent"] == "claude" and s["native_id"] == native), None)
                if existing:
                    subs.add(existing["id"])
                    return {"op": "session", "session": existing}
                info, evts = await asyncio.to_thread(history.load_for_import, native)
                s = self.store.create_session("claude", "default", None, info.get("cwd"), info.get("title"), native_id=native)
                await asyncio.to_thread(self.store.append_bulk, s["id"], evts)
                s = self.store.session(s["id"])
                subs.add(s["id"])
                await self.broadcast({"op": "session", "session": s})
                return {"op": "session", "session": s}
        if op == "send":
            atts = [a for a in (msg.get("attachments") or []) if a.get("path") and os.path.isfile(a["path"])]
            await self.submit(msg["session"], msg.get("text") or "", atts, msg.get("clientId"))
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
            sid = msg["session"]
            self.active_readers[sid] = time.time()
            self.store.update_session(sid, unread=0)
            await self.push_session(sid)
            return None
        if op == "focus":
            sid = msg["session"]
            self.active_readers[sid] = time.time()
            self.store.update_session(sid, unread=0)
            await self.push_session(sid)
            return None
        if op == "delete":
            sid = msg["session"]
            rt = self.runtimes.pop(sid, None)
            if rt:
                await rt.close()
            self.store.delete_session(sid)
            await self.broadcast({"op": "deleted", "session": sid})
            return None
        if op == "fork":
            src = self.store.session(msg["session"])
            if not src:
                raise KeyError("No such session")
            title = f"{src.get('title') or 'Session'} (fork)"
            if src["agent"] == "claude" and src.get("native_id"):
                s = await self.start_session(ws, "claude", src.get("model"), src.get("effort"), src.get("cwd"), title,
                                             src.get("permission_mode"), src.get("mode"), fork_from=src["native_id"])
            else:
                s = await self.start_session(ws, src["agent"], src.get("model"), src.get("effort"), src.get("cwd"), title,
                                             src.get("permission_mode"), src.get("mode"),
                                             context=f"Earlier conversation (continue from it):\n\n{self.transcript_text(src['id'])}")
            copied = []
            open_turn = False
            for e in self.store.events(src["id"]):          # the copy shows the history it continues from
                e_clean = {k: v for k, v in e.items() if k not in ("seq", "ts")}
                copied.append({**e_clean, "imported": True})
                if e.get("type") == "turn.start":
                    open_turn = True
                elif e.get("type") == "turn.end":
                    open_turn = False
            if open_turn:
                copied.append({"type": "turn.end", "stopReason": "forked", "imported": True})
            await asyncio.to_thread(self.store.append_bulk, s["id"], copied)
            return {"op": "session", "session": self.store.session(s["id"])}
        if op == "handoff":
            src = self.store.session(msg["session"])
            if not src:
                raise KeyError("No such session")
            agent = msg.get("agent") or "claude"
            context = (f"You are taking over a conversation the user had with {self.agents[src['agent']].name}. "
                       f"Here it is:\n\n{self.transcript_text(src['id'])}\n\nContinue helping from here.")
            s = await self.start_session(ws, agent, msg.get("model"), None, src.get("cwd"),
                                         f"{src.get('title') or 'Session'} \u2192 {self.agents[agent].name}",
                                         None, src.get("mode"), context=context)
            await self.record(s["id"], {"type": "notice", "text": f"Context from \u201C{src.get('title') or 'session'}\u201D attached"})
            return {"op": "session", "session": self.store.session(s["id"])}
        if op == "compare":
            prompt = msg.get("prompt") or ""
            out = []
            for agent in msg.get("agents") or list(self.agents):
                s = await self.start_session(ws, agent, None, None, msg.get("cwd"), f"\u2696\uFE0E {prompt[:50]}")
                out.append(s)
                asyncio.create_task(self.submit(s["id"], prompt, []))
            return {"op": "sessions.compare", "sessions": out}
        if op == "projects.create":
            p = await asyncio.to_thread(workspace.create_project, msg["name"], bool(msg.get("git")),
                                        bool(msg.get("readme")), msg.get("template"))
            return {"op": "project", "project": p}
        if op in ("fs.list", "fs.read", "git.status", "git.diff", "git.log", "git.commit", "git.push", "gh.runs"):
            path = os.path.expanduser(msg.get("path") or "~")
            if not workspace.allowed(path):
                raise PermissionError("That folder isn't reachable from Linkup")
            if op == "fs.list":
                return {"op": op, "entries": await asyncio.to_thread(workspace.list_dir, path)}
            if op == "fs.read":
                return {"op": op, "file": await asyncio.to_thread(workspace.read_file, path, self.media.url)}
            if op == "git.status":
                return {"op": op, "status": await workspace.git_status(path)}
            if op == "git.diff":
                return {"op": op, "diff": await workspace.git_diff(path, msg.get("file"))}
            if op == "git.log":
                return {"op": op, "commits": await workspace.git_log(path)}
            if op == "git.commit":
                return {"op": op, "commit": await workspace.git_commit(path, msg.get("message") or "Update from Linkup")}
            if op == "git.push":
                return {"op": op, "output": await workspace.git_push(path)}
            return {"op": op, "runs": await workspace.gh_runs(path)}
        if op == "schedules":
            return {"op": op, "schedules": self.scheduler.list()}
        if op == "schedule.save":
            return {"op": op, "schedule": self.scheduler.save(msg["schedule"])}
        if op == "schedule.delete":
            self.scheduler.delete(msg["id"])
            return {"op": op}
        if op == "schedule.run":
            return {"op": op, "session": await self.scheduler.run_now(msg["id"])}
        raise ValueError(f"Unknown op {op}")


# -- HTTP -------------------------------------------------------------------------------------------------------
def authorized(request: web.Request, hub: Hub) -> bool:
    supplied = request.query.get("token") or request.cookies.get("linkup_token") or request.cookies.get("linkup")
    header = request.headers.get("Authorization", "")
    if header.startswith("Bearer "):
        supplied = header[7:].strip()
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
        if os.path.basename(path) != name or not os.path.isfile(path):
            return web.Response(status=404)
        resp = web.FileResponse(path, headers={"Content-Type": mime or "application/octet-stream",
                                               "Cache-Control": "private, max-age=3600"})
        if request.query.get("token"):
            resp.set_cookie("linkup_token", request.query["token"], httponly=True, secure=True, samesite="Lax",
                            path="/linkup/")
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

    async def proxy(request):
        if not authorized(request, hub):
            return web.Response(status=401, text="unauthorized")
        return await workspace.proxy(request, int(request.match_info["port"]), request.match_info.get("tail", ""))
    app.router.add_route("*", "/linkup/proxy/{port:\\d+}/{tail:.*}", proxy)

    async def warm(app):
        async def go():
            try:
                await hub.catalog(force=True)
                log.info("catalog ready")
            except Exception as exc:
                log.warning("catalog warmup failed: %s", exc)
        asyncio.create_task(go())
        asyncio.create_task(hub.poll_usage())
        hub.scheduler.start()
    app.on_startup.append(warm)
    return app


def main():
    logging.basicConfig(level=os.environ.get("LINKUP_LOG", "INFO"), format="%(asctime)s %(levelname)s %(name)s %(message)s")
    web.run_app(make_app(), host=os.environ.get("LINKUP_HOST", "127.0.0.1"), port=PORT, access_log=None)
