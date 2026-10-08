# Linkup 1.0 — Shell & chat screen (RootView, ChatView, drawer, top bar, iPad layout)

YOUR FILES: ios/Linkup/UI/RootView.swift, ios/Linkup/UI/Chat/ChatView.swift, ios/Linkup/UI/Shell/InspectorView.swift,
ios/Linkup/App/LinkupApp.swift, ios/Linkup/App/DebugLaunch.swift, ios/Linkup/UI/Theme/Theme.swift.
New files allowed in ios/Linkup/UI/Shell/.

This is the user's #1 complaint. Their real iPhone screenshot shows: the sidebar's "From your PC" header visible
behind the status bar while the drawer is CLOSED; chat text scrolling under the floating top bar with no blur and
colliding with the title; the composer see-through over cards; the scroll-to-bottom arrow on top of the send button.
They also say opening/closing the sidebar, going chat to chat and streaming are buggy.

Must-fix (root causes verified, see AUDIT W2-A/B/C/D and "Sonnet: layering/safe area", "Sonnet: state/lifecycle"):
1. Layering: root GeometryReader (RootView ~118) respects the safe area, so mainLayer is framed+clipped short of the
   status bar while SidebarView sits under it at full opacity. Make the main layer full-bleed and opaque
   (`Theme.background.ignoresSafeArea()`), keep keyboard avoidance, and make the sidebar layer invisible when closed
   (opacity tied to open progress, with a subtle parallax `offset(x: -40 * (1 - progress))`).
2. Top bar → `.safeAreaBar(edge: .top)` on the chat ScrollView (iOS 26) so the system scroll-edge blur works
   and the content inset is real. Delete every magic `.padding(.top, 70/60)` in ChatView. Pinned strip, connection
   pill and update banner live INSIDE that bar so they push content instead of overlapping it. Composer →
   `.safeAreaBar(edge: .bottom)` + `.scrollEdgeEffectStyle(.soft, for: .bottom)`. The scroll-to-bottom arrow sits
   above the composer (inside the bottom bar region), never over the send button; 44pt.
   Same treatment in the iPad layout.
3. ONE ComposerView instance: today greetingView and sessionView each build their own, and `.id(currentSessionId)`
   rebuilds the whole chat on every switch → keyboard drops, draft/dictation/voice mode lost. Hoist a single
   `ComposerView(sessionId:)` (its init stays `ComposerView(sessionId: String?)`; composer agent stores drafts per
   session internally) and remove the `.id(...)` remount; use `.task(id: sessionId)` to `store.open` the new id and
   `store.close` the previous one. Show a quiet loading state while `transcript.isLoading`, never the greeting for a
   session that has events. Existing chat opens already scrolled to the bottom (no visible jump).
4. Streaming performance: ChatView must not read `transcript.lastSeq` / `store.sessions` in its main body. Move
   auto-scroll into a tiny child view that observes the live turn; ONE scroll driver (not defaultScrollAnchor +
   throttled scrollTo fighting); `autoScrollTask` reset with `defer`; "user scrolled up" decided from
   `onScrollPhaseChange` (user interaction), not from content-height jumps; distance accounts for bottom insets.
   When returning to a chat that received events in background, land at the bottom.
5. Drawer (iPhone): edge-swipe zone must not be removed mid-gesture (today it disappears at the first pixel and the
   drawer freezes half open); close-drag must not lose its gesture when the scrim disappears; use `.global`
   coordinate space (local space inside the offset layer jitters); no 28pt full-height dead strip over the chat
   (use a narrow edge zone that doesn't eat taps/scrolls of content — e.g. only starts on horizontal-dominant drags
   from x < 20); velocity-aware spring on release; scrim/corner radius/shadow interpolate with progress
   (no pop on first frame); `.compositingGroup()` for drag performance; opening the drawer dismisses the keyboard;
   chat behind the open drawer is `accessibilityHidden`; `@GestureState`-style reset if a gesture is cancelled.
   Hamburger and the right-side button: matching 44pt glass circles, matching icon weights; correct
   accessibility labels ("Open sidebar", "New chat", "More").
6. New-chat screen shows the top-bar title/model like a session does (today hidden behind `if let session`).
7. Session deleted (by another device or here) while open → `ui.newChat()`; never stay in a dead chat.
8. Rotation / size-class change must not rebuild the chat and lose draft/scroll (one stable tree, vary layout).
9. iPad: sidebar 300–320, inspector collapses (or overlays) when the window is too narrow to keep a ≥ 500pt chat
   column; Slide Over / narrow Split View uses the iPhone drawer; reading width capped ~720 and centred; top bar
   aligned with the chat column; ⌘K posts `.linkupFocusSearch`.
10. Toast: use `ui.toastID` for the timer. The RootView-level sheets: make sure presenting a sheet from the drawer
    closes the drawer first; summary/artifact sheets don't clip (.large where content is long).
11. DebugLaunch: fixture launch must NOT persist settings (serverURL/token) to UserDefaults/Keychain or write fixture
    events into the real cache — keep screenshots working (`-LinkupScreen <name>` in scripts/screens.sh; keep every
    screen name working). Add an `artifact` screen that really shows the artifact viewer.
12. Theme: unify the two code-block blacks into one token; add tokens other agents may need only if missing
    (don't rename existing ones). Greeting copy: no "night owl"; use a calm time-of-day greeting.
Also fix every other AUDIT finding naming your files (navigation section 1, W2-B, W2-C, W2-E items for these files,
a11y/RTL items for these files).
