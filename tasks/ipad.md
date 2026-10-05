Linkup iPad: three-column layout, dev-server preview [shots]

## Your files (only these): `ios/Linkup/UI/RootView.swift` (iPad branch only — keep the iPhone layout exactly as is) and new
files under `ios/Linkup/UI/Shell/`.
## Build
1. On iPad (horizontalSizeClass == .regular), use a three-column layout instead of the drawer: left = `SidebarView()`
   (fixed 320 pt, collapsible with the existing ≡ button), center = ChatView, right = an **inspector** panel (380 pt)
   that shows, when set, the Summary timeline of `ui.summaryTurn` (`SummarySheet(turn:)` content) or the open artifact
   (`ArtifactViewer(artifact:)`) instead of presenting them as sheets/covers (iPhone keeps sheets). A close button in
   the inspector header clears `ui.summaryTurn` / `ui.openArtifact`. Smooth spring animations, divider hairlines.
   Keyboard shortcuts: ⌘N new chat, ⌘K focus search (post a Notification "LinkupFocusSearch"), ⌘. stop
   (`store.interrupt(current)`), ⌘[ toggle sidebar.
2. **Dev-server preview**: create `ios/Linkup/UI/Shell/DevServerPreview.swift`: `DevServerPreview(port: Int)` — a
   WKWebView loading `client.resolve("/linkup/proxy/<port>/")` (the bridge reverse-proxies localhost dev servers), with a
   toolbar (back, forward, reload, open in Safari, close). Also `DevServerDetector`: a function
   `static func ports(in text: String) -> [Int]` that finds `http://localhost:<port>` / `127.0.0.1:<port>` /
   `0.0.0.0:<port>` in agent text or tool output. (Claude wires a "Preview" chip into tool output.)
