Add the Pi agent to the Linkup bridge

## Goal
Pi (https://github.com/badlogic/pi-mono, npm `@mariozechner/pi-coding-agent`, v0.73.1) is a coding agent like Claude Code.
It is installed at `~/.local/bin/pi` (needs `node` in PATH) and is already signed in via `~/.pi/agent` (settings.json,
models.json, auth.json, skills/extensions). Add it as a 4th agent `id = "pi"`, name "Pi", with the SAME capabilities the
other agents have in the app: live model list + thinking levels, streaming text/thinking, tool cards, images in and out,
artifacts, `linkup:send`, interrupt, slash commands/skills, usage, scheduler, session resume, idle reaping.

## Read FIRST (contracts — do not invent APIs)
- `bridge/linkup_bridge/agents/claude.py` (closest model: one long-lived process per session, `pid` property, `close()`,
  `interrupt()`, `set_mode()`, `resolve_permission()`, usage events, `paths_in`/`Media.artifact` artifact detection,
  `SEND_PROMPT`, image attachments) and `agents/base.py` (the NORMALIZED EVENT VOCABULARY — emit exactly those events),
  `agents/hermes.py` (smaller adapter), `server.py` (Hub: agents dict, `submit`, `catalog`, `runtime`, idle reaper,
  usage totals, how sessions are resumed with `native_id`), `scheduler.py` (`VALID_AGENTS`), `commands.py`,
  `store.py`, `history.py`.
- Pi RPC docs: `~/.local/lib/node_modules/@mariozechner/pi-coding-agent/docs/rpc.md` (and `json.md`, `sessions.md`,
  `session-format.md`). A REAL captured RPC trace is in `tasks/pi-rpc-sample.jsonl` (get_state, get_available_models,
  get_commands, a prompt with a bash tool call). Probe more yourself by piping JSON lines into
  `pi --mode rpc --no-session` (strict JSONL, split on "\n" ONLY — do not use a reader that splits on U+2028/2029;
  with asyncio use `readline()` on a StreamReader created with a big `limit=64<<20`).

## Files you may edit
NEW `bridge/linkup_bridge/agents/pi.py`; and small, surgical edits in `server.py` (import + register `PiAgent` in the Hub
agents dict; SEND_PROMPT injection for `s["agent"] == "pi"` like agy; `commands` for pi in `catalog()`; CARDS handling is
already generic; usage totals/any per-agent lists that mention "claude/agy/hermes" — grep for them and add "pi"),
`scheduler.py` (`VALID_AGENTS`), `commands.py` (add `pi_commands()` if you choose to use the catalog route), `history.py`
(only if you add pi session import, see 8), `workspace.py` (nothing unless a per-agent list needs "pi"),
and `README.md`/`CLAUDE.md` one-line mentions. Another agent is editing the iOS app at the same time — do not touch `ios/`.

## Behaviour to implement (verify each against the real `pi`)
1. **Catalog** `PiAgent.catalog(force)` (cache 10 min): spawn `pi --mode rpc --no-session`, send `get_available_models`,
   `get_state`, `get_commands`, then terminate it. Models: `id = "<provider>/<id>"` (so `--model` is unambiguous, e.g.
   `meta-ai/muse-spark-1.3-contributor`), `name` = model name + provider in description, `efforts` = pi thinking levels
   `["off","minimal","low","medium","high","xhigh"]` only for models with `reasoning: true`, else `[]`. Only list models
   that are usable (pi's get_available_models already filters to authed providers — keep order, but put the
   `get_state` model first / as `defaultModel`). `supportsImages` = True, `supportsInterrupt` = True,
   `supportsPermissions` = False (pi runs tools without prompting). Version via `pi --version`. `available: False` with a
   clear `error` if the binary is missing. Binary: env `LINKUP_PI`, default `~/.local/bin/pi` if it exists else `pi`.
   Commands (`catalog["commands"]`): from `get_commands` → `[{"name","description","kind": "skill"|"command"|"prompt"}]`
   (pi names look like `skill:brainstorming`; keep them exactly, the app sends `/skill:name` back as the prompt text, which
   pi expands itself).
2. **Session** `PiSession` (same interface as `ClaudeSession`: `send`, `interrupt`, `resolve_permission` (no-op),
   `set_mode` (no-op), `close`, `pid` property, `session`, `emit`): one long-lived
   `pi --mode rpc --model <provider/id> --thinking <effort> --session-dir ~/.linkup/pi-sessions` per open session, cwd =
   session cwd (default home), env = os.environ (+ PATH containing the dir of `node`; the systemd unit has a minimal PATH,
   so prepend `~/.local/bin` and `/usr/bin`). Start lazily on first `send`. After start call `get_state` and store
   `sessionFile` as `native_id` (`store.update_session(id, native_id=...)`). When a session already has a `native_id`
   (resume after bridge restart / reaper) start with `--session <native_id>`. Model/effort changes between turns:
   send `set_model` (needs provider+modelId) / `set_thinking_level` instead of restarting. Never leak the stderr to the
   user except as an `error` event when the process dies mid-turn; log it.
3. **Send**: images (attachments with an image mime) → RPC `images: [{type:"image", data:b64, mimeType}]`; other
   attachments → a line `Attached file: <path>` prepended to the message (like hermes/agy). If a turn is already running,
   send with `streamingBehavior: "steer"`. Emit `turn.start` + `status requesting` on send, `status running` on first event.
4. **Event mapping** (pi → normalized; use the captured trace): `message_update` with assistantMessageEvent
   `thinking_start/delta/end` → `thinking.start/delta/end {block}`; `text_start/delta/end` → `text.start/delta/end {block}`
   (block id = uuid per content block); `toolcall_start/delta/end` → `tool.start {id,name,input}` / `tool.input` (partial) /
   `tool.update` (full args) — pi tool names are lowercase `read bash edit write grep find ls` (keep them as-is, the iOS
   side maps them) — and `tool_execution_start/update/end` → running state, `tool.end {id, output (joined text content),
   isError, images:[url]}` (image tool results: write the base64 to `~/.linkup/media/pi/` and use `Media.url`).
   `message_end` for an assistant message → `usage {inputTokens, outputTokens, cacheRead, cacheWrite, costUsd (usage.cost.total),
   contextTokens (usage.totalTokens or input+cacheRead)}`. `agent_end` → `turn.end {stopReason, durationMs, costUsd summed,
   isError (stopReason error/aborted?), text (final assistant text)}` then `status idle`. Assistant `stopReason: "error"` with
   `errorMessage` → `error {message}`. `auto_retry_start/end`, `compaction_start/end` → `notice {text}`. `queue_update` →
   ignore. `extension_error` → notice. Extension UI requests (`extension_ui_request` on stdout: select/confirm/input/editor,
   see rpc.md): reply immediately with a cancellation (`extension_ui_response` cancelled) so pi never hangs, and log it; fire-and-forget
   kinds (notify/setStatus/setWidget/setTitle) → `notice` only for notify. Detect artifacts exactly like claude.py does
   (paths in tool args/outputs/final text via `paths_in`, plus `sends_in` for `linkup:send`), emitting `artifact` events
   with `Media.artifact`, deduped per session the way claude.py/server do.
5. **Interrupt** → RPC `abort`; then ensure `turn.end {stopReason:"interrupted"}` + `status interrupted/idle` happen
   exactly once. **Process death / bridge restart** → `error` + `turn.end isError` + `status idle`, never a stuck "running".
6. **Fork/compare/handoff**: `session["fork_from"]` and `session["context"]` are handled by the server for all agents; check
   how claude.py uses `fork_from` and support it if it is just a `native_id` copy (pi has `--fork <session>`); if not trivially
   supported, ignore it.
7. **Server wiring**: register in Hub; `VALID_AGENTS`; usage dashboard totals must include per-agent historical totals for
   "pi" (see how `totals` is computed in `server.py`/`store.py` and make pi's sessions count; `usage` events carry tokens);
   idle reaper must close pi processes (they expose `pid`); `catalog()` attaches commands for pi.
8. **History import (do last, only if clean)**: pi sessions are JSONL files under `~/.pi/agent/sessions/<cwd-slug>/*.jsonl`
   (format: `docs/session-format.md`). If `history.py` lists PC sessions for "import into the app", add pi sessions the same
   way (agent "pi", `native_id` = absolute session file path, title = first real user prompt, cwd from the session header)
   and make `load_for_import` / `events` convert a pi session to normalized events. Keep the existing claude behaviour
   unchanged and make the item shape identical so the app needs no change beyond the agent id.

## Verify (must do, show output in your final message)
- `cd bridge && ~/.linkup/.venv/bin/python -c "import asyncio,linkup_bridge.agents.pi as p; ..."` printing the catalog (model
  count, default, a few commands).
- A scratch bridge: `LINKUP_PORT=8899 LINKUP_HOME=/tmp/pi-scratch ~/.linkup/.venv/bin/python -m linkup_bridge serve &` then
  `~/.linkup/.venv/bin/python tests/e2e.py 8899 /tmp/pi-scratch pi "<default model id>" "Create /tmp/pi-e2e.txt containing hi using bash, then reply done"`
  (read `tests/e2e.py` for its real usage first). Show the normalized events you got (tool.start/tool.end/turn.end), then a
  second turn on the same session proving resume works, and an interrupt test. Kill the scratch server by PID.
- Use the model `meta-ai/muse-spark-1.3-contributor` (the user's default; free) — do NOT use paid providers.
- Do NOT restart the systemd service `linkup-bridge`; do not run `pkill -f linkup_bridge`.

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
