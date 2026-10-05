Linkup rich cards (Do): 15 card views for the chat [shots]

## Your files (only these)
- `ios/Linkup/UI/Cards/CardsDo.swift` — replace every stub with the real view, keeping the struct names exactly:
  RecipeCard, ChecklistCard, StepsCard, ProductCard, CodeCard, ContactCard, EmailCard, TranslationCard, MathCard, QuizCard, PaletteCard, LinkCard, GalleryCard, CalloutCard, FileCard (each `struct XCard: View { let card: JSONValue }`).
- you may add more files named `ios/Linkup/UI/Cards/CardsDo*.swift` for helpers (prefix private helper types with
  `Do` to avoid clashes with the other card tasks working in parallel).

## What these cards are
The agent writes ```linkup-card JSON blocks in its answers; `RichCardView` (already done) dispatches by `type` to your
views. Field names are in this spec (read the whole file): `bridge/linkup_bridge/cards.md` — your section:

### Do & learn
- `recipe` — title, image, time ("35 min"), servings, difficulty, ingredients [text], steps [text], tips [text]
- `checklist` — title, items [{text, done}] (the user can tick items in the app)
- `steps` — title, items [{title, detail, image}] (how-to guides)
- `product` — name, brand, price, currency, rating, reviews, images [url], url, specs {label: value}, summary
- `code` — language, title, code, explanation
- `contact` — name, role, company, phone, email, website, address, photo
- `email` — to, subject, body (the user can open it in Mail)
- `translation` — from (language), to (language), source, result, pronunciation, notes
- `math` — expression, result, steps [text]
- `quiz` — title, questions [{question, options [text], answer (index), explanation}]
- `palette` — title, colors [{hex, name}]
- `link` — url, title, description, image, site
- `gallery` — title, images [{url, caption}]
- `callout` — style ("info"|"tip"|"warning"|"success"|"error"), title, text
- `file` — name, url, size, kind

Every field is optional: render gracefully with whatever is present (no empty labels, no crashes). Read values with
the JSONValue helpers (`card["name"]?.string`, `card["rating"]?.double`, `card.strings("genres")`,
`card.objects("items")`, `card.url("website")`). Wrap each card in `CardContainer` (title = a short label such as
"Restaurant", symbol = a fitting SF Symbol) unless the design calls for a full-bleed image header — then build the same
rounded surface yourself (radius 20, Theme.surface, hairline border). Images: `AsyncImage` with a Theme.elevated
placeholder and graceful failure. Links: open with `@Environment(\.openURL)` or SFSafariViewController.
Cards must look premium, like Apple Maps / Apple Weather / Apple Music detail views compressed into a chat card:
generous spacing, SF Pro for UI text (Theme.sans), serif only for big titles where noted, rounded 12–16 inner
elements, subtle animations. Max width follows the chat column (don't hardcode screen widths).

## Card-specific design and REAL data
- `recipe`: hero image, time/servings/difficulty chips, ingredients with checkboxes (local state), numbered steps,
  tips callout; "Cook mode" button: full-screen sheet showing one step at a time, large type, keeps the screen on
  (`UIApplication.shared.isIdleTimerDisabled` while open).
- `checklist`: tappable rows with animated check circles (local state, persisted per card with @AppStorage keyed by a
  hash of the card JSON), progress "3 of 7".
- `steps`: numbered cards with optional images. `product`: image carousel, brand, name, price big, rating, specs grid,
  "View" link. `code`: syntax-highlighted mono block with language badge, Copy, and explanation.
- `contact`: avatar, name/role/company, action buttons (call, mail, website, maps) and "Save to Contacts" via
  `CNContactViewController` (ContactsUI, presented for a new unsaved contact — no permission needed).
- `email`: To/Subject/Body preview + "Open in Mail" (`mailto:` URL with percent-encoded subject/body) + Copy.
- `translation`: source/result with language labels, pronunciation, speak button (AVSpeechSynthesizer with the
  target language), copy.
- `math`: expression and result big (mono for math), steps list.
- `quiz`: one question at a time, tap an option → green/red feedback + explanation, score at the end, "Send my score"
  via cardActions.send.
- `palette`: color swatches (tap copies hex, toast-free: show "Copied" inline), names.
- `link`: rich link preview (image, title, description, site) → opens SFSafariViewController.
- `gallery`: grid of images (2 columns), tap → full-screen pager with zoom.
- `callout`: tinted box per style with SF Symbol (info.circle, lightbulb, exclamationmark.triangle, checkmark.seal,
  xmark.octagon). `file`: icon by kind, name, size, open via `ui.openArtifact` with an ArtifactRef built from url.

Add `#Preview` blocks? NO previews (they'd need sample data). Make sure it compiles with Swift 5 mode / iOS 26.
