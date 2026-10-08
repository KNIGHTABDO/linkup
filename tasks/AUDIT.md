# Linkup full audit — 2026-10-08

9 Haiku auditors, read-only, ~413 findings (73 High / 220 Med / 120 Low). Several overlap across sections (noted below).
Items marked ✅ were re-verified against the code by Opus; the rest are Haiku findings, mostly accurate but unverified on device.

## A. Fix-first (crashes, hangs, lost data, broken core loop)
1. ✅ **App hang**: code highlighter never advances on `$` (bash `$HOME`) or `#` in C/C++ → infinite loop — `ios/Linkup/UI/Chat/MarkdownParser.swift:364,386`
2. ✅ **Claude replies vanish**: bridge ignores text/thinking in `assistant` messages incl. API-error text (rate limit/auth) — `bridge/linkup_bridge/agents/claude.py:256`
3. **Failed turns have no reason**: `result.is_error` / `error_max_turns` never forwarded; process crash stderr hidden — `claude.py:279-292, 227-232`
4. **Messages silently dropped offline**: `post()` returns when socket nil; composer already cleared text+attachments; permission answers lost — `LinkupClient.swift:251`, `ComposerView.swift:548`, `SessionStore.swift:166`
5. **Dead socket never detected**: ping failures ignored, `reconnectIfNeeded` skips when "connected", no NWPathMonitor, 401 shown as "can't reach PC" forever — `LinkupClient.swift:156,182,204`
6. **Events lost/out of order**: replay vs live broadcast interleave; client drops lower seq; no gap resync; replay capped at 20k rows; undecodable frames dropped — `server.py:79-109,289-312`, `store.py:96`, `Transcript.swift:38`
7. **Two Claude processes per session** (warm + send race) and agy double-process on quick follow-ups — `claude.py:103-130`, `server.py:227`
8. **Stale permission cards / agent hangs**: turn end leaves Allow/Deny live; no `control_cancel_request`; no allow-always; Edit/Write prompts don't show the diff — `Transcript.swift:152`, `claude.py:190-302`, `ActivityViews.swift:1204`
9. **Stuck "working" states**: error with no live turn opens a phantom turn; `status: interrupted` mid-turn; duplicate tool rows from agy `tool.start` — `Transcript.swift:57,84,137`
10. **HEIC photos break Claude turns** (unsupported mime), large photos >5 MB fail — `ComposerView.swift:156`
11. ✅ **"Edit & resend" and ⌘K do nothing** (notifications posted, never observed) — `MessageViews.swift:107`, `RootView.swift:328`
12. ✅ **Fake data in production**: usage dashboard falls back to screenshot fixture; widget shows placeholder 42%/18% — `UsageDashboardView.swift:53`, `LinkupWidgetSnapshot.swift:161`
13. **Git commit/push always show "success"**; `git add -A` stages everything — `GitStatusView.swift:345,370`, `workspace.py:515-555`
14. ✅ "Runn command failed" title bug — `ToolPresentation.swift:53`
15. agy/Hermes: stderr pipe can deadlock agy; exit 0 with no result = silent empty reply; Hermes HTTP errors ignored; user Stop shown as failure — `agy.py:81,125,132`, `hermes.py:98,149`

## B. Security (bridge is on Tailscale Funnel = internet-facing behind token)
- ✅ `/linkup/files` sibling lookup serves any file under a registered file's folder (e.g. `~` → `~/.linkup/token`, `~/.hermes/.env`) — `server.py:503`
- Workspace `allowed()` = whole home incl. dotfiles — `workspace.py:40`
- Dev proxy reaches any localhost port (Hermes 8642…) and forwards Authorization — `server.py:536`, `workspace.py:625`
- `send` accepts any PC path as attachment; upload has no size cap; token copied to clipboard via "Copy Link" and visible to artifact JS — `server.py:213,517`, `ArtifactViews.swift:261,332`
- commands.py fork: if `execvp` fails, child continues as a second bridge — `commands.py:206`

## C. Navigation & shell (why it "feels buggy")
- 12 separate sheets on RootView fight each other (Settings→Pair again, model sheet→Usage silently fail) → one `ActiveSheet` router
- ChatView/composer recreated on rotation/size-class change and on every session switch → drafts + scroll lost; no per-session drafts
- iPhone Max landscape gets iPad 3-column layout; iPad portrait with inspector leaves ~130pt for chat
- Disconnect undone on every foreground; deep link silently overwrites pairing; manual connect overwrites working config before testing
- Drawer: actions don't close it; swipe rows conflict with scroll; edge-swipe strip covers hamburger; not RTL-aware
- Toasts render behind sheets → errors invisible in Connect/Import/Voice
- Auto-scroll snaps you back while streaming (180pt threshold)

## D. Response rendering
- Markdown/cards/highlighter re-parsed on every streamed token (perf); throttled text may miss last chunk; caret floats right
- Loose lists split, no `~~~` fences, tables never wrap, pipes in code break tables, no images/LaTeX
- No "Stopped" marker, no timestamps, token counts inflated by cache reads, $ cost shown on subscription
- Tool detail: raw JSON uncapped and duplicated, Write/MultiEdit have no diff, timers don't tick, huge outputs freeze

## E. Visual (why it "looks bad")
- 78 hard-coded colors, 278 `.system(size:)`, 13 corner radii, 11 paddings, zero Dynamic Type
- Liquid Glass used on content (cards, place chips, composer container, toasts) instead of controls only
- Body text at 10–13pt, low-contrast tertiary text (3.3:1), pure-black artifact viewer vs warm theme
- Cards: 48 overlapping types, PlaceCard 9 blocks deep, currency shows 1:1 while loading, weather always "day" → consider cutting ~10 card types

## F. Missing features worth considering
Hardware keyboard (Return=send on iPad), offline outbox/queue + send-while-working queue, paste/drag images, session rows with agent·project·time, full-text search, `linkup://session/<id>` deep links, Stop from Live Activity when app suspended, Live Activities that end/go stale, schedule run history, per-commit diff, Compare per-column stop/"use this", Handoff context preview, light mode / appearance setting, Arabic RTL + XXL text in screenshot CI.

---
# Full findings by area (raw auditor output)

## 1. Navigation, shell, sidebar, settings, iPad

BUGS

1. [High] ios/Linkup/UI/RootView.swift:126-169 - Twelve sheet/fullScreenCover presentations hang off one view, each with its own binding. SwiftUI presents one at a time per presenter, so combinations (Settings open, then something else opens) drop or fight. Fix: one `enum ActiveSheet` driving a single `.sheet(item:)` plus one `fullScreenCover`.
2. [High] ios/Linkup/UI/Settings/SettingsViews.swift:343-349 - "Pair again" sets `ui.isShowingConnect = true` while SettingsView (itself a sheet on RootView) is still presented and never dismisses itself, so the Connect sheet will not appear. Fix: dismiss Settings first, then present Connect from its `onDismiss`.
3. [High] ios/Linkup/UI/Settings/SettingsViews.swift:678-691 (and 220-223, 247-258) - `hasFound` latches on the first barcode whose string parses as a URL (any QR text does). `applyAndConnect` then returns false for non-Linkup codes and the result is ignored, so the scanner is stuck with no message. Fix: latch only when `settings.apply` succeeds; otherwise show "Not a Linkup pairing code" and keep scanning.
4. [High] ios/Linkup/UI/Settings/SettingsViews.swift:243 and ios/Linkup/UI/Sidebar/SidebarView.swift:815 - Toasts are drawn by RootView's overlay (RootView.swift:301-302), which sits behind the ConnectView and HistoryImportSheet sheets. The clipboard error and the import error are invisible. Fix: show an inline message inside the presented sheet.
5. [High] ios/Linkup/UI/RootView.swift:314-329 - ⌘K posts `"LinkupFocusSearch"`, but nothing observes it (grep finds only the post). The search field never opens or gets focus, so this is the spec's ⌘K requirement left unimplemented. Fix: SidebarView `.onReceive` sets `isSearching = true` and focuses a `@FocusState` field.
6. [High] ios/Linkup/UI/RootView.swift:119-123 and 243/364 - The layout is chosen by horizontalSizeClass. iPhone Plus/Max in landscape reports `.regular` and gets the iPad 3-column layout. Rotation or Split View moves ChatView between `if/else` branches, recreating it and losing the composer draft and scroll position. Fix: choose the layout by idiom plus a width threshold, and keep ChatView in one stable position.
7. [High] ios/Linkup/UI/RootView.swift:227-265 - Fixed widths of 320 (sidebar) and 380 (inspector) leave roughly 130 pt for chat on an 11-inch iPad in portrait (834 pt), and less on iPad mini. Fix: below about 1100 pt, auto-hide the sidebar when the inspector opens, or show the inspector as an overlay.
8. [High] ios/Linkup/UI/Settings/SettingsViews.swift:352-354 with ios/Linkup/App/LinkupApp.swift:25-27 - Disconnect is undone on every foreground. `scenePhase == .active` calls `reconnectIfNeeded()`, which connects from `.offline`. Fix: persist a `userDisconnected` flag and skip auto-reconnect while it is set.
9. [Med] ios/Linkup/UI/Sidebar/SidebarView.swift:213-217 and 377-379 - Projects, Running, Compare, Scheduled and the settings avatar do not close the drawer. After dismissing the sheet the user returns to an open drawer; only SchedulesView (line 341) closes it. Fix: set `ui.isSidebarOpen = false` in each action.
10. [Med] ios/Linkup/Core/Net/LinkupClient.swift:251-257 and ios/Linkup/Core/Store/SessionStore.swift:171-186 - `post()` silently returns when offline. Delete removes the session locally first, so it reappears on reconnect. Pin and rename do nothing with no feedback. Fix: check connection state before acting, show "Offline" feedback, or queue the op.
11. [Med] ios/Linkup/App/LinkupApp.swift:62-67 with ios/Linkup/Core/Net/LinkupClient.swift:32-41 - Any `linkup://pair` URL silently overwrites the saved server and token and reconnects, with no confirmation. Fix: when already configured, confirm with an alert naming the new host.
12. [Med] ios/Linkup/UI/Settings/SettingsViews.swift:159-162 - Manual Connect overwrites the saved serverURL and token before testing. A typo leaves the app pointed at a dead server and the working config is lost. Fix: test with a temporary connection and commit only on `.connected`.
13. [Med] ios/Linkup/UI/Settings/SettingsViews.swift:656 - `try? scanner.startScanning()` in `makeUIViewController` swallows errors. Camera denial shows a blank view with no explanation. Fix: start scanning in `viewDidAppear` and show a "Enable camera in Settings" message on denial.
14. [Med] ios/Linkup/UI/Sidebar/SidebarView.swift:310-349 and 881-885 - `filteredSessions`, `groupedRecents` and `pinnedSessions` are recomputed over all sessions on every render, and a `RelativeDateTimeFormatter` is allocated per history row. Fix: compute groups once on store change and share one static formatter.
15. [Med] ios/Linkup/UI/Sidebar/SidebarView.swift:492-597 - Swipe-reveal state is per row with no coordination, so several rows can stay revealed. The reveal also survives drawer close, and the simultaneous drag gesture competes with ScrollView scrolling. Fix: use `List` with `.swipeActions`, or lift a single `revealedId` into SidebarView and clear it on scroll and close.
16. [Med] ios/Linkup/UI/RootView.swift:591-600 and 443-460 - The edge-swipe strip (0-28 pt, layered above the top bar) covers the left 12 pt of the hamburger button, which starts at x=16. Fix: start the edge strip below the top bar, or inset the hamburger.
17. [Low] ios/Linkup/UI/RootView.swift:170-179 vs ios/Linkup/UI/Sidebar/SidebarView.swift:66-68 - The RootView rename alert accepts an empty title, while the sidebar rejects one. Fix: share one rename helper that trims and rejects empty input.
18. [Low] ios/Linkup/UI/RootView.swift:278 - Drawer width 340 applies to every `.pad` compact case, including Slide Over at about 320 pt, which makes the drawer wider than the window. Fix: `min(340, screenWidth * 0.82)`.
19. [Low] ios/Linkup/UI/Sidebar/SidebarView.swift:428-430 - The footer tap does nothing when `notConfigured`, because `connect()` just sets the same state. Fix: hide the footer tap or route it to ConnectView.
20. [Low] ios/Linkup/UI/RootView.swift:202-208 - The error toast auto-hides after 2.5 s, so connection and store errors vanish before they can be read. Fix: keep error toasts until dismissed or until the next success.

VISUAL

21. [Med] ios/Linkup/UI/Theme/Theme.swift:25-27 - `sans`, `serif` and `mono` use fixed `.system(size:)`, so no chrome honors Dynamic Type. Fix: use `Font.custom(_:size:relativeTo:)` or `@ScaledMetric`.
22. [Med] ios/Linkup/UI/Settings/SettingsViews.swift:55 - The string literal contains backticks, which render on screen: "Run `python -m linkup_bridge pair`". Fix: build an AttributedString with the command in a monospaced run.
23. [Low] ios/Linkup/UI/Sidebar/SidebarView.swift:399-402 - "New session" is black text on pure `Color.white`, outside the Theme palette (ivory `Theme.text`). Fix: use Theme tokens.
24. [Low] ios/Linkup/UI/Sidebar/SidebarView.swift:181 and 562 - `Color(white: 0.45)` and hard-coded `#3A82F7` replace existing tokens (`Theme.tertiaryText`, `Theme.link`). Fix: use the tokens.
25. [Low] ios/Linkup/UI/Sidebar/SidebarView.swift:124-155 vs 676-704 - The sidebar search field uses `Theme.surface` and the history sheet search uses `Theme.elevated`, with different padding. Fix: one shared SearchField component.
26. [Low] ios/Linkup/UI/RootView.swift:562 - The title overlay uses a fixed 96 pt horizontal padding, so on a 320 pt SE the title is squeezed to about 128 pt. Fix: put the title in a principal toolbar or size it from the proxy width.
27. [Low] ios/Linkup/UI/RootView.swift:632 - The transient toast uses `.glassEffect`, which is glass on content rather than a control. Fix: use a plain `Theme.elevated` capsule.
28. [Low] ios/Linkup/UI/Settings/SettingsViews.swift:90, 138, 155, 197 - Corners mix `RoundedRectangle(cornerRadius:)` with `.continuous`, which the sidebar and other views use. Fix: use `.continuous` everywhere.
29. [Low] ios/Linkup/App/LinkupApp.swift:18 - `.preferredColorScheme(.dark)` is hard-coded and Settings offers no appearance option. Fix: add a System / Light / Dark picker, or document dark-only as deliberate.
30. [Low] ios/Linkup/UI/Sidebar/SidebarView.swift:49-50 - `Color.clear.frame(height: 120)` is a magic number that must match the bottom overlay height, and it breaks under larger text sizes. Fix: measure the overlay with `safeAreaInset(edge: .bottom)`.
31. [Low] ios/Linkup/UI/RootView.swift:477-530 - The top-bar ellipsis mixes global items (Usage, Settings) with session actions in one unlabeled menu with no sections. Fix: split into a global menu and a session menu, or add section headers.

UX-NAVIGATION

32. [Med] ios/Linkup/UI/Sidebar/SidebarView.swift:223-306 - There is no empty state when the account has zero sessions; the drawer shows only agent rows and "New session". Fix: a short onboarding card ("Start a chat with Claude Code").
33. [Med] ios/Linkup/UI/RootView.swift:380-400 - The drawer can only be dragged closed from the 18% scrim strip; the drag gesture is not attached to the sidebar layer itself. Fix: attach the same DragGesture to the sidebar layer.
34. [Low] ios/Linkup/UI/Settings/SettingsViews.swift:460 - Settings opens at `.medium` over a long Form. Fix: default to `.large`.
35. [Low] ios/Linkup/UI/Settings/SettingsViews.swift:498-502 - The pushed Usage page shows a redundant X close next to the back button. Fix: remove it and rely on sheet dismissal.
36. [Med] ios/Linkup/UI/Sidebar/SidebarView.swift:794-803 and 742-770 - The history sheet has no pull-to-refresh and no re-fetch after a failed refresh; "Try again" appears only in the empty state. Fix: `.refreshable` on the List.
37. [Med] ios/Linkup/UI/RootView.swift:569-588 - The connection pill shows a label only. Tapping reconnects, but there is no last-error detail or retry countdown. Fix: a tap-through sheet showing last error and next retry time.
38. [Low] ios/Linkup/UI/Settings/SettingsViews.swift:129-147 - The manual form has no submit key, so Return does not trigger Connect. Fix: `.onSubmit` plus a `FocusState` chain from URL to token.

MISSING / ENHANCEMENTS

39. [Med] ios/Linkup/UI/Sidebar/SidebarView.swift:544-566 - Session rows show only the title, with no agent name, project, time or preview. Fix: add a second line such as "Claude Code · project · 2h".
40. [Med] ios/Linkup/UI/Sidebar/SidebarView.swift:310-319 - Search matches only title and preview, not message content. Fix: add a bridge search op backed by full-text indexing.
41. [Med] ios/Linkup/UI/Settings/SettingsViews.swift:299-361 - Settings has no "Forget server / sign out" (which would clear the Keychain token), no default agent, model or effort, and no clear-local-cache action. Fix: add these rows.
42. [Low] ios/Linkup/UI/Sidebar/SidebarView.swift:26 - The drawer has no pull-to-refresh to re-sync sessions. Fix: `.refreshable { await store.refreshCatalog() }`.
43. [Low] ios/Linkup/UI/Sidebar/SidebarView.swift:163-181 - Agent availability is a color-only dot with no accessibility label, and `AgentLogo` is unlabeled. Fix: add "Available" or "Unavailable" labels.
44. [Low] ios/Linkup/UI/RootView.swift:314-348 - Shortcuts cover only ⌘N, ⌘K, ⌘., and ⌘[. Missing: ⌘, for Settings, ⌘1–9 to switch sessions, and ⌘⇧I for the inspector. Fix: add them to `keyboardShortcuts`.
45. [Low] ios/Linkup/App/LinkupApp.swift:20 and 62-67 - `onOpenURL` handles only `linkup://pair`. There is no `linkup://session/<id>` route for widgets, Shortcuts or Handoff. Fix: a small URL router in AppModel.

## 2. Chat rendering & response handling (iOS)

BUGS
1. [High] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MarkdownParser.swift:364-367 and 383-393 - A `$` outside a string (bash `$HOME`, PHP, Perl, Makefile) enters the word branch, consumes nothing, and never advances `i`, so the highlighter loops forever and the app hangs on the first such code block - Advance `i` by at least one character in every branch, and treat `$` as a symbol when not followed by a letter.
2. [High] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MarkdownParser.swift:317 and 386 - For `c`/`cpp` the `#` comment branch is skipped, but the symbol loop breaks on `#`, so `#include` hangs the same way - Drop the `#` break in the symbol loop for C/C++, or force progress by one character.
3. [High] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MessageViews.swift:104-109 - "Edit & resend" posts `.linkupComposerSetText`, but nothing in the codebase observes it, so the menu item does nothing - Add `.onReceive(NotificationCenter.default.publisher(for: .linkupComposerSetText))` in ComposerView that sets its text.
4. [High] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/ChatView.swift:92, 153, 160-164 - While streaming, the "scrolled up" threshold is 180pt and auto-scroll runs on every event unless that flag is set, so any upward scroll under 180pt is snapped back within 75ms - Set the flag immediately on user drag (`onScrollPhaseChange` interacting) and use a smaller threshold (about 40pt) while working.
5. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MessageViews.swift:606-620 - The throttle Task captures the `let text` from the view struct when it was scheduled, and later updates inside the window are dropped, so the displayed tail can lag or miss the last chunk until the next delta or stream end - Keep the latest text in a `@State`/box that the Task reads, or flush on a trailing timer with the newest value.
6. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/ChatView.swift:17-19 - A session whose events have not arrived yet shows the "Hello, night owl" greeting and empty state instead of a loading indicator - Add a `loaded` state from `subscribe`/cache and show a spinner until the first event.
7. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/SessionStore.swift:26-31 - `transcript(for:)` synchronously reads and decodes the full JSONL cache on the main thread, and it is called from view bodies (ChatView.swift:17, ComposerView.swift:39) - Preload transcripts off-main at launch or cache the decoded result.
8. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/Transcript.swift:57 and /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MessageViews.swift:268 - A `status` of `interrupted` or `error` mid-turn sets `phase` while `liveTurn` stays set, so `isLive` is false, the action row and copy/share show while the turn still runs, and `isWorking` stays true - Only set phase from `status` to running/requesting, and end the turn solely on `turn.end`.
9. [Med] /home/knight/Desktop/projects/linkup/bridge/linkup_bridge/agents/hermes.py:152 and /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/Transcript.swift:145 - Hermes `run.cancelled`/`run.stopped` send `isError: true`, and the reducer only maps `stopReason == "interrupted"`, so a user stop shows as a failed turn - Map cancelled/stopped to `interrupted` in the adapter or the reducer.
10. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/Transcript.swift:152 and /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MessageViews.swift:229 - Turn end clears `pendingPermissions` but leaves `.permission` parts with `allowed == nil`, so a permission card with live buttons stays in finished turns - At `turn.end`, set `allowed = false` on unresolved requests and hide the card.
11. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/Transcript.swift:149 - Tools still running at turn end are marked finished with `isError == false`, so an interrupted or failed tool reads as "Ran command" success - Add a `stopped` state to ToolCall and show "Stopped" for those tools.
12. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/Transcript.swift:84-90 - A repeated `tool.start` for an existing id re-appends the same ToolCall to `turn.parts` and `children`, producing duplicate rows with identical `TurnPart` ids (agy emits `tool.start` on each ACTIVE step) - Return early when `tools[id]` already exists and only update name/input.
13. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/Transcript.swift:15-18, 86 - The tools/texts/thinking maps are never cleared per turn, so a reused id attaches an old ToolCall object to a new turn (shared state, duplicated ids) - Scope maps per turn or namespace ids by turn.
14. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/Transcript.swift:137-138 - An `error` event with no open turn calls `turn(date)`, which creates a new live turn and sets `liveTurn`, so the stop button and "Working" state stay until a later `turn.end` - Attach the error to the last assistant turn when none is live, and do not open a turn.
15. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/Transcript.swift:38-39 - Seq gaps are not detected, so a dropped event (e.g. a `tool.end`) leaves a tool spinning forever with no resync - When `e.seq > lastSeq + 1`, re-subscribe with `since: lastSeq` before applying.
16. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/Transcript.swift:62, 96-101 - `thinking.start` and `tool.update` ignore `parent`, so sub-agent thinking and tools show as top-level parts in the main turn - Route them to the owner tool's children or skip them when `parent` is set.
17. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MessageViews.swift:530 and /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Cards/RichTextView.swift:9 - The markdown parser and `CardExtractor.segments` run on every body evaluation, and the body re-runs on every streamed token - Cache parsed blocks keyed by text (in TextBlock or `@State`) and move the text read into a child view.
18. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MessageViews.swift:225 and /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/Transcript.swift:228-236 - `AssistantTurnView.body` reads `block.text` and recomputes `turn.activity`, `hasErrors` and `shouldShowActivityRow` on every token - Pass the TextBlock to a child view that observes only its own text.
19. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MessageViews.swift:277-283 - `devServerPorts` scans up to 20k chars of every tool output with a detector on each body evaluation - Compute once when the turn finishes and store the result.
20. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MessageViews.swift:714 - `ChatSyntaxHighlighter.highlight` runs on every render of a code block, building an AttributedString per token, including during streaming - Memoize the highlighted result by (code, language).
21. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/ChatExportHelper.swift:317-322 - Markdown and PDF export run synchronously on the main actor, and PDF layout for 1000+ events blocks the UI - Snapshot the items and render in a detached task before handing the URL to the share sheet.
22. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/Transcript.swift:161 - Turn ids are `"a\(lastSeq)"`, so they collide when events have no seq and reset ids across reloads, breaking pins and scroll targets - Derive ids from the starting event's seq or a UUID stored in the cache.
23. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/Transcript.swift:168 and 76-81 - A text or thinking delta with no `block` gets `"b\(seq)"` as its id, so each delta creates a new paragraph - Fall back to the last open block of the same kind instead of a per-event id.
24. [Med] /home/knight/Desktop/projects/linkup/bridge/linkup_bridge/agents/claude.py:288-291 and /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/Transcript.swift:145-146 - A failed Claude turn sends `turn.end` with `isError` and no `text`, so the reducer adds no error part and the user sees a red turn with no explanation - Forward the result's error text in `turn.end.text` or emit an `error` event before it.
25. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/Transcript.swift:132 and /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MessageViews.swift:495-505 - Turn "tokens" sums input + cacheRead + cacheWrite, so a small answer reads as "52.1k tokens" from cached context - Show output tokens separately and label cache reads, or exclude them from the total.
26. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/ToolPresentation.swift:53 - The error title does `replacingOccurrences(of: "ing", ...)` on the active verb, so "Running command" becomes "Runn command failed" and "Using Foo" becomes "Us Foo failed" - Give each verb an explicit failed title.
27. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/ToolPresentation.swift:12-24 and 30-43 - Hermes names such as `write_file`, `patch` and `skill_view` are not mapped, so they render as "Using write file" with a wrench - Add aliases for these names.

RESPONSE-HANDLING
28. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MarkdownParser.swift:145 - A blank line ends a list, so loose lists become separate blocks with 12pt gaps and inconsistent bullet/number alignment - Continue the list across blank lines when the next non-blank line is a list item.
29. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MarkdownParser.swift:248-253 - `parseCells` splits on every `|`, so escaped `\|` and pipes inside inline code break table cells - Split only on unescaped pipes outside backticks.
30. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MarkdownParser.swift:66 - Only backtick fences are recognized, so `~~~` fences show as raw paragraphs - Accept `~~~` as an opening and closing fence.
31. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MarkdownParser.swift:155 - Continuation lines of a list item are joined with spaces, which flattens paragraphs inside items - Keep newlines and render them as separate paragraphs within the item.
32. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MarkdownParser.swift:272 - The numbered-item regex matches a sentence starting with a year, e.g. "2024. It was", and turns it into a list item - Require a small number or a following space after a sentence-like prefix, or restrict to lines that start a list block.
33. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/ChatExportHelper.swift:33-36 - Consecutive text blocks are appended with a single newline, so markdown paragraphs and "> Used" lines merge in the .md export - Append a blank line between parts.
34. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/ChatExportHelper.swift:22 - Attachment links are bridge-relative (`/linkup/files/...`) and resolve to nothing outside the app - Export with absolute URLs via `LinkupClient.resolve(_:)` or drop the links.
35. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/ChatExportHelper.swift:203, 233-242 - The PDF prints assistant text raw, so `**`, `#`, fences and table pipes appear literally - Run the text through `ChatMarkdownParser` and draw styled runs, or strip markers.
36. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/ChatExportHelper.swift:101 - `try? renderer.writePDF` swallows failures, so the share sheet can offer a missing file - Catch the error and surface it as a toast.
37. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MessageViews.swift:468-481 - Retry resends only the text and drops attachments, unlike Resend - Pass the attachments the same way UserBubble does.
38. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MessageViews.swift:486-492 - Durations are shown as whole seconds with no minutes, so 125 s reads "125s" - Format as "2m 5s" above 60s.
39. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MessageViews.swift:334-338 - Copy and Share act on text blocks only, so artifact-only turns copy and share an empty string - Hide them or include the artifact titles and links.
40. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/ChatView.swift:257 - The pinned-strip fallback shows the raw model id (e.g. "claude-opus-…") when the answer has no text - Show the agent name or "Answer".

VISUAL
41. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MessageViews.swift:539-546 - The streaming caret sits in an HStack beside a multi-line Text, so it floats to the right of the longest line rather than after the last word, and the structure switches when streaming ends - Append the caret as a `Text` run (`Text(attr) + Text(" ●")`) so it follows the text.
42. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MessageViews.swift:751-768 - Tables sit in an unbounded horizontal ScrollView, so cells never wrap and long cells make very wide single-line tables - Give cells a max width with multiline wrapping, or switch to a stacked layout on phone widths.
43. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MessageViews.swift:840-848 - Bullets use a 14pt column and numbers a 20pt minimum, so text indents differ between list types, and nested bullets all use "•" - Use one fixed marker column and vary the glyph by level.
44. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MessageViews.swift:532, 647 - Headings add their own top padding inside a 12pt VStack, so spacing before headings is doubled - Remove the extra top padding.
45. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MessageViews.swift:707, 721 and /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MarkdownParser.swift:210 - Code block and inline-code colors are hard-coded instead of Theme tokens, and inline code uses mono(15) against serif(17) text - Move them to Theme tokens and match the text size.
46. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MessageViews.swift:692-703 - The code block Copy target is a small text button with no minimum hit area - Add `.contentShape` and a 44pt minimum frame.
47. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MessageViews.swift:574 - `.textSelection` is applied per block, so a selection cannot span paragraphs or code blocks as in the Claude app - Use one selectable container for the paragraphs of a turn.
48. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Cards/RichTextView.swift:25 - `.animation(.smooth, value: segments.count)` animates the layout whenever a pending card resolves, which causes visible jumps while streaming - Limit the animation to card insertions.

MISSING / ENHANCEMENTS
49. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MessageViews.swift (whole file) - The `interrupted` phase is never rendered, so a stopped reply shows no "Stopped" marker - Add a small "Stopped" label to finished interrupted turns.
50. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/Transcript.swift:23 and /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MessageViews.swift (no time shown) - `UserMessage.date` and `AssistantTurn.started` are stored but never displayed - Show a relative time or time-of-day per turn, as in the Claude app.
51. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MarkdownParser.swift (parse) - Markdown images `![alt](url)`, LaTeX (`$…$`, `\[…\]`), and footnotes render as raw text - Add inline image rendering via `RemoteImageView` and a basic math fallback.
52. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MessageViews.swift:146 and the streaming caret - `ChatBlinkingCaret` runs `repeatForever` without checking `accessibilityReduceMotion` - Skip the animation when reduce motion is on.
53. [Low] /home/knight/Desktop/projects/linkup/bridge/linkup_bridge/agents/base.py:4-19 - The docstring omits `parent` on `thinking.start`/`tool.update`, `notice.kind`/`model`, and the `status.detail` used by the reducer - Document these fields so each adapter emits them consistently.

## 3. Activity (tool cards, permissions) & Artifacts

BUGS

1. [High] ios/Linkup/UI/Activity/ActivityViews.swift:1204-1219 (PermissionCard.resolvedKeyInput) — Edit, MultiEdit, NotebookEdit and Write permission cards show only the file path, so the user approves a change without seeing old/new text or content. Fix: reuse the Edit diff parsing in PermissionCard and show the first ~20 lines of `content` or the `edits[]` diff.
2. [High] ios/Linkup/Core/Store/Transcript.swift:152 (with 147-149) — `turn.end` clears `pendingPermissions` but never sets `allowed` on requests still pending. Result: the Allow/Deny card stays live on a finished or interrupted turn (MessageViews.swift:228 shows it while `allowed == nil`) and ActivityViews.swift:35-42 keeps "Waiting for your approval" forever. Fix: on turn end, mark leftover requests as expired/denied and hide the card unless the turn is live.
3. [High] ios/Linkup/Core/Store/SessionStore.swift:166-169 with ios/Linkup/Core/Net/LinkupClient.swift:251-257 — `answer()` sets `allowed` locally before sending, and `post()` silently returns when `task` is nil and ignores send errors. The card disappears while the bridge still waits, so the agent hangs and reconnect offers no way to re-answer. Fix: keep the request pending until the bridge acks or `permission.resolved` arrives, re-send on reconnect, and surface send failures.
4. [High] ios/Linkup/Core/Store/ToolPresentation.swift:53 — `replacingOccurrences(of: "ing", with: "")` mangles failed-tool titles: "Running command" becomes "Runn command failed", "Creating file" becomes "Creat file failed", "Updating plan" and "Running agent" are also mangled, and "Using X" becomes "Use X failed". Fix: give each verb an explicit past-failed string.
5. [High] ios/Linkup/UI/Activity/ActivityViews.swift:972-994 (rawInputSection / rawInputString) — the raw input JSON is uncapped, with `\n` escapes, in one non-wrapping Text. It holds the whole Write `content` or `edits[]`, and it re-renders on every `partialInput` delta during streaming, which is quadratic. Fix: cap it like the output (20k with "Show all"), unescape string values, and render file content as lines.
6. [High] ios/Linkup/UI/Activity/ActivityViews.swift:744, 748, 829-866 — Write (`content`), MultiEdit (`edits[]`) and NotebookEdit (`new_source`) get no diff or body. Write falls into fileHeader with no content; editHeader only reads `old_string`/`new_string`. Fix: parse those keys into the diff/code block.
7. [Med] ios/Linkup/UI/Activity/ActivityViews.swift:702-720 vs 726-737 — the friendly header and the full raw JSON show the same command or old/new strings twice. Fix: put raw JSON behind a "Raw" disclosure for known tools.
8. [Med] ios/Linkup/UI/Activity/ActivityViews.swift:422-425 with 202-208 — `ThinkingEntryView.isExpanded` is `@State` inside a LazyVStack, so expanded state resets when the row scrolls off-screen. Fix: keep expanded block ids in a Set on the sheet or turn model.
9. [Med] ios/Linkup/UI/Activity/ActivityViews.swift:453-455 — the "Show more" rule (≥4 newlines or >180 chars) shows the button on short wrapped text and misses long single-line text. Fix: detect real truncation from the rendered line count, or drop the heuristic.
10. [Med] ios/Linkup/UI/Activity/ActivityViews.swift:693-696 — "N s elapsed" is computed once from `Date()` at render and never ticks. Fix: wrap the header in `TimelineView(.periodic(from: .now, by: 1))`.
11. [Med] ios/Linkup/UI/Activity/ActivityViews.swift:620 — `navigationTitle` always uses `activeTitle`, so a finished tool still reads "Running command". Fix: `tool.isRunning ? activeTitle : doneTitle`.
12. [Med] ios/Linkup/UI/Activity/ActivityViews.swift:1010-1025 — the output is one 20k-char Text with `textSelection(.enabled)` inside a horizontal ScrollView, so it cannot wrap and selection on that size is slow. Fix: render lines in a LazyVStack with wrap or horizontal scroll per line.
13. [Med] ios/Linkup/UI/Activity/ActivityViews.swift:868-912 — `diffView` builds an eager ForEach over every line of old and new strings, uncapped, inside a horizontal ScrollView. A large Edit freezes the detail view on open. Fix: cap the lines and use a lazy list.
14. [Med] ios/Linkup/UI/Activity/ActivityViews.swift:761-793 — the Bash command is uncapped and has no max height, so a multi-line heredoc fills the screen. Fix: max height ~220 with internal scroll, and use `description` as the header title.
15. [Med] ios/Linkup/UI/Activity/ActivityViews.swift:1185-1201 — the permission key-input box is uncapped in height for multi-line commands. Fix: `maxHeight` ~160 with a "Show all" toggle.
16. [Med] ios/Linkup/UI/Activity/ActivityViews.swift:1232-1245 with ios/Linkup/UI/Chat/MessageViews.swift:228 — the card is removed from the chat once `allowed` is set, so the "Allowed/Denied" status branch never renders in chat and the user gets no feedback. Fix: keep the card with its status after answering.
17. [Med] ios/Linkup/UI/Activity/ActivityViews.swift:1247-1264 — there is no "Allow always" or "don't ask again", and Deny sends no reason. The bridge `permission` op takes only a bool (grep finds no "always" in bridge/). Fix: add an allow-always option end to end with the bridge.
18. [Med] ios/Linkup/UI/Artifacts/ArtifactViews.swift:261 — "Copy Link" copies `client.resolve()` output, which includes `?token=` (LinkupClient.swift:101-107), so the bridge token goes to the clipboard. Fix: copy the link without the token, or use a short-lived share token.
19. [Med] ios/Linkup/UI/Artifacts/ArtifactViews.swift:332, 352 — WKWebView loads artifact HTML same-origin with the bridge and the token in the URL, so agent-generated JS can read `location` and call the bridge. Fix: cookie-only auth for `/linkup/files` and a sandbox CSP on served artifacts.
20. [Med] ios/Linkup/UI/Artifacts/ArtifactViews.swift:934-947 — `ArtifactDownloader` ignores the HTTP status, so a 401 or 404 page gets saved as the file. It also uses the raw title as the filename: "Image" gets no extension (from ArtifactViews.swift:537-544), and a "/" in the title makes `moveItem` fail at line 944. Fix: check the status, sanitize the name, and add an extension from the MIME type.
21. [Med] ios/Linkup/UI/Artifacts/ArtifactViews.swift:295-306 — every kind except image and media, including binary "file" kinds (zip, docx), goes to WKWebView, which shows a blank page or a failure. Fix: route binary kinds to QuickLook.
22. [Med] ios/Linkup/UI/Artifacts/ArtifactViews.swift:40-47 — `imageCard` puts `maxHeight: 360` on a full-width frame, so the bordered and clipped box stays 360pt tall and landscape images letterbox inside it. Likely, verify on device. Fix: apply the aspect ratio to the image itself, then cap the height.
23. [Med] ios/Linkup/UI/Artifacts/ArtifactViews.swift:510-521 — `RemoteImageView` uses AsyncImage at full resolution with no downsampling or cache, so long chats with images get janky and memory-heavy. Fix: downsample with ImageIO to ~1024px and cache with NSCache.
24. [Med] ios/Linkup/UI/Artifacts/ArtifactViews.swift:923-931 with 368 — `UIActivityViewController` is embedded as sheet content through UIViewControllerRepresentable instead of being presented modally, which breaks the share UI on iPhone and the popover anchor on iPad. Likely, verify. Fix: use `ShareLink(item:)` or present from the top view controller.
25. [Med] ios/Linkup/UI/Artifacts/ArtifactViews.swift:594-600 — `.offset` is applied before `.scaleEffect`, so the pan is multiplied by the zoom and does not track the finger 1:1. Fix: apply `scaleEffect` first, then offset.
26. [Med] ios/Linkup/UI/Artifacts/ArtifactViews.swift:747-749 — the AVPlayer path never sets an AVAudioSession category (only LiveAudioKeepAlive.swift:22 does, in live mode), so audio is silent with the ringer switch off. Fix: set `.playback` before playing.
27. [Low] ios/Linkup/UI/Artifacts/ArtifactViews.swift:777 — `pinchGestureRecognizer?.isEnabled = true` is a no-op, so PDF and SVG pinch zoom is not really configured. Fix: set `scrollView.maximumZoomScale` and inject a viewport zoom meta.
28. [Low] ios/Linkup/UI/Artifacts/ArtifactViews.swift:785 — `makeUIView` writes the `errorMessage` binding during a view update, which triggers the SwiftUI "modifying state during view update" warning. Fix: set it asynchronously from the coordinator.
29. [Low] ios/Linkup/UI/Activity/ActivityViews.swift:12 with ios/Linkup/UI/Chat/MessageViews.swift:207-213 — ActivityRow is a Button nested inside another Button, which duplicates the accessibility element. Fix: drop the outer Button in MessageViews.
30. [Low] ios/Linkup/UI/Activity/ActivityViews.swift:210-217, 304-310 — the live "Thinking…" row shows while a tool is running, which is misleading. Fix: show `activityLine` or the running tool's title.
31. [Low] ios/Linkup/Core/Store/Transcript.swift:132 — token totals include cacheRead and cacheWrite, so "4.2k tokens" is inflated, and "$0.03" is shown to users who run on a subscription with no API keys. Fix: show output tokens only and hide cost unless the user opts in.
32. [Low] ios/Linkup/UI/Activity/ActivityViews.swift:1175 — the PermissionCard title shows the raw tool id, for example "mcp__x__y wants to use…". Fix: use the humanized name from ToolPresentation.
33. [Low] ios/Linkup/UI/Activity/ActivityViews.swift:557-577 — `ToolIconView` starts a repeatForever pulse that is never reset when the tool finishes. Fix: drive the animation off `isRunning` with `.animation(value:)`.
34. [Low] ios/Linkup/UI/Shell/InspectorView.swift:26-45 — an invisible 48pt button overlays the top-left and swallows taps on the header content beneath it. Fix: put the close control inside the sheet and viewer headers.

VISUAL

35. [Med] ios/Linkup/UI/Activity/ActivityViews.swift:785, 819, 854, 930, 959, 979, 1020, 1111, 1195 — `Color(red: 0x14/255…)` is repeated about nine times instead of a token, so it drifts from Theme.swift. Fix: add `Theme.codeBackground`.
36. [Med] ios/Linkup/UI/Activity/ActivityViews.swift:874-905 — diff rows are plain colored text with no line tint, gutter or line numbers, and they do not wrap. Fix: per-row tinted background with a +/- gutter and line numbers.
37. [Low] ios/Linkup/UI/Theme/Theme.swift:20-31 — every font is a fixed point size, so nothing follows Dynamic Type. Fix: use `Font.custom(…, relativeTo:)` or text styles.
38. [Low] ios/Linkup/UI/Artifacts/ArtifactViews.swift:347-349 — the 2.5pt progress bar is inserted and removed, which shifts the web view. Fix: overlay it at the top of the web view.
39. [Low] ios/Linkup/UI/Artifacts/ArtifactViews.swift:53-59, 78-85, 431-435 — the type scale is inconsistent: caption 14 medium, card title 17 semibold, viewer title 16 semibold. Fix: pick one scale and use it everywhere.

MISSING / ENHANCEMENTS

40. [Med] ios/Linkup/UI/Artifacts/ArtifactViews.swift:140-188 — HTML, PDF and markdown artifacts get only generic tiles and no preview. Fix: cache a snapshot thumbnail (WKWebView snapshot or first PDF page).
41. [Low] ios/Linkup/UI/Activity/ActivityViews.swift:724-737 — there is no friendly header for Grep/Glob (`pattern`, `path`), so they show raw JSON. Fix: add a search header that reads those keys.
42. [Low] ios/Linkup/UI/Activity/ActivityViews.swift:624-636 — Copy copies only the output, not the command or input. Fix: add a copy menu for input and output.
43. [Low] ios/Linkup/UI/Activity/ActivityViews.swift:268-275 — pending permissions in the Summary sheet cannot be answered there. Fix: show Allow/Deny inline.

## 4. Composer, slash commands, dictation, voice mode

BUGS

1. [High] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Composer/ComposerView.swift:131-136, 104-105. The slash popover's X does nothing when the text is "/xyz". `showSuggestions` stays true while the text starts with "/" and has no space, and `onDismiss` clears the text only when it is exactly "/". Fix: gate `showSuggestions` on a dismissed flag and clear the text on dismiss.
2. [High] ComposerView.swift:548-550, 554-591. Text and attachments are cleared before the upload, create and send Task runs. Any throw (upload failure, create failure, bridge down) only shows a toast, and the message is lost. Fix: restore text and attachments in the catch, or clear them only after `store.send` succeeds.
3. [High] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Net/LinkupClient.swift:251-257 with ComposerView.swift:588. `post()` returns silently when `task` is nil and ignores send errors, while the composer has already cleared. A message sent while disconnected vanishes with no feedback. Fix: check connection state first, keep the text, and show "Not connected".
4. [High] ComposerView.swift:156-157 with /home/knight/Desktop/projects/linkup/bridge/linkup_bridge/agents/claude.py:170-172. Photos and HEIC files keep `image/heic` as the MIME type, and the bridge forwards it unchanged. The Claude API accepts only jpeg, png, gif and webp, so the turn fails. Fix: transcode to JPEG in `addAttachment` for any other image type.
5. [High] ComposerView.swift:474-481 with 533-536. While `isWorking`, the primary button is only Stop, so a follow-up typed during a turn cannot be sent. The bridge already serializes sends per session (server.py:227-228 lock), so queueing is possible. Fix: keep Send enabled while working and show a "queued" state.
6. [High] ComposerDictation.swift:69. `setCategory(.record, mode: .measurement, options: .duckOthers)` is likely invalid, because duckOthers is not valid for the record category, and it may throw so dictation never starts. Verify on device. Fix: use `.playAndRecord` with `.defaultToSpeaker` and `.allowBluetooth`, and drop duckOthers.
7. [High] ComposerDictation.swift:61, 69 with /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Composer/VoiceModeView.swift:247. Dictation switches the shared audio session to `.record`, which mutes AVSpeechSynthesizer output, and `stop()` deactivates the session mid-speech. Fix: one owner for the session, `.playAndRecord` throughout voice mode, and no deactivation while voice mode is active.
8. [High] VoiceModeView.swift:344-345, 363-369. `transcript.liveTurn ?? transcript.lastAssistantTurn` is read before the new turn exists, so the previous finished reply matches the exit condition. It is spoken again and the loop breaks. Fix: snapshot the current turn ID before send and accept only a newer turn.
9. [Med] ComposerView.swift:124 and 129-133 region. Heuristic symbol and "Skills" classification are not the bug here; see item 31 for the parsing issue. (Withdrawn, no finding.)
10. [Med] ComposerView.swift:616-619, 334-342, 318-332. `uploadFailed` is set but no view reads it, so a failed attachment looks normal and send silently re-uploads it. Fix: show a red badge or retry control and block send until the failed item is removed or retried.
11. [Med] ComposerView.swift:638-640 and 645. The `startAccessingSecurityScopedResource` guard silently skips files that return false. `Data(contentsOf:)` and `UIImage(data:)` run synchronously on the main thread for large files. Fix: load off the main actor, and toast any skipped files.
12. [Med] ComposerView.swift:155-160, 629. Full-resolution photos and camera JPEGs are sent unmodified, and the Claude API caps images at 5 MB, so large photos fail. Fix: downscale to about 1568 px on the long edge and JPEG-encode at about 0.8 before upload.
13. [Med] ComposerView.swift:523-525. Each dictation partial overwrites the field with `baseDictationText + spoken`, so anything the user types while listening is lost. Fix: track the spoken offset, or lock the field while listening.
14. [Med] ComposerDictation.swift:21-27, 34-37, 43. `isListening` flips only after the async permission await, so a double tap starts two engines, and the first engine keeps its tap running. If `beginRecording` throws after `setActive(true)` (lines 69-74), `stop()`'s guard at line 43 returns early and the session stays active. Fix: set a synchronous "starting" flag, and always deactivate in `stop()`.
15. [Med] VoiceModeView.swift:265-266. Dictation errors go to `ui.toast`, and the toast overlay lives in RootView beneath the fullScreenCover, so mic or permission errors are invisible and the screen just says "Listening". Fix: show the error inline in the voice sheet.
16. [Med] VoiceModeView.swift:340-381. The loop exits only when `turn.finished != nil && !isWorking`. Errors or interrupts that never set `finished` leave the phase stuck in Thinking or Speaking and the 200 ms poll running forever. Fix: exit when `!isWorking` after a grace period and reset the phase.
17. [Med] VoiceModeView.swift:409-419. Tapping the orb while speaking calls `store.interrupt`, which stops the agent's whole turn rather than only the speech. Fix: stop speech only, and offer a separate stop control.
18. [Med] VoiceModeView.swift:(permission path) with /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MessageViews.swift:228. PermissionCard renders only in chat. In voice mode a can_use_tool request leaves the turn waiting with no visible approval UI. Fix: show the approval inside the voice sheet, or surface a banner that returns to chat.
19. [Med] ComposerView.swift:579, 781, 91, 100. `draftEffort` is not reset on agent switch, it is passed to `create()` for every agent, and the pill shows it even for Antigravity and Hermes, which have no efforts. Fix: reset effort on agent switch, and pass effort only when `model.efforts` is non-empty.
20. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/RootView.swift:244 with ComposerView.swift:105. `.id(ui.currentSessionId ?? "new")` recreates ComposerView, so typed text is lost on every session switch, and there is no per-session draft store. Fix: persist drafts keyed by session ID (or "new") and restore them on appear.
21. [Med] CommandSuggestions.swift:157-161 with 172. `searchQuery` is seeded from `initialQuery` only in `onAppear`, so the popover search field and the composer text drift apart, and the search box is a second, disconnected input. Fix: derive the filter from the composer text alone, or sync both ways.
22. [Med] CommandSuggestions.swift:121-122 with ComposerView.swift:124-140. An empty "No matching commands" panel appears for any "/" even when the agent has zero commands, contrary to tasks/commands.md ("show nothing"). Fix: gate `showSuggestions` on `!commands.isEmpty`.
23. [Med] ComposerView.swift:1036-1039. The footer sets `ui.isShowingUsage = true` while the model sheet is still dismissing, and SwiftUI drops the second sheet. Fix: present Usage from the sheet's `onDisappear`.
24. [Med] ComposerView.swift:724-734 with /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/SessionStore.swift:107-113. The catalog refreshes only on connect and on pull-to-refresh, so the sheet shows stale or empty lists, and refresh errors go only to `lastError` with no UI. Fix: refresh on sheet appear when stale, and show the error in the sheet.
25. [Med] /home/knight/Desktop/projects/linkup/bridge/linkup_bridge/agents/claude.py:51-54 and 74-78. On EOF `data` stays None, and an empty `available: false` catalog is cached for 10 minutes with no error string. Fix: do not cache when `data` is None, and return an error.
26. [Med] ComposerView.swift:98-99. The resolved model name is parsed out of the description by splitting on "·". The bridge already sends `resolved` (claude.py:70), so use that field instead.
27. [Low] ComposerView.swift:1058. The "Full access" (bypassPermissions) mode has no warning or confirmation.
28. [Low] ComposerView.swift:465-466. The `repeatForever` animation keyed to `isPulsingMic` can keep pulsing or stick at a non-1 scale after stop. Fix: use `symbolEffect(.pulse, isActive:)`.
29. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Live/LiveAudioKeepAlive.swift:21, 66. The keep-alive `.playback` session is torn down by dictation's `setActive(false)`, and `isPlaying` stays true so it never restarts. Verify on device.
30. [Low] CommandSuggestions.swift:282-291. Keyword symbols use substring matching, so "ui" matches build or guide and "pr" matches prompt or project. Fix: match on word tokens.
31. [Low] CommandSuggestions.swift:302-341 and 57-80. The static `filter()` is dead code, and its "max 50" cap is not applied in the view. Fix: delete it, or apply the cap in `filteredItems`.
32. [Low] CommandSuggestions.swift:149. `UIScreen.main` is deprecated. Fix: use `containerRelativeFrame` or GeometryReader.
33. [Low] ComposerPromptLibrary.swift:83-85, 90-92, 163-166. The alert says "template" but saves the title as the body when the text is empty, and an empty title silently dismisses the alert. Fix: fix the copy and keep the alert open on an empty title.
34. [Low] ComposerPromptLibrary.swift:146-158. Context-menu delete and long-press delete both exist, and the confirmation dialog is reachable only through long-press. Fix: keep one delete path.

UX

35. [Med] ComposerView.swift:124-140 with CommandSuggestions.swift:149. The popover lives in the safeAreaInset flow, so up to 55% of the screen is taken from the chat. Fix: overlay the popover above the composer instead of inserting it into layout.
36. [Med] VoiceModeView.swift:184-190 and 203-210. The live transcript and spoken reply don't auto-scroll, so long text hides the current sentence. Fix: use a ScrollViewReader anchored to the bottom or the current sentence.
37. [Low] ComposerView.swift:344-351 and 372-378. Attachment remove buttons are about 18 pt, well below the 44 pt target. Fix: enlarge the hit area.

VISUAL

38. [Med] ComposerView.swift:297 with 283-294. The composer container is glass, its buttons are glass, and the prompt chips and segmented control add more glass. CLAUDE.md says Liquid Glass on controls only, and this reads as glass-on-glass. Fix: use a solid `Theme.elevated` container with a hairline and keep glass only on the buttons.
39. [Med] ComposerView.swift:238-245. The prompt library appears on focus, not when the field is empty as the spec says, so the composer height changes and the chat jumps on focus. Fix: show it only when the text is empty, and animate or reserve its height.
40. [Low] ComposerView.swift:474-514. The primary button swaps between Stop, Send, and Voice with no transition, and the uploading state is only a 0.4 opacity dim. Fix: add a symbol transition and a small progress indicator.

MISSING

41. [High] ComposerView.swift:272-277. There is no hardware-keyboard handling: on iPad, Return always inserts a newline, and there is no Shift+Return or Cmd+Return. Fix: `onKeyPress(.return)` that sends on plain Return and inserts a newline on Shift+Return, plus `keyboardShortcut(.return, modifiers: .command)` on the send button.
42. [High] ComposerView.swift:(whole file) with /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Net/LinkupClient.swift:63, 86. The composer never reads `client.state`, so there is no disabled send, no offline banner, and no offline queue. Fix: read the connection state and disable send with a visible reason.
43. [Med] ComposerView.swift:(attachment menu). Paste-image and drag-and-drop from other apps are missing. Fix: add `PasteButton` or `dropDestination` for images.
44. [Low] ComposerView.swift:477-481. The stop button has no "Stopping" state, because `interrupt` is fire-and-forget. Fix: show a pending state until the "Stopped" notice arrives.

## 5. iOS networking, reconnect, cache, Live Activity, widgets

BUGS

1. [High] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Live/LiveManager.swift:37-39,150-175 — Live Activities restored at launch are never ended if their turn finished while the app was dead. The end branch only runs for sessions in `previouslyRunningSessions`, which starts empty. Fix: in `poll()`, end any activity in `activeActivities` whose session has no `liveTurn`, not only previously-running ones.
2. [High] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/SessionStore.swift:166-169 (with `post` at LinkupClient.swift:251-257) — `answer()` marks the permission as allowed locally, then `post` silently drops the message when the socket is nil or the send fails. The agent stalls with no feedback. Fix: make `post` return a Bool or throw, and don't mark the request answered until the send succeeds.
3. [High] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Net/LinkupClient.swift:251-257 — `post()` returns silently when `task` is nil or on send error, so composer messages, interrupts, and renames typed while offline vanish. Fix: queue sends in an outbox and flush after hello, or surface an error toast and keep the draft.
4. [High] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Live/LiveManager.swift:290-301 with /home/knight/Desktop/projects/linkup/ios/Linkup/App/LinkupApp.swift:21 — Notification Allow/Deny from the lock screen can launch the app with no window, so `.task { app.start() }` never runs and `client.connect()` is never called. The answer is then dropped (see item 3). Fix: connect from the `UNUserNotificationCenter` delegate, await the connection, then post the answer.
5. [High] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Net/LinkupClient.swift:156-161 — `reconnectIfNeeded()` returns early when `state == .connected`, so a half-open socket after a network change or suspend is never replaced on foreground. Nothing detects the dead socket because the ping loop ignores failures (line 204). Fix: on foreground, send a ping with a 5 s timeout and force `connect()` if it fails; also make ping failure call `scheduleReconnect`.
6. [High] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Net/LinkupClient.swift:190-191 — Frames that fail `JSONDecoder` are dropped with `try?`, and the next event's higher seq makes `Transcript.apply` accept it. The missing seq is never backfilled, because resume points use the max seq. Fix: log and count undecodable frames, and on any seq gap (`seq > lastSeq + 1`) re-send `subscribe` with `since = lastSeq`.
7. [High] /home/knight/Desktop/projects/linkup/bridge/linkup_bridge/server.py:307-312 (client side: /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/Transcript.swift:38) — The subscribe replay loop awaits each `send_str`, while live `broadcast` can send a newer event on the same socket in between. The client sees seq N+1 before N and drops N permanently, since `apply` only accepts `seq > lastSeq`. Fix: server holds a per-client send lock or sends replay and live events through one queue; client should buffer out-of-order events or re-subscribe.
8. [High] /home/knight/Desktop/projects/linkup/ios/LinkupWidgets/UsageWidget.swift:17,22 with /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Live/LinkupWidgetSnapshot.swift:161-166 — `read()` falls back to `.placeholder` (fake 42%/18%, "1,240 credits", "Linkup Live Activity") when no snapshot exists. That is mock data in production, which CLAUDE.md forbids. Fix: return an explicit "no data" state and render it as "Open Linkup to sync".
9. [High] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Net/LinkupClient.swift:143,182 with /home/knight/Desktop/projects/linkup/bridge/linkup_bridge/server.py:463-468 — A wrong token gets a 401 on the WebSocket handshake, which the client reports as "Can't reach your PC" and retries forever at 10 s. Fix: read the HTTP status from the failed handshake (`ws.response`), stop retrying on 401, and show "Token rejected, re-pair".
10. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Support/UpdateChecker.swift:38-46 with /home/knight/Desktop/projects/linkup/ios/Linkup/UI/RootView.swift:430-435 — `showsBanner` reads `UserDefaults`, which `@Observable` does not track. `dismissBanner()` mutates nothing observed, so the banner stays visible until something else re-renders. Fix: store `dismissedVersion` as an observed property.
11. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Support/UpdateChecker.swift:58 — `lastCheck` is stamped before the request, so a failed check blocks retries for 6 h. Fix: set `lastCheck` only on success, or use a shorter retry on failure.
12. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Live/LiveManager.swift:128-130 — `Activity.update` runs every second for each running session even when the state is unchanged, which risks ActivityKit throttling and battery drain. Fix: compare with the last `ContentState` and update only on change.
13. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Live/LiveManager.swift:118-140,171 — Activities use `staleDate: nil`, so if the app is killed mid-turn the activity shows "running" forever. Fix: set `staleDate` to now + a few minutes and refresh it on each update.
14. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Live/LiveManager.swift:343-347 — The 300 s throttle on `reloadAllTimelines` drops trailing changes. A change inside the window is written but never reloaded until the 15-min timeline. Fix: schedule a deferred reload for the remaining window.
15. [Med] /home/knight/Desktop/projects/linkup/ios/LinkupWidgets/StopTurnIntent.swift:20-23 with LinkupLiveActivity.swift:68,171 — Stop only enqueues into the app group, and `poll()` consumes it, so Stop does nothing while the app is suspended. Fix: make the intent open the app (`openAppWhenRun = true`) or have the app drain stops on `.active` and on a silent push.
16. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Live/LiveAudioKeepAlive.swift:57 (and whole file) — No `AVAudioSession` interruption or route-change observer. After a call or Siri interrupts, `isPlaying` stays true, so `poll()` (LiveManager.swift:186) never restarts the keep-alive. Fix: observe `interruptionNotification`, clear `isPlaying`, and restart when a turn is still running.
17. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Live/LiveManager.swift:185-190 with LiveAudioKeepAlive.swift:70-78 — The 60-minute hard cap is defeated: `tick()` stops the engine, then the next `poll()` restarts it because a turn is still running. Fix: track the cap in `LiveManager` and don't auto-restart after the cap.
18. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Live/LiveAudioKeepAlive.swift:20-53 — Starting `AVAudioEngine` from the `.background` scene phase may be rejected by iOS, and the catch only calls `stop()`, which returns early because `engine` was never assigned (line 57). The audio session stays active. Fix: start from `.active` only, log the error, and deactivate the session in the catch. (Unverified on device.)
19. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Net/LinkupClient.swift:111-119 with 148-151 — `connect()` cancels the old socket without resuming waiters from the prior generation, and `disconnect()` does the same. Requests hang for the full 30 s then show "didn't answer in time". Fix: fail all `pending` in `connect()` and `disconnect()`.
20. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/RootView.swift:568-571 — The connection pill calls `connect()` even when already connected, which tears down a healthy socket and triggers item 19. Fix: call `reconnectIfNeeded()` or run a health-check ping instead.
21. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/SessionStore.swift:56-59 — `ingest` appends every event to the disk cache before the seq check, so duplicates from overlapping replay and live delivery are written to the file. Fix: check `seq > lastSeq` before `cache.append`, or dedupe in `EventCache.append`.
22. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/SessionStore.swift:29 with EventCache (SessionStore.swift:213-233) — Event logs are never compacted or capped and are fully parsed on the main thread on first open. Long sessions cause hitches and unbounded disk use. Fix: cap per-session cache (keep last N events plus a snapshot), and load on a background queue.
23. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Net/LinkupClient.swift:44-58 — Keychain: `SecItemAdd` status is ignored (Keychain.swift:51), and `get` treats `errSecInteractionNotAllowed` as "no token" (line 58). A locked-device launch can show the connect screen and lose the token. Fix: check `OSStatus`, and handle `errSecInteractionNotAllowed` by retrying rather than clearing settings.
24. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/SessionStore+Extras.swift:115-118,146-148,135 — `decoded()` returns nil silently, so a decode failure looks like an empty result: `gitStatus` reports "not a repo", `listFiles` returns []. Fix: have `decoded` throw, and surface the error.
25. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/SessionStore.swift:49-50,63,67,78-79 — Whole-list decodes (sessions, usage, agents) fall back silently to the old value if one element fails. The usage snapshot is especially fragile: any nested mismatch freezes all usage. Fix: decode per element, skipping bad rows with a log, and surface decode failures in `lastError`.
26. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Live/LinkupWidgetSnapshot.swift:174-183 with UsageWidget.swift:17-27 — The widget never shows the snapshot's `updatedAt`, so numbers from days ago look current. Fix: show "updated 3h ago" and dim the rings when `updatedAt` is older than about 30 minutes.
27. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/SessionStore.swift:15 — `transcripts` is never evicted, so memory grows with every opened session. Fix: LRU of about 10 transcripts, reloading from cache on demand.
28. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/SessionStore.swift:29 with EventCache.swift (`cache.append` at 222-232) — The async write queue races the synchronous `loadEvents` read, so the freshest events can be missing on open. Hello and subscribe recover them, but there is a visible flicker. Fix: route reads through `queue.sync`.
29. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/SessionStore.swift:58 with 235-238 — Late events for a deleted session recreate its file, leaving orphan cache files. Nothing prunes events for sessions gone from the bridge. Fix: ignore events for unknown sessions, and prune cache files not in the session list on `hello`.
30. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/SessionStore.swift:90 — `sessions.json` is rewritten in full on every upsert and every status push. Fix: debounce the save by about 500 ms.
31. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/SessionStore.swift:116-120 — `loadProjects()` uses `try?` and swallows errors, so the project picker is silently empty. Fix: set `lastError` on failure.
32. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Live/LiveManager.swift:16-17,103-105 — `notifiedPermissionIds` grows without bound, and `previouslyRunningSessions` is never pruned for deleted sessions. Fix: prune both when a session disappears from `store.sessions`.
33. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Live/LiveManager.swift:144-146 — `Activity.request` failures are swallowed, so the user never learns that the Live Activity is missing. Fix: log, and retry on the next poll if the session is still running.
34. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Net/LinkupClient.swift:242-246 — The timeout Task is never cancelled on success, so every request keeps a 30–90 s task alive. This is harmless but wasteful. Fix: cancel the timer when the reply arrives.
35. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Net/LinkupClient.swift:120-122,106 — The bridge token travels in the WebSocket URL and in artifact/image URLs, where it can persist in `URLCache` and on-disk caches. Fix: send the token in an `Authorization` header for the WebSocket and in a cookie for artifact loads.
36. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Net/LinkupClient.swift:260-272 — Upload uses `URLSession.shared` with no timeout, and the error body is discarded. Fix: use the shared session with a longer timeout, and surface the bridge's error text.
37. [Low] /home/knight/Desktop/projects/linkup/ios/LinkupWidgets/StopTurnIntent.swift:21 with LinkupWidgetSnapshot.swift:121-137 — `consumePendingStops` is a non-atomic read-then-remove across the app and extension, so two concurrent stops can lose one. Fix: append under a lock or use a per-session key.
38. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Support/UpdateChecker.swift:134,140 — `isVersion` treats "0.3.0-beta" as 0, and `tag_name` is not filtered for prerelease. Fix: strip the suffix and compare numerically.

RELIABILITY

39. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Net/LinkupClient.swift:81 — The doc comment says the client reconnects on "network changes", but no `NWPathMonitor` exists. Fix: add a path monitor that calls `reconnectIfNeeded()` on a satisfied path change.
40. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Net/LinkupClient.swift:163-174 — Reconnect backoff never gives up and never stops offline, so it retries every 10 s indefinitely with no jitter. Fix: exponential backoff with jitter, and pause retries while the path is unsatisfied.
41. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Net/LinkupClient.swift:94-96,199-208 — `pingTask` keeps running after a socket failure, and latency is never reset. Fix: cancel the ping task in `scheduleReconnect`.
42. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Net/LinkupClient.swift:133-134 — The `hello` request has a 30 s timeout, but the server replays all missed events before replying, so a large backlog can time out and cause a reconnect storm. Fix: give `hello` a longer timeout, or have the server reply first and then replay.

PROTOCOL-MISMATCH

43. [Low] /home/knight/Desktop/projects/linkup/bridge/linkup_bridge/server.py:4 vs 296-297 — The docstring says `hello` returns `catalog`, but the code returns `usage`. The Swift client doesn't read `catalog` from hello, so this is only a docs bug. Fix: correct the docstring.
44. [Low] /home/knight/Desktop/projects/linkup/bridge/linkup_bridge/server.py:1-18 — The docstring omits ops the client uses: `fork`, `handoff`, `compare`, `projects.create`, `fs.*`, `git.*`, `gh.runs`, `schedule*`, `unsubscribe`, and the `mode` field on `create`. Fix: document them so the protocol is checkable.
45. [Med] /home/knight/Desktop/projects/linkup/bridge/linkup_bridge/agents/claude.py:273-276 — The raw `rate_limit_event` windows (`unifiedWindows`) are sent without normalization, but Swift `RateLimitWindow` expects `utilization` as 0…1 and `resetsAt` as epoch seconds. Plan usage divides by 100 in `usage.py`, but this path does not. (Unverified: the exact CLI payload was not inspected.) Fix: normalize in the bridge the same way `_parse_window` does, and document the shape.

MISSING-ENHANCEMENTS

46. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/SessionStore.swift:130-131 — After reconnect, the app never re-checks "unread" or re-subscribes sessions that were never loaded. Fix: on `hello`, re-run `open()` for the currently visible session.
47. [Low] /home/knight/Desktop/projects/linkup/project.yml:53 — `NSAllowsArbitraryLoads: true` is unnecessary, since the bridge is HTTPS via Tailscale Funnel, and it weakens ATS and may draw App Store review questions. Fix: remove it and keep `NSAllowsLocalNetworking`.
48. [Low] /home/knight/Desktop/projects/linkup/project.yml:49 — `UIBackgroundModes: [audio]` with a silent-audio engine is a background-keepalive hack. It is fine for SideStore but fragile. Fix: document it as a known limitation, and prefer `BGAppRefreshTask` or APNs-free polling where possible.

## 6. Bridge: Claude / agy / Hermes adapters, server, store

BUGS

1. [High] /home/knight/Desktop/projects/linkup/bridge/linkup_bridge/agents/claude.py:256-262 - The `assistant` branch only reads `tool_use` blocks. Its text and thinking blocks are dropped, and so is the `isApiErrorMessage` text the CLI emits for rate-limit, auth and billing errors (the CLI binary 2.1.294 contains these strings). If no stream_event carried that text, the user sees nothing. Fix: emit text/thinking blocks not already streamed, and surface API-error text as an error.
2. [High] claude.py:279-292 - The `result` branch never reads `msg["result"]` and only keeps `is_error` as a boolean. Errors such as `error_max_turns` and `error_during_execution` produce turn.end with no reason, then status idle rather than error. Fix: emit an `error` event with the result text or subtype when `is_error` is set, and set status error.
3. [High] claude.py:227-232 and 132-137 - When the process exits mid-turn, the app gets only "Claude Code exited (N)". Stderr is drained to the debug log only. Fix: keep the last few stderr lines and include them in the error detail.
4. [High] claude.py:103-130 and server.py:202-204 - `warm()` and the first `send()` both call `_ensure()` concurrently. `_ensure` awaits `_spawn` before setting `self.proc`, so two `claude` processes start and one is orphaned, with its reader still emitting events. Fix: guard `_ensure` with an asyncio.Lock per ClaudeSession.
5. [High] server.py:227-236 with agents/agy.py:80 and agents/hermes.py:90 - The per-session lock covers only `rt.send()`, which returns immediately for agy and hermes. A second message starts a second agy process that overwrites `self.proc`, so interrupt only kills the newest one. If the first turn has no native_id yet, `--conversation` is omitted and a second conversation is created. Fix: hold the lock until turn.end, or queue turns per session.
6. [High] agents/agy.py:81 and 125 - stderr is a PIPE but is only read after stdout reaches EOF. Enough stderr output during a run blocks agy and hangs the turn. Fix: drain stderr concurrently into a bounded buffer, as claude.py does.
7. [High] agents/agy.py:132-134 - An exit code of 0 with no `result` event gives turn.end with `isError` false and no error. The user gets a silent empty reply. Fix: treat a missing result as an error regardless of exit code.
8. [High] agents/hermes.py:98-104 - The POST to /v1/runs never checks the HTTP status. On a 401, 404 or 500, `run_id` is None and the SSE GET targets `/v1/runs/None/events`. The failure reaches the app only as turn.end "exited" with `isError`, and no message. Fix: check `r.status` and emit an error with the response body.
9. [High] agents/claude.py:45-68 - In the catalog, a timeout (45 s) or exception in readline skips the kill, which only runs on the success path at line 64, so the `claude` process leaks on each failed attempt. Its stderr is also a PIPE that is never drained (line 28), so a chatty CLI blocks until the timeout. Fix: kill and reap in `finally`, and send stderr to DEVNULL.
10. [High] store.py:96-100 with server.py:294 and 310 - `events()` silently caps at 20000 rows, and hello and subscribe never paginate. Every text.delta is a row, so a long session replays with a gap, which breaks the "no gaps" contract. Fix: page through the replay until exhausted, or coalesce deltas.
11. [High] server.py:79-88 - `broadcast` awaits `send_str` to each client in turn. One stalled phone socket blocks `record()`, and therefore the agent reader, for every session. Fix: give each client a bounded queue and writer task, and drop clients that stall.
12. [Med] claude.py:43-45 and 73-79 - A failed catalog (`data` is None, so the models list is empty) is cached as `available: false` for 600 seconds. Fix: do not cache an empty result.
13. [Med] server.py:100-109 - `record()` appends synchronously, then awaits the broadcast without a lock. Concurrent records can reach clients out of seq order, which breaks the iOS gap logic. Fix: hold a per-session lock across append and broadcast, or use a single writer queue.
14. [Med] server.py:289-297 and 307-312 - hello and subscribe register the subscription before the replay. Live events broadcast during the replay's awaits interleave with older replayed events. Fix: buffer live events until the replay has been flushed.
15. [Med] server.py:475-489 - Each inbound WebSocket message runs in its own task, so two quick `send` ops, or a `create` followed by a `send`, can be processed out of order. Fix: use a per-socket queue for ops.
16. [Med] claude.py:145-154 and store.py:73-76 - Deleting a running session cancels the reader, but its `finally` still appends turn.end and status to the deleted session id. `Store.append` never checks the session exists, so orphan event rows stay forever. Fix: skip appends for missing sessions. agy has the same issue (agy.py:178-189).
17. [Med] claude.py:164-183 with 227-232 - `running` is set to True before `_write`, and a failed write leaves it True, so submit records a second turn.end. A model or effort change mid-turn makes `_ensure` call `close()`, which cancels the reader. The old reader's `finally` then emits an error or turn.end into the new turn. Fix: tag each turn with a generation token, and queue setting changes until the turn ends.
18. [Med] agents/claude.py:190-201 and 293-302 - `pending_permissions` is never cleared on turn end, process exit or close. The CLI binary contains `control_cancel_request`, which has no handler here, so stale permission cards persist. An unanswered `can_use_tool` blocks the CLI forever, with no timeout and no fallback when the phone disconnects. Fix: handle `control_cancel_request` by emitting `permission.resolved`, clear pending on exit, and auto-deny after a timeout.
19. [Med] claude.py:190-201 and 293-302 - The permission event drops `permission_suggestions`. Allow sends only `updatedInput` (line 196), so there is no "always allow" path. AskUserQuestion goes through the same allow/deny with no way to supply answers. Fix: forward suggestions and map them to updatedPermissions, and special-case AskUserQuestion to fill `answers` in updatedInput.
20. [Med] claude.py:225-232 and agy.py:124-135 - Open text and thinking blocks are never closed when the process exits or is killed. Only agy closes them, and only on the result path (agy.py:110-111). The server's `text_buffers` then leak, and the next turn's text merges into them. Fix: emit end events for open blocks in `finally`.
21. [Med] agents/agy.py:122-131 - Errors collected from `error` and `failed` events are emitted only when no result arrived. A FAILED result puts its text only in turn.end.text (line 121) and emits no `error` event. Fix: always emit collected errors, and emit an error event on a failed result.
22. [Med] agents/agy.py:70 and 80-81 - There is no timeout. `--print-timeout 0` plus no watchdog means a hung agy turn runs forever with no status update. Fix: add an inactivity watchdog that terminates the process and emits an error.
23. [Med] agents/agy.py:70 with 185-186 - `--dangerously-skip-permissions` is always passed, and `set_mode` is a no-op, so the session's permission_mode is silently ignored for agy. Fix: honor the mode, or hide the mode picker for agy.
24. [Med] agents/agy.py:161 - The tool id is `f"{native_id}:{idx}"`. Before init it is `None:idx`, and if step indices restart across turns on one conversation, tool cards collide by id in iOS. Fix: include a per-turn counter or uuid in the id. (Unverified whether agy restarts step_index, so confirm with a two-turn capture.)
25. [Med] agents/agy.py:178-180 and 188-189 - interrupt sends SIGTERM only, and close() neither waits nor kills, so an ignored SIGTERM leaves an orphan. Also, a cancelled run that still emits a result is reported as `isError` (lines 118-121). Fix: escalate to SIGKILL after a timeout, and treat CANCELED as interrupted.
26. [Med] agents/hermes.py:149-151 - `failed = ev != "run.completed"` marks run.cancelled and run.stopped as errors, so a user-stopped run shows as a failure. Fix: set `isError` only for run.failed.
27. [Med] agents/hermes.py:105-164 - The SSE stream has no reconnect or resume, and there is no Last-Event-ID. A network blip ends the turn as "exited" while the durable run keeps going server-side. Fix: reconnect GET /v1/runs/{id}/events with backoff, or poll run status.
28. [Med] agents/hermes.py:114-155 - Only some event types are mapped. Others, including `error` and tool progress, are dropped with no log. Fix: log unknown types at info level and map `error` to an error event.
29. [Low] agents/hermes.py:85 - The model fallback "hermes-knight" is hardcoded, while the catalog default is models[0] (line 61). A mismatched id fails silently, as in item 8. Fix: use the catalog default.
30. [Med] agents/claude.py:240-252 - Unhandled system subtypes such as `api_retry` are dropped silently, so the user sees no feedback while the CLI retries API errors (the CLI binary contains `api_retry`). Fix: map them to a status or notice event.
31. [Med] server.py:101-109 and 124-125 - Artifact dedupe lives only in memory, so after a restart the same artifacts are announced again. The key is path plus size, so a rewritten file at the same size is not re-announced. Fix: persist the announced keys, or key on mtime as well.
32. [Med] server.py:74-76 - On restart, sessions are set idle, but in-flight turns get no turn.end or error event and pending permissions are not resolved. Cached transcripts keep spinning cards. Fix: append turn.end (interrupted) and a notice for each session that was running.

RESPONSE-HANDLING

33. [Low] server.py:131-132 with claude.py:282-286 - Cost and usage are summed per turn. If the CLI's `total_cost_usd` is cumulative for the process, totals inflate. Fix: verify with a two-turn capture, and store the delta if it is cumulative.

SECURITY

34. [Med] server.py:333-336 and 213 - The `send` op accepts any existing file path from the client, checked only with isfile. The file is then base64-inlined to Claude or registered for download. Fix: restrict attachments to the uploads folder under ~/.linkup.
35. [Med] server.py:517-529 - Upload streams to disk with no size cap. `client_max_size` (line 457) applies to request.read() and post(), not to iter_chunked streaming, and there is no free-space check. Partial files are left behind on error. Fix: enforce a running byte cap and delete the file on failure.
36. [Med] server.py:503-509 - The sibling lookup on /linkup/files serves any file under the parent directory of a registered file, because the candidate only needs to start with base plus a separator. Registering ~/x.pdf exposes all of ~, including .linkup/token and .hermes/.env. Fix: serve only exact registered paths, and reject dotfiles and subdirectories.
37. [Med] server.py:536-540 with workspace.py:628 - The proxy accepts any local port from 1024 to 65535, except the bridge port, so it reaches Hermes on 8642 and any other local service. Fix: allowlist ports.
38. [Low] server.py:316-319 with claude.py:123-124 - `create` accepts any cwd and `os.makedirs` creates it. Claude defaults to bypassPermissions (claude.py:115). Fix: validate cwd with workspace.allowed.
39. [Low] server.py:449-452 and 558 - The token may travel in the query string (proxies and logs), and access_log is disabled, so auth failures are not logged. Fix: prefer the header and log 401s.

RELIABILITY

40. [Med] store.py:86-94 and 92 - There is no retention, and every text.delta is a full JSON row. The events table, the files table (line 109-111) and the artifact dedupe set all grow forever. Fix: coalesce deltas per block and compact finished turns.
41. [Low] server.py:124-125 and 135-136 - Every status event does a session read plus a broadcast, and every ratelimit event scans all sessions in usage(). Fix: debounce or cache.
42. [Low] claude.py:127-128, server.py:204 and agy.py:82 - Fire-and-forget `create_task` results are not stored, so the tasks can be garbage-collected. Fix: keep references in a set.
43. [Low] claude.py:28 and 214 - A stdout line over the 64 MB limit makes readline raise ValueError, which is not caught around readline, so the reader dies and the session ends. Fix: catch it and resync, or raise the limit.
44. [Low] server.py:389 - fork copies history without broadcasting it, so the client sees the copy only after a re-subscribe. Fix: broadcast the copied events.

MISSING-ENHANCEMENTS

45. [Med] tests/e2e.py:14-29 - There are no unit tests for normalization, replay ordering or the stream parser. The e2e loop also hangs forever if no turn.end arrives. Fix: add a fixture-driven test for claude stream-json and a timeout to the e2e loop.
46. [Low] server.py:43 - VERSION is "1.0.0", but the latest commit is "Linkup 0.2.0". Fix: sync the version.

## 7. Workspace, git, schedules, usage, dev-server preview

BUGS
- [High] bridge/linkup_bridge/commands.py:206-215 — If execvp fails in the os.fork() child, it falls through into the bridge code inside an outer try that returns {}, so a duplicate server runs — wrap the child in try/finally with os._exit(127).
- [High] ios/Linkup/UI/Usage/UsageDashboardView.swift:40-60 — ClaudePlanSectionView.fallbackRateLimit reads screenshot-fixture.json in production and shows it as live usage — delete the fallback; show an "unavailable" state when the bridge sends no data.
- [High] ios/Linkup/UI/Workspace/GitStatusView.swift:345-360 — performCommit shows a success toast regardless of the result, and the bridge returns None on failure — return {ok, error} from git_commit and gate the toast on it.
- [High] ios/Linkup/UI/Workspace/GitStatusView.swift:370-385 — performPush shows success regardless of the result — the bridge returns raw output with no success flag, so add ok/exit code to git_push and check it in the UI.
- [High] bridge/linkup_bridge/workspace.py:534-555 — git_push returns raw output with no success flag, so the iOS side cannot tell failure from success — return {ok, code, stderr}.
- [Med-High] bridge/linkup_bridge/scheduler.py:247-277 — _tick holds a reference to a schedule dict across the await run(); a concurrent save() can replace the dict, so lastRun or nextRun writes are lost and a slot can re-fire — re-fetch by id after the await and write to the current entry.
- [Med-High] bridge/linkup_bridge/scheduler.py:135-201 — save() replaces the dict in place while _tick may hold a stale reference, which is the same race — serialize schedule mutations with an asyncio.Lock.
- [Med-High] ios/Linkup/UI/Workspace/FileViewer.swift:225-235 — mediaArtifactPreview uses .onAppear, so the artifact viewer reopens every time the user returns to the file — use a one-shot flag or present on user action only.
- [Med-High] bridge/linkup_bridge/workspace.py:40-50 and 252 — allowed() permits the whole home directory, so read_file can return dotfiles such as ~/.hermes/.env — deny dotfiles and known secret paths by default, with an explicit allowlist for project roots.
- [Med] bridge/linkup_bridge/workspace.py:515-531 — git_commit runs `git add -A` with no confirmation and no file list, so it can commit secrets or build output — stage only the files the user selected, or show the staged list before commit.
- [Med] ios/Linkup/Core/Store/SessionStore+Extras.swift:183-186 — saveSchedule omits nil optional keys, and the bridge reads "absent" as "keep existing", so model and cwd can never be cleared — send explicit JSON null for cleared fields.
- [Med] ios/Linkup/Core/Store/SessionStore.swift:117 — loadProjects uses try?, so a network or decode failure shows "No projects yet" — surface the error with a retry.
- [Med] ios/Linkup/UI/Workspace/NewProjectSheet.swift:85-90 vs bridge/linkup_bridge/workspace.py:53-57 — the client rejects invalid characters while the bridge silently strips them, so the created name can differ from what was typed — share one rule and show the sanitized name before submit.
- [Med] ios/Linkup/UI/Workspace/CIRunsView.swift (empty state) — gh missing and "no runs" both show the same empty state, because gh_runs returns [] in both cases — return an explicit error code and show a distinct "install/auth gh" message.
- [Med] ios/Linkup/UI/Workspace/CIRunsView.swift:195 — Color.orange is hard-coded instead of a Theme token — use a Theme warning token or add one.
- [Med] ios/Linkup/UI/Workspace/GitHistoryView.swift:200-250 — the header says "tap to view commit diff" but the detail shows only metadata — either add a diff fetch or remove the hint.
- [Med] ios/Linkup/UI/Workspace/GitStatusView.swift:490-500 (GitDiffSheet diffScrollView) — a non-lazy VStack renders up to a 400 KB diff at once — use LazyVStack and cap rendered lines, with a "show more" action.
- [Med] ios/Linkup/UI/Workspace/FileViewer.swift:500-525 — prepareCodeLines runs on the main thread for up to 100k lines — move it to a background task and show progress.
- [Med] ios/Linkup/UI/Usage/UsageDashboardView.swift:510-545 and 730+ — the AgentUsageCard chart buckets lifetime tokens onto the last-activity day, so the 7-day chart shows fabricated per-day history — chart only real per-day data or label the chart as totals.
- [Med] bridge/linkup_bridge/usage.py:60-75 — _parse_window divides utilization by 100, but the rate_limit_event reports 0..1, so the scale may be wrong by 100x — confirm against the live OAuth response and use one normalization path (unverified).
- [Med] bridge/linkup_bridge/usage.py:232-258 — agy_usage always returns models: [], so the iOS per-model view is always empty — parse model rows from the PTY output or hide the section.
- [Med] bridge/linkup_bridge/workspace.py:625-700 — the proxy forwards Cookie and Authorization headers to any localhost port in 1024-65535 and overwrites Set-Cookie — forward only the dev-server port the user opened, and strip Authorization.
- [Med] ios/Linkup/UI/Shell/DevServerPreview.swift:196 and bridge proxy — the preview loads /linkup/proxy/<port>/, but absolute asset paths such as /src/main.js in the dev server HTML bypass the prefix — rewrite base or use a <base href>, and confirm with a real Vite app (unverified).
- [Med] ios/Linkup/UI/Schedules/ScheduleFormatter.swift:72-100 — nextRunDate computes the next run in the phone's time zone, but the bridge fires at PC local time, so the displayed time can be wrong when the zones differ — display schedule.time as a label, or use the bridge's nextRun value.
- [Med] ios/Linkup/UI/Schedules/SchedulesView.swift:32-35 and ScheduleEditor.swift:563-575 — the editor sends nextRun and lastRun back on save, and the bridge reads them as authoritative — send only editable fields and let the bridge compute nextRun.
- [Low] bridge/linkup_bridge/server.py:154-175 — poll_usage adds an `at` timestamp to every payload, so every poll looks changed and broadcasts — compare without `at`.
- [Low] bridge/linkup_bridge/server.py:240 — run_schedule starts the session with ws=None, so permission prompts for scheduled runs have no client to answer them — define the deny-by-default policy for scheduled runs explicitly.
- [Low] ios/Linkup/UI/Usage/UsageRing.swift — Theme.hairline.opacity(1.8) and opacity(1.6) are no-ops because opacity is clamped to 1 — use an explicit color with the intended alpha.
- [Low] ios/Linkup/UI/Workspace/GitStatusView.swift:395-420 — statusBadge uses hard-coded colors instead of Theme.success, Theme.danger and Theme.accent — switch to the Theme tokens.
- [Low] ios/Linkup/UI/Workspace/ProjectDetailView.swift — "New session here" calls ui.newChat() and then dismiss() from inside a NavigationStack nested in a sheet, which can dismiss the wrong level — dismiss the sheet first, then navigate (unverified).

PROTOCOL-MISMATCH
- [Med] ios/Linkup/Core/Store/SessionStore+Extras.swift:183-186 vs bridge/linkup_bridge/scheduler.py:179-182 — nil is omitted on iOS but read as "keep existing" on the bridge, so clearing a field cannot be sent — send explicit null and treat null as clear.
- [High] bridge/linkup_bridge/workspace.py:534-555 vs ios GitStatusView.swift:370-385 — git_push has no success field and the UI ignores the return value — add {ok} to the reply and check it on iOS.
- [Med] bridge/linkup_bridge/workspace.py:515-531 vs ios GitStatusView.swift:345-360 — git_commit returns None on failure, which the UI treats as success — return an error object instead of None.
- [Med] bridge/linkup_bridge/usage.py:232-258 vs ios UsageDashboardView — the bridge sends models: [] while the iOS card expects per-model rows — send real rows or remove the field from the iOS model.
- [Med] bridge/linkup_bridge/scheduler.py:135-201 vs ScheduleFormatter.swift:72 — the time zone used to compute the next run differs between iOS and the bridge — make the bridge's nextRun authoritative and display it.
- [Low] bridge/linkup_bridge/scheduler.py:14 vs ScheduleEditor.swift:23 — the bridge agents set is {claude, agy, hermes}, but the editor's agent picker may offer other values — generate the picker from the bridge's list.

UX-NAVIGATION
- [Med] ios/Linkup/UI/Schedules/SchedulesView.swift:83-140 — the Schedules sheet uses presentationDetents [.medium, .large] with a NavigationStack inside a sheet, so the editor sheet stacks over a medium detent and is hard to dismiss — use .large only for the editor.
- [Med] ios/Linkup/UI/Workspace/FileViewer.swift:225-235 — the artifact viewer reopens on return, which traps the user in a loop — present once per file open.
- [Med] ios/Linkup/Core/Store/SessionStore.swift:117 — a project load failure looks like an empty state, so the user cannot retry — add a retry button and an error row.
- [Low] ios/Linkup/UI/Workspace/ProjectsView.swift and ProjectDetailView.swift — NavigationStack nested inside sheets with push and dismiss mixed — use one NavigationStack per sheet and dismiss with the environment action.
- [Low] ios/Linkup/UI/RootView.swift:133-160 — Usage, Projects and Schedules are separate sheets with no shared dismiss path, and the DevServerPreview fullScreenCover adds a NavigationStack — flatten to one sheet router in UIState.

VISUAL
- [Med] ios/Linkup/UI/Workspace/GitStatusView.swift:395-420 — statusBadge colors do not match the Theme palette, so badges look off-brand — use Theme.success, Theme.danger and Theme.accent.
- [Med] ios/Linkup/UI/Usage/UsageRing.swift — the hairline strokes are effectively invisible because of the no-op opacity, so ring tracks blend into the background — use Color.white.opacity(0.08) or Theme.hairline directly.
- [Low] ios/Linkup/UI/Workspace/CIRunsView.swift:195 — Color.orange clashes with the Claude palette — use Theme.accent or a Theme warning token.
- [Low] ios/Linkup/UI/Schedules/SchedulesView.swift:95 and ScheduleEditor.swift:525 — the empty state and progress use mixed tints (Theme.accent and .white) — use Theme.accent consistently.

SECURITY
- [High] bridge/linkup_bridge/workspace.py:40-50 and 252 — the whole home directory is readable, including dotfiles like ~/.hermes/.env and credentials — deny dotfiles and known secret files by default.
- [Med] bridge/linkup_bridge/workspace.py:625-700 — the dev proxy forwards Cookie and Authorization to any localhost port in 1024-65535 and overwrites Set-Cookie — restrict to the chosen dev port and strip Authorization.
- [Med] bridge/linkup_bridge/workspace.py:515-531 — git add -A can stage .env and key files without review — stage explicit paths only.
- [Low] bridge/linkup_bridge/commands.py:206-215 — the fork fallthrough runs a second bridge instance with the same token and home — exit the child on exec failure.

MISSING-ENHANCEMENTS
- [Med] ios/Linkup/UI/Workspace/GitHistoryView.swift:200-250 — no per-commit diff, although the header implies one — add a fetch of git show for the selected commit, capped in size.
- [Med] bridge/linkup_bridge/scheduler.py:223 — there is no run history, only lastRun and lastSessionId — keep the last N run results with status and surface them in SchedulesView.
- [Med] ios/Linkup/UI/Schedules/SchedulesView.swift:320-360 — the scheduled run shows no indicator of a run in progress after "Run now" — show the running state from the bridge's session status.
- [Low] bridge/linkup_bridge/usage.py:232 — agy usage relies on a 12-second PTY capture every 5 minutes, which is fragile — cache the last good value and show its age.
- [Low] ios/Linkup/UI/Usage/UsageDashboardView.swift — no empty or stale indicator when the bridge stops sending usage — show "last updated" from the `at` field.

## 8. Rich cards & multi-agent (Compare / Handoff / Running)

BUGS

1. [High] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Cards/CardsPlaces.swift:1661 — CurrencyCard uses `amount * (rate ?? 1.0)`, so while the live rate is loading or fails it shows a 1:1 conversion as if it were real. Fix: show "--" or "Rate unavailable" when `rate` is nil.
2. [High] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/CardExtractor.swift:33-35 — a `linkup-card` fence closed on the same line with text after it (`{...}``` more text`) matches no closer, so it returns `.pendingCard` and drops everything after it. Fix: search for a closing ``` anywhere after the opener, not only `\n```` or end-of-string.
3. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Cards/CardSupport.swift:50-60 — an unterminated card (interrupted or malformed output) leaves `PendingCardView` spinning forever with `repeatForever`. Fix: show a "Card incomplete" state once the turn has ended.
4. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Chat/MessageViews.swift:225 — `RichTextView` parses cards for every session type, but the card prompt is injected only in chat mode (bridge/linkup_bridge/agents/claude.py:121-122). Answers that quote the fence, such as work on Linkup itself, become garbage cards. Fix: parse cards only when `session.mode == "chat"`.
5. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Cards/CardRegistry.swift:57-59 — an unknown or misspelled card type renders its raw JSON in a mono box. Fix: show a short "Unsupported card: <type>" line, or fall back to markdown.
6. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Cards/CardsPlaces.swift:724 — WeatherCard hard-codes `isDay: true`, so night conditions show sun icons and day gradients. Fix: request `is_day` from Open-Meteo and pass it through.
7. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Cards/CardsPlacesHelpers.swift:431-442 — the forecast cache has no TTL, so weather stays stale for the whole app session. Fix: store a timestamp and expire entries after about 15 minutes.
8. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Cards/CardsPlacesHelpers.swift:452 and /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Cards/CardsDo.swift:582,604 — `.urlQueryAllowed` leaves `&` and `+` unencoded, so "Tom & Jerry" or "A+B" geocodes or maps to the wrong place. Fix: build the query with `URLQueryItem` through `URLComponents`.
9. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Cards/CardsPlaces.swift:79 with /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Cards/CardsPlacesHelpers.swift:545 — a place with no photos shows a map snapshot in the hero and then a second map (`PlacesMiniMapView`) at the bottom. Fix: skip the mini map when the hero already shows a map.
10. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Cards/CardsPlacesHelpers.swift:627 — `PlacesMiniMapView` is a live MapKit `Map` in every chat card, which is heavy during scroll. Fix: use the cached `MKMapSnapshotter` image the other path already uses.
11. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Cards/CardsData.swift:88 and :95 (and 124-147) — `DataChartPoint` and `DataChartSeries` get a new `UUID()` on every `parseSeries()` call from `body`, so Charts re-identifies and animates on every render. Fix: use `id = label + index`, or parse once in `init`.
12. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Cards/CardsData.swift:131,144,1490,1495 — `Int(x!.double!)` traps on very large or non-finite values, and `Int(item.value * 100)` at :1778 is unclamped. Fix: guard with `abs(v) < 1e15` or use `Int(exactly:)`.
13. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Cards/CardsData.swift:1576-1611 — PollCard keeps the vote in local `@State`, so it resets when the row is recycled and allows a second vote. Its options also use `id: \.self`, which collides on duplicates. Fix: persist the vote per message or session, and use `id: \.offset`.
14. [High] /home/knight/Desktop/projects/linkup/bridge/linkup_bridge/server.py:177-188 — `transcript_text` keeps only the last 14,000 characters with no truncation marker, so the original request is silently dropped. Unfinished text blocks (no `text.end`) are also lost after Stop. Fix: summarise the older part, or pass a "[earlier context truncated]" header and flush partial blocks.
15. [Med] /home/knight/Desktop/projects/linkup/bridge/linkup_bridge/server.py:406-410 — `compare` starts agents in a loop with no try/except, so one failure leaves earlier sessions orphaned and the sheet shows an error. Retrying then creates duplicates. Fix: catch per agent, return the successes plus per-agent errors, and let the client show partial results.
16. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Multi/HandoffSheet.swift:296 — "Continue" is enabled even when the target agent is offline (line 216 shows "Agent is offline") or is the current agent, so the handoff fails or is pointless. Fix: disable the button when `available == false` or the target equals the current agent.
17. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Multi/CompareView.swift:84-90 and :134-143 — on iPad the segmented header sets `selectedPageIndex`, but the side-by-side layout ignores it, so tapping a tab does nothing. Fix: on iPad, scroll the columns with `ScrollViewReader` to the chosen index, or drop the tabs.
18. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Multi/RunningNowView.swift:23-55 with /home/knight/Desktop/projects/linkup/ios/Linkup/UI/RootView.swift:141 — RunningNowView does not hide the system nav bar, so the empty system bar stacks above its custom header. Fix: add `.toolbar(.hidden, for: .navigationBar)` as CompareView does.
19. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Multi/RunningNowView.swift:243 — the elapsed timer falls back to `session.updated`, which is the last event time, so the timer shows time since the last event rather than since the run started. Fix: track the turn start from the first status "running" event.
20. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Multi/CompareSheet.swift:277-296 — the compare Task is not stored or cancellable, so dismissing mid-run still navigates, and a hung request leaves the spinner forever. Fix: store the Task, cancel on dismiss, and add a timeout.
21. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Multi/CompareView.swift:337 — `turn?.started ?? Date()` inside the TimelineView makes the timer read 0:00 when `started` is nil. Fix: fall back to the session creation time.
22. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Multi/CompareView.swift:15-17 — `isPad` treats `.regular` size class as iPad, so iPhone Max landscape gets three squeezed columns. Fix: use `UIDevice` idiom alone, or a minimum width check.
23. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/Core/Store/SessionStore.swift:128-132 — `open` subscribes but nothing ever sends `unsubscribe` (the bridge supports it at server.py:313), so every session ever opened keeps streaming. Fix: unsubscribe when a session leaves the running list or the compare/running view closes.
24. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Multi/HandoffSheet.swift:12 and :302-312 — the default selection is "agy", then flips in `.task`, which causes a visible flicker. Fix: compute the initial value in `init`.
25. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Multi/HandoffSheet.swift:50, :89, :144 — default-model logic is duplicated three times. Fix: one computed property.

UX

26. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Multi/RunningNowView.swift:204 — Stop fires with no confirmation and no visible pending state, and the card keeps showing "running" until the bridge reports back. Fix: show "Stopping..." optimistically and confirm when it is a Claude session with unsaved work.
27. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Multi/RunningNowView.swift:101-103 — sessions waiting on a permission request appear as plain "running" with no way to act on them here. Fix: add a "Needs approval" badge that opens the session on the permission card.
28. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Multi/CompareSheet.swift:18-22 — agents are hard-coded and shown even when unavailable, so starting a compare with one offline fails mid-loop (see item 15). Fix: filter by `store.agents` availability and disable offline chips.

Cards: data trust and value

29. [High] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Cards/CardsPlaces.swift:1629 — CurrencyCard prefers a model-supplied `rate` over the live fetch, so invented or stale rates win. Fix: use the live rate and ignore `card["rate"]` unless the fetch fails.
30. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Cards/CardsData.swift (StockCard, CryptoCard, SportsCard) — these show numbers the model wrote from web search, with no timestamp or source, presented as market data. Fix: show "as of <date>" and a source, or remove the cards.

Clutter / remove

31. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Cards/CardRegistry.swift — 48 types with heavy overlap: place/places/map, stock/crypto/sports, quote/callout/definition/wiki, progress/metrics/conversion/currency. Fix: cut palette, math, translation, countdown, timezones, conversion, callout, wiki, and poll (see item 13); keep one list card and one text card.
32. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Cards/CardsData.swift:1576-1611 — PollCard sends "I vote: X" as a new user turn, which starts a paid agent turn, and shows no tally. Fix: remove it, or show live tallies in the same card.
33. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Cards/CardsPlaces.swift:9-116 — PlaceCard stacks nine blocks (hero, name, meta, rating, address, hours, summary, mini map, action row), which is too dense for a chat bubble. Fix: keep hero, name, rating, one action row, and tap-through to the detail sheet.
34. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Multi/RunningNowView.swift:142-146 — "Recently Finished" repeats the sidebar history. Fix: remove it, or show it only when the running list is empty.

Code health

35. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Cards/CardsData.swift (1982 lines), CardsPlaces.swift (1738), CardsDo.swift (1688) — three files over 1,500 lines with mixed concerns. Fix: one file per card family, with shared formatters in one helper file.
36. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Cards/CardsDoHelpers.swift, CardsMediaHelpers.swift:220-229, CardsData.swift:47-70 and CardsPlacesHelpers.swift:9-25 — four separate ISO-date and formatter setups, some allocated per call (the media helper creates `ISO8601DateFormatter` and `DateFormatter` every time). Fix: one shared `CardDates` helper with cached formatters.
37. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Multi/CompareSheet.swift:18-22, CompareView.swift:159-166 and :354-361, HandoffSheet.swift:23-39 — the agent name and logo mapping is copied in four places. Fix: one `AgentKind` display-name extension.
38. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Cards/RichTextView.swift:9 — `CardExtractor.segments` re-scans the full text on every render, including each streaming delta. Fix: cache segments per text (or per part) and recompute only when the text changes.

Missing

39. [Med] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Multi/HandoffSheet.swift — the sheet doesn't show what context will be carried or whether it was truncated. Fix: show "Carrying N messages (older truncated)" before the user taps Continue.
40. [Low] /home/knight/Desktop/projects/linkup/ios/Linkup/UI/Multi/CompareView.swift — no per-agent Stop and no "use this answer" action. Fix: add Stop per column (`store.interrupt`) and a Copy/Continue action on each finished column.

## 9. Visual design system (cross-cutting)

AUDIT (read-only, no files edited). Counts: 78 hard-coded `Color(red:` literals in 16 files, plus about 20 other literal colors (`Color.white`, `Color.black`, `Color(white:)`, `UIColor(` in 6 files). 278 `.system(size:)` calls across 36 files, using about 24 distinct sizes. 701 `Theme.sans(` calls, all fixed-point. 0 uses of Dynamic Type or `ScaledMetric`. Corner radii use 13 distinct values; paddings use 11 distinct values.

THEME-TOKENS
- [High] ios/Linkup/UI/Theme/Theme.swift (sans/serif/mono helpers) — The palette is a single token set, but 78 literal `Color(red:)` sites bypass it. Fix: add tokens for the repeated literals (glass tints, the #141413 code block, the status colors) and replace the call sites.
- [High] ios/Linkup/UI/Activity/ActivityViews.swift:785,819,854,930,959,979,1020,1111,1195 — Nine copies of `Color(red: 0x14/255…)` (#141413) for code/tool blocks. Fix: add `Theme.codeBackground` and replace all nine.
- [High] ios/Linkup/UI/Cards/CardsPlacesHelpers.swift:403-418 — About 10 hand-tuned gradient stops for place-card backgrounds that match no token. Fix: derive from `Theme.surface`/`elevated` with a single tint parameter.
- [Med] ios/Linkup/UI/Sidebar/SidebarView.swift:181,402,562 — `Color(white: 0.45)`, `Color.white` capsule, and a `#3A82F7` blue that is not in Theme (Theme.link is #7FB0F5). Fix: use `Theme.tertiaryText`, `Theme.text`, and `Theme.link`.
- [Med] ios/Linkup/UI/Usage/UsageRing.swift:5 vs ios/Linkup/UI/Cards/CardsDo.swift:1554 vs ios/LinkupWidgets/UsageWidget.swift:83 — Three different "warning" yellows (#E8B04B, 0.95/0.72/0.3, 0.95/0.72/0.45). Fix: one `Theme.warning` shared with the widget target.
- [Med] ios/Linkup/UI/Theme/Theme.swift:39-40 vs ios/Linkup/UI/Cards/CardsDo.swift:1615,1617 vs ios/Linkup/UI/Workspace/GitStatusView.swift:258 — Agent and purple colors are defined in several places with different values (agy blue vs Theme.link; purple 0.75/0.6/0.95 vs 0.70/0.50/0.95). Fix: `Theme.agentColor` and `Theme.purple`, used everywhere.
- [Med] ios/Linkup/UI/Workspace/WorkspaceComponents.swift:183-187 — Syntax-highlight colors are private literals. Fix: keep them, but move them into Theme as `Theme.syntax*` so the palette is in one place.
- [Med] ios/Linkup/UI/Cards/CardsDo.swift:176,778,1099,1213,1508 and CardsDo.swift:388 — `Color.white` text and `Color.yellow` stars instead of `Theme.text`/accent. Fix: `Theme.text`; use a star color token.
- [Low] ios/Linkup/UI/Workspace/GitHistoryView.swift, FileViewer.swift, ProjectsView.swift — Mixed use of `.foregroundStyle(.white)`, `Color.orange`, and `Color.red` on the same screens (for example CIRunsView.swift:150 uses `Color.orange`). Fix: route all status colors through Theme.

TYPOGRAPHY
- [High] ios/Linkup/UI/Theme/Theme.swift (sans/serif/mono helpers) — Every Theme font is `.system(size:)`, so none of the 701+ text sites scale with Dynamic Type or the accessibility sizes. Fix: map to `Font.TextStyle` (for example `Theme.sans(15)` becomes `.system(.subheadline)` with a scale), or use `@ScaledMetric` on the base size.
- [High] ios/Linkup/UI/Activity/ActivityViews.swift, Cards/*.swift, Sidebar/SidebarView.swift — 11, 12, 13, 15 pt used as body text in many rows (`.system(size: 11)` appears 30 times, 10 pt 14 times). Fix: floor body text at 15 pt and captions at 12 pt; reserve 9–10 pt for badges only.
- [High] ios/Linkup/UI/Artifacts/ArtifactViews.swift:136-186 — Six identical `.font(.system(size: 24, weight: .medium))` on tile-style labels. Fix: one `Theme.title` token.
- [Med] ios/Linkup/UI/RootView.swift:453,469,533 — 19 and 20 pt sizes for headers, with the title font set separately from the sidebar. Fix: use `Theme.title`/`Theme.headline`.
- [Med] Entire UI (749 `Text(` sites) — `lineLimit(1)` and `minimumScaleFactor` are almost absent (1 use of lineLimit(1) on Text), so long Arabic/French/Darija strings and file paths overflow or wrap badly. Fix: allow wrapping on message text; use `.truncationMode(.middle)` for paths.
- [Med] ios/Linkup/UI/Theme/Theme.swift serif helper — 38 `Theme.serif(` uses for agent text, but the serif is applied with no line-height or tracking, so long replies look dense. Fix: add `.lineSpacing` in the message view.
- [Low] ios/LinkupWidgets/UsageWidget.swift:228-231, LinkupLiveActivity.swift:49-174 — 9–12 pt fixed sizes in widgets (widgets are exempt from Dynamic Type, but still clip). Fix: use `.caption2` and test at the largest size.

SPACING-SHAPES
- [High] Global (ios/Linkup/UI/**) — `cornerRadius` takes 13 distinct values (12 ×84, 14 ×76, 10 ×44, 16 ×31, 8 ×18, 20 ×17, plus 6, 18, 22, 24, 28, 3, 1.5). Fix: three radii (`Theme.radiusS=10`, `radiusM=14`, `radiusL=22`) and the existing `bubbleRadius`/`composerRadius`.
- [High] Global — `.padding(...)` takes 11 values (16 ×24, 12 ×16, 14 ×15, 10 ×15, 8 ×9, 4 ×4, 20, 6, 3, 28, 18). Fix: a 4/8/12/16/24 spacing scale in Theme.
- [Med] ios/Linkup/UI/Theme/Theme.swift:margin = 18 — The page margin is 18, but most screens hard-code 16, so edges don't line up between sheets and the chat. Fix: use `Theme.margin` (or 16) everywhere.
- [Med] ios/Linkup/UI/Cards/CardsData.swift:627, ios/LinkupWidgets/LinkupLiveActivity.swift:104 — Fixed widths (`frame(maxWidth: 100)`, `44`) that clip at large Dynamic Type. Fix: use `minWidth` with `fixedSize`.
- [Low] Icon sizes — `AgentLogo` is used at 20, 24, 26 pt, and SF Symbol sizes are 40/44/52/64 pt in empty states across ProjectsView, GitHistory, CIRuns, and FileViewer. Fix: three icon sizes (16/24/40) and matching empty-state components.

LIQUID-GLASS
- [High] ios/Linkup/UI/Cards/CardsMedia.swift:87,179,284,428,605,868,926 and ios/Linkup/UI/Cards/CardsPlaces.swift:375,406,640,1379,1394 — Glass on content chips and cards (capsule glass on media rows and place-card actions). The guidance is glass on controls only. Fix: use `Theme.surface` with a hairline stroke for these; keep glass on the floating action buttons.
- [High] ios/Linkup/UI/Cards/CardsPlacesHelpers.swift:651,698,717,735,749 — Five more capsule glass uses on the place card body. Fix: same as above.
- [Med] ios/Linkup/UI/Cards/CardsMediaHelpers.swift:365 and CardsPlaces.swift:267 — Circle glass on overlays sitting on photos, where glass has no contrast. Fix: solid `Color.black.opacity(0.5)` circles.
- [Med] GlassEffectContainer usage — Only 4 containers (RootView.swift:419, ArtifactViews.swift:379, ActivityViews.swift:1247, UpdateBanner.swift:13, ScheduleEditor.swift:189). Adjacent glass controls in SidebarView.swift:386/665 and RootView.swift:459/542 are not grouped, so they don't morph together. Fix: wrap each control cluster in one container.
- [Med] Mixed glass styles — `.buttonStyle(.glass)` and `.glassEffect(.regular.interactive(), in: .circle)` are used side by side for the same kind of control (RootView, GitStatusView:335 vs 510). Fix: pick one per role (icon button = circle glass; text action = `.glass`/`.glassProminent`).
- [Low] ios/Linkup/UI/Composer/CommandSuggestions.swift:156, RootView.swift:413, VoiceModeView.swift:165 — Manual `.shadow` on glass/popover surfaces, which doubles up with the system glass depth. Fix: drop shadows on glass; keep one shadow for the drawer only.

DARK-MODE-ACCESSIBILITY
- [High] Theme.swift — The app is dark-only: `Theme` has no light variants and `.colorScheme`/`.preferredColorScheme` appear once. Fix: confirm this is intended; if not, add light values to each token.
- [High] Theme.swift:tertiaryText (#73716B) on background #1F1E1D — roughly 3.3:1 contrast, below the 4.5:1 target for body text. Used for timestamps and captions. Fix: lift to #8A877F (about 4.6:1).
- [Med] Sidebar/SidebarView.swift:181 — Availability state is shown by a color dot alone (`Theme.success` vs `Color(white:0.45)`). Fix: add an icon or label for the offline state.
- [Med] ios/Linkup/UI/Artifacts/ArtifactViews.swift:373,582,694 — Pure `Color.black` backgrounds next to warm `Theme.background` (#1F1E1D), so the artifact viewer looks like a different app. Fix: use `Theme.background`.
- [Low] ios/Linkup/UI/Composer/VoiceModeView.swift — Voice mode relies on glow color and animation to show state, with no text cue visible to VoiceOver. Fix: add `accessibilityValue` for the phase.

IPAD
- [High] ios/Linkup/UI/RootView.swift:278 — Drawer width is a hard `340` on iPad and `screenWidth * 0.82` on iPhone, with separate sidebar logic at lines 29-47, 119, 315, 341, 445. Fix: one `sidebarWidth` computed from `horizontalSizeClass` in one place.
- [Med] ios/Linkup/UI/Chat/ChatView.swift:67 and 6 other files (`maxWidth: 760`) — Max content width is set in 7 places with 760 (and 520 in Settings). Fix: a single `Theme.readableWidth` constant.
- [Med] ios/Linkup/UI/Multi/CompareView.swift:16 and Composer/CommandSuggestions.swift:26 — iPad detection uses `UIDevice.idiom == .pad || sizeClass == .regular`, which behaves differently across iPad Split View. Fix: use `horizontalSizeClass` only.

RTL (Arabic/Darija)
- [High] ios/Linkup/UI/Sidebar/SidebarView.swift:576 and RootView.swift:231 — `.offset(x:)` drag and `.move(edge: .leading)` are not RTL-aware, so the drawer opens from the wrong side under an Arabic locale. Fix: use `.offset` with `layoutDirection` mapping, or `.move(edge:)` via `.trailing` for RTL.
- [Med] ios/Linkup/UI/Workspace/GitStatusView.swift:558-594, NewProjectSheet.swift:187-251 — `alignment: .leading` and `multilineTextAlignment(.leading)` are hard-coded for labels. These read correctly in LTR and are acceptable, but mixed Arabic/Latin text needs `.natural`. Fix: use `.multilineTextAlignment(.natural)`.
- [Low] Global — No `.environment(\.layoutDirection)` override and no `.leading`/`.trailing` audit beyond these; the app is LTR-only in practice. Fix: test with the Arabic locale in the screenshot job.

ANIMATION
- [Med] Global — 70 `withAnimation` and 22 `.animation(` modifiers, with no shared spring constant. Fix: define `Theme.spring` and `Theme.quick` and use them.
- [Low] Global — `.symbolEffect` is used once; other state changes use `contentTransition` 22 times with no effect, so icons snap. Fix: add symbol effects on the send/stop and voice buttons.

TOP-10-HIGHEST-IMPACT-VISUAL-FIXES
1. Route all fonts through one scaled type scale (Theme.swift, then 278 `.system(size:)` sites) — fixes Dynamic Type and gives a consistent hierarchy.
2. Remove glass from content cards and place/media chips (CardsMedia.swift, CardsPlaces.swift, CardsPlacesHelpers.swift) — biggest single "looks off" cause; use solid surfaces with hairlines.
3. Replace the 13 corner radii and 11 padding values with a 3-radius, 5-step spacing scale.
4. Add `Theme.codeBackground` and replace the 9 #141413 copies in ActivityViews.swift.
5. Lift `tertiaryText` contrast to about 4.6:1 (Theme.swift).
6. Unify the warning, purple, and agent blues into Theme tokens (UsageRing, CardsDo, GitStatusView, SidebarView, widgets).
7. Replace pure black artifact backgrounds with `Theme.background` (ArtifactViews.swift:373,582,694).
8. One sidebar/drawer width and layout-direction source (RootView.swift:278 and the 760-width sites).
9. Group glass controls in GlassEffectContainer and use one glass style per role (RootView, SidebarView, GitStatusView).
10. Extend the screenshot job to cover the uncovered screens (workspace, composer voice mode, schedule editor, new-project sheet, dev-server preview) and add an Arabic locale and an XXXL Dynamic Type run.

Screenshot coverage (scripts/screens.sh SCREENS): home, chat, cards, sidebar, models, summary, artifact, settings, usage, connect, projects, running, compare, schedules, handoff. Not covered: GitStatus, GitHistory, CIRuns, FileBrowser/FileViewer, DevServerPreview, VoiceMode, NewProjectSheet, ScheduleEditor, HandoffSheet detail states. Production code leakage is limited to `UsageDashboardView.swift:52-53` (loads `screenshot-fixture.json` as a fallback) and `App/DebugLaunch.swift`, which only runs under `-LinkupScreen`.

---

# WAVE 2 — deep pass (12 auditors: 3 Sonnet, 4 Haiku, 5 Gemini 3.8 Flash)

About 380 new raw findings, many reported by more than one auditor. Below is the de-duplicated priority list. ✅ = I verified it in the code; ❌ = checked and wrong (dropped). Raw outputs follow.

## W2-A. Your screenshot, root-caused
1. ✅ **The sidebar shows behind the status bar while closed.** RootView.swift:118: the root `GeometryReader` has no `.ignoresSafeArea`, so `mainLayer` is framed and clipped to the safe-area rectangle (:410-412). `SidebarView` sits underneath at full opacity even when closed (:287-291; only hit-testing changes). Its ScrollView content draws into the status-bar strip.
   **Fix:** run the GeometryReader full-bleed, give `mainLayer` an opaque `Theme.background.ignoresSafeArea()`, and set the sidebar to `.opacity(0)` when closed. Mirror this on iPad.
2. **Chat text scrolls under the top bar with no blur.** The top bar is a sibling overlay rather than a bar of the ScrollView, so `.scrollEdgeEffectStyle(.soft)` (ChatView.swift:71) never applies.
   **Fix:** use `.safeAreaBar(edge: .top) { topBar }` (iOS 26), which gives the real blur and correct insets.
3. **The title and the first message collide with the top bar.** The space is reserved with hard-coded `.padding(.top, 70)` (ChatView.swift:53, 65, 319) and `.padding(.top, 60)` for the pinned strip (:77). The connection pill and update banner make the bar taller without moving the content. The `safeAreaBar` fix removes all of these.
4. **The composer is see-through, so card text shows behind it.** It is a plain `safeAreaInset(.bottom)` with no bottom edge effect (ChatView.swift:69, 138, 303). **Fix:** `.safeAreaBar(edge: .bottom)` plus `.scrollEdgeEffectStyle(.soft, for: .bottom)`.
5. **The model pill wraps to "Mediu/m".** The Text has no `lineLimit` or `fixedSize` (ComposerView.swift:436-441). The "spinner" is the 16pt `UsageRingBadge` drawn unconditionally (:427-431, UsageRing.swift:55-68).
6. ✅ **329.5k tokens for one reply.** Transcript.swift:132 adds `cacheRead` and `cacheWrite` to the input count, so a 500-token reply on a warm cache shows hundreds of thousands. Show input and output separately, with cached tokens labelled as cached.
7. **The scroll-to-bottom arrow overlaps the send button.** The overlay is attached before the composer inset (ChatView.swift:101-118).

## W2-B. Sidebar open/close
8. **The edge swipe freezes partway open.** `edgeSwipeZone` is removed as soon as `openProgress > 0` (RootView.swift:406), so `onEnded` never fires and `isDragging` stays true. *Reported by 3 auditors.*
9. **Dragging closed in one long swipe breaks the hamburger.** The scrim that owns the close gesture is removed mid-drag, leaving `isSidebarOpen = true` while the drawer looks closed (RootView.swift:369-401).
10. **The drawer jitters and trails the finger.** `DragGesture(coordinateSpace: .local)` sits inside the layer being offset (:380, :598). Use `.global`.
11. **The left 28pt of the chat is dead.** A full-height `Color.clear` gesture strip blocks taps, scrolling and text selection there (:598-600).
12. **Picking a chat, New session or an agent row snaps the drawer shut with no slide.** `isSidebarOpen = false` is set outside `withAnimation` (SidebarView.swift:165, 240, 276, 390; LinkupApp.swift:106; LiveManager.swift:312).
13. **The scrim, rounded corners and shadow pop instead of fading.** They are driven by `openProgress > 0 ? … : …` (RootView.swift:369, 412-413). Interpolate them, and add `.compositingGroup()` for drag performance.
14. **The keyboard stays up over the open drawer.** Resign first responder when opening.
15. **Row swipe (Pin/Delete) fights the drawer-close swipe and vertical scroll** (SidebarView.swift:577-597). Use `List` + `.swipeActions`, or coordinate the gestures.
16. **Swipe buttons are hidden only with opacity,** so VoiceOver reads a Delete button on every row. The chat behind the open drawer also stays in the VoiceOver tree.
17. **The sidebar re-renders on every ping (every 15s) and every session push** while always mounted (SidebarView.swift:215, 410-417).
18. **iPad Slide Over:** `drawerWidth` is hard-coded at 340pt, wider than the window, so the user is trapped in the sidebar.
19. **The sidebar footer ("Not connected" + avatar) overlaps the last rows.** The scrim is not opaque and the spacer is too short.

## W2-C. Switching chats
20. **Switching chats freezes the app.** `store.transcript(for:)` is called inside `body` and synchronously reads and decodes the whole jsonl, one JSONDecoder per line (ChatView.swift:17, SessionStore.swift:26-33). LiveManager does the same every second.
21. **The composer is destroyed and rebuilt** on the first message (two `ComposerView`s in the greeting/session branches) and on every switch (`.id(currentSessionId)`). Keyboard focus, draft, attachments, dictation and in-flight uploads are lost.
22. **Existing chats flash the greeting** ("Good evening") before their events load, then jump, and the scroll position settles late.
23. **First send:** text is cleared before `create` returns, so a failure loses it. Nothing blocks a second send, which creates two sessions. Tapping New chat meanwhile gets overridden when the create returns.
24. **Voice Mode closes itself after the first sentence in a new chat,** because creating the session changes the `.id` (VoiceModeView.swift:306-319).
25. **The iPad inspector keeps the previous chat's Summary or Artifact** after a switch or delete. Turn ids `a<seq>` collide across sessions.
26. **Subscriptions are never removed.** Every opened chat stays subscribed and in memory, and new chats send up to 3 `subscribe`s (ComposerView.swift:570-585, SessionStore+Extras.swift:233).
27. **Coming back to a chat that got events in the background doesn't scroll to them** (`scrollGluedToBottom` requires `isWorking`).
28. **An unread dot appears on the chat you're looking at** after every turn. The bridge sets unread on `turn.end`, and the app only marks read on open.
29. **Deleting a chat from another device leaves you in a dead chat.** Sending goes to a non-existent session.
30. **The top-bar title and model are missing on the new-chat screen** (the header is guarded by `if let session`).
31. **Antigravity and Hermes show a bogus "High" effort badge** taken from the global `draftEffort`.
32. **The agent switcher in the model sheet silently does nothing** inside an existing session.
33. **Handoff and fork:**
    - The handoff target opens as a blank greeting because the `notice` is dropped when there is no live turn.
    - Forking a streaming session creates a zombie stuck on "Working…".
34. **Sheets that don't close:**
    - Compare "Open" and the Compare "X" just pop inside the sheet.
    - Schedules "Run now" switches the chat behind the sheet.
    - Deleting a running chat leaves its Live Activity on the Dynamic Island.
35. **Rotating an iPhone Max or using iPad multitasking rebuilds everything:** draft, scroll and sidebar search are lost (RootView.swift:119-123).

## W2-D. Streaming
36. **The whole ChatView re-renders on every token.** `.onChange(of: transcript.lastSeq)` makes body track `lastSeq` (ChatView.swift:136).
37. **Each token re-renders the whole assistant turn,** not just the block, because the parent reads `block.text` (MessageViews.swift:225). Thinking tokens do the same through `turn.activity`.
38. **Markdown is parsed twice per token on the main thread,** and CardExtractor re-runs on the full text, which is O(n²) per reply (MessageViews.swift:530, 579-587). The throttle Task also writes stale text (:612-621).
39. **Every visible turn re-renders on each `session` push** because it reads `store.session`/`store.agents`, and CardActions creates a new closure each body.
40. **Per token on the main thread:** a JSON decode, a re-encode, and a file open/seek/close for the cache. Reconnect replays are appended to disk again as duplicates.
41. **Two auto-scroll drivers fight:** `defaultScrollAnchor(.bottom)` plus the throttled `scrollTo`, and `autoScrollTask` is never reset when its guard fails. A large block such as a code block, card or image counts as "user scrolled up", so auto-follow stops and the arrow appears. The scroll-up distance also ignores the composer inset.
42. **Send flashes Send → Voice → Stop,** and a fast double tap opens Voice Mode by accident (ComposerView.swift:474-514). The user bubble only appears after the bridge round-trip; there is no optimistic insert.
43. **Status/activity row problems:**
    - The activity line flickers back to "Working…" on each newline in thinking.
    - The row vanishes at turn end in chat mode, so the answer jumps up.
    - Thinking text expands, then snaps to 4 lines mid-stream.
44. **Permission card:** answering it makes the card vanish with no "Allowed"/"Denied" state.
45. **Artifact cards appear suddenly at the bottom** when the stream completes.
46. ✅ **Antigravity thinking blocks:** `agy.py:143-145` emits only `thinking.delta`, with no start or end, so blocks stay "active". Block ids `t{idx}` restart for each `agy -p` process, while `Transcript` only resets its dictionaries on reset (Transcript.swift:33), so turn 2's thinking appends to turn 1's block.
47. **The syntax highlighter turns the whole code block green** while an unclosed quote is streaming (MarkdownParser.swift:329-348). This is on top of the wave-1 `$` infinite loop.

## W2-E. Layout, sheets, keyboard
48. **Full-screen covers put their close/title under the Dynamic Island:** artifact viewer (ArtifactViews.swift:342-364), Voice Mode (VoiceModeView.swift:54-58), Cook Mode (CardsDoHelpers.swift:230-266). In landscape, Voice Mode overflows and traps you.
49. **Typing `/` pushes the composer and suggestions off the top.** In landscape the composer fills the whole screen.
50. **Sheet conflicts:**
    - Prompt library alerts cause keyboard focus loops.
    - New Project dismiss races the push.
    - Git Changes has two sheets on one view.
    - The QR scanner dismiss leaves Connect stuck.
51. **Half-height (`.medium`) sheets clip their content:** Compare (3 columns in a half sheet), Turn Summary and its drill-down, model picker, Settings, Handoff, Schedules, Git.
52. **Sheet chrome is inconsistent:** close buttons (pill, circle, left or right), backgrounds and dividers vary.
53. **iPad:**
    - Fixed 320/380 columns squeeze the chat.
    - The layout overflows in Slide Over or narrow Split View.
    - The reading width is uncapped.
    - The top bar doesn't align with the chat column.
54. **Top-bar buttons:** a 48pt circle and a 44×48 capsule, with mismatched icon weights. The new-chat button is labelled "More options".
55. **Compare agent chips wrap mid-word** ("Antigravi/ty"), and the effort chips have no selected state.
56. **Tap targets under 44pt:** message action icons, ellipsis (24pt), code copy, scroll-to-bottom (36pt), search toggle, swipe buttons, connection pill, Agent/Chat segment.

## W2-F. Journeys, bridge, CI
57. **QR pairing:** it dismisses Connect even when the bridge is unreachable. Funnel URLs with a path prefix can 404 (LinkupClient.swift:22-28).
58. ✅ **A Wi-Fi ↔ cellular switch can hang forever.** A failed ping is ignored (`try?`) and never triggers a reconnect (LinkupClient.swift:204).
59. **The bridge restarts and in-flight turns stay "Working" forever** on the phone.
60. **Projects:**
    - "New session here" in chat mode starts in the home directory instead.
    - `draftProject` persists in UserDefaults, so every later new chat is trapped in that project.
61. **"Resend" drops photo and file attachments** (MessageViews.swift:115-123).
62. **Background keep-alive doesn't engage** if you background the app right after sending.
63. **Voice Mode:**
    - Short replies ("Done.") are never spoken because a sentence needs more than 15 characters.
    - Streaming markdown links make speech skip.
    - The TTS voice and dictation follow the device locale only (no en/fr/ar choice).
64. **Opening an image, PDF or HTML from the file browser does nothing on iPhone.**
65. **Arabic/RTL:**
    - No direction handling in bubbles, markdown, lists, tables or the composer.
    - Search doesn't fold Arabic or diacritics.
    - No localization file.
66. **Accessibility:**
    - Many icon-only buttons have no labels.
    - Headings lack the header trait.
    - No Reduce Motion, Reduce Transparency or Increase Contrast handling.
    - Voice Mode makes no announcements.
67. **Animations:**
    - The voice orb scale conflicts.
    - Pin/delete rows jump.
    - World-clock cards rebuild every second.
    - LiveManager polls every 1s forever.
    - Timers are never cancelled.
68. **Crashes and data:**
    - `JSONValue.int` traps on NaN/inf/huge numbers from cards (JSONValue.swift:54).
    - A `-LinkupScreen` launch on a real phone overwrites your pairing (DebugLaunch.swift:120).
    - Deleted chats' cache files reappear.
    - Pins are never cleaned up.
69. **Security:**
    - The dev-server preview puts the bridge token in the URL; JS can read it, and "Open in Safari" leaks it.
    - The proxy can reach any localhost port, including Hermes on 8642.
    - `history.py` passes a client-supplied `nativeId` into glob.
70. **Bridge robustness:**
    - `history.py` crashes on non-dict lines.
    - Import double-creates sessions.
    - Any unknown CLI subcommand starts the server.
    - The service has no start limit and no `Wants=tailscaled`.
    - Redeploying kills running turns.
71. **CI:**
    - `make-source.py` has an empty entitlements list, so the app-group entitlement is missing (widgets and Live Activities break).
    - `gh release create` fails on re-run.
    - `screens.sh` never fails on missing shots.
    - The artifact screenshot is just the chat screen.

❌ Dropped: "Hermes SSE parser breaks on multi-line chunks". aiohttp's `r.content` iterates by line.

---

# WAVE 2 — raw auditor output

## Sonnet: layering/safe area

ROOT CAUSE (known bug)

Not run on device. The safe-area behaviour of `GeometryReader` and `ScrollView` below is from SwiftUI semantics and the code, so confirm it on a device or simulator.

1. RootView.swift:118 — the root `GeometryReader` respects the safe area.
   - `proxy.size` is the safe-area rectangle, and `proxy.safeAreaInsets` is ~0.
   - `mainLayer` is then framed and clipped to that rectangle (RootView.swift:410 `.frame(width: proxy.size.width, height: proxy.size.height)`, :412 `.clipShape`). It starts below the status bar and ends above the home indicator, so the status-bar strip is not covered by it.
2. RootView.swift:287-291 — `SidebarView` sits under the main layer and stays fully rendered while the drawer is closed.
   - Only `allowsHitTesting` and `accessibilityHidden` change. Opacity and offset never change, so it is never visually hidden.
3. SidebarView.swift:26 — its root is a `ScrollView` that touches the safe-area edge, so its viewport extends into the status-bar strip.
   - Rows ("From your PC") scrolled up there draw above the area the main layer covers.
   - `Theme.background.ignoresSafeArea()` at SidebarView.swift:55 is only a background and does not clip the content.
4. The chat has the same flaw, so the "no blur" symptom has the same cause.
   - `topBarSection` is a sibling overlay in the ZStack (RootView.swift:403), not a safe-area inset of the chat `ScrollView`. It also gets `safeAreaTop` = 0, so its padding is just 8.
   - The `ScrollView` therefore has nothing to blur against. `.scrollEdgeEffectStyle(.soft, for: .top)` at ChatView.swift:71 has no effect.
   - Text runs under the bar and is cut off hard at the clip edge. The bar only clears the content through magic paddings, `.padding(.top, 70)` at ChatView.swift:53 and :319 and `.padding(.top, 60)` at :77.
   - The connection pill and update banner grow the bar but not the content padding, so they overlap messages.

Fix, RootView:
```swift
GeometryReader { proxy in ... }
    .ignoresSafeArea(.container)          // real insets; keyboard avoidance kept

// iphoneDrawerLayout, sidebar layer:
SidebarView()
    .frame(width: drawerWidth).frame(maxHeight: .infinity)
    .opacity(ui.isSidebarOpen || openProgress > 0 ? 1 : 0)   // never visible when closed
    .allowsHitTesting(ui.isSidebarOpen || openProgress > 0)
    .accessibilityHidden(!(ui.isSidebarOpen || openProgress > 0))

// mainLayer: make the layer opaque full-bleed, and the top bar a real bar
ZStack(alignment: .top) {
    ChatView(sessionId: ui.currentSessionId)
        .id(ui.currentSessionId ?? "new")
        .safeAreaBar(edge: .top, spacing: 0) { topBarSection() }   // iOS 26; blur + insets for free
        .background(Theme.background.ignoresSafeArea())
    ...
}
```
- In `topBarSection`, use `.padding(.top, 8)` and drop the `safeAreaTop` parameter.
- In ChatView, delete the `.padding(.top, 70/60)` hacks at lines 53, 77 and 319. Keep `.scrollEdgeEffectStyle(.soft, for: .top)`.
- Mirror the same `safeAreaBar` change in the iPad layout (RootView.swift:241-248).

BUGS

1. [High] RootView.swift:406 — Edge swipe never opens the drawer correctly.
   - Symptom: after ~10 pt the drag stops, the drawer is left a few points open with a dim scrim, and `isDragging` is stuck true.
   - Cause: `edgeSwipeZone` exists only while `openProgress == 0`. The first `dragOffset > 0` flips that false, the view is removed mid-gesture, and `onEnded` never fires.
   - Fix: `if !ui.isSidebarOpen { edgeSwipeZone(...) }`, and reset the drag state with a `@GestureState` or an `onChange` cleanup.
2. [High] RootView.swift:380 and :598 — `DragGesture(coordinateSpace: .local)` is used on views inside the layer that gets `.offset(currentOffset)`.
   - Symptom: the drawer jitters and trails the finger. On release the translation is under-measured, so it snaps back when it should open or close.
   - Cause: local-space translation = finger movement minus `dragOffset`, a feedback loop.
   - Fix: use `coordinateSpace: .global` in both gestures.
3. [High] RootView.swift:598-600 — The 28 pt edge strip is a full-height `Color.clear` with a `DragGesture`, stacked above the chat.
   - Symptom: scrolling, taps and text selection starting in the left 28 pt of the chat do nothing. Code blocks and carousels near the left edge cannot be dragged. It also covers part of the hamburger (known).
   - Fix: replace it with a `UIScreenEdgePanGestureRecognizer` representable. Or put `.simultaneousGesture(DragGesture(minimumDistance: 12, coordinateSpace: .global))` on the whole ChatView and act only when `startLocation.x < 24` and the drag is horizontal-dominant.
4. [Med] ChatView.swift:17-19 and :303 — `Group { if transcript.items.isEmpty greetingView else sessionView }` holds two separate `ComposerView` instances (ChatView.swift:138 and :303).
   - Symptom: sending the first message in a new or empty session recreates the composer. The keyboard dismisses, and the draft, focus and dictation state reset. Opening a session also flashes the greeting before events load.
   - Fix: hoist a single `ComposerView` (via `safeAreaBar`) above the if/else, and switch only the content.
5. [Med] ChatView.swift:93-97 — The scrolled-up distance ignores the bottom content inset (the composer, ~100+ pt).
   - Symptom: the real "scrolled up" threshold is about 180 pt plus the composer height while streaming, so auto-scroll fights the user (this sharpens known item 4).
   - Fix: `contentSize.height + geometry.contentInsets.bottom - (contentOffset.y + containerSize.height)`, with a smaller threshold.
6. [Med] ChatView.swift:69, :138 and :303 — The composer is a plain `safeAreaInset(.bottom)`, so no bottom scroll-edge effect applies.
   - Symptom: chat text shows through the gaps beside and under the glass composer, with no fade.
   - Fix: `.safeAreaBar(edge: .bottom) { ComposerView(...) }`, plus `.scrollEdgeEffectStyle(.soft, for: .bottom)`.
7. [Med] RootView.swift:191 and :401-403 — Opening the drawer does not dismiss the keyboard.
   - Symptom: the keyboard stays over the drawer and shrinks it. The sidebar `bottomOverlay` (SidebarView.swift:~380-420) rides above the keyboard and covers the rows.
   - Fix: in `onChange(of: ui.isSidebarOpen)`, when opening, call `UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)`.
8. [Med] SidebarView.swift:241, :277 (session select), App/LinkupApp.swift:106-109 (`newChat`), LiveManager.swift:312, SidebarView.swift:812 — `ui.isSidebarOpen = false` is set outside `withAnimation`.
   - Symptom: selecting a session or tapping New Chat makes the drawer snap shut, while the chat swaps (`.id`) in the same frame, so it looks like a cut.
   - Fix: wrap those assignments in `withAnimation(.smooth(duration: 0.35))`, or add `.animation(.smooth(duration: 0.35), value: ui.isSidebarOpen)` on `mainLayer`.
9. [Med] RootView.swift:122-123 vs :119 — The ChatView `.id` and the layout branch both swap on a size-class change.
   - Symptom: rotating an iPhone Max or going to Split View loses the draft, scroll position and sidebar search/scroll state.
   - Fix: one stable view hierarchy with a custom layout (e.g. `ViewThatFits`, or `AnyLayout` with a stable ChatView).
10. [Low] RootView.swift:369 — The scrim is inserted and removed with `if openProgress > 0`, so a close animates through a removal transition. Always render it with `.opacity(0.35 * openProgress)` and `.allowsHitTesting(openProgress > 0)`.
11. [Low] RootView.swift:365-366 — While the drawer is open, the chat behind the scrim stays in the VoiceOver tree. Add `.accessibilityHidden(openProgress > 0)` to ChatView.
12. [Low] SidebarView.swift:~496-516 — The swipe-row Pin/Delete buttons use `.opacity(dragOffset < -10 ? 1 : 0)`. They are still in the accessibility tree and are focusable by hardware keyboard. Use `if`, or `.accessibilityHidden` / `.allowsHitTesting`.
13. [Low] RootView.swift:195-199 — The `onChange` that sets `dragOffset = 0` runs without animation and duplicates the explicit resets. Remove it, or wrap it in `withAnimation`.

GESTURES

14. [Med] RootView.swift:370-398 — Drawer close-drag exists only on the scrim, and `isDragging` is shared with the edge zone. A cancelled gesture (a system alert, say) never calls `onEnded`, so `dragOffset` is stuck.
    - Fix: use `@GestureState` for the offset, which auto-resets.
15. [Med] RootView.swift:395-397 — Release uses fixed `.smooth(0.35)` and ignores gesture velocity, so a flick feels the same as a slow drag. Use `.interpolatingSpring` or `.spring` with the predicted velocity, and a lower distance threshold.
16. [Low] SidebarView.swift:~578 — Row swipes use `simultaneousGesture` (min 20 pt) inside a vertical ScrollView; there is no `highPriority`/scroll-phase coordination, so slight diagonal drags both scroll and reveal. Prefer `List` with `.swipeActions` (already in AUDIT #15; this adds a gesture-order cause).
17. [Low] RootView.swift:406-408 — The edge zone is declared last, so it beats the top bar even where the zone is only meant for the gap. Hamburger overlap is known. Clip the zone to below the top bar once the bar is a `safeAreaBar`.

ANIMATION

18. [Med] RootView.swift:412-413 — `cornerRadius: openProgress > 0 ? 20 : 0` and the shadow opacity step instantly at the first dragged pixel, so the corners and shadow pop in. Fix: `cornerRadius: 20 * min(1, openProgress * 6)`, and shadow opacity `0.35 * min(1, openProgress * 4)`.
19. [Low] RootView.swift:412-413 — Clip, then shadow, then offset runs a full-screen blur shadow on a layer containing glass and a ScrollView, every frame, so drags drop frames. Wrap it in `.compositingGroup()`, or draw the shadow with a separate `Rectangle().fill(...).blur` behind the layer.
20. [Low] RootView.swift:285-299 — The sidebar has no parallax or dimming (static under the main layer). Add `.offset(x: -40 * (1 - openProgress))` and `.opacity(0.6 + 0.4 * openProgress)`, tied to the same progress value.
21. [Low] RootView.swift:268-269 and :241-247 — On iPad the sidebar and inspector transitions use `.move + .opacity` inside an HStack, so the chat column relayouts every frame (it contains ChatView and the `ScrollViewReader`). Consider an overlay or offset for the inspector.

IDENTITY

22. [Med] RootView.swift:243 and :364 — `.id(ui.currentSessionId ?? "new")` resets all of ChatView's `@State` (`isUserScrolledUp`, `autoScrollTask`, and the composer text, attachments, focus, dictation). It runs on the nil-to-id change after the first send (see #4), and the whole subtree remounts, so there is a flash and scroll position is lost. `.task(id: sessionId)` already re-fires on its own, so the `.id` is redundant; remove it and key transcript state by session id.
23. [Low] ChatView.swift:51 and :54 — `.id(item.id)` on views that are already `ForEach`-identified is redundant. With the turn ids built as `"a\(lastSeq)"` it forces a state reset when an id shifts (see AUDIT #22).
24. [Low] InspectorView.swift:18 and :21 — `.id(artifact.url)` and `.id(turn.id)` rebuild the viewer each time the model changes; this is correct but costly, and the artifact WebView reloads on any state change that touches `ui.openArtifact`.

SHEETS / DRAWER

25. [Med] RootView.swift:126-179 together with SidebarView's own `.sheet`, `.alert` and `.confirmationDialog` (SidebarView.swift:57-90) — Presenters are split across two levels. A RootView sheet opened from a drawer action (known: the drawer is not closed) leaves the drawer open under the sheet, and the sidebar's alerts and dialogs are anchored to a view that is covered by the main layer. Fix: route all presentations through one `ActiveSheet` on RootView and close the drawer first.
26. [Low] RootView.swift:17-48 — `summaryTurnBinding` and `openArtifactBinding` return nil when `horizontalSizeClass == .regular`. If a sheet is open and the window goes regular (Split View), it is dismissed with no setter call. Rotating back does not reopen it, but `ui.summaryTurn` stays set, so the inspector column appears with no visible trigger.

## Sonnet: state/lifecycle

SIDEBAR

1. [High] ios/Linkup/UI/RootView.swift:406,597-615 — Edge-swipe to open leaves the drawer stuck partway open. — The `edgeSwipeZone` exists only while `!isSidebarOpen && openProgress == 0`. The first `onChanged` sets `dragOffset`, so `openProgress > 0` and the zone is removed mid-gesture. A removed view's gesture is cancelled and `onEnded` never fires, so `isDragging` stays true and `dragOffset` is left at its last value. I traced this but did not run it on a device. — Fix: keep the zone always mounted (use `allowsHitTesting`), or drive open and close from one container-level gesture.

2. [High] ios/Linkup/UI/RootView.swift:369-401 — Dragging the drawer closed in one continuous drag can leave state out of sync, so the hamburger stops working. — If `translation <= -drawerWidth`, `openProgress` becomes 0 and the scrim (which owns the close gesture) is removed mid-drag. `onEnded` never runs, so `isSidebarOpen` stays true while `dragOffset = -drawerWidth`. The offset is then 0, the drawer looks closed, and the hamburger sets true to true, so nothing changes. The edge zone is also unmounted because `isSidebarOpen` is true. — Fix: keep the scrim mounted while `isSidebarOpen || dragOffset != 0`, and reset state in a `.onChange` of the drag state.

3. [Med] ios/Linkup/UI/Sidebar/SidebarView.swift:240,276 and RootView.swift:466, LinkupApp.swift:106 — The drawer snaps shut with no animation when you pick a chat or tap New chat. — `onSelect` and `newChat()` set `isSidebarOpen = false` outside `withAnimation`, and nothing animates the offset. The heavy ChatView rebuild (SWITCHING #1) lands in the same frame as the snap. — Fix: wrap the close in `withAnimation(.smooth)` and set `currentSessionId` after the animation starts.

4. [Med] ios/Linkup/UI/Sidebar/SidebarView.swift:215,410-417 — The whole sidebar re-evaluates on every ping and every session push. — The body reads `client.latencyMs` (written every 15s by `LinkupClient.startPing`), `client.state` and `store.sessions` (replaced on every `session` op). The sidebar is always mounted under the chat on iPhone. — Fix: move the footer and `Running now` badge into small child views, and make rows Equatable.

5. [Med] ios/Linkup/Core/Store/SessionStore.swift:82-97 — Every `session` op sorts, re-encodes and rewrites all of sessions.json from the main thread, and the status pushes come in bursts. `server.py:125` pushes on every `status` event. A running session makes rows jump and invalidates every ChatView reader of `store.sessions`. — Fix: skip `upsert` when the SessionInfo is equal, and encode off the main actor with debounce.

6. [Med] ios/Linkup/Core/Store/SessionStore.swift:128-132, bridge server.py:139 — The chat you are viewing shows an unread dot after each finished turn. — The bridge sets `unread=1` on every `turn.end`. The app only posts `read` in `open()`, which runs once per session switch. — Fix: when `turn.end` arrives for `ui.currentSessionId` and the app is active, post `read`.

7. [Med] ios/Linkup/UI/Sidebar/SidebarView.swift:81 and RootView.swift:182 vs SessionStore.swift:93 — Remote deletion (the `deleted` op) never resets `ui.currentSessionId`. — `removeLocal` clears the transcript, but the open ChatView keeps the dead id. The next `store.transcript(for:)` in body creates a fresh empty Transcript, reads the cache file and shows the greeting plus a composer. Sending goes to a session that no longer exists. — Fix: in `removeLocal`, if the id is current, call `ui.newChat()`, via a callback on the store.

8. [Low] ios/Linkup/UI/Sidebar/SidebarView.swift:493 — A revealed swipe row stays open when the drawer closes or another row opens, because `isRevealed` and `dragOffset` are per-row @State. — Fix: keep `revealedId` in the sidebar and reset it when the drawer closes.

SWITCHING

1. [High] ios/Linkup/UI/Chat/ChatView.swift:17 and SessionStore.swift:26-33 — Switching chats freezes the main thread. — `store.transcript(for:)` is called inside `body`. On a cold session it synchronously reads the jsonl file, makes a new `JSONDecoder` per line, decodes every event and replays it through `apply`. LiveManager.poll (LiveManager.swift:82) does the same once a second for running sessions. — Fix: load in a detached task and show a skeleton, with a shared decoder and a snapshot file.

2. [High] ios/Linkup/UI/Chat/ChatView.swift:18-22,120,321 — The composer is rebuilt when the first message arrives, and on every switch. — `ComposerView` is created in two branches (`greetingView` and `sessionView`). When `items` goes from empty to non-empty, the composer is destroyed and recreated. The view-level `.id(ui.currentSessionId ?? "new")` at RootView.swift:244,365 does the same on every switch. Typing state, `@FocusState` (keyboard drops), dictation, attachments and in-flight upload Tasks are lost. — Fix: one persistent ComposerView outside the branch, with per-session drafts in a store.

3. [High] ios/Linkup/UI/Chat/ChatView.swift:16-22 — An existing session whose cache is empty (or still loading) shows the "Good evening" greeting, then swaps to the chat when the replay arrives. The ScrollView is created late, so `defaultScrollAnchor(.bottom)` applies to a freshly built, very tall LazyVStack and the scroll position settles late. — Fix: show a loading state when the session has events (`lastSeq > 0` in SessionInfo) but the transcript is empty.

4. [High] ios/Linkup/UI/Composer/ComposerView.swift:554-588 — The first message creates the session after text and attachments are already cleared, and nothing stops a second send. — The composer stays mounted with `sessionId == nil` until `create` returns, so a second send creates a second session. A failed or offline create loses the text. If the user taps New chat meanwhile, the Task still sets `ui.currentSessionId = s.id` and pulls them away. — Fix: lock the composer while creating, clear text only on success, and ignore the result if `currentSessionId` changed.

5. [Med] ios/Linkup/UI/RootView.swift:206-221, App/LinkupApp.swift:105-109 — Selecting a session or calling `newChat()` leaves `ui.summaryTurn` and `ui.openArtifact` set. On iPad the inspector keeps showing the previous chat's Summary or Artifact. `InspectorView.swift:21` uses `.id(turn.id)`, and turn ids are `a<seq>`, so they can collide across sessions. — Fix: clear both in `currentSessionId` didSet, and key by session id plus turn id.

6. [Med] ios/Linkup/UI/RootView.swift:119-123 — A size-class change (rotation, iPad multitasking, iPhone Max landscape) recreates SidebarView and ChatView, because they sit under different `if` branches. `.task` fires again, the composer, scroll and sidebar search are reset, and `store.open` re-subscribes. — Fix: use one layout tree and vary only frames and offsets.

7. [Med] ios/Linkup/UI/Chat/ChatView.swift:27-34 vs SessionStore.swift:128 — Nothing ever unsubscribes. Every chat opened stays subscribed (`server.broadcast` sends events to all subscribed sessions), and its Transcript is never evicted from `transcripts`. Memory and traffic grow with every chat you open. The `.task(id:)` also duplicates the `.id()` reset and makes `open()` fire twice on creation (ComposerView.swift:572 plus the task). — Fix: add an `unsubscribe` op and an LRU for transcripts, and drop the explicit `open` in the composer.

8. [Med] ios/Linkup/Core/Store/SessionStore.swift:52-60 and Core/Live/LiveManager.swift:82 — Events can be lost for a session whose Transcript does not exist yet. — `ingest` writes to the cache via an async utility queue and skips `apply` when no Transcript exists. A Transcript created a moment later (LiveManager's 1s poll, or `open`) reads the file on the main thread and can miss queued appends. The next live event has `seq` greater than `lastSeq + 1`, and the guard at Transcript.swift:38 accepts it. The gap is never resynced. — Fix: have `loadEvents` run `queue.sync {}` first, or hold the events in memory until the Transcript exists.

9. [Med] ios/Linkup/UI/Chat/ChatView.swift:70,46,61-63 — The scroll position is unreliable on switch. — `defaultScrollAnchor(.bottom)` plus `scrollTo("chat_bottom")` inside a LazyVStack uses estimated row heights. When rows measure, the offset jumps. `RemoteImageView` (ArtifactViews.swift:513) has a `.empty` phase with no fixed height, so images change row height after load and the view shifts. — Fix: give image placeholders a fixed aspect ratio, and on switch do a single deferred `scrollTo` without animation.

10. [Low] ios/Linkup/UI/RootView.swift:161-163 — The model picker sheet is bound to `ui.currentSessionId`. If a session switch happens while it is open (notification tap at LiveManager.swift:311), the sheet silently retargets. Notification taps also leave the sidebar state and any open sheets as they were. — Fix: snapshot the id in the sheet item.

11. [Low] ios/Linkup/UI/Composer/ComposerView.swift:149-163,595-621 — Upload and photo Tasks write to the old composer's @State after a switch. The attachment is silently lost and the toast names a file from another chat. — Fix: tie uploads to a store-owned draft.

STREAMING

1. [High] ios/Linkup/UI/Chat/ChatView.swift:136 — The whole ChatView body re-runs on every event. — `.onChange(of: transcript.lastSeq)` reads `lastSeq` during body evaluation, so the body is tracked against it. `lastSeq` is a tracked property of an @Observable and is written for every event. `ForEach(transcript.items)` is rebuilt, `pinnedTurns` runs, and so on. — Fix: mark `lastSeq` `@ObservationIgnored`, and drive auto-scroll from the live turn's text length or a separate throttled tick property.

2. [High] ios/Linkup/UI/Chat/MessageViews.swift:225 — Each streaming token invalidates the whole AssistantTurnView, not just one block. — `RichTextView(text: block.text, ...)` reads `block.text` in the parent's ForEach body. The `Transcript.swift:5` comment claims "re-renders only that block", but the parent does the reading. `turn.activity` (Transcript.swift:~212) also reads thinking text, so thinking tokens re-render the turn too. — Fix: pass the TextBlock object to a child view (`BlockTextView(block:)`) that reads `.text`.

3. [High] ios/Linkup/UI/Chat/MessageViews.swift:530,579-587 and UI/Cards/RichTextView.swift:9 — Each token parses markdown twice, on the main thread. — `body` runs `ChatMarkdownParser.parse` over the full text. Then `.onChange(of: text)` writes `bufferedText`, which triggers a second body and parse. `CardExtractor.segments` is also re-run on the full text. Cost is O(n²) over a reply. — Fix: parse once per throttled update into @State blocks, or cache by text hash.

4. [Med] ios/Linkup/UI/Chat/MessageViews.swift:612-621 — The throttle Task captures `text` from the struct copy that existed when the Task was created, so it writes stale text after the 50 ms delay. The last chunk shows only when `isStreaming` flips to false. — Fix: read the latest text from the model (the TextBlock), or schedule from `onChange` only.

5. [Med] ios/Linkup/UI/Chat/MessageViews.swift:143,178,190,304 — Every AssistantTurnView reads `store.session(sessionId)` and `store.agents`. When a `session` op arrives (status, turn.end, rename, and so on), every visible turn re-renders and re-parses all its markdown. — Fix: pass `agentId`, `model` and `isChatMode` from ChatView as plain values, or compare them in an Equatable wrapper.

6. [Med] ios/Linkup/UI/Chat/ChatView.swift:42,263,342 — ChatView reads `store.session(id)` and `store.agent(...)`, so it is also invalidated by every session push. Combined with finding 1, this is a full re-diff of the list. — Fix: split the header and footer into small views.

7. [Med] ios/Linkup/UI/Composer/ComposerView.swift:19 and ChatView.swift:120 — `@State private var dictation = ComposerDictation()` evaluates its default expression each time ComposerView is constructed, which is every ChatView body (per token). Each one allocates an SFSpeechRecognizer and discards it. — Fix: create it lazily on first mic tap, or hold it in `@State var dictation: ComposerDictation?`.

8. [Med] ios/Linkup/UI/Chat/MessageViews.swift:201 — `.environment(\.cardActions, CardActions(send: ...))` builds a new closure each body. Environment changes can then invalidate every card consumer under the turn. — Fix: make CardActions Equatable by session id.

9. [Med] ios/Linkup/Core/Net/LinkupClient.swift:117-132 and SessionStore.swift:54-58 — Per token on the main thread: a JSON decode of the frame, a `JSONEncoder` re-encode in `cache.append`, and a FileHandle open, seek and close on the utility queue. — Fix: decode on a background actor, append the raw frame string, and batch writes every 200 ms.

10. [Med] ios/Linkup/UI/Chat/ChatView.swift:152-176 — The throttled auto-scroll has a state bug. `autoScrollTask` is reset to nil only inside the `if !Task.isCancelled && ...` branch. If the condition fails (user scrolled up or turn ended), it stays non-nil. The `else if autoScrollTask == nil` guard then blocks later trailing scrolls until a 75 ms gap occurs, which causes stutter. The Task also captures `transcript` and the old view. — Fix: use `defer { autoScrollTask = nil }` and cancel the task in `.onDisappear`.

11. [Med] ios/Linkup/UI/Chat/ChatView.swift:89-100 — `isUserScrolledUp` is written from the geometry callback during streaming, with `withAnimation`. A large block arriving (code, card, image) adds more than 180pt in one layout pass and flips the flag. Auto-follow stops and the arrow appears. The arrow button at line 104 sets the flag to false before the scroll, and the callback can flip it back. — Fix: decide "user scrolled" from the scroll phase (`onScrollPhaseChange`), not from distance.

12. [Low] ios/Linkup/Core/Store/Transcript.swift:36-40,141 — The Transcript's dictionaries `tools`, `texts` and `thinking` are never cleared between turns. agy block ids are `s{step_index}` and `t{step_index}` (agy.py:139-145). If the index restarts per `agy -p` process, a `thinking.delta` with no start appends to the previous turn's block. I could not confirm whether the index restarts. — Fix: clear the dictionaries on `turn.start`, or prefix ids with the turn.

13. [Low] ios/Linkup/Core/Store/Transcript.swift:~229 (`startTurn`) — Turn ids are `a\(lastSeq)`, and user ids are `u\(seq)`. Events with `seq == 0` collide, and the id is the key for PinnedStore. Pins break if events are ever renumbered after a bridge DB reset. — Fix: use the bridge's turn id, or the first event's seq plus the session id.

14. [Low] ios/Linkup/UI/Chat/ChatView.swift:122-135 — On a user message `isUserScrolledUp = false` and an animated `scrollTo` run. The same event then triggers `onChange(of: lastSeq)`. Both fire for one batch of events, which causes a double scroll. — Fix: use a single scroll trigger.

GENERAL

1. [Med] ios/Linkup/UI/RootView.swift:115-123,411-413 — Dragging the drawer re-evaluates the whole RootView body every frame (`dragOffset` is @State). The ChatView sits under `.clipShape` and `.shadow` with an animated corner radius, so the full chat is composited offscreen each frame. The topBar glass containers re-run too. — Fix: hold `dragOffset` in a small child view or `GestureState`, and apply the shadow and clip to a lightweight background only.

2. [Med] ios/Linkup/UI/RootView.swift:68-71,490-545 — RootView reads `store.session(id)` (via `currentSession`) and `client.state`, and re-runs on every session push. — Fix: move the top bar into its own view.

3. [Low] ios/Linkup/UI/RootView.swift:196-208 — `ui.toast` is cleared by `.task(id: ui.toast)`. Setting the same message again while it is shown (for example two "Copied" taps) does not restart the timer, so the second toast disappears early. — Fix: use a toast id counter.

4. [Low] ios/Linkup/UI/Activity/ActivityViews.swift:571,590 — The repeatForever pulse animations are started in `onAppear` and are never reset. `ToolIconView` keeps animating after the tool finishes (no visible effect, but the animation keeps running). If the view is reused with a new `isRunning`, the animation state is stale. — Fix: bind the animation to `.animation(.repeatForever, value: isRunning)`, or use `TimelineView`/`phaseAnimator`.

5. [Low] ios/Linkup/UI/Chat/PinnedStore.swift:18 — Every `isPinned` read in every turn tracks the single `revision` counter, so pinning one message re-renders all turn headers (and the menu labels at MessageViews.swift:434). Pins of deleted sessions are never removed from UserDefaults (SessionStore.swift:93). — Fix: store the per-session set in an observable box, and delete keys in `removeLocal`.

6. [Low] ios/Linkup/Core/Live/LiveManager.swift:76-89 — The 1s poll calls `store.transcript(for:)` for ids in `previouslyRunningSessions` and `activeActivities`. This can resurrect a Transcript for a session just deleted, and reads the cache file on the main thread for sessions not yet opened. — Fix: skip ids not in `store.sessions`, and use a non-creating lookup.

7. [Low] ios/Linkup/Core/Store/SessionStore.swift:183-185,235-238 — `delete` queues file removal asynchronously, while late events for that session recreate the file via `cache.append`'s fallback `data.write`. Deleted sessions' jsonl files reappear. — Fix: tombstone deleted ids in `ingest`.

8. [Low] ios/Linkup/Core/Store/SessionStore.swift:56-60 — Reconnect replays are appended to disk again even when `apply` ignores them as duplicates (`seq <= lastSeq`). The jsonl grows with duplicates and the next cold load replays them. — Fix: append only when `apply` accepts the event (return a Bool).

9. [Low] ios/Linkup/UI/Chat/MessageViews.swift:104-109 (post) and ChatView/ComposerView (no `onReceive`) — "Edit & resend" posts `linkupComposerSetText`, and the `LinkupFocusSearch` post at RootView.swift:328 likewise has no observer. This is already in AUDIT item 11. The note here is that the composer is rebuilt on every switch, so an observer would also need a store-owned draft. — Fix: put the draft text in a store.

## Sonnet: visual QA from screenshots

Note: the Google Drive connector needs authorization in claude.ai connector settings. It wasn't used here.

Visual QA of Linkup: new findings beyond AUDIT.md. I read only the first 255 of 617 lines of AUDIT.md, so a few items may already be in the unread part. Nothing was edited. I could not cite exact lines for the Compare chips, the Effort chips, the scroll-to-bottom button or most per-sheet items; those need a grep before fixing.

**iPhone chat and cards**
1. [High] chat — Content scrolls under the status bar and the floating top bar. The only fade is `.scrollEdgeEffectStyle(.soft, for: .top)`, which is invisible over the custom bar. Chat/ChatView.swift:71, :75. Fix: put an opaque-to-clear gradient or `.safeAreaBar` behind the top bar, sized to safe-area top + 60.
2. [High] chat — Title and subtitle collide with card content and weather chips. Chat/ChatView.swift:65 sets a fixed 70pt top padding that is smaller than the real bar height. Fix: use `.safeAreaInset(edge: .top)` with the measured bar height instead of a constant.
3. [High] chat — The composer is see-through over the Currency card, so text shows through. Chat/ChatView.swift:119 (bottom inset), Composer/ComposerView.swift (container). Fix: add a Theme.background gradient under the composer, with glass only on the buttons.
4. [Med] chat — The scroll-to-bottom button overlaps the send/waveform button. Chat/ChatView.swift:109. Fix: offset it by the composer height, or put it in the same safeAreaInset stack.
5. [High] model pill — "Mediu/m" wraps and a stray spinner appears. The Text has no `.lineLimit(1)` or `.fixedSize`. Composer/ComposerView.swift:439-440, with the effort string from :100. Fix: add `.lineLimit(1)`, `.fixedSize(horizontal: true, vertical: false)` and `.minimumScaleFactor(0.8)`; let the name truncate before the effort does.
6. [Med] model pill — The glass capsule is 44pt and the usage ring is only 16pt, so the pill looks crowded. Composer/ComposerView.swift:421-433. Fix: drop the ring when width is tight, or move the plan usage into the picker.
7. [Low] composer — The "+", "/", mic and model pill are all separate glass elements of mixed shape. Composer/ComposerView.swift:395-415. Fix: wrap them in one `GlassEffectContainer`, or use a single glass bar.
8. [Low] composer — Control icon sizes are inconsistent (19, 20 and 20 semibold rounded). Composer/ComposerView.swift:393, :405, :454. Fix: use one 19pt medium size and one frame.
9. [Low] attachments — The xmark badge is 18pt white-on-black and the progress overlay is a hard-coded black at 0.45. Composer/ComposerView.swift:339-358. Fix: use Theme tokens and a 20pt hit target.

**Top bar**
10. [High] hamburger and new-chat — The hamburger is a 48pt glass circle and the right-side button is a 44x48 capsule, so heights and shapes are unbalanced. The new-chat button is labelled "More options" but its icon is `plus.bubble.fill`. RootView.swift:443-460, :535-545. Fix: use two matching 44pt circles and correct the accessibility label.
11. [Med] top bar — Hamburger weight (20 medium) and plus.bubble (19 medium, filled) differ in size and fill style. RootView.swift:454, :538. Fix: match them (same size, both outline).
12. [Med] connection pill — The glass pill sits on top of content. RootView.swift:586. Fix: show it as a plain dot in the top bar; reserve glass for buttons.

**Sidebar**
13. [High] sidebar footer — "Not connected" and the "L" avatar overlap the last history row. The gradient scrim is 0.85 opaque at the top and only fully opaque at the bottom, and the 120pt spacer is too short. Sidebar/SidebarView.swift:49-50, ~420-433. Fix: make the footer a solid Theme.background block, and make the scroll bottom inset equal the measured footer height.
14. [Med] sidebar — The chat peeks out at the right of the open drawer. The drawer is 82% of width while the main layer is only partly covered. RootView.swift:265 (drawerWidth). Fix: dim and shrink the main layer, or use full-width opaque panes.
15. [Med] sidebar — The "New session" pill is white with fixed 18pt text and a 16pt icon. It is the loudest element on screen and is not a Claude pattern (already in AUDIT for colour only). Sidebar/SidebarView.swift:389-402. Fix: use an accent-tinted or `Theme.elevated` pill.
16. [Low] sidebar — The avatar circle (48pt glass) and the New session button (48pt) have different shapes in the same row. Sidebar/SidebarView.swift:380-402. Fix: make the avatar 44pt, or merge the two.

**Sheets (all)**
17. [High] sheets — Close buttons are inconsistent: some are a pill, some a circle, and Connect has it on the right. Settings/SettingsViews.swift:34, :450, :511, :608; Multi/CompareSheet.swift:81; Multi/HandoffSheet.swift:101; Multi/RunningNowView.swift:62; Schedules/SchedulesView.swift:52; Workspace/ProjectsView.swift:47. Fix: one shared `SheetCloseButton` (trailing circle, 32pt).
18. [Med] sheets — Backgrounds differ: GitStatusView.swift:531 uses `Theme.background` while the rest use `Theme.surface`. Fix: use `Theme.surface` everywhere.
19. [Med] sheets — Nine or more sheets default to `[.medium, .large]`, so content opens clipped at the medium size (Settings, Handoff, Compare, Schedules, Git history, Git status). Examples: Multi/HandoffSheet.swift:83, Multi/CompareSheet.swift:64, Schedules/SchedulesView.swift:84, Workspace/GitHistoryView.swift:294. Fix: use `.large` for list-heavy sheets, `.fixedSize`-driven heights for small ones.
20. [Low] sheets — Divider() between rows uses the system colour, not `Theme.hairline`. Multi/CompareView.swift:233, :292; Multi/HandoffSheet.swift:259; Workspace/GitStatusView.swift:191. Fix: replace with a `Theme.hairline` rectangle.

**Compare**
21. [High] Compare — The agent chips wrap mid-word ("Antigravi/ty"), have unequal heights and show no selected state. Multi/CompareSheet.swift (agent chip row, around :115-130). Fix: single-line, `.minimumScaleFactor`, equal widths and an accent-filled selected state.

**Composer pickers**
22. [Med] Models/Effort — The effort chips (ComposerView.swift:885-905) show no selected state. Fix: use accent fill plus a check mark.
23. [Med] Models — The model picker sheet opens at medium and clips its rows (ComposerView.swift:654 onward). Fix: use `.large`.

**Settings**
24. [Med] Settings — Section headers and row styles differ from the Claude app: grouped cards with mixed corner styles (SettingsViews.swift:90, :138, :155, :197). Already noted in AUDIT for radii; also the sheet at :460 is a medium detent that clips. Fix: one `SettingsCard` and `.large`.

**Home / empty state**
25. [Med] home — The empty state is weakly hierarchical, with no greeting or suggestions. Fix: add a serif greeting and 3 suggestion rows like Claude's.
26. [Low] home — Spacing above the empty-state title relies on the 96pt horizontal padding (RootView.swift:562), already in AUDIT.

**Usage, Handoff, Schedules, Projects, Running**
27. [Med] Usage — Ring badges and tags use different sizes and corner radii from the model pill ring (16pt). Fix: share one `UsageRingBadge` size scale.
28. [Med] Handoff — Rows have inconsistent padding and divider insets. Multi/HandoffSheet.swift:259. Fix: shared row component.
29. [Med] Schedules — The error banner uses a different corner radius and colour from other banners. Fix: one `Banner` component.
30. [Low] Projects — The empty state is bare text with large empty space. Workspace/ProjectsView.swift:47-100. Fix: icon, one line of copy and an action button.
31. [Low] Running — Header style differs from the other sheets (Multi/RunningNowView.swift:47-62). Fix: shared sheet header.

**Artifact**
32. [High] artifact — `iphone-artifact.png` is identical to `iphone-chat.png`, so the artifact viewer is not rendered in CI and cannot be reviewed. Fix: add a fixture route for the artifact screen.

**iPad**
33. [High] iPad chat — The column stretches to 100+ characters per line. Chat/ChatView.swift:67-68 caps content at 760 but the 320 / 380 columns plus the sidebar fix leave the centre cramped or over-wide depending on state. Fix: cap the reading width (~680) and centre it in the column.
34. [High] iPad Summary — The 3-column layout squeezes the chat: the title, composer pill, map and hourly forecast are clipped. RootView.swift:227-265 (fixed 320 / 380). Fix: collapse the sidebar when the inspector opens, or make the inspector an overlay below 1100pt.
35. [Med] iPad sheets — Clipped `.medium` form sheets with a pointless grabber. Settings/SettingsViews.swift:460, Multi/HandoffSheet.swift:83. Fix: `.presentationSizing(.page)` or `.form` with `.large`, and hide the drag indicator.
36. [Med] iPad top bar — The hamburger and title row do not realign with the chat column. RootView.swift:449-470. Fix: constrain the bar to the same max width as the content.
37. [Low] iPad — Sidebar hairline and inspector hairline have different vertical safe-area behaviour. RootView.swift:232-236, :251-255. Fix: share one divider view.

**TOP 10 visual fixes**
1. Add a top fade or opaque safe-area bar behind the top bar and status bar (items 1, 2).
2. Make the composer container solid, with glass only on its buttons (3).
3. Fix the model pill wrapping and the stray spinner (5).
4. Give the sidebar footer an opaque background and a measured bottom inset (13).
5. Unify the sheet close button and header (17, 18, 20, 31).
6. Fix the Compare agent chips: no mid-word wrap and a selected state (21, 22).
7. Make the top-bar buttons match in shape and size, and fix the "More options" label (10, 11).
8. Rework the iPad layout so the inspector and sidebar do not squeeze the chat (33, 34, 36).
9. Replace the clipped `.medium` detents with `.large` or proper sizing (19, 23, 35).
10. Render the artifact viewer in CI so it can be checked (32).

## Haiku: small details

Composer (ios/Linkup/UI/Composer/ComposerView.swift)

- [High] ComposerView.swift:436-441 — Model pill name and effort Text have no lineLimit or fixedSize, so "Medium" wraps to "Mediu/m" and "Opus 5.5" splits onto two lines (confirmed in USER-REAL-iphone-chat.jpg) — add `.lineLimit(1).fixedSize()` and drop the effort text before the name truncates.
- [High] ComposerView.swift:427-431 — UsageRingBadge (16pt ring) sits inside the pill and reads as a stray spinner when utilization is low (visible in USER-REAL-iphone-chat.jpg) — show usage only at high utilization, with a label, or move it to the Usage page.
- [Med] ComposerView.swift:446 — Pill is 44pt tall but its text is 15pt with no minimum width, so the pill shrinks unevenly against the 44pt circle buttons — give the pill a fixed min width and matching horizontal padding.
- [Med] ComposerView.swift:250-264 — Selected slash-command chip's xmark is a ~10pt glyph with no 44pt hit area — wrap it in a 44x44 contentShape.
- [Med] ComposerView.swift:270-276 — Placeholder "Ask anything — places, weather, recipes…" is long and wraps or truncates with lineLimit(1...8) on the field — shorten it or use `.lineLimit(1)` on the placeholder.
- [Med] ComposerView.swift:362-370 — File capsule name is `lineLimit(1)` with the default tail truncation, so extensions are lost — use `.truncationMode(.middle)` and cap width around 180pt.
- [Med] ComposerView.swift:339 and 358-363 — ProgressView spinners appear in upload thumbnails and file capsules (scaled 0.75), intentional but visually competing with the send button; keep only the overlay and drop the capsule spinner.
- [Med] ComposerView.swift:186-222 — Agent/Chat segmented buttons have 6pt vertical padding, so tap height is about 26pt — add `.frame(minHeight: 44)`.
- [Med] ComposerView.swift:412-420 — The "/" button uses `.system(size: 20, design: .rounded)` text while every other control uses SF Symbols, so the glyph sits visually off-center and off-weight — use an SF Symbol or match the baseline and weight of the mic icon.
- [Low] ComposerView.swift:452-461 and 479-511 — Icon weights differ: mic is medium 20, send is bold 19, waveform is semibold 20, stop is bold 16 — unify at one size and weight.
- [Low] ComposerView.swift:849-855 (model picker row) — Model description Text has no lineLimit, so long descriptions push rows tall — add `.lineLimit(2)`.
- [Low] ComposerView.swift:791-792 — "Offline" tag is 11pt in a row that also uses 14pt, so it looks like a footnote — raise to 12pt.

Top bar (ios/Linkup/UI/RootView.swift)

- [High] RootView.swift:548-557 — Session title and subtitle float over scrolled chat text with no scrim under the bar, so content collides with the title (visible in both screenshots) — add the same top gradient used for the pinned strip, behind topBarSection.
- [High] ChatView.swift:65 — Messages start at a fixed `.padding(.top, 70)` that ignores the connection pill (about 36pt extra) and the real bar height, so the first lines run under the bar — derive the top inset from the measured topBarSection height.
- [Med] RootView.swift:569-586 — Connection pill is about 24pt tall (12pt text, 6pt vertical padding) and is tappable to reconnect, which is below 44pt — give it `.frame(minHeight: 44)` or a larger hit area.
- [Med] RootView.swift:467-471 — Plus and ellipsis buttons have a 44x48 frame, but the glass capsule around them is only 88pt wide, so the title overlay can crowd the trailing capsule on narrow phones — measure the title frame against the trailing group.
- [Low] RootView.swift:549-554 — Title truncates to "Hey this is linkup my all in…" with no subtitle truncation hint — keep title lineLimit(1) and let subtitle shrink with minimumScaleFactor(0.8).

Chat (ios/Linkup/UI/Chat/ChatView.swift)

- [High] ChatView.swift:74-78 — Pinned strip uses a hard-coded `.padding(.top, 60)`, which overlaps the top bar on devices with a different safe area — use the measured bar height instead.
- [Med] ChatView.swift:235-238 — Pinned snippet is `prefix(24)` with no ellipsis, so it cuts mid-word with no "…" — append "…" when truncated.
- [Med] ChatView.swift:222-229 — Unpin xmark is a 14x14 target — give it a 44pt contentShape.
- [Med] ChatView.swift:105-115 — Scroll-to-bottom button is 36x36, below 44pt — make it 44x44.
- [Med] ChatView.swift:336-337 — Fallback greeting "Hello, night owl" appears between 21:00 and 05:00 and reads as a cutesy placeholder — use "Good evening" or a neutral line for all hours.
- [Low] ChatView.swift:267-274 — Greeting is centered between Spacers that ignore the top bar, so the optical center is off — add the bar height to the top padding.
- [Low] ChatView.swift:280-292 — Agent chip is 12pt with 5pt vertical padding, roughly 27pt tall — add minimum height 44 to the hit area.
- [Low] ChatView.swift:354-359 — Footnote is 13pt tertiary text at about 3.3:1 contrast, and the copy omits the "double-check responses" line that Claude uses — use secondaryText and match the Claude wording.

Assistant messages (ios/Linkup/UI/Chat/MessageViews.swift)

- [High] MessageViews.swift:336-366 — Copy, share, retry icons are 20pt with no frame, so tap targets are about 22pt, and the 22pt spacing is uneven next to the 24pt ellipsis — give each button a 44x44 frame and equal spacing.
- [High] MessageViews.swift:459-461 — Turn ellipsis is a 24x24 frame, far below 44pt — enlarge the frame and contentShape.
- [Med] MessageViews.swift:310-312 — Model name in the turn header is 12pt tertiary text, low contrast on the dark background — use secondaryText.
- [Med] MessageViews.swift:315-321 — "Pinned" badge is 10pt text with a 9pt icon, too small to read — raise to 11pt.
- [Med] MessageViews.swift:689-699 — Code-block copy icon is 11pt inside an unframed button (about 20pt tall) — make it a 44pt-tall hit area with a 13pt icon.
- [Med] MessageViews.swift:707 and 721 — Code header and body use two hard-coded blacks (#1A1A19 and #141413), which creates a visible seam, and neither is a Theme token — use one Theme token for the block.
- [Med] MessageViews.swift:779 — Table body cells are serif 15 while header cells are sans 14 and chat text is 17/18, so tables look smaller and mixed-family — use the chat text size and one family.
- [Med] MessageViews.swift:840-852 — List bullets are sans 15 and numbers sans 14 next to serif 17 body text, so markers sit off the baseline — align to the body font.
- [Low] MessageViews.swift:843 and 848 — Bullet column is 14pt wide and numbers are minWidth 20, so "10." items indent differently from "•" items — use a single marker width.
- [Low] MessageViews.swift:79-81 — Attachment chip background is `Color.white.opacity(0.1)`, off-palette — use Theme.hairline or Theme.elevated.
- [Low] MessageViews.swift:867-868 — Streaming caret is a "●" glyph at 11pt, which does not match the 17pt body line height — use a 2pt-wide bar or size it to the line.
- [Low] MessageViews.swift:697-699 — "Copy" and "Copied" have different widths, so the header jitters on tap — set a fixed minimum width.

Sidebar (ios/Linkup/UI/Sidebar/SidebarView.swift)

- [High] SidebarView.swift:557-563 — Running sessions show a ProgressView and a blue 8pt dot together, which is redundant and reads as a stray spinner — keep one indicator.
- [Med] SidebarView.swift:113-116 — Search toggle is 38x38, below 44pt — make it 44x44.
- [Med] SidebarView.swift:130-141 — Search field has no clear button, so users must delete text character by character — add an xmark clear.
- [Med] SidebarView.swift:130-131 and 681-682 — Search placeholder reads "Search sessions…" in one place and "Search PC sessions…" in the other, with 16pt text and a 15pt icon — share one SearchField component.
- [Low] SidebarView.swift:437-440 — Connection status footer is 12pt with lineLimit(1), so long server text truncates — allow two lines or shorten the copy.
- [Low] SidebarView.swift:507-525 — Swipe action buttons are 44x38, so their height differs from the 44pt standard — use 44x44.
- [Low] SidebarView.swift:833-856 — History row metadata line truncates folder names with no separation from the date — use middle truncation and keep the separators in one Text.
- [Low] SidebarView.swift:395-397 — "New session" label conflicts with the Claude app's "New chat" wording — match the Claude app.
- [Low] SidebarView.swift:299-302 — "No matching sessions" has no action to clear the search — add a "Clear search" button.

Screenshot notes: USER-REAL-iphone-chat.jpg shows the model pill wrap and the stray ring (first two composer items), the title overlapping streamed text (RootView item 1), and the top-inset problem (ChatView item 1). iphone-chat.png shows the scroll-to-bottom button overlapping the send button and the composer covering the currency card, with a spinner in the model pill from the usage ring.

## Haiku: animations

[High] ios/Linkup/UI/Composer/VoiceModeView.swift:137-138 - Voice orb scale jitters or keeps pulsing after phase changes. Cause: `scaleEffect` gets a per-frame `interactiveSpring` tied to audioLevel and a `repeatForever` tied to phase on the same property, so the repeat is not cleanly replaced. Fix: keep scale on audioLevel only and run the breathing pulse on a separate layer (phaseAnimator or TimelineView).

[High] ios/Linkup/UI/Chat/ChatView.swift:122-135 and 152-175 - Transcript stutters or jumps while tokens stream. Cause: each new item fires an animated `scrollTo(.smooth 0.15)`, while `scrollGluedToBottom` fires unanimated scrolls on every `lastSeq` change, so two drivers fight. Fix: when `transcript.isWorking`, let `scrollGluedToBottom` be the only scroller and drop the animation in the items.count branch.

[Med] ios/Linkup/UI/Activity/ActivityViews.swift:225-234 - Tool bursts make the activity list scroll jerkily. Cause: every activity event fires two `withAnimation(.smooth)` scrollTo calls (from `activity.count` and `activityLine`), which restart each other. Fix: use one trigger and an unanimated or throttled scroll.

[Med] ios/Linkup/UI/Activity/ActivityViews.swift:67-68 - The live activity line flickers or ghosts when updates arrive quickly. Cause: `.contentTransition(.opacity)` plus `.animation(.smooth)` on a high-frequency `activityLine`, so 0.5s crossfades overlap. Fix: animate only when the category changes, or use a short 0.15s fade.

[Med] ios/Linkup/UI/RootView.swift:412-413 - The edge-swipe drawer's corners and shadow pop on the first drag frame, and the whole app root is clipped and shadowed every frame while dragging. Cause: `cornerRadius` and `shadow` switch on `openProgress > 0` with no animation. Fix: derive radius and shadow continuously from `openProgress`.

[Med] ios/Linkup/UI/RootView.swift:268-269 - The iPad sidebar and inspector toggles hitch, and the transcript reflows on each frame for 0.35s. Cause: `.animation(value:)` on the whole three-column HStack animates the ChatView frame too. Fix: animate only the side columns (transition or offset) and keep the chat column width stable.

[Med] ios/Linkup/UI/RootView.swift:243-244 and 364-365 - Switching chats cuts hard, and scroll and transcript state reset. Cause: `.id(ui.currentSessionId ?? "new")` recreates ChatView with no transition. Fix: crossfade the id change with `.transition(.opacity)` and `withAnimation`, or keep one ChatView keyed by transcript.

[Med] ios/Linkup/UI/Sidebar/SidebarView.swift:244 and 280 - Pinning from the swipe or context menu makes the row jump between sections. Cause: `store.update(pinned:)` runs outside any `withAnimation`. Fix: wrap it in `withAnimation(.snappy)`. The delete paths at :520 and :613 have the same problem.

[Low] ios/Linkup/UI/Sidebar/SidebarView.swift:531 - Swipe action buttons pop in at -10pt during the drag. Cause: `.opacity(dragOffset < -10 ? 1 : 0)` is a binary step. Fix: map opacity continuously from dragOffset.

[Med] ios/Linkup/UI/Composer/ComposerView.swift:109-114, 254, 545 - The command chip pops in and out instead of animating. Cause: `selectedCommand` is set without `withAnimation`, so the `.scale` transition at :269 never plays. Fix: wrap these writes in `withAnimation(.snappy)`.

[Low] ios/Linkup/UI/Composer/ComposerView.swift:138-147 - The text field and attachment strip shift when a new chat starts. Cause: `.animation(.smooth, value: sessionId == nil)` is on the whole composer VStack. Fix: scope the animation to the segmented control.

[Med] ios/Linkup/UI/Cards/CardsPlaces.swift:1539-1545 - Scrolling through chats with World Clocks cards gets janky. Cause: the TimelineView(1s) wraps the whole card, so every clocks card rebuilds its body every second. Fix: put the TimelineView only around the time text, or precompute the zones.

[Low] ios/Linkup/UI/Cards/CardsPlaces.swift:1463-1470 - The countdown switches to "done" with a hard cut. Cause: the `remaining <= 0` branch has no transition. Fix: add `.transition(.scale.combined(with: .opacity))` inside a `withAnimation`.

[Low] ios/Linkup/UI/Cards/CardsData.swift:1090-1093 - A second CSV copy within 2s is hidden early by the first timer. Cause: an unstored `DispatchQueue.main.asyncAfter` that nothing cancels. Fix: store a Task and cancel it on each copy.

[Low] ios/Linkup/UI/Chat/MessageViews.swift:734-741 - The "Copied" state clears early on repeated taps. Cause: an unstored Task that is never cancelled. Fix: store and cancel it. The same pattern is at CardsDo.swift:826-829, 962-965 and 1395-1397.

[Low] ios/Linkup/UI/Chat/ChatView.swift:167-175 - The last token's auto-scroll can be dropped, leaving the chat a line short of the bottom until the next event. Cause: `autoScrollTask` is cleared only when the guard passes, so a stale task blocks new throttled scrolls. Fix: clear it on every path.

[Low] ios/Linkup/UI/Chat/ChatView.swift:92-101 - The scroll-to-bottom button threshold changes when a turn starts or ends. Cause: the threshold switches between 180 and 120 with `isWorking`. Fix: add hysteresis or keep one threshold.

[Low] ios/Linkup/UI/Chat/ChatView.swift:122-135 - A new assistant or tool item pops into the list. Cause: rows are inserted without a transition. Fix: add an opacity plus small-offset transition to new rows.

[Med] global (ios/Linkup, representative: ios/Linkup/UI/RootView.swift:268) - Reduce Motion is ignored everywhere. Cause: zero hits for `accessibilityReduceMotion` or `isReduceMotionEnabled`, while about 9 `repeatForever` pulses and about 150 spring animations run unconditionally. Fix: add a motion helper that checks `@Environment(\.accessibilityReduceMotion)` and returns nil or `.none` when it is on.

[Low] ios/Linkup/UI/Activity/ActivityViews.swift:571-575 - Tool icons stop pulsing or never start. Cause: the pulse starts only in `onAppear`, so rows that begin running later never pulse, and the opacity snaps back to 1 without animation when the tool finishes. This extends AUDIT item 33. Fix: drive it with `.symbolEffect(.pulse, isActive: isRunning)`.

[Low] ios/Linkup/UI/Artifacts/ArtifactViews.swift:907 - The shimmer loops forever and ignores Reduce Motion. Cause: `repeatForever` runs without a condition. Fix: gate it on loading state and Reduce Motion.

[Low] ios/Linkup/UI/Settings/SettingsViews.swift:70-76 - The copy icon swaps to a checkmark with no animation. Cause: `hasCopiedCommand` is set without `withAnimation`, and the Task is not cancelled. Fix: `withAnimation(.snappy)` plus `.contentTransition(.symbolEffect(.replace))`.

[Low] ios/Linkup/Core/Live/LiveManager.swift:41-47 - Not an animation issue, but the poll loop runs `poll()` every second for the app's lifetime. Cause: an unconditional 1s loop. Fix: back off, or poll only while Live Activities are active.

## Haiku: RTL / accessibility / text

Scope: text input/display, Arabic/Darija/French handling, speech, and accessibility in `ios/Linkup/UI`. Paths are under `ios/Linkup/`. Read-only; no files edited. Items already in tasks/AUDIT.md (dictation overwrite, audio session, voice-loop bugs, Dynamic Type, drawer offsets, tertiary contrast, caret reduce-motion) are left out.

RTL-MIXED-TEXT
1. [High] UI/Chat/MessageViews.swift:85 — user bubble `Text` has no direction or alignment; Arabic messages sit left-aligned inside a right-aligned bubble — per message, detect Arabic script and apply `.environment(\.layoutDirection, .rightToLeft)`.
2. [High] UI/Chat/MessageViews.swift:541,548,643-661,778,817 — assistant paragraphs, headings, table cells and blockquotes all inherit the LTR environment, so Arabic blocks are left-aligned — add a per-block direction helper (first strong character) and align to trailing/leading accordingly.
3. [Med] UI/Chat/MessageViews.swift:840-856 — list markers (•, 1.) are always on the left and nested indent is `.padding(.leading)`; RTL items need the marker on the right and indent on the trailing side — derive both from the item's direction.
4. [Med] UI/Chat/MessageViews.swift:811-813 — blockquote accent bar is fixed on the left edge — mirror the bar for RTL blocks.
5. [Med] UI/Chat/MessageViews.swift:753 — table `Grid(alignment: .leading)` left-aligns Arabic cells — align each cell by its own direction.
6. [Med] UI/Chat/MessageViews.swift:541-546 — the streaming caret sits after the text in an LTR HStack, so for RTL paragraphs it lands at the visual wrong end — put the caret inside the AttributedString, or flip the HStack for RTL blocks.
7. [Med] UI/Chat/MessageViews.swift:569 and whole file — there is no `layoutDirection` policy anywhere (grep finds none) and no localizations are declared, so direction is LTR only by accident — decide and document one policy and apply it at the root.
8. [Low] UI/Chat/MessageViews.swift:671-750 — code block text is always LTR but has no explicit `.leftToRight`, so Arabic inside code bidi-reorders — pin code to `.leftToRight` and isolate it.
9. [Med] UI/Composer/ComposerView.swift:272-276 — the vertical `TextField` has no explicit alignment or direction, so Arabic input alignment is left to chance — verify on device; if wrong, use a UITextView wrapper with natural alignment.
10. [Med] UI/Sidebar/SidebarView.swift:548-552 — session titles are left-aligned regardless of script, so Arabic titles look wrong in the row — align the title by its detected direction.
11. [Med] UI/Sidebar/SidebarView.swift:316-317 and 789-790 — search uses `localizedCaseInsensitiveContains`, which is diacritic-sensitive, so "مرحبا" does not match "مَرْحَبًا" — use `range(of:options:[.caseInsensitive,.diacriticInsensitive])` and also fold alef variants (أ/إ/آ→ا), ى→ي and ة→ه.
12. [Low] UI/Workspace/FileViewer.swift:175 — in-file search uses `.caseInsensitive` only, with the same diacritic problem — add `.diacriticInsensitive`.
13. [Low] UI/Chat/MarkdownParser.swift:272-274 — the ordered-list regex `\d` and `isNumber` keep Arabic-Indic digits, mixing numeral styles with the Western digits used elsewhere — pick one numeral policy.

SPEECH-LANGUAGE
14. [High] UI/Composer/VoiceModeView.swift:496-526 — `pickBestVoice` uses only the device locale, so an Arabic or French reply on an English device is read by an English voice (Arabic script becomes noise) — detect the language of each chunk (NaturalLanguage `NLLanguageRecognizer`) and pick a voice for that language (ar-SA for Arabic script, fr-FR for Latin Darija and French, en for English).
15. [High] UI/Composer/VoiceModeView.swift:498,503,511,519 — `Locale.current.identifier` returns "en_US" (underscore) while `AVSpeechSynthesisVoice.language` uses "en-US", so the exact-locale matches in steps 1, 3 and 5 never fire — use `Locale.current.identifier(.bcp47)`.
16. [High] UI/Composer/ComposerDictation.swift:18,72 — `SFSpeechRecognizer(locale: Locale.current)` is the only language, so Arabic, Darija and French speech on an English device is transcribed as English nonsense, and a device locale without a recognizer (e.g. ar_MA) always fails with the generic "not available right now" — add a dictation-language setting (en-US, fr-FR, ar-SA) with a sensible default and a clear error that names the locale.
17. [Med] UI/Composer/VoiceModeView.swift:446-452 — `pickBestVoice()` is called and `speechVoices()` re-queried for every chunk — choose and cache the voice per language once per session.
18. [Med] UI/Composer/VoiceModeView.swift:91-180 — there is no voice or language setting anywhere, so the user cannot fix a wrong voice — add a voice/language picker in Settings.
19. [Med] UI/Chat/MessageViews.swift:500; UI/Usage/UsageRing.swift:191-218; UI/Activity/ActivityViews.swift:344,352 — `String(format:)` always writes "." as the decimal separator and hard-codes "k", "M" and "$", so a French user sees "1.2k tokens" instead of "1,2 k" — use `FormatStyle` (`.number`, `.currency`) with `Locale.current`.
20. [Med] UI/Sidebar/SidebarView.swift:853 and UI/Composer/ComposerView.swift (cost and plural strings) — English-only plurals built with ternaries ("message"/"messages") — use `String(localized:)` with plural variants.
21. [Med] Global (no `*.xcstrings` or `.lproj` in the repo) — all roughly 750 UI strings are English literals, so nothing can be translated or switched to Arabic/French without touching every site — add `Localizable.xcstrings` and migrate user-visible strings progressively, starting with composer, sidebar and voice mode.
22. [Low] UI/Chat/ChatView.swift:327-335 — the greeting ("Good morning" and so on) is hard-coded English — move to the string catalog.
23. [Low] UI/Composer/VoiceModeView.swift:cleanTextForSpeech (about line 512) — list markers and numbered prefixes are read aloud, and the cleaner only removes Markdown symbols — strip list markers and also run `cleanTextForSpeech` before the Arabic/French check.

ACCESSIBILITY
24. [High] UI/Composer/ComposerView.swift:452-466 — the mic button has no `accessibilityLabel`, no value and no toggle state, so VoiceOver reads the symbol name and cannot tell whether dictation is on — add label "Dictate", `.accessibilityValue("Listening")` while active, and `.isToggle`.
25. [High] UI/Composer/ComposerView.swift:474-512 — the primary button is icon-only and changes meaning (Stop, Send, Voice mode) with no label on any state — add "Stop response", "Send message" and "Voice mode" labels.
26. [Med] UI/Composer/ComposerView.swift:385-404 — the plus `Menu` label is an unlabeled "plus" icon — add `.accessibilityLabel("Add attachment")`.
27. [Med] UI/Composer/ComposerView.swift:347,375 — attachment remove buttons (`xmark.circle.fill`) have no label — add "Remove \(name)".
28. [Med] UI/Composer/ComposerView.swift:257 — the slash-command clear button (`xmark`) is unlabeled — add "Clear command".
29. [Med] UI/Composer/ComposerView.swift:183-220 — the Agent/Chat segmented control has no `.isSelected` trait, so the current mode is conveyed by colour only — add `.accessibilityAddTraits(draftMode == "agent" ? .isSelected : [])` (and the same for chat).
30. [Med] UI/Composer/ComposerView.swift:745 — the model-picker sheet close button (`xmark`) is unlabeled — add "Close".
31. [Med] UI/Chat/ChatView.swift:109 — the scroll-to-bottom button (`arrow.down`) is unlabeled — add "Scroll to latest".
32. [Med] UI/Sidebar/SidebarView.swift:496-531 — the swipe Delete and Pin buttons stay in the accessibility tree at opacity 0, so VoiceOver announces them on every row — hide them until revealed, or expose them through `accessibilityAction(named:)`.
33. [Med] UI/Sidebar/SidebarView.swift:548-575 — the session row label is only the title, so the agent, running state (ProgressView) and unread state (colour-only dot) are not announced — combine them into one label, for example "Title, Claude, unread".
34. [Med] UI/Chat/MessageViews.swift:643-661 — `ChatHeadingView` has no `.isHeader` trait, so the VoiceOver heading rotor cannot jump between sections — add `.accessibilityAddTraits(.isHeader)`.
35. [Med] UI/Composer/VoiceModeView.swift:184-186, 203-207 — the live transcript and spoken reply change without announcements, and the phase (Listening/Thinking/Speaking) is not exposed — add `.updatesFrequently` and post an announcement on phase change.
36. [High] Global (grep: zero hits for accessibilityReduceMotion, accessibilityReduceTransparency, colorSchemeContrast, legibilityWeight, dynamicTypeSize across UI/) — the voice orb (VoiceModeView.swift:138), mic pulse (ComposerView.swift:456-462) and the working dots run `repeatForever` regardless of Reduce Motion — read `@Environment(\.accessibilityReduceMotion)` and gate the loops.
37. [Med] Global — no `colorSchemeContrast` branch, so hairlines (`Theme.hairline`) and the white-0.1 attachment capsule (MessageViews.swift user bubble area) stay faint under Increase Contrast — add a `.increased` branch in Theme that raises hairline and stroke opacity.
38. [Low] UI/Composer/ComposerView.swift:123-130 and UI/Chat/MessageViews.swift — the custom `Theme.surface`/`elevated` fills are opaque tints that ignore the system Reduce Transparency setting, so they do not match the glass beside them — read `accessibilityReduceTransparency` and use solid fills.

## Haiku: uncovered files

High and Med items first, then Low, grouped by area. Nothing was edited.

**Shell / Cards / Core (Swift)**
- [High] ios/Linkup/Core/Protocol/JSONValue.swift:54 — `var int` does `Int($0)` on any double, and `.double` (line 50) accepts strings, so `"NaN"`, `"inf"` or `"1e400"` from card fields trap. Fix: `guard n.isFinite, abs(n) < 9e15 else { return nil }`.
- [Med] ios/Linkup/Core/Protocol/JSONValue.swift:42 — `.string` on a number does `String(Int(n))`, which traps for |n| ≥ 2^63. Fix: format non-integers and huge values with `String(n)` or `%g`.
- [Med] ios/Linkup/UI/Multi/CompareView.swift:285 — `RichTextView` is rendered with no `.environment(\.cardActions)`, so poll, quiz and checklist taps in Compare silently do nothing. The default `CardActions.send` in ios/Linkup/UI/Cards/CardSupport.swift:6 is a no-op, which hides this. Fix: inject `CardActions` in CompareView and make the default fail loudly in debug.
- [Med] ios/Linkup/UI/Shell/DevServerPreview.swift:195-197 — `targetURL` embeds `?token=` in the URL the WKWebView loads, so the proxied dev page's JS can read the bridge token. Fix: send the token as a header or cookie, not in the URL.
- [Med] ios/Linkup/UI/Shell/DevServerPreview.swift:251-254 and 299-302 — "Open in Safari" opens `currentURL ?? targetURL`, which carries the token into Safari history and the clipboard. Fix: open a tokenless URL or drop the button.
- [Med] ios/Linkup/UI/Shell/DevServerPreview.swift:55-58 and 329-331 — Retry calls `webView.reload()`, which does nothing when the first navigation never committed, so the error screen cannot recover. Fix: keep the requested URL and call `load(URLRequest(...))` when `currentURL == nil`.
- [Med] ios/Linkup/UI/Shell/DevServerPreview.swift:85-90 — `makeUIView` writes `controller.errorMessage` (a @Published) during a view update, which triggers SwiftUI's publish-during-update warning. Fix: set it asynchronously or compute the error in the body.
- [Med] ios/Linkup/App/DebugLaunch.swift:120-121 — `apply()` writes `settings.serverURL` and `settings.token`, which persist to UserDefaults and Keychain via didSet. A `-LinkupScreen` launch on a real device therefore replaces the pairing with `example.ts.net` / `screenshot-mode`. Fix: keep fixture settings in memory only, or skip the didSet persistence when `DebugLaunch.screen != nil`.
- [Med] ios/Linkup/App/DebugLaunch.swift:151-158 — `loadFixture` ingests fixture sessions into the live SessionStore. Check whether `ingest` writes the on-disk EventCache; if it does, fixture sessions leak into real history. Fix: guard that path under DebugLaunch.
- [Med] ios/Linkup/UI/Composer/ComposerView.swift:629 — the camera capture is JPEG-encoded at full resolution on the main thread with no downscale, so multi-MB uploads and UI stalls. Fix: resize to about 2048 px and encode off the main thread.
- [Low] ios/Linkup/UI/Settings/UpdatesSection.swift:157,165,200 — `message` is set but never cleared, so the footer keeps "SideStore isn't installed" after later successes, and success gives no feedback. Fix: reset it at the start of each action and set it on success too.
- [Low] ios/Linkup/UI/Shell/UpdateBanner.swift:64-71 — the install button has no in-flight guard, so a double tap starts two installs and two fallbacks. Fix: a busy flag that disables the button.
- [Low] ios/Linkup/Core/Protocol/JSONValue.swift:67-76 — `JSONValue.from(Any)` is dead code. Its `as Bool` check before `NSNumber` would also map 0/1 to bool on Apple platforms if it were used. Fix: delete it.
- [Low] ios/Linkup/UI/Chat/PinnedStore.swift:244 — `init() {}` is redundant. Pins are keyed by session id in UserDefaults (line 287) and never cleared when a session is deleted, and they are device-local. Fix: clear the key on session delete.
- [Low] ios/Linkup/UI/Workspace/FileBrowserView.swift:84-94 — a search with no matches shows a blank list instead of a "no matches" state. Fix: `ContentUnavailableView.search` when `sortedEntries` is empty and the search is non-empty.
- [Low] ios/Linkup/UI/Workspace/FileBrowserView.swift:191-203 — a failed refresh with existing entries is silent, and `.task` and `.refreshable` can load concurrently. Fix: a non-blocking error banner and a single in-flight load.
- [Low] ios/Linkup/Core/Store/SessionStore+Extras.swift:194-196 and 214-221 — `runSchedule` and `compare` never ingest the returned sessions (unlike `sessionFrom` at line 232), so new sessions are missing until the next list push. Fix: route both through `ingest`.

**Bridge (Python)**
- [Med] bridge/linkup_bridge/history.py:74-75 and 85-86 — `p.get(...)` assumes every content element is a dict, so one string or null element fails the whole `events()` import (called at server.py:327). Fix: filter with `isinstance(p, dict)`.
- [Med] bridge/linkup_bridge/history.py:36 and 67 — a JSON line that parses to a non-dict makes `d.get` raise and aborts `list_sessions` or `events`. Fix: `if not isinstance(d, dict): continue`.
- [Med] bridge/linkup_bridge/history.py:26 and 52 — `os.path.getmtime` runs outside any try, so a transcript deleted between glob and sort fails the whole `history` op. Fix: stat inside a try and skip on OSError.
- [Med] bridge/linkup_bridge/history.py:60 with server.py:321-327 — the client-supplied `nativeId` goes straight into a glob pattern (`*`, `../`) and is stored as `native_id`, so a crafted id can read any `*.jsonl` under `~/.claude`. Fix: require a UUID regex in the import and `events` paths.
- [Med] bridge/linkup_bridge/server.py:321-327 — the import does check-then-create across an `await`, so two taps or clients importing the same transcript create two sessions. Fix: reserve the row or hold a per-nativeId asyncio lock across the await.
- [Med] bridge/linkup_bridge/workspace.py:628 — the proxy allowlist blocks only 8890 and the bridge port, so any other localhost service (including Hermes on 8642) is reachable from the Funnel with the token. Fix: allow only dev-server ports, or deny 8642 and other known services.
- [Low] bridge/linkup_bridge/server.py:328 — `store.append` runs per event on the event loop (not in `to_thread`), so importing a long transcript blocks every client. Fix: one batched write in a worker thread.
- [Low] bridge/linkup_bridge/history.py:26-45 — `list_sessions` re-parses up to 4000 lines of every file on each import-sheet open. Fix: cache titles keyed by (path, mtime).
- [Low] bridge/linkup_bridge/server.py:50-56 — `load_token` writes the file with default umask and chmods afterwards, and it returns an empty string if a previous write was interrupted. Fix: `os.open(..., O_CREAT|O_EXCL, 0o600)` and refuse an empty token.
- [Low] bridge/linkup_bridge/__main__.py:7 — `PUBLIC` defaults to a hard-coded tailnet hostname, so a different machine pairs with the wrong URL unless `LINKUP_PUBLIC_URL` is set. Fix: derive it from `tailscale status --json` or fail loudly.
- [Low] bridge/linkup_bridge/__main__.py:21 — `except ImportError: pass` silently drops the QR when qrcode is missing. Fix: print `pip install qrcode`.
- [Low] bridge/linkup_bridge/__main__.py:31-32 — any unknown subcommand (for example a `pari` typo or `--help`) falls through to `main()` and starts the server. Fix: print usage and exit 2 for unknown commands.

**Deploy (systemd / install.sh)**
- [Med] bridge/deploy/install.sh:10 — `systemctl restart` kills every running agent turn on each redeploy, with no warning. Fix: refuse or warn when sessions are running, or add `KillMode=process` and handle orphaned turns.
- [Low] bridge/deploy/linkup-bridge.service:3 — `After=network-online.target` has no matching `Wants=`, and there is no ordering on `tailscaled.service`, which Funnel needs. Fix: `Wants=network-online.target tailscaled.service`.
- [Low] bridge/deploy/linkup-bridge.service:13 — `Restart=always` with no start limit loops every 3 s forever if startup fails (for example, port 8890 busy). Fix: `StartLimitIntervalSec` and `StartLimitBurst`.
- [Low] bridge/deploy/linkup-bridge.service:9-10 — PATH and XDG are hard-coded for uid 1000 and do not include wherever `claude` or `agy` are installed (no `shutil.which` in the agents). Fix: verify with `which claude` and `which agy` as knight, and add their directories.
- [Low] bridge/deploy/install.sh:6 — `uv pip install aiohttp qrcode` is unpinned, so a breaking release changes production silently. Fix: a pinned requirements file.
- [Low] bridge/deploy/install.sh:12 — no post-deploy health check of the public Funnel URL. Fix: `curl -fsS` the public `/linkup` health route at the end.

**CI / scripts**
- [Med] .github/workflows/ios.yml:93 — `gh release create` fails when the release already exists (re-run or re-pushed tag), so the rerun cannot publish the IPA or apps.json. Fix: fall back to `gh release upload --clobber`.
- [Med] scripts/make-source.py:12 — `ENTITLEMENT_FILES = []` is empty, so the unsigned CI build yields no entitlements (codesign finds nothing). apps.json then omits `com.apple.security.application-groups` declared in ios/Linkup/Core/Live/Linkup.entitlements and the widget entitlements, which breaks the shared data for widgets and Live Activities. Fix: list both `.entitlements` paths; the script runs from repo root in CI.
- [Low] scripts/make-source.py:33 — only FileNotFoundError and InvalidFileException are caught, but `plistlib.loads` raises ValueError on junk output. Line 7 also says KnightMusic.app, a copy-paste error. Fix: broaden the except and fix the usage string.
- [Low] scripts/screens.sh:41 — the script's exit status is `ls`'s, so failed captures never fail CI, and each shot uses a fixed `sleep 9` with no foreground check. Fix: count the PNGs and `exit 1` below the expected total.

## Gemini: sidebar lifecycle

# Linkup Bug Hunt: Sidebar & Drawer Lifecycle Audit

Audited files: `ios/Linkup/UI/RootView.swift`, `ios/Linkup/UI/Sidebar/SidebarView.swift`, `ios/Linkup/App/LinkupApp.swift`, `ios/Linkup/UI/Chat/ChatView.swift`, `ios/Linkup/UI/Composer/ComposerView.swift`, `ios/Linkup/UI/Brand/AgentLogo.swift`.
Total new findings: 50 (14 High, 24 Medium, 12 Low). None duplicate `tasks/AUDIT.md`.

---

## 1. Layering, Framing & Safe Area

1. [High] `ios/Linkup/UI/RootView.swift:276-300, 410-413` — Sidebar header and "From your PC" bleed through behind status bar while drawer is closed — `iphoneDrawerLayout`'s `ZStack` expands to full screen via `Theme.background.ignoresSafeArea()`, centering child `mainLayer` vertically within safe area `proxy.size.height` with `.clipShape()`, leaving a ~56pt gap behind the status bar where background `SidebarView` shows through — Expand `mainLayer` to full screen bounds ignoring safe area, or avoid clipping `mainLayer` while constraining `SidebarView` behind it.
2. [High] `ios/Linkup/UI/RootView.swift:403, 417-438` and `ios/Linkup/UI/Chat/ChatView.swift:74-88` — Chat messages scroll directly behind floating top bar controls and title with no blur or gradient fade — `topBarSection` is a cluster of isolated glass pills floating over `ChatView` without an underlying material or gradient bar, and `ChatView` only applies a gradient when `!pinned.isEmpty` — Add a top material blur or `LinearGradient` fade behind `topBarSection` extending into the top safe area.
3. [Med] `ios/Linkup/UI/RootView.swift:437` — Top bar floating controls are pushed down too far from the status bar on notched devices — `topBarSection` adds `.padding(.top, max(safeAreaTop, 8))` on top of a `mainLayer` that is already inset by the safe area in `GeometryReader`, resulting in double safe area spacing — Align `mainLayer` to screen top with `.ignoresSafeArea(edges: .top)` and apply `safeAreaTop` only once to `topBarSection`.
4. [Med] `ios/Linkup/UI/RootView.swift:410-412` — Bottom edge of chat / composer is clipped above the home indicator, exposing underlying screen background — `mainLayer` is constrained to `proxy.size.height` (safe area height) and clipped by `clipShape`, leaving the ~34pt bottom safe area uncovered — Let `mainLayer` fill `maxHeight: .infinity` and handle bottom safe area via `safeAreaInset`.
5. [Med] `ios/Linkup/UI/Sidebar/SidebarView.swift:56-58, 408-423` — "New session" and Settings buttons in sidebar bottom overlay sit right over the home indicator on iPhone — `bottomOverlay` is placed as `.overlay(alignment: .bottom)` on `ScrollView` with only 12pt bottom padding, lacking safe area bottom insetting — Use `.safeAreaInset(edge: .bottom)` on `SidebarView`'s `ScrollView` or add `safeAreaInsets.bottom` to `bottomOverlay` padding.
6. [Med] `ios/Linkup/UI/Sidebar/SidebarView.swift:25-53` — Sidebar "Linkup" title and search button collide with Dynamic Island / status bar when scrolled up — `ScrollView` content in `SidebarView` has only 20pt top padding and lacks a top safe area inset or sticky header blur — Add `safeAreaInset(edge: .top)` or wrap header in a pinned section with safe area top padding.
7. [Low] `ios/Linkup/UI/RootView.swift:233-239` — Hairline divider between sidebar and chat on iPad extends past the sidebar header into the status bar area — Divider `Rectangle` has `.ignoresSafeArea(edges: .vertical)` while adjacent `SidebarView` does not ignore safe area, causing an uneven vertical extent — Align vertical safe area behavior between `SidebarView` and the hairline divider.
8. [Low] `ios/Linkup/UI/RootView.swift:412` — Main layer corners abruptly pop from square to 20pt rounded on the very first pixel of drawer drag — `cornerRadius: openProgress > 0 ? 20 : 0` uses a step boolean condition rather than interpolating proportionally with drag distance — Use `cornerRadius: 20 * openProgress`.
9. [Low] `ios/Linkup/UI/RootView.swift:413` — Main layer drawer shadow pops from transparent to full opacity instantly when drag starts — Shadow opacity is conditioned on `openProgress > 0 ? 0.35 : 0` rather than smooth interpolation — Use `color: Color.black.opacity(0.35 * openProgress)`.
10. [Low] `ios/Linkup/UI/RootView.swift:544-565` — Session title in top bar is visually off-center towards the right — Overlay title uses symmetric `.padding(.horizontal, 96)` despite the left hamburger button being 48pt wide and the right action cluster being 88pt wide — Inset title overlay with leading 56pt and trailing 96pt, or compute padding dynamically.

---

## 2. Gestures, Dragging & Hit-Testing Conflicts

11. [High] `ios/Linkup/UI/RootView.swift:406` — Edge swipe gesture gets destroyed mid-drag, freezing the drawer in a partially open state — `edgeSwipeZone` is wrapped in `if !ui.isSidebarOpen && openProgress == 0`; as soon as the user drags 1 pixel, `openProgress > 0` becomes true and SwiftUI tears down the view hosting the active gesture — Gate `edgeSwipeZone` on `!ui.isSidebarOpen && !isDragging` so the view survives throughout the active drag.
12. [Med] `ios/Linkup/UI/RootView.swift:600-604` — Reversing edge-swipe direction while dragging freezes the drawer offset — `onChanged` only updates `dragOffset` when `value.translation.width > 0`; dragging back left ignores changes and freezes `dragOffset` at its peak — Update `dragOffset = max(0, value.translation.width)` unconditionally once dragging has started.
13. [Med] `ios/Linkup/UI/RootView.swift:598-604` — Diagonal or vertical swipes near the left edge trigger accidental drawer dragging — `DragGesture` in `edgeSwipeZone` does not verify `abs(translation.width) > abs(translation.height)` before activating `isDragging` — Guard gesture activation with `abs(value.translation.width) > abs(value.translation.height)`.
14. [Med] `ios/Linkup/UI/RootView.swift:373-379, 380-400` — Tapping the scrim to close the drawer fails or requires multiple taps if finger moves slightly — Combining `.onTapGesture` and `.gesture(DragGesture)` on the scrim view causes `DragGesture` to swallow touches that have minor micro-movement — Use `TapGesture().simultaneously(with: DragGesture())` or close on drag end when total distance is under tap threshold.
15. [Med] `ios/Linkup/UI/RootView.swift:106-112` — Dragging left when sidebar is closed pushes chat off-screen to the left, showing a blank black void — `computeOffset` calculates `base = 0` and allows negative `total * 0.2`, translating `mainLayer` negatively without checking `isSidebarOpen` — Clamp `total` to `max(0, total)` when `!ui.isSidebarOpen`.
16. [Med] `ios/Linkup/UI/RootView.swift:393-398` — Flinging the drawer right to keep it open still closes it if past 35% threshold — `shouldClose` closes if `translation.width < -drawerWidth * 0.35` regardless of whether velocity/predicted translation is positive (towards reopening) — Factor velocity direction into `shouldClose` so an explicit flick right cancels closure.
17. [High] `ios/Linkup/UI/Sidebar/SidebarView.swift:577-597` — Swiping left to close the drawer accidentally triggers row swipe actions and gets stuck — `SidebarSessionRow` attaches an uncoordinated `DragGesture(minimumDistance: 20)` that intercepts leftward drags intended to close the sidebar — Disable row drag gestures when dragging the drawer, or replace custom drag with native `.swipeActions`.
18. [Med] `ios/Linkup/UI/Sidebar/SidebarView.swift:369-424` — Tapping top area of session rows near the bottom of the list is swallowed with no response — `bottomOverlay` has transparent top padding in its gradient background that intercepts hit testing over the underlying `ScrollView` content — Add `.allowsHitTesting(false)` to the background gradient and apply hit testing strictly to the button controls.
19. [Med] `ios/Linkup/UI/RootView.swift:593-596, ComposerView.swift:403-409` — Tapping the composer's `+` attachment button on the left fails or triggers edge swipe — `edgeSwipeZone` runs full height (`maxHeight: .infinity`), overlapping the 44pt attachment button positioned at the bottom-left of the screen — Restrict `edgeSwipeZone` frame between top bar and composer top.
20. [High] `ios/Linkup/UI/RootView.swift:278, SidebarView.swift:97-122` — In iPad Slide Over, user gets completely trapped in sidebar with no way to close it — In Slide Over (~320pt window), `drawerWidth` is hardcoded to 340pt, pushing the scrim entirely offscreen, and `SidebarView` contains zero close buttons — Cap `drawerWidth` to `proxy.size.width * 0.8` and add a close button to `SidebarView.headerSection`.

---

## 3. Animations, Transitions & Visual Jank

21. [High] `ios/Linkup/UI/RootView.swift:369-371` — Drawer scrim dimming vanishes abruptly in 1 frame instead of fading out when closing — Scrim is gated on `if openProgress > 0`; when `ui.isSidebarOpen` becomes false, `openProgress` immediately evaluates to 0 and drops the view with no transition — Keep scrim always present when animating and drive opacity via animatable property with `.animation(.smooth, value: openProgress)`.
22. [High] `ios/Linkup/UI/RootView.swift:412-413` — Main layer rounded corners and shadow snap flat in 1 frame at start of close animation — `cornerRadius` and `shadow` depend on `openProgress > 0`; evaluating to false at t=0 snaps them to 0 while `offset` is still animating over 0.35s — Bind corner radius and shadow opacity directly to continuous `openProgress` instead of boolean check.
23. [High] `ios/Linkup/UI/Sidebar/SidebarView.swift:239-242, 275-278` — Selecting a session in sidebar snaps drawer closed instantly with no sliding animation — `onSelect` sets `ui.isSidebarOpen = false` directly without wrapping in `withAnimation` — Wrap `ui.isSidebarOpen = false` in `withAnimation(.smooth(duration: 0.35))`.
24. [High] `ios/Linkup/UI/Sidebar/SidebarView.swift:390-405, UIState.swift:106-109` — Tapping "+ New session" in sidebar hard-snaps drawer shut without animation — `ui.newChat()` mutates `isSidebarOpen = false` without `withAnimation` — Wrap `isSidebarOpen = false` in `withAnimation(.smooth(duration: 0.35))` in `newChat()`.
25. [High] `ios/Linkup/UI/Sidebar/SidebarView.swift:165-169` — Tapping any agent row to start a session snaps drawer closed without animation — Agent row buttons invoke `ui.newChat()` without wrapping in `withAnimation` — Wrap agent row selection in `withAnimation(.smooth(duration: 0.35))`.
26. [Med] `ios/Linkup/UI/Sidebar/SidebarView.swift:32-34, 154` — Toggling search bar causes agent rows below to jump abruptly without animation — `searchBar` has a transition but enclosing `VStack` lacks `.animation(..., value: isSearching)`, causing layout recalculation jumps — Add `.animation(.snappy(duration: 0.25), value: isSearching)` to the containing VStack.
27. [Med] `ios/Linkup/UI/Sidebar/SidebarView.swift:225-259` — Pinning or unpinning a session causes it to violently teleport across sections with zero animation — `onTogglePin` modifies store sorting directly, triggering an un-animated re-render of `pinnedSessions` and `groupedRecents` — Wrap `store.update(session.id, pinned: ...)` with `withAnimation(.smooth)`.
28. [Med] `ios/Linkup/UI/Sidebar/SidebarView.swift:77-87` — Deleting a session causes the row to vanish instantly and adjacent rows to jump upward — `store.delete(session.id)` removes row from store with no view animation wrapper — Wrap deletion handler in `withAnimation(.smooth)`.
29. [Low] `ios/Linkup/UI/RootView.swift:268, 444` — Double animation conflict when toggling iPad sidebar from hamburger button — Hamburger button wraps toggle in explicit `withAnimation(.smooth(duration: 0.35))` while container layout also has `.animation(.smooth(duration: 0.35), value: isIPadSidebarVisible)` — Remove container `.animation` modifier and rely on explicit state animation.
30. [Low] `ios/Linkup/UI/RootView.swift:610` vs `ios/Linkup/UI/Sidebar/SidebarView.swift:106, 587` — Unnatural deceleration jerk when releasing edge-swipe gesture with high flick velocity — `onEnded` snaps to a fixed-duration `.smooth(duration: 0.35)` animation regardless of gesture velocity — Use `.interactiveSpring(response: 0.35, dampingFraction: 0.86)` with gesture velocity.

---

## 4. State Synchronization & Lifecycle Traps

31. [High] `ios/Linkup/UI/RootView.swift:443-450` — Opening drawer while keyboard is up leaves keyboard floating over and blocking sidebar — Opening sidebar does not resign first responder, keeping the software keyboard pinned on screen over `SidebarView`'s bottom controls — Dismiss keyboard (`UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder)...)`) when opening sidebar.
32. [High] `ios/Linkup/UI/Chat/ChatView.swift:136-138, 152-176` — Streaming tokens cause sidebar scrolling and search typing to hitch and lag — Background `ChatView` continues triggering `proxy.scrollTo` on every token arrival every 75ms while sidebar is open — Check `guard !ui.isSidebarOpen else { return }` in `scrollGluedToBottom`.
33. [Med] `ios/Linkup/UI/RootView.swift:19, UIState.swift:72-110` — iPad sidebar visibility state is decoupled from `UIState`, desynchronizing across views — `isIPadSidebarVisible` is stored as private `@State` in `RootView` while `isSidebarOpen` lives in `UIState` — Move `isIPadSidebarVisible` into `UIState` as a unified observable navigation property.
34. [High] `ios/Linkup/UI/RootView.swift:118-124` — Rotating iPhone Pro Max to landscape resets sidebar state, search text, and scroll offsets — `RootView` switches between `iphoneDrawerLayout` and `ipadThreeColumnLayout` on size class change, recreating all child views and discarding `@State` — Preserve view state across size class transitions or decouple state into `UIState`.
35. [Med] `ios/Linkup/UI/RootView.swift:322-329` — ⌘K shortcut leaves `dragOffset` dirty if pressed while dragging, causing drawer overshoot — `FocusSearch` keyboard handler sets `ui.isSidebarOpen = true` without resetting `dragOffset = 0` — Reset `dragOffset = 0` whenever `isSidebarOpen` is set programmatically.
36. [Med] `ios/Linkup/UI/RootView.swift:339-348` — ⌘[ toggle shortcut leaves `dragOffset` in dirty state if toggled during drag interaction — `Toggle Sidebar` keyboard shortcut toggles boolean without clearing `dragOffset` — Explicitly set `dragOffset = 0` inside `Toggle Sidebar` shortcut handler.
37. [Med] `ios/Linkup/Core/Store/SessionStore.swift:131, SidebarView.swift:560-564` — Blue unread dot remains on session row in sidebar even after user opens and views it — `SessionStore.open()` sends `"read"` to server but fails to update `unread = 0` locally on the cached session object — Set `session.unread = 0` locally in `SessionStore.open()` and notify observers.
38. [Med] `ios/Linkup/UI/Sidebar/SidebarView.swift:805-820` — Importing a PC session while a draft is in progress overwrites draft with no confirmation — `importSession` switches `currentSessionId` immediately without checking for unsaved composer draft text — Prompt user to discard draft or save draft per-session before switching on import.
39. [Med] `ios/Linkup/UI/Sidebar/SidebarView.swift:25-53, 160-219` — Top agent/tool rows remain visible during search, pushing search results off-screen under keyboard — `agentRowsSection` is unconditionally rendered above `sessionsSection` even when `isSearching` is active with an open keyboard — Hide or collapse `agentRowsSection` when `isSearching` is true or search query is non-empty.
40. [Med] `ios/Linkup/UI/Sidebar/SidebarView.swift:105-121, 130-135` — Tapping search icon shows search bar but fails to focus it or open keyboard — `TextField` has no `@FocusState` binding triggered by `isSearching.toggle()`, requiring a redundant second tap — Add `@FocusState private var isSearchFocused: Bool` and set `isSearchFocused = true` on search button tap.
41. [Low] `ios/Linkup/UI/Sidebar/SidebarView.swift:165-169` — Tapping unavailable agent row silently starts a chat that will fail to connect — Agent buttons are not disabled when `!isAvailable` and provide no error feedback on tap — Disable button or show toast when attempting to start a session with an unavailable agent.
42. [Low] `ios/Linkup/UI/Sidebar/SidebarView.swift:427-431` — Tapping offline connection footer while already reconnecting queues duplicate reconnection attempts — `connectionFooter` checks `client.state != .connected && client.state != .connecting`, but rapid double taps before state flips dispatch multiple connect calls — Debounce tap handler or gate on a local connecting flag.

---

## 5. Accessibility & VoiceOver

43. [High] `ios/Linkup/UI/RootView.swift:357-414` — VoiceOver reads and interacts with background chat messages and controls while drawer is open — `mainLayer` lacks `.accessibilityHidden(ui.isSidebarOpen || openProgress > 0)`, allowing VoiceOver cursor to traverse behind the scrim — Apply `.accessibilityHidden(ui.isSidebarOpen || openProgress > 0)` to `mainLayer`.
44. [High] `ios/Linkup/UI/Sidebar/SidebarView.swift:531` — Hidden swipe-reveal Delete buttons are read by VoiceOver on every row, risking accidental deletion — Swipe action buttons use `.opacity(dragOffset < -10 ? 1 : 0)` without `.accessibilityHidden(...)`, exposing inactive buttons to VoiceOver navigation — Add `.accessibilityHidden(!isRevealed)` to the trailing swipe button HStack.
45. [Med] `ios/Linkup/UI/RootView.swift:370-401` — VoiceOver users have no accessible way to close the open drawer on iPhone — Scrim view has `.onTapGesture` but lacks `.accessibilityLabel("Dismiss sidebar")` and `.accessibilityAddTraits(.isButton)` — Add `.accessibilityLabel("Dismiss sidebar")` and button traits to the scrim.
46. [Med] `ios/Linkup/UI/Sidebar/SidebarView.swift:569-573` — VoiceOver does not announce which session is currently active/selected — `SidebarSessionRow` styles selection visually via `Theme.elevated` but does not add `.accessibilityAddTraits(.isSelected)` — Add `.accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)`.
47. [Med] `ios/Linkup/UI/Sidebar/SidebarView.swift:560-564` — Unread status dot on session row is completely invisible to VoiceOver — `Circle()` has no accessibility label or value, omitting unread state from accessibility announcement — Add `.accessibilityValue("Unread messages")` or append to session row accessibility label.
48. [Low] `ios/Linkup/UI/Sidebar/SidebarView.swift:25-93` — Two-finger scrub or hardware Escape key does not dismiss sidebar on iPad / iPhone — `SidebarView` lacks `.accessibilityAction(.escape)` to handle standard modal dismissal gestures — Add `.accessibilityAction(.escape) { ui.isSidebarOpen = false }`.
49. [Low] `ios/Linkup/UI/RootView.swift:621-643` — In-app toasts appearing while sidebar is open are never announced to VoiceOver — `toastView` renders as a visual overlay without posting a `UIAccessibility.announcementNotification` — Post `UIAccessibility.post(notification: .announcement, argument: toast)` when `ui.toast` changes.
50. [Low] `ios/Linkup/UI/Sidebar/SidebarView.swift:830-874` — PC history session row reads literal punctuation glyphs ("dot") to VoiceOver users — `SidebarHistoryItemRow` includes literal `"·"` Text views in its HStack without combining into an accessible label — Provide a unified `.accessibilityLabel` combining title, directory, and relative date.

## Gemini: chat switching

# Linkup Bug Audit: Chat Switching, New Chats & Session Navigation

This audit focuses on switching chat to chat, creating new chats, navigation into sessions (sidebar, top bar, deep links, forking, handoff, compare, running now, schedules, projects), session deletion, scroll position handling, inspector/composer state leakage, double subscribes, and race conditions during streaming.

All findings are NEW and verified against the current codebase (`tasks/AUDIT.md` excluded).

---

## 1. Navigation & Transition Flow (Sidebar, Top Bar, Drawers, Gestures)

- [High] ios/Linkup/UI/RootView.swift:287-292 — Sidebar header "From your PC" bleeds through behind the status bar and dynamic island while the drawer is closed — in `iphoneDrawerLayout`, `SidebarView()` sits at x=0 with opacity 1.0 ignoring safe area, while `mainLayer` is constrained to `proxy.size.height` (excluding safe area top), leaving the status bar unpainted by chat and exposing the sidebar underneath — set `SidebarView().opacity(openProgress > 0 ? 1 : 0)` or gate on `ui.isSidebarOpen || dragOffset > 0`, and ensure `mainLayer` covers safe area.
- [High] ios/Linkup/UI/RootView.swift:418-438 — Chat message bubbles scroll directly underneath floating top bar controls and title with no blur or fade — `topBarSection` is an ungrounded floating bar with transparent negative space between controls and no background material or gradient mask on the top of `ScrollView` — add a `.background(.ultraThinMaterial)` or gradient fade across the top bar safe area.
- [High] ios/Linkup/UI/Sidebar/SidebarView.swift:239-242 — Tapping a session row in the sidebar snaps the drawer shut with zero animation — `onSelect` sets `ui.isSidebarOpen = false` without `withAnimation`, causing `RootView.computeOffset` to jump from `drawerWidth` to 0 instantaneously — wrap `ui.isSidebarOpen = false` in `withAnimation(.smooth(duration: 0.35))`.
- [Med] ios/Linkup/UI/Sidebar/SidebarView.swift:390-405 — Tapping "+ New session" in the sidebar snaps the drawer shut with no slide animation — `newChat()` sets `isSidebarOpen = false` without an animation block — wrap `ui.newChat()` in `withAnimation(.smooth(duration: 0.35))` or animate `isSidebarOpen` inside `newChat`.
- [Med] ios/Linkup/UI/Sidebar/SidebarView.swift:165-169 — Tapping an agent row (Claude Code, Antigravity, Hermes) in the sidebar drawer snaps it closed instantly — `ui.newChat()` is called directly without `withAnimation` — wrap in `withAnimation(.smooth(duration: 0.35))`.
- [Med] ios/Linkup/UI/Sidebar/SidebarView.swift:239-242 — Tapping the currently open session in the sidebar fails to clear its unread marker or re-scroll to bottom — `onSelect` sets `ui.currentSessionId = session.id`, which is a no-op when `currentSessionId` already equals `session.id`, so `ChatView.task(id: sessionId)` never fires and `store.open` is never invoked — if `ui.currentSessionId == session.id`, explicitly call `store.open(session.id)` and scroll to bottom.
- [Med] ios/Linkup/UI/Sidebar/SidebarView.swift:310-319 — Reopening the sidebar drawer after selecting a search result leaves the list trapped in search mode — `onSelect` sets `currentSessionId` and closes the drawer, but never resets `isSearching = false` or clears `searchText` — reset `isSearching = false` and `searchText = ""` on session selection.
- [Med] ios/Linkup/UI/Sidebar/SidebarView.swift:33-35 — Tapping the search icon in the sidebar header causes the entire session list to violently jump down by ~54pt — inserting `searchBar` into the vertical `VStack` pushes all agent rows and recent sessions downward without layout reservation — reserve header height or overlay the search bar.
- [Low] ios/Linkup/UI/RootView.swift:465-476 — Tapping the top bar "plus.bubble.fill" button while already on the new-chat screen provides zero visual or haptic feedback — `newChat()` sets `currentSessionId = nil`, but since it is already nil, SwiftUI performs no state update or composer draft reset — trigger a light haptic generator and clear composer text when `currentSessionId` is already nil.

---

## 2. View Identity & Greeting / Empty State Flicker

- [High] ios/Linkup/UI/Chat/ChatView.swift:16-22 — Composer disappears and recreates, dropping keyboard focus and draft text, when the first message arrives — `ChatView` switches from `greetingView` to `sessionView` when `transcript.items.isEmpty` becomes false; because both views declare separate `ComposerView` instances in different hierarchy positions, SwiftUI destroys and reconstructs the composer — keep a single stable `ComposerView` in `.safeAreaInset(edge: .bottom)` on the outer container regardless of item count.
- [High] ios/Linkup/UI/Composer/VoiceModeView.swift:306-319 — Voice Mode dismisses itself automatically after the user speaks the first sentence in a new chat — speaking creates the session and sets `ui.currentSessionId = s.id`, which causes `RootView` to replace `ChatView(id: "new")`, destroying the presenting `ComposerView` and tearing down the `.fullScreenCover` — present `VoiceModeView` from `RootView` or avoid changing `.id` on the parent view during voice mode.
- [High] ios/Linkup/UI/Chat/ChatView.swift:18-24 — Starting a new chat causes a double flicker from greeting to greeting to conversation — creating a session sets `ui.currentSessionId = s.id`, which immediately re-renders `ChatView` with an empty transcript, displaying `greetingView` a second time until the bridge echoes the `user` event and flips to `sessionView` — show a loading or optimistic message bubble instead of reverting to the greeting view once a session ID is assigned.
- [Med] ios/Linkup/UI/Chat/ChatView.swift:17-20 — Tapping a newly created or imported session in the sidebar displays the "Hello, night owl" greeting screen — empty sessions render `greetingView(sessionId: id)` identically to the new-chat screen, confusing users as to whether they successfully opened their session — render an empty session state showing the agent and project rather than the global greeting.
- [Med] ios/Linkup/UI/Chat/ChatView.swift:327-339 — Greeting view time-of-day greeting does not react to system time changes — `greetingText` calculates the greeting from `Calendar.current.component(.hour, from: Date())` only when evaluated, with no timer or scene phase invalidation — update greeting text on `scenePhase == .active` or using a timeline.
- [Low] ios/Linkup/UI/Chat/ChatView.swift:341-349 — Agent greeting chip flashes Claude Code's name and asterisk icon when opening an Antigravity or Hermes session — `agentTitle` and `agentSymbol` fall back to `ui.draftAgent` while `store.session($0)` has not resolved in memory — show a neutral placeholder icon until the session model is resolved.

---

## 3. Scroll Anchoring, Auto-Scroll & Position Tracking

- [High] ios/Linkup/UI/Chat/ChatView.swift:101-121 — Floating "arrow.down" jump-to-bottom button is hidden or covered by ComposerView — `.overlay(alignment: .bottom)` on `ScrollView` has `.padding(.bottom, 12)`, which positions the circle button 12pt above the screen bottom before `.safeAreaInset(edge: .bottom)` is factored in, placing it behind the 80-120pt composer — move the overlay modifier after `.safeAreaInset(edge: .bottom)` or add bottom padding matching the composer height.
- [High] ios/Linkup/UI/Chat/ChatView.swift:89-99 — Initial load of long conversations falsely triggers "user scrolled up" and displays the jump button — lazy text blocks and remote images have not completed layout passes on the first frame, causing `distanceFromBottom` to briefly exceed 120pt and setting `isUserScrolledUp = true` — gate `onScrollGeometryChange` until the view has completed its initial appearance and scroll positioning.
- [High] ios/Linkup/UI/Chat/ChatView.swift:136-138 — Switching back to a session that received background events does not scroll down to show the new messages — `scrollGluedToBottom` aborts with `guard transcript.isWorking`, so catch-up events that arrive for finished turns increment `lastSeq` but never scroll the view — scroll to `"chat_bottom"` on session open when catch-up events are ingested.
- [Med] ios/Linkup/UI/Chat/ChatView.swift:65, 74-88 — Switching between sessions with and without pinned turns causes a vertical scroll jump — `LazyVStack` top padding abruptly flips between 70pt and 12pt while `pinnedStrip` inserts a ~100pt safe area inset — maintain a consistent top inset or animate the safe area transition smoothly.
- [Med] ios/Linkup/UI/Chat/ChatView.swift:9 — Switching away from a session and back loses the user's scroll position and forces a jump to bottom — `isUserScrolledUp` is a local `@State` reset to `false` when `ChatView` is rebuilt via `.id(ui.currentSessionId ?? "new")` — persist scroll offsets or `isUserScrolledUp` keyed by session ID in `UIState`.
- [Med] ios/Linkup/UI/Chat/ChatView.swift:207-210 — Tapping a pinned turn chip in the pinned strip silently fails to scroll in long conversations — in `LazyVStack`, off-screen turns that have not been rendered do not exist in the view hierarchy, so `proxy.scrollTo(turn.id)` fails — render a target anchor or estimate offset before issuing `scrollTo`.
- [Low] ios/Linkup/UI/Chat/ChatView.swift:160-175 — Detached `autoScrollTask` can fire after session switch and target a destroyed view proxy — `autoScrollTask` captures `proxy` across a `Task.sleep` without checking if `sessionId` changed — verify `Task.isCancelled` and check session identity before calling `proxy.scrollTo`.

---

## 4. Title, Subtitle, Model Picker & Stale Header Metadata

- [High] ios/Linkup/UI/Composer/ComposerView.swift:777-783 — Agent switcher buttons in ModelPickerSheet silently do nothing when opened from an existing session — the buttons (Claude, Antigravity, Hermes) render with interactive glass styling, but the action is guarded by `if sessionId == nil` with no disabled opacity or explanation — disable the buttons with `opacity(0.4)` and a tooltip explaining that agent changes require Handoff.
- [High] ios/Linkup/UI/RootView.swift:545-565 — Top bar title and model selector are completely missing on the new chat screen — the header title overlay is guarded by `if let session = currentSession`, rendering nothing when `currentSessionId == nil` — show a "New Chat" title with draft model selector when `currentSession == nil`.
- [Med] ios/Linkup/UI/Composer/ComposerView.swift:840-845 — Selecting a new model for an active session does not update the checkmark in ModelPickerSheet — `store.update()` sends a message to the bridge but does not update `session.model` locally, leaving the old model checked until the server pushes an update — update `session.model` optimistically in `SessionStore.update()`.
- [Med] ios/Linkup/UI/Composer/ComposerView.swift:81-102 — Antigravity and Hermes sessions display an invalid "High" effort badge in the model pill — `modelPillText` reads global `ui.draftEffort` whenever `s.effort` is nil, displaying effort levels on models that do not support them — check `model?.efforts?.isEmpty == false` before displaying effort.
- [Med] ios/Linkup/UI/Sidebar/SidebarView.swift:166-168 — Tapping an agent in the sidebar resets `draftModel` to nil instead of remembering the agent's last-used model — `ui.draftModel = nil` is hard-coded on agent switch — store `draftModel` per agent in UserDefaults (`draftModel_claude`, `draftModel_agy`).
- [Med] ios/Linkup/UI/Chat/ChatView.swift:352-354 — Footnote displays "Claude Code can make mistakes" when opening Antigravity or Hermes sessions — `footnoteView` falls back to `ui.draftAgent` when `store.session(sessionId)` is not yet cached — read `store.transcript(for: sessionId).items` or wait for session resolution.
- [Low] ios/Linkup/UI/RootView.swift:493-499 — Renaming an untitled session permanently destroys smart auto-titling by pre-filling "New session" — `renameTitle` defaults to `session.displayTitle` (`"New session"`), sending `"New session"` as the explicit title and blocking bridge auto-titling — leave text field empty when `session.title == nil`.
- [Low] ios/Linkup/UI/RootView.swift:501-504 — Pin/Unpin menu action in top bar gives no haptic or visual feedback — `store.update()` has no optimistic mutation and no haptic feedback generator — add `UIImpactFeedbackGenerator(style: .medium).impactOccurred()` and toggle `session.pinned` optimistically.

---

## 5. Inspector, Artifact & Summary State Leaks Across Chats

- [High] ios/Linkup/UI/Shell/InspectorView.swift:16-22 — iPad inspector panel continues showing previous chat's turn summary or artifact after switching sessions — `ui.summaryTurn` and `ui.openArtifact` are stored on `UIState` and are never cleared when `ui.currentSessionId` changes or when `newChat()` is called — clear `ui.summaryTurn = nil` and `ui.openArtifact = nil` on session switch unless inspecting a shared file.
- [High] ios/Linkup/UI/RootView.swift:181-186 — Deleting a session leaves its summary timeline and artifacts open in the iPad inspector — `store.delete(id)` deletes data but leaves `ui.summaryTurn` and `ui.openArtifact` populated, referencing deleted records — clear `summaryTurn` and `openArtifact` inside `store.delete()` if they belong to the deleted session.
- [Med] ios/Linkup/UI/RootView.swift:26-37 — Rotating iPhone Max to landscape permanently dismisses SummarySheet without restoring it in the inspector — `summaryTurnBinding.get` returns `nil` whenever `horizontalSizeClass == .regular`, causing SwiftUI to dismiss the sheet, but does not transition the state into the iPad inspector column — unify presentation state under an active inspector router.
- [Low] ios/Linkup/UI/Shell/InspectorView.swift:30-44 — Inspector close button uses a transparent 48pt tap target overlay that can intercept underlying header buttons — a clear rectangle is layered over `SummarySheet` top-left to trigger dismissal — embed an explicit dismissal button in the inspector header bar itself.

---

## 6. Subscription Lifecycle, Double Subscribe & Network Races

- [High] ios/Linkup/Core/Store/SessionStore+Extras.swift:233 & ios/Linkup/UI/Chat/ChatView.swift:31-33 — Every forked, handed-off, and imported session sends two concurrent subscribe requests to the bridge — `sessionFrom` calls `open(s.id)` and setting `ui.currentSessionId` immediately triggers `ChatView.task` calling `open(s.id)` again — remove the redundant `open()` call in `sessionFrom` and `importHistory`, letting `ChatView.task` be the single subscriber.
- [High] ios/Linkup/UI/Composer/ComposerView.swift:570-572, 583-585 — Creating a new chat from the composer sends three subscribe requests in rapid succession — `createChat` calls `open()`, line 572 calls `open()`, and `ChatView.task` calls `open()` — eliminate manual `open()` calls in `sendMessage()`.
- [High] ios/Linkup/Core/Store/SessionStore.swift:128-132 — Inactive sessions are never unsubscribed when switching chats, saturating WebSocket bandwidth — neither `ChatView` nor `SessionStore` sends `unsubscribe` (supported at `server.py:313`), so all background sessions continue streaming live tokens — send `unsubscribe` for the previous session when `currentSessionId` changes.
- [High] ios/Linkup/Core/Store/SessionStore.swift:55-59 — Replaying catch-up events during session switch locks the main actor with hundreds of layout updates — each WebSocket event frame triggers an independent `@MainActor` dispatch and `@Observable` mutation — batch replayed frames or apply events to `Transcript` before publishing view invalidation.
- [Med] ios/Linkup/Core/Store/SessionStore.swift:38-42 — Cold launch reconnect always sends an empty resume points dictionary — `resumePoints()` only checks the in-memory `transcripts` map which starts empty, sending `"since": {}` in `hello` and dropping background events — populate `resumePoints()` from `EventCache` on launch.
- [Med] ios/Linkup/Core/Store/SessionStore.swift:128-132 — Switching sessions while offline silently drops subscription catch-up and leaves unread badges stuck — `client.post` silently returns when disconnected, with no retry or outbox queue — queue pending `subscribe` and `read` ops and flush upon reconnection.
- [Low] ios/Linkup/Core/Store/Transcript.swift:38, 47 — Replayed user events with `seq == 0` collide with ID `"u0"`, breaking SwiftUI list rendering — `items.append` creates `UserMessage(id: "u\(e.seq)")`, causing multiple `"u0"` items in `ForEach` — generate unique IDs or fallback to timestamp-based IDs.

---

## 7. Composer & Voice State Leaking Across Sessions

- [High] ios/Linkup/UI/Composer/ComposerView.swift:548-550, 589-591 — Composer input is wiped before session creation completes, losing the message if creation fails — `text = ""` and `attachments = []` are cleared synchronously before `store.create()` completes; network failure toasts an error with no way to recover text — keep draft text until `create()` and `send()` succeed.
- [Med] ios/Linkup/UI/Composer/ComposerView.swift:120-122 — Agent / Chat mode segmented control disappears after the first message and cannot be changed — `chatModeSegmentedControl` is wrapped in `if sessionId == nil`, disappearing as soon as a session is created — display the mode indicator in session settings or keep in composer header.
- [Med] ios/Linkup/UI/Composer/ComposerView.swift:248-261 — Active slash command chip is discarded when switching sessions — `selectedCommand` is stored in `@State` and is wiped when `ComposerView` is recreated by `.id(...)` — persist active command token in per-session draft state.
- [Med] ios/Linkup/UI/Composer/ComposerView.swift:154-162 — Asynchronous photo picker loading discards attachments if the user switches chats while images load — `item.loadTransferable` captures a `@State` mutator on a view struct that gets deallocated on session switch — route transferable loading through an app-scoped or store-scoped model.
- [Low] ios/Linkup/UI/Composer/ComposerView.swift:176-178 — Dictating in one session loses all spoken text if the user switches chats before sending — `onDisappear` calls `dictation.stop()` but doesn't persist the combined base and spoken text — flush spoken text to a persistent draft on view disappear.

---

## 8. Multi-Agent Switching (Fork, Handoff, Compare, Running Now, Schedules)

- [High] bridge/linkup_bridge/server.py:401 & ios/Linkup/Core/Store/Transcript.swift:135 — Navigating into a handoff session displays a completely blank new chat screen — the bridge emits `notice: Context attached`, but `Transcript.swift` only appends notices to existing assistant turns; in a new session there are no turns, so the event is dropped and `items.isEmpty` stays true — allow top-level `notice` items in `TranscriptItem`.
- [High] bridge/linkup_bridge/server.py:387-389 & ios/Linkup/Core/Store/Transcript.swift:225 — Forking a streaming session produces a zombie session permanently stuck in "Working..." — events copied to the new session include `turn.start` without a closing `turn.end`, permanently locking `isWorking == true` on the forked session — emit `turn.end` (interrupted) on unfinalized turns when copying events.
- [High] ios/Linkup/UI/Multi/CompareView.swift:212-215 — Tapping "Open" on a compared session traps the user inside CompareSheet — `dismiss()` only pops the `CompareView` off `CompareSheet`'s `NavigationStack`, leaving `ui.isShowingCompare == true` — set `ui.isShowingCompare = false` directly before dismissing.
- [High] ios/Linkup/UI/Schedules/SchedulesView.swift:339-342 — Tapping "Run now" on a schedule switches sessions underneath but does not dismiss the schedules sheet — `ui.currentSessionId = session.id` is set without calling `dismiss()`, leaving `SchedulesView` covering the active chat — call `dismiss()` after setting `currentSessionId`.
- [Med] ios/Linkup/UI/Multi/RunningNowView.swift:288-291 — Tapping a running session card opens the session but leaves the sidebar drawer open — `openSession()` dismisses the modal sheet but leaves `ui.isSidebarOpen == true` — set `ui.isSidebarOpen = false` in `openSession()`.
- [Med] ios/Linkup/UI/Multi/RunningNowView.swift:173-198 — Tapping the body of a running session card does nothing; only the small top-left title opens the chat — only the header HStack is enclosed in a `Button`, while the activity rows and timers ignore taps — expand the `Button` hit target to cover the entire card.
- [Med] ios/Linkup/UI/Workspace/ProjectDetailView.swift:42-45 — Tapping "New session here" pops to ProjectsView instead of opening chat — `dismiss()` is called inside a pushed navigation view, popping back to the project list rather than dismissing the sheet — dismiss the root `ProjectsView` sheet when creating a new session.
- [Low] ios/Linkup/UI/Multi/CompareView.swift:41-48, 60-69 — Header has redundant back and close buttons that perform the exact same navigation pop — both `chevron.left` and `xmark` call `dismiss()`, popping to the same configuration screen — replace `xmark` with a root dismissal action that closes the entire compare sheet.

---

## 9. Session Deletion & Orphaned State

- [High] ios/Linkup/Core/Live/LiveManager.swift:150-175 — Deleting a currently running session leaves its Dynamic Island / Lock Screen Live Activity active indefinitely — `LiveManager` only ends activities when `transcript.liveTurn == nil`; deleting the session skips normal completion and leaves the activity tracking the deleted ID — explicitly terminate `activeActivities[sid]` when a session is deleted.
- [Med] ios/Linkup/Core/Store/SessionStore.swift:55-58, 96 — Late-arriving bridge events for a deleted session recreate orphaned `.jsonl` files on disk — `removeLocal(sid)` deletes the cache file, but subsequent events (such as `turn.end` on process exit) call `cache.append(raw, to: sid)`, creating an orphaned file — track recently deleted session IDs and drop incoming events for them.
- [Med] ios/Linkup/UI/Sidebar/SidebarView.swift:262-295 — Deleting the only session in a date bucket causes an un-animated list collapse that jumps other rows — removing a session from `groupedRecents` drops the entire section header instantaneously — wrap recent session updates in `withAnimation(.snappy)`.
- [Low] ios/Linkup/App/LinkupApp.swift:62-67 & ios/LinkupWidgets/LinkupLiveActivity.swift:8 — Tapping a Live Activity from the lock screen or Dynamic Island opens the app but fails to navigate to the running session — `LinkupLiveActivity` omits `.widgetURL(URL(string: "linkup://session/\(sessionId)"))` and `LinkupApp.handle()` only parses pairing links — add a session URL route in `AppModel.handle()`.
- [Low] ios/Linkup/Core/Live/LiveManager.swift:310-313 — Tapping a background notification sets `currentSessionId` but leaves active modal sheets open — `handleNotificationResponse` updates `ui?.currentSessionId` without resetting `isShowingSettings`, `isShowingRunning`, etc. — dismiss active sheets when handling navigation from a user notification.

## Gemini: streaming

# Linkup Streaming Lifecycle Audit (g3-streaming)

Audited end-to-end streaming lifecycle: bridge adapters (`bridge/linkup_bridge/agents/*.py`, `server.py` record/broadcast) → `LinkupClient` receive → `SessionStore.ingest` → `Transcript.apply` → `ChatView`/`MessageViews`/`ActivityViews` rendering, plus composer model pill and token calculation.

All 50 findings below are new and not present in `tasks/AUDIT.md`.

---

## 1. Auto-Scroll, Layout Snapping & Caret Glitches

1. [High] ios/Linkup/UI/Chat/ChatView.swift:101-118 — Scroll-to-bottom arrow button directly overlaps and obscures the composer's voice/send button — `.overlay(alignment: .bottom)` on `ScrollView` is attached before `.safeAreaInset(edge: .bottom) { ComposerView }`, so the arrow sits at the bottom edge of the screen rather than above the composer — attach `.overlay` after `.safeAreaInset` or use a dedicated floating inset.
2. [High] ios/Linkup/UI/Chat/ChatView.swift:70, 136-176 — Auto-scroll jitters and fights itself continuously during streaming — `ScrollView` specifies `.defaultScrollAnchor(.bottom)` while `scrollGluedToBottom` concurrently commands programmatic `proxy.scrollTo("chat_bottom")` every 75ms without animation, causing native and manual scroll engines to collide — remove `.defaultScrollAnchor(.bottom)` or rely solely on native anchoring during active turns.
3. [Med] ios/Linkup/UI/Chat/ChatView.swift:122-135 vs 160-174 — Violent scroll stutter when a new assistant turn starts — `onChange(of: transcript.items.count)` triggers an animated scroll (`.smooth(duration: 0.15)`), but incoming `lastSeq` events concurrently invoke un-animated `proxy.scrollTo` within 75ms, canceling the animation mid-flight — gate `items.count` animation behind `!transcript.isWorking` or unify into a single throttled animator.
4. [Med] ios/Linkup/UI/Chat/ChatView.swift:61-63, 351-360 — Auto-scroll overshoots the assistant response, pushing the latest streamed line partially behind the composer — `proxy.scrollTo("chat_bottom")` targets an invisible spacer placed below `footnoteView` (24pt text + 24pt padding), so the view scrolls past the answer into the disclaimer — scroll to the live turn's ID rather than the trailing footnote spacer.
5. [High] ios/Linkup/UI/Chat/ChatView.swift:89-99 — Rapid content expansion tricks Linkup into thinking the user scrolled up, showing the down-arrow button and freezing auto-scroll mid-stream — `onScrollGeometryChange` calculates `distanceFromBottom > threshold`; when a token burst or code block expands, content height grows before the 75ms scroll fires, exceeding 180pt and latching `isUserScrolledUp = true` — only flip `isUserScrolledUp` on active user drag gestures.
6. [Med] ios/Linkup/UI/Chat/MessageViews.swift:539-552, 568-570 — Caret jumps wildly between inline paragraph position and a standalone 12pt block when switching between text and non-text blocks — while the last block is a paragraph, the caret is embedded in `HStack { Text; ChatBlinkingCaret }`; when the block becomes a list, table, or code fence, the caret is removed and placed in the outer `VStack` 12pt below — keep caret container placement uniform across block types.
7. [Med] ios/Linkup/UI/Chat/MessageViews.swift:539-546 — Paragraph line breaks and height jump abruptly the moment streaming finishes — while streaming, paragraph text is constrained inside an `HStack` beside the caret; when streaming ends, the `HStack` is discarded for a bare `Text`, altering SwiftUI's horizontal layout proposal — maintain a stable container hierarchy regardless of `isStreaming` state.
8. [Low] ios/Linkup/UI/Chat/MessageViews.swift:863-877 — Caret blinking animation resets and flickers on every markdown re-render — `ChatBlinkingCaret` has local `@State private var isVisible = true` inside an un-keyed view recreated on every body evaluation, re-executing `onAppear` and `.repeatForever()` — hoist caret animation state to an external driver or use `.symbolEffect`.

---

## 2. Activity Row, Thinking Blocks & Timeline Flickers

9. [High] ios/Linkup/Core/Store/Transcript.swift:251-263, 296-299 — Activity line in collapsed row flickers back to "Ran command" or "Working…" on every newline in thinking — `summaryLine` takes `text.split(whereSeparator: \.isNewline).last`; on a newline, the last line is temporarily empty, so `activityLine` falls back to the previous tool or default state for one token until characters arrive — fall back to the previous non-empty line instead of returning empty on trailing newlines.
10. [Med] ios/Linkup/UI/Activity/ActivityViews.swift:66-68 — Collapsed activity row text jitters continuously during thinking streaming — `turn.activityLine` changes on every single thinking token, and `ActivityRow` attaches `.animation(.smooth, value: turn.activityLine)`, queueing continuous overlapping smooth transitions — throttle `activityLine` updates or remove `.animation(.smooth)` from the continuous text change.
11. [High] ios/Linkup/UI/Chat/MessageViews.swift:160-170, 207-214 — Activity row abruptly vanishes at turn end in chat-mode sessions, snapping the answer upward — `shouldShowActivityRow` returns `true` while `turn.isLive`, but in chat mode (`isChatMode`), it immediately returns `false` when `turn.isLive` becomes false (unless errors occurred), removing the row with no animation — animate row collapse or preserve the finished summary row in chat mode.
12. [Med] ios/Linkup/UI/Chat/MessageViews.swift:173-175, 217-219 — Assistant header (agent logo and model name) suddenly pops in when the first text token arrives, shifting layout downward — `hasAnswerContent` gates `turnHeader` on `!turn.textBlocks.isEmpty || !turn.artifacts.isEmpty || !turn.isLive`; during tool/thinking phases it is hidden, then suddenly appears when text starts streaming — always render `turnHeader` at the top of an assistant turn from turn start.
13. [Med] ios/Linkup/UI/Activity/ActivityViews.swift:428-436 — Thinking block in timeline pops from "Thinking…" shimmer to multi-line text with an un-animated height jump — `ThinkingEntryView` switches abruptly from `ActivityShimmerText` to `VStack { Text(block.text) }` with no transition as soon as the first character arrives — apply a smooth content transition between the placeholder and the streaming text.
14. [High] ios/Linkup/UI/Activity/ActivityViews.swift:438-455 — Streaming thinking text abruptly snaps from expanding view down to 4 lines mid-stream — `needsCollapseButton` checks `block.text.filter(\.isNewline).count >= 4 || block.text.count > 180`; as soon as line 4 or char 181 is streamed, `isExpanded` (default false) clamps the view with `.lineLimit(4)` and pops the "Show more" button in — keep thinking expanded during active streaming (`block.isActive`), and only collapse after streaming ends.
15. [Med] ios/Linkup/UI/Activity/ActivityViews.swift:210-213, 304-310 — Live thinking row shows a redundant "Thinking…" pulsing entry below already running tools or thinking entries — `timelineList` always appends `liveThinkingRow` at the bottom whenever `turn.isLive` is true, even when a tool is active or a thinking block is already displayed in `items` — show `liveThinkingRow` only when `items.isEmpty` or when in an initial requesting phase without active parts.
16. [Med] ios/Linkup/UI/Activity/ActivityViews.swift:230-236 — Timeline sheet auto-scroll stutters on every token of thinking — `.onChange(of: turn.activityLine)` scrolls to `bottom_anchor` with `.smooth` on every thinking token (dozens of times per second) without throttling — throttle timeline auto-scroll or trigger only on part additions (`turn.activity.count`).
17. [Low] ios/Linkup/UI/Activity/ActivityViews.swift:396-417 — Timeline connecting vertical line cuts off prematurely when streaming ends — at `turn.end`, `part.id == items.last?.id` becomes `isLast: true` which renders `Color.clear` for the bottom half, while `finishedFooter` has no connecting line, leaving a gap — extend the hairline through the finished footer entry.

---

## 3. Tool Calls, Permissions & State Shifts

18. [Med] ios/Linkup/Core/Store/ToolPresentation.swift:56-72 — Tool card title jumps from 1 line to 2 lines when tool input finishes streaming — while input JSON streams in `partialInput`, `detail` is nil so `title` is just "Running command"; when `tool.update` arrives with parsed `input`, `detail` is appended ("Running command · <cmd>"), expanding the title row — extract detail preview opportunistically from `partialInput` or reserve a 2-line title container.
19. [Low] ios/Linkup/UI/Activity/ActivityViews.swift:475-479 — Tool call chevron and text jump horizontally when a tool finishes — `if tool.isRunning { ProgressView() }` is conditionally included inside the `HStack` without reserved width; when the tool finishes, the spinner disappears and the layout snaps — reserve a fixed 20pt frame for the status indicator/spinner.
20. [Med] ios/Linkup/UI/Activity/ActivityViews.swift:708, 723-737 — Tool input detail view suddenly pops friendly headers mid-stream when `tool.update` arrives — `friendlyHeaderView` reads `tool.input`, which is empty during `tool.input` streaming; when `tool.update` sets `tool.input`, the friendly header suddenly mounts above `rawInputSection` — parse partial JSON or show a consistent placeholder until input is complete.
21. [Med] ios/Linkup/UI/Activity/ActivityViews.swift:989-994 — Raw input text in tool detail view jumps from raw single-line JSON to multi-line pretty text — `rawInputString` returns unescaped raw string while `partialInput` is present, then abruptly switches to indented `prettyText` on `tool.update` — format partial JSON consistently with a streaming-safe formatter.
22. [High] ios/Linkup/UI/Activity/ActivityViews.swift:1232-1245 with MessageViews.swift:228-231 — Answering a permission prompt causes the card to vanish instantly with no feedback instead of showing "Allowed" or "Denied" — `MessageViews` only renders `PermissionCard` `if p.allowed == nil`; the moment `allowed` is set, the entire card is stripped from the view hierarchy, so `actionOrStatus`'s status branch never displays — keep the permission card visible in chat with its allowed/denied badge and transition it out gracefully.
23. [Low] ios/Linkup/UI/Activity/ActivityViews.swift:44-57 — Leading icon in collapsed activity row snaps with no transition when permissions appear and resolve — `leadingIcon` switches directly between `WorkingDots()` and `Image(systemName: "hand.raised.fill")` based on `hasPendingPermission` with no `contentTransition` — add `.contentTransition(.symbolEffect(.replace))` to the leading icon.

---

## 4. Composer Pill, Stop Button & Send Flow

24. [High] ios/Linkup/UI/Composer/ComposerView.swift:436-444 — Model pill wraps "Medium" to "Mediu\nm" inside a 44pt pill — neither `Text(info.name)` nor `Text(effort)` has `.lineLimit(1)`, and the bottom toolbar HStack has 5 controls on one row with insufficient width on standard iPhone widths, so SwiftUI wraps the effort text across two lines — add `.lineLimit(1)` and `.fixedSize(horizontal: true, vertical: false)` to both labels and reduce horizontal padding.
25. [High] ios/Linkup/UI/Composer/ComposerView.swift:431-435 with UsageRing.swift:55-68 — Stray empty spinner circle displayed in model pill — `UsageRingBadge` draws `Circle().stroke(lineWidth: 2.5)` unconditionally for Claude sessions even when utilization is zero or uncalibrated, which visually looks like a frozen or broken progress spinner next to the model name — only render `UsageRingBadge` when utilization is non-zero, or display a distinct quota icon.
26. [High] ios/Linkup/UI/Composer/ComposerView.swift:474-514 — Composer button rapidly flashes from Send -> Voice -> Stop upon sending — `handleSend()` immediately clears `text` and `attachments` while the bridge has not yet responded with `liveTurn`, so `hasContent` is false and `isWorking` is false, briefly displaying the Voice button before jumping to Stop — introduce an optimistic `isSubmitting` state that shows Stop or a spinner until the first turn event arrives.
27. [High] ios/Linkup/UI/Composer/ComposerView.swift:502-512 — Accidental Voice Mode trigger when tapping send button rapidly — because the button instantly becomes the Voice mode trigger (`isVoiceModePresented = true`) as soon as text clears, a quick second tap on the send button opens the full-screen voice mode sheet — debounce or disable voice mode presentation immediately after a send action.
28. [High] ios/Linkup/UI/Composer/ComposerView.swift:548-553 — User message does not appear in chat after sending until the bridge round-trips over WebSocket — `store.send` does not optimistically insert a `UserMessage` into `transcript.items`; it waits for the bridge to echo the event back over WebSocket, leaving the chat frozen for hundreds of milliseconds — append an optimistic `UserMessage` to `transcript.items` immediately upon send.
29. [Med] ios/Linkup/UI/Composer/ComposerView.swift:557-564 — Composer appears frozen and un-interactive during sequential attachment uploads — attachments are uploaded sequentially in a loop inside `Task` on the main actor after text is cleared, with no progress bar or upload indicator on the composer container — upload attachments concurrently (`withThrowingTaskGroup`) with an explicit progress indicator.

---

## 5. Bridge Adapters, Server & Event Replay

30. [High] bridge/linkup_bridge/agents/agy.py:143-153 — Antigravity agent never emits `thinking.start` or `thinking.end`, leaving thinking blocks permanently marked active — `_step` only emits `thinking.delta` without surrounding `thinking.start` or `thinking.end` events; in `Transcript.swift`, `ThinkingBlock.isActive` defaults to `true` and remains `true` until `turn.end` — emit `thinking.start` on the first delta and `thinking.end` when state is DONE or when switching to text.
31. [Med] bridge/linkup_bridge/agents/hermes.py:129-138 with ios/Linkup/Core/Store/Transcript.swift:105-109 — Completed tool rows without matching `tool.started` appear with generic title "tool" at completion — Hermes `tool.completed` pops a generated UUID if the tool name was not in `tools`, emitting `tool.end` without `"name"`; `Transcript.swift` falls back to `name: "tool"`, popping a finished generic wrench row into the UI — include `e.get("tool")` in the `tool.end` payload and look up tools accurately.
32. [Med] bridge/linkup_bridge/agents/hermes.py:130, 135-136 — Concurrent or out-of-order tools in Hermes swap outputs and error states — `tools` stores a FIFO list of tool IDs per tool name (`tools.setdefault(name, []).append(tid)` and `ids.pop(0)`); if two identical tools complete out of order, their outputs and IDs cross — correlate tool calls with server-provided call IDs rather than a FIFO queue by name.
33. [High] bridge/linkup_bridge/server.py:120-121 with ios/Linkup/UI/Chat/MessageViews.swift:226-227 — Full-size artifact cards suddenly spawn at the bottom of the answer upon stream completion — when `text.end` arrives, `server.py` scans `paths_in(text)` and automatically emits `artifact` events for every mentioned path; `MessageViews` appends `ArtifactCard`s at the end of `turn.parts`, causing massive layout shifts — only emit artifacts for tools that created files, or badge them as inline mentions rather than full cards.
34. [High] bridge/linkup_bridge/agents/base.py:64 — Server crashes in `_side_effects` on stream completion if assistant text mentions a non-existent file path — `media.artifact()` calls `os.path.getsize(path)` unconditionally without checking `os.path.exists()`, raising `FileNotFoundError` during `paths_in(text)` processing on `text.end` — guard `os.path.isfile(path)` before calling `os.path.getsize(path)`.
35. [Med] bridge/linkup_bridge/agents/claude.py:308-311 — Claude content block keys collide across multiple turns in a session — `self._key(msg, ev.get("index"))` keys solely on `parent:index` (e.g. `:0`); on the next turn, block 0 overwrites `self.blocks[":0"]`, corrupting block tracking if previous blocks are still open — include a turn UUID or message ID in the block key.

---

## 6. Token Inflations & Live Activities

36. [High] ios/Linkup/Core/Store/Transcript.swift:132-133 with MessageViews.swift:495-505 — Token count displays 329.5k for a single 500-token response — `Transcript.swift` sums `inputTokens + cacheRead + cacheWrite` directly into `turn.usage.input`; in Claude Code, prompt caching reads context windows of 200k-300k tokens on every turn, which `MessageViews` formats as "329.5k tokens" — separate cached prompt tokens from net generated tokens, or display only output tokens in turn stats.
37. [Med] ios/Linkup/Core/Live/LiveManager.swift:124, 167 with LinkupLiveActivity.swift:56, 159 — Live Activity displays 0 tokens throughout active streaming, then suddenly jumps to full count at turn end — adapters only emit `usage` events on `result` / `turn.end`; during active generation, `turn.usage` is nil, so `ContentState.tokens` is 0 and the token chip in the Dynamic Island pops in only after completion — estimate streaming token count from character count or display progress without a 0-token gap.
38. [Med] ios/Linkup/Core/Live/LiveManager.swift:118-130 — Live Activity text stutters every second with erratic thinking fragments — `poll()` captures `turn.activityLine` once per second; because `activityLine` flickers continuously between thinking phrases, tool names, and empty lines, the Dynamic Island shows erratic jumping text — latch a stable phase/tool name for Live Activities rather than raw streaming thinking lines.

---

## 7. Backgrounding, Reconnect & Markdown Rendering

39. [High] ios/Linkup/Core/Store/Transcript.swift:38-40 with SessionStore.swift:48-51 — Reconnect mid-stream replays events in rapid succession without batching, triggering repeated full markdown reparses — during replay on `hello`, each replayed event is ingested individually; each `text.delta` mutates `TextBlock.text`, triggering repeated MainActor body passes and markdown regex passes — batch replayed events during `hello` replay and apply to transcript in a single pass.
40. [High] ios/Linkup/Core/Store/SessionStore.swift:222-232 — Flash memory I/O thrashing during streaming due to individual event file appends — `EventCache.append` performs a `FileHandle` open, seek, write, and close on disk for every single token received from the WebSocket, causing thousands of disk writes per answer — keep an in-memory buffer and flush events to disk every 500ms or when streaming pauses.
41. [Med] ios/Linkup/UI/Chat/MarkdownParser.swift:48-53 — Markdown block IDs change across parses, defeating SwiftUI view identity and causing visual blinks — `ChatMarkdownParser.parse` assigns IDs using a monotonic counter `blockIdCounter` based purely on position (`p_1`, `p_2`); inserting or splitting a block causes all subsequent blocks to receive new IDs — derive block IDs stably from content hashes or line ranges.
42. [Med] ios/Linkup/UI/Cards/RichTextView.swift:18-20, 25 with CardSupport.swift:51-62 — Pending card placeholder causes a 400pt height jump when rich cards resolve — `PendingCardView` has a hard-coded frame height of 120pt; when the card finishes streaming, weather/place/data cards expand to 500-600pt, causing an animated layout jump (`.animation(.smooth)`) — remove animated transitions on card resolution and estimate placeholder height by card type.
43. [Med] ios/Linkup/UI/Chat/MarkdownParser.swift:120-134 — Table header appears as a plain serif paragraph before abruptly transforming into a table view on the second line — a markdown table is only recognized once line 2's separator (`| --- |`) is parsed; while line 1 is streaming, it is rendered as a regular paragraph with raw pipe characters — detect unclosed table headers with leading pipes and render as a table placeholder.
44. [Low] ios/Linkup/UI/Chat/MarkdownParser.swift:65-81 — Code block language header updates character by character on screen with no syntax highlighting until the fence line is complete — the language tag is parsed as `trimmed.dropFirst(3)` on every delta, continually morphing the header name before code lines begin — delay language badge rendering until a newline follows the opening fence.
45. [Low] ios/Linkup/UI/Chat/MarkdownParser.swift:329-348 — Entire code block flashes green during streaming when typing an unclosed quote — `ChatSyntaxHighlighter.highlight` consumes all characters until EOF when a quote is opened; while the string literal is being streamed, all subsequent code in the block is styled as a string — confine unclosed string literals to the current line during streaming syntax highlighting.
46. [Med] ios/Linkup/UI/Chat/MessageViews.swift:268-271 — Turn action row and dev server chips pop in with a hard layout snap when streaming finishes — `if !turn.isLive { devServerChips; actionRow }` has no transition or reserved height; the moment `turn.end` arrives, 50-80pt of controls appear instantaneously — add `.transition(.opacity)` with a smooth animation on action row appearance.
47. [Low] ios/Linkup/UI/Chat/ChatView.swift:65, 74-88 with PinnedStore.swift:17-26 — Pinned turn snippet continuously resizes horizontally in top strip while that turn is streaming — `pinnedTurnSnippet` extracts the first text block; as characters stream in, the pinned capsule button expands horizontally on every token — fix the pinned snippet width or truncate at a fixed character threshold.
48. [Med] ios/Linkup/Core/Net/LinkupClient.swift:184-192 — Main actor frame drops during high-frequency streaming due to main-thread JSON decoding — `ws.receive` dispatches to `Task { @MainActor in ... }` before calling `JSONDecoder().decode([String: JSONValue].self, from: data)`, running all parsing on the UI thread — perform JSON decoding on a cooperative background thread before dispatching to MainActor.
49. [Med] ios/Linkup/UI/Chat/MessageViews.swift:606-620 — Streaming text can visibly roll back to older content when throttle timer fires — the throttle `Task` captures the struct's `text` property at scheduling time; if newer deltas arrived, `bufferedText = text` writes the stale captured value — read current text from an `@Observable` model reference instead of a captured struct property.
50. [Low] ios/Linkup/UI/Chat/MessageViews.swift:805-827 — Blockquote accent bar height stutters as wrapped lines stream in — `ChatBlockquoteView`'s accent bar has no fixed height and stretches dynamically to the `VStack` containing individually enumerated lines with `id: \.offset` — wrap the blockquote in a continuous text container with a leading border.

## Gemini: layout / safe areas / sheets

# Layout, Safe Areas, Keyboard, and Presentation Audit

Audited: Native SwiftUI layout, safe area insets, ignoresSafeArea, keyboard avoidance, top bar scroll-edge effects, content clipping under chrome, sheet/fullScreenCover detents, nested NavigationStacks, double presentations, dismissal races, iPad multitasking widths, and iPhone landscape/Dynamic Island geometry across `ios/Linkup/UI/**`.
Total new findings: 55 (18 High, 26 Med, 11 Low).

---

## 1. Top Bar, Safe Areas & Dynamic Island

1. [High] ios/Linkup/UI/RootView.swift:403-438 & ios/Linkup/UI/Chat/ChatView.swift:45-88 — Scrolled chat text scrolls under the floating top bar controls and title with no background blur or fade, causing message text to collide with top bar title and buttons — `topBarSection` is a transparent VStack overlay with isolated glass buttons and an unbacked title; `ChatView`'s ScrollView has no top safe area material/bar (`.scrollEdgeEffectStyle` alone without a background), and `safeAreaInset(edge: .top)` only exists when `!pinned.isEmpty` — Add a `.background(.ultraThinMaterial)` or gradient safeAreaBar to `topBarSection` so scrolled content fades and blurs underneath the navigation controls.
2. [High] ios/Linkup/UI/Chat/ChatView.swift:65 vs ios/Linkup/UI/RootView.swift:437-438, 455, 541 — The first message of every chat session is partially hidden and clipped behind the floating top bar on launch — `ChatView` hardcodes `.padding(.top, pinned.isEmpty ? 70 : 12)`, but on notch/Dynamic Island iPhones `safeAreaInsets.top` (54–59 pt) + top bar height (48 pt) puts the bar at 102–115 pt (or ~145 pt if connection pill is shown), leaving 32–45+ pt of initial content obscured — Calculate top content inset dynamically from `safeAreaInsets.top + topBarHeight` or embed the top bar via `.safeAreaInset(edge: .top)`.
3. [High] ios/Linkup/UI/Artifacts/ArtifactViews.swift:342-364 — When viewing HTML, website, chart, or markdown artifacts in full-screen, the top navigation bar (close button, title, share, refresh) is clipped behind the Dynamic Island and status bar — In `.case .web`, `topBar` has only `.padding(.bottom, 6)` and `.padding(.top, 8)` without `.safeAreaPadding(.top)` (unlike `.case .image` and `.case .media` at lines 326 and 339 which include it) inside a `.fullScreenCover` — Add `.safeAreaPadding(.top)` to `topBar` in `ArtifactViewer`'s `.case .web`.
4. [High] ios/Linkup/UI/Composer/VoiceModeView.swift:54-58 — In voice mode fullScreenCover, the top bar "X" close button and agent pill are clipped under the Dynamic Island and status bar — `VoiceModeView` is presented as `.fullScreenCover` and sets `topBar.padding(.top, 16)` without querying safe area insets or using safeAreaPadding, rendering controls directly at y=16 pt in the hardware cutout zone — Change `.padding(.top, 16)` to `.safeAreaPadding(.top)`.
5. [High] ios/Linkup/UI/Cards/CardsDoHelpers.swift:230-266 — In recipe Cook Mode fullScreenCover, the close button, recipe title, and step counter are obstructed by the Dynamic Island and status bar — `DoCookModeSheet` is presented via `.fullScreenCover` and applies only `.padding(.top, 16)` to its header without safe area insets — Add `.safeAreaPadding(.top)` to the Cook Mode header `HStack`.
6. [Med] ios/Linkup/UI/Chat/ChatView.swift:76-85 — When pins are present, `pinnedStrip` creates an excessively large blank gap on SE/landscape while colliding with the top bar on Dynamic Island devices with offline pills — `pinnedStrip` hardcodes `.padding(.top, 60)` inside `safeAreaInset(edge: .top)`, completely ignoring actual dynamic `safeAreaInsets.top` and top bar height states — Bind top padding of `pinnedStrip` to the dynamic measured height of `topBarSection`.
7. [Med] ios/Linkup/UI/Chat/ChatView.swift:319 — In the empty chat state ("Hello, night owl"), the greeting headline and agent icon are cut off under the top bar buttons on Dynamic Island devices — `greetingView` uses a static `.padding(.top, 70)` which is smaller than Dynamic Island safe area (54 pt) + top bar button height (48 pt) = 102 pt — Inset `greetingView` by `max(safeAreaTop, 8) + 56` instead of fixed 70 pt.
8. [Med] ios/Linkup/UI/RootView.swift:621-636 — Toast notifications touch or overlap the bottom of the Dynamic Island and status bar — `toastView` applies `.padding(.top, max(safeAreaTop, 8) + 8)`, placing a centered capsule at y=62 pt which touches or overlaps the Dynamic Island (height 54 pt, expanding during Live Activities) — Position toasts below the full top bar (`max(safeAreaTop, 8) + 56`) or anchor them to the bottom above the composer.
9. [Med] ios/Linkup/UI/Cards/CardsDoHelpers.swift:469-495 — In the full-screen photo gallery viewer, the close button is clipped behind the Dynamic Island and status bar — `DoGalleryViewer` (presented via `.fullScreenCover` at `CardsDo.swift:1525`) positions its top close button with `.padding(.top, 16)` inside a fullScreenCover that ignores safe areas — Add `.safeAreaPadding(.top)` to the gallery close button.
10. [Low] ios/Linkup/UI/RootView.swift:544-566 — The top bar title and subtitle overlay collides with both the hamburger button on the left and the new chat capsule on the right on narrow screens — `topBarRow` uses `.overlay` with fixed `.padding(.horizontal, 96)` without verifying if remaining width fits the session title and subtitle strings — Place title in the main HStack layout or scale down text using `.minimumScaleFactor(0.8)`.

---

## 2. Drawer & Shell Layout

11. [High] ios/Linkup/UI/RootView.swift:287-292 with 118, 278-285 — The top of `SidebarView` ("From your PC" and agent list) bleeds through behind the status bar and Dynamic Island while the drawer is closed — `SidebarView()` is unconditionally active in the ZStack behind `mainLayer` with no `.opacity(0)` or conditional rendering, while root `GeometryReader` excludes `safeAreaInsets.top` so `mainLayer`'s top safe area remains transparent — Hide `SidebarView` (`.opacity(openProgress > 0 ? 1 : 0)`) when closed and ensure `mainLayer` covers the top safe area.
12. [Med] ios/Linkup/UI/Sidebar/SidebarView.swift:415-424 — The sidebar's "New session" and connection status pill sit directly over or against the home indicator gesture line — `bottomOverlay` has `.ignoresSafeArea(edges: .bottom)` at line 422, pulling interactive controls into the home bar exclusion zone — Remove `.ignoresSafeArea(edges: .bottom)` from `bottomOverlay` so controls sit safely above the home indicator.
13. [Med] ios/Linkup/UI/Sidebar/SidebarView.swift:49-51 — On devices with larger text sizes or home indicators, the bottom of the sidebar history list is obscured under the overlaid bottom bar and cannot be scrolled into view — `Color.clear.frame(height: 120)` is used as a static dummy spacer instead of measuring dynamic bottom overlay height — Replace the static 120 pt spacer with `.safeAreaInset(edge: .bottom) { bottomOverlay }`.
14. [Low] ios/Linkup/UI/RootView.swift:412 — When dragging the drawer open on iPhone, the rounded corners of `mainLayer` switch abruptly between sharp and rounded — `clipShape(RoundedRectangle(cornerRadius: openProgress > 0 ? 20 : 0, style: .continuous))` uses a binary threshold rather than interpolating the radius — Interpolate corner radius smoothly with `cornerRadius: openProgress * 20`.

---

## 3. Composer Layout, Bottom Insets & Keyboard Avoidance

15. [High] ios/Linkup/UI/Composer/ComposerView.swift:124-140 & ios/Linkup/UI/Composer/CommandSuggestions.swift:148-150 — Typing `/` to trigger slash commands causes the composer and suggestions to push off the top of the iPhone screen, clipping search bar and header — `CommandSuggestionsView` has `.frame(maxHeight: UIScreen.main.bounds.height * 0.55)` (~468 pt) embedded in `safeAreaInset(edge: .bottom)`; combined with keyboard (~336 pt) and composer (~120 pt) = 924 pt, which exceeds iPhone screen height (852 pt) — Present `CommandSuggestionsView` as a dedicated sheet/popover or clamp its height to remaining viewport above the keyboard.
16. [High] ios/Linkup/UI/Composer/ComposerView.swift:142-146 & 232-298 — When composer text field is focused in landscape on iPhone, the composer expands to fill the entire screen, pushing chat messages and navigation bar out of sight — `ComposerView` sits in `safeAreaInset(edge: .bottom)` with prompt library chips, 8-line TextField, attachments, and buttons with no maxHeight cap or landscape compactness — Add `.frame(maxHeight: 180)` to `composerContainer` and collapse prompt chips in landscape.
17. [High] ios/Linkup/UI/Composer/ComposerPromptLibrary.swift:81-110 — Tapping "+" to save a prompt or long-pressing to delete a prompt causes keyboard hitching, flickering, and focus loops — `.alert("Save Prompt", isPresented: $isSaveAlertPresented)` and `.confirmationDialog` are presented directly on `ComposerPromptLibraryView` while `ComposerView`'s `TextField` is focused with active keyboard — Dismiss the keyboard / resign focus before presenting the prompt title alert.
18. [Med] ios/Linkup/UI/Composer/CommandSuggestions.swift:172 vs ios/Linkup/UI/Composer/ComposerView.swift:272 — When slash suggestions appear, two blinking text cursors and two search fields appear simultaneously on screen — `CommandSuggestionsView` embeds its own `TextField("Search commands…", text: $searchQuery)` while `ComposerView`'s `TextField` remains active and focused underneath — Remove the duplicate `TextField` in `CommandSuggestionsView` and filter commands using `ComposerView`'s existing text.
19. [Med] ios/Linkup/UI/Composer/ComposerPromptLibrary.swift:67-77 — Tapping into the composer causes the text field to abruptly jump downward as prompt library chips animate in — `ComposerPromptLibraryView` is conditionally inserted inside the `VStack` of `composerContainer` above the `TextField` inside `.safeAreaInset(edge: .bottom)`, changing composer height by 40+ pt — Stabilize container height or place prompt chips in an attached keyboard input accessory bar.
20. [Med] ios/Linkup/UI/Workspace/GitStatusView.swift:283-292 — When typing a commit message in Git Changes, the keyboard covers the Commit and Push buttons with no way to drag to dismiss — `GitStatusView`'s `ScrollView` lacks `.scrollDismissesKeyboard(.interactively)` and lacks bottom keyboard avoidance padding for its bottom-docked commitBox — Add `.scrollDismissesKeyboard(.interactively)` and safe area bottom padding to the commit box.
21. [Med] ios/Linkup/UI/Schedules/ScheduleEditor.swift:382-388 — Focusing the prompt editor in ScheduleEditor causes the keyboard to cover the text being typed, with no ability to scroll down to the Save button — `TextEditor` has a fixed `minHeight: 120` inside a non-keyboard-dismissing `ScrollView` in a `.medium` detent sheet — Add `.scrollDismissesKeyboard(.interactively)` and default the sheet detent to `.large`.
22. [Med] ios/Linkup/UI/Workspace/FileViewer.swift:96-99 & 354-407 — Searching within a file while the keyboard is up causes code lines and match navigation buttons to be covered by the keyboard — `searchBarOverlay` is placed in a non-sticky `VStack` above code lines with no keyboard avoidance or pinned toolbar placement — Pin the search bar in a principal `.toolbar` or inset code lines above the software keyboard.
23. [Low] ios/Linkup/UI/Composer/ComposerView.swift:81-102 — Model pill button text ("Opus 5.5 Medium") wraps awkwardly into two lines ("Mediu" / "m") on narrow screens, stretching the composer bar — `modelPillButton` uses fixed padding without line truncation or minimum scale factor on the model and effort labels — Add `.lineLimit(1)` and `.minimumScaleFactor(0.85)` to model pill text runs.

---

## 4. Sheets, FullScreenCovers & Modal Presentations

24. [High] ios/Linkup/UI/Workspace/NewProjectSheet.swift:293-294 vs ios/Linkup/UI/Workspace/ProjectsView.swift:72-74 — Tapping "Create project" causes the sheet dismiss and navigation push to conflict, resulting in a dropped or stuttering push animation — `performCreate()` executes `onCreated(project)` (which appends to `navigationPath` in `ProjectsView`) immediately followed by `dismiss()`, pushing onto a navigation stack behind an actively dismissing sheet — Call `dismiss()` first and append to `navigationPath` in `onDismiss` of the sheet.
25. [High] ios/Linkup/UI/Workspace/GitStatusView.swift:48-53 — Tapping a changed file diff in Git Changes fails to open if full workspace diff was previously opened, or sheets dismiss unexpectedly — `GitStatusView` attaches two distinct `.sheet` modifiers to the same view: `.sheet(item: $selectedFileForDiff)` and `.sheet(isPresented: $isShowingFullDiff)`, violating SwiftUI's single-sheet-per-view constraint — Consolidate into a single `.sheet(item:)` driven by an identifiable diff target enum.
26. [High] ios/Linkup/UI/Multi/CompareView.swift:40-70 — In the multi-agent Comparison view header, tapping the "X" close button fails to dismiss the sheet and instead pops back to the setup configuration screen — Both the left chevron and right "X" buttons call `dismiss()`, which in a pushed NavigationStack view only pops the view from the stack — Connect the "X" close button to `ui.isShowingCompare = false` to dismiss the root sheet.
27. [High] ios/Linkup/UI/Multi/CompareView.swift:212-215 — Tapping "Open" on an agent column in Comparison pops back to the setup configuration sheet instead of navigating to the chat session — `openSession()` in `CompareColumnView` sets `ui.currentSessionId = sessionId` and calls `dismiss()`, which only pops `CompareView` back to `CompareSheet`, leaving `CompareSheet` presented — Set `ui.isShowingCompare = false` to dismiss the entire sheet hierarchy.
28. [High] ios/Linkup/UI/Settings/SettingsViews.swift:251-253 — Scanning a pairing QR code causes a UI freeze or glitch where the scanner dismisses but the connect sheet stays stuck — `applyAndConnect` sets `isShowingScannerSheet = false`, `ui.isShowingConnect = false`, and calls `dismiss()` simultaneously on the same runloop turn, causing a UIKit double-dismissal conflict — Dismiss scanner sheet first, then dismiss `ConnectView` inside the scanner's `onDismiss` callback.
29. [High] ios/Linkup/UI/Multi/CompareSheet.swift:60-65 & ios/Linkup/UI/Multi/CompareView.swift:20-31 — The multi-agent Comparison view is pushed inside a half-height sheet (.medium detent) where 3 agent columns cannot fit vertically or horizontally — `CompareSheet` declares `.presentationDetents([.medium, .large])` on its NavigationStack, and pushes `CompareView` into that same sheet, locking comparison to medium detent on launch — Set `.presentationDetents([.large])` on `CompareSheet` when navigating to `CompareView`, or present `CompareView` as a fullScreenCover.
30. [High] ios/Linkup/UI/Activity/ActivityViews.swift:154-156 & 610-639 — Tapping a turn summary opens at half-height (.medium), and drilling down into tool details (diffs, bash commands) stays confined to the half-height sheet — `SummarySheet` has `.presentationDetents([.medium, .large])` which applies to all pushed views (`ToolCallDetailView`) in its `NavigationStack` — Auto-expand to `.large` when drilling into a tool call detail.
31. [Med] ios/Linkup/UI/Multi/RunningNowView.swift:47-48 vs ios/Linkup/UI/RootView.swift:142-143 — Jerky, stuttering sheet presentation animation when opening Running Now — `.presentationDetents([.medium, .large])` and `.presentationBackground(Theme.surface)` are defined redundantly in both `RootView.swift:142-143` and `RunningNowView.swift:47-48` — Remove the duplicate presentation modifiers from `RunningNowView`.
32. [Med] ios/Linkup/UI/RootView.swift:141 — Extra blank bar space at the top of RunningNowView pushing the header down — `RootView` wraps `RunningNowView` in a `NavigationStack`, but `RunningNowView` provides its own custom header and has no navigation destinations or links — Remove the outer `NavigationStack` or add `.toolbar(.hidden, for: .navigationBar)` to `RunningNowView`.
33. [Med] ios/Linkup/UI/Multi/HandoffSheet.swift:83-84 vs ios/Linkup/UI/RootView.swift:155-156 — Janky presentation animation and primary "Continue handoff" button clipped below the fold on launch — Duplicate `.presentationDetents` in both `RootView` and `HandoffSheet`, combined with `.medium` detent hiding the primary action button below the fold — Remove duplicate modifiers and default `HandoffSheet` to `.large` detent.
34. [Med] ios/Linkup/UI/Multi/HandoffSheet.swift:325-327 — If handoff sheet dismissal is interrupted or canceled by user drag, the sheet remains stuck in `isLoading == true` with no retry ability — `performHandoff()` sets `ui.currentSessionId = newSession.id` and calls `dismiss()` while `isLoading` remains `true` — Reset `isLoading = false` if dismissal does not succeed.
35. [Med] ios/Linkup/UI/Workspace/NewProjectSheet.swift:106-107 — On iPhone, NewProjectSheet opens at half-height (.medium detent) and focusing the name field causes the keyboard to cover all templates and the create button — `NewProjectSheet` sets `.presentationDetents([.medium, .large])` for a content-heavy creation form requiring keyboard input — Use `.presentationDetents([.large])` exclusively for `NewProjectSheet`.
36. [Med] ios/Linkup/UI/Workspace/GitHistoryView.swift:275, 294-295 — When viewing commit details from git history, the sheet opens at `.medium` detent and cuts off commit message, author info, and full hash — `GitCommitDetailSheet` sets `.presentationDetents([.medium, .large])`, defaulting to `.medium` for an informational detail view that contains multi-paragraph commit subjects and bodies — Change detents to `.presentationDetents([.large])`.
37. [Med] ios/Linkup/UI/Workspace/CIRunsView.swift:57-60 — Tapping a CI workflow run presents `WorkspaceSafariView` inside a sheet with redundant grabber and double-wrapped navigation chrome — `SFSafariViewController` is wrapped in `UIViewControllerRepresentable` and presented via `.sheet(item: $safariTarget)` with `.ignoresSafeArea()`, which clashes with SFSafariViewController's internal modal navigation bar — Present safari target using fullScreenCover or open via `Link` / `openURL`.
38. [Med] ios/Linkup/UI/Settings/SettingsViews.swift:446-449 — Settings close button triggers conflicting dismissal state transitions — Close button executes both `ui.isShowingSettings = false` and `dismiss()`, triggering two conflicting dismissal pathways simultaneously — Use either `dismiss()` or `ui.isShowingSettings = false`, not both.
39. [Med] ios/Linkup/UI/Settings/SettingsViews.swift:485-495 — Usage view opens at `.medium` detent, cutting off the usage rings and 7-day token charts halfway — `UsageView` sets `.presentationDetents([.medium, .large])` on its `NavigationStack` — Default `UsageView` to `.large` presentation detent.
40. [Med] ios/Linkup/UI/Activity/ActivityViews.swift:160-170 vs ios/Linkup/UI/Shell/InspectorView.swift:26-44 — On iPad, tapping the "X" button in the summary inspector header does nothing unless tapped precisely inside an invisible 48x48 box — `SummarySheet` uses `@Environment(\.dismiss) private var dismiss`, which has no effect when embedded in iPad `InspectorView` column; `InspectorView` masks this with an invisible button overlay — Pass an explicit `onClose` closure to `SummarySheet` so iPad inspector clears `ui.summaryTurn = nil` cleanly.
41. [Med] ios/Linkup/UI/Cards/CardsPlaces.swift:222-224 & 294-296 — Tapping a place card in chat opens a place detail sheet at half-height (.medium detent) where the hero image and details are truncated — `PlacesDetailSheetView` sets `.presentationDetents([.medium, .large])` over a 9-block dense place card — Default `PlacesDetailSheetView` to `.large` presentation detent.
42. [Med] ios/Linkup/UI/Cards/CardsMedia.swift:96, 184, 433, 610, 692, 935 — Tapping external links on media cards inside a long chat can cause unexpected sheet dismissal or crash while scrolling — Each individual card instance in `LazyVStack` attaches its own `.sheet(item: $safariURL)`; when cells scroll off-screen, their State and sheet presenters are destroyed by cell recycling — Lift safari presentation state to the parent `ChatView` or use `Link` / `OpenURL`.
43. [Med] ios/Linkup/UI/Shell/DevServerPreview.swift:210, 266-308 — In dev server preview, the bottom navigation bar overlaps web page content or clips behind the home indicator — `DevServerWebView` uses `.ignoresSafeArea(edges: .bottom)` while `ToolbarItemGroup(placement: .bottomBar)` is applied to the container, causing toolbar and web content safe area collisions — Remove `.ignoresSafeArea(edges: .bottom)` from `DevServerWebView` so it properly respects the bottom toolbar.
44. [Low] ios/Linkup/UI/Shell/DevServerPreview.swift:250-264 & 299-307 — The "Open in Safari" icon appears twice simultaneously: in the top right navigation bar and in the bottom navigation bar — Duplicate `ToolbarItem` and `ToolbarItemGroup` actions pointing to the same `openURL(url)` action — Remove the top bar Safari button and keep it in the bottom toolbar only.
45. [Low] ios/Linkup/UI/Workspace/FileBrowserView.swift:63-71 vs ios/Linkup/UI/Workspace/ProjectDetailView.swift:36 — When navigating files in the workspace, the navigation bar title flickers or displays conflicting titles between folder names and project names — `FileBrowserView` sets `.navigationTitle(folderTitle)` and `.navigationBarTitleDisplayMode(.inline)`, but it is embedded as a child view inside `ProjectDetailView`'s tab switch, which also sets `.navigationTitle(project.name)` — Lift navigation title to `ProjectDetailView` or omit `navigationTitle` on nested tab container children.
46. [Low] ios/Linkup/UI/Workspace/FileViewer.swift:467 & ios/Linkup/UI/Workspace/GitHistoryView.swift:214 — Toast notifications for "Copied to clipboard" and "Full hash copied" are completely invisible — `ui.toast` is set from deeply nested sheets (`ProjectsView` -> `FileViewer` or `GitHistoryView`), but toasts are rendered on `RootView`'s overlay which is covered by presented sheets — Display copy feedback inline within the sheet or lift toasts into sheet overlays.

---

## 5. iPad Multitasking & Window Layout

47. [High] ios/Linkup/UI/RootView.swift:227-239 — In iPad Slide Over or narrow Split View, the sidebar separator rectangle and columns exceed the window width — `ipadThreeColumnLayout` is chosen when `horizontalSizeClass == .regular`, but on an iPad in 1/2 or 1/3 split, horizontal size class can flip or report regular while width is only ~500 pt, allocating 320 pt (sidebar) + 380 pt (inspector) = 700 pt > 500 pt — Guard column widths with `proxy.size.width` checks and collapse sidebar/inspector when width < 800 pt.
48. [Med] ios/Linkup/UI/Composer/CommandSuggestions.swift:25-31 — On iPad in Split View (e.g. 1/3 split, ~320 pt wide), slash command suggestions render in a 2-column grid, causing text and descriptions in each command card to clip and wrap illegibly — `columns` checks `UIDevice.current.userInterfaceIdiom == .pad || sizeClass == .regular`; on iPad Split View, `userInterfaceIdiom` is always `.pad` even when horizontalSizeClass is `.compact` and window width is only 320 pt — Check `sizeClass == .regular` alone without overriding on `userInterfaceIdiom == .pad`.
49. [Med] ios/Linkup/UI/Composer/CommandSuggestions.swift:149 — In iPad Stage Manager or Split View with a short window, the slash command picker sizes itself relative to the full hardware display instead of the app window, overflowing the app's window frame — `CommandSuggestionsView` uses `UIScreen.main.bounds.height * 0.55`; in iPad multitasking, `UIScreen.main.bounds` reports display hardware dimensions, ignoring the multi-window size — Use `GeometryReader` or container height instead of `UIScreen.main.bounds`.
50. [Low] ios/Linkup/UI/Workspace/FileViewer.swift:475-480 — Tapping the share button in `FileViewer` inside iPad Split View causes a layout warning or misplaced popover — `ShareLink(item: text)` inside a pushed navigation destination within a modal sheet does not specify an anchor or presentation source for iPad popover routing — Anchor `ShareLink` or provide source rectangle for iPad.

---

## 6. Landscape iPhone Layout & Hardware Cutout Avoidance

51. [High] ios/Linkup/UI/Composer/VoiceModeView.swift:54-73 — On landscape iPhone, VoiceModeView overflows the screen vertically; the bottom mic/stop controls and close button are pushed off-screen, trapping the user in voice mode — `VoiceModeView` uses a non-scrolling `VStack(spacing: 0)` with a fixed 180 pt orb, 120 pt transcript, and fixed paddings totaling >510 pt, whereas landscape iPhone height is only ~390 pt — Embed `VoiceModeView` content in a `ViewThatFits` or `ScrollView` with responsive sizing for landscape.
52. [Med] ios/Linkup/UI/RootView.swift:436-438 — In landscape mode on iPhones with a notch or Dynamic Island, the sidebar hamburger button is clipped or covered by the camera cutout on the leading edge — `topBarSection` applies `.padding(.horizontal, 16)`; in landscape, `safeAreaInsets.leading` is ~59 pt, placing the button at x=16 directly in the hardware cutout zone — Use `.padding(.leading, max(proxy.safeAreaInsets.leading, 16))` for the leading button in `topBarSection`.
53. [Med] ios/Linkup/UI/RootView.swift:464-543 — In landscape orientation on iPhone, the right top bar capsule (new chat + ellipsis menu) is partially clipped under the trailing display corner / curve — `topBarSection` uses `.padding(.horizontal, 16)`, which does not inset for `proxy.safeAreaInsets.trailing` in landscape — Use `.padding(.trailing, max(proxy.safeAreaInsets.trailing, 16))`.
54. [Med] ios/Linkup/UI/RootView.swift:592-604 — Edge swipe to open the drawer fails or conflicts with system home/rotation gestures in landscape orientation — `edgeSwipeZone` hardcodes `frame(width: 28)` and checks `startLocation.x <= 28`; in landscape, safe area is ~59 pt, placing the 28 pt strip entirely inside the dead zone of the notch/Island — Offset `edgeSwipeZone` by `proxy.safeAreaInsets.leading`.
55. [Med] ios/Linkup/UI/RootView.swift:277-280 — On standard iPhones (iPhone 14, 15, 16, SE) in landscape orientation, opening the sidebar covers 82% of the wide screen (~700 pt), leaving only a tiny ~150 pt sliver of chat — `drawerWidth = UIDevice.current.userInterfaceIdiom == .pad ? 340 : (screenWidth * 0.82)`; in landscape, `screenWidth` is ~852 pt, so `screenWidth * 0.82` is 698 pt — Cap drawer width at `min(340, screenWidth * 0.82)`.

## Gemini: user journeys

# Linkup Bug Hunt — User Journeys & iOS Experience Audit

This audit evaluates the end-to-end user journeys of Linkup on iOS (SwiftUI, iOS 26 target) and the Python bridge (`bridge/linkup_bridge`), tracing real code paths from first launch through complex agent interactions. All findings below are **new** issues not documented in `tasks/AUDIT.md`.

---

## 1. Visual Glitches & Layout Jank (Real Device Artifacts)

- [High] ios/Linkup/UI/RootView.swift:287-299 & SidebarView.swift:36,55 — While the drawer is fully closed on iPhone, the sidebar header text "From your PC" bleeds through behind the status bar and notch — `SidebarView` in `iphoneDrawerLayout` is always rendered in the root `ZStack` with opacity 1.0; its background ignores safe area, while `GeometryReader` proxy starts below the status bar safe area, exposing the sidebar behind the top safe area gap — Add `.opacity(openProgress > 0 ? 1 : 0)` or gate `SidebarView` with `if ui.isSidebarOpen || dragOffset > 0`.
- [High] ios/Linkup/UI/RootView.swift:417-438 & ChatView.swift:45-69 — Chat text and message bubbles scroll underneath the floating top bar controls with no background fade or blur, causing text collisions — `topBarSection` is a floating glass container with transparent gaps around it, and `ChatView`'s `ScrollView` scrolls right to the top edge without an upper safe-area blur material or gradient mask — Add an `.ignoresSafeArea(edges: .top)` blur material background or a top gradient fade mask to `topBarSection`.
- [Med] ios/Linkup/UI/Composer/ComposerView.swift:436-444 — The model pill button in the composer splits effort text into two clipped lines (e.g. "Mediu\nm") on standard iPhone screen widths — In `HStack` inside `modelPillButton`, `Text(effort)` lacks `.lineLimit(1)` and `.fixedSize()`, while sitting beside 4 fixed 44pt circular buttons and a `Spacer()` with insufficient horizontal room — Add `.lineLimit(1)` to `Text(effort)` and set `.layoutPriority(1)` on the pill while allowing the pill to compress gracefully.
- [Low] ios/Linkup/UI/Composer/ComposerView.swift:431-435 & UsageRing.swift:46-64 — The composer model pill shows a tiny unlabelled hairline ring that looks like a broken or frozen loading spinner — `UsageRingBadge` renders a 16pt circular stroke for 5-hour utilization with no label or tooltip when utilization is near zero — Show the usage badge only when utilization is above a minimum threshold or add an explicit percentage glyph.
- [Med] ios/Linkup/UI/Chat/ChatView.swift:16-22 — Visual jump and flicker when sending the first message in a new session — `ChatView` switches abruptly between `greetingView` and `sessionView` using a hard `if transcript.items.isEmpty` branch with no animation or crossfade transition — Wrap the mode switch in `withAnimation(.smooth)` or apply `.transition(.opacity)`.
- [Low] ios/Linkup/UI/Multi/CompareView.swift:41-69 — Redundant dismiss controls in comparison top bar — Top bar renders both a chevron-left "Back" button on the leading side and an "xmark" button on the trailing side, both executing `dismiss()` — Remove the chevron button and retain only the trailing dismiss button.

---

## 2. Journey 1: First Launch & Pairing (QR / Manual) → First Chat

- [High] ios/Linkup/UI/Settings/SettingsViews.swift:249-254 — Scanning a pairing QR code immediately dismisses the connection sheet even if the bridge is offline or the host is unreachable — `applyAndConnect(url:)` applies settings to `@AppStorage` and dismisses before the WebSocket handshake succeeds; if connection fails, the user is dumped onto an empty screen with no feedback — Await connection handshake before dismissing `ConnectView`, displaying an inline spinner and error message if unreachable.
- [High] ios/Linkup/Core/Net/LinkupClient.swift:22-28, 120-122 — Tailscale funnel URLs with path prefixes fail to connect with 404 Not Found — `baseURL` trims trailing slashes but does not normalize path prefixes, causing `base.appendingPathComponent("linkup/ws")` to duplicate paths (e.g., `/linkup/linkup/ws`) — Check whether `base.path` already contains `/linkup` before appending `linkup/ws`.
- [Med] ios/Linkup/Core/Net/LinkupClient.swift:101-107 — Bridge resource URLs (artifacts, images, attachments) resolve to malformed URLs if paths lack leading slashes — `resolve(_:)` directly concatenates `base.absoluteString + relative` without ensuring a separating slash, producing URLs like `https://host:8765linkup/files` — Use `base.appendingPathComponent(relative)` or verify slash boundaries when concatenating relative paths.
- [Med] ios/Linkup/Core/Net/LinkupClient.swift:42-50 — Keychain token reads fail when app resumes in background after lock screen — Keychain queries use default accessibility without `kSecAttrAccessibleAfterFirstUnlock`, preventing background tasks from reading the token while device is locked — Add `kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock` to `Keychain.set` and `Keychain.get`.

---

## 3. Journey 2: Claude Code in Project, Permissions, Diffs, Stop, Retry, Edit & Resend

- [High] ios/Linkup/UI/Workspace/ProjectDetailView.swift:41-45 & ComposerView.swift:569-573 — Tapping "New session here" from a project detail view starts the session in the user's home directory if draft mode is "chat" — `store.createChat(agent:model:)` omits the `cwd` parameter, ignoring `ui.draftProject` entirely — Pass `cwd: ui.draftProject` to `createChat()` so chat mode respects the project directory.
- [High] ios/Linkup/App/LinkupApp.swift:85-87 & ComposerView.swift:580 — Creating a session from a project permanently traps all future new sessions inside that project — `ui.draftProject` is stored in `UserDefaults` and is never cleared in `newChat()` or after session creation, silently scoping subsequent chats to that directory — Clear `ui.draftProject = nil` inside `newChat()` and immediately after creating a session.
- [High] ios/Linkup/UI/Chat/MessageViews.swift:115-123 & bridge/linkup_bridge/server.py:334 — Tapping "Resend" on a user bubble silently strips and drops all photo/file attachments — `UserBubble` maps attachments to `["name": ..., "url": ...]`, but `server.py:334` strictly requires `a.get("path") and os.path.isfile(a["path"])`, evaluating to an empty list — Include `path` in the attachment dictionary or allow `server.py` to resolve attachments via existing stored files.
- [Med] ios/Linkup/UI/Chat/MessageViews.swift:468-481 — Tapping "Retry" while an agent turn is actively executing triggers duplicate concurrent turns and state desynchronization — `retryTurn()` lacks a guard check on `!transcript.isWorking`, sending a new user prompt while the runtime lock is engaged or streaming — Add `guard !store.transcript(for: sessionId).isWorking else { return }` at the top of `retryTurn()`.
- [Med] ios/Linkup/Core/Store/Transcript.swift:144-145 & bridge/linkup_bridge/agents/claude.py:288 — Stopping a Claude Code turn marks the turn as `.done` with a green checkmark instead of `.interrupted` — Claude Code CLI emits subtype `"interrupt"`, but `Transcript.swift:145` compares `reason == "interrupted"`, defaulting to `.done` — Update check to `(reason == "interrupted" || reason == "interrupt")`.
- [Med] ios/Linkup/UI/Activity/ActivityViews.swift:868-912 — The permission diff viewer renders all deleted lines followed by all added lines rather than an interleaved unified diff — `diffView(oldStr:newStr:)` renders the entire `oldStr` in a red box followed by the entire `newStr` in a green box without computing line-by-line diff deltas — Integrate a line-by-line unified diff algorithm to interleave matching and modified lines.
- [Low] ios/Linkup/UI/Chat/MessageViews.swift:475-478 — "Retry" drops user attachments that were part of the original prompt — `retryTurn()` reads only `userMsg.text` and calls `store.send(userMsg.text, to: sessionId)` without passing `userMsg.attachments` — Pass mapped attachments from `userMsg` into `store.send`.

---

## 4. Journey 3: Backgrounding App During Long Turn, Live Activity, Return

- [High] ios/Linkup/Core/Live/LiveManager.swift:52-55, 97 — Background audio keep-alive fails to engage if the user backgrounds the app immediately after sending a prompt — `previouslyRunningSessions` is populated only inside the 1-second `poll()` loop; backgrounding before the next tick leaves the set empty, skipping `audioKeepAlive.start()` and allowing iOS to suspend the app — Check `store.sessions.contains(where: \.isRunning)` directly inside `scenePhaseChanged(to: .background)`.
- [Med] ios/Linkup/Core/Live/LiveManager.swift:270-275 — Turn completion and permission notifications produce disruptive banner alerts and sounds while the user is actively viewing the chat in foreground — `userNotificationCenter(_:willPresent:)` unconditionally returns `[.banner, .sound]` regardless of whether the active session is currently on screen — Check if `notification.request.content.userInfo["sessionId"]` matches `ui.currentSessionId` and suppress banner/sound when active.
- [Med] ios/Linkup/Core/Live/LiveManager.swift:310-313 — Tapping a turn notification abruptly swaps the active session without dismissing open modal sheets or saving composer text — `handleNotificationResponse` directly reassigns `ui?.currentSessionId = sessionId` without dismissing `isShowingProjects`, `isShowingSettings`, or inspector sheets — Dismiss active sheets and preserve draft composer state when handling notification navigation.
- [Low] ios/Linkup/Core/Live/LiveManager.swift:154-158 — Live Activity completion snippet displays raw markdown fences or technical headers on the Lock Screen — `lastTurn?.textBlocks.map(\.text).joined()` extracts raw unparsed markdown which may start with ````json` or markdown headers — Strip markdown syntax from the snippet before updating the final Activity state.

---

## 5. Journey 4: PC Bridge Restart / Wi-Fi → Cellular Switch Mid-Turn

- [High] bridge/linkup_bridge/server.py:74-76 & ios/Linkup/Core/Store/Transcript.swift:22, 140-151 — In-flight turns remain stuck with a pulsating "Working" indicator on iOS forever after the bridge restarts — On startup, `server.py` resets session database status to `idle` without appending a `turn.end` event to the event log; reconnection replays no end event, leaving `liveTurn != nil` — Append a synthetic `turn.end` event with `stopReason: "error"` for any session reset to idle on bridge startup.
- [High] ios/Linkup/Core/Net/LinkupClient.swift:204-206 — Network interface handover (Wi-Fi to Cellular) hangs the connection indefinitely without triggering reconnection — `startPing` wraps `try? await request("ping", [:])` and ignores thrown errors, failing to set `state = .offline` or trigger `scheduleReconnect` — On ping timeout or network failure, cancel the current task and trigger `scheduleReconnect("Network connection lost")`.
- [Med] ios/Linkup/Core/Net/LinkupClient.swift:241-246 — Pending requests during bridge crashes stall for 30 to 90 seconds before failing — Continuation timeouts sleep for fixed durations; when WebSocket disconnects, continuations in `pending` are only cleaned up if `scheduleReconnect` is explicitly invoked — Iterate and reject all pending continuations immediately on `URLSessionWebSocketTask` disconnection.
- [Low] bridge/linkup_bridge/server.py:82-88 — WebSocket broadcast silently drops disconnected clients without unsubscribing them from session topics — `except Exception: self.clients.pop(ws, None)` cleans the dictionary but leaves stale references in locks and subscription sets — Clean up session subscription sets and lock references when removing failed WebSocket connections.

---

## 6. Journey 5: Antigravity and Hermes Chats vs Claude (Inconsistent Behaviour)

- [High] bridge/linkup_bridge/agents/hermes.py:105-112 — Hermes SSE stream parser drops events and crashes with `Extra data` on multi-line network chunks — `async for raw in r.content` yields arbitrary TCP buffer chunks rather than complete lines; multi-line buffers cause `json.loads` to fail with `JSONDecodeError` and get skipped — Buffer streaming bytes and split on line breaks using `r.content.readline()`.
- [High] bridge/linkup_bridge/agents/agy.py:142-150 & ios/Linkup/Core/Store/Transcript.swift:76-81 — Antigravity second turn appends text deltas to the first turn's bubble instead of creating a new bubble — `agy.py` restarts block indexing at `s0` on each step, while `Transcript.texts` cache is never cleared between turns, matching the old block ID — Prefix Antigravity block IDs with turn sequence or clear `texts` cache upon `turn.end`.
- [High] bridge/linkup_bridge/agents/agy.py:143-145 & ios/Linkup/Core/Store/Transcript.swift:63-68 — Antigravity second turn thinking text concatenates onto previous turn's thinking block — `thinking.delta` emits `t0`, colliding with the uncleared `thinking` dictionary in `Transcript.swift` — Namespace thinking block identifiers with unique turn or sequence IDs.
- [Med] bridge/linkup_bridge/server.py:224-226 — Antigravity and Hermes stop generating UI cards after their first turn — `CARDS_PROMPT` is gated on `not s.get("native_id")`, which is set after turn 1, reverting subsequent turns to plain markdown — Prepend `CARDS_PROMPT` for all chat-mode turns regardless of `native_id` existence.
- [Med] bridge/linkup_bridge/agents/agy.py:178-180 — Stopping an Antigravity turn sends SIGTERM, terminating the conversation process and losing session continuity — `interrupt()` calls `self.proc.terminate()` directly, killing the CLI subprocess rather than sending a graceful cancellation signal — Send an interrupt message or signal over stdin/SIGINT to maintain process continuity.
- [Low] bridge/linkup_bridge/agents/agy.py:133 — Antigravity turn completion always emits `stopReason: "done"`, even when cancelled or faulted — Exit handler ignores process exit code when emitting `turn.end`, masking errors as normal completions — Check `self.proc.returncode` and emit `"interrupted"` or `"error"` when non-zero.

---

## 7. Journey 6: Attach Photo/File, Voice Mode

- [High] ios/Linkup/UI/Composer/VoiceModeView.swift:396-406 — Short spoken agent responses ("Done.", "Yes.", "Saved.") are never spoken aloud during streaming — `findSentenceBoundary` enforces `idx > 15` before recognizing sentence delimiters, returning `nil` for replies under 16 characters — Remove the arbitrary `idx > 15` length threshold in sentence boundary detection.
- [High] ios/Linkup/UI/Composer/VoiceModeView.swift:359-373 — Voice mode speech playback skips and halts when markdown links stream in — `cleanTextForSpeech` is recomputed from scratch every tick; when a closing parenthesis completes a markdown link, the string length suddenly shrinks, invalidating `spokenOffset` — Clean input text deltas incrementally rather than recomputing indices against a mutating string.
- [Med] ios/Linkup/UI/Composer/ComposerView.swift:153-163 — Multiple photos selected from PhotosPicker are added in random, scrambled order — `for item in picked { Task { ... } }` launches unsequenced concurrent tasks where image decoding times vary — Load transferable items sequentially or sort by original selection index before appending attachments.
- [Med] ios/Linkup/UI/Composer/ComposerView.swift:629-632 — Rapid camera captures overwrite previous photos due to timestamp collision — Filename uses integer seconds `camera-\(Int(Date().timeIntervalSince1970)).jpg`, producing identical names during burst shots — Use a unique UUID string in the camera file naming scheme.
- [Med] ios/Linkup/UI/Composer/ComposerView.swift:637-640 — File importer reads full file data synchronously on the main thread, freezing the UI on large files — `Data(contentsOf: url)` runs directly on the `@MainActor` without background dispatch — Move `Data(contentsOf:)` into a background `Task.detached` to avoid locking the main thread.
- [Low] ios/Linkup/UI/Composer/VoiceModeView.swift:409-415 — Voice mode lacks speech barge-in interrupt capability — Speaking while the agent is speaking does not interrupt playback unless the user manually taps the visual orb — Enable speech recognizer audio monitoring during agent playback to detect user voice barge-in.

---

## 8. Journey 7: Workspace: Browse Files, Git Commit

- [High] ios/Linkup/UI/Workspace/FileViewer.swift:261-276 & RootView.swift:167 — Opening an image, PDF, or HTML file in workspace fails to present Artifact Viewer — `openInArtifactViewer` sets `ui.openArtifact`, attempting to present a `fullScreenCover` on `RootView` while `ProjectsView` sheet is already presented, which UIKit blocks — Present `ArtifactViewer` directly within the `ProjectsView` navigation hierarchy.
- [Med] ios/Linkup/UI/Workspace/FileBrowserView.swift:65-71 — Drilling into folders pushes onto root stack, permanently hiding the project's segmented tab bar — `navigationDestination(for: FileEntry.self)` pushes a new view that covers `pickerBar` (Files, Changes, History, Builds) — Retain the tab picker bar in a persistent container or embed folder navigation within the Files tab tab view.
- [Med] ios/Linkup/UI/Workspace/GitStatusView.swift:361-363 & bridge/linkup_bridge/workspace.py:526-528 — Git commit failure displays a false "Committed changes" success toast and clears the user's message — When `git_commit` returns `None` on failure, `performCommit` falls back to `ui.toast = "Committed changes"` and wipes `commitMessage` — Check for nil commit result, display an error toast, and preserve the commit message text.
- [Med] bridge/linkup_bridge/workspace.py:517 — Git commit unconditionally stages all modified and untracked files across the repository — `await _run_git(p, "add", "-A")` executes automatically before commit, overriding user intent to commit only specific staged files — Commit only already-staged changes unless explicit staging of all files is requested by the user.

---

## 9. Journey 8: Schedules, Usage & Missing Official Claude iOS Affordances

- [High] ios/Linkup/UI/Schedules/SchedulesView.swift:339-343 — Tapping "Run now" on a schedule leaves the user trapped on the Schedules sheet while the session runs behind it — `runScheduleNow` assigns `ui.currentSessionId` but fails to dismiss `SchedulesView` (`ui.isShowingSchedules = false` or `dismiss()`) — Call `dismiss()` immediately after setting `ui.currentSessionId`.
- [High] ios/Linkup/UI/Multi/HandoffSheet.swift:320-327 & Transcript.swift:135 — Agent handoff transitions user to an empty greeting screen with no context notice — Notice event is dropped in `Transcript.swift` because `liveTurn` and `lastAssistantTurn` are both nil on a fresh session — Append notice events as standalone transcript banner items when turns are empty.
- [Med] ios/Linkup/UI/Chat/MessageViews.swift:198-265 — Missing long-press context menu on assistant message bubbles — Users must scroll to the very bottom of multi-page responses to tap the tiny 24pt turn ellipsis button to copy or interact — Add a `.contextMenu` modifier to `AssistantTurnView` content with Copy, Share, and Retry actions.
- [Med] ios/Linkup/UI/Chat/MessageViews.swift:80-90 — Missing message timestamps and date section dividers — Transcript lacks any timestamp metadata on user bubbles and assistant turns, unlike official Claude iOS app — Render relative timestamps and date headers between conversation turns.
- [Med] ios/Linkup/UI/Activity/ActivityViews.swift:206-214 — Tool calls force full modal sheet takeovers rather than inline collapsible disclosure — Tapping any tool call in the activity strip opens a full-screen sheet instead of expanding inline — Support inline accordion-style folding for tool calls to preserve reading continuity.
- [Low] ios/Linkup/UI/Usage/UsageDashboardView.swift:110-130 — Usage dashboard does not show token caching breakdown — View displays aggregate input and output tokens but omits `cacheRead` and `cacheWrite` metrics provided by the bridge — Add cache read and cache creation token metrics to the Claude usage card.
