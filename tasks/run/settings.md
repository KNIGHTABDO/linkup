Linkup settings: pairing (link/QR/manual), settings sheet, usage dashboard [shots]

## Your files (only these)
- `ios/Linkup/UI/Settings/SettingsViews.swift` (replace stubs; keep `SettingsView()`, `ConnectView()`, `UsageView()`)
- you may add more files under `ios/Linkup/UI/Settings/`

## ConnectView ("Connect to your PC")
Shown on first launch. Big `SparkView(size: 56, animating: true)`, title "Link up your agents" (Theme.serif 30),
subtitle "Run `python -m linkup_bridge pair` on your PC and scan the code." (Theme.sans 16 secondaryText, the
command in mono in a rounded box with a copy button).
- Primary: "Scan pairing code" (`.buttonStyle(.glassProminent)`, accent) → camera QR scanner using
  `DataScannerViewController` (VisionKit, `recognizedDataTypes: [.barcode(symbologies: [.qr])]`) wrapped in a
  UIViewControllerRepresentable; when a `linkup://pair?...` payload is found → `settings.apply(pairingLink: url)`,
  `client.connect()`, dismiss (`ui.isShowingConnect = false`). Check `DataScannerViewController.isSupported/isAvailable`
  and fall back to a message.
- "Paste link" button: reads `UIPasteboard.general.url` or string, applies it the same way.
- Manual section (DisclosureGroup "Enter manually"): Server URL field (placeholder
  "https://your-pc.tailnet.ts.net"), Token SecureField, "Connect" button → set `settings.serverURL`/`settings.token`,
  `client.connect()`; show live `client.state.label` underneath with a status dot; when `.connected` show a
  checkmark and close after 0.8 s.
Background Theme.background, content centered, max width 520.

## SettingsView (sheet, Form `.insetGrouped`, `.scrollContentBackground(.hidden)`, background Theme.surface)
- "Connection": server URL, status (dot + label + latency), "Reconnect" (client.connect()), "Pair again"
  (ui.isShowingConnect = true), "Disconnect" (client.disconnect()).
- "Agents": one row per `store.agents`: symbol, name, status (Available / error text), model count, account label;
  "Refresh agents" → `await store.refreshCatalog(force: true)`.
- "Usage" → NavigationLink to `UsageView()`.
- "About": app version from Bundle, "Bridge on <serverName>".
Glass xmark close top-left, title "Settings".

## UsageView ("Usage")
Real numbers only from `store.usage` (UsageSnapshot) and `store.sessions`:
- **Claude plan** card (if `usage.claude` exists): two big rings or bars: "Current session" = `fiveHour.utilization`
  (0…1 → %) with "Resets in 2 h 14 min" from `fiveHour.resetDate`, and "Weekly" = `sevenDay`; color shifts to
  accent above 80% and danger above 95%; status text from `claude.status` ("allowed", "allowed_warning" → "Close to
  the limit", "rejected" → "Limit reached"). Account label from `store.agent("claude")?.accountLabel`.
  If no rate limit has been seen yet: "Send a message with Claude Code to see your plan usage."
- **Per agent** cards from `usage.totals[agentId]`: input/output tokens (formatted 12.3k / 1.2M), sessions count,
  cost in USD when > 0 (Claude Code reports cost equivalents).
- **Top sessions** by tokens: list of the 8 sessions with the most `usage` (input+cacheRead+cacheWrite+output),
  each with agent icon, title, tokens.
- Pull to refresh → `await store.refreshCatalog(force: false)`.
Glass xmark close, title "Usage", background Theme.surface, numbers animate with `.contentTransition(.numericText())`.

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
