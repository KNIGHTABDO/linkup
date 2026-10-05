"""Scheduled prompts for Linkup bridge."""
from __future__ import annotations

import asyncio
from datetime import datetime, timedelta
import json
import logging
import os
import time
import uuid

log = logging.getLogger("linkup.scheduler")

VALID_AGENTS = {"claude", "agy", "hermes"}


class Scheduler:
    """Persists schedules in <home>/schedules.json and calls `run(schedule) -> session dict` when one is due."""

    def __init__(self, home: str, run):
        self.home = home
        self.run = run
        self.path = os.path.join(self.home, "schedules.json")
        self._schedules: dict[str, dict] = {}
        self._mtime: float = 0.0
        self._task: asyncio.Task | None = None
        self._load()

    def _load(self) -> None:
        if not os.path.exists(self.path):
            self._schedules = {}
            self._mtime = 0.0
            return
        try:
            mtime = os.path.getmtime(self.path)
            with open(self.path, "r", encoding="utf-8") as f:
                data = json.load(f)
            schedules: dict[str, dict] = {}
            if isinstance(data, list):
                for item in data:
                    if isinstance(item, dict) and "id" in item:
                        schedules[item["id"]] = item
            elif isinstance(data, dict):
                if "schedules" in data and isinstance(data["schedules"], list):
                    for item in data["schedules"]:
                        if isinstance(item, dict) and "id" in item:
                            schedules[item["id"]] = item
                else:
                    for k, v in data.items():
                        if isinstance(v, dict):
                            sid = v.get("id") or k
                            v["id"] = sid
                            schedules[sid] = v
            self._schedules = schedules
            self._mtime = mtime
        except Exception as exc:
            log.warning("Failed to load schedules from %s: %s", self.path, exc)
            self._schedules = {}

    def _check_reload(self) -> None:
        if os.path.exists(self.path):
            try:
                mtime = os.path.getmtime(self.path)
                if mtime > self._mtime:
                    self._load()
            except OSError:
                pass

    def _save(self) -> None:
        os.makedirs(self.home, exist_ok=True)
        tmp_path = os.path.join(self.home, f".schedules.json.{uuid.uuid4().hex}.tmp")
        data = list(self._schedules.values())
        try:
            with open(tmp_path, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
            os.replace(tmp_path, self.path)
            self._mtime = os.path.getmtime(self.path)
        except Exception as exc:
            log.error("Failed to save schedules to %s: %s", self.path, exc)
            if os.path.exists(tmp_path):
                try:
                    os.remove(tmp_path)
                except OSError:
                    pass
            raise

    def compute_next_run(self, schedule: dict, from_time: float | None = None) -> float:
        """Computes the next epoch timestamp (in local time) matching schedule's time and days."""
        time_str = schedule.get("time", "")
        parts = time_str.split(":")
        hour, minute = int(parts[0]), int(parts[1])
        days = schedule.get("days") or []
        allowed_days = set(days) if days else set(range(1, 8))

        from_ts = from_time if from_time is not None else time.time()
        current_dt = datetime.fromtimestamp(from_ts)

        for offset in range(14):
            candidate_date = current_dt.date() + timedelta(days=offset)
            if candidate_date.isoweekday() not in allowed_days:
                continue
            candidate_dt = datetime(candidate_date.year, candidate_date.month, candidate_date.day, hour, minute, 0)
            candidate_ts = candidate_dt.timestamp()
            if candidate_ts > from_ts:
                return candidate_ts

        return from_ts + 86400.0

    def _fresh_next_run(self, schedule: dict, now: float) -> float:
        next_run = schedule.get("nextRun")
        last_run = schedule.get("lastRun")
        if next_run is None:
            return self.compute_next_run(schedule, from_time=now)
        if last_run is not None and last_run >= next_run:
            return self.compute_next_run(schedule, from_time=max(now, last_run))
        if not schedule.get("enabled") and next_run <= now:
            return self.compute_next_run(schedule, from_time=now)
        if now - next_run > 86400.0:
            return self.compute_next_run(schedule, from_time=now)
        return next_run

    def list(self) -> list[dict]:
        self._check_reload()
        now = time.time()
        dirty = False
        for s in self._schedules.values():
            fresh = self._fresh_next_run(s, now)
            if fresh != s.get("nextRun"):
                s["nextRun"] = fresh
                dirty = True
        if dirty:
            self._save()
        return [dict(s) for s in sorted(self._schedules.values(), key=lambda s: (s.get("nextRun") is None, s.get("nextRun") or 0))]

    def save(self, schedule: dict) -> dict:
        self._check_reload()
        sid = schedule.get("id")
        existing = self._schedules.get(sid, {}) if sid else {}

        # Validate agent
        agent = schedule.get("agent") or existing.get("agent")
        if agent not in VALID_AGENTS:
            raise ValueError(f"Invalid agent '{agent}', expected one of {sorted(VALID_AGENTS)}")

        # Validate time
        raw_time = schedule.get("time") if "time" in schedule else existing.get("time")
        if not isinstance(raw_time, str):
            raise ValueError("Time must be a string 'HH:MM'")
        parts = raw_time.split(":")
        if len(parts) != 2:
            raise ValueError(f"Invalid time format '{raw_time}', expected 'HH:MM'")
        try:
            hour, minute = int(parts[0]), int(parts[1])
        except ValueError:
            raise ValueError(f"Invalid time format '{raw_time}', expected integers 'HH:MM'")
        if not (0 <= hour <= 23 and 0 <= minute <= 59):
            raise ValueError(f"Time out of range '{raw_time}', hour must be 0-23 and minute 0-59")
        norm_time = f"{hour:02d}:{minute:02d}"

        # Validate days
        raw_days = schedule.get("days") if "days" in schedule else existing.get("days", [])
        if raw_days is None:
            norm_days: list[int] = []
        elif not isinstance(raw_days, (list, tuple)):
            raise ValueError("Days must be a list of integers 1..7 (1=Monday)")
        else:
            norm_days = []
            for d in raw_days:
                if not isinstance(d, int) or isinstance(d, bool) or not (1 <= d <= 7):
                    raise ValueError(f"Invalid day '{d}', days must be integers 1..7 (1=Monday)")
                if d not in norm_days:
                    norm_days.append(d)
            norm_days.sort()

        final_id = sid or uuid.uuid4().hex[:12]
        title = str(schedule.get("title") if "title" in schedule else existing.get("title", ""))
        prompt = str(schedule.get("prompt") if "prompt" in schedule else existing.get("prompt", ""))
        model = schedule["model"] if "model" in schedule else existing.get("model")
        cwd = schedule["cwd"] if "cwd" in schedule else existing.get("cwd")
        enabled = bool(schedule["enabled"]) if "enabled" in schedule else bool(existing.get("enabled", True))
        last_run = schedule["lastRun"] if "lastRun" in schedule else existing.get("lastRun")
        last_session_id = schedule["lastSessionId"] if "lastSessionId" in schedule else existing.get("lastSessionId")

        item = {
            "id": final_id,
            "title": title,
            "agent": agent,
            "model": model,
            "cwd": cwd,
            "prompt": prompt,
            "time": norm_time,
            "days": norm_days,
            "enabled": enabled,
            "lastRun": last_run,
            "nextRun": None,
            "lastSessionId": last_session_id,
        }
        item["nextRun"] = self.compute_next_run(item, from_time=time.time())
        self._schedules[final_id] = item
        self._save()
        return dict(item)

    def delete(self, sid: str) -> None:
        self._check_reload()
        if sid in self._schedules:
            del self._schedules[sid]
            self._save()

    async def run_now(self, sid: str) -> dict | None:
        self._check_reload()
        schedule = self._schedules.get(sid)
        if not schedule:
            return None
        res = self.run(schedule)
        session = await res if asyncio.iscoroutine(res) else res
        now = time.time()
        schedule["lastRun"] = now
        schedule["lastSessionId"] = session.get("id") if isinstance(session, dict) else None
        schedule["nextRun"] = self.compute_next_run(schedule, from_time=now)
        self._save()
        return session

    def start(self, interval: float = 20.0) -> None:
        """Starts the background loop (asyncio task) that fires due schedules."""
        if self._task is None or self._task.done():
            self._task = asyncio.create_task(self._loop(interval))

    def stop(self) -> None:
        """Stops the background loop."""
        if self._task is not None and not self._task.done():
            self._task.cancel()
            self._task = None

    async def _loop(self, interval: float = 20.0) -> None:
        while True:
            try:
                await self._tick()
            except asyncio.CancelledError:
                break
            except Exception as exc:
                log.exception("Scheduler tick failed: %s", exc)
            try:
                await asyncio.sleep(interval)
            except asyncio.CancelledError:
                break

    async def _tick(self) -> None:
        now = time.time()
        self._check_reload()
        for schedule in list(self._schedules.values()):
            if not schedule.get("enabled"):
                continue
            next_run = schedule.get("nextRun")
            if next_run is None or next_run > now:
                continue

            last_run = schedule.get("lastRun")
            if last_run is not None and last_run >= next_run:
                # Slot has already been run (e.g. across restart)
                schedule["nextRun"] = self.compute_next_run(schedule, from_time=now)
                self._save()
                continue

            run_time = time.time()
            try:
                res = self.run(schedule)
                session = await res if asyncio.iscoroutine(res) else res
                run_time = time.time()
                schedule["lastRun"] = run_time
                schedule["lastSessionId"] = session.get("id") if isinstance(session, dict) else None
            except Exception as exc:
                log.exception("Scheduled run failed for %s: %s", schedule.get("id"), exc)
                run_time = time.time()
                schedule["lastRun"] = run_time
            finally:
                schedule["nextRun"] = self.compute_next_run(schedule, from_time=run_time)
                self._save()
