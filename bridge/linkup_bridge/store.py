"""Sessions and their event logs. Every event gets a per-session sequence number so any client can reconnect and
resume exactly where it left off (`since=<seq>`), and several devices stay in sync."""
from __future__ import annotations

import json
import os
import sqlite3
import threading
import time
import uuid

HOME = os.path.expanduser(os.environ.get("LINKUP_HOME", "~/.linkup"))


class Store:
    def __init__(self, path: str | None = None):
        os.makedirs(HOME, exist_ok=True)
        self.path = path or os.path.join(HOME, "linkup.db")
        self.lock = threading.RLock()
        self.db = sqlite3.connect(self.path, check_same_thread=False, isolation_level=None)
        self.db.execute("pragma journal_mode=wal")
        self.db.execute("pragma synchronous=normal")
        self.db.executescript("""
            create table if not exists sessions (
                id text primary key, agent text not null, title text, model text, effort text, cwd text,
                native_id text, permission_mode text, created real, updated real, pinned integer default 0,
                status text default 'idle', last_seq integer default 0, preview text, unread integer default 0,
                usage text);
            create table if not exists events (
                session_id text not null, seq integer not null, ts real not null, type text not null, data text not null,
                primary key (session_id, seq));
            create table if not exists files (id text primary key, path text not null, mime text, created real);
        """)

    # -- sessions ---------------------------------------------------------------------------------------------
    def create_session(self, agent: str, model: str | None, effort: str | None, cwd: str | None,
                       title: str | None = None, native_id: str | None = None,
                       permission_mode: str | None = None) -> dict:
        sid = uuid.uuid4().hex[:16]
        now = time.time()
        with self.lock:
            self.db.execute("insert into sessions (id, agent, title, model, effort, cwd, native_id, permission_mode,"
                            " created, updated) values (?,?,?,?,?,?,?,?,?,?)",
                            (sid, agent, title, model, effort, cwd, native_id, permission_mode, now, now))
        return self.session(sid)

    def session(self, sid: str) -> dict | None:
        with self.lock:
            cur = self.db.execute("select * from sessions where id=?", (sid,))
            row = cur.fetchone()
            if not row:
                return None
            return self._row(cur.description, row)

    def sessions(self) -> list[dict]:
        with self.lock:
            cur = self.db.execute("select * from sessions order by pinned desc, updated desc")
            return [self._row(cur.description, r) for r in cur.fetchall()]

    def update_session(self, sid: str, **fields):
        if not fields:
            return
        keys = ", ".join(f"{k}=?" for k in fields)
        with self.lock:
            self.db.execute(f"update sessions set {keys} where id=?", (*fields.values(), sid))

    def delete_session(self, sid: str):
        with self.lock:
            self.db.execute("delete from events where session_id=?", (sid,))
            self.db.execute("delete from sessions where id=?", (sid,))

    @staticmethod
    def _row(desc, row) -> dict:
        d = {c[0]: v for c, v in zip(desc, row)}
        d["pinned"] = bool(d.get("pinned"))
        d["usage"] = json.loads(d["usage"]) if d.get("usage") else None
        return d

    # -- events -----------------------------------------------------------------------------------------------
    def append(self, sid: str, event: dict) -> dict:
        """Stores an event (assigns seq/ts) and returns it as sent to clients."""
        with self.lock:
            seq = self.db.execute("select coalesce(max(seq), 0) + 1 from events where session_id=?", (sid,)).fetchone()[0]
            event = {**event, "seq": seq, "ts": event.get("ts") or time.time()}
            self.db.execute("insert into events values (?,?,?,?,?)",
                            (sid, seq, event["ts"], event["type"], json.dumps(event, separators=(",", ":"))))
            self.db.execute("update sessions set last_seq=?, updated=? where id=?", (seq, event["ts"], sid))
        return event

    def events(self, sid: str, since: int = 0, limit: int = 20000) -> list[dict]:
        with self.lock:
            rows = self.db.execute("select data from events where session_id=? and seq>? order by seq limit ?",
                                   (sid, since, limit)).fetchall()
        return [json.loads(r[0]) for r in rows]

    # -- files the phone may fetch ----------------------------------------------------------------------------
    def register_file(self, path: str, mime: str | None) -> str:
        path = os.path.abspath(path)
        with self.lock:
            row = self.db.execute("select id from files where path=?", (path,)).fetchone()
            if row:
                return row[0]
            fid = uuid.uuid4().hex
            self.db.execute("insert into files values (?,?,?,?)", (fid, path, mime, time.time()))
            return fid

    def file(self, fid: str) -> tuple[str, str | None] | None:
        with self.lock:
            row = self.db.execute("select path, mime from files where id=?", (fid,)).fetchone()
        return (row[0], row[1]) if row else None
