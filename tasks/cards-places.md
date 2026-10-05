Linkup rich cards (Places): 11 card views for the chat [shots]

## Your files (only these)
- `ios/Linkup/UI/Cards/CardsPlaces.swift` — replace every stub with the real view, keeping the struct names exactly:
  PlaceCard, PlacesCard, MapCard, RouteCard, WeatherCard, FlightCard, HotelCard, EventCard, CountdownCard, TimezonesCard, CurrencyCard (each `struct XCard: View { let card: JSONValue }`).
- you may add more files named `ios/Linkup/UI/Cards/CardsPlaces*.swift` for helpers (prefix private helper types with
  `Places` to avoid clashes with the other card tasks working in parallel).

## What these cards are
The agent writes ```linkup-card JSON blocks in its answers; `RichCardView` (already done) dispatches by `type` to your
views. Field names are in this spec (read the whole file): `bridge/linkup_bridge/cards.md` — your section:

### Places, travel, time
- `place` — name, category, address, lat, lon, rating (0–5), reviews, price ("$$"), photos [url], website, phone, hours, summary
- `places` — title, items [place objects as above] (restaurants, hotels, sights…)
- `map` — title, pins [{name, lat, lon, note}] (or pins with `query` instead of lat/lon), region ("Paris, France")
- `route` — from, to, mode ("driving"|"walking"|"transit"|"cycling"), duration ("25 min"), distance ("8.4 km"), steps [text]
- `weather` — location, lat, lon (the app fetches live weather itself when lat/lon are given), summary
- `flight` — airline, number, from {code, city, time}, to {code, city, time}, status, terminal, gate, duration
- `hotel` — name, address, lat, lon, stars, rating, price ("€180/night"), photos [url], amenities [text], website
- `event` — title, start, end, location, description, url
- `countdown` — title, target (ISO date-time), emoji
- `timezones` — items [{city, timezone (IANA, e.g. "Asia/Tokyo")}]
- `currency` — from ("USD"), to ("MAD"), amount, rate, date

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
- `place`/`places`/`hotel`: hero photo carousel (TabView .page, AsyncImage, 16:9, rounded 14) — when no photos,
  a MapKit snapshot instead; name (Theme.sans 19 semibold), category · price · ★ rating (reviews), address, hours
  (green "Open"/red "Closed" prefix if present). Embedded small `Map` (MapKit SwiftUI, height 160, rounded,
  non-interactive) with a marker: use lat/lon, else geocode `address`/`name` with `MKLocalSearch` (real Apple Maps
  data, no key) and show the found place. Buttons row (glass capsules): Directions (open Apple Maps:
  `MKMapItem.openInMaps` with the item), Call (`tel:`), Website (Link), Share. `places` = vertical list of compact
  rows (thumbnail 64, name, rating, category, distance-free), tap expands to the full place card in a sheet.
- `map`: interactive `Map` height 260 with all pins (geocode `query` pins via MKLocalSearch), labels, tap pin → callout,
  "Open in Maps" button. `route`: map with from/to markers (geocode), polyline via `MKDirections` (real route, matching
  mode; transit falls back to markers only), duration/distance chips, steps list collapsible.
- `weather`: fetch LIVE data from Open-Meteo (free, no key): `https://api.open-meteo.com/v1/forecast?latitude=..&longitude=..
  &current=temperature_2m,weather_code,wind_speed_10m,relative_humidity_2m&hourly=temperature_2m,weather_code
  &daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=7`
  (geocode `location` with `https://geocoding-api.open-meteo.com/v1/search?name=<city>&count=1` when no lat/lon). Big
  temperature, SF Symbol for the WMO weather code (map codes 0–99 to symbols), condition text, hourly strip (next 12 h),
  7-day rows with min/max bars. Gradient background tied to condition/daytime (inside the card only).
- `flight`: boarding-pass style (two big IATA codes with a plane line, times, status pill colored, terminal/gate).
- `event`: date badge (month/day), title, time range, location, "Add to Calendar" using EventKit
  (`EKEventStore().requestWriteOnlyAccessToEvents`) + NSCalendarsWriteOnlyAccessUsageDescription is NOT in Info.plist —
  so instead export an .ics file through ShareLink (works without permissions).
- `countdown`: live `TimelineView(.periodic(from: .now, by: 1))` days/hours/min/sec with numericText transitions.
- `timezones`: live clocks for each city (TimelineView), with day/night icon and offset vs local.
- `currency`: amount → converted; if `rate` missing fetch live from `https://open.er-api.com/v6/latest/<from>` (free).

Add `#Preview` blocks? NO previews (they'd need sample data). Make sure it compiles with Swift 5 mode / iOS 26.
