import SwiftUI

/// One search result row: title, author, fandoms, summary, and key stats. The
/// summary is clamped to a few lines; an expand toggle reveals the full summary
/// plus the work's tags (like AO3's blurb) without opening the work.
struct AO3WorkRow: View {
    enum Presentation: Equatable {
        case standard
        case searchLedger
    }

    let work: AO3WorkSummary
    /// Driven by the list's "expand/collapse all" toggle; each card follows it
    /// (and can still be toggled individually afterwards).
    var expandAll: Bool = false
    /// When true, a selection bubble takes the top-right corner (mirrors `WorkRow`)
    /// and the caller is expected to route taps to selection instead of navigation.
    var isSelecting: Bool = false
    var isSelected: Bool = false
    /// Search opts into the redesign without changing the shared row in Browse,
    /// Account, Authors, or Library before those screens receive their own pass.
    var presentation: Presentation = .standard
    /// Own Works and Dashboard put parsed performance figures inside the card.
    var showsPerformance = false
    /// A bookmark fixes the row to 1q's search-ledger composition: its note
    /// replaces the work summary, its tags are always visible, and its date
    /// closes the metadata row.
    var bookmark: AO3AuthorBookmark?
    /// Search's computed-sort figure (T-473 "Show the signal on each result"),
    /// drawn under the ledger's figures in their style. Nil draws nothing.
    var signal: String?
    /// Detailed surfaces. Off hides the summary paragraph only; tags, the stat
    /// line and the bookmark note stay. A ledger row still shows its summary.
    var showsSummary = true
    /// New chapters since the reader last looked. The "+N" badge and the red bars.
    var badgeCount = 0
    /// Search and fandom results: the grid sits beside the title block only.
    var wide = false
    /// False when a footnote under this row draws the separator for the whole block.
    var showsSeparator = true

    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("showsZeroStats") private var showsZeroStats = true
    @ScaledMetric(relativeTo: .title3) private var bookmarkTitleSize: CGFloat = 19
    @State private var expanded = false

    /// Worth an expand toggle only when there's more to show than the clamped view:
    /// a long summary, any categorized tags — or fandoms the collapsed card folds
    /// into "+N others". Without that last clause a crossover with a short summary
    /// and no tags would hide its extra fandoms behind no control at all.
    private var isExpandable: Bool {
        if bookmark != nil { return work.fandoms.count > 1 }
        let summaryWarrants = showsSummary && work.summary.count > 120
        return summaryWarrants || work.fandoms.count > 1 || !additionalTags.isEmpty
            || !work.relationships.isEmpty || !work.characters.isEmpty || !work.warnings.isEmpty
    }

    /// Collapsed, a card names the work's main fandom and counts the rest. AO3
    /// blurbs for a crossover can carry a dozen, each of them long — unfolded they
    /// pushed the summary off the card and made every result the same height.
    private var visibleFandoms: [String] {
        expanded ? work.fandoms : Array(work.fandoms.prefix(1))
    }

    private var hiddenFandomCount: Int {
        max(0, work.fandoms.count - visibleFandoms.count)
    }

    var body: some View {
        Group {
            if isSelecting {
                presentedCard
            } else {
                presentedCard.remoteWorkContextMenu(work: work)
            }
        }
        // Follow the global expand/collapse-all toggle (also applies on first
        // appearance so cards scrolled into view match the current state).
        .onChange(of: expandAll, initial: true) { _, value in expanded = value }
    }

    @ViewBuilder
    private var presentedCard: some View {
        if bookmark != nil {
            bookmarkCard
        } else {
            switch presentation {
            case .standard:
                standardCard
            case .searchLedger:
                searchLedgerCard
            }
        }
    }

    /// 1q keeps the bookmark's note where the summary would be. The rest of the
    /// ledger — fandom, title, author, every stat, chapter bars — stays.
    private var bookmarkCard: some View {
        WorkPlainRow(wide: wide, showsSeparator: showsSeparator) {
            statusGrid
        } heading: {
            searchLedgerIdentity
        } remainder: {
            if let bookmark, !bookmark.notes.isEmpty || !bookmark.tags.isEmpty {
                AO3BookmarkFootnote(bookmark: bookmark)
            }
            ledgerFacts
            if let bookmark, !bookmark.date.isEmpty {
                Text(bookmark.date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Bookmarked \(bookmark.date)")
            }
        }
    }

    private var standardCard: some View {
        WorkPlainRow(wide: wide, showsSeparator: showsSeparator) {
            statusGrid
        } heading: {
            standardHeading
        } remainder: {
            if !expanded {
                WorkTagLineView(
                    relationships: work.relationships,
                    characters: work.characters,
                    freeforms: additionalTags,
                    onTap: { tag, field in router.searchAO3(field, tag) }
                )
            }
            if showsSummary, !work.summary.isEmpty {
                Text(work.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(expanded || dynamicTypeSize.isAccessibilitySize ? nil : 3)
                    .multilineTextAlignment(.leading)
                    .animation(nil, value: expanded)
            }
            if expanded {
                // No "Archive Warnings" group: expanding turns the stats row's
                // warning chip into the warnings themselves.
                chipGroup("Relationships", work.relationships, field: .relationship)
                chipGroup("Characters", work.characters, field: .character)
                chipGroup("Additional Tags", additionalTags, field: .freeform)
            }
            statsRow
            if showsPerformance {
                AO3AuthorPerformanceStrip(work: work)
            }
        }
    }

    /// Fandom label, title, author, summary, every stat, and equal chapter bars.
    /// A remote work has no downloaded lengths and no reading progress.
    private var searchLedgerCard: some View {
        WorkPlainRow(wide: wide, showsSeparator: showsSeparator) {
            statusGrid
        } heading: {
            searchLedgerIdentity
        } remainder: {
            if !work.summary.isEmpty {
                Text(work.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(expanded || dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(nil, value: expanded)
            }
            if !expanded {
                WorkTagLineView(
                    relationships: work.relationships,
                    characters: work.characters,
                    freeforms: additionalTags,
                    onTap: { tag, field in router.searchAO3(field, tag) }
                )
            }
            if expanded {
                chipGroup("Fandoms", Array(nonemptyFandoms.dropFirst()), field: .fandom)
                chipGroup("Archive Warnings", work.warnings, field: .warning)
                chipGroup("Relationships", work.relationships, field: .relationship)
                chipGroup("Characters", work.characters, field: .character)
                chipGroup("Additional Tags", additionalTags, field: .freeform)
            }
            ledgerFacts
            searchLedgerSignal
            if showsPerformance {
                AO3AuthorPerformanceStrip(work: work)
            }
        }
    }

    private var standardHeading: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 6) {
                Text(work.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                WorkPlusBadge(count: badgeCount)
                Spacer(minLength: 4)
                if !work.dateUpdated.isEmpty {
                    WorkUpdatedDateBadge(dateUpdated: work.dateUpdated)
                }
                if isExpandable { expandButton }
                if isSelecting { WorkSelectionBubble(isSelected: isSelected) }
            }
            authorAndFandoms
        }
    }

    @ViewBuilder
    private var authorAndFandoms: some View {
        if !work.authors.isEmpty || !nonemptyFandoms.isEmpty {
            ViewThatFits(in: .horizontal) {
                authorFandomLine(wraps: false)
                authorFandomLine(wraps: true)
            }
        }
    }

    private func authorFandomLine(wraps: Bool) -> some View {
        let layout = wraps
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 4))
        return layout {
            if !work.authors.isEmpty {
                AO3AuthorBylineView(
                    names: work.authors,
                    identities: work.authorIdentities,
                    font: .subheadline,
                    compact: !dynamicTypeSize.isAccessibilitySize
                )
            }
            if !work.authors.isEmpty, !visibleFandoms.isEmpty {
                Text("·")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            if !visibleFandoms.isEmpty {
                FlowLayout(spacing: 4, rowSpacing: 2) {
                    ForEach(visibleFandoms, id: \.self) { fandom in
                        Button { router.searchAO3(.fandom, fandom) } label: {
                            Text(fandom).multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                    if hiddenFandomCount > 0 {
                        Text("+\(hiddenFandomCount) other\(hiddenFandomCount == 1 ? "" : "s")")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.subheadline)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var statusGrid: some View {
        WorkStatusIconGrid(
            rating: work.rating.isEmpty ? nil : work.rating,
            categories: work.categories,
            warnings: work.warnings,
            completion: WorkCompletionStatus(isComplete: work.isComplete),
            tileSize: 24,
            announcesToVoiceOver: true
        )
    }

    private var remoteFigures: WorkStat.LedgerFigures {
        let isFullBlurb = work.words != nil
        func count(_ value: Int?) -> Int? { value ?? (isFullBlurb ? 0 : nil) }
        return WorkStat.ledgerFigures(
            language: work.language,
            wordCount: work.words,
            chapters: work.chapters,
            comments: count(work.comments),
            kudos: count(work.kudos),
            bookmarks: count(work.bookmarks),
            hits: count(work.hits),
            dateUpdated: work.dateUpdated,
            showsZeroStats: showsZeroStats,
            zeroCountsRequireWords: false
        )
    }

    @ViewBuilder
    private var ledgerFacts: some View {
        WorkLedgerStatsLine(figures: remoteFigures)
        WorkChapterBarLine(
            items: ChapterBarModel.items(
                chapters: work.chapters,
                progress: nil,
                weights: nil,
                newChapterCount: badgeCount
            ),
            label: nil
        )
    }

    /// Series, Private and Rec sit on the kicker's line. Without a fandom there was
    /// no line, so a private bookmark of a work that names none did not say so.
    private var hasLedgerBadges: Bool {
        work.seriesTitle != nil || bookmark?.isPrivate == true || bookmark?.isRecommendation == true
    }

    private var statsRow: some View {
        // Same sparse-row rule as `ledgerMetadata`: AO3's full blurb always
        // prints words, so without it missing engagement figures are unknown.
        let isFullBlurb = work.words != nil
        func count(_ value: Int?) -> Int? { value ?? (isFullBlurb ? 0 : nil) }
        return WorkListStatsRow(
            rating: work.rating.isEmpty ? nil : work.rating,
            categories: work.categories,
            warnings: work.warnings,
            completion: WorkCompletionStatus(isComplete: work.isComplete),
            language: work.language,
            wordCount: work.words,
            chapters: work.chapters,
            comments: count(work.comments),
            kudos: count(work.kudos),
            bookmarks: count(work.bookmarks),
            hits: count(work.hits),
            // AO3WorkSummary carries only AO3's single revised date, rendered
            // separately by both presentations.
            isExpanded: expanded
        )
    }

    /// One more figure, so it reads as the row's stats do: same size, same grey.
    @ViewBuilder
    private var searchLedgerSignal: some View {
        if let signal {
            Text(signal)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Ranking: \(signal)")
        }
    }

    /// Pure formatting seam for the ledger's visible text and regression tests.
    static func ledgerMetadata(
        for work: AO3WorkSummary,
        showsZeroStats: Bool,
        includesPerformance: Bool = true
    ) -> [String] {
        var metadata: [String] = []
        let language = work.language.trimmingCharacters(in: .whitespacesAndNewlines)
        if !language.isEmpty {
            metadata.append(language)
        }
        // A blurb always has a word count. Without one this is a sparse list
        // row (subscriptions, marked for later), whose stats are unknown, not
        // zero — on a full blurb a missing count is AO3 omitting a zero.
        let isFullBlurb = work.words != nil
        func count(_ value: Int?) -> Int? { value ?? (isFullBlurb ? 0 : nil) }
        if let words = ledgerCount(work.words, singular: "word", showsZeroStats: showsZeroStats) {
            metadata.append(words)
        }
        let chapters = work.chapters.trimmingCharacters(in: .whitespacesAndNewlines)
        if !chapters.isEmpty {
            metadata.append(chapters)
        }
        guard includesPerformance else { return metadata }
        for item in [
            ledgerCount(count(work.comments), singular: "comment", showsZeroStats: showsZeroStats),
            ledgerCount(count(work.kudos), singular: "kudos", plural: "kudos", showsZeroStats: showsZeroStats),
            ledgerCount(count(work.bookmarks), singular: "bookmark", showsZeroStats: showsZeroStats),
            ledgerCount(count(work.hits), singular: "hit", showsZeroStats: showsZeroStats),
        ].compactMap(\.self) {
            metadata.append(item)
        }
        return metadata
    }

    private static func ledgerCount(
        _ value: Int?,
        singular: String,
        plural: String? = nil,
        showsZeroStats: Bool
    ) -> String? {
        guard let count = value, count > 0 || showsZeroStats else { return nil }
        let noun = count == 1 ? singular : (plural ?? "\(singular)s")
        return "\(count.formatted()) \(noun)"
    }

    private var nonemptyFandoms: [String] {
        work.fandoms.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var primaryFandom: String? {
        nonemptyFandoms.first.map(FandomDisplayName.bareTitle)
    }

    private var workHue: Double {
        CoverArt.workHue(fandoms: work.fandoms, title: work.title)
    }

    private var palette: SubjectPalette {
        themeManager.appTheme.subjectPalette(hue: workHue)
    }

    /// Expand/collapse control, bottom-right of the card. A bordered circular
    /// button (not plain text) so it reads as a tappable affordance; borderless
    /// interaction would blend into the background. Captures its own tap so it
    /// never triggers the row's navigation link.
    @ViewBuilder
    private var expandButton: some View {
        let button = Button {
            // No `withAnimation`: these rows live in a `List`, and animating a
            // row's height change makes it composite a snapshot of the old cell
            // over the new one. The two layouts differ in height, so every
            // element — title, byline, fandom, stats — ghosts over the expanded
            // summary and chips for the duration. Toggling instantly relayouts
            // in one frame with nothing to cross-fade.
            expanded.toggle()
        } label: {
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.caption.weight(.semibold))
        }
        if presentation == .searchLedger {
            // Spec 1k draws this inline with the kicker as a bare 20pt glyph; it is
            // a control, so it takes the app colour. It gets a 30pt hit target rather
            // than the full 44: the fandom button sits 5pt to its left, and a
            // 44pt region here reached back over that button's own label.
            button
                .buttonStyle(.plain)
                .foregroundStyle(themeManager.accentInk)
                .frame(width: 20, height: 20)
                .minimumHitTarget(30)
                .accessibilityLabel(expanded ? "Show less" : "Show more")
        } else {
            button
                .buttonStyle(.bordered)
                .foregroundStyle(.accentInk)
                .accentFill()
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .minimumHitTarget()
                .accessibilityLabel(expanded ? "Show less" : "Show more")
        }
    }

    /// AO3's freeform/additional tags, defensively filtered against the categorized
    /// groups before display so expanded cards never repeat a tag across sections.
    private var additionalTags: [String] {
        let categorized = Set((work.fandoms + work.warnings + work.relationships + work.characters)
            .map(normalizedTag))
        var seen = Set<String>()
        return work.tags.filter { tag in
            let key = normalizedTag(tag)
            guard !categorized.contains(key), seen.insert(key).inserted else { return false }
            return true
        }
    }

    private func normalizedTag(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// A labeled group of tappable tag chips; each chip runs an AO3 search for that
    /// tag. Borderless so a chip tap doesn't trigger the row's navigation link.
    @ViewBuilder
    private func chipGroup(_ label: String, _ tags: [String], field: AO3TagSearch.Field) -> some View {
        if !tags.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                FlowLayout(spacing: 6, rowSpacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        Button { router.searchAO3(field, tag) } label: { TagChip(text: tag, symbol: field.symbol) }
                            .buttonStyle(.borderless)
                            .minimumHitTarget(28)
                    }
                }
            }
            .padding(.top, 2)
        }
    }
}

// Its own extension so the type body stays within the lint limit.
extension AO3WorkRow {
    private var searchLedgerIdentity: some View {
        VStack(alignment: .leading, spacing: 5) {
            if primaryFandom != nil || isExpandable || hasLedgerBadges {
                if dynamicTypeSize.isAccessibilitySize {
                    // Beside the badges the kicker stayed one line and was cut
                    // ("THE LOCKED T…"). It takes the width and wraps, as a
                    // page kicker does; the badges wrap under it.
                    VStack(alignment: .leading, spacing: 6) {
                        fandomLabel
                        if hasLedgerBadges || isExpandable {
                            FlowLayout(spacing: 5, rowSpacing: 6) {
                                if work.seriesTitle != nil {
                                    SubjectStateBadge(title: "Series", color: palette.accent)
                                }
                                if bookmark?.isPrivate == true {
                                    SubjectStateBadge(title: "Private", color: .secondary)
                                }
                                if bookmark?.isRecommendation == true {
                                    SubjectStateBadge(title: "Rec", color: .secondary)
                                }
                                if isExpandable {
                                    expandButton
                                }
                            }
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 5) {
                        fandomLabel
                        // 1u row 2: "Series" beside the kicker. Gift is drawn
                        // too, but no gift flag is parsed onto the summary yet.
                        if work.seriesTitle != nil {
                            SubjectStateBadge(title: "Series", color: palette.accent)
                        }
                        if let bookmark {
                            if bookmark.isPrivate {
                                SubjectStateBadge(title: "Private", color: .secondary)
                            }
                            if bookmark.isRecommendation {
                                SubjectStateBadge(title: "Rec", color: .secondary)
                            }
                        }
                        if isExpandable {
                            expandButton
                        }
                    }
                }
            }
            HStack(alignment: .top, spacing: 6) {
                Text(work.title)
                    .font(bookmark == nil
                        ? .headline.weight(.semibold)
                        : .system(size: bookmarkTitleSize, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                WorkPlusBadge(count: badgeCount)
                Spacer(minLength: 4)
                if isSelecting {
                    WorkSelectionBubble(isSelected: isSelected)
                }
            }
            AO3AuthorBylineView(
                names: work.authors,
                identities: work.authorIdentities,
                font: .subheadline,
                compact: !dynamicTypeSize.isAccessibilitySize
            )
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    @ViewBuilder
    private var fandomLabel: some View {
        if let fandom = nonemptyFandoms.first {
            WorkFandomLabel(
                title: FandomDisplayName.bareTitle(fandom),
                palette: palette,
                additionalCount: expanded ? 0 : max(0, nonemptyFandoms.count - 1),
                action: { router.searchAO3(.fandom, fandom) }
            )
        }
    }
}
