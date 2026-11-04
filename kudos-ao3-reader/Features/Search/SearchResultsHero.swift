import SwiftUI

/// Pure logic for AO3 result lists (search results, fandom works, tag works).
/// Covers header copy, loading footer status, and unique work appending.
enum AO3ResultListPaging {
    static func title(subject: String?, query: String?, hasLibrarySections: Bool = false) -> String {
        if hasLibrarySections {
            return "On AO3"
        }
        let subject = subject?.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let subject, !subject.isEmpty {
            if let query, !query.isEmpty, subject == query {
                return "“\(query)”"
            }
            return subject
        }
        if let query, !query.isEmpty {
            return "“\(query)”"
        }
        return "Search Results"
    }

    static func subtitle(total: Int) -> String {
        let count = total.formatted()
        return "\(count) \(total == 1 ? "work" : "works") on AO3"
    }

    static func countText(total: Int) -> String {
        "\(total.formatted()) \(total == 1 ? "work" : "works")"
    }

    static func footerLoadingText(loaded: Int, total: Int, page: Int) -> String {
        "\(loaded.formatted()) of \(total.formatted()) · loading page \(page)"
    }

    static func footerLoadedText(loaded: Int, total: Int) -> String {
        if total > 0 {
            return "\(loaded.formatted()) of \(total.formatted()) works"
        }
        return "\(loaded.formatted()) \(loaded == 1 ? "work" : "works")"
    }

    static func appendUnique(newWorks: [AO3WorkSummary], to existingWorks: [AO3WorkSummary]) -> [AO3WorkSummary] {
        var seen = Set(existingWorks.map(\.id))
        var combined = existingWorks
        for work in newWorks {
            if seen.insert(work.id).inserted {
                combined.append(work)
            }
        }
        return combined
    }

    static func furthestLoadedPage(currentPage: Int, loadedPages: [Int]) -> Int {
        max(currentPage, loadedPages.max() ?? currentPage)
    }
}

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
    /// `.subjectPage` is the redesign header (T-492, boards 15 and 18):
    /// the query or fandom as a Large Title, with "N works on AO3",
    /// Sort (T-473), Filters (filled with a count when active) and layout capsules,
    /// followed by active-filter chips.
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
    /// The sort control 1k puts beside the subject. Nil draws the sort as plain
    /// text instead, which is what a caller with no binding to offer should get
    /// rather than a menu that cannot change anything.
    var sortSelection: Binding<AO3SearchFilters.Sort>?
    /// The orders the menu offers. A tag listing has no relevance order, so
    /// Browse's pages leave Best Match out.
    var sortOptions: [AO3SearchFilters.Sort] = AO3SearchFilters.Sort.allCases
    /// Toggles summaries in wide ledger rows (T-492).
    var showSummaries: Binding<Bool>?
    /// Query string for search results title display.
    var query: String?
    /// Redesigned header variant: when library sections are shown above on the combined
    /// search page (Board 11), the title reads "On AO3" with the count beside it.
    var showsOnAO3Header: Bool = false
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Beyond this the chips would crowd out the works. The overflow is *counted*
    /// rather than silently dropped, so the card never implies it listed everything.
    private static let visibleChipLimit = 6

    /// The results page is scoped to whatever was searched, so it takes that
    /// subject's hue — the same one its work cards take, which is what makes a
    /// gold fandom's results page and its rows read as one surface. A free-text
    /// search names no subject, so it falls back to the app accent (spec 1m's
    /// rule for anything not scoped to a work).
    private var palette: SubjectPalette {
        guard let subject = summary.subject else { return themeManager.scopePalette }
        return themeManager.appTheme.subjectPalette(hue: CoverArt.hue(for: subject))
    }

    @ViewBuilder
    var body: some View {
        switch presentation {
        case .card: cardBody
        case .subjectPage: subjectPageBody
        }
    }

    // MARK: - Redesigned result list header (T-492, boards 15 and 18)

    private var subjectPageBody: some View {
        let displayTitle = showsOnAO3Header
            ? "On AO3"
            : AO3ResultListPaging.title(subject: summary.subject, query: query)
        let countFact = showsOnAO3Header
            ? AO3ResultListPaging.countText(total: summary.total)
            : AO3ResultListPaging.subtitle(total: summary.total)
        let filterCount = nonSortFilterLabels.count

        return VStack(alignment: .leading, spacing: 10) {
            if showsOnAO3Header {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        onAO3TitleBlock(title: displayTitle, count: countFact)
                        Spacer(minLength: 0)
                        sortControl
                        filterControl(count: filterCount)
                        layoutControl
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        onAO3TitleBlock(title: displayTitle, count: countFact)
                        HStack(spacing: 8) {
                            sortControl
                            filterControl(count: filterCount)
                            Spacer(minLength: 0)
                            layoutControl
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .minimumScaleFactor(0.85)
                        .accessibilityAddTraits(.isHeader)

                    Text(countFact)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        sortControl
                        filterControl(count: filterCount)
                        Spacer(minLength: 0)
                        layoutControl
                    }
                    FlowLayout(spacing: 8, rowSpacing: 8) {
                        sortControl
                        filterControl(count: filterCount)
                        layoutControl
                    }
                }
            }

            if !nonSortFilterLabels.isEmpty {
                FlowLayout(spacing: 6, rowSpacing: 6) {
                    ForEach(nonSortFilterLabels, id: \.self) { label in
                        Button {
                            onEditFilters?()
                        } label: {
                            HStack(spacing: 4) {
                                if let symbol = label.symbol {
                                    Image(systemName: symbol)
                                        .font(.caption2)
                                }
                                Text(label.text)
                                    .font(.footnote.weight(.semibold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .frame(minHeight: 30)
                            .background(themeManager.appTheme.glassFill(0.12))
                            .foregroundStyle(Color.primary)
                            .clipShape(SubjectMetrics.controlShape(dynamicTypeSize))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(label.text), opens Filters")
                    }
                }
            }
        }
        .padding(.horizontal, SubjectMetrics.gutter)
    }

    private func onAO3TitleBlock(title: String, count: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.primary)
                .accessibilityAddTraits(.isHeader)

            Text(count)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
                    ForEach(sortOptions) { option in
                        Text(option.title).tag(option)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(sortLabelText)
                        .font(.subheadline)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(minHeight: 32)
                .background(themeManager.appTheme.glassFill(0.12))
                .foregroundStyle(Color.primary)
                .clipShape(SubjectMetrics.controlShape(dynamicTypeSize))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sort by: \(sortLabelText)")
        } else if !sortLabelText.isEmpty {
            HStack(spacing: 4) {
                Text(sortLabelText)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 32)
            .background(themeManager.appTheme.glassFill(0.12))
            .foregroundStyle(Color.primary)
            .clipShape(SubjectMetrics.controlShape(dynamicTypeSize))
        }
    }

    private func filterControl(count: Int) -> some View {
        Button {
            onEditFilters?()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.caption.weight(.semibold))
                Text(count > 0 ? "Filters · \(count)" : "Filters")
                    .font(.subheadline.weight(count > 0 ? .semibold : .regular))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 32)
            .background(count > 0 ? themeManager.effectiveTint : themeManager.appTheme.glassFill(0.12))
            .foregroundStyle(count > 0 ? ThemeManager.label(on: themeManager.effectiveTint) : Color.primary)
            .clipShape(SubjectMetrics.controlShape(dynamicTypeSize))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0 ? "Filters, \(count) active" : "Filters")
    }

    @ViewBuilder
    private var layoutControl: some View {
        if let showSummaries {
            Button {
                showSummaries.wrappedValue.toggle()
            } label: {
                Image(systemName: showSummaries.wrappedValue ? "text.alignleft" : "rectangle.grid.1x2")
                    .font(.subheadline)
                    .frame(width: 32, height: 32)
                    .background(themeManager.appTheme.glassFill(0.12))
                    .foregroundStyle(Color.primary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showSummaries.wrappedValue ? "Layout: rows with summaries" : "Layout: compact rows")
            .accessibilityHint("Toggles summaries in search results")
        }
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

/// How many filters the Search toolbar's Filter button counts: what the hero's
/// Filters capsule counts for the same search — every summary label except the
/// subject, which the heading already names, and the sort, which is always in
/// effect and has its own control. One function so the two cannot disagree.
enum SearchFilterBadge {
    static func count(for filters: AO3SearchFilters) -> Int {
        filters.summaryLabels(excluding: filters.searchSubject.text, includesSort: false).count
    }
}

/// Redesigned loading footer at the end of AO3 search and fandom result lists (T-492).
/// Replaces the old SearchPaginationBar with an explicit next-page action.
struct AO3ResultListEndFooter: View {
    let loadedCount: Int
    let totalCount: Int
    let currentPage: Int
    let totalPages: Int
    let isLoading: Bool
    var targetPage: Int?
    var errorMessage: String?
    let loadNextPage: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(AO3ResultListPaging.footerLoadingText(
                        loaded: loadedCount,
                        total: totalCount,
                        page: targetPage ?? (currentPage + 1)
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Loading page \(targetPage ?? (currentPage + 1)), \(loadedCount) of \(totalCount) works loaded so far")
            } else if let errorMessage {
                VStack(spacing: 6) {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again", action: loadNextPage)
                        .buttonStyle(.kudosSecondary)
                }
            } else if currentPage < totalPages {
                Text(AO3ResultListPaging.footerLoadedText(loaded: loadedCount, total: totalCount))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Load Page \(currentPage + 1)", action: loadNextPage)
                    .buttonStyle(.kudosSecondary)
            } else {
                Text(AO3ResultListPaging.footerLoadedText(loaded: loadedCount, total: totalCount))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 12)
        .padding(.horizontal, SubjectMetrics.gutter)
    }
}
