import SwiftUI

extension View {
    /// Collapses a small icon+text metadata row (e.g. `WorkStatLabel`,
    /// `CardMetaLabel`) into one VoiceOver stop instead of two — one for the
    /// decorative icon, one for the text. Ignores the row's own subview
    /// accessibility entirely (so a glyph's auto-derived SF Symbol name, e.g.
    /// "checkmark shield", never leaks into the announcement — no need to
    /// `.accessibilityHidden` the icon separately) and reports `label` instead,
    /// normally the same string already shown by the row's `Text`.
    ///
    /// Deliberately NOT a `Label` conversion: `Label`'s icon-tint renders
    /// inconsistently between `List` and plain `ScrollView` containers in this
    /// codebase — see the icon+title row comment near `AccountComponents.swift`'s
    /// `chapterSection`-style row (icon and text styled separately "rather than via
    /// a single Label, whose icon otherwise only picks up the accent tint inside a
    /// List... and falls back to .primary in Compact's plain ScrollView") — and
    /// these rows appear in both container types.
    func combinedAccessibilityRow(_ label: String) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
    }
}

/// A single compact work stat: a bold, theme-tinted glyph hugging its value, with
/// the value inheriting the surrounding font/colour. Shared across every work
/// surface — the Search/Library rows (`AO3WorkRow` / `WorkRow`) and the Home/Library
/// cover-card shelves — so metadata reads as one family (Part 4 card consistency).
struct WorkStatLabel: View {
    let text: String
    let symbol: String
    /// What VoiceOver announces instead of the bare visible `text` — a stat like
    /// "45,678" or "T" is meaningless without knowing what it's counting. Defaults
    /// to `text` for callers where the visible string is already self-describing
    /// (e.g. a full rating name, "Complete").
    var accessibilityLabel: String?

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tint)
            Text(text)
        }
        .lineLimit(1)
        .fixedSize()
        .combinedAccessibilityRow(accessibilityLabel ?? text)
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
    var datePublished: String?
    var dateUpdated: String?

    /// Published shows whenever known. Updated only shows when it actually differs
    /// from published (a never-updated oneshot has nothing new to say twice) —
    /// distinct icons so which is which is never a guess. AO3's blurb date text is
    /// already display-ready, so this passes it through unformatted.
    private var showsPublished: Bool {
        guard let datePublished else { return false }
        return !datePublished.isEmpty
    }

    private var showsUpdated: Bool {
        guard let dateUpdated, !dateUpdated.isEmpty else { return false }
        return dateUpdated != datePublished
    }

    var body: some View {
        FlowLayout(spacing: 18, rowSpacing: 5) {
            if let rating { WorkStatLabel(text: rating, symbol: "checkmark.shield") }
            if let wordCount {
                WorkStatLabel(
                    text: wordCount.formatted(),
                    symbol: "textformat.size",
                    accessibilityLabel: "\(wordCount.formatted()) words"
                )
            }
            if let chapters {
                WorkStatLabel(text: chapters, symbol: "book", accessibilityLabel: "Chapters \(chapters)")
            }
            if let kudos {
                WorkStatLabel(
                    text: kudos.formatted(),
                    symbol: "heart",
                    accessibilityLabel: "\(kudos.formatted()) kudos"
                )
            }
            if showsPublished, let datePublished {
                WorkStatLabel(
                    text: datePublished,
                    symbol: "calendar",
                    accessibilityLabel: "Published \(datePublished)"
                )
            }
            if showsUpdated, let dateUpdated {
                WorkStatLabel(
                    text: dateUpdated,
                    symbol: "calendar.badge.clock",
                    accessibilityLabel: "Updated \(dateUpdated)"
                )
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.top, 1)
    }
}

enum WorkStat {
    /// AO3 rating → a short but readable name for cover cards.
    ///
    /// These were single letters ("M", "E") while the cards packed several stats onto
    /// one wrapped row and had no width to spare. Now that each stat gets its own row
    /// there is room to say what the letter meant — "M" told a reader nothing unless
    /// they already knew AO3's scheme. The wide list rows keep the full AO3 name
    /// ("Teen And Up Audiences"); this is the middle length, chosen to fit a 164pt card.
    static func ratingName(_ rating: String) -> String? {
        switch rating {
        case "General Audiences": "General"
        case "Teen And Up Audiences": "Teen"
        case "Mature": "Mature"
        case "Explicit": "Explicit"
        case "Not Rated": "Not Rated"
        default: rating.isEmpty ? nil : rating
        }
    }
}
