import SwiftUI

extension String {
    /// Direction of the first strong character (Arabic/Hebrew → RTL), so mixed Darija/French/English text
    /// is laid out per paragraph the way the user typed it.
    var dominantLayoutDirection: LayoutDirection {
        for scalar in unicodeScalars {
            switch scalar.value {
            case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF: return .rightToLeft
            case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F: return .leftToRight
            default: continue
            }
        }
        return .leftToRight
    }

    var isRightToLeft: Bool { dominantLayoutDirection == .rightToLeft }

    /// Case/diacritic/width-insensitive search key; also folds Arabic letter variants (أ إ آ → ا, ة → ه, ى → ي).
    var searchFolded: String {
        var s = folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        for (from, to) in [("أ", "ا"), ("إ", "ا"), ("آ", "ا"), ("ة", "ه"), ("ى", "ي"), ("ـ", "")] {
            s = s.replacingOccurrences(of: from, with: to)
        }
        return s
    }
}
