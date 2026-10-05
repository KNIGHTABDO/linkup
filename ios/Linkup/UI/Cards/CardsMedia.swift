import SwiftUI

// STUBS (task cards-media): replace each with the real card view. Fields: bridge/linkup_bridge/cards.md

struct PersonCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "person") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct BookCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "book") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct MovieCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "movie") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct TvshowCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "tvshow") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct MusicCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "music") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct VideoCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "video") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct PodcastCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "podcast") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct NewsCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "news") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct DefinitionCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "definition") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct QuoteCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "quote") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct WikiCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "wiki") { Text(card.prettyText).font(Theme.mono(12)) } }
}
