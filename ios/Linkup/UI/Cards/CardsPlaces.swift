import SwiftUI

// STUBS (task cards-places): replace each with the real card view. Fields: bridge/linkup_bridge/cards.md

struct PlaceCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "place") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct PlacesCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "places") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct MapCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "map") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct RouteCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "route") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct WeatherCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "weather") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct FlightCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "flight") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct HotelCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "hotel") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct EventCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "event") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct CountdownCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "countdown") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct TimezonesCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "timezones") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct CurrencyCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "currency") { Text(card.prettyText).font(Theme.mono(12)) } }
}
