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
    /// Overrides the icon's usual `.tint` — the rating and category icons use
    /// AO3's own color coding instead.
    var iconColor: Color?

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(iconColor.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.tint))
            Text(text)
        }
        .lineLimit(1)
        .fixedSize()
        .combinedAccessibilityRow(accessibilityLabel ?? text)
    }
}

/// The work's last-updated date, pinned to the card's top-right corner beside
/// the expand control rather than sitting in `WorkListStatsRow` with the other
/// stats — it answers "is this still being written" at a glance, which is worth
/// the prime corner. Shared by `WorkRow` and `AO3WorkRow` so the two agree.
///
/// Shows only when it differs from the published date, which stays in the stats
/// row: a never-updated oneshot has nothing new to say twice. `AO3WorkSummary`
/// carries no published date at all, so a search result always shows this.
struct WorkUpdatedDateBadge: View {
    let dateUpdated: String
    var datePublished: String?

    var body: some View {
        if !dateUpdated.isEmpty, dateUpdated != datePublished {
            let display = WorkStat.displayDate(dateUpdated)
            WorkStatLabel(
                text: display,
                symbol: "calendar.badge.clock",
                accessibilityLabel: "Updated \(display)"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

/// The rating/word-count/chapters/kudos stat row on a detailed list row. Shared
/// by `WorkRow` (local `SavedWork`) and `AO3WorkRow` (remote `AO3WorkSummary`)
/// — each derives these already-formatted, already-nil-checked values from its
/// own model shape and hands them here, so the two never drift out of layout
/// sync with each other.
struct WorkListStatsRow: View {
    var rating: String?
    var categories: [String] = []
    var warnings: [String] = []
    var completion: WorkCompletionStatus = .unknown
    var language: String?
    var wordCount: Int?
    var chapters: String?
    var comments: Int?
    var kudos: Int?
    /// The work's AO3 bookmark count — not the in-book bookmarks/highlights
    /// that `KudosBackupBookmark` and the reader mean by the same word.
    var bookmarks: Int?
    var hits: Int?
    /// Published only — the updated date lives in the card's top-right corner
    /// (`WorkUpdatedDateBadge`), not down here with the rest of the stats.
    var datePublished: String?

    /// Settings → Library → "Show zero counts". On (the default) every stat
    /// keeps its place even at zero, so a card's stat row has the same shape
    /// whatever the work; off drops the empty ones for a terser row.
    @AppStorage("showsZeroStats") private var showsZeroStats = true

    private var showsPublished: Bool {
        guard let datePublished else { return false }
        return !datePublished.isEmpty
    }

    private struct Item {
        let text: String
        let symbol: String
        let accessibilityLabel: String
        var iconColor: Color?
    }

    /// A count stat, treating "AO3 didn't print it" as the zero it means.
    /// Returns nil — dropping the badge — only when the count is zero and the
    /// user has turned "Show zero counts" off.
    private func count(_ value: Int?, symbol: String, noun: String) -> Item? {
        let count = value ?? 0
        guard count > 0 || showsZeroStats else { return nil }
        let formatted = count.formatted()
        return Item(text: formatted, symbol: symbol, accessibilityLabel: "\(formatted) \(noun)")
    }

    /// Language / words / chapters / engagement counts / published date, below
    /// the justified row.
    ///
    /// With "Show zero counts" on (the default) every stat holds its place,
    /// zeros included: AO3 omits a `dd` entirely when its count is zero, so a
    /// nil here means "AO3 said nothing", which for a count means zero — and
    /// dropping those badges made a card's stat row change shape for no reason
    /// a reader could see. The two text stats (language, chapters) can be
    /// genuinely absent rather than zero, so they fall back to an em dash.
    private var secondaryItems: [Item] {
        let unknownText = "—"
        let language = language.flatMap { $0.isEmpty ? nil : $0 }
        let chapters = chapters.flatMap { $0.isEmpty ? nil : $0 }
        var result: [Item] = []
        if language != nil || showsZeroStats {
            // AO3 scrapes `dd.language` as a display name already ("English",
            // "Español"), so there is no code to map here.
            result.append(Item(
                text: language ?? unknownText,
                symbol: "globe",
                accessibilityLabel: language.map { "Language: \($0)" } ?? "Language unknown"
            ))
        }
        result.append(contentsOf: [
            count(wordCount, symbol: "textformat.size", noun: "words")
        ].compactMap(\.self))
        if chapters != nil || showsZeroStats {
            result.append(Item(
                text: chapters ?? unknownText,
                symbol: "book",
                accessibilityLabel: chapters.map { "Chapters \($0)" } ?? "Chapter count unknown"
            ))
        }
        result.append(contentsOf: [
            count(comments, symbol: "bubble.left", noun: "comments"),
            count(kudos, symbol: "heart", noun: "kudos"),
            count(bookmarks, symbol: "bookmark", noun: "bookmarks"),
            count(hits, symbol: "eye", noun: "hits")
        ].compactMap(\.self))
        if showsPublished, let datePublished {
            let display = WorkStat.displayDate(datePublished)
            result.append(Item(text: display, symbol: "calendar", accessibilityLabel: "Published \(display)"))
        }
        return result
    }

    /// Rating, category, warnings, and completion status — the four fields AO3
    /// itself always surfaces up front on a work. Every badge always shows
    /// something, even "Uncategorized"/"No Warnings" — a blank slot reads as a
    /// layout gap rather than a real state on device.
    ///
    /// Checking `categories` for emptiness isn't enough: an unrecognized
    /// category string (or a comma-joined blob AO3 sometimes hands back for a
    /// multi-category work) would pass `!isEmpty` but still render nothing,
    /// leaving the slot silently blank. Filter to recognized values first.
    ///
    /// AO3's own legend never lists the specific warnings in its badge either —
    /// just how many apply — so the visible warning text stays short; the full
    /// list still reaches VoiceOver through the accessibility label.
    private var topItems: [Item] {
        var result: [Item] = []
        if let rating {
            result.append(Item(
                text: WorkStat.ratingLetter(rating) ?? rating,
                symbol: "checkmark.shield",
                accessibilityLabel: rating,
                iconColor: WorkStat.ratingColor(rating)
            ))
        }
        let recognized = categories.filter { WorkStat.categoryColor($0) != nil }
        if recognized.isEmpty {
            result.append(Item(
                text: "N/A",
                symbol: "person.2.fill",
                accessibilityLabel: "Category: not categorized",
                iconColor: .gray
            ))
        } else {
            for category in recognized {
                result.append(Item(
                    text: category,
                    symbol: "person.2.fill",
                    accessibilityLabel: WorkStat.categoryAccessibilityLabel(category),
                    iconColor: WorkStat.categoryColor(category)
                ))
            }
        }
        let status = WorkWarningStatus(rawWarnings: warnings)
        result.append(Item(
            text: status.text,
            symbol: status.symbol,
            accessibilityLabel: status.accessibilityLabel(rawWarnings: warnings),
            iconColor: status.color
        ))
        result.append(Item(
            text: completion.shortText,
            symbol: completion.symbol,
            accessibilityLabel: "Status: \(completion.text)",
            iconColor: completion.color
        ))
        return result
    }

    /// Justified: the first badge hugs the leading edge, the last hugs the
    /// trailing edge, and the slack is split evenly across every gap rather
    /// than dumped into a single one (which read as a hole in the row).
    ///
    /// `FlowLayout` rather than an `HStack` of `Spacer`s inside a
    /// `ViewThatFits`: that sizes its chosen candidate to the candidate's
    /// *ideal* width, never the width on offer, so the spacers had nothing to
    /// expand into and the row rendered short with a ragged trailing edge.
    /// FlowLayout also still wraps when the badges genuinely don't fit — they
    /// are all `fixedSize`, so a too-long single row would otherwise overflow
    /// and stretch the card past its own padding.
    private var topRow: some View {
        FlowLayout(spacing: 6, rowSpacing: 5, justifiesRows: true) {
            ForEach(Array(topItems.enumerated()), id: \.offset) { index, item in
                if index > 0 { bullet }
                badge(item)
            }
        }
    }

    private func badge(_ item: Item) -> some View {
        WorkStatLabel(
            text: item.text,
            symbol: item.symbol,
            accessibilityLabel: item.accessibilityLabel,
            iconColor: item.iconColor
        )
    }

    /// `.fixedSize()` matters here: every other child in this row is a
    /// `WorkStatLabel`, which already refuses to compress. Without it too, a
    /// bare `Text` is the only flexible child left when the row runs long
    /// (e.g. "Uncategorized" next to "Not Disclosed") — the HStack squeezes
    /// all the slack onto it first, sometimes down to invisible.
    private var bullet: some View {
        Text("•")
            .fixedSize()
            .accessibilityHidden(true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            topRow
            if !secondaryItems.isEmpty {
                FlowLayout(spacing: 8, rowSpacing: 5) {
                    ForEach(Array(secondaryItems.enumerated()), id: \.offset) { index, item in
                        if index > 0 {
                            Text("•")
                                .accessibilityHidden(true)
                        }
                        WorkStatLabel(
                            text: item.text,
                            symbol: item.symbol,
                            accessibilityLabel: item.accessibilityLabel,
                            iconColor: item.iconColor
                        )
                    }
                }
            }
        }
        .font(.caption2)
        // Matches the summary text above the divider (.secondary) — .tertiary
        // read as too faint next to it.
        .foregroundStyle(.secondary)
        .padding(.top, 1)
    }
}

/// Complete / In Progress / Unknown — shared by the compact cover cards and the
/// detail/search stats row so both read the same tri-state the same way.
enum WorkCompletionStatus: Equatable {
    case complete
    case inProgress
    case unknown

    /// `isComplete` is `nil` only when the status is genuinely not known (an
    /// import whose source never stated it) — not simply "not yet checked".
    init(isComplete: Bool?) {
        switch isComplete {
        case true: self = .complete
        case false: self = .inProgress
        case nil: self = .unknown
        }
    }

    var text: String {
        switch self {
        case .complete: "Complete"
        case .inProgress: "In Progress"
        case .unknown: "Unknown"
        }
    }

    /// For the dense four-badge top row, where "In Progress" is the one label
    /// long enough to push the row past a single line. The compact cover cards
    /// keep `text` — they deliberately spell their stats out (see
    /// `CoverCardStatsRow`) and have the width for it.
    var shortText: String {
        switch self {
        case .complete: "Complete"
        case .inProgress: "WIP"
        case .unknown: "Unknown"
        }
    }

    /// The compact cover cards already shipped checkmark.seal/circle.dashed for
    /// the two known states — kept as-is; questionmark.circle.fill fills the
    /// one gap (unknown status previously showed no badge at all).
    var symbol: String {
        switch self {
        case .complete: "checkmark.seal"
        case .inProgress: "circle.dashed"
        case .unknown: "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .complete: .green
        case .inProgress: .orange
        case .unknown: .gray
        }
    }
}

/// AO3's Archive Warnings field is one of three mutually-exclusive states, not
/// a plain present/absent flag — its own legend colors each differently:
/// specific warnings listed (red), "No Archive Warnings Apply" (gray/none),
/// or "Creator Chose Not To Use Archive Warnings" (amber — the content
/// *could* include any of the standard warnings, the creator just didn't say).
/// Collapsing the latter two together would misrepresent an undisclosed work
/// as a confirmed-clean one.
enum WorkWarningStatus: Equatable {
    case none
    case undisclosed
    case present(count: Int)

    init(rawWarnings: [String]) {
        if rawWarnings.contains(where: { $0.localizedCaseInsensitiveContains("Chose Not To Use") }) {
            self = .undisclosed
            return
        }
        let real = WorkStat.realWarnings(rawWarnings)
        self = real.isEmpty ? .none : .present(count: real.count)
    }

    var text: String {
        switch self {
        case .none: "No Warnings"
        case .undisclosed: "Not Disclosed"
        case .present(let count): count == 1 ? "1 Warning Applies" : "\(count) Warnings Apply"
        }
    }

    /// One icon for all three states — like the rating shield and category
    /// glyph, color alone carries the distinction.
    var symbol: String { "exclamationmark.circle.fill" }

    var color: Color {
        switch self {
        case .none: .gray
        case .undisclosed: .orange
        case .present: .red
        }
    }

    func accessibilityLabel(rawWarnings: [String]) -> String {
        switch self {
        case .none: "No archive warnings"
        case .undisclosed: "Archive warnings: creator chose not to disclose — content could include any of the standard warnings"
        case .present: "Warnings: \(WorkStat.realWarnings(rawWarnings).joined(separator: ", "))"
        }
    }
}

extension SavedWork {
    /// An AO3 work always has a known status. A converted import only has one
    /// when its source stated it, which the metadata page now carries through —
    /// so "Complete"/"In Progress" show when actually known, "Unknown" otherwise,
    /// rather than defaulting a non-AO3 work to "In Progress" and being wrong.
    var completionStatus: WorkCompletionStatus {
        let hasKnownStatus = ao3WorkID != nil || WorkTags.ao3WorkID(from: sourceURL) != nil
        if hasKnownStatus { return isComplete ? .complete : .inProgress }
        return isComplete ? .complete : .unknown
    }
}

enum WorkStat {
    /// AO3's "No Archive Warnings Apply" / "Creator Chose Not To Use Archive
    /// Warnings" are sentinel non-warnings, not warnings worth flagging red.
    static func realWarnings(_ warnings: [String]) -> [String] {
        warnings.filter {
            !$0.localizedCaseInsensitiveContains("No Archive Warnings")
                && !$0.localizedCaseInsensitiveContains("Chose Not To Use")
        }
    }

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

    /// AO3's own single-letter rating shorthand, for the dense four-badge top
    /// row where the spelled-out names don't all fit on one line. Deliberately
    /// NOT used by the compact cover cards: those moved away from cryptic
    /// abbreviations on purpose (see `CoverCardStatsRow` — "the values were
    /// abbreviated to the point of being cryptic") and have the width for the
    /// full name. The icon's color carries the same meaning either way, and the
    /// full rating still reaches VoiceOver through the accessibility label.
    static func ratingLetter(_ rating: String) -> String? {
        switch rating {
        case "General Audiences": "G"
        case "Teen And Up Audiences": "T"
        case "Mature": "M"
        case "Explicit": "E"
        case "Not Rated": "NR"
        default: rating.isEmpty ? nil : rating
        }
    }

    /// AO3's own General/Teen/Mature/Explicit rating-icon color coding, so the
    /// icon carries meaning at a glance instead of every rating looking the same.
    static func ratingColor(_ rating: String) -> Color? {
        switch rating {
        case "General Audiences": .green
        case "Teen And Up Audiences": .yellow
        case "Mature": .orange
        case "Explicit": .red
        // Explicitly gray rather than nil: falling through to `.tint` painted
        // it the app's red accent, which reads as the most severe rating —
        // the opposite of what "no rating given" means. AO3 leaves its own
        // unrated icon blank for the same reason.
        case "Not Rated": .gray
        default: nil
        }
    }

    /// AO3's own category color coding (a small colored badge per
    /// relationship-category tag, e.g. F/F, Gen, Multi). SF Symbols has no
    /// venus/mars/gender glyphs to tell the categories apart by shape, so every
    /// category shares one real SF Symbol ("person.2.fill", same treatment as
    /// the rating shield) and color alone carries the distinction.
    static func categoryColor(_ category: String) -> Color? {
        switch category {
        case "F/F": .red
        case "F/M": .pink
        case "Gen": .green
        case "M/M": .blue
        case "Multi": .purple
        case "Other": .gray
        default: nil
        }
    }

    static func categoryAccessibilityLabel(_ category: String) -> String {
        switch category {
        case "F/F": "Category: female/female relationships"
        case "F/M": "Category: female/male relationships"
        case "Gen": "Category: no romantic or sexual relationships, or not the main focus"
        case "M/M": "Category: male/male relationships"
        case "Multi": "Category: more than one kind of relationship"
        case "Other": "Category: other relationships"
        default: "Category: \(category)"
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
