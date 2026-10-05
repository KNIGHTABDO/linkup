"""STUB (task bridge-scheduler): scheduled prompts (e.g. every morning at 8)."""
from __future__ import annotations


class Scheduler:
    """Persists schedules in <home>/schedules.json and calls `run(schedule) -> session dict` when one is due."""

    def __init__(self, home: str, run):
        self.home = home
        self.run = run

    def list(self) -> list[dict]:
        return []

    def save(self, schedule: dict) -> dict:
        raise NotImplementedError

    def delete(self, sid: str) -> None:
        raise NotImplementedError

    async def run_now(self, sid: str) -> dict | None:
        raise NotImplementedError

    def start(self) -> None:
        """Starts the background loop (asyncio task) that fires due schedules."""
        return
