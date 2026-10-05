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
