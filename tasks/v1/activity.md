# Linkup 1.0 — Activity (tool rows, thinking, permissions, turn Summary sheet)

YOUR FILES: ios/Linkup/UI/Activity/ActivityViews.swift. New files allowed in ios/Linkup/UI/Activity/.
Read first: tasks/v1/_common.md, Core/Store/Transcript.swift, Core/Store/ToolPresentation.swift (read only).

Must-fix (AUDIT: grep ActivityViews; section 3, W2-D 43/44, small-details, animations, RTL/a11y):
1. Activity line flickers back to "Working…"/"Ran command" on each newline in thinking — keep the last meaningful line.
2. Thinking block: no snap from expanded to 4 lines mid-stream; collapse decision stable while streaming
   (decide once text exceeds the limit, animate).
3. Permission card: after Allow/Deny keep a compact resolved state ("Allowed · Bash" / "Denied") instead of vanishing;
   buttons 44pt, haptic, disabled while sending; show tool input readably (command in mono, file path, diff preview).
4. Turn Summary sheet: opens `.large` (or `[.medium, .large]` but starts at .large when content is long); drill-down
   into tool details (diffs, bash output) gets full height; use SheetHeader; scrolling list doesn't double-scroll or
   flicker; timeline lines don't flicker.
5. Tool rows: running pulse animation only while running (bind to isRunning, stops cleanly; Reduce Motion → static);
   failed state clear (danger colour, error text readable, selectable); long outputs collapsed with "Show more";
   images in tool output with fixed aspect placeholders (no layout jump).
6. Token/usage lines use input+output (cached as secondary).
7. RTL/a11y: labels for icon buttons, headers, combined row labels.
Also every other AUDIT finding naming ActivityViews.


---
# SHARED RULES (tasks/v1/_common.md)

# Linkup 1.0 — shared rules for every fix agent (read fully before touching code)

Linkup is a native SwiftUI iOS/iPadOS 26 app (Swift 5 language mode, Xcode 26 SDK, no Swift packages) + a Python
bridge (`bridge/`) on the user's PC. Read `CLAUDE.md` and the old shared rules `tasks/_common.md` (design language,
Theme, Liquid Glass rules, API contracts) first. The user said the app is "buggy in navigation, model responses not well
handled, everything looks bad". We are shipping **Linkup 1.0** that fixes ALL of it. Quality bar: feels like the
official Claude iOS app — smooth, no jank, no clipped/overlapping UI, nothing that silently does nothing.

## Your checklist = the audit
`tasks/AUDIT.md` (~1700 lines) holds every finding from two audit waves, by file and line (line numbers are from
commit 17bee80 and may have drifted slightly — re-find by content). **Fix every finding that names one of YOUR files**,
in both waves: the curated sections (A–F, W2-A … W2-F) and the raw auditor sections. Search it like this:
`grep -n "RootView" tasks/AUDIT.md` for each of your files. Several auditors often report the same bug — fix it once.
Your brief adds the most important items and any cross-file contract. If a finding is wrong (the code doesn't do what
it claims), skip it and say so in your final message. If a finding needs a change in a file you don't own, don't do it:
list it in your final message under "NEEDS OTHER FILE".

You are one of ~10 agents editing DIFFERENT files at the same time. **Edit only the files your brief lists**
(you may create new files only inside the directories your brief names; prefix new private types with your area,
e.g. `SidebarFooter`, to avoid duplicate type names). Never edit project.yml, .github, Theme.swift (unless listed),
or another agent's files.

## Contracts already in the code (use them, don't redefine them)
- `ui.openSession(_ id: String?)` and `ui.newChat()` (App/LinkupApp.swift) are THE way to switch chats: they reset
  the inspector panels (summaryTurn/openArtifact) and close the drawer with its slide animation. Never assign
  `ui.currentSessionId` directly anywhere else. If a sheet starts/opens a session (Compare "Open", Schedules "Run now",
  Handoff, Projects "New session here"), call `ui.openSession(id)` AND dismiss the sheet (set its `ui.isShowing…`
  flag false / call dismiss()).
- `ui.toastID` bumps on every toast (use `.task(id: ui.toastID)` for the timer).
- `Transcript.isLoading` — true while cached events load from disk. ChatView shows a quiet loading state, not the greeting.
- `store.close(_ sessionId:)` — ChatView calls it when the user leaves a chat (store agent implements it: unsubscribe +
  evict). `store.open(_:)` subscribes; it must be safe to call twice (store agent dedupes).
- `TurnUsage { input (fresh, uncached), output, costUsd, cached }` — show token counts as input+output; `cached` only
  as a secondary detail ("+ 320k cached"). Never add cached into the headline number.
- `Notification.Name.linkupComposerSetText` (object: String) and `.linkupFocusSearch` (Core/Support/Notifications.swift).
- `String.dominantLayoutDirection`, `.isRightToLeft`, `.searchFolded` (Core/Support/TextDirection.swift): user writes
  Moroccan Darija in Arabic script, French and English. Any user-written or agent-written paragraph must be laid out
  in its own direction (`.environment(\.layoutDirection, text.dominantLayoutDirection)` + `.multilineTextAlignment`),
  and search must compare `searchFolded` strings.
- `SheetCloseButton(action:)` and `SheetHeader(title:onClose:leading:)` (UI/Theme/SheetChrome.swift): EVERY sheet uses
  this header/close button (trailing 44pt glass circle). Sheets: `.presentationBackground(Theme.surface)`; list-heavy or
  multi-column sheets open `.large` (or `[.large]`); only small pickers use `.medium`. Dividers use `Theme.hairline`.
- UserDefaults key `"linkupSpeechLanguage"`: "" = automatic (device), or a BCP-47 id "en-US" | "fr-FR" | "ar-MA" |
  "ar-SA". Settings writes it; dictation + voice mode TTS/STT read it (STT: `SFSpeechRecognizer(locale:)`, TTS: best
  installed `AVSpeechSynthesisVoice` for that language, preferring enhanced/premium quality; compare language codes
  with `-`/`_` normalised).

## Quality rules
- It must COMPILE first time on Xcode 26 / iOS 26 SDK: open and read every type/function you call; no invented APIs.
  iOS 26 APIs you may use: `.safeAreaBar(edge:alignment:spacing:content:)`, `.scrollEdgeEffectStyle(_:for:)`,
  `.glassEffect(_:in:)`, `GlassEffectContainer`, `.buttonStyle(.glass)`, `onScrollGeometryChange`, `onScrollPhaseChange`,
  `.presentationSizing`. Swift 5 mode: helpers called from background closures must be `nonisolated`.
- Never fix a bug by deleting a feature. Keep every existing public type/func signature other agents call
  (if you must change one, keep the old one working).
- Tap targets ≥ 44×44pt (`.contentShape(Rectangle())` + frame). Every icon-only button has `.accessibilityLabel`.
  Respect `@Environment(\.accessibilityReduceMotion)` for big/looping animations.
- Animations: state changes that move layout go through `withAnimation(.smooth(duration: 0.3))` / `.snappy`; no popping.
  Never make values jump at the first frame (interpolate with progress instead of `x > 0 ? a : b`).
- Performance while streaming: a view must not read observable properties it doesn't display (reading a property in
  `body` — even inside `.onChange(of:)` — subscribes the whole body). Push frequently-changing reads into small child views.
- Text never clips or wraps mid-word in pills/chips: `.lineLimit(1)` + `.fixedSize(horizontal: true, vertical: false)`
  or `.minimumScaleFactor`, and truncate the less important part first.
- No mock/fixture data in production paths (`DebugLaunch.screen != nil` is the only place fixtures may load).
- Errors visible to the user (`ui.toast` or inline), never silently swallowed.
- Comments only for non-obvious "why", matching the existing sparse style.

## When done
`git status` must show only your files. Commit with a short message. Your final message (≤ 40 lines): what you fixed
(grouped), findings you skipped as wrong (with reason), and "NEEDS OTHER FILE" items.
