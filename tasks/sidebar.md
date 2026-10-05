Linkup sidebar: drawer with agents, pinned, recents, search, new session, PC history [shots]

## Your files (only these)
- `ios/Linkup/UI/Sidebar/SidebarView.swift` (replace stubs; keep `SidebarView()` and `HistoryImportSheet()`)
- you may add more files under `ios/Linkup/UI/Sidebar/`

## SidebarView (Claude iOS drawer, see screenshot: "Claude" title, rows with line icons, sections)
Full height, background `Theme.background` (slightly darker feel is fine), padding 20, inside a ScrollView:
1. Header: "Linkup" in `Theme.serif(30, weight: .medium)` + a glass circle search button (magnifyingglass) that
   toggles a search field (filters sessions by title/preview, case-insensitive).
2. Top rows (icon 22pt line style + Theme.sans(19)): "Claude Code", "Antigravity", "Hermes" — one per agent using
   `AgentKind.symbol`, each with a small status dot (green if `store.agent(id)?.available == true`, grey otherwise).
   Tapping one starts a new chat with that agent: `ui.draftAgent = id; ui.draftModel = nil; ui.newChat()`.
   Then "From your PC" (icon `desktopcomputer`) → presents `HistoryImportSheet()`.
3. "Pinned" section (Theme.sans 15 secondaryText header) with pinned sessions, then "Recents" with the rest
   (store.sessions is already sorted). Group recents by "Today", "Yesterday", "Previous 7 days", "Older".
   Session row: agent symbol icon (tinted `Theme.agentColor(agent)`), title (Theme.sans 18, 1 line), trailing:
   a blue dot (#3A82F7) when `hasUnread`, or a small spinning ProgressView when `isRunning`. Selected session row has
   a subtle `Theme.elevated` rounded background. Tap → `ui.currentSessionId = s.id; ui.isSidebarOpen = false`.
   Swipe / context menu: Pin/Unpin (`store.update(id, pinned:)`), Rename (alert), Delete (destructive).
4. Bottom bar (overlaid at the bottom with a fade): a glass circle avatar with the first letter of the server name
   (`client.serverName`, else "L") → `ui.isShowingSettings = true`, and a big white capsule "+ New session"
   (black text, Theme.sans 18 medium) → `ui.newChat()`.
5. Connection footer line above the bottom bar: dot + `client.state.label` + latency "· 42 ms" when connected.

## HistoryImportSheet ("From your PC")
Lists Claude Code sessions started on the PC: `try await store.loadHistory()` in `.task` (show ProgressView,
errors inline). Rows: title (2 lines), project folder name from `cwd`, relative date from `updated`, message count.
Search field on top. Tap → `let s = try await store.importHistory(item)` → `ui.currentSessionId = s.id`, close the
sheet and the sidebar. Title "Continue from your PC", glass xmark close, Theme.surface background.
