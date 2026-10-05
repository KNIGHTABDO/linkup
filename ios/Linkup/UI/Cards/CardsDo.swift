import SwiftUI

// STUBS (task cards-do): replace each with the real card view. Fields: bridge/linkup_bridge/cards.md

struct RecipeCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "recipe") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct ChecklistCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "checklist") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct StepsCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "steps") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct ProductCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "product") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct CodeCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "code") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct ContactCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "contact") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct EmailCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "email") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct TranslationCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "translation") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct MathCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "math") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct QuizCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "quiz") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct PaletteCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "palette") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct LinkCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "link") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct GalleryCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "gallery") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct CalloutCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "callout") { Text(card.prettyText).font(Theme.mono(12)) } }
}

struct FileCard: View {
    let card: JSONValue
    var body: some View { CardContainer(title: "file") { Text(card.prettyText).font(Theme.mono(12)) } }
}
