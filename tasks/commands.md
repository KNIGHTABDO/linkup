Linkup slash commands: "/" suggestions in the composer from the agent's live command list

## Your files (only these)
- create `ios/Linkup/UI/Composer/CommandSuggestions.swift`
- edit `ios/Linkup/UI/Composer/ComposerView.swift` ONLY to show the suggestions panel above the composer
  container and to insert the chosen command into the text field.

## What to build
When the composer text starts with "/" (and has no space yet), show a floating panel above the composer
(rounded 20, `Theme.surface`, hairline border, max height 300, scrollable, shadow) listing the current agent's
commands from `store.agent(agentId)?.commands` (`CommandInfo.name` / `.description`), filtered by the typed prefix
(case-insensitive, prefix matches first, then substring), max 50 rows. Row: "/name" in `Theme.sans(16, weight: .medium)`
ivory + description in `Theme.sans(13)` secondaryText (2 lines). Tap → replaces the text with "/name " and keeps
focus. Hide when no matches or the text no longer starts with "/". The agent id comes from the open session
(`store.session(id)?.agent`) or `ui.draftAgent` for a new chat (the composer already computes this — reuse it).
Animate in/out with `.smooth` and `.transition(.move(edge: .bottom).combined(with: .opacity))`.
For agents without commands (Antigravity, Hermes) show nothing.
