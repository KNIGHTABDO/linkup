Linkup artifacts: artifact cards, full-screen viewer (HTML, images, PDF, video, files), remote images [shots]

## Your files (only these)
- `ios/Linkup/UI/Artifacts/ArtifactViews.swift` (replace stubs; keep `ArtifactCard(artifact:)`,
  `ArtifactViewer(artifact:)`, `RemoteImageView(url:)`)
- you may add more files under `ios/Linkup/UI/Artifacts/`

Agents produce files: HTML pages, images (Antigravity has image generation), SVG, PDF, markdown, video, audio,
code. The bridge serves them at relative URLs; ALWAYS turn them into real URLs with `client.resolve(relativeURL)`.

## ArtifactCard (inline, like the Claude "Slack Tide · Artifact" card)
Full-width rounded card (radius 18, `Theme.surface` with hairline border), height ~76: a 56×56 rounded tile on the
left (`Theme.artifactTile` indigo for html/svg/code with `square.on.circle`-style icon; for images show the actual
image thumbnail via RemoteImageView; pdf `doc.richtext`, video `play.rectangle`, audio `waveform`, markdown
`doc.text`, other `doc`), then title (Theme.sans 17 semibold, ivory) and subtitle (Theme.sans 15 secondaryText):
"Artifact" for html/svg, "Image", "PDF", "Video", "Audio", or the file size formatted with ByteCountFormatter.
For `kind == "image"` show instead a large inline image (full width, max height 360, aspect fit, radius 16) with the
title under it — images must appear directly in the chat. Tap → `ui.openArtifact = artifact`.
Context menu: Open, Share (download to a temp file then share), Copy link.

## ArtifactViewer (full-screen cover)
Top bar like the screenshot: glass circle `xmark` left (dismiss), centered title, glass capsule right with
`square.and.arrow.up` (share the file: download with URLSession to a temp file named `artifact.title`, then
ShareLink / UIActivityViewController) and `arrow.clockwise` (reload).
Content by kind:
- html / svg / pdf / markdown / code / file (text-like): a `WKWebView` (UIViewRepresentable) loading
  `client.resolve(artifact.url)` (the token in the URL lets the bridge set a cookie so the page's own CSS/JS/images
  load too). Enable JavaScript, inline media playback, back/forward gestures, pinch zoom for pdf/svg; show a thin
  accent progress bar while loading (KVO `estimatedProgress`); errors → centered message with Retry.
  For markdown use the web view too (the browser shows it as text) — fine.
- image: zoomable image (pinch + double-tap zoom, pan) on black, using a ScrollView-based zoom or MagnifyGesture.
- video / audio: `AVPlayer` with `VideoPlayer` (import AVKit).
Background black for media, Theme.background otherwise. Swipe down to dismiss for images.

## RemoteImageView(url:)
`url` is bridge-relative (or absolute). Load with `AsyncImage(url: client.resolve(url))` with a shimmering
rounded placeholder (Theme.elevated) while loading and an `photo` + "Couldn't load image" state on failure.
`.scaledToFit()` by default; callers set frames. Tap → full screen viewer (present `ArtifactViewer` with an
`ArtifactRef(id: url, kind: "image", title: "Image", url: url, path: nil, mime: nil, size: nil)` via
`ui.openArtifact`).

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
