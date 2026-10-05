Linkup bridge: slash commands and skills for Antigravity and Hermes

## Your files: `bridge/linkup_bridge/commands.py` (replace the stub, keep `agy_commands()` / `hermes_commands()`)
Return `[{"name": "<name without slash>", "description": "...", "kind": "command"|"skill"|"agent"|"plugin"}]`,
deduplicated by name, sorted (commands, then skills, agents, plugins; then by name), max 300.
- Antigravity (`agy`): find its real slash commands and skills. Explore: `agy --help`, `agy agents`, `agy plugin list`,
  `agy mcp list`, the directories `~/.gemini/antigravity-cli/builtin`, `~/.gemini/config/plugins`, `~/.gemini/antigravity`,
  `~/.gemini/skills` (if present) and any SKILL.md files (frontmatter `name:` / `description:`). Built-in TUI slash
  commands: discover them for real (e.g. run `agy` in a pty and type "/" — or find them in the builtin folder);
  do not invent commands. Cache results for 10 minutes (module-level). Must finish within 25 s (timeouts).
- Hermes: skills under `~/.hermes/skills/**/SKILL.md` (frontmatter name/description; folder name as fallback) plus
  Hermes' own gateway slash commands if you can find them in `~/.hermes/hermes-agent` (e.g. a commands registry in
  `hermes_cli` or `gateway`); read the source, don't guess.
Show real output counts and samples in your final message.

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
