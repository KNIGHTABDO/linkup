Linkup shell: root layout, drawer, top bar and sheet routing [shots]

## Your files (only these)
- `ios/Linkup/UI/RootView.swift` (replace the stub; keep the type name `RootView`)

## Build
RootView is the whole app frame, like the Claude iOS app:
1. **Main layer**: `ChatView(sessionId: ui.currentSessionId)` filling the screen on `Theme.background`.
   Use `.id(ui.currentSessionId ?? "new")` so switching sessions resets scroll state.
2. **Top bar overlay** (not a navigation bar) pinned to the top safe area, horizontal padding 16:
   - left: glass circle 48pt with `line.3.horizontal` → opens the sidebar (`withAnimation(.smooth) { ui.isSidebarOpen = true }`).
   - right: glass capsule (height 48) containing two buttons: `plus.bubble.fill` (new chat: `ui.newChat()`) and
     `ellipsis` (a SwiftUI `Menu` with: "Usage" → ui.isShowingUsage = true, "Settings" → ui.isShowingSettings = true,
     when a session is open also "Rename" (alert with TextField → store.update(id, title:)), "Pin"/"Unpin"
     (store.update(id, pinned:)), "Delete" (destructive, confirmationDialog → store.delete(id); ui.newChat())).
   - Between them, when a session is open, a small centered title: session title (Theme.sans 15 semibold, 1 line)
     and under it the agent name + project (Theme.sans 12, secondaryText), tappable to open the model picker
     (`ui.isShowingModelPicker = true`).
   - A connection pill under the top bar ONLY when `client.state` is not `.connected` (and not in screenshot mode
     with fixtures — i.e. hide when `store.sessions` is non-empty AND state is notConfigured… simpler: show when
     state is `.connecting` or `.offline`): small glass capsule with a dot + `client.state.label`, tap → `client.connect()`.
   Use `GlassEffectContainer` around the top bar items. Real `.glassEffect(.regular.interactive(), in: .circle/.capsule)`.
3. **Drawer**: when `ui.isSidebarOpen`, the main layer slides right by ~82% of the width (max 340pt on iPad stays
   docked? keep it simple: slide on all devices) and dims (black 35% overlay that closes on tap); `SidebarView()`
   sits underneath on the left at that width. Support an edge-swipe from the left edge to open and a swipe left on
   the dimmed layer to close (DragGesture, rubber-band, spring). Spring `.smooth(duration: 0.35)`.
4. **Sheets / covers** routed from UIState (each `.sheet(isPresented:)` with the matching binding):
   - `ui.isShowingSettings` → `SettingsView()`
   - `ui.isShowingConnect` → `ConnectView()` (`.interactiveDismissDisabled(!settings.isConfigured)`)
   - `ui.isShowingUsage` → `UsageView()`
   - `ui.isShowingModelPicker` → `ModelPickerSheet(sessionId: ui.currentSessionId)`
   - `ui.summaryTurn` (item binding: wrap in an Identifiable via `.sheet(item:)` on a computed binding) → `SummarySheet(turn:)`
   - `ui.openArtifact` → `.fullScreenCover(item:)` → `ArtifactViewer(artifact:)`
5. **Toast**: when `ui.toast` is set, a glass capsule at the top with the text, auto-hides after 2.5 s.
   Also show `store.lastError` as a toast (then `store.clearError()`).
6. On appear: if `client.state == .notConfigured && !settings.isConfigured` keep the connect sheet up (AppModel does
   that already — just respect `ui.isShowingConnect`).
