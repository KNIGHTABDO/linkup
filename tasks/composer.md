Linkup composer: glass input, model/agent picker, attachments, dictation [shots]

## Your files (only these)
- `ios/Linkup/UI/Composer/ComposerView.swift` (replace stubs; keep `ComposerView(sessionId: String?)` and
  `ModelPickerSheet(sessionId: String?)`)
- you may add more files under `ios/Linkup/UI/Composer/`

## ComposerView (bottom of the chat, exactly like the Claude iOS composer)
A rounded container (radius `Theme.composerRadius`, glass: `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28))`)
with horizontal margin 12, bottom padding 8:
1. Attachment strip (only when there are attachments): horizontal thumbnails 60pt (images) / capsules (files) with
   an `xmark.circle.fill` remove button, and an upload progress spinner while uploading.
2. Multiline `TextField(placeholder, text:, axis: .vertical)` `Theme.sans(17)`, 1…8 lines. Placeholder:
   new chat → "Chat with \(agent name)"; open session → "Reply to \(agent name)".
3. Bottom row: `+` glass circle 44 (Menu: "Photos" → PhotosPicker (multiple), "Camera" → camera sheet
   (UIImagePickerController wrapped), "Files" → `.fileImporter` any type), then the **model pill**: glass capsule
   with model display name (Theme.sans 15, ivory) and effort in secondaryText e.g. "Sonnet 5.5 Medium" → opens
   `ui.isShowingModelPicker = true`; Spacer; mic glass circle 44 (dictation, see below); and the primary button:
   white circle 44 — when the agent is working (`store.transcript(for:).isWorking`) a black "stop.fill" square
   (→ `store.interrupt(id)`), otherwise when text/attachments non-empty an "arrow.up" (send), otherwise a "waveform"
   icon (starts dictation too).
4. **Send**: trim text; if `sessionId == nil` create the session first:
   `let s = try await store.create(agent: ui.draftAgent, model: ui.draftModel, effort: ui.draftEffort, cwd: ui.draftProject)`
   then `ui.currentSessionId = s.id`, `store.open(s.id)`, then `store.send(text, to: s.id, attachments: uploaded)`.
   Attachments: upload each picked item first with `client.upload(data:name:mime:)` (returns a dict with "path",
   "name", "mime", "url"); pass those dicts as `attachments`. Clear the field immediately, haptic, errors → `ui.toast`.
   Disable send while uploading. Keyboard: return inserts newline; send via button.
5. Model label source: for an open session use `store.session(id)` (agent, model, effort); for a new chat use
   `ui.draftAgent/draftModel/draftEffort`; display name from `store.agent(agentId)?.model(modelId)?.name` (fall back
   to the raw id, and to the agent's `defaultModel`). Effort shown capitalized.
6. **Dictation**: tap mic → live speech-to-text into the field using `SFSpeechRecognizer` + `AVAudioEngine`
   (request permissions; on-device if available); mic button turns accent and pulses while listening; tap again to
   stop. Handle denial with a toast. Put the recognizer in its own small class in your files (`ComposerDictation`).

## ModelPickerSheet
`.presentationDetents([.medium, .large])`, background Theme.surface, glass xmark close, title "Model".
- Top: segmented agent switcher (three glass capsules: Claude Code / Antigravity / Hermes with `AgentKind.symbol`),
  disabled + "Offline" caption when `agent.available == false` (show `agent.error`). For an open session the agent
  can't change (show it fixed); for a new chat it sets `ui.draftAgent` and resets draftModel to the agent's default.
- List of `agent.models` (live from the agent): name (Theme.sans 17), description (secondaryText 14), checkmark on the
  selected one. Selecting: open session → `store.update(id, model:)`; new chat → `ui.draftModel = model.id`.
- If the selected model has `efforts` non-empty: an "Effort" row of capsules (Low/Medium/High/Xhigh/Max) →
  `store.update(id, effort:)` / `ui.draftEffort`.
- Claude only: "Permissions" picker of `agent.permissionModes` (labels: default → "Ask before acting",
  acceptEdits → "Auto-accept edits", plan → "Plan only", bypassPermissions → "Full access") → `store.update(id, permissionMode:)`
  for a session, else stored in UserDefaults key "draftPermissionMode" (read it at create time and pass permissionMode).
- New chat only: "Project" row (folder icon + project name) → list from `store.projects` (call `await store.loadProjects()`
  in `.task`) → `ui.draftProject = path`.
- A footer with the account: `agent.accountLabel` (e.g. "Claude Pro") and a link button "Usage" → `ui.isShowingUsage = true`.
- Pull to refresh → `await store.refreshCatalog(force: true)`.
