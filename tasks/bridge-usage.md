Linkup bridge: live plan usage for Claude Code and Antigravity

## Your files: `bridge/linkup_bridge/usage.py` (replace the stub, keep `claude_plan()` and `agy_usage()`)

### claude_plan()
The signed-in Claude Code keeps its OAuth credentials in `~/.claude/.credentials.json` (`claudeAiOauth.accessToken`,
`expiresAt` ms). The same endpoint Claude Code's `/usage` command uses returns the plan usage (verified):
`GET https://api.anthropic.com/api/oauth/usage` with headers `Authorization: Bearer <accessToken>` and
`anthropic-beta: oauth-2025-04-20` → JSON like
`{"five_hour": {"utilization": 19.0, "resets_at": "2026-10-05T14:00:00.244180+00:00", ...}, "seven_day": {...},
"seven_day_opus": null | {...}, "seven_day_sonnet": null | {...}, ...}` (utilization is a PERCENT 0–100).
Return `{"fiveHour": {"utilization": 0.19, "resetsAt": <epoch seconds>}, "sevenDay": {...}, "sevenDayOpus": {...}|None,
"sevenDaySonnet": {...}|None, "subscription": <claudeAiOauth.subscriptionType, prettified e.g. "Claude Pro">,
"at": time.time()}` (utilization converted to 0…1). Use aiohttp with a 10 s timeout. Re-read the credentials file
every call (Claude Code refreshes the token itself). On 401 or an expired token: refresh by running
`claude -p --output-format json --model haiku "ok"`? NO — that costs usage. Instead just return None and log once;
the CLI refreshes the token on its next normal use. Never log the token.

### agy_usage()
Antigravity (`agy`, at ~/.local/bin/agy) shows its credit status in its interactive TUI footer, e.g.
`Gemini 3.8 Flash · high · AI: Out of credits` (the part after "AI:"). Capture it without user interaction:
spawn `agy` in a pseudo-terminal (use the stdlib `pty` + `os.fork`/`subprocess` with `pty.openpty()`), size 200x50,
read output for up to ~12 s, strip ANSI escape codes, find the last `AI: ...` footer text, then terminate the process
(send Ctrl-C twice then kill). Also look for any quota numbers it prints. Explore first: run it yourself and look at
the raw TUI output, and check `agy --help`, `agy models` and the logs at `~/.gemini/antigravity-cli/cli.log`
(look for credits/quota lines, e.g. `GetG1Credits`) for any better machine-readable source; use the best real source
you find. Return `{"credits": "Out of credits" (exact text), "status": "ok"|"out"|"unknown", "models": [...]
(only if you found real per-model quota, else []), "at": time.time()}` or None if agy isn't available.
Must never hang: hard timeout 20 s, always kill the child. Run it in a thread if it blocks.
