Linkup composer: glass input, model/agent picker, attachments, dictation [shots]

## Your files (only these)
- `ios/Linkup/UI/Composer/ComposerView.swift` (replace stubs; keep `ComposerView(sessionId: String?)` and
  `ModelPickerSheet(sessionId: String?)`)
- you may add more files under `ios/Linkup/UI/Composer/`

## ComposerView (bottom of the chat, exactly like the Claude iOS composer)
A rounded container (radius `Theme.composerRadius`, glass: `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28))`)
with horizontal margin 12, bottom padding 8:
1. Attachment strip (only when there are attachments): horizontal thumbnails 60pt (images) / capsules (files) with
   an `xmark.circle.fill` remove button, and an upload progress spinner while uploading.
2. Multiline `TextField(placeholder, text:, axis: .vertical)` `Theme.sans(17)`, 1…8 lines. Placeholder:
   new chat → "Chat with \(agent name)"; open session → "Reply to \(agent name)".
3. Bottom row: `+` glass circle 44 (Menu: "Photos" → PhotosPicker (multiple), "Camera" → camera sheet
   (UIImagePickerController wrapped), "Files" → `.fileImporter` any type), then the **model pill**: glass capsule
   with model display name (Theme.sans 15, ivory) and effort in secondaryText e.g. "Sonnet 5.5 Medium" → opens
   `ui.isShowingModelPicker = true`; Spacer; mic glass circle 44 (dictation, see below); and the primary button:
   white circle 44 — when the agent is working (`store.transcript(for:).isWorking`) a black "stop.fill" square
   (→ `store.interrupt(id)`), otherwise when text/attachments non-empty an "arrow.up" (send), otherwise a "waveform"
   icon (starts dictation too).
4. **Send**: trim text; if `sessionId == nil` create the session first:
   `let s = try await store.create(agent: ui.draftAgent, model: ui.draftModel, effort: ui.draftEffort, cwd: ui.draftProject)`
   then `ui.currentSessionId = s.id`, `store.open(s.id)`, then `store.send(text, to: s.id, attachments: uploaded)`.
   Attachments: upload each picked item first with `client.upload(data:name:mime:)` (returns a dict with "path",
   "name", "mime", "url"); pass those dicts as `attachments`. Clear the field immediately, haptic, errors → `ui.toast`.
   Disable send while uploading. Keyboard: return inserts newline; send via button.
5. Model label source: for an open session use `store.session(id)` (agent, model, effort); for a new chat use
   `ui.draftAgent/draftModel/draftEffort`; display name from `store.agent(agentId)?.model(modelId)?.name` (fall back
   to the raw id, and to the agent's `defaultModel`). Effort shown capitalized.
6. **Dictation**: tap mic → live speech-to-text into the field using `SFSpeechRecognizer` + `AVAudioEngine`
   (request permissions; on-device if available); mic button turns accent and pulses while listening; tap again to
   stop. Handle denial with a toast. Put the recognizer in its own small class in your files (`ComposerDictation`).

## ModelPickerSheet
`.presentationDetents([.medium, .large])`, background Theme.surface, glass xmark close, title "Model".
- Top: segmented agent switcher (three glass capsules: Claude Code / Antigravity / Hermes with `AgentKind.symbol`),
  disabled + "Offline" caption when `agent.available == false` (show `agent.error`). For an open session the agent
  can't change (show it fixed); for a new chat it sets `ui.draftAgent` and resets draftModel to the agent's default.
- List of `agent.models` (live from the agent): name (Theme.sans 17), description (secondaryText 14), checkmark on the
  selected one. Selecting: open session → `store.update(id, model:)`; new chat → `ui.draftModel = model.id`.
- If the selected model has `efforts` non-empty: an "Effort" row of capsules (Low/Medium/High/Xhigh/Max) →
  `store.update(id, effort:)` / `ui.draftEffort`.
- Claude only: "Permissions" picker of `agent.permissionModes` (labels: default → "Ask before acting",
  acceptEdits → "Auto-accept edits", plan → "Plan only", bypassPermissions → "Full access") → `store.update(id, permissionMode:)`
  for a session, else stored in UserDefaults key "draftPermissionMode" (read it at create time and pass permissionMode).
- New chat only: "Project" row (folder icon + project name) → list from `store.projects` (call `await store.loadProjects()`
  in `.task`) → `ui.draftProject = path`.
- A footer with the account: `agent.accountLabel` (e.g. "Claude Pro") and a link button "Usage" → `ui.isShowingUsage = true`.
- Pull to refresh → `await store.refreshCatalog(force: true)`.

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
