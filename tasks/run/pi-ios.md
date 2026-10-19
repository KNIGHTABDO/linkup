Add the Pi agent to the Linkup iOS app

## Goal
The bridge is getting a 4th agent `id = "pi"` (name "Pi", the Pi coding agent by Mario Zechner). Another agent is writing
the Python side right now; you do the whole iOS side so Pi is a first-class citizen everywhere Claude/Antigravity/Hermes
appear. The bridge sends the same normalized events and `AgentInfo` catalog as for other agents (models like
`meta-ai/muse-spark-1.3-contributor`, efforts `off/minimal/low/medium/high/xhigh`, `commands` list of
`{name, description, kind}` where names look like `skill:brainstorming`, supportsImages true, supportsPermissions false).
Pi's tool names are LOWERCASE: `read`, `bash`, `edit`, `write`, `grep`, `find`, `ls` with args `bash{command}`,
`read{path,offset,limit}`, `write{path,content}`, `edit{path,oldText/newText or edits[]}` (check
`~/.local/lib/node_modules/@mariozechner/pi-coding-agent/docs` and `tasks/pi-rpc-sample.jsonl` for the real shapes; grep the pi
`dist/` tool sources for the exact edit-tool arguments).

## Do (grep the repo for every place the three agents are listed — `grep -rn '"hermes"\|case hermes\|\.hermes' ios/`)
1. `Core/Protocol/Models.swift` `AgentKind`: add `case pi` (title "Pi", SF symbol `function` or the closest to "π").
2. `UI/Brand/AgentLogo.swift`: Pi mark. No asset available: draw a bold serif/rounded "π" glyph inside the same-size frame
   (a `Text("π")` or a small custom `Shape` path of the pi symbol), tinted `Theme.text`, so it matches the monochrome Hermes
   treatment. Update `label`.
3. `UI/Theme/Theme.swift` `agentColor("pi")`: a distinct colour that fits the warm dark palette (e.g. a sage/teal green,
   clearly different from Claude orange, agy blue, Hermes). You MAY edit Theme.swift for this one function only.
4. `Core/Store/ToolPresentation.swift`: map pi's lowercase tools to the same symbols/titles/active titles/details as
   Claude's Read/Bash/Edit/Write/Grep/Glob(find)/LS equivalents (case-insensitive aliases). `bash` detail = command, `read`/`write`/
   `edit` detail = file path (last 2 components), etc. Keep all existing behaviour for other agents.
5. Pickers & lists: `UI/Usage/UsageDashboardView.swift` (add a Pi section like Hermes' — local tokens/cost totals from
   `store.usage?.totals?["pi"]` + sessions with agent "pi"; add "pi" to `knownOrder`), `UI/Usage/UsageRing.swift`,
   `UI/Multi/CompareView.swift`, `UI/Multi/CompareSheet.swift` (agent list + default selection stays claude/agy/hermes/pi),
   `UI/Multi/HandoffSheet.swift`, `UI/Schedules/SchedulesView.swift` (agent picker), the new-session/model picker in `UI/Composer`
   and `UI/Sidebar` + `UI/Settings` (agent filters, badges, labels, colours, effort pickers: Pi's efforts come from the
   catalog like Claude's — make sure effort UI shows for Pi models that have efforts and hides it for those without),
   `UI/Chat` (anything switching on agent for image attach, interrupt, permissions UI hidden because supportsPermissions false).
6. Slash-command menu: Pi's `commands` come in the catalog (kind "skill"/"command"/"prompt"); make sure the composer's `/` menu
   shows them for Pi like for agy/hermes and inserts `/<name>` verbatim.
7. `App/DebugLaunch.swift`: add Pi to the fixture agents (one model `meta-ai/muse-spark-1.3-contributor`, efforts) so `[shots]`
   builds show it. `Resources/Fixtures/screenshot-fixture.json`: only add a pi agent entry if it is a pure data addition.
8. `scripts/make-source.py` / README text: mention Pi next to the other agents.
Do NOT add network code, new packages, or mock data in production. Keep iOS 26 / Swift 5 mode / existing style. You cannot
compile (no Mac) — be extremely careful: exhaustive `switch` statements over `AgentKind` must all gain the `.pi` case; re-grep
for `switch` on `AgentKind`/agent strings at the end; check every edit for balanced braces and real symbol names by reading
the files you depend on. Only touch iOS/doc files; another agent edits `bridge/` at the same time.
Final message: list each file changed with one line, plus the exhaustive-switch grep proving none was missed.

---
# Shared rules for every Linkup task (read fully before coding)

## What Linkup is
A native SwiftUI iOS/iPadOS 26 app (Swift 5 mode, Xcode 26 SDK) that drives the user's AI agents running on their PC
— **Claude Code**, **Antigravity (agy)** and **Hermes** — through a bridge on the PC (`bridge/`, already done and
working). It must look and feel like the **Claude iOS app** (dark warm surfaces, ivory text, Claude-orange accent,
serif agent text) with Apple's real **Liquid Glass** on the control layer. Everything is real data from the bridge:
**no mock data, no placeholders, no "coming soon"** in production code.

You are one of several agents working IN PARALLEL on different files. **Only edit the files your task lists.**
Never edit Core/ files, Theme.swift, LinkupApp.swift, DebugLaunch.swift or other tasks' files. If you need something
from Core that doesn't exist, build it privately inside your own files (prefix private helper types with your task
name to avoid duplicate declarations, e.g. `ChatCodeBlock`, `SidebarRow`).

## Read these files first (they are the contracts — use their exact API, never invent APIs)
- `ios/Linkup/Core/Protocol/Models.swift` — SessionInfo, AgentInfo, ModelInfo, UsageSnapshot, ClaudeRateLimit,
  ProjectInfo, HistoryItem, AgentKind (title/symbol per agent).
- `ios/Linkup/Core/Protocol/JSONValue.swift` — JSONValue (`["key"]`, `.string`, `.int`, `.prettyText`…).
- `ios/Linkup/Core/Store/Transcript.swift` — Transcript (items, liveTurn, isWorking, pendingPermissions),
  TranscriptItem (.user / .assistant), UserMessage, AttachmentRef, AssistantTurn (parts, phase, isLive, activity,
  textBlocks, artifacts, activityLine, durationMs, usage, model), TurnPart (.thinking/.text/.tool/.artifact/
  .permission/.notice/.error), ThinkingBlock (text, isActive, summaryLine), TextBlock (text, isActive), ToolCall
  (name, input, partialInput, output, isError, images, artifacts, children, childText, isRunning, presentation),
  PermissionRequest (tool, input, reason, allowed), ArtifactRef (kind, title, url, path, mime, size).
  All of these are `@Observable` classes/structs updated live while the agent streams: read them directly in views.
- `ios/Linkup/Core/Store/ToolPresentation.swift` — `tool.presentation.symbol / .title / .activeTitle / .detail`.
- `ios/Linkup/Core/Store/SessionStore.swift` — SessionStore: sessions, agents, usage, projects, lastError,
  `transcript(for:)`, `session(_:)`, `agent(_:)`, `open(_:)`, `create(agent:model:effort:cwd:permissionMode:)`,
  `send(_:to:attachments:)`, `interrupt(_:)`, `answer(_:in:allow:)`, `update(_:title:pinned:model:effort:permissionMode:)`,
  `delete(_:)`, `refreshCatalog(force:)`, `loadProjects()`, `loadHistory()`, `importHistory(_:)`.
- `ios/Linkup/Core/Net/LinkupClient.swift` — LinkupClient: `state` (ConnectionState .notConfigured/.connecting/
  .connected/.offline(String), `.label`), `latencyMs`, `serverName`, `resolve(_ relativeURL) -> URL?` (ALWAYS use
  this for any bridge URL like "/linkup/files/…" — it adds the host and token), `upload(data:name:mime:)`, `connect()`,
  `disconnect()`. ConnectionSettings: `serverURL`, `token`, `isConfigured`, `apply(pairingLink:)`.
- `ios/Linkup/App/LinkupApp.swift` — AppModel, **UIState** (currentSessionId, draftAgent/draftModel/draftEffort/
  draftProject, isSidebarOpen, isShowingSettings, isShowingConnect, isShowingModelPicker, isShowingUsage, summaryTurn,
  openArtifact, toast, newChat()).
- `ios/Linkup/UI/Theme/Theme.swift` — **Theme** colors (background #1F1E1D, surface, elevated, userBubble, hairline,
  text ivory, secondaryText, tertiaryText, accent Claude orange #D97757, artifactTile, danger, success, link),
  fonts `Theme.serif(size)` (agent voice), `Theme.sans(size)` (UI + user text), `Theme.mono(size)`, `Theme.margin`,
  `Theme.bubbleRadius`, `Theme.composerRadius`, `Theme.agentColor(agentId)`, `SparkView(size:animating:)`,
  `WorkingDots()`.
- Environment objects available everywhere: `@Environment(AppModel.self)`, `@Environment(ConnectionSettings.self)`,
  `@Environment(LinkupClient.self)`, `@Environment(SessionStore.self)`, `@Environment(UIState.self)`.
  For bindings to UIState use `@Bindable var ui = ui` inside `body`.

## Design language (match the Claude iOS app screenshots the user loves)
- Background `Theme.background` everywhere, edge to edge. Text ivory. Agent responses in **serif** (`Theme.serif(17)`,
  line spacing ~4). User messages in SF Pro (`Theme.sans(17)`) inside a right-aligned bubble `Theme.userBubble`,
  corner radius 22, max width ~80%.
- Top bar: no navigation bar. A **glass circle** button top-left (≡ "line.3.horizontal", opens sidebar) and a
  **glass capsule** top-right (new chat "plus.bubble" + "ellipsis" menu). Use real Liquid Glass:
  `.glassEffect(.regular.interactive(), in: .circle)` / `.capsule`, group neighbours in `GlassEffectContainer`.
  Buttons can use `.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)`. Never fake glass with materials/blur.
  Glass only on controls, never on content (messages, cards).
- Accent orange only for the spark, working dots, links and key highlights. Secondary text `Theme.secondaryText`.
- Motion: `.smooth` / `.snappy` springs, `.contentTransition(.numericText())` for numbers, haptics via
  `UIImpactFeedbackGenerator` on send/stop/allow. No jank: LazyVStack, stable ids.
- Sheets: `.presentationDetents([.medium, .large])`, `.presentationBackground(Theme.surface)`, rounded, with a
  glass circle "xmark" close button top-left and a centered title (like the Claude "Summary" sheet).
- SF Symbols only (no image assets). Support iPhone and iPad (iPad: same layout, content max width ~760 centered).
- Dynamic Type friendly: use the Theme fonts; text must wrap, never clip.

## Code rules
- Swift 5 language mode, iOS 26 APIs allowed. `@MainActor` views; no force unwraps on data; `async/await`.
- Small focused views, one primary type per file is fine but you may keep your views in your listed files.
- Comments only for non-obvious "why".
- Errors are shown to the user (inline text or `ui.toast`), never silently swallowed.
- It must COMPILE: double-check every API you call exists in the files above or in SwiftUI/UIKit for iOS 26.
  Prefer simple, well-known SwiftUI APIs over clever ones.
- Do not add Swift packages or new targets. Do not touch project.yml or .github.
- When done: make sure `git status` shows only your files changed, then commit with a short message.

## Round 2 additions (read too)
- `ios/Linkup/Core/Store/SessionStore+Extras.swift` — projects/files/git/CI/schedules/fork/handoff/compare/createChat
  wrappers and their models (FileEntry, FileContent, GitStatus, GitCommit, CIRun, ScheduleInfo, AgyUsage,
  ClaudePlanUsage). `store.usage?.claudePlan`, `store.usage?.agy` are live (pushed every minute).
- `SessionInfo.mode == "chat"` marks rich-card chat sessions.
- `AgentLogo(agent: "claude" | "agy" | "hermes", size:)` — ALWAYS use it to show an agent (not SF Symbols).
- Rich cards: `RichCardView(card:)`, `CardContainer(title:symbol:)`, `CardActions` (`@Environment(\.cardActions)`),
  JSON helpers `card.strings("k")`, `card.objects("k")`, `card.url("k")`; spec: `bridge/linkup_bridge/cards.md`.
- Do NOT edit RootView.swift, SidebarView.swift or LinkupApp.swift unless your task says so: build your screens as
  standalone views; Claude wires the entry points (menus, rows, sheets) when merging. State in your final message
  the exact view names and how to present them.
