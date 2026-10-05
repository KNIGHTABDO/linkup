Linkup usage dashboard v2: live plan usage for Claude Code and Antigravity [shots]

## Your files (only these)
- `ios/Linkup/UI/Settings/SettingsViews.swift` — ONLY the `UsageView` type (rewrite it fully; leave SettingsView and
  ConnectView untouched), plus new files under `ios/Linkup/UI/Usage/`.

## Build (real data only, updates live — the bridge pushes `usage` every minute; views observe `store.usage`)
- **Claude plan** (`store.usage?.claudePlan`, fall back to `store.usage?.claude` when nil): four rings in a 2×2 grid —
  "5-hour session" (fiveHour), "Weekly" (sevenDay), "Weekly · Opus" (sevenDayOpus, only if present), "Weekly · Sonnet"
  (sevenDaySonnet, only if present); each ring animates to its value, center % with numericText, caption
  "Resets in 2 h 14 min" from resetDate using a live `TimelineView(.periodic(from: .now, by: 30))` countdown; colors:
  ivory < 50 %, accent < 80 %, `#E8B04B` < 95 %, danger ≥ 95 %. Subscription label (`claudePlan.subscription`).
  "Updated 12 s ago" (live) from `claudePlan.at`.
- **Antigravity** (`store.usage?.agy`): card with AgentLogo, the credits text exactly as reported (`credits`, e.g. "Out of
  credits" in danger color, or the number), status, per-model quota bars when `models` non-empty (name, remaining %,
  reset time), updated-ago label. When nil: "Antigravity usage appears after the bridge's next check".
- **Hermes**: tokens from `usage.totals["hermes"]`.
- **Per agent totals** (existing): keep, but with AgentLogo, animated numbers, and a small bar chart (Swift Charts) of
  tokens per day for the last 7 days computed from `store.sessions` (bucket each session's total tokens by its
  `updated` day — label it "by last activity").
- **Top sessions** (keep) with AgentLogo.
- Pull to refresh → `await store.refreshCatalog(force: false)`.
- Also create `ios/Linkup/UI/Usage/UsageRing.swift`: `struct UsageRingBadge: View { let utilization: Double?; var size: CGFloat = 18 }`
  — a tiny circular progress ring (stroke 2.5) colored by the same thresholds, for the composer's model pill
  (Claude will wire it). And `UsageAlertWatcher` (ViewModifier `.usageAlerts()`): when Claude's 5-hour utilization
  crosses 0.8 or 0.95 (once per reset window, remembered in UserDefaults by resetsAt) set `ui.toast` to
  "Claude: 80 % of your 5-hour limit used" etc. (Claude will attach it to RootView.)

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
