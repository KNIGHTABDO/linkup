# Linkup — your PC's AI agents on iPhone/iPad

Native SwiftUI iOS/iPadOS 26 app (Claude-app look, real Liquid Glass) + a Python bridge on the PC that drives the
**already signed-in CLIs/servers** — no API keys, no paid APIs:
- **Claude Code**: long-lived `claude -p --input-format stream-json --output-format stream-json --verbose
  --include-partial-messages --permission-prompt-tool stdio` per session (control channel: `initialize` → live models
  with efforts, commands, account; `interrupt`; `set_permission_mode`; `can_use_tool` permission prompts;
  `rate_limit_event` = 5-hour / 7-day plan usage).
- **Antigravity**: `agy -p … --output-format stream-json [--conversation <id>]` per turn; `agy models` for the list.
- **Hermes**: local API server (127.0.0.1:8642, key in ~/.hermes/.env): POST /v1/runs + SSE /v1/runs/{id}/events.

## Layout
```
bridge/linkup_bridge/   server.py (aiohttp WS hub + files/upload), store.py (sqlite: sessions, seq'd events, files),
                        history.py (PC Claude Code sessions → importable), agents/{claude,agy,hermes,base}.py
bridge/deploy/          linkup-bridge.service + install.sh (systemd + Tailscale Funnel path /linkup)
ios/Linkup/Core         Protocol (JSONValue, Models), Net (LinkupClient WebSocket, ConnectionSettings/Keychain),
                        Store (Transcript reducer, ToolPresentation, SessionStore + EventCache)
ios/Linkup/UI           RootView, Chat, Activity, Composer, Sidebar, Artifacts, Settings, Theme
tasks/                  Gemini briefs (`_common.md` = shared rules)
```
- Normalized event vocabulary: see `bridge/linkup_bridge/agents/base.py` docstring. Every event has a per-session
  `seq`; the app caches events on disk and reconnects with `hello {since}` / `subscribe {since}` — no gaps, no dupes.
- WS ops: see `server.py` docstring. Files are served at `/linkup/files/<id>/<name>`; always resolve URLs with
  `LinkupClient.resolve(_:)` (adds host + token).
- Run/verify the bridge locally: `cd bridge && ~/.linkup/.venv/bin/python -m linkup_bridge serve`
  (env LINKUP_PORT / LINKUP_HOME for a scratch instance), `python tests/e2e.py <port> <home> <agent> <model> "<prompt>"`.
  Deploy: `bridge/deploy/install.sh`. Pair: `python -m linkup_bridge pair` (QR with `linkup://pair?url=&token=`).
- Never `pkill -f linkup_bridge` from a shell whose command line contains that text (it kills the shell itself).

## iOS rules
Same as Knight Music: no Mac, GitHub Actions compiles (`[shots]` → screenshots via `-LinkupScreen <name>` using
real captured events in `Resources/Fixtures/screenshot-fixture.json`), XcodeGen `project.yml`, iOS 26, Swift 5 mode,
no extra packages, real Liquid Glass on controls only, Claude palette in `Theme.swift`, no mock data in production.
