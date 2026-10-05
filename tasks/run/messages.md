Linkup messages: edit & resend, fork, hand off, pin, export, chat-mode look [shots]

## Your files (only these)
- `ios/Linkup/UI/Chat/MessageViews.swift`, `ios/Linkup/UI/Chat/ChatView.swift`, `ios/Linkup/UI/Chat/MarkdownParser.swift`,
  new files under `ios/Linkup/UI/Chat/`. (Keep `RichTextView(text:isStreaming:)` usage for text blocks and the
  `.environment(\.cardActions, …)` wrapper in AssistantTurnView exactly as they are.)

## Build
1. **User message actions** (context menu + swipe-free): Copy, **Edit & resend** (puts the text in the composer —
   post `NotificationCenter` name `Notification.Name("LinkupComposerSetText")` with the text as object; the composer
   task listens for it — also document it), **Resend**.
2. **Agent turn action row** additions: a "…" menu with **Fork conversation** (`try await store.fork(sessionId)` →
   `ui.currentSessionId = new.id`), **Continue with…** submenu listing the other agents with AgentLogo
   (`store.handoff(sessionId, to: agent, model: nil)` → open it), **Pin message** (local, UserDefaults set of turn ids
   per session; pinned turns get a small pin badge and appear in a "Pinned" strip at the top of the chat that scrolls
   to them), **Export chat** (Markdown of the whole transcript — user/agent text, tool titles as `> Used …` lines —
   shared via ShareLink as a .md file, and "Export as PDF" rendering the transcript text with `ImageRenderer`/
   UIGraphicsPDFRenderer into a PDF file).
3. **Chat-mode sessions** (`store.session(id)?.mode == "chat"`): hide the activity row while the turn is finished
   unless it has errors (rich chat should feel like a consumer assistant), show agent text in `Theme.serif(18)`, and
   show a subtle "Chat" badge in the empty-state greeting area. Cards render through RichTextView already.
4. **Streaming polish**: while text streams, keep it smooth — throttle re-parsing of markdown for very long texts
   (only re-render at most every 50 ms using a small @State-buffer driven by the TextBlock), and make sure the auto
   scroll stays glued to the bottom without jitter.
5. **Header of a turn**: tiny `AgentLogo(agent:size: 16)` + model name (from `turn.model` or session.model) in
   tertiaryText above the first answer of each turn.

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
