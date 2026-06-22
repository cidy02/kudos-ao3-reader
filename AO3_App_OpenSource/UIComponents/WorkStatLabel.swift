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
