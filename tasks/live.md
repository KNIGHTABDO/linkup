Linkup live: Live Activity + Dynamic Island, background live mode, done notifications, Home Screen widget [shots]

## Your files (only these)
- `project.yml` (add the widget extension target + Info.plist keys described below)
- new folder `ios/LinkupWidgets/` (the extension: widget bundle, Live Activity UI, Home Screen widget)
- new folder `ios/Linkup/Core/Live/` (app side: activity manager, background keep-alive, notifications)
- `ios/Linkup/App/LinkupApp.swift` ONLY to: create `let live = LiveManager(store: store, client: client)` in AppModel,
  inject `.environment(app.live)`, start it in `start()`, and forward scenePhase changes to it.

Look at how the sibling project added a widget extension: `/home/knight/Desktop/projects/knight-music/project.yml`
(target `KnightMusicWidgets`, `embed: true`, shared sources) and `/home/knight/Desktop/projects/knight-music/KnightMusicWidgets/`.
The app is installed with SideStore (free Apple ID): App Groups work (SideStore remaps them) — use
`group.com.knightabdo.linkup` with an entitlements file for BOTH targets (like Knight Music's), no push entitlements.

## Live Activity (ActivityKit)
- Shared attributes file in `ios/Linkup/Core/Live/LinkupActivityAttributes.swift` compiled into BOTH targets (add it to
  the widget target's sources in project.yml): `struct LinkupActivityAttributes: ActivityAttributes { var sessionId:
  String; var agent: String; var title: String; struct ContentState: Codable, Hashable { var phase: String; var line:
  String; var started: Date; var finished: Date?; var steps: Int; var tokens: Int } }`.
- Info.plist (main app): `NSSupportsLiveActivities: true`, `NSSupportsLiveActivitiesFrequentUpdates: true`.
- `LiveManager` (@MainActor @Observable): when a session's transcript `liveTurn` becomes non-nil, start an Activity
  (only while the app is active or within background live mode); update it at most every 1 s from
  `transcript.liveTurn` (`activityLine`, phase, count of tool parts, tokens); when the turn ends, update to "Done"
  (first ~80 chars of the answer) and end with `dismissalPolicy: .after(.now + 15 min)`.
  Observe changes by polling the active sessions' transcripts every 1 s with a Task (simple and robust).
- Widget UI (`ios/LinkupWidgets/`): lock screen banner (AgentLogo-like small orange spark drawn with SparkShape —
  re-implement a tiny spark Shape in the widget since the app's Theme isn't shared unless you add Theme.swift to the
  widget sources — do add `ios/Linkup/UI/Theme/Theme.swift` to the widget target sources), title, live activity line,
  elapsed timer `Text(timerInterval: started...Date.distantFuture, countsDown: false)`, steps; Dynamic Island compact
  (spark + elapsed), minimal (spark), expanded (title, line, timer, a "Stop" `Button(intent:)` using an AppIntent
  `StopTurnIntent(sessionId:)` that sets a flag in the App Group UserDefaults which LiveManager polls and turns into
  `store.interrupt`).
## Background live mode
iOS suspends the app (and its WebSocket) ~30 s after it leaves the screen. While ANY turn is running and the app goes to
the background, keep it alive with a silent audio loop: `AVAudioSession` category `.playback` with `.mixWithOthers`,
play a generated silent PCM buffer on loop with AVAudioEngine; stop as soon as no turn is running for 10 s, or after
60 minutes. Add `UIBackgroundModes: [audio]` to the app Info.plist in project.yml. Setting toggle key
"backgroundLiveMode" (UserDefaults, default true) — respect it.
## Notifications
Request notification permission on first send. When a turn ends while the app is not active, post a local
notification: title = session title, body = first line of the answer (or "Needs your approval" for permission
requests, with category actions "Allow" / "Deny" that call `store.answer` via the notification response handler —
set a `UNUserNotificationCenterDelegate` in LiveManager), userInfo sessionId; tapping opens that session
(`ui.currentSessionId`). Permission requests also trigger a notification while backgrounded.
## Home Screen widget
`UsageWidget` (systemSmall/systemMedium/accessoryCircular): Claude 5-hour and weekly rings + last session title. Data:
LiveManager writes a small JSON snapshot (claudePlan utilizations/resets, agy credits text, last session title/agent)
to App Group UserDefaults on every usage change and calls `WidgetCenter.shared.reloadAllTimelines()` (throttled to
once per 5 min); the widget reads it in its TimelineProvider (refresh policy .after 15 min).
