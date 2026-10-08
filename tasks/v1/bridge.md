# Linkup 1.0 — Bridge (Python, runs on the user's PC behind Tailscale Funnel)

YOUR FILES: bridge/** (linkup_bridge/*.py, agents/*.py, deploy/*, tests/*), scripts/screens.sh, scripts/make-source.py
(only the usage-string/except fixes there; do NOT change ENTITLEMENT_FILES).
Read first: tasks/_common_py.md, CLAUDE.md, linkup_bridge/agents/base.py docstring (event vocabulary),
server.py docstring (ops). Keep the protocol backward compatible with the current iOS app.

Must-fix (AUDIT: section A/B security, section 6 bridge, W2-D 46, W2-F 59/69/70, "Haiku: uncovered files" bridge+deploy+CI):
1. Security (internet-facing): `/linkup/files` sibling lookup can serve any file under a registered file's dir —
   serve only registered files (exact path). `history.py`: `nativeId` must match a UUID regex before any glob/import.
   Workspace proxy: only allow dev-server ports (deny the bridge port, Hermes 8642, and well-known service ports;
   prefer an explicit allowlist range like 3000-9999 minus denied). Accept the token from an `Authorization: Bearer`
   header or a `linkup_token` cookie (in addition to the existing query param) so the app can stop putting it in URLs.
   Token file created atomically with 0600, refuse empty token. commands.py fork child: `os._exit(127)` on exec failure.
2. Claude adapter: the `assistant` message branch drops text/thinking/API-error text (only tool_use handled) —
   emit them (dedupe against stream deltas already sent via partial messages; API errors → `error` event with the text).
3. agy adapter: emit `thinking.start`/`thinking.end` around thinking; block ids unique per turn (prefix with a turn
   counter, e.g. `t{turn}-{idx}`), since step_index restarts per `agy -p` process; text.end always sent; usage events.
4. Bridge restart: on startup, sessions left "running" in the DB get a final `turn.end` (or `error` "Bridge restarted")
   + status idle, so phones stop showing "Working…" forever. Fork of a streaming session must not copy an
   unterminated live turn (close it in the copy). Handoff `notice` events are normal events.
5. Unread: support `read` as today, but don't mark unread for a session that has an active subscriber that sent
   `focus`/`read` recently (optional) — at minimum keep `read` working. Add `unsubscribe {session}` op if missing
   (the iOS store will send it when the user leaves a chat; running sessions may stay subscribed).
6. Robustness: history.py skips non-dict lines/parts, stat inside try, cache titles by (path, mtime);
   import of the same nativeId concurrently creates one session (lock); bulk event import in one store write in a
   worker thread; `base.py` artifact(): skip paths that don't exist (no getsize crash); `__main__.py`: unknown
   subcommand → usage + exit 2, missing qrcode → print install hint, PUBLIC url from env or `tailscale status --json`.
7. Deploy: service `Wants=network-online.target tailscaled.service`, `StartLimitIntervalSec/Burst`, PATH includes where
   `claude`/`agy` live (check `which claude agy` and use those dirs); install.sh: pinned deps
   (requirements.txt), warn if sessions are running before restart, health-check the public URL at the end.
8. scripts/screens.sh: fail (exit 1) when fewer screenshots than expected were captured.
Verify: `cd bridge && python -m py_compile linkup_bridge/*.py linkup_bridge/agents/*.py` and, if possible, start a
scratch instance (LINKUP_PORT=8899 LINKUP_HOME=$(mktemp -d)) and run `python tests/e2e.py` against it with the claude
agent (see CLAUDE.md). NEVER `pkill -f linkup_bridge` (kills your own shell) — kill by PID. Do not touch the running
production service (port 8890) or ~/.linkup.


---
# SHARED RULES (tasks/v1/_common.md)

# Linkup 1.0 — shared rules for every fix agent (read fully before touching code)

Linkup is a native SwiftUI iOS/iPadOS 26 app (Swift 5 language mode, Xcode 26 SDK, no Swift packages) + a Python
bridge (`bridge/`) on the user's PC. Read `CLAUDE.md` and the old shared rules `tasks/_common.md` (design language,
Theme, Liquid Glass rules, API contracts) first. The user said the app is "buggy in navigation, model responses not well
handled, everything looks bad". We are shipping **Linkup 1.0** that fixes ALL of it. Quality bar: feels like the
official Claude iOS app — smooth, no jank, no clipped/overlapping UI, nothing that silently does nothing.

## Your checklist = the audit
`tasks/AUDIT.md` (~1700 lines) holds every finding from two audit waves, by file and line (line numbers are from
commit 17bee80 and may have drifted slightly — re-find by content). **Fix every finding that names one of YOUR files**,
in both waves: the curated sections (A–F, W2-A … W2-F) and the raw auditor sections. Search it like this:
`grep -n "RootView" tasks/AUDIT.md` for each of your files. Several auditors often report the same bug — fix it once.
Your brief adds the most important items and any cross-file contract. If a finding is wrong (the code doesn't do what
it claims), skip it and say so in your final message. If a finding needs a change in a file you don't own, don't do it:
list it in your final message under "NEEDS OTHER FILE".

You are one of ~10 agents editing DIFFERENT files at the same time. **Edit only the files your brief lists**
(you may create new files only inside the directories your brief names; prefix new private types with your area,
e.g. `SidebarFooter`, to avoid duplicate type names). Never edit project.yml, .github, Theme.swift (unless listed),
or another agent's files.

## Contracts already in the code (use them, don't redefine them)
- `ui.openSession(_ id: String?)` and `ui.newChat()` (App/LinkupApp.swift) are THE way to switch chats: they reset
  the inspector panels (summaryTurn/openArtifact) and close the drawer with its slide animation. Never assign
  `ui.currentSessionId` directly anywhere else. If a sheet starts/opens a session (Compare "Open", Schedules "Run now",
  Handoff, Projects "New session here"), call `ui.openSession(id)` AND dismiss the sheet (set its `ui.isShowing…`
  flag false / call dismiss()).
- `ui.toastID` bumps on every toast (use `.task(id: ui.toastID)` for the timer).
- `Transcript.isLoading` — true while cached events load from disk. ChatView shows a quiet loading state, not the greeting.
- `store.close(_ sessionId:)` — ChatView calls it when the user leaves a chat (store agent implements it: unsubscribe +
  evict). `store.open(_:)` subscribes; it must be safe to call twice (store agent dedupes).
- `TurnUsage { input (fresh, uncached), output, costUsd, cached }` — show token counts as input+output; `cached` only
  as a secondary detail ("+ 320k cached"). Never add cached into the headline number.
- `Notification.Name.linkupComposerSetText` (object: String) and `.linkupFocusSearch` (Core/Support/Notifications.swift).
- `String.dominantLayoutDirection`, `.isRightToLeft`, `.searchFolded` (Core/Support/TextDirection.swift): user writes
  Moroccan Darija in Arabic script, French and English. Any user-written or agent-written paragraph must be laid out
  in its own direction (`.environment(\.layoutDirection, text.dominantLayoutDirection)` + `.multilineTextAlignment`),
  and search must compare `searchFolded` strings.
- `SheetCloseButton(action:)` and `SheetHeader(title:onClose:leading:)` (UI/Theme/SheetChrome.swift): EVERY sheet uses
  this header/close button (trailing 44pt glass circle). Sheets: `.presentationBackground(Theme.surface)`; list-heavy or
  multi-column sheets open `.large` (or `[.large]`); only small pickers use `.medium`. Dividers use `Theme.hairline`.
- UserDefaults key `"linkupSpeechLanguage"`: "" = automatic (device), or a BCP-47 id "en-US" | "fr-FR" | "ar-MA" |
  "ar-SA". Settings writes it; dictation + voice mode TTS/STT read it (STT: `SFSpeechRecognizer(locale:)`, TTS: best
  installed `AVSpeechSynthesisVoice` for that language, preferring enhanced/premium quality; compare language codes
  with `-`/`_` normalised).

## Quality rules
- It must COMPILE first time on Xcode 26 / iOS 26 SDK: open and read every type/function you call; no invented APIs.
  iOS 26 APIs you may use: `.safeAreaBar(edge:alignment:spacing:content:)`, `.scrollEdgeEffectStyle(_:for:)`,
  `.glassEffect(_:in:)`, `GlassEffectContainer`, `.buttonStyle(.glass)`, `onScrollGeometryChange`, `onScrollPhaseChange`,
  `.presentationSizing`. Swift 5 mode: helpers called from background closures must be `nonisolated`.
- Never fix a bug by deleting a feature. Keep every existing public type/func signature other agents call
  (if you must change one, keep the old one working).
- Tap targets ≥ 44×44pt (`.contentShape(Rectangle())` + frame). Every icon-only button has `.accessibilityLabel`.
  Respect `@Environment(\.accessibilityReduceMotion)` for big/looping animations.
- Animations: state changes that move layout go through `withAnimation(.smooth(duration: 0.3))` / `.snappy`; no popping.
  Never make values jump at the first frame (interpolate with progress instead of `x > 0 ? a : b`).
- Performance while streaming: a view must not read observable properties it doesn't display (reading a property in
  `body` — even inside `.onChange(of:)` — subscribes the whole body). Push frequently-changing reads into small child views.
- Text never clips or wraps mid-word in pills/chips: `.lineLimit(1)` + `.fixedSize(horizontal: true, vertical: false)`
  or `.minimumScaleFactor`, and truncate the less important part first.
- No mock/fixture data in production paths (`DebugLaunch.screen != nil` is the only place fixtures may load).
- Errors visible to the user (`ui.toast` or inline), never silently swallowed.
- Comments only for non-obvious "why", matching the existing sparse style.

## When done
`git status` must show only your files. Commit with a short message. Your final message (≤ 40 lines): what you fixed
(grouped), findings you skipped as wrong (with reason), and "NEEDS OTHER FILE" items.
