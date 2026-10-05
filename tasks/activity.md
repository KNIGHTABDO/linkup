Linkup activity: thinking/tool row, Summary timeline sheet, tool details, permission card [shots]

## Your files (only these)
- `ios/Linkup/UI/Activity/ActivityViews.swift` (replace stubs; keep `ActivityRow(turn:)`, `SummarySheet(turn:)`,
  `ToolCallDetailView(tool:)`, `PermissionCard(request:sessionId:)`)
- you may add more files under `ios/Linkup/UI/Activity/`

This is the "very cool design of thinking and tool calls" the user asked for. Copy the Claude iOS app:

## ActivityRow (collapsed, inside the turn, above the answer)
One line, left aligned, height ~32: leading icon area 28pt wide, then the text, then a chevron.
- While `turn.isLive`: leading = `WorkingDots()` (orange pulsing dots); text = `turn.activityLine` in
  `Theme.sans(16)` with a **shimmer** sweeping left→right across the text (secondaryText base, ivory highlight;
  implement with a moving LinearGradient mask, 1.6 s loop). Text changes with `.contentTransition(.opacity)` +
  `.animation(.smooth, value: turn.activityLine)`. Trailing `chevron.right` tertiaryText.
- When finished: leading `clock` (like the screenshot) in secondaryText; text = a summary like the last
  thinking line, or "Thought for 12s" if only thinking, or "Used 4 tools" — choose: if any thinking text exists use
  the last thinking `summaryLine` else "\(n) steps"; plus duration "· 12s" from `turn.durationMs`. One line, truncated.
- Tap anywhere → `ui.summaryTurn = turn` (UIState from environment). Accessibility: button.
- If the turn has a pending permission (`turn.parts` contains `.permission(p)` with `p.allowed == nil`) show the
  text "Waiting for your approval" in accent instead.

## SummarySheet (the "Summary" sheet in the screenshots)
`.presentationDetents([.medium, .large])`, background `Theme.surface`, top bar: glass circle `xmark` (dismiss) left,
centered title "Summary" (Theme.sans 17 semibold). Content: a vertical **timeline** of `turn.activity` in order:
- each entry has a leading 28pt column with an icon (thinking → small 8pt dot in secondaryText; tool →
  `tool.presentation.symbol` in secondaryText, 17pt; permission → `hand.raised`), connected by a 1pt vertical line
  (Theme.hairline) between entries; live entries pulse.
- thinking entry: the thinking text (Theme.sans 17, ivory for the latest, secondaryText for older), collapsible to
  4 lines with "Show more"; while `block.isActive` and empty show "Thinking…" with the shimmer.
- tool entry: title `tool.presentation.title` (Theme.sans 17), trailing `chevron.right`; running tools show a
  small ProgressView; errored tools tint the icon `Theme.danger`. Tap → push `ToolCallDetailView(tool:)` (use a
  NavigationStack inside the sheet). Nested `tool.children` render indented under their parent (sub-agents).
- at the end while the turn is live: "Thinking…" entry with shimmer. When finished: footer "Done · 12s · 4.2k
  tokens · $0.03" (cost only if present) in tertiaryText.
- Auto-scrolls to the newest entry while live.

## ToolCallDetailView
Navigation title = `tool.presentation.activeTitle`. Sections (cards on Theme.elevated, radius 16):
- "Input": if `tool.partialInput` non-nil show it (streaming) else `tool.input.prettyText`, in `Theme.mono(13)`,
  selectable, horizontally scrollable; for common tools show a friendly header first: Bash/run_command → the command
  in a terminal-style box with `$ ` prefix; Read/Write/Edit → file name + path; Edit → old/new strings as a red/green
  diff (input keys `old_string`/`new_string`); WebSearch → the query; Task → the description + prompt.
- "Output": `tool.output` mono 13 (cap the rendered text to the first 20,000 characters with a "Show all" toggle),
  red title if `tool.isError`; `tool.images` → `RemoteImageView(url:)` (exists as a type) full width; artifacts →
  `ArtifactCard(artifact:)` (exists).
- duration (finished - started) and status in the header. A copy button in the toolbar copies the output.

## PermissionCard (inline in the turn while waiting)
Rounded card (Theme.elevated, radius 20, hairline border), header `hand.raised.fill` accent + "\(agent) wants to use
\(request.tool)", the key input (command / file path / url via the same friendly logic) in mono, `request.reason`
if any. Two buttons in a `GlassEffectContainer`: "Deny" (`.buttonStyle(.glass)`) and "Allow" (`.buttonStyle(.glassProminent)`
tinted accent) → `store.answer(request, in: sessionId, allow:)` + haptic. After answering show "Allowed"/"Denied" state.
