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
    /// distinct icons so which is which is never a guess.
    private var showsPublished: Bool {
        guard let datePublished else { return false }
        return !datePublished.isEmpty
    }

    private var showsUpdated: Bool {
        guard let dateUpdated, !dateUpdated.isEmpty else { return false }
        return dateUpdated != datePublished
    }

    /// Every visible stat as (text, symbol, accessibilityLabel) — built as data
    /// first so a "·" separator can be interleaved between only the items that
    /// actually show, never a dangling one next to a nil stat.
    private var items: [(text: String, symbol: String, accessibilityLabel: String)] {
        var result: [(text: String, symbol: String, accessibilityLabel: String)] = []
        if let rating {
            result.append((WorkStat.ratingName(rating) ?? rating, "checkmark.shield", rating))
        }
        if let wordCount {
            result.append((wordCount.formatted(), "textformat.size", "\(wordCount.formatted()) words"))
        }
        if let chapters {
            result.append((chapters, "book", "Chapters \(chapters)"))
        }
        if let kudos {
            result.append((kudos.formatted(), "heart", "\(kudos.formatted()) kudos"))
        }
        if showsPublished, let datePublished {
            let display = WorkStat.displayDate(datePublished)
            result.append((display, "calendar", "Published \(display)"))
        }
        if showsUpdated, let dateUpdated {
            let display = WorkStat.displayDate(dateUpdated)
            result.append((display, "calendar.badge.clock", "Updated \(display)"))
        }
        return result
    }

    var body: some View {
        FlowLayout(spacing: 8, rowSpacing: 5) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Text("•")
                        .accessibilityHidden(true)
                }
                WorkStatLabel(text: item.text, symbol: item.symbol, accessibilityLabel: item.accessibilityLabel)
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.top, 1)
    }
}

enum WorkStat {
    /// AO3 rating → a short, glanceable name. Originally scoped to compact cover
    /// cards only (no width for "Teen And Up Audiences" there); list rows and
    /// search-result cards now use the same short form for a consistent stat row.
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

    /// AO3 renders `Published`/`Updated` in two different formats depending on
    /// which page it was scraped from — "2025-11-01" (ISO) on a work's own detail
    /// page (`dd.published`/`dd.status`), "01 Nov 2025" on search/listing blurbs
    /// (`p.datetime`) — both confirmed live against archiveofourown.org. Tries
    /// both, normalizes to MM/DD/YYYY; falls back to the raw string unparsed
    /// rather than showing nothing if AO3 ever changes either format.
    private static let parseFormats = ["yyyy-MM-dd", "dd MMM yyyy"]

    private static let parseFormatters: [DateFormatter] = parseFormats.map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter
    }()

    static func displayDate(_ rawText: String) -> String {
        for formatter in parseFormatters {
            if let date = formatter.date(from: rawText) {
                return displayFormatter.string(from: date)
            }
        }
        return rawText
    }
}
