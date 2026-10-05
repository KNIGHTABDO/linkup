
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
