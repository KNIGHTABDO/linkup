"""Unit tests verifying all Linkup 1.0 bridge fixes."""
import asyncio
import os
import shutil
import sqlite3
import tempfile
import time
import unittest

from linkup_bridge import history, workspace
from linkup_bridge.agents import base
from linkup_bridge.agents.agy import AgyAgent, AgySession
from linkup_bridge.agents.claude import ClaudeAgent, ClaudeSession
from linkup_bridge.server import Hub, authorized, load_token
from linkup_bridge.store import Store


class TestBridgeFixes(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.orig_home = os.environ.get("LINKUP_HOME")
        os.environ["LINKUP_HOME"] = self.temp_dir

    def tearDown(self):
        if self.orig_home is not None:
            os.environ["LINKUP_HOME"] = self.orig_home
        else:
            os.environ.pop("LINKUP_HOME", None)
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    # 1. Security & Token
    def test_token_creation_and_refuse_empty(self):
        token_path = os.path.join(self.temp_dir, "token")
        # 1. Create fresh token
        token = load_token()
        self.assertTrue(len(token) >= 32)
        self.assertTrue(os.path.isfile(token_path))
        # Check permissions 0600
        mode = os.stat(token_path).st_mode & 0o777
        self.assertEqual(mode, 0o600)

        # 2. Refuse empty token
        with open(token_path, "w") as f:
            f.write("   \n")
        with self.assertRaises(RuntimeError):
            load_token()

    def test_uuid_validation(self):
        valid_uuid = "14297723-4686-44ed-ab73-9e0ab869ad42"
        invalid_uuid = "../../etc/passwd"
        invalid_uuid2 = "not-a-uuid"

        self.assertTrue(history.is_valid_native_id(valid_uuid))
        self.assertFalse(history.is_valid_native_id(invalid_uuid))
        self.assertFalse(history.is_valid_native_id(invalid_uuid2))
        self.assertEqual(history.events(invalid_uuid), [])

    def test_workspace_proxy_ports(self):
        denied_ports = [8890, 8642, 3306, 5432, 6379, 6432, 9042, 9200, 9300, 80, 443, 22, 2999, 10000]
        allowed_ports = [3000, 3001, 4000, 5000, 5173, 8000, 8080, 9999]

        from linkup_bridge.workspace import DEV_PORT_MIN, DEV_PORT_MAX, DENIED_PORTS

        bridge_port = int(os.environ.get("LINKUP_PORT", "8890"))
        all_denied = DENIED_PORTS | {8890, bridge_port}

        for p in denied_ports:
            is_allowed = (DEV_PORT_MIN <= p <= DEV_PORT_MAX) and (p not in all_denied)
            self.assertFalse(is_allowed, f"Port {p} should be denied")

        for p in allowed_ports:
            is_allowed = (DEV_PORT_MIN <= p <= DEV_PORT_MAX) and (p not in all_denied)
            self.assertTrue(is_allowed, f"Port {p} should be allowed")

    # 2. Base artifact safe
    def test_base_artifact_missing_file(self):
        store = Store()
        media = base.Media(store)
        # Non-existent path returns None without crash
        self.assertIsNone(media.artifact("/nonexistent/file/path.png"))

    # 3. Store append_bulk
    def test_store_append_bulk(self):
        store = Store()
        s = store.create_session("claude", "default", None, None)
        sid = s["id"]
        events_to_add = [
            {"type": "user", "text": "Hello"},
            {"type": "turn.start"},
            {"type": "text.start", "block": "b1"},
            {"type": "text.delta", "block": "b1", "text": "Hi"},
            {"type": "text.end", "block": "b1"},
            {"type": "turn.end", "stopReason": "end_turn"},
        ]
        res = store.append_bulk(sid, events_to_add)
        self.assertEqual(len(res), 6)
        self.assertEqual(res[0]["seq"], 1)
        self.assertEqual(res[-1]["seq"], 6)

        stored = store.events(sid)
        self.assertEqual(len(stored), 6)
        self.assertEqual(stored[0]["text"], "Hello")

    # 4. Bridge restart recovery
    def test_bridge_restart_recovery(self):
        store = Store()
        s1 = store.create_session("claude", "default", None, None)
        store.update_session(s1["id"], status="running")
        s2 = store.create_session("agy", "default", None, None)
        store.update_session(s2["id"], status="requesting")

        # Now start Hub
        hub = Hub()
        sess1 = store.session(s1["id"])
        sess2 = store.session(s2["id"])
        self.assertEqual(sess1["status"], "idle")
        self.assertEqual(sess2["status"], "idle")

        evts1 = store.events(s1["id"])
        self.assertEqual(evts1[-2]["type"], "error")
        self.assertEqual(evts1[-2]["message"], "Bridge restarted")
        self.assertEqual(evts1[-1]["type"], "turn.end")

    # 5. Claude adapter assistant handling and deduplication
    async def test_claude_assistant_dedup_and_errors(self):
        store = Store()
        media = base.Media(store)
        agent = ClaudeAgent(store, media)
        s = store.create_session("claude", "default", None, None)
        emitted = []

        async def emit(ev):
            emitted.append(ev)

        cs = ClaudeSession(agent, s, emit)

        # 1. Streaming arrives for text block 0
        parent = None
        msg_stream = {"parent_tool_use_id": None}
        await cs._stream({"type": "content_block_start", "index": 0, "content_block": {"type": "text"}}, msg_stream, parent)
        await cs._stream({"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "Hello "}}, msg_stream, parent)
        await cs._stream({"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "world!"}}, msg_stream, parent)
        await cs._stream({"type": "content_block_stop", "index": 0}, msg_stream, parent)

        # 2. Assistant message arrives with same text -> should not duplicate!
        assistant_msg = {
            "type": "assistant",
            "message": {
                "content": [
                    {"type": "text", "text": "Hello world!"}
                ]
            }
        }
        await cs._handle(assistant_msg)
        text_deltas = [e["text"] for e in emitted if e["type"] == "text.delta"]
        self.assertEqual(text_deltas, ["Hello ", "world!"])

        # 3. Assistant message arrives with tail text not in stream -> emits remainder!
        emitted.clear()
        cs.streamed_text.clear()
        cs.streamed_ended.clear()
        cs.blocks.clear()
        await cs._stream({"type": "content_block_start", "index": 0, "content_block": {"type": "text"}}, msg_stream, parent)
        await cs._stream({"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "Hello "}}, msg_stream, parent)
        # notice: streaming dropped the rest!
        assistant_msg2 = {
            "type": "assistant",
            "message": {
                "content": [
                    {"type": "text", "text": "Hello world from assistant"}
                ]
            }
        }
        await cs._handle(assistant_msg2)
        text_deltas2 = [e["text"] for e in emitted if e["type"] == "text.delta"]
        self.assertEqual(text_deltas2, ["Hello ", "world from assistant"])

        # 4. API error in assistant message -> emits error
        emitted.clear()
        err_msg = {
            "type": "assistant",
            "error": {"message": "Overloaded"}
        }
        await cs._handle(err_msg)
        errors = [e["message"] for e in emitted if e["type"] == "error"]
        self.assertEqual(errors, ["Overloaded"])

    # 6. Agy adapter thinking start/end, turn block IDs, usage events
    async def test_agy_turn_block_ids_and_thinking(self):
        store = Store()
        media = base.Media(store)
        agent = AgyAgent(store, media)
        s = store.create_session("agy", "default", None, None)
        emitted = []

        async def emit(ev):
            emitted.append(ev)

        session = AgySession(agent, s, emit)
        session.turn = 1
        open_text = set()
        open_thinking = set()

        # Step 0: thinking (ACTIVE emits thinking.start, thinking.delta, status running)
        step0 = {
            "step_type": "agent_response",
            "step_index": 0,
            "state": "ACTIVE",
            "thinking_delta": "Let me think...",
        }
        await session._step(step0, open_text, open_thinking, session.turn)
        self.assertEqual(emitted[0]["type"], "thinking.start")
        self.assertEqual(emitted[0]["block"], "t1-th0")
        self.assertEqual(emitted[1]["type"], "thinking.delta")
        self.assertEqual(emitted[1]["text"], "Let me think...")
        self.assertEqual(emitted[2]["type"], "status")
        self.assertEqual(emitted[2]["state"], "running")

        # Step 0: text delta starts -> closes thinking
        step0_text = {
            "step_type": "agent_response",
            "step_index": 0,
            "state": "ACTIVE",
            "text_delta": "Here is the answer.",
        }
        await session._step(step0_text, open_text, open_thinking, session.turn)
        self.assertEqual(emitted[3]["type"], "thinking.end")
        self.assertEqual(emitted[3]["block"], "t1-th0")
        self.assertEqual(emitted[4]["type"], "text.start")
        self.assertEqual(emitted[4]["block"], "t1-s0")
        self.assertEqual(emitted[5]["type"], "text.delta")

        # Step 0: DONE with usage
        step0_done = {
            "step_type": "agent_response",
            "step_index": 0,
            "state": "DONE",
            "usage": {"input_tokens": 100, "output_tokens": 50, "thinking_tokens": 20},
        }
        await session._step(step0_done, open_text, open_thinking, session.turn)
        self.assertEqual(emitted[7]["type"], "text.end")
        self.assertEqual(emitted[7]["block"], "t1-s0")
        self.assertEqual(emitted[8]["type"], "usage")
        self.assertEqual(emitted[8]["inputTokens"], 100)

        # Turn 2: verify prefix changes to t2-
        session.turn = 2
        emitted.clear()
        open_text.clear()
        open_thinking.clear()
        await session._step(step0, open_text, open_thinking, session.turn)
        self.assertEqual(emitted[0]["block"], "t2-th0")

    # 7. Authorized from Bearer header, linkup_token cookie, linkup cookie, query param
    def test_authorized_tokens(self):
        class DummyRequest:
            def __init__(self, headers=None, cookies=None, query=None):
                self.headers = headers or {}
                self.cookies = cookies or {}
                self.query = query or {}

        hub = Hub()
        tok = hub.token

        # 1. Query param
        req1 = DummyRequest(query={"token": tok})
        self.assertTrue(authorized(req1, hub))

        # 2. Bearer header
        req2 = DummyRequest(headers={"Authorization": f"Bearer {tok}"})
        self.assertTrue(authorized(req2, hub))

        # 3. linkup_token cookie
        req3 = DummyRequest(cookies={"linkup_token": tok})
        self.assertTrue(authorized(req3, hub))

        # 4. linkup cookie
        req4 = DummyRequest(cookies={"linkup": tok})
        self.assertTrue(authorized(req4, hub))

        # 5. Invalid token
        req5 = DummyRequest(headers={"Authorization": "Bearer wrong"})
        self.assertFalse(authorized(req5, hub))

    # 8. Fork of streaming session closes unterminated live turn
    async def test_fork_closes_unterminated_turn(self):
        hub = Hub()
        s = hub.store.create_session("agy", "default", None, None)
        # Append open turn without turn.end
        hub.store.append(s["id"], {"type": "user", "text": "start"})
        hub.store.append(s["id"], {"type": "turn.start"})
        hub.store.append(s["id"], {"type": "text.start", "block": "b1"})
        hub.store.append(s["id"], {"type": "text.delta", "block": "b1", "text": "stream..."})

        # Now fork
        reply = await hub.handle(None, {"op": "fork", "session": s["id"]})
        forked_session = reply["session"]
        forked_events = hub.store.events(forked_session["id"])

        # Unterminated turn must be closed with turn.end in the copy
        self.assertEqual(forked_events[-1]["type"], "turn.end")
        self.assertEqual(forked_events[-1]["stopReason"], "forked")

    # 9. __main__.py unknown subcommand exit 2
    def test_main_unknown_subcommand_exit_2(self):
        import subprocess, sys
        res = subprocess.run([sys.executable, "-m", "linkup_bridge", "invalid_subcmd"],
                             cwd=os.path.join(os.path.dirname(__file__), ".."),
                             capture_output=True, text=True)
        self.assertEqual(res.returncode, 2)
        self.assertIn("usage: python -m linkup_bridge", res.stderr)

    # 10. scripts/make-source.py exit 2 on insufficient args
    def test_make_source_usage_exit_2(self):
        import subprocess, sys
        script = os.path.join(os.path.dirname(__file__), "../../scripts/make-source.py")
        res = subprocess.run([sys.executable, script], capture_output=True, text=True)
        self.assertEqual(res.returncode, 2)
        self.assertIn("usage: make-source.py <Payload/Linkup.app>", res.stderr)


if __name__ == "__main__":
    unittest.main()

