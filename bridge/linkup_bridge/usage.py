"""Live plan usage for Claude Code and Antigravity, polled by the hub."""
from __future__ import annotations

import asyncio
from datetime import datetime
import fcntl
import json
import logging
import os
import pty
import re
import select
import shutil
import signal
import struct
import subprocess
import termios
import time

import aiohttp

log = logging.getLogger("linkup.usage")

CLAUDE_CREDS_PATH = os.path.expanduser("~/.claude/.credentials.json")
AGY_BIN_DEFAULT = os.path.expanduser("~/.local/bin/agy")
ANSI_RE = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~]|\([a-zA-Z])")

_claude_auth_logged = False


def _parse_window(data: dict | None) -> dict | None:
    if not data or not isinstance(data, dict):
        return None
    utilization = data.get("utilization")
    resets_at = data.get("resets_at")
    if utilization is None and resets_at is None:
        return None
    util = round(float(utilization) / 100.0, 4) if utilization is not None else None
    resets_epoch = None
    if isinstance(resets_at, str):
        try:
            resets_epoch = datetime.fromisoformat(resets_at).timestamp()
        except Exception:
            pass
    elif isinstance(resets_at, (int, float)):
        resets_epoch = float(resets_at)
    return {
        "utilization": util,
        "resetsAt": resets_epoch,
    }


def _prettify_subscription(sub: str | None) -> str | None:
    if not sub:
        return None
    s = sub.strip()
    mapping = {
        "pro": "Claude Pro",
        "team": "Claude Team",
        "enterprise": "Claude Enterprise",
        "free": "Claude Free",
        "max": "Claude Max",
    }
    key = s.lower()
    if key in mapping:
        return mapping[key]
    if key.startswith("claude"):
        return s.title()
    return f"Claude {s.title()}"


async def claude_plan() -> dict | None:
    """{"fiveHour": {"utilization": 0..1, "resetsAt": epoch}, "sevenDay": {...}, "sevenDayOpus": {...} | None,
    "sevenDaySonnet": {...} | None, "subscription": "Claude Pro", "at": epoch} or None if unavailable."""
    global _claude_auth_logged
    if not os.path.exists(CLAUDE_CREDS_PATH):
        return None

    try:
        with open(CLAUDE_CREDS_PATH, "r", encoding="utf-8") as f:
            creds = json.load(f)
    except Exception as exc:
        log.warning("Failed to read Claude credentials: %s", exc)
        return None

    oauth = creds.get("claudeAiOauth")
    if not isinstance(oauth, dict):
        return None

    token = oauth.get("accessToken")
    if not token or not isinstance(token, str):
        return None

    expires_at = oauth.get("expiresAt")
    if expires_at and isinstance(expires_at, (int, float)):
        if (expires_at / 1000.0) <= time.time():
            if not _claude_auth_logged:
                log.warning("Claude credentials token is expired; waiting for CLI refresh on next normal use")
                _claude_auth_logged = True
            return None

    subscription = _prettify_subscription(oauth.get("subscriptionType"))

    headers = {
        "Authorization": f"Bearer {token}",
        "anthropic-beta": "oauth-2025-04-20",
        "User-Agent": "claude-code",
    }
    timeout = aiohttp.ClientTimeout(total=10)
    try:
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.get("https://api.anthropic.com/api/oauth/usage", headers=headers) as resp:
                if resp.status == 401:
                    if not _claude_auth_logged:
                        log.warning("Claude usage returned 401 Unauthorized; waiting for CLI refresh on next normal use")
                        _claude_auth_logged = True
                    return None
                if resp.status != 200:
                    log.warning("Claude usage endpoint returned status %d", resp.status)
                    return None
                data = await resp.json()
    except Exception as exc:
        log.warning("Failed to fetch Claude plan usage: %s", exc)
        return None

    _claude_auth_logged = False

    return {
        "fiveHour": _parse_window(data.get("five_hour")),
        "sevenDay": _parse_window(data.get("seven_day")),
        "sevenDayOpus": _parse_window(data.get("seven_day_opus")),
        "sevenDaySonnet": _parse_window(data.get("seven_day_sonnet")),
        "subscription": subscription,
        "at": time.time(),
    }


def _capture_agy_pty() -> str | None:
    agy_path = os.environ.get("LINKUP_AGY") or shutil.which("agy") or AGY_BIN_DEFAULT
    if not os.path.exists(agy_path) and not shutil.which(agy_path):
        return None

    master, slave = pty.openpty()
    proc = None
    output_chunks: list[bytes] = []
    start = time.time()
    last_ai_time: float | None = None

    try:
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 200, 0, 0))
        proc = subprocess.Popen(
            [agy_path],
            stdin=slave,
            stdout=slave,
            stderr=slave,
            cwd=os.path.expanduser("~"),
            env={**os.environ, "TERM": "xterm-256color", "COLUMNS": "200", "LINES": "50"},
            preexec_fn=os.setsid,
            close_fds=True,
        )
        os.close(slave)
        slave = -1

        while time.time() - start < 12.0:
            r, _, _ = select.select([master], [], [], 0.25)
            if master in r:
                try:
                    data = os.read(master, 4096)
                    if not data:
                        break
                    output_chunks.append(data)
                    if b"AI:" in data:
                        last_ai_time = time.time()
                except OSError:
                    break
            if last_ai_time is not None and (time.time() - last_ai_time > 2.0):
                break
    except Exception as exc:
        log.warning("agy pty capture failed: %s", exc)
        return None
    finally:
        if slave >= 0:
            try:
                os.close(slave)
            except OSError:
                pass
        if master >= 0:
            try:
                os.write(master, b"\x03")
                time.sleep(0.1)
                os.write(master, b"\x03")
                time.sleep(0.1)
            except OSError:
                pass
        if proc:
            pgid = None
            try:
                pgid = os.getpgid(proc.pid)
            except OSError:
                pass
            try:
                if pgid:
                    os.killpg(pgid, signal.SIGTERM)
                else:
                    proc.terminate()
                proc.wait(timeout=0.5)
            except Exception:
                try:
                    if pgid:
                        os.killpg(pgid, signal.SIGKILL)
                    else:
                        proc.kill()
                    proc.wait(timeout=0.5)
                except Exception:
                    pass
        if master >= 0:
            try:
                os.close(master)
            except OSError:
                pass

    raw = b"".join(output_chunks).decode("utf-8", errors="replace")
    stripped = ANSI_RE.sub("", raw)
    matches: list[str] = []
    for line in stripped.splitlines():
        if "AI:" in line:
            part = line.split("AI:", 1)[1].strip()
            if part:
                matches.append(part)
    return matches[-1] if matches else None


async def agy_usage() -> dict | None:
    """{"credits": "Out of credits" | "1,240 credits" | None, "status": str | None,
    "models": [{"name": str, "remaining": 0..1 | None, "resetsAt": epoch | None}], "at": epoch} or None."""
    try:
        credits_text = await asyncio.wait_for(asyncio.to_thread(_capture_agy_pty), timeout=20.0)
    except Exception as exc:
        log.warning("agy_usage timed out or failed: %s", exc)
        return None

    if credits_text is None:
        return None

    credits_lower = credits_text.lower()
    if "out of" in credits_lower:
        status = "out"
    elif any(ch.isdigit() for ch in credits_text) or "credit" in credits_lower or "available" in credits_lower or "ok" in credits_lower:
        status = "ok"
    else:
        status = "unknown"

    return {
        "credits": credits_text,
        "status": status,
        "models": [],
        "at": time.time(),
    }
