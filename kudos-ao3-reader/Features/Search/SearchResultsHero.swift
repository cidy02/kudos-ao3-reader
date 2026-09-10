import SwiftUI

/// AO3's own result-count line plus the filters producing it:
///
///     Naruto (Anime & Manga)                    1–20
///     142,327 works
///     [Sort: Date Updated] [English] [Complete]
///
/// The total is the one fact a page of blurbs cannot tell you — the app knows it
/// has 20 works and how many pages there are, but "how big is this fandom" exists
/// only in AO3's heading. The chips answer the other half: until now nothing on
/// screen said what was filtering a list once the panel was dismissed, only a
/// filter button that changed colour.
///
/// Tapping anywhere opens the filter panel, which is what makes the chips worth
/// their height — they are the control, not a caption about it.
struct SearchResultsHero: View {
    /// Which of the two shapes this header takes.
    ///
    /// `.card` is the established one: a tappable card sitting in the list, with
    /// the count, the subject and the filter chips stacked inside it.
    ///
    /// `.subjectPage` is artboard 1k — the same facts, but as the page's own
    /// header on the subject's wash: kicker, rule, the total at 32pt, the
    /// subject with a sort dropdown beside it, a four-cell figure strip, and the
    /// filters as a chip rail with a dashed Filter pinned at its end. Not a
    /// restyle of the card but a different arrangement of the same content, so
    /// both live here rather than drifting apart in two files.
    enum Presentation: Equatable {
        case card
        case subjectPage
    }

    let summary: AO3ResultSummary
    /// From `AO3SearchFilters.summaryLabels(excluding:)` — non-default settings
    /// only, always ending with the sort.
    var filterLabels: [AO3SearchFilters.SummaryLabel] = []
    /// The subject's own tag category, so the heading is labelled the way its chips
    /// are — a fandom, a character and a ship should not all look alike. From
    /// `AO3ResultSummary.subjectField(inAnyOf:)`; nil leaves the heading unlabelled
    /// rather than guessing.
    var subjectField: AO3TagSearch.Field?
    var onEditFilters: (() -> Void)?
    var presentation: Presentation = .card
    /// Page numbers for the figure strip. `.card` ignores them — it sits above a
    /// pagination bar that already states them.
    var currentPage: Int = 1
    var totalPages: Int = 1
    /// The sort control 1k puts beside the subject. Nil draws the sort as plain
    /// text instead, which is what a caller with no binding to offer should get
    /// rather than a menu that cannot change anything.
    var sortSelection: Binding<AO3SearchFilters.Sort>?

    @Environment(ThemeManager.self) private var themeManager

    /// Beyond this the chips would crowd out the works. The overflow is *counted*
    /// rather than silently dropped, so the card never implies it listed everything.
    private static let visibleChipLimit = 6

    /// The results page is scoped to whatever was searched, so it takes that
    /// subject's hue — the same one its work cards take, which is what makes a
    /// gold fandom's results page and its rows read as one surface. A free-text
    /// search names no subject, so it falls back to the app accent (spec 1m's
    /// rule for anything not scoped to a work).
    private var palette: SubjectPalette {
        let hue = summary.subject.map { CoverArt.hue(for: $0) } ?? themeManager.scopeHue
        return themeManager.appTheme.subjectPalette(hue: hue)
    }

    @ViewBuilder
    var body: some View {
        switch presentation {
        case .card: cardBody
        case .subjectPage: subjectPageBody
        }
    }

    // MARK: - Artboard 1k

    private var subjectPageBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            SubjectHeaderBlock(
                kicker: "Search results",
                title: "\(summary.total.formatted()) \(summary.total == 1 ? "work" : "works")",
                subtitle: summary.subject,
                palette: palette
            ) {
                sortControl
            }

            SubjectStatStrip(cells: statStripCells, palette: palette)
                .padding(.horizontal, 22)

            if onEditFilters != nil {
                SubjectFilterRail(
                    onOpenFilters: { onEditFilters?() },
                    activeFilterCount: nonSortFilterLabels.count
                ) {
                    ForEach(nonSortFilterLabels, id: \.self) { label in
                        SubjectChip(
                            text: label.text,
                            style: .tinted,
                            systemImage: label.symbol,
                            palette: palette
                        )
                    }
                }
            }
        }
    }

    /// Sort is pulled out of the chip rail and given its own control beside the
    /// subject, per 1k. It is the one setting that is always in effect, so as a
    /// chip it was permanent furniture; as a dropdown it is the thing you reach
    /// for when the order is wrong.
    private var nonSortFilterLabels: [AO3SearchFilters.SummaryLabel] {
        filterLabels.filter { !$0.text.hasPrefix("Sort: ") }
    }

    private var sortLabelText: String {
        if let sortSelection { return sortSelection.wrappedValue.title }
        return filterLabels.first { $0.text.hasPrefix("Sort: ") }?
            .text.replacingOccurrences(of: "Sort: ", with: "") ?? ""
    }

    @ViewBuilder
    private var sortControl: some View {
        if let sortSelection {
            Menu {
                Picker("Sort", selection: sortSelection) {
                    ForEach(AO3SearchFilters.Sort.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            } label: {
                SubjectChip(text: sortLabelText, style: .neutral, trailingImage: "chevron.down")
            }
            .buttonStyle(.plain)
        } else if !sortLabelText.isEmpty {
            SubjectChip(text: sortLabelText, style: .neutral)
        }
    }

    /// Works, active filters, pages, and which page you are on — the four figures
    /// 1k puts under the header. The live page is the highlighted cell, because
    /// it is the only one of the four that answers "where am I" rather than
    /// "how big is this".
    private var statStripCells: [SubjectStatStrip.Cell] {
        [
            SubjectStatStrip.Cell(value: summary.total.formatted(), label: "Works"),
            SubjectStatStrip.Cell(value: "\(nonSortFilterLabels.count)", label: "Filters"),
            SubjectStatStrip.Cell(value: totalPages.formatted(), label: "Pages"),
            SubjectStatStrip.Cell(value: currentPage.formatted(), label: "Page", isHighlighted: true),
        ]
    }

    // MARK: - Established card

    @ViewBuilder
    private var cardBody: some View {
        if let onEditFilters {
            Button(action: onEditFilters) { content }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(spokenLabel))
                .accessibilityHint(Text("Opens filters"))
                .accessibilityAddTraits(.isButton)
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(spokenLabel))
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                // Only tag and user lists name a subject or state a range; a plain
                // search has neither, so its card starts at the count rather than
                // padding out a title row with something invented.
                if summary.subject != nil || summary.range != nil {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let subject = summary.subject {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                if let subjectField {
                                    Image(systemName: subjectField.symbol)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.tint)
                                        .accessibilityHidden(true)
                                }
                                Text(subject)
                                    .font(.title3.weight(.semibold))
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)
                            }
                        }
                        Spacer(minLength: 0)
                        if let range = summary.range {
                            // Tinted rather than the neutral capsule the filter
                            // chips use: it is a status, not another filter, and
                            // side by side they would otherwise read as the same
                            // kind of thing.
                            TagChip(text: "\(range.lowerBound)–\(range.upperBound)", tinted: true)
                                // Fixed-width digits so paging doesn't resize the
                                // badge, and priority so a long fandom name shrinks
                                // before the badge is squeezed out.
                                .monospacedDigit()
                                .layoutPriority(1)
                        }
                    }
                }

                // Icon uses WorkStatLabel's secondary default; the text inherits
                // the secondary style set here.
                //
                // `doc.text` is the app's established Works glyph — the Works tab on
                // both `AccountView` and `AuthorProfileView` uses it. Not
                // `books.vertical`, which is the *fandom* glyph and can appear as a
                // chip one line below on the Search card: two different things must
                // not share an icon inside one card.
                WorkStatLabel(text: countText, symbol: "doc.text")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            if !filterLabels.isEmpty {
                FlowLayout(spacing: 6, rowSpacing: 6) {
                    ForEach(visibleChips, id: \.self) { TagChip(text: $0.text, symbol: $0.symbol) }
                    if overflowCount > 0 { TagChip(text: "+\(overflowCount) more") }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var visibleChips: [AO3SearchFilters.SummaryLabel] {
        Array(filterLabels.prefix(Self.visibleChipLimit))
    }

    private var overflowCount: Int {
        max(0, filterLabels.count - Self.visibleChipLimit)
    }

    private var countText: String {
        "\(summary.total.formatted()) \(summary.total == 1 ? "work" : "works")"
    }

    /// Preview-only: wraps plain strings so the previews stay readable.
    fileprivate static func previewLabels(_ texts: [String]) -> [AO3SearchFilters.SummaryLabel] {
        texts.map { AO3SearchFilters.SummaryLabel(text: $0, symbol: nil) }
    }

    private var spokenLabel: String {
        // The category leads, so VoiceOver says "Fandom, 142,327 works in Naruto …"
        // rather than dropping the glyph's meaning entirely.
        var parts: [String] = []
        if let subjectField { parts.append(subjectField.accessibilityName) }
        parts.append(countText)
        // The verbatim scope, preposition included — "in Naruto (Anime & Manga)"
        // reads correctly aloud where the bare subject used as a heading does not.
        if let scope = summary.scope { parts.append(scope) }
        if let range = summary.range {
            parts.append("showing \(range.lowerBound) to \(range.upperBound)")
        }
        // Every filter, not just the six on screen — the visual cap is about space.
        parts += filterLabels.map(\.text)
        return parts.joined(separator: ", ")
    }
}

#Preview("Browse — fandom with filters") {
    SearchResultsHero(
        summary: AO3ResultSummary(total: 142_327, scope: "in Naruto (Anime & Manga)", range: 1 ... 20),
        filterLabels: SearchResultsHero.previewLabels(["English", "Complete", "Teen And Up+", "Sort: Date Updated"]),
        onEditFilters: {}
    )
    .padding()
}

#Preview("Browse — nothing set") {
    SearchResultsHero(
        summary: AO3ResultSummary(total: 142_327, scope: "in Naruto (Anime & Manga)", range: 1 ... 20),
        filterLabels: SearchResultsHero.previewLabels(["Sort: Date Updated"]),
        onEditFilters: {}
    )
    .padding()
}

#Preview("Overflow") {
    SearchResultsHero(
        summary: AO3ResultSummary(total: 812, scope: "in Naruto (Anime & Manga)", range: 21 ... 40),
        filterLabels: SearchResultsHero.previewLabels([
            "Sasuke Uchiha", "−Time Travel", "Explicit", "No Not Rated",
            "Major Character Death", "Complete", "Words ≥ 1000", "Past week", "Sort: Kudos"
        ]),
        onEditFilters: {}
    )
    .padding()
}

#Preview("Search — no subject or range") {
    SearchResultsHero(
        summary: AO3ResultSummary(total: 92_495, scope: nil, range: 1 ... 20),
        filterLabels: SearchResultsHero.previewLabels(["Sort: Best Match"]),
        onEditFilters: {}
    )
    .padding()
}
