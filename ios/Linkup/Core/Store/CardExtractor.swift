import Foundation

/// Splits agent text into markdown and rich cards (```linkup-card {json}``` fences, see bridge/linkup_bridge/cards.md).
/// Safe on half-streamed text: an unfinished card becomes `.pendingCard` until its closing fence arrives.
enum RichSegment: Identifiable {
    case markdown(id: Int, String)
    case card(id: Int, JSONValue)
    case pendingCard(id: Int)
    /// A fence that closed but isn't valid JSON: shown as plain code so nothing is lost.
    case invalidCard(id: Int, String)

    var id: Int {
        switch self {
        case .markdown(let id, _), .card(let id, _), .pendingCard(let id), .invalidCard(let id, _): id
        }
    }
}

enum CardExtractor {
    static let fence = "```linkup-card"

    static func segments(_ text: String) -> [RichSegment] {
        guard text.contains(fence) else { return [.markdown(id: 0, text)] }
        var out: [RichSegment] = []
        var rest = Substring(text)
        var index = 0
        while let open = rest.range(of: fence) {
            let before = String(rest[..<open.lowerBound])
            if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                out.append(.markdown(id: index, before)); index += 1
            }
            let afterOpen = rest[open.upperBound...]
            guard let close = afterOpen.range(of: "```") else {
                out.append(.pendingCard(id: index))
                return out
            }
            let body = afterOpen[..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = body.data(using: .utf8), let json = try? JSONDecoder().decode(JSONValue.self, from: data),
               json["type"]?.string != nil {
                out.append(.card(id: index, json))
            } else {
                out.append(.invalidCard(id: index, body))
            }
            index += 1
            rest = afterOpen[close.upperBound...]
        }
        if !rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(.markdown(id: index, String(rest))) }
        return out
    }
}
