# Linkup 1.0 — Message rendering (assistant/user turns, markdown, code, export)

YOUR FILES: ios/Linkup/UI/Chat/MessageViews.swift, ios/Linkup/UI/Chat/MarkdownParser.swift,
ios/Linkup/UI/Chat/ChatExportHelper.swift, ios/Linkup/UI/Cards/RichTextView.swift, ios/Linkup/UI/Cards/CardSupport.swift,
ios/Linkup/UI/Cards/CardRegistry.swift. New files allowed in ios/Linkup/UI/Chat/.

The user says "the models responses are not well handled". Must-fix (AUDIT A, D, section 2, W2-D, raw sections):
1. HANG: the syntax highlighter's word branch accepts `$` but never consumes it → `$HOME` in a code block loops forever.
   `#` breaks without consuming. Unclosed string while streaming colours the whole block. Make every branch always
   advance; cap work per block; highlight off the main thread or cache by text.
2. Per-token cost: today each token re-parses the full markdown twice on the main thread (body + onChange → second
   body) and re-runs CardExtractor over the whole text; the parent AssistantTurnView reads `block.text` so the whole
   turn re-renders. Make a child view per text block that alone reads `block.text`; parse once per throttled update
   (~30–60 ms) and cache parsed blocks by text; only the last (growing) paragraph is re-parsed while streaming; the
   throttle must always end with the latest text (no stale capture). Turn views must not read `store.sessions`/
   `store.agents` in body — take plain values; `CardActions` stable (no new closure identity per body).
3. Markdown fidelity like the Claude app: headings, nested lists (bullets + numbers, proper indent and hanging
   wrap), task lists, blockquotes, tables (horizontally scrollable, header styling, consistent font), inline code,
   links (tappable), images, horizontal rules, code blocks (language label, copy button 44pt, horizontal scroll,
   one background colour — no seam), LaTeX-ish `$…$` left as text (never crash). Serif agent text, consistent line
   spacing and paragraph spacing. Text selection works (`.textSelection(.enabled)` on paragraphs).
4. RTL: user bubbles and each agent paragraph/list/table/blockquote laid out in its own direction
   (`text.dominantLayoutDirection`); Arabic text never left-aligned with misplaced punctuation.
5. User bubble actions: "Edit & resend" posts `.linkupComposerSetText` (composer agent observes it) ; "Resend" must
   keep attachments (send the original attachment refs back); copy; long text collapses with "Show more".
6. Assistant turn footer: action icons ≥ 44pt targets with labels; token label = input+output (cached only as detail);
   duration; model. Error turns (API errors, rate limits) render as a clear error row, not raw JSON.
7. Artifact cards appearing at stream end: reserve their space / animate in smoothly (no jump of the answer).
8. Chat-mode activity row: don't vanish abruptly at turn end (fade/collapse with animation).
9. ChatExport: fix AUDIT findings for it (lazy, off-main, no crash).
Also every other AUDIT finding naming your files.
