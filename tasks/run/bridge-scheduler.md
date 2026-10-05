Linkup bridge: scheduled prompts

## Your files: `bridge/linkup_bridge/scheduler.py` (replace the stub, keep class/method names and shapes)
Schedule dict: {"id", "title", "agent", "model", "cwd", "prompt", "time": "HH:MM" (local PC time), "days": [1..7]
(1=Monday; empty = every day), "enabled": bool, "lastRun": epoch|None, "nextRun": epoch|None, "lastSessionId"}.
- Persist in `<home>/schedules.json` (atomic write via temp file + os.replace). `save` creates (new id = uuid hex[:12])
  or updates by id, validates time/days/agent ("claude"|"agy"|"hermes") and computes nextRun; `list` returns all
  with fresh nextRun, sorted by nextRun.
- `start()`: create an asyncio task looping every 20 s; when an enabled schedule's nextRun ≤ now, call
  `await self.run(schedule)` (returns the new session dict), store lastRun/lastSessionId, compute the next nextRun.
  Never run the same schedule twice for one slot (also across restarts: compare with lastRun). Exceptions are
  logged and never stop the loop.
- `run_now(id)`: runs immediately (same bookkeeping) and returns the session dict.
Test with a fake `run` coroutine in a temp home directory (time 1 minute ahead) and show the output.

---
# Shared rules for Linkup bridge tasks (Python)
The bridge (`bridge/linkup_bridge/`) is a Python 3.12 aiohttp service on the user's Linux PC (systemd
`linkup-bridge`, venv `~/.linkup/.venv`, data in `~/.linkup`). It drives the user's signed-in CLIs. Read
`bridge/linkup_bridge/server.py` (how your module is called), `store.py` and the stub you replace FIRST.
- Only edit the files your task lists. Keep every function name/signature/return shape in the stub exactly.
- No new dependencies beyond the stdlib and aiohttp (already installed). Never print secrets.
- Use `asyncio.create_subprocess_exec` for commands (never shell=True with user input), timeouts on everything,
  and never block the event loop (wrap blocking work in `asyncio.to_thread` if you call it from async code).
- Verify for real on this PC: run your functions with `~/.linkup/.venv/bin/python -c ...` from `bridge/` and show the
  output in your final message. Do NOT restart the systemd service (Claude does that when merging).
- Commit only your files when done.
