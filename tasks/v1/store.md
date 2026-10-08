# Linkup 1.0 — Store, networking, live, widgets (iOS Core)

YOUR FILES: everything under ios/Linkup/Core/ (Store/*, Net/*, Protocol/*, Live/*, Support/* — except don't remove the
helpers in Support/Notifications.swift and Support/TextDirection.swift), ios/Linkup/UI/Chat/PinnedStore.swift,
ios/LinkupWidgets/*.

Must-fix (see AUDIT A, section 5 "iOS networking", W2-C/D/F, "Sonnet: state/lifecycle" SWITCHING/STREAMING/GENERAL):
1. `transcript(for:)` is called from view bodies and synchronously reads+decodes the whole jsonl on the main thread
   (new JSONDecoder per line) → switching chats freezes. Return the Transcript immediately with `isLoading = true`,
   decode off the main actor (one shared decoder), apply in one batch, then `isLoading = false`. Events that arrive
   while loading must not be lost or applied out of order (buffer, then apply after the cached ones; dedupe by seq).
   Same for LiveManager's poll — never create/load transcripts for sessions that don't exist / weren't opened.
2. Implement `close(_:)` (stub exists): send `unsubscribe` (check bridge/linkup_bridge/server.py for the op name;
   if missing, say so — the bridge agent adds `unsubscribe {session}`), keep running sessions subscribed, LRU-evict
   transcripts beyond ~8. `open(_:)` idempotent (no double/triple subscribe from createChat + composer + ChatView).
   `resumePoints` still covers every subscribed session.
3. Event ingest: decode frames off the main thread where possible; batch cache appends (one file handle, flush every
   ~200 ms); append to disk only events `apply` accepted (no duplicate replay lines); tombstone deleted sessions so
   late events don't recreate files; delete pins of deleted sessions.
4. Unread: when `turn.end` arrives for the chat currently open (last `open`ed and not `close`d) and the app is
   active, send `read` so the open chat never shows an unread dot.
5. Transcript correctness: reset block dictionaries (texts/thinking/tools) on `turn.start` (agy reuses block ids
   per process); a `thinking.delta` without start creates a new block; `notice` with no live turn must still show
   (handoff target opened blank); a session that is not running per the bridge (hello/session status) but has a live
   turn locally → end it (bridge restart left "Working…" forever; forked streaming session zombie).
   Turn ids must be unique per session and stable (pins key on them).
6. Observation: don't make every view re-render per token. `lastSeq` may stay observable but make sure nothing
   unrelated changes per event (e.g. `sessions` array replaced only when a SessionInfo actually changed; sessions.json
   written debounced off-main). `upsert` skips equal values.
7. LinkupClient: ping failure/timeout (e.g. Wi-Fi→cellular) must trigger reconnect; reconnect backoff with jitter;
   path-prefixed bridge URLs (Tailscale Funnel `/linkup`) must resolve correctly for ws, files and upload.
8. JSONValue: `.int`/`.string` must never trap (NaN, inf, |n| ≥ 2^63, numeric strings); remove dead `from(Any)`.
9. ToolPresentation: "Running command" failure label becomes "Runn command failed" — fix the verb logic.
10. LiveManager: no 1s poll forever (event-driven, or only while something runs); end Live Activities of deleted /
    finished sessions; background keep-alive engages right after a send even before the first event.
11. Widgets / Live Activity: fix any AUDIT findings in LinkupWidgets/*.
Keep every public API other files call (`transcript(for:)`, `session(_:)`, `agent(_:)`, `open`, `create`, `send`,
`interrupt`, `answer`, `update`, `delete`, Extras wrappers…) source-compatible.
