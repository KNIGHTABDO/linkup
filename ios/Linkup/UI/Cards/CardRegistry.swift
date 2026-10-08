import SwiftUI

/// Maps a card's `type` to its view (all types: bridge/linkup_bridge/cards.md).
struct RichCardView: View {
    let card: JSONValue

    var body: some View {
        switch card["type"]?.string ?? "" {
        case "place": PlaceCard(card: card)
        case "places": PlacesCard(card: card)
        case "map": MapCard(card: card)
        case "route": RouteCard(card: card)
        case "weather": WeatherCard(card: card)
        case "flight": FlightCard(card: card)
        case "hotel": HotelCard(card: card)
        case "event": EventCard(card: card)
        case "countdown": CountdownCard(card: card)
        case "timezones": TimezonesCard(card: card)
        case "currency": CurrencyCard(card: card)
        case "person": PersonCard(card: card)
        case "book": BookCard(card: card)
        case "movie": MovieCard(card: card)
        case "tvshow": TvshowCard(card: card)
        case "music": MusicCard(card: card)
        case "video": VideoCard(card: card)
        case "podcast": PodcastCard(card: card)
        case "news": NewsCard(card: card)
        case "definition": DefinitionCard(card: card)
        case "quote": QuoteCard(card: card)
        case "wiki": WikiCard(card: card)
        case "chart": ChartCard(card: card)
        case "stock": StockCard(card: card)
        case "crypto": CryptoCard(card: card)
        case "metrics": MetricsCard(card: card)
        case "table": TableCard(card: card)
        case "comparison": ComparisonCard(card: card)
        case "sports": SportsCard(card: card)
        case "poll": PollCard(card: card)
        case "progress": ProgressCard(card: card)
        case "timeline": TimelineCard(card: card)
        case "conversion": ConversionCard(card: card)
        case "recipe": RecipeCard(card: card)
        case "checklist": ChecklistCard(card: card)
        case "steps": StepsCard(card: card)
        case "product": ProductCard(card: card)
        case "code": CodeCard(card: card)
        case "contact": ContactCard(card: card)
        case "email": EmailCard(card: card)
        case "translation": TranslationCard(card: card)
        case "math": MathCard(card: card)
        case "quiz": QuizCard(card: card)
        case "palette": PaletteCard(card: card)
        case "link": LinkCard(card: card)
        case "gallery": GalleryCard(card: card)
        case "callout": CalloutCard(card: card)
        case "file": FileCard(card: card)
        default:
            CardContainer(title: "Unsupported card", symbol: "questionmark.square.dashed") {
                Text("This card type (\(card["type"]?.string ?? "unknown")) is not supported in this version of Linkup.")
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}
