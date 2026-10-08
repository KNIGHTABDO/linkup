"""Claude Code sessions started on the PC (~/.claude/projects/*/<id>.jsonl): listed so the phone can pick any of them
up and continue it (`claude --resume <id>`), with their history converted to Linkup events."""
from __future__ import annotations

import glob
import json
import os
import re

ROOT = os.path.expanduser("~/.claude/projects")
UUID_RE = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")

# (path, mtime) -> (title, cwd, message_count)
_TITLE_CACHE: dict[tuple[str, float], tuple[str, str | None, int]] = {}


def is_valid_native_id(native_id: str) -> bool:
    return bool(native_id and UUID_RE.match(native_id))


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
    raw_files = glob.glob(os.path.join(ROOT, "*", "*.jsonl"))
    files = sorted(raw_files, key=_safe_mtime, reverse=True)[:limit * 2]
    out = []
    for path in files:
        basename = os.path.splitext(os.path.basename(path))[0]
        if not is_valid_native_id(basename):
            continue
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            continue

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
            except OSError:
                continue
            if title:
                _TITLE_CACHE[(path, mtime)] = (title, cwd, count)

        if not title:
            continue
        out.append({"nativeId": basename, "title": title, "cwd": cwd,
                    "updated": mtime, "messages": count})
        if len(out) >= limit:
            break
    return out


def events(native_id: str) -> list[dict]:
    """The conversation as Linkup events (user text, thinking, text, tool calls and results)."""
    if not is_valid_native_id(native_id):
        return []
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
    # Close every imported turn so the phone renders them as finished.
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


def load_for_import(native_id: str) -> tuple[dict, list[dict]]:
    """Loads session metadata and events together for import."""
    if not is_valid_native_id(native_id):
        return {}, []
    info = next((h for h in list_sessions(200) if h["nativeId"] == native_id), {})
    evts = events(native_id)
    return info, evts
