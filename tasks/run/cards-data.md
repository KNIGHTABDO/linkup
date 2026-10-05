Linkup rich cards (Data): 11 card views for the chat [shots]

## Your files (only these)
- `ios/Linkup/UI/Cards/CardsData.swift` — replace every stub with the real view, keeping the struct names exactly:
  ChartCard, StockCard, CryptoCard, MetricsCard, TableCard, ComparisonCard, SportsCard, PollCard, ProgressCard, TimelineCard, ConversionCard (each `struct XCard: View { let card: JSONValue }`).
- you may add more files named `ios/Linkup/UI/Cards/CardsData*.swift` for helpers (prefix private helper types with
  `Data` to avoid clashes with the other card tasks working in parallel).

## What these cards are
The agent writes ```linkup-card JSON blocks in its answers; `RichCardView` (already done) dispatches by `type` to your
views. Field names are in this spec (read the whole file): `bridge/linkup_bridge/cards.md` — your section:

### Numbers, data, comparisons
- `chart` — title, kind ("line"|"bar"|"pie"|"area"), unit, series [{name, points [{x, y}]}] (x = label or ISO date, y = number)
- `stock` — symbol, name, price, change, changePercent, currency, points [{x, y}] (recent prices), marketCap, exchange
- `crypto` — symbol, name, price, change24h, changePercent24h, currency, points [{x, y}]
- `metrics` — title, items [{label, value, delta, trend ("up"|"down"|"flat")}]
- `table` — title, columns [text], rows [[text]]
- `comparison` — title, items [{name, image, price, rating, pros [text], cons [text], highlights {label: value}}]
- `sports` — league, status ("Live 67'"|"Final"|"Today 20:00"), home {name, logo, score}, away {name, logo, score}, events [text]
- `poll` — question, options [text] (the user votes in the app; the vote is sent back as a message)
- `progress` — title, items [{label, value (0–1), note}]
- `timeline` — title, items [{date, title, detail}]
- `conversion` — from {value, unit}, to {value, unit}, formula

Every field is optional: render gracefully with whatever is present (no empty labels, no crashes). Read values with
the JSONValue helpers (`card["name"]?.string`, `card["rating"]?.double`, `card.strings("genres")`,
`card.objects("items")`, `card.url("website")`). Wrap each card in `CardContainer` (title = a short label such as
"Restaurant", symbol = a fitting SF Symbol) unless the design calls for a full-bleed image header — then build the same
rounded surface yourself (radius 20, Theme.surface, hairline border). Images: `AsyncImage` with a Theme.elevated
placeholder and graceful failure. Links: open with `@Environment(\.openURL)` or SFSafariViewController.
Cards must look premium, like Apple Maps / Apple Weather / Apple Music detail views compressed into a chat card:
generous spacing, SF Pro for UI text (Theme.sans), serif only for big titles where noted, rounded 12–16 inner
elements, subtle animations. Max width follows the chat column (don't hardcode screen widths).

## Card-specific design and REAL data
- `chart`: Swift Charts (`import Charts`): LineMark/BarMark/AreaMark/SectorMark (pie/donut) per `kind`, one color per
  series (accent, then #7FB0F5, #6FB37E, #E8B04B, #B48CF2), x as dates when ISO else categories, legend, unit on axis,
  tap/drag selection showing the value (chartXSelection).
- `stock`/`crypto`: symbol + name, big price, change (green/red with arrow), sparkline/area chart of points with
  gradient fill, stats row (market cap, exchange). Do NOT fetch market data yourself (no key-free reliable source);
  use the card's numbers.
- `metrics`: 2-column grid of KPI tiles (value big rounded font with numericText, delta colored with trend arrow).
- `table`: horizontally scrollable Grid with header row, zebra rows, numbers right-aligned; copy as CSV in a menu.
- `comparison`: horizontally scrolling columns (one per item: image, name, price, rating, highlights rows aligned by
  label, pros ✓ green / cons ✗ red).
- `sports`: scoreboard (team logos AsyncImage or initials circles, big scores, status pill red "LIVE" pulsing when
  status contains "Live"), events list.
- `poll`: options as tappable bars; tapping sends the vote with `@Environment(\.cardActions)`
  `actions.send("I vote: <option>")` and shows a checkmark (local state).
- `progress`: labeled progress bars/rings. `timeline`: vertical timeline with dots and connecting line.
- `conversion`: from → to big numbers with unit labels and the formula.

Add `#Preview` blocks? NO previews (they'd need sample data). Make sure it compiles with Swift 5 mode / iOS 26.

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
