Linkup rich cards (Media): 11 card views for the chat [shots]

## Your files (only these)
- `ios/Linkup/UI/Cards/CardsMedia.swift` — replace every stub with the real view, keeping the struct names exactly:
  PersonCard, BookCard, MovieCard, TvshowCard, MusicCard, VideoCard, PodcastCard, NewsCard, DefinitionCard, QuoteCard, WikiCard (each `struct XCard: View { let card: JSONValue }`).
- you may add more files named `ios/Linkup/UI/Cards/CardsMedia*.swift` for helpers (prefix private helper types with
  `Media` to avoid clashes with the other card tasks working in parallel).

## What these cards are
The agent writes ```linkup-card JSON blocks in its answers; `RichCardView` (already done) dispatches by `type` to your
views. Field names are in this spec (read the whole file): `bridge/linkup_bridge/cards.md` — your section:

### People, media, knowledge
- `person` — name, role, born, died, nationality, photo, summary, links [{title, url}]
- `book` — title, author, year, cover, rating, pages, summary, url
- `movie` — title, year, poster, rating, runtime, genres [text], director, cast [text], summary, trailer (YouTube URL)
- `tvshow` — title, years, poster, rating, seasons, network, genres [text], summary
- `music` — title, artist, album, year, artwork, duration, url
- `video` — title, url (YouTube or direct .mp4), thumbnail, channel, duration
- `podcast` — title, show, artwork, duration, date, url, summary
- `news` — title, items [{title, source, date, url, image, summary}]
- `definition` — term, phonetic, partOfSpeech, meanings [text], examples [text], origin
- `quote` — text, author, source
- `wiki` — title, image, summary, facts [{label, value}], url

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
- `person`/`book`/`movie`/`tvshow`/`music`/`podcast`: poster/photo left (2:3 for movie/tv/book, square for music/
  podcast, circle for person) with a soft blurred backdrop of the same image behind the card content; title (serif 20),
  meta line, genre chips, rating stars/score, summary (4 lines + "More"), links as glass capsules. `movie` with
  `trailer` → play button opening the YouTube video (see video).
- `video`: 16:9 thumbnail with a big play glass circle; YouTube URLs (youtube.com/watch?v=, youtu.be/, shorts/) play
  inline in a `WKWebView` loading `https://www.youtube-nocookie.com/embed/<id>?playsinline=1`
  (allowsInlineMediaPlayback = true); direct .mp4 → AVKit `VideoPlayer`. Thumbnail fallback
  `https://img.youtube.com/vi/<id>/hqdefault.jpg`.
- `news`: list of article rows (image 72 square right, source · relative date, title 2 lines semibold, summary 2 lines),
  tap → open URL in an in-app SFSafariViewController.
- `definition`: dictionary style (term serif 26, phonetic, part of speech italic, numbered meanings, examples in quotes).
- `quote`: big serif quotation with a large “ mark in accent, author below.
- `wiki`: image header, summary, facts as a 2-column grid of label/value, "Read more" link.

Add `#Preview` blocks? NO previews (they'd need sample data). Make sure it compiles with Swift 5 mode / iOS 26.
