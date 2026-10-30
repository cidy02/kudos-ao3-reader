import SwiftUI

extension View {
    /// Collapses a small icon+text metadata row (e.g. `WorkStatLabel`, a
    /// card's author line) into one VoiceOver stop instead of two — one for the
    /// decorative icon, one for the text. Ignores the row's own subview
    /// accessibility entirely (so a glyph's auto-derived SF Symbol name, e.g.
    /// "checkmark shield", never leaks into the announcement — no need to
    /// `.accessibilityHidden` the icon separately) and reports `label` instead,
    /// normally the same string already shown by the row's `Text`.
    ///
    /// Deliberately NOT a `Label` conversion: `Label`'s icon-tint renders
    /// inconsistently between `List` and plain `ScrollView` containers in this
    /// codebase — see the icon+title row comment near `AccountComponents.swift`'s
    /// chapter row (icon and text styled separately "rather than via
    /// a single Label, whose icon otherwise only picks up the accent tint inside a
    /// List... and falls back to .primary in Compact's plain ScrollView") — and
    /// these rows appear in both container types.
    func combinedAccessibilityRow(_ label: String) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
    }
}

/// A single compact work stat: a bold glyph hugging its value, with the value
/// inheriting the surrounding font/colour. Shared across every work surface —
/// the Search/Library rows (`AO3WorkRow` / `WorkRow`) and the Home/Library
/// cover-card shelves — so metadata reads as one family (Part 4 card consistency).
struct WorkStatLabel: View {
    let text: String
    let symbol: String
    /// What VoiceOver announces instead of the bare visible `text` — a stat like
    /// "45,678" or "T" is meaningless without knowing what it's counting. Defaults
    /// to `text` for callers where the visible string is already self-describing
    /// (e.g. a full rating name, "Complete").
    var accessibilityLabel: String?
    /// Overrides the icon's usual secondary colour — rating/category chips that
    /// still need AO3's own coding pass an explicit colour. Default is secondary
    /// (not app accent): language/words/kudos etc. sit under the category row and
    /// should read as quiet metadata, not chrome.
    var iconColor: Color?

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(iconColor.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary))
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

/// I-8: one "+N" for new chapters. Caption 2 bold, 16 pt tall at the default
/// size, 6 pt on the sides, fully round, app colour, white text. The ring is
/// only for a badge that sits on top of a button. The height is a minimum so
/// an accessibility size can grow instead of clipping the digits.
struct WorkPlusBadge: View {
    var count: Int
    var showsRing = false

    @Environment(\.accentFill) private var accentFill

    var body: some View {
        if count > 0 {
            Text("+\(count)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(minHeight: 16)
                .background(accentFill, in: Capsule())
                .overlay {
                    if showsRing {
                        Capsule().strokeBorder(.white, lineWidth: 1)
                    }
                }
                .fixedSize()
                .accessibilityLabel(count == 1 ? "1 new chapter" : "\(count) new chapters")
        }
    }
}

/// The ledger's full stat line. Wraps so a long line keeps every figure.
struct WorkLedgerStatsLine: View {
    var figures: WorkStat.LedgerFigures

    var body: some View {
        if !figures.visible.isEmpty {
            Text(figures.visible.joined(separator: "  ·  "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(figures.spoken)
        }
    }
}

/// One collapsed tag on a work row, before the "+N" overflow.
struct WorkTagChip: Identifiable, Equatable {
    var text: String
    var field: AO3TagSearch.Field
    var id: String { "\(field)-\(text)" }
    var isRelationship: Bool { field == .relationship }
}

enum WorkTagLine {
    /// Relationships first, then characters, then freeforms. Three chips, then "+N".
    static func chips(
        relationships: [String],
        characters: [String],
        freeforms: [String],
        limit: Int = 3
    ) -> (shown: [WorkTagChip], extra: Int) {
        let groups: [(AO3TagSearch.Field, [String])] = [
            (.relationship, relationships),
            (.character, characters),
            (.freeform, freeforms)
        ]
        var seen = Set<String>()
        var all: [WorkTagChip] = []
        for (field, tags) in groups {
            for tag in tags {
                let text = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, seen.insert(text.lowercased()).inserted else { continue }
                all.append(WorkTagChip(text: text, field: field))
            }
        }
        return (Array(all.prefix(limit)), max(0, all.count - limit))
    }
}

/// Relationships take the app colour. Everything else is grey. Each chip searches.
struct WorkTagLineView: View {
    var relationships: [String]
    var characters: [String] = []
    var freeforms: [String] = []
    var onTap: (String, AO3TagSearch.Field) -> Void

    @Environment(\.accentFill) private var accentFill
    @Environment(\.accentInk) private var accentInk

    var body: some View {
        let line = WorkTagLine.chips(
            relationships: relationships, characters: characters, freeforms: freeforms
        )
        if !line.shown.isEmpty {
            FlowLayout(spacing: 6, rowSpacing: 6) {
                ForEach(line.shown) { chip in
                    Button { onTap(chip.text, chip.field) } label: {
                        Text(chip.text)
                            .font(.caption.weight(chip.isRelationship ? .semibold : .regular))
                            .foregroundStyle(chip.isRelationship ? accentInk : Color.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                chip.isRelationship ? accentFill.opacity(0.10) : Color.primary.opacity(0.08),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.borderless)
                    .minimumHitTarget(28)
                }
                if line.extra > 0 {
                    Text("+\(line.extra)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Rating, category, warnings, and completion status as color-coded capsule
/// chips — the four fields AO3 itself always surfaces up front on a work.
/// Every badge always shows something, even "Uncategorized"/"No Warnings" —
/// a blank slot reads as a layout gap rather than a real state on device.
///
/// Shared by `WorkListStatsRow` (search/library list rows, paired with its
/// own longer secondary-facts row below) and `HomeResumeHero` (paired with a
/// shorter Language/Words/Chapters row instead) — both need this exact same row
/// of chips, just different company underneath. The work-detail page states the
/// same four fields as `WorkDetailFigureStrip` instead: it has the width to
/// spell them out, which a row of chips is there to avoid needing.
struct WorkTopStatsRow: View {
    var rating: String?
    var categories: [String] = []
    var warnings: [String] = []
    var completion: WorkCompletionStatus = .unknown
    /// The host card is showing its full detail. Only the category chip changes:
    /// collapsed it folds several categories into "Multi" the way AO3's own blurb
    /// does, expanded it names each one. Defaults to compact, which is what every
    /// list wants.
    var isExpanded: Bool = false
    /// True gives each chip its own row instead of wrapping several onto one
    /// line — the compact cover cards, narrow enough that a wrapping row
    /// often only fit one or two chips per line anyway. Search/library rows
    /// and the hero cards have the width for several per line, so they keep
    /// the default wrapping `FlowLayout`.
    var stacked: Bool = false

    struct Item {
        /// Which of AO3's four tags an item states; nil for the other stats
        /// (`WorkListStatsRow`'s language, words…) that reuse this type.
        enum Facet { case rating, category, warnings, completion }

        let text: String
        let symbol: String
        let accessibilityLabel: String
        var iconColor: Color?
        var facet: Facet?
    }

    /// Checking `categories` for emptiness isn't enough: an unrecognized
    /// category string would pass `!isEmpty` but still render nothing, leaving
    /// the slot silently blank. Filter to recognized values first.
    ///
    /// AO3's own legend never lists the specific warnings in its badge either —
    /// just how many apply — so the visible warning text stays short; the full
    /// list still reaches VoiceOver through the accessibility label.
    /// The category chips only, for tests: the collapse rule is the thing worth
    /// pinning and `topItems` mixes in three other facets.
    var categoryChipTexts: [String] {
        topItems.filter { $0.facet == .category }.map(\.text)
    }

    /// The warning chips only — same reason as `categoryChipTexts`.
    var warningChipTexts: [String] {
        topItems.filter { $0.facet == .warnings }.map(\.text)
    }

    var topItems: [Item] {
        var result: [Item] = []
        if let rating {
            result.append(Item(
                text: WorkStat.ratingLetter(rating) ?? rating,
                symbol: "checkmark.shield",
                accessibilityLabel: rating,
                iconColor: WorkStat.ratingColor(rating),
                facet: .rating
            ))
        }
        let recognized = categories.filter { WorkStat.categoryColor($0) != nil }
        if recognized.count > 1, !isExpanded {
            // AO3's own rule, verified live on 2026-08-07: its blurb draws
            // `category-multi` for *any* work with more than one category, whether
            // or not the literal "Multi" tag is among them — `F/F, M/M` and
            // `Gen, M/M` both get it, with the real list only in the title
            // attribute. One chip keeps a collapsed card glanceable; expanding
            // spells them out, which is what AO3's own work page does too.
            result.append(Item(
                text: "Multi",
                symbol: "person.2.fill",
                accessibilityLabel: "Categories: \(recognized.joined(separator: ", "))",
                iconColor: WorkStat.categoryColor("Multi"),
                facet: .category
            ))
        } else if recognized.isEmpty {
            result.append(Item(
                text: "N/A",
                symbol: "person.2.fill",
                accessibilityLabel: "Category: not categorized",
                iconColor: .gray,
                facet: .category
            ))
        } else {
            for category in recognized {
                result.append(Item(
                    text: category,
                    symbol: "person.2.fill",
                    accessibilityLabel: WorkStat.categoryAccessibilityLabel(category),
                    iconColor: WorkStat.categoryColor(category),
                    facet: .category
                ))
            }
        }
        let status = WorkWarningStatus(rawWarnings: warnings)
        let realWarnings = WorkStat.realWarnings(warnings)
        if isExpanded, case .present = status {
            // Expanded, the count becomes the warnings themselves — the same
            // collapsed/expanded split the categories take. Only `.present` has
            // anything to expand: "No Warnings" and "Not Disclosed" are single
            // states, not folded lists, and would say the same thing either way.
            for warning in realWarnings {
                result.append(Item(
                    text: warning,
                    symbol: status.symbol,
                    accessibilityLabel: "Warning: \(warning)",
                    iconColor: status.color,
                    facet: .warnings
                ))
            }
        } else {
            result.append(Item(
                text: status.text,
                symbol: status.symbol,
                accessibilityLabel: status.accessibilityLabel(rawWarnings: warnings),
                iconColor: status.color,
                facet: .warnings
            ))
        }
        result.append(Item(
            text: completion.shortText,
            symbol: completion.symbol,
            accessibilityLabel: "Status: \(completion.text)",
            iconColor: completion.color,
            facet: .completion
        ))
        return result
    }

    /// One AO3 status as a capsule. The *capsule* carries AO3's rating/category
    /// colour coding now, not the glyph — a chip is a block of colour, so painting
    /// it is what the colour coding is for. The glyph and text stay on the row's
    /// inherited `.secondary`, which is legible on every tint and in every theme;
    /// a saturated glyph on a tinted capsule of the same hue just goes muddy.
    ///
    /// Tinted, not filled: `.explicit` is red and `.mature` orange, and four
    /// solid blocks of those beside the cover art would read as an error state.
    /// The alpha is low enough that secondary text keeps its contrast in both
    /// appearances, and an uncoloured item (nothing AO3 colour-codes) falls back
    /// to the neutral `.quaternary` the whole row used to use.
    private func statusChip(_ item: Item) -> some View {
        HStack(spacing: 3) {
            Image(systemName: item.symbol)
                .font(.caption2.weight(.bold))
            Text(item.text)
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(chipFill(item), in: Capsule())
        .combinedAccessibilityRow(item.accessibilityLabel)
    }

    private func chipFill(_ item: Item) -> AnyShapeStyle {
        guard let color = item.iconColor else { return AnyShapeStyle(.quaternary) }
        return AnyShapeStyle(color.opacity(0.22))
    }

    /// Centred. Justification stretched the gaps to square the row's edges
    /// with the counts underneath, which only works while both rows are
    /// full — a two-chip work got two capsules pinned to opposite edges of
    /// the card with a canyon between them. Centring keeps the natural gaps
    /// at any chip count and still reads as a deliberate row. No bullet
    /// separators between chips — each capsule already has its own colored
    /// background, so a bullet was redundant separation, and dropping it
    /// lets more chips fit on one row before wrapping.
    ///
    /// `FlowLayout` rather than an `HStack` inside a `ViewThatFits`: that sizes its
    /// chosen candidate to the candidate's *ideal* width, never the width on offer,
    /// so there was nothing to centre within. FlowLayout also still wraps when the
    /// chips genuinely don't fit — they are all `fixedSize`, so a too-long single
    /// row would otherwise stretch the card past its own padding.
    var body: some View {
        if stacked {
            VStack(alignment: .leading, spacing: 5) {
                // Rating and category share a row — both are short tags
                // ("T", "M/M") that comfortably fit side by side, unlike
                // Warnings/Completion, which run longer ("Not Disclosed",
                // "In Progress"). A FlowLayout, not an HStack, only so a rare
                // expanded/long combination still wraps instead of
                // overflowing the card.
                let ratingAndCategory = topItems.filter { $0.facet == .rating || $0.facet == .category }
                let rest = topItems.filter { $0.facet != .rating && $0.facet != .category }
                if !ratingAndCategory.isEmpty {
                    FlowLayout(spacing: 6, rowSpacing: 5) {
                        ForEach(Array(ratingAndCategory.enumerated()), id: \.offset) { _, item in
                            statusChip(item)
                        }
                    }
                }
                ForEach(Array(rest.enumerated()), id: \.offset) { _, item in
                    statusChip(item)
                }
            }
        } else {
            FlowLayout(spacing: 6, rowSpacing: 5, rowAlignment: .center) {
                ForEach(Array(topItems.enumerated()), id: \.offset) { _, item in
                    statusChip(item)
                }
            }
        }
    }
}

/// Rating, category, warnings and completion as four solid tiles — AO3's own
/// required-tags grid in AO3's own colours (T-479, decision TILES), in the
/// Symbols board's order: rating and category on top, warnings and completion
/// below. Every tile always draws something: a tag that is absent (not rated,
/// no category, no warnings, status unknown) is a grey tile, not a gap.
/// `WorkSymbolTile` holds what each tile draws.
///
/// No tray behind it anywhere (I-1): solid tiles carry their own contrast on a
/// plain row, a washed card and a gradient alike.
///
/// Purely decorative unless `announcesToVoiceOver` — callers that leave it off
/// keep a real accessible summary of the same facts elsewhere (`WorkTopStatsRow`'s
/// own text chips, or the card's title/stats row).
struct WorkStatusIconGrid: View {
    enum Arrangement {
        /// The 2×2 grid.
        case grid
        /// One row of four, the spare width going between the tiles.
        case strip
    }

    var rating: String?
    var categories: [String] = []
    var warnings: [String] = []
    var completion: WorkCompletionStatus = .unknown
    /// Each tile's edge before Dynamic Type; the gap, corners and glyphs scale
    /// with it. I-2: 24 for a grid or a strip, 22 for one tile in a filter
    /// chip, 20 inline.
    var tileSize: CGFloat = 24
    /// True when this grid is a card's *only* summary of rating/category/
    /// warnings/completion, with no separate always-visible text row to
    /// carry the accessible version — announces the same facts as one
    /// VoiceOver stop instead of staying fully hidden.
    var announcesToVoiceOver: Bool = false
    var arrangement: Arrangement = .grid

    /// The board's tile geometry, as fractions of the tile.
    static let cornerRadiusRatio: CGFloat = 0.24
    static let gapRatio: CGFloat = 0.12

    var body: some View {
        WorkStatusIconGridContent(
            rating: rating,
            categories: categories,
            warnings: warnings,
            completion: completion,
            tileSize: tileSize,
            announcesToVoiceOver: announcesToVoiceOver,
            arrangement: arrangement
        )
        .dynamicTypeSize(.xSmall ... .accessibility2)
    }

    /// The drawn height of the 2×2 grid — two tiles and the gap between them.
    /// Exposed so a neighbour (the ledger row's progress ring) can match it
    /// instead of hard-coding a number that drifts the next time a tile changes.
    static func gridHeight(tileSize: CGFloat) -> CGFloat {
        tileSize * (2 + gapRatio)
    }
}

/// Hands `content` the grid's drawn height at the current Dynamic Type size,
/// under the same cap and scale the grid uses, so a neighbour sized to it grows with it.
struct WorkStatusGridMatched<Content: View>: View {
    let tileSize: CGFloat
    @ViewBuilder var content: (CGFloat) -> Content

    var body: some View {
        Scaled(tileSize: tileSize, content: content)
            .dynamicTypeSize(.xSmall ... .accessibility2)
    }

    private struct Scaled: View {
        let tileSize: CGFloat
        let content: (CGFloat) -> Content
        @ScaledMetric(relativeTo: .caption2) private var scale: CGFloat = 1

        var body: some View {
            content(WorkStatusIconGrid.gridHeight(tileSize: tileSize * scale))
        }
    }
}

private struct WorkStatusIconGridContent: View {
    var rating: String?
    var categories: [String]
    var warnings: [String]
    var completion: WorkCompletionStatus
    var tileSize: CGFloat
    var announcesToVoiceOver: Bool
    var arrangement: WorkStatusIconGrid.Arrangement

    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .caption2) private var scale: CGFloat = 1

    private var side: CGFloat { tileSize * scale }
    private var gap: CGFloat { side * WorkStatusIconGrid.gapRatio }

    /// Always the collapsed fold: a tile has room for one category, so several
    /// are Multi whether or not the card around it is expanded.
    private var tiles: [WorkSymbolTile] {
        let dark = colorScheme == .dark
        return [
            .rating(rating, dark: dark),
            .category(categories, dark: dark),
            .warnings(WorkWarningStatus(rawWarnings: warnings), dark: dark),
            .completion(completion, dark: dark),
        ]
    }

    var body: some View {
        if announcesToVoiceOver {
            // The text chips' own labels, so the grid says what they would.
            let items = WorkTopStatsRow(
                rating: rating, categories: categories, warnings: warnings, completion: completion
            ).topItems
            layout.combinedAccessibilityRow(items.map(\.accessibilityLabel).joined(separator: ", "))
        } else {
            layout.accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var layout: some View {
        let resolved = tiles
        switch arrangement {
        case .grid:
            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    tile(resolved[0])
                    tile(resolved[1])
                }
                HStack(spacing: gap) {
                    tile(resolved[2])
                    tile(resolved[3])
                }
            }
        case .strip:
            HStack(spacing: 0) {
                ForEach(resolved.indices, id: \.self) { index in
                    if index > 0 {
                        Spacer(minLength: gap)
                    }
                    tile(resolved[index])
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func tile(_ symbol: WorkSymbolTile) -> some View {
        ZStack {
            if symbol.mark == .multi {
                multiQuadrants
            } else {
                symbol.fill
                glyph(symbol)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * WorkStatusIconGrid.cornerRadiusRatio, style: .continuous))
    }

    /// Every glyph sits in one box, 0.68 of the tile, centred on its own ink
    /// (I-3); the shield is the exception at 0.84, its letter centred on the
    /// shield's body rather than the tile.
    @ViewBuilder
    private func glyph(_ symbol: WorkSymbolTile) -> some View {
        switch symbol.mark {
        case .shield(let letter):
            let box = side * WorkSymbolTile.shieldBoxRatio
            ZStack {
                WorkSymbolTile.path(for: symbol.mark, in: box)
                    .fill(symbol.ink)
                // Cut out: the letter is the tile's own colour.
                Text(letter)
                    .font(.system(size: side * 0.36, weight: .heavy, design: .rounded))
                    .foregroundStyle(symbol.fill)
                    .offset(y: box * WorkSymbolTile.shieldBodyOffset)
            }
            .frame(width: box, height: box)
        case .exclamation, .question:
            // SF Symbols, which are drawn centred on their own ink already.
            Image(systemName: symbol.mark == .exclamation ? "exclamationmark" : "questionmark")
                .font(.system(size: side * 0.6, weight: .heavy))
                .foregroundStyle(symbol.ink)
                .frame(width: side * WorkSymbolTile.glyphBoxRatio, height: side * WorkSymbolTile.glyphBoxRatio)
        default:
            let box = side * WorkSymbolTile.glyphBoxRatio
            WorkSymbolTile.path(for: symbol.mark, in: box)
                .fill(symbol.ink)
                .frame(width: box, height: box)
        }
    }

    /// Multi has no one relationship to symbolize — AO3's own icon is a small
    /// multicolour grid. Four solid quadrants in the Gen, F/M, F/F and M/M
    /// colours, clipped to the tile's corners with it.
    private var multiQuadrants: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                AO3TagPalette.general
                AO3TagPalette.femaleMale
            }
            HStack(spacing: 0) {
                AO3TagPalette.femaleFemale
                AO3TagPalette.maleMale
            }
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
    var isExpanded: Bool = false

    /// Settings → Library → "Show zero counts". On (the default) every stat
    /// keeps its place even at zero, so a card's stat row has the same shape
    /// whatever the work; off drops the empty ones for a terser row.
    @AppStorage("showsZeroStats") private var showsZeroStats = true

    private var showsPublished: Bool {
        guard let datePublished else { return false }
        return !datePublished.isEmpty
    }

    private typealias Item = WorkTopStatsRow.Item

    /// A count stat whose caller has already distinguished zero from unknown.
    /// Returns nil for unknown, or for zero when the user hides zero counts.
    private func count(_ value: Int?, symbol: String, noun: String) -> Item? {
        guard let count = value else { return nil }
        guard count > 0 || showsZeroStats else { return nil }
        let formatted = count.formatted()
        return Item(text: formatted, symbol: symbol, accessibilityLabel: "\(formatted) \(noun)")
    }

    /// Language / words / chapters / engagement counts / published date, below
    /// the justified row.
    ///
    /// With "Show zero counts" on (the default) every known zero holds its place.
    /// Remote callers normalize AO3's omitted full-blurb counts to zero first;
    /// sparse rows leave them nil because AO3 did not publish those stats.
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

    private var topStatsRow: WorkTopStatsRow {
        WorkTopStatsRow(rating: rating, categories: categories, warnings: warnings,
                         completion: completion, isExpanded: isExpanded)
    }

    /// For tests: the collapse rule is the thing worth pinning. See
    /// `WorkTopStatsRow.categoryChipTexts`/`.warningChipTexts`.
    var categoryChipTexts: [String] { topStatsRow.categoryChipTexts }
    var warningChipTexts: [String] { topStatsRow.warningChipTexts }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            topStatsRow
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

    /// The text chip's glyph: the same plain check, half-filled ring and "?"
    /// the tile draws (`WorkSymbolTile.completion`).
    var symbol: String {
        switch self {
        case .complete: "checkmark"
        case .inProgress: "circle.lefthalf.filled"
        case .unknown: "questionmark"
        }
    }

    /// The text chip's tint. WIP takes its soft tile's ink, not Mature's orange.
    var color: Color {
        switch self {
        case .complete: AO3TagPalette.general
        case .inProgress: AO3TagPalette.wipInk
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
        case .present(let count): count == 1 ? "1 Warning" : "\(count) Warnings"
        }
    }

    /// The same three states as a bare figure under a WARNINGS label, for the
    /// stat strip spec 1a puts under a work's title. Two things change at that
    /// size: the label already names the field, so `text`'s "No Warnings" would
    /// state it twice, and a count reads better as a figure beside its
    /// neighbouring "3/3" and "412" than as prose.
    var figureText: String {
        switch self {
        case .none: "None"
        case .undisclosed: "Undisclosed"
        case .present(let count): "\(count)"
        }
    }

    /// The text chip's glyph: the dash, "?" and "!" the tile draws
    /// (`WorkSymbolTile.warnings`).
    var symbol: String {
        switch self {
        case .none: "minus"
        case .undisclosed: "questionmark"
        case .present: "exclamationmark"
        }
    }

    var color: Color {
        switch self {
        case .none: .gray
        case .undisclosed: AO3TagPalette.mature
        case .present: AO3TagPalette.explicit
        }
    }

    /// `color` in the same figure context `figureText` serves. Its gray for
    /// `.none` is AO3's own legend, and correct in a row of badge icons where
    /// gray reads as "nothing flagged" against its red and orange neighbours.
    /// As the only text in a stat cell it reads instead as dimmed-out, making
    /// the cell look less important than the three beside it when what it says
    /// — this work carries no warnings — is a fact the reader came for. Spec 1a
    /// paints it green for that reason; the other two keep the ramp's colours.
    var figureColor: Color {
        switch self {
        case .none: AO3TagPalette.general
        case .undisclosed, .present: color
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

    /// Author · words · chapters, the dot-separated line the redesign puts under
    /// a local work's title — the Home resume hero and the Library ledger row.
    ///
    /// One implementation because there were two, byte for byte, in
    /// `HomeResumeHero` and `WorkRow`. That is the duplication the review of
    /// Codex's `38c42f4` recorded as finding 6 and left unpaid; a second verbatim
    /// copy appeared afterwards, which is what an unpaid formatting debt does.
    ///
    /// Takes values rather than a `SavedWork` so it is a pure function with a
    /// test that needs no model context.
    static func localWorkMetadata(author: String, wordCount: Int, chapters: String) -> [String] {
        var segments: [String] = []
        let name = author.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            segments.append(name)
        }
        if wordCount > 0 {
            // Compact past 999 — "1K", "1.25K", "33.7K", "1.2M" — owner's call,
            // 2026-09-12, to buy the ledger row's narrow metadata column back
            // the width "33,700 words" was spending on digits. Below 1000 the
            // notation prints the plain figure, so short works read unchanged.
            //
            // `.compactName` is what the app already uses for a big figure in a
            // small space (`SearchView`, `ReadingInsightsView`, `MediaBrowserView`);
            // the two fraction digits are what keep 1,250 as "1.25K" rather than
            // rounding it to the default one digit's "1.2K".
            let figure = wordCount.formatted(
                .number.notation(.compactName).precision(.fractionLength(0...2))
            )
            segments.append(figure + " words")
        }
        let chapterRange = chapters.trimmingCharacters(in: .whitespacesAndNewlines)
        if !chapterRange.isEmpty {
            segments.append(chapterRange)
        }
        return segments
    }

    /// The full AO3 stat line a detailed card used to show, as the ledger's
    /// one dot-separated line: author, language, words, chapters, comments,
    /// kudos, bookmarks, hits, and the updated date.
    ///
    /// A local work stores 0 until AO3 has been asked, and that 0 means
    /// unknown. Zero counts are printed only when the reader shows zeros and
    /// the work has a word count, which is how a refreshed blurb is told from
    /// a sparse row. Positive counts are printed either way.
    static func fullLedgerStatLine(
        author: String,
        language: String,
        wordCount: Int,
        chapters: String,
        comments: Int,
        kudos: Int,
        bookmarks: Int,
        hits: Int,
        dateUpdated: String,
        showsZeroStats: Bool
    ) -> [String] {
        var segments: [String] = []
        let name = author.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { segments.append(name) }
        let languageName = language.trimmingCharacters(in: .whitespacesAndNewlines)
        if !languageName.isEmpty { segments.append(languageName) }
        func count(_ value: Int, singular: String, plural: String? = nil) -> String? {
            let known = value > 0 || (showsZeroStats && wordCount > 0)
            guard known else { return nil }
            let noun = value == 1 ? singular : (plural ?? "\(singular)s")
            return "\(value.formatted()) \(noun)"
        }
        if let words = count(wordCount, singular: "word") { segments.append(words) }
        let chapterRange = chapters.trimmingCharacters(in: .whitespacesAndNewlines)
        if !chapterRange.isEmpty { segments.append(chapterRange) }
        for item in [
            count(comments, singular: "comment"),
            count(kudos, singular: "kudos", plural: "kudos"),
            count(bookmarks, singular: "bookmark"),
            count(hits, singular: "hit")
        ].compactMap(\.self) {
            segments.append(item)
        }
        let updated = dateUpdated.trimmingCharacters(in: .whitespacesAndNewlines)
        if !updated.isEmpty { segments.append(displayDate(updated)) }
        return segments
    }

    /// Visible segments and the VoiceOver sentence for a ledger row.
    ///
    /// Author is not here: the row gives the byline its own line. Kudos is a
    /// heart in the text and the word "kudos" when spoken. Chapters gain a
    /// " ch" unit unless the string already has one. Words stay grouped, not
    /// compact. The line wraps, so none of these facts are ellipsized away.
    struct LedgerFigures: Equatable {
        var visible: [String]
        var spoken: String
    }

    /// `zeroCountsRequireWords` matches `fullLedgerStatLine`: a local 0 is
    /// unknown until the work has a word count. Remote rows pass false, so an
    /// explicit 0 still prints when the reader shows zeros, and nil stays unknown.
    static func ledgerFigures(
        language: String,
        wordCount: Int?,
        chapters: String,
        comments: Int?,
        kudos: Int?,
        bookmarks: Int?,
        hits: Int?,
        dateUpdated: String,
        showsZeroStats: Bool,
        zeroCountsRequireWords: Bool = false
    ) -> LedgerFigures {
        let wordsKnown = (wordCount ?? 0) > 0
        func printed(_ value: Int?) -> Int? {
            guard let value else { return nil }
            if value > 0 { return value }
            guard showsZeroStats, value == 0 else { return nil }
            if zeroCountsRequireWords, !wordsKnown { return nil }
            return value
        }

        var visible: [String] = []
        var spoken: [String] = []
        func append(_ text: String, say: String? = nil) {
            visible.append(text)
            spoken.append(say ?? text)
        }

        let languageName = language.trimmingCharacters(in: .whitespacesAndNewlines)
        if !languageName.isEmpty { append(languageName) }
        if let words = wordCount, words > 0 {
            append("\(words.formatted()) words")
        }
        let chapterRange = chapters.trimmingCharacters(in: .whitespacesAndNewlines)
        if !chapterRange.isEmpty {
            let shown = chapterRange.range(of: "ch", options: .caseInsensitive) == nil
                ? "\(chapterRange) ch"
                : chapterRange
            append(shown)
        }
        if let comments = printed(comments) {
            append("\(comments.formatted()) \(comments == 1 ? "comment" : "comments")")
        }
        if let kudos = printed(kudos) {
            append("♥ \(kudos.formatted())", say: "\(kudos.formatted()) kudos")
        }
        if let bookmarks = printed(bookmarks) {
            append("\(bookmarks.formatted()) \(bookmarks == 1 ? "bookmark" : "bookmarks")")
        }
        if let hits = printed(hits) {
            append("\(hits.formatted()) \(hits == 1 ? "hit" : "hits")")
        }
        let updated = dateUpdated.trimmingCharacters(in: .whitespacesAndNewlines)
        if !updated.isEmpty {
            let display = displayDate(updated)
            append(display, say: "Updated \(display)")
        }
        return LedgerFigures(visible: visible, spoken: spoken.joined(separator: ", "))
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

    /// AO3's own General/Teen/Mature/Explicit colour coding, in AO3's own hexes
    /// (`AO3TagPalette`), so the rating carries meaning at a glance. As text on a
    /// page use `ratingInk(_:on:)`: these are tile fills.
    static func ratingColor(_ rating: String) -> Color? {
        switch rating {
        case "General Audiences": AO3TagPalette.general
        case "Teen And Up Audiences": AO3TagPalette.teen
        case "Mature": AO3TagPalette.mature
        case "Explicit": AO3TagPalette.explicit
        // Explicitly gray rather than nil: falling through to `.tint` painted
        // it the app's red accent, which reads as the most severe rating —
        // the opposite of what "no rating given" means. AO3 leaves its own
        // unrated icon blank for the same reason.
        case "Not Rated": .gray
        default: nil
        }
    }

    /// A rating's colour as *text* on a page (Work Detail's figure strip), not
    /// as a tile. Teen's tile yellow is ~1.6:1 on a light page, so the light
    /// themes print it in L3-TH-4's dark mustard; Dark and OLED take T-419's
    /// readable step, as every accent text does there.
    static func ratingInk(_ rating: String, on theme: ReaderTheme) -> Color? {
        guard let color = ratingColor(rating) else { return nil }
        if theme.colorScheme == .light, rating == "Teen And Up Audiences" {
            return AO3TagPalette.teenTextOnLight
        }
        return theme.accentInk(for: color)
    }

    /// AO3's own category colour coding (a small coloured badge per
    /// relationship-category tag, e.g. F/F, Gen, Multi), in AO3's hexes. The
    /// text chips share one SF Symbol ("person.2.fill") and the colour carries
    /// the distinction; the tiles draw each category's own sign
    /// (`WorkSymbolTile`). Non-nil is also what makes a string a category.
    static func categoryColor(_ category: String) -> Color? {
        switch category {
        case "F/F": AO3TagPalette.femaleFemale
        case "F/M": AO3TagPalette.femaleMale
        case "Gen": AO3TagPalette.general
        case "M/M": AO3TagPalette.maleMale
        // The board has no one colour for Multi (its tile is four quadrants);
        // the text chip keeps its purple tint.
        case "Multi": .purple
        // The light-theme hex; the tile itself lifts it on Dark and OLED.
        case "Other": AO3TagPalette.other
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
        date(from: rawText).map(displayFormatter.string(from:)) ?? rawText
    }

    /// The same date as a `Date`, for arithmetic on it (T-473's age groups); nil
    /// when neither of AO3's formats parses.
    static func date(from rawText: String) -> Date? {
        for formatter in parseFormatters {
            if let date = formatter.date(from: rawText) { return date }
        }
        return nil
    }
}
