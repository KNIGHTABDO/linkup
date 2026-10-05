Linkup chat: conversation view, user bubble, agent turn, streaming markdown [shots]

## Your files (only these)
- `ios/Linkup/UI/Chat/ChatView.swift` (replace stub, keep `ChatView(sessionId: String?)`)
- `ios/Linkup/UI/Chat/MessageViews.swift` (replace stubs, keep `UserBubble(message:)`,
  `AssistantTurnView(turn:sessionId:)`, `MarkdownView(text:isStreaming:)`)
- you may add `ios/Linkup/UI/Chat/MarkdownParser.swift`

## ChatView
- `sessionId == nil` → **new chat screen**: centered `SparkView(size: 44)` and below it a greeting in
  `Theme.serif(30)`: "Hello, night owl" between 21:00–05:00, "Good morning" 5–12, "Good afternoon" 12–17,
  "Good evening" 17–21 (Text color #E8E6DC-ish = Theme.text opacity 0.9). Under it, small agent chip:
  `AgentKind(rawValue: ui.draftAgent)?.title`. Composer pinned at the bottom: `ComposerView(sessionId: nil)`.
- `sessionId != nil` → `let transcript = store.transcript(for: id)`; `.task(id: id) { store.open(id) }`.
  A `ScrollView` + `LazyVStack(alignment: .leading, spacing: 18)` of `transcript.items`:
  `.user(m)` → `UserBubble(message: m)` (right aligned), `.assistant(t)` → `AssistantTurnView(turn: t, sessionId: id)`.
  Top padding ~70 (room for the top bar overlay), bottom inset for the composer via
  `.safeAreaInset(edge: .bottom) { ComposerView(sessionId: id) }`.
- **Auto-scroll**: stick to the bottom while streaming (use `ScrollViewReader` or `.defaultScrollAnchor(.bottom)` +
  `.scrollPosition`), but stop following if the user scrolls up; show a small glass circle "arrow.down" button to
  jump back down. Scroll to bottom when a new user message is appended.
- `.scrollEdgeEffectStyle(.soft, for: .top)` and `.scrollDismissesKeyboard(.interactively)`.
- Below the last item: "Claude is AI and can make mistakes." style footnote in Theme.sans(13) tertiaryText, using
  the agent's name: "<Agent name> can make mistakes."
- Empty session (no items yet) → same greeting as new chat.

## UserBubble
Right aligned, `Theme.userBubble`, radius 22, padding 14×12, `Theme.sans(17)`, text selection enabled; image
attachments above the text as rounded thumbnails (`RemoteImageView(url:)` from the artifacts task — it exists as a
type; use it with `.frame(width: 120, height: 120).clipShape(RoundedRectangle(cornerRadius: 14))`), other
attachments as small capsules with `doc` icon + name. Long-press context menu: Copy.

## AssistantTurnView (one agent turn, Claude-app style, left aligned, full width)
Read `turn.parts` in order and render:
- The **activity row** first if the turn has any `activity` (thinking/tools/permissions) or is live:
  `ActivityRow(turn: turn)` (from the activity task — exists as a type) — tapping it opens the timeline:
  `ui.summaryTurn = turn`.
- `.text(block)` → `MarkdownView(text: block.text, isStreaming: block.isActive)`.
- `.artifact(a)` → `ArtifactCard(artifact: a)` (exists as a type).
- `.permission(p)` where `p.allowed == nil` → `PermissionCard(request: p, sessionId: sessionId)` (exists).
- `.error(_, msg)` → red-tinted rounded box with `exclamationmark.triangle` + message (Theme.sans 15).
- `.notice(_, text)` → centered small capsule (Theme.sans 12, tertiaryText).
- `.thinking` / `.tool` parts are NOT rendered inline — they live in the activity row/summary.
- While `turn.isLive` and there is no text yet: the activity row shows the working dots (handled by ActivityRow).
- When the turn is finished (`!turn.isLive`): an **action row** of plain icon buttons (Theme.secondaryText, 20pt,
  spacing 22): copy (`square.on.square` → copies all text blocks joined), share (`square.and.arrow.up` →
  ShareLink with the text), retry (`arrow.clockwise` → resend the previous user message:
  find the user message just before this turn in `store.transcript(for:)` and `store.send(text, to:)`), and a
  trailing small label with duration ("12s") and tokens ("4.2k tokens") from `durationMs`/`usage` in tertiaryText.
  Haptic + `ui.toast = "Copied"` on copy.

## MarkdownView (the core of reading quality — make it excellent)
Render agent markdown in `Theme.serif(17)`, ivory, line spacing 5, paragraph spacing 12. Must be robust while
text is still streaming (unclosed code fences, half lists): parse the whole string each time, cheaply.
Support: headings (# … ###### → serif semibold 26/22/19/17), paragraphs with inline **bold**, *italic*, `code`,
[links](url), ~~strike~~ (use `AttributedString(markdown:options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))`
per line/paragraph for inline styling; links tinted `Theme.link`), bullet and numbered lists (nested by indent,
proper hanging indent), > blockquotes (left bar), horizontal rules, tables (horizontal ScrollView grid with
header row bold, hairline separators), fenced code blocks: dark rounded box (#141413), header with language name
and a "Copy" button, `Theme.mono(14)` content, horizontal scrolling, light keyword coloring for common languages is a
bonus (keep it simple and fast). When `isStreaming`, append a soft blinking caret ● in accent at the end.
Text selection enabled (`.textSelection(.enabled)`). Inline code: mono with a subtle rounded background.

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
