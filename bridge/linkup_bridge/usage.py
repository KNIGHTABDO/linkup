"""STUB (task bridge-usage): live plan usage, polled every minute by the hub."""
from __future__ import annotations


async def claude_plan() -> dict | None:
    """{"fiveHour": {"utilization": 0..1, "resetsAt": epoch}, "sevenDay": {...}, "sevenDayOpus": {...} | None,
    "sevenDaySonnet": {...} | None, "subscription": "Claude Pro", "at": epoch} or None if unavailable."""
    return None


async def agy_usage() -> dict | None:
    """{"credits": "Out of credits" | "1,240 credits" | None, "status": str | None,
    "models": [{"name": str, "remaining": 0..1 | None, "resetsAt": epoch | None}], "at": epoch} or None."""
    return None
