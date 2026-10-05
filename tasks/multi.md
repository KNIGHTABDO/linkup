Linkup multi-agent: Running now dashboard, Compare, hand-off picker [shots]

## Your files (only these): new files under `ios/Linkup/UI/Multi/`.
## Views (Claude wires entry points)
1. `RunningNowView()`: every session with `isRunning` (from `store.sessions`) as live cards: AgentLogo, title, project,
   the live activity line from `store.transcript(for:).liveTurn?.activityLine` (call `store.open(id)` in `.task` for each
   running session so its stream flows), elapsed timer (TimelineView), steps count, a Stop glass button
   (`store.interrupt`), tap → open the session (`ui.currentSessionId = id`, dismiss). Empty state: "Nothing running".
   Also "Recently finished" (last 5 sessions updated in the past hour that aren't running).
2. `CompareSheet()`: prompt TextEditor, agent toggles (3 AgentLogo chips, all on), optional project picker from
   `store.projects`; "Run on all" → `let sessions = try await store.compare(prompt, agents:, cwd:)` → push
   `CompareView(sessionIds:)`.
3. `CompareView(sessionIds: [String])`: side by side columns on iPad (HStack), paged TabView on iPhone with a top
   segmented header showing each agent's logo + live status (working dots / done ✓ / duration); each column renders
   that session's transcript compactly: the latest assistant turn's text via `RichTextView(text:isStreaming:)` and its
   activity line; tokens/duration footer; "Open" button per column → `ui.currentSessionId`.
4. `HandoffSheet(sessionId: String)`: choose the target agent (cards with AgentLogo, name, description of strengths:
   Claude Code "Best for code and long tasks", Antigravity "Gemini models, image generation, browser", Hermes "Your
   personal agent with memory"), model picker from that agent's catalog, "Continue with <agent>" → `store.handoff` →
   open it.
