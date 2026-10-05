Linkup composer v2: command cards for every agent, voice mode, prompt library, chat-mode toggle [shots]

## Your files (only these)
- `ios/Linkup/UI/Composer/ComposerView.swift`, `ios/Linkup/UI/Composer/CommandSuggestions.swift`,
  `ios/Linkup/UI/Composer/ComposerDictation.swift`, and new files under `ios/Linkup/UI/Composer/`.

## 1. Slash command picker with "special cards" (all agents)
Each agent's catalog now carries `commands` (CommandInfo name/description; the bridge adds Antigravity's and Hermes'
commands/skills too). Replace the simple list with a beautiful picker:
- Typing "/" opens it (and a new "/" glass button in the composer's bottom row opens it too).
- Layout: a floating sheet-like panel above the composer (max height 55% screen), search field at top, then sections
  by kind when the command dict has `kind` — note CommandInfo has only name/description: add the optional field
  yourself by decoding `kind` from `store.agent(id)?.commands`… CommandInfo is in Core (don't edit Core) — instead
  classify locally: names that look like `plugin:skill` → "Plugins", names matching the agent's known skills (contain
  "-" and long description) → "Skills", others → "Commands".
- Each command is a **card**: rounded 16, Theme.elevated, leading 36pt tile with a symbol picked by keywords
  (review→checkmark.seal, deploy→paperplane, test→testtube.2, design/ui→paintbrush, video→film, image→photo,
  ios→iphone, git/pr→arrow.triangle.branch, docs→doc.text, default→command), the agent's `AgentLogo` small badge,
  "/name" semibold, description 2 lines secondary. Grid of 2 columns on iPad, 1 on iPhone. Recently used commands
  (UserDefaults per agent) pinned at the top as horizontal chips.
- Choosing a command inserts a **token chip** at the start of the composer ("/name" capsule tinted accent with an x to
  remove) followed by free text; on send the text becomes "/name <rest>".
## 2. Voice mode (the white waveform button when the field is empty)
Full-screen voice sheet (dark, big animated orb using SparkView/a pulsing circle that reacts to microphone level
via AVAudioEngine input tap RMS): listens with `ComposerDictation`, shows the live transcript; when the user stops
talking for 1.5 s (or taps "Send"), sends it (creating the session if needed, like the normal send), then shows
"Thinking…", streams the agent's reply text from the transcript (`store.transcript(for:)` → last turn's text) and
speaks it with `AVSpeechSynthesizer` (natural voice: pick the best available `AVSpeechSynthesisVoice` for the
language, premium/enhanced quality first), skipping code blocks and ```linkup-card blocks. Then listens again
(continuous conversation) until the user taps the X. Interrupt speaking when the user taps the orb.
## 3. Prompt library
A row of horizontally scrolling glass chips above the text field when it's empty and focused: the user's saved
prompts (UserDefaults JSON list of {title, text}); "+" chip saves the current text as a prompt (alert for title);
long-press a chip to delete. Tap inserts the text.
## 4. New chat: Agent / Chat mode
For a NEW chat only (sessionId == nil) show a small segmented glass control above the composer: "Agent" (normal)
and "Chat" (rich cards: maps, weather, recipes…). Persist the choice in UserDefaults "draftMode". When "Chat" is
selected, sending creates the session with `store.createChat(agent: ui.draftAgent, model: ui.draftModel)` instead of
`store.create(...)`. Placeholder in chat mode: "Ask anything — places, weather, recipes…".
