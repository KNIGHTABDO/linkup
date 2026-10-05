Linkup rich cards (Do): 15 card views for the chat [shots]

## Your files (only these)
- `ios/Linkup/UI/Cards/CardsDo.swift` — replace every stub with the real view, keeping the struct names exactly:
  RecipeCard, ChecklistCard, StepsCard, ProductCard, CodeCard, ContactCard, EmailCard, TranslationCard, MathCard, QuizCard, PaletteCard, LinkCard, GalleryCard, CalloutCard, FileCard (each `struct XCard: View { let card: JSONValue }`).
- you may add more files named `ios/Linkup/UI/Cards/CardsDo*.swift` for helpers (prefix private helper types with
  `Do` to avoid clashes with the other card tasks working in parallel).

## What these cards are
The agent writes ```linkup-card JSON blocks in its answers; `RichCardView` (already done) dispatches by `type` to your
views. Field names are in this spec (read the whole file): `bridge/linkup_bridge/cards.md` — your section:

### Do & learn
- `recipe` — title, image, time ("35 min"), servings, difficulty, ingredients [text], steps [text], tips [text]
- `checklist` — title, items [{text, done}] (the user can tick items in the app)
- `steps` — title, items [{title, detail, image}] (how-to guides)
- `product` — name, brand, price, currency, rating, reviews, images [url], url, specs {label: value}, summary
- `code` — language, title, code, explanation
- `contact` — name, role, company, phone, email, website, address, photo
- `email` — to, subject, body (the user can open it in Mail)
- `translation` — from (language), to (language), source, result, pronunciation, notes
- `math` — expression, result, steps [text]
- `quiz` — title, questions [{question, options [text], answer (index), explanation}]
- `palette` — title, colors [{hex, name}]
- `link` — url, title, description, image, site
- `gallery` — title, images [{url, caption}]
- `callout` — style ("info"|"tip"|"warning"|"success"|"error"), title, text
- `file` — name, url, size, kind

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
- `recipe`: hero image, time/servings/difficulty chips, ingredients with checkboxes (local state), numbered steps,
  tips callout; "Cook mode" button: full-screen sheet showing one step at a time, large type, keeps the screen on
  (`UIApplication.shared.isIdleTimerDisabled` while open).
- `checklist`: tappable rows with animated check circles (local state, persisted per card with @AppStorage keyed by a
  hash of the card JSON), progress "3 of 7".
- `steps`: numbered cards with optional images. `product`: image carousel, brand, name, price big, rating, specs grid,
  "View" link. `code`: syntax-highlighted mono block with language badge, Copy, and explanation.
- `contact`: avatar, name/role/company, action buttons (call, mail, website, maps) and "Save to Contacts" via
  `CNContactViewController` (ContactsUI, presented for a new unsaved contact — no permission needed).
- `email`: To/Subject/Body preview + "Open in Mail" (`mailto:` URL with percent-encoded subject/body) + Copy.
- `translation`: source/result with language labels, pronunciation, speak button (AVSpeechSynthesizer with the
  target language), copy.
- `math`: expression and result big (mono for math), steps list.
- `quiz`: one question at a time, tap an option → green/red feedback + explanation, score at the end, "Send my score"
  via cardActions.send.
- `palette`: color swatches (tap copies hex, toast-free: show "Copied" inline), names.
- `link`: rich link preview (image, title, description, site) → opens SFSafariViewController.
- `gallery`: grid of images (2 columns), tap → full-screen pager with zoom.
- `callout`: tinted box per style with SF Symbol (info.circle, lightbulb, exclamationmark.triangle, checkmark.seal,
  xmark.octagon). `file`: icon by kind, name, size, open via `ui.openArtifact` with an ArtifactRef built from url.

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
