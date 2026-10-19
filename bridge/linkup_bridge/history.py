"""Claude Code and Pi sessions started on the PC: listed so the phone can pick any of them
up and continue it (`claude --resume <id>` or `pi --session <path>`), with their history converted to Linkup events."""
from __future__ import annotations

import glob
import json
import os
import re

ROOT = os.path.expanduser("~/.claude/projects")
PI_ROOT = os.path.expanduser("~/.pi/agent/sessions")
UUID_RE = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")

# (path, mtime) -> (title, cwd, message_count)
_TITLE_CACHE: dict[tuple[str, float], tuple[str, str | None, int]] = {}


def is_valid_native_id(native_id: str) -> bool:
    if not native_id:
        return False
    if UUID_RE.match(native_id):
        return True
    if os.path.isabs(native_id) and native_id.endswith(".jsonl"):
        real = os.path.realpath(native_id)
        pi_real = os.path.realpath(PI_ROOT)
        return real.startswith(pi_real + os.sep) and os.path.isfile(real)
    return False


def _text(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(p.get("text", "") for p in content if isinstance(p, dict) and p.get("type") == "text")
    return ""


def _is_real_prompt(text: str) -> bool:
    t = text.strip()
    return bool(t) and not t.startswith(("<command-", "<local-command", "<system-reminder", "Caveat:", "[Request interrupted"))


def _safe_mtime(p: str) -> float:
    try:
        return os.path.getmtime(p)
    except OSError:
        return 0.0


def list_sessions(limit: int = 80) -> list[dict]:
    raw_claude = glob.glob(os.path.join(ROOT, "*", "*.jsonl"))
    raw_pi = glob.glob(os.path.join(PI_ROOT, "*", "*.jsonl"))

    all_files = [(p, "claude") for p in raw_claude] + [(p, "pi") for p in raw_pi]
    all_files.sort(key=lambda item: _safe_mtime(item[0]), reverse=True)

    out = []
    for path, agent in all_files[:limit * 3]:
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            continue

        if agent == "claude":
            basename = os.path.splitext(os.path.basename(path))[0]
            if not UUID_RE.match(basename):
                continue
            native_id = basename
        else:
            native_id = path

        cached = _TITLE_CACHE.get((path, mtime))
        if cached is not None:
            title, cwd, count = cached
        else:
            title, cwd, count = None, None, 0
            try:
                with open(path, errors="replace") as f:
                    for i, line in enumerate(f):
                        if i > 4000:
                            break
                        try:
                            d = json.loads(line)
                        except (ValueError, TypeError):
                            continue
                        if not isinstance(d, dict):
                            continue

                        if agent == "claude":
                            cwd = cwd or d.get("cwd")
                            msg = d.get("message")
                            if not isinstance(msg, dict):
                                msg = {}
                            if d.get("type") == "user" and not d.get("isMeta"):
                                txt = _text(msg.get("content"))
                                if _is_real_prompt(txt):
                                    count += 1
                                    title = title or txt.strip().splitlines()[0][:90]
                            if d.get("type") == "summary" and d.get("summary"):
                                title = d["summary"][:90]
                        else:  # pi
                            if d.get("type") == "session":
                                cwd = cwd or d.get("cwd")
                            elif d.get("type") == "message":
                                msg = d.get("message")
                                if isinstance(msg, dict) and msg.get("role") == "user":
                                    txt = _text(msg.get("content"))
                                    if _is_real_prompt(txt):
                                        count += 1
                                        title = title or txt.strip().splitlines()[0][:90]
            except OSError:
                continue

            if title:
                _TITLE_CACHE[(path, mtime)] = (title, cwd, count)

        if not title:
            continue

        out.append({
            "agent": agent,
            "nativeId": native_id,
            "title": title,
            "cwd": cwd,
            "updated": mtime,
            "messages": count,
        })
        if len(out) >= limit:
            break

    out.sort(key=lambda s: s.get("updated", 0), reverse=True)
    return out[:limit]


def _claude_events(native_id: str) -> list[dict]:
    paths = glob.glob(os.path.join(ROOT, "*", f"{native_id}.jsonl"))
    if not paths:
        return []
    out = []
    try:
        with open(paths[0], errors="replace") as f:
            for line in f:
                try:
                    d = json.loads(line)
                except (ValueError, TypeError):
                    continue
                if not isinstance(d, dict):
                    continue
                msg = d.get("message")
                if not isinstance(msg, dict):
                    msg = {}
                content = msg.get("content")
                if d.get("type") == "user" and not d.get("isMeta"):
                    if isinstance(content, list) and any(isinstance(p, dict) and p.get("type") == "tool_result" for p in content):
                        for p in content:
                            if isinstance(p, dict) and p.get("type") == "tool_result":
                                out.append({"type": "tool.end", "id": p.get("tool_use_id"), "output": _text(p.get("content"))[:20000]
                                            if not isinstance(p.get("content"), str) else p["content"][:20000],
                                            "isError": bool(p.get("is_error")), "images": [], "imported": True})
                        continue
                    txt = _text(content)
                    if _is_real_prompt(txt):
                        out.append({"type": "user", "text": txt, "attachments": [], "imported": True})
                        out.append({"type": "turn.start", "imported": True})
                elif d.get("type") == "assistant" and isinstance(content, list):
                    for i, p in enumerate(content):
                        if not isinstance(p, dict):
                            continue
                        bid = f"{d.get('uuid', '')}:{i}"
                        if p.get("type") == "thinking" and p.get("thinking"):
                            out += [{"type": "thinking.start", "block": bid}, {"type": "thinking.delta", "block": bid,
                                    "text": p["thinking"]}, {"type": "thinking.end", "block": bid}]
                        elif p.get("type") == "text" and p.get("text"):
                            out += [{"type": "text.start", "block": bid}, {"type": "text.delta", "block": bid, "text": p["text"]},
                                    {"type": "text.end", "block": bid}]
                        elif p.get("type") == "tool_use":
                            out.append({"type": "tool.start", "id": p.get("id"), "name": p.get("name"),
                                        "input": p.get("input") if isinstance(p.get("input"), dict) else {}})
    except OSError:
        return []

    final = []
    open_turn = False
    for e in out:
        if e["type"] == "user" and open_turn:
            final.append({"type": "turn.end", "stopReason": "end_turn", "imported": True})
        if e["type"] == "turn.start":
            open_turn = True
        final.append(e)
    if open_turn:
        final.append({"type": "turn.end", "stopReason": "end_turn", "imported": True})
    return final


def _pi_events(path: str) -> list[dict]:
    if not os.path.isfile(path):
        return []
    out = []
    try:
        with open(path, errors="replace") as f:
            for line in f:
                try:
                    d = json.loads(line)
                except (ValueError, TypeError):
                    continue
                if not isinstance(d, dict) or d.get("type") != "message":
                    continue
                msg = d.get("message")
                if not isinstance(msg, dict):
                    continue
                role = msg.get("role")
                content = msg.get("content")
                if role == "user":
                    txt = _text(content)
                    if _is_real_prompt(txt):
                        out.append({"type": "user", "text": txt, "attachments": [], "imported": True})
                        out.append({"type": "turn.start", "imported": True})
                elif role == "assistant":
                    if isinstance(content, list):
                        for i, p in enumerate(content):
                            if not isinstance(p, dict):
                                continue
                            bid = f"{d.get('id', '')}:{i}"
                            ptype = p.get("type")
                            if ptype == "thinking" and p.get("thinking"):
                                out += [
                                    {"type": "thinking.start", "block": bid},
                                    {"type": "thinking.delta", "block": bid, "text": p["thinking"]},
                                    {"type": "thinking.end", "block": bid},
                                ]
                            elif ptype == "text" and p.get("text"):
                                out += [
                                    {"type": "text.start", "block": bid},
                                    {"type": "text.delta", "block": bid, "text": p["text"]},
                                    {"type": "text.end", "block": bid},
                                ]
                            elif ptype == "toolCall":
                                out.append({
                                    "type": "tool.start",
                                    "id": p.get("id"),
                                    "name": p.get("name"),
                                    "input": p.get("arguments") if isinstance(p.get("arguments"), dict) else {},
                                })
                elif role == "toolResult":
                    out_text = _text(content)
                    out.append({
                        "type": "tool.end",
                        "id": msg.get("toolCallId"),
                        "output": out_text[:20000],
                        "isError": bool(msg.get("isError")),
                        "images": [],
                        "imported": True,
                    })
                elif role == "bashExecution":
                    bid = d.get("id") or "bash"
                    out.append({
                        "type": "tool.start",
                        "id": bid,
                        "name": "bash",
                        "input": {"command": msg.get("command", "")},
                    })
                    out.append({
                        "type": "tool.end",
                        "id": bid,
                        "output": (msg.get("output") or "")[:20000],
                        "isError": msg.get("exitCode") != 0,
                        "images": [],
                        "imported": True,
                    })
    except OSError:
        return []

    final = []
    open_turn = False
    for e in out:
        if e["type"] == "user" and open_turn:
            final.append({"type": "turn.end", "stopReason": "end_turn", "imported": True})
        if e["type"] == "turn.start":
            open_turn = True
        final.append(e)
    if open_turn:
        final.append({"type": "turn.end", "stopReason": "end_turn", "imported": True})
    return final


def events(native_id: str) -> list[dict]:
    """The conversation as Linkup events (user text, thinking, text, tool calls and results)."""
    if not is_valid_native_id(native_id):
        return []
    if native_id.endswith(".jsonl"):
        return _pi_events(native_id)
    return _claude_events(native_id)


def load_for_import(native_id: str) -> tuple[dict, list[dict]]:
    """Loads session metadata and events together for import."""
    if not is_valid_native_id(native_id):
        return {}, []
    info = next((h for h in list_sessions(200) if h["nativeId"] == native_id), {})
    evts = events(native_id)
    return info, evts
