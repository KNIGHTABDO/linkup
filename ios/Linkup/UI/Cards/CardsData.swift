import SwiftUI

// STUBS (task cards-data): replace each with the real card view. Fields: bridge/linkup_bridge/cards.md

struct ChartCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "chart") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct StockCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "stock") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct CryptoCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "crypto") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct MetricsCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "metrics") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct TableCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "table") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct ComparisonCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "comparison") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct SportsCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "sports") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct PollCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "poll") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct ProgressCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "progress") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct TimelineCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "timeline") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct ConversionCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "conversion") { Text(card.prettyText).font(Theme.mono(12)) } }
}
