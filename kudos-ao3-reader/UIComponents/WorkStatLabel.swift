import SwiftUI

/// A single compact work stat: a bold, theme-tinted glyph hugging its value, with
/// the value inheriting the surrounding font/colour. Shared across every work
/// surface — the Search/Library rows (`AO3WorkRow` / `WorkRow`) and the Home/Library
/// cover-card shelves — so metadata reads as one family (Part 4 card consistency).
struct WorkStatLabel: View {
    let text: String
    let symbol: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tint)
            Text(text)
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// The rating/word-count/chapters/kudos stat row on a detailed list row. Shared
/// by `WorkRow` (local `SavedWork`) and `AO3WorkRow` (remote `AO3WorkSummary`)
/// — each derives these already-formatted, already-nil-checked values from its
/// own model shape and hands them here, so the two never drift out of layout
/// sync with each other.
struct WorkListStatsRow: View {
    var rating: String?
    var wordCount: Int?
    var chapters: String?
    var kudos: Int?

    var body: some View {
        FlowLayout(spacing: 18, rowSpacing: 5) {
            if let rating { WorkStatLabel(text: rating, symbol: "checkmark.shield") }
            if let wordCount { WorkStatLabel(text: wordCount.formatted(), symbol: "textformat.size") }
            if let chapters { WorkStatLabel(text: chapters, symbol: "book") }
            if let kudos { WorkStatLabel(text: kudos.formatted(), symbol: "heart") }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.top, 1)
    }
}

enum WorkStat {
    /// AO3 rating → a one/two-letter badge for tight spaces (cover cards). Full
    /// rating text stays on the wide rows.
    static func ratingShort(_ rating: String) -> String? {
        switch rating {
        case "General Audiences": "G"
        case "Teen And Up Audiences": "T"
        case "Mature": "M"
        case "Explicit": "E"
        case "Not Rated": "NR"
        default: rating.isEmpty ? nil : String(rating.prefix(1)).uppercased()
        }
    }
}
