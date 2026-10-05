Linkup messages: edit & resend, fork, hand off, pin, export, chat-mode look [shots]

## Your files (only these)
- `ios/Linkup/UI/Chat/MessageViews.swift`, `ios/Linkup/UI/Chat/ChatView.swift`, `ios/Linkup/UI/Chat/MarkdownParser.swift`,
  new files under `ios/Linkup/UI/Chat/`. (Keep `RichTextView(text:isStreaming:)` usage for text blocks and the
  `.environment(\.cardActions, …)` wrapper in AssistantTurnView exactly as they are.)

## Build
1. **User message actions** (context menu + swipe-free): Copy, **Edit & resend** (puts the text in the composer —
   post `NotificationCenter` name `Notification.Name("LinkupComposerSetText")` with the text as object; the composer
   task listens for it — also document it), **Resend**.
2. **Agent turn action row** additions: a "…" menu with **Fork conversation** (`try await store.fork(sessionId)` →
   `ui.currentSessionId = new.id`), **Continue with…** submenu listing the other agents with AgentLogo
   (`store.handoff(sessionId, to: agent, model: nil)` → open it), **Pin message** (local, UserDefaults set of turn ids
   per session; pinned turns get a small pin badge and appear in a "Pinned" strip at the top of the chat that scrolls
   to them), **Export chat** (Markdown of the whole transcript — user/agent text, tool titles as `> Used …` lines —
   shared via ShareLink as a .md file, and "Export as PDF" rendering the transcript text with `ImageRenderer`/
   UIGraphicsPDFRenderer into a PDF file).
3. **Chat-mode sessions** (`store.session(id)?.mode == "chat"`): hide the activity row while the turn is finished
   unless it has errors (rich chat should feel like a consumer assistant), show agent text in `Theme.serif(18)`, and
   show a subtle "Chat" badge in the empty-state greeting area. Cards render through RichTextView already.
4. **Streaming polish**: while text streams, keep it smooth — throttle re-parsing of markdown for very long texts
   (only re-render at most every 50 ms using a small @State-buffer driven by the TextBlock), and make sure the auto
   scroll stays glued to the bottom without jitter.
5. **Header of a turn**: tiny `AgentLogo(agent:size: 16)` + model name (from `turn.model` or session.model) in
   tertiaryText above the first answer of each turn.
