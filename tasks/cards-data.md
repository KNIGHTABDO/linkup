Linkup rich cards (Data): 11 card views for the chat [shots]

## Your files (only these)
- `ios/Linkup/UI/Cards/CardsData.swift` — replace every stub with the real view, keeping the struct names exactly:
  ChartCard, StockCard, CryptoCard, MetricsCard, TableCard, ComparisonCard, SportsCard, PollCard, ProgressCard, TimelineCard, ConversionCard (each `struct XCard: View { let card: JSONValue }`).
- you may add more files named `ios/Linkup/UI/Cards/CardsData*.swift` for helpers (prefix private helper types with
  `Data` to avoid clashes with the other card tasks working in parallel).

## What these cards are
The agent writes ```linkup-card JSON blocks in its answers; `RichCardView` (already done) dispatches by `type` to your
views. Field names are in this spec (read the whole file): `bridge/linkup_bridge/cards.md` — your section:

### Numbers, data, comparisons
- `chart` — title, kind ("line"|"bar"|"pie"|"area"), unit, series [{name, points [{x, y}]}] (x = label or ISO date, y = number)
- `stock` — symbol, name, price, change, changePercent, currency, points [{x, y}] (recent prices), marketCap, exchange
- `crypto` — symbol, name, price, change24h, changePercent24h, currency, points [{x, y}]
- `metrics` — title, items [{label, value, delta, trend ("up"|"down"|"flat")}]
- `table` — title, columns [text], rows [[text]]
- `comparison` — title, items [{name, image, price, rating, pros [text], cons [text], highlights {label: value}}]
- `sports` — league, status ("Live 67'"|"Final"|"Today 20:00"), home {name, logo, score}, away {name, logo, score}, events [text]
- `poll` — question, options [text] (the user votes in the app; the vote is sent back as a message)
- `progress` — title, items [{label, value (0–1), note}]
- `timeline` — title, items [{date, title, detail}]
- `conversion` — from {value, unit}, to {value, unit}, formula

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
- `chart`: Swift Charts (`import Charts`): LineMark/BarMark/AreaMark/SectorMark (pie/donut) per `kind`, one color per
  series (accent, then #7FB0F5, #6FB37E, #E8B04B, #B48CF2), x as dates when ISO else categories, legend, unit on axis,
  tap/drag selection showing the value (chartXSelection).
- `stock`/`crypto`: symbol + name, big price, change (green/red with arrow), sparkline/area chart of points with
  gradient fill, stats row (market cap, exchange). Do NOT fetch market data yourself (no key-free reliable source);
  use the card's numbers.
- `metrics`: 2-column grid of KPI tiles (value big rounded font with numericText, delta colored with trend arrow).
- `table`: horizontally scrollable Grid with header row, zebra rows, numbers right-aligned; copy as CSV in a menu.
- `comparison`: horizontally scrolling columns (one per item: image, name, price, rating, highlights rows aligned by
  label, pros ✓ green / cons ✗ red).
- `sports`: scoreboard (team logos AsyncImage or initials circles, big scores, status pill red "LIVE" pulsing when
  status contains "Live"), events list.
- `poll`: options as tappable bars; tapping sends the vote with `@Environment(\.cardActions)`
  `actions.send("I vote: <option>")` and shows a checkmark (local state).
- `progress`: labeled progress bars/rings. `timeline`: vertical timeline with dots and connecting line.
- `conversion`: from → to big numbers with unit labels and the formula.

Add `#Preview` blocks? NO previews (they'd need sample data). Make sure it compiles with Swift 5 mode / iOS 26.
