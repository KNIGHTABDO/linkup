Linkup activity: thinking/tool row, Summary timeline sheet, tool details, permission card [shots]

## Your files (only these)
- `ios/Linkup/UI/Activity/ActivityViews.swift` (replace stubs; keep `ActivityRow(turn:)`, `SummarySheet(turn:)`,
  `ToolCallDetailView(tool:)`, `PermissionCard(request:sessionId:)`)
- you may add more files under `ios/Linkup/UI/Activity/`

This is the "very cool design of thinking and tool calls" the user asked for. Copy the Claude iOS app:

## ActivityRow (collapsed, inside the turn, above the answer)
One line, left aligned, height ~32: leading icon area 28pt wide, then the text, then a chevron.
- While `turn.isLive`: leading = `WorkingDots()` (orange pulsing dots); text = `turn.activityLine` in
  `Theme.sans(16)` with a **shimmer** sweeping left→right across the text (secondaryText base, ivory highlight;
  implement with a moving LinearGradient mask, 1.6 s loop). Text changes with `.contentTransition(.opacity)` +
  `.animation(.smooth, value: turn.activityLine)`. Trailing `chevron.right` tertiaryText.
- When finished: leading `clock` (like the screenshot) in secondaryText; text = a summary like the last
  thinking line, or "Thought for 12s" if only thinking, or "Used 4 tools" — choose: if any thinking text exists use
  the last thinking `summaryLine` else "\(n) steps"; plus duration "· 12s" from `turn.durationMs`. One line, truncated.
- Tap anywhere → `ui.summaryTurn = turn` (UIState from environment). Accessibility: button.
- If the turn has a pending permission (`turn.parts` contains `.permission(p)` with `p.allowed == nil`) show the
  text "Waiting for your approval" in accent instead.

## SummarySheet (the "Summary" sheet in the screenshots)
`.presentationDetents([.medium, .large])`, background `Theme.surface`, top bar: glass circle `xmark` (dismiss) left,
centered title "Summary" (Theme.sans 17 semibold). Content: a vertical **timeline** of `turn.activity` in order:
- each entry has a leading 28pt column with an icon (thinking → small 8pt dot in secondaryText; tool →
  `tool.presentation.symbol` in secondaryText, 17pt; permission → `hand.raised`), connected by a 1pt vertical line
  (Theme.hairline) between entries; live entries pulse.
- thinking entry: the thinking text (Theme.sans 17, ivory for the latest, secondaryText for older), collapsible to
  4 lines with "Show more"; while `block.isActive` and empty show "Thinking…" with the shimmer.
- tool entry: title `tool.presentation.title` (Theme.sans 17), trailing `chevron.right`; running tools show a
  small ProgressView; errored tools tint the icon `Theme.danger`. Tap → push `ToolCallDetailView(tool:)` (use a
  NavigationStack inside the sheet). Nested `tool.children` render indented under their parent (sub-agents).
- at the end while the turn is live: "Thinking…" entry with shimmer. When finished: footer "Done · 12s · 4.2k
  tokens · $0.03" (cost only if present) in tertiaryText.
- Auto-scrolls to the newest entry while live.

## ToolCallDetailView
Navigation title = `tool.presentation.activeTitle`. Sections (cards on Theme.elevated, radius 16):
- "Input": if `tool.partialInput` non-nil show it (streaming) else `tool.input.prettyText`, in `Theme.mono(13)`,
  selectable, horizontally scrollable; for common tools show a friendly header first: Bash/run_command → the command
  in a terminal-style box with `$ ` prefix; Read/Write/Edit → file name + path; Edit → old/new strings as a red/green
  diff (input keys `old_string`/`new_string`); WebSearch → the query; Task → the description + prompt.
- "Output": `tool.output` mono 13 (cap the rendered text to the first 20,000 characters with a "Show all" toggle),
  red title if `tool.isError`; `tool.images` → `RemoteImageView(url:)` (exists as a type) full width; artifacts →
  `ArtifactCard(artifact:)` (exists).
- duration (finished - started) and status in the header. A copy button in the toolbar copies the output.

## PermissionCard (inline in the turn while waiting)
Rounded card (Theme.elevated, radius 20, hairline border), header `hand.raised.fill` accent + "\(agent) wants to use
\(request.tool)", the key input (command / file path / url via the same friendly logic) in mono, `request.reason`
if any. Two buttons in a `GlassEffectContainer`: "Deny" (`.buttonStyle(.glass)`) and "Allow" (`.buttonStyle(.glassProminent)`
tinted accent) → `store.answer(request, in: sessionId, allow:)` + haptic. After answering show "Allowed"/"Denied" state.

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
