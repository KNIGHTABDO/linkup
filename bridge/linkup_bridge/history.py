"""Claude Code sessions started on the PC (~/.claude/projects/*/<id>.jsonl): listed so the phone can pick any of them
up and continue it (`claude --resume <id>`), with their history converted to Linkup events."""
from __future__ import annotations

import glob
import json
import os

ROOT = os.path.expanduser("~/.claude/projects")


def _text(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(p.get("text", "") for p in content if isinstance(p, dict) and p.get("type") == "text")
    return ""


def _is_real_prompt(text: str) -> bool:
    t = text.strip()
    return bool(t) and not t.startswith(("<command-", "<local-command", "<system-reminder", "Caveat:", "[Request interrupted"))


def list_sessions(limit: int = 80) -> list[dict]:
    files = sorted(glob.glob(os.path.join(ROOT, "*", "*.jsonl")), key=os.path.getmtime, reverse=True)[:limit * 2]
    out = []
    for path in files:
        title, cwd, count = None, None, 0
        try:
            with open(path, errors="replace") as f:
                for i, line in enumerate(f):
                    if i > 4000:
                        break
                    try:
                        d = json.loads(line)
                    except ValueError:
                        continue
                    cwd = cwd or d.get("cwd")
                    if d.get("type") == "user" and not d.get("isMeta"):
                        txt = _text((d.get("message") or {}).get("content"))
                        if _is_real_prompt(txt):
                            count += 1
                            title = title or txt.strip().splitlines()[0][:90]
                    if d.get("type") == "summary" and d.get("summary"):
                        title = d["summary"][:90]
        except OSError:
            continue
        if not title:
            continue
        out.append({"nativeId": os.path.splitext(os.path.basename(path))[0], "title": title, "cwd": cwd,
                    "updated": os.path.getmtime(path), "messages": count})
        if len(out) >= limit:
            break
    return out


def events(native_id: str) -> list[dict]:
    """The conversation as Linkup events (user text, thinking, text, tool calls and results)."""
    paths = glob.glob(os.path.join(ROOT, "*", f"{native_id}.jsonl"))
    if not paths:
        return []
    out = []
    with open(paths[0], errors="replace") as f:
        for line in f:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            msg = d.get("message") or {}
            content = msg.get("content")
            if d.get("type") == "user" and not d.get("isMeta"):
                if isinstance(content, list) and any(isinstance(p, dict) and p.get("type") == "tool_result" for p in content):
                    for p in content:
                        if p.get("type") == "tool_result":
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
                    bid = f"{d.get('uuid', '')}:{i}"
                    if p.get("type") == "thinking" and p.get("thinking"):
                        out += [{"type": "thinking.start", "block": bid}, {"type": "thinking.delta", "block": bid,
                                "text": p["thinking"]}, {"type": "thinking.end", "block": bid}]
                    elif p.get("type") == "text" and p.get("text"):
                        out += [{"type": "text.start", "block": bid}, {"type": "text.delta", "block": bid, "text": p["text"]},
                                {"type": "text.end", "block": bid}]
                    elif p.get("type") == "tool_use":
                        out.append({"type": "tool.start", "id": p.get("id"), "name": p.get("name"),
                                    "input": p.get("input") or {}})
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
