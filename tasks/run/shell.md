Linkup shell: root layout, drawer, top bar and sheet routing [shots]

## Your files (only these)
- `ios/Linkup/UI/RootView.swift` (replace the stub; keep the type name `RootView`)

## Build
RootView is the whole app frame, like the Claude iOS app:
1. **Main layer**: `ChatView(sessionId: ui.currentSessionId)` filling the screen on `Theme.background`.
   Use `.id(ui.currentSessionId ?? "new")` so switching sessions resets scroll state.
2. **Top bar overlay** (not a navigation bar) pinned to the top safe area, horizontal padding 16:
   - left: glass circle 48pt with `line.3.horizontal` → opens the sidebar (`withAnimation(.smooth) { ui.isSidebarOpen = true }`).
   - right: glass capsule (height 48) containing two buttons: `plus.bubble.fill` (new chat: `ui.newChat()`) and
     `ellipsis` (a SwiftUI `Menu` with: "Usage" → ui.isShowingUsage = true, "Settings" → ui.isShowingSettings = true,
     when a session is open also "Rename" (alert with TextField → store.update(id, title:)), "Pin"/"Unpin"
     (store.update(id, pinned:)), "Delete" (destructive, confirmationDialog → store.delete(id); ui.newChat())).
   - Between them, when a session is open, a small centered title: session title (Theme.sans 15 semibold, 1 line)
     and under it the agent name + project (Theme.sans 12, secondaryText), tappable to open the model picker
     (`ui.isShowingModelPicker = true`).
   - A connection pill under the top bar ONLY when `client.state` is not `.connected` (and not in screenshot mode
     with fixtures — i.e. hide when `store.sessions` is non-empty AND state is notConfigured… simpler: show when
     state is `.connecting` or `.offline`): small glass capsule with a dot + `client.state.label`, tap → `client.connect()`.
   Use `GlassEffectContainer` around the top bar items. Real `.glassEffect(.regular.interactive(), in: .circle/.capsule)`.
3. **Drawer**: when `ui.isSidebarOpen`, the main layer slides right by ~82% of the width (max 340pt on iPad stays
   docked? keep it simple: slide on all devices) and dims (black 35% overlay that closes on tap); `SidebarView()`
   sits underneath on the left at that width. Support an edge-swipe from the left edge to open and a swipe left on
   the dimmed layer to close (DragGesture, rubber-band, spring). Spring `.smooth(duration: 0.35)`.
4. **Sheets / covers** routed from UIState (each `.sheet(isPresented:)` with the matching binding):
   - `ui.isShowingSettings` → `SettingsView()`
   - `ui.isShowingConnect` → `ConnectView()` (`.interactiveDismissDisabled(!settings.isConfigured)`)
   - `ui.isShowingUsage` → `UsageView()`
   - `ui.isShowingModelPicker` → `ModelPickerSheet(sessionId: ui.currentSessionId)`
   - `ui.summaryTurn` (item binding: wrap in an Identifiable via `.sheet(item:)` on a computed binding) → `SummarySheet(turn:)`
   - `ui.openArtifact` → `.fullScreenCover(item:)` → `ArtifactViewer(artifact:)`
5. **Toast**: when `ui.toast` is set, a glass capsule at the top with the text, auto-hides after 2.5 s.
   Also show `store.lastError` as a toast (then `store.clearError()`).
6. On appear: if `client.state == .notConfigured && !settings.isConfigured` keep the connect sheet up (AppModel does
   that already — just respect `ui.isShowingConnect`).

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
