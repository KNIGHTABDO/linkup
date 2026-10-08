# Linkup 1.0 — Composer, model picker, slash commands, dictation, voice mode

YOUR FILES: ios/Linkup/UI/Composer/* (ComposerView, CommandSuggestions, ComposerAttachment, ComposerDictation,
ComposerPromptLibrary, VoiceModeView), ios/Linkup/UI/Usage/UsageRing.swift. New files allowed in ios/Linkup/UI/Composer/.

Must-fix (AUDIT section 4, W2-A 5, W2-C 23/24/31/32, W2-D 42, W2-E 49, W2-F 61/63, small-details, RTL/a11y):
1. Model pill: never wraps ("Mediu/m" today) — lineLimit(1), fixedSize, model name truncates before effort; the 16pt
   UsageRingBadge drawn as an empty circle looks like a stray spinner: only show the ring when there is real usage
   data, sized/padded so the pill isn't crowded; pill 44pt tall. Agy/Hermes never show a bogus effort from
   `ui.draftEffort` (only show effort the agent supports). Model sheet: `.large` when the list is long, effort chips
   show a selected state (accent fill + check), agent switcher in an existing session either works (start a new
   chat with that agent via ui.newChat() + draft settings) or is clearly disabled — never silently does nothing.
2. Drafts per session: ChatView now keeps ONE ComposerView alive across chat switches (its `sessionId` changes).
   Keep text + attachments per session id (and for the new-chat screen) in a small private @Observable store in
   your files; switching chats swaps the draft; keyboard focus is kept. `@State var dictation = ComposerDictation()`
   is re-evaluated each init → make it lazy.
3. Send flow: no Send→Voice→Stop flashing (show Stop as soon as a send is in flight, until the bridge reports
   running/idle); no accidental Voice Mode on a double tap (debounce, and voice button only when idle and empty);
   first message in a new chat: lock the composer while `create` runs, clear text only on success, keep it and toast
   on failure, a second tap doesn't create a second session, and if the user switched chats meanwhile don't yank
   them back (only `ui.openSession(new)` if still on the new-chat screen). Don't call `store.open` yourself after
   create (ChatView does). Optimistic: haptic + immediate visual feedback.
4. Observe `.linkupComposerSetText` → put text in the composer, focus it.
5. Voice mode: it lives in the composer's fullScreenCover → must survive the session being created by the first
   utterance; close button/agent pill not under the Dynamic Island (respect safe area); landscape doesn't overflow;
   short replies ("Done.") are spoken; streaming markdown links don't make speech skip; TTS voice + STT locale from
   `"linkupSpeechLanguage"` (see _common); orb scale animation conflict; announcements for VoiceOver.
6. Dictation: locale from `"linkupSpeechLanguage"` (fallback device); handles Arabic.
7. Layout: typing `/` must not push composer/suggestions off the top (cap suggestion height, scroll inside);
   landscape: composer max height ~40% of screen; prompt library alerts without focus loops; attachments: camera
   images downscaled (~2048px) and encoded off the main thread; remove-attachment 44pt target; upload tasks tied to
   the draft (not lost on switch).
8. Visual: one GlassEffectContainer for the composer controls; consistent icon sizes (19pt medium); composer
   container background solid enough that chat text doesn't show through (glass only on controls);
   RTL: the text field follows the typed text's direction; all icon buttons labelled.
Also every other AUDIT finding naming your files.
