import Foundation
import SwiftUI

/// Shared cached date and number formatters for Linkup rich cards.
/// Avoids allocating ISO8601DateFormatter / DateFormatter per view render or list cell.
enum CardDates {
    private static let isoWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoStandard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoDateOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = .current   // a bare date is a local calendar day, not UTC midnight
        return f
    }()

    private static let simpleDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let fallbackFormatters: [DateFormatter] = {
        let patterns = [
            "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
            "MMM d, yyyy",
            "MMMM d, yyyy"
        ]
        return patterns.map { pattern in
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = pattern
            return df
        }
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private static let monthAbbrFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM")
        return f
    }()

    private static let dayMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f
    }()

    private static let shortTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f
    }()

    static func parse(_ raw: String?) -> Date? {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if let d = isoWithFractional.date(from: s) { return d }
        if let d = isoStandard.date(from: s) { return d }
        if let d = isoDateOnly.date(from: s) { return d }
        if let d = simpleDateFormatter.date(from: s) { return d }
        for f in fallbackFormatters {
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    static func formatRelative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    static func monthAbbreviation(from date: Date) -> String {
        monthAbbrFormatter.string(from: date).uppercased()
    }

    static func formatDayMonth(_ date: Date) -> String {
        dayMonthFormatter.string(from: date)
    }

    static func formatTime(_ date: Date, timeZone: TimeZone) -> String {
        let df = DateFormatter()
        df.timeZone = timeZone
        df.dateFormat = "HH:mm:ss"
        return df.string(from: date)
    }
}

// MARK: - Safe Numeric & Conversion Helpers

/// Never crash on odd data: guard against NaN, Infinity, and integer overflow.
func cardSafeInt(_ val: Double?, clampedTo: ClosedRange<Int>? = nil) -> Int? {
    guard let val, val.isFinite, !val.isNaN else { return nil }
    guard abs(val) < 9.0e18 else { return nil }
    let intVal = Int(val)
    if let range = clampedTo {
        return min(max(intVal, range.lowerBound), range.upperBound)
    }
    return intVal
}

func cardSafeDouble(_ val: Double?) -> Double? {
    guard let val, val.isFinite, !val.isNaN else { return nil }
    return val
}

func cardFormatNumber(_ num: Double) -> String {
    guard num.isFinite, !num.isNaN else { return "--" }
    let absNum = abs(num)
    if absNum >= 1_000_000_000 {
        return (num / 1_000_000_000).formatted(.number.precision(.fractionLength(1))) + "B"
    } else if absNum >= 1_000_000 {
        return (num / 1_000_000).formatted(.number.precision(.fractionLength(1))) + "M"
    } else if absNum >= 1_000 {
        return (num / 1_000).formatted(.number.precision(.fractionLength(1))) + "K"
    } else if num.rounded() == num, let intVal = cardSafeInt(num) {
        return intVal.formatted()
    } else {
        return num.formatted(.number.precision(.fractionLength(0...2)))
    }
}

func cardFormatCurrency(_ val: Double, currency: String?) -> String {
    guard val.isFinite, !val.isNaN else { return "--" }
    let formatted = val.formatted(.number.precision(.fractionLength(val >= 100 ? 2 : (val >= 1 ? 2 : 4))))
    let curr = currency?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "$"
    if curr == "$" || curr == "€" || curr == "£" || curr == "¥" {
        return "\(curr)\(formatted)"
    } else if !curr.isEmpty {
        return "\(formatted) \(curr)"
    }
    return formatted
}

/// Builds search or maps URL with URLComponents to ensure `&` and `+` are properly encoded.
func cardMakeURL(scheme: String = "https", host: String, path: String = "/", queryItems: [URLQueryItem]) -> URL? {
    var comp = URLComponents()
    comp.scheme = scheme
    comp.host = host
    comp.path = path
    comp.queryItems = queryItems
    return comp.url
}

/// Consistent star color token for ratings across cards (#E8B04B).
let cardStarColor = Color(red: 0xE8 / 255.0, green: 0xB0 / 255.0, blue: 0x4B / 255.0)

// MARK: - RTL Text Modifier

struct CardTextDirectionModifier: ViewModifier {
    let text: String

    func body(content: Content) -> some View {
        content
            .environment(\.layoutDirection, text.dominantLayoutDirection)
            .multilineTextAlignment(.leading)   // .leading already flips under a right-to-left environment
    }
}

extension View {
    func cardTextDirection(_ text: String?) -> some View {
        Group {
            if let text, !text.isEmpty {
                self.modifier(CardTextDirectionModifier(text: text))
            } else {
                self
            }
        }
    }
}


extension View {
    /// Wrapping paragraph laid out in its own direction, pinned to that direction's leading edge.
    func cardParagraph(_ text: String?) -> some View {
        let direction = text?.dominantLayoutDirection ?? .leftToRight
        return self
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, direction)
    }
}
