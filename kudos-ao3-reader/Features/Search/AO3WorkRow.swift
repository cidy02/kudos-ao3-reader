import SwiftUI

/// One search result row: title, author, fandoms, summary, and key stats. The
/// summary is clamped to a few lines; an expand toggle reveals the full summary
/// plus the work's tags (like AO3's blurb) without opening the work.
struct AO3WorkRow: View {
    enum Presentation: Equatable {
        case standard
        case fandomTop
        case searchLedger
    }

    let work: AO3WorkSummary
    /// Driven by the list's "expand/collapse all" toggle; each card follows it
    /// (and can still be toggled individually afterwards).
    var expandAll: Bool = false
    /// When true, a leading selection circle sits beside the status grid (mirrors `WorkRow`)
    /// and the caller is expected to route taps to selection instead of navigation.
    var isSelecting: Bool = false
    var isSelected: Bool = false
    /// False reserves the 24pt leading selection column without drawing the circle, so
    /// `SensitiveWorkRow` can overlay an unblurred `WorkLeadingSelectionCheck` in the exact slot.
    var showsSelectionIndicator = true
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
    /// Structured reader-response signal (FID40, Quality-Results board).
    var qualitySignal: WorkSignal? = nil
    /// Ranked work context for the Quality-Response sheet.
    var rankedContext: RankedWork? = nil
    /// Search-only local state shown beside the title, such as "In Library".
    var badgeTitle: String? = nil
    /// Detailed surfaces. Off hides the summary paragraph only; tags, the stat
    /// line and the bookmark note stay. A ledger row still shows its summary.
    var showsSummary = true
    /// New chapters since the reader last looked. The "+N" badge and the red bars.
    var badgeCount = 0
    /// Search and fandom results: the grid sits beside the title block only.
    var wide = false
    /// False when a footnote under this row draws the separator for the whole block.
    var showsSeparator = true
    /// False suppresses the row's own expand/collapse button — used when a caller
    /// (SensitiveWorkRow's blurred branch) renders its own copy externally instead,
    /// so the two don't compete for the same top-trailing corner.
    var showsExpandButton = true
    /// Lets a caller drive (and observe) this row's expanded state from outside —
    /// used by SensitiveWorkRow's blurred branch, which renders its own unblurred
    /// expand button but still needs it to expand the blurred content underneath.
    /// Falls back to purely-internal state when nil.
    var externalExpanded: Binding<Bool>?
    /// False suppresses the row's own context menu — used when blurred so long-pressing
    /// a concealed mature work does not pop up a menu detailing it.
    var showsContextMenu = true

    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("showsZeroStats") private var showsZeroStats = true
    @AppStorage(WorkSymbolPlacement.storageKey) private var symbolPlacement: WorkSymbolPlacement = .beside
    @ScaledMetric(relativeTo: .title3) private var bookmarkTitleSize: CGFloat = 19
    @State private var internalExpanded = false
    @State private var showingResponseSheet = false

    private var expandedBinding: Binding<Bool> {
        externalExpanded ?? $internalExpanded
    }

    private var expanded: Bool {
        get { expandedBinding.wrappedValue }
        nonmutating set { expandedBinding.wrappedValue = newValue }
    }

    /// Worth an expand toggle only when there's more to show than the clamped view:
    /// a long summary, any categorized tags — or fandoms the collapsed card folds
    /// into "+N others". Exposed statically so SensitiveWorkRow can decide whether to
    /// render an external expand button without building a row.
    static func isExpandable(
        for work: AO3WorkSummary,
        bookmark: AO3AuthorBookmark? = nil,
        showsSummary: Bool = true
    ) -> Bool {
        if bookmark != nil { return work.fandoms.count > 1 }
        let summaryWarrants = showsSummary && work.summary.count > 120
        return summaryWarrants || work.fandoms.count > 1 || !additionalTags(for: work).isEmpty
            || !work.relationships.isEmpty || !work.characters.isEmpty || !work.warnings.isEmpty
    }

    private var isExpandable: Bool {
        Self.isExpandable(for: work, bookmark: bookmark, showsSummary: showsSummary)
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
            if isSelecting || !showsContextMenu {
                presentedCard
            } else {
                presentedCard.remoteWorkContextMenu(work: work)
            }
        }
        // Follow the global expand/collapse-all toggle (also applies on first
        // appearance so cards scrolled into view match the current state).
        .onChange(of: expandAll, initial: true) { _, value in
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { expandedBinding.wrappedValue = value }
        }
    }

    @ViewBuilder
    private var presentedCard: some View {
        if bookmark != nil {
            bookmarkCard
        } else {
            switch presentation {
            case .standard:
                standardCard
            case .fandomTop, .searchLedger:
                searchLedgerCard
            }
        }
    }

    /// 1q keeps the bookmark's note where the summary would be. The rest of the
    /// ledger — fandom, title, author, every stat, chapter bars — stays.
    private var bookmarkCard: some View {
        WorkPlainRow(wide: wide, showsSeparator: showsSeparator, separatorInset: rowSeparatorInset) {
            selectionCheck
        } symbols: { arrangement in
            symbols(arrangement)
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

    /// 2×2 grid beside the title + a summary: what follows the heading runs full width under the grid,
    /// as in `WorkRow` (owner, 2026-11-09).
    private var summaryRunsFullWidth: Bool {
        WorkRow.summaryRunsFullWidth(
            placement: presentation == .fandomTop ? .underTitle : symbolPlacement,
            isStacked: dynamicTypeSize.isAccessibilitySize,
            hasSummary: showsSummary && !work.summary.isEmpty
        )
    }

    private var fullWidthLeadingPadding: CGFloat {
        summaryRunsFullWidth ? WorkRow.fullWidthSummaryLeadingPadding(isSelecting: isSelecting) : 0
    }

    private var standardCard: some View {
        WorkPlainRow(
            wide: wide || summaryRunsFullWidth,
            showsSeparator: showsSeparator,
            separatorInset: rowSeparatorInset
        ) {
            selectionCheck
        } symbols: { arrangement in
            symbols(arrangement)
        } heading: {
            standardHeading
        } remainder: {
            Group {
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
                    WorkRowExpandedDetails(animate: !expandAll) {
                        VStack(alignment: .leading, spacing: 12) {
                            if presentation == .fandomTop {
                                chipGroup("Fandoms", Array(nonemptyFandoms.dropFirst()), field: .fandom)
                            }
                            // No "Archive Warnings" group: expanding turns the stats row's
                            // warning chip into the warnings themselves.
                            chipGroup("Relationships", work.relationships, field: .relationship)
                            chipGroup("Characters", work.characters, field: .character)
                            chipGroup("Additional Tags", additionalTags, field: .freeform)
                        }
                    }
                }
                statsRow
                if showsPerformance {
                    AO3AuthorPerformanceStrip(work: work)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, fullWidthLeadingPadding)
        }
    }

    /// Fandom label, title, author, summary, every stat, and equal chapter bars.
    /// A remote work has no downloaded lengths and no reading progress.
    private var searchLedgerCard: some View {
        WorkPlainRow(
            wide: wide || summaryRunsFullWidth,
            showsSeparator: showsSeparator,
            separatorInset: rowSeparatorInset,
            placementOverride: presentation == .fandomTop ? .underTitle : nil
        ) {
            selectionCheck
        } symbols: { arrangement in
            symbols(arrangement)
        } heading: {
            ledgerIdentity
        } remainder: {
            Group {
                if !expanded {
                    WorkTagLineView(
                        relationships: work.relationships,
                        characters: work.characters,
                        freeforms: additionalTags,
                        onTap: { tag, field in router.searchAO3(field, tag) }
                    )
                }
                if expanded {
                    WorkRowExpandedDetails(animate: !expandAll) {
                        if presentation == .fandomTop {
                            VStack(alignment: .leading, spacing: 6) {
                                inlineTagGroup("Fandoms", nonemptyFandoms, field: .fandom)
                                inlineTagGroup("Warnings", work.warnings, field: .warning)
                                inlineTagGroup("Relationships", work.relationships, field: .relationship)
                                inlineTagGroup("Characters", work.characters, field: .character)
                                inlineTagGroup("Additional tags", additionalTags, field: .freeform)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                chipGroup("Fandoms", Array(nonemptyFandoms.dropFirst()), field: .fandom)
                                chipGroup("Archive Warnings", work.warnings, field: .warning)
                                chipGroup("Relationships", work.relationships, field: .relationship)
                                chipGroup("Characters", work.characters, field: .character)
                                chipGroup("Additional Tags", additionalTags, field: .freeform)
                            }
                        }
                    }
                }
                if showsSummary, !work.summary.isEmpty {
                    Text(work.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(expanded || dynamicTypeSize.isAccessibilitySize
                            ? nil
                            : (presentation == .fandomTop ? 3 : 2))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .animation(nil, value: expanded)
                }
                if presentation == .fandomTop {
                    seriesLine
                    searchStatsGrid
                } else {
                    ledgerFacts
                }
                searchLedgerSignal
                if showsPerformance {
                    AO3AuthorPerformanceStrip(work: work)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, fullWidthLeadingPadding)
        }
    }

    private var standardHeading: some View {
        VStack(alignment: .leading, spacing: 2) {
            if presentation == .fandomTop {
                fandomLabel
            }
            HStack(alignment: .top, spacing: 6) {
                Text(work.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                WorkPlusBadge(count: badgeCount)
                if let badgeTitle {
                    SubjectStateBadge(title: badgeTitle, color: themeManager.effectiveTint)
                }
                Spacer(minLength: 4)
                if !work.dateUpdated.isEmpty {
                    WorkUpdatedDateBadge(dateUpdated: work.dateUpdated)
                }
                if isExpandable && showsExpandButton { expandButton }
            }
            if presentation == .fandomTop {
                authorByline
            } else {
                authorAndFandoms
            }
        }
    }

    @ViewBuilder
    private var authorByline: some View {
        if !work.authors.isEmpty {
            // Two lines: AO3 writes a pseud as "pseud (login)", so co-authors outgrow one line.
            AO3AuthorBylineView(
                names: work.authors,
                identities: work.authorIdentities,
                font: .subheadline
            )
            .fixedSize(horizontal: false, vertical: true)
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
            // Only between them on one line: stacked, the dot was a line of its own.
            if !wraps, !work.authors.isEmpty, !visibleFandoms.isEmpty {
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

    @ViewBuilder
    private var selectionCheck: some View {
        if Self.selectionEdge(isSelecting: isSelecting) == .leading {
            if showsSelectionIndicator {
                WorkLeadingSelectionCheck(isSelected: isSelected)
            } else {
                Color.clear.frame(width: 24, height: 24)
            }
        }
    }

    private func symbols(_ arrangement: WorkStatusIconGrid.Arrangement) -> some View {
        WorkStatusIconGrid(
            rating: work.rating.isEmpty ? nil : work.rating,
            categories: work.categories,
            warnings: work.warnings,
            completion: WorkCompletionStatus(isComplete: work.isComplete),
            tileSize: 24,
            announcesToVoiceOver: true,
            arrangement: arrangement
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
            layout: ChapterBarModel.layout(
                chapters: work.chapters,
                progress: nil,
                weights: nil,
                newChapterCount: badgeCount,
                scale: .row
            ),
            label: nil
        )
    }

    private var searchStatsGrid: some View {
        let isFullBlurb = work.words != nil
        func count(_ value: Int?) -> Int? {
            value ?? (isFullBlurb ? 0 : nil)
        }
        return WorkListStatsGrid(cells: WorkListStatsGrid.cells(
            words: work.words,
            chapters: work.chapters,
            kudos: count(work.kudos),
            hits: count(work.hits),
            comments: count(work.comments),
            bookmarks: count(work.bookmarks),
            language: work.language,
            dateUpdated: work.dateUpdated
        ))
    }

    @ViewBuilder
    private var seriesLine: some View {
        if let title = work.seriesTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            let position = work.seriesPosition.map { String($0) } ?? "—"
            if let rawURL = work.seriesURL, let url = URL(string: rawURL) {
                Button { router.open(url) } label: {
                    seriesLabel(position: position, title: title)
                }
                .buttonStyle(.borderless)
                .minimumHitTarget()
            } else {
                seriesLabel(position: position, title: title)
            }
        }
    }

    private func seriesLabel(position: String, title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("Part \(position) of")
                .foregroundStyle(.secondary)
            Text(title)
                .foregroundStyle(themeManager.accentInk)
        }
        .font(.footnote)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    /// Series, Private and Rec sit on bookmark kickers. Without a fandom there was
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

    private var effectiveSignal: WorkSignal? {
        qualitySignal ?? signal.map { WorkSignal(label: $0, note: nil, tone: .neutral) }
    }

    /// Reader-response signal: tone chip + grey note (FID40, Quality-Results board).
    /// Tapping opens the Reader Response sheet (Quality-Response board).
    @ViewBuilder
    private var searchLedgerSignal: some View {
        if let sig = effectiveSignal {
            WorkSignalRow(signal: sig) {
                showingResponseSheet = true
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sheet(isPresented: $showingResponseSheet) {
                QualityResponseSheet(
                    work: work,
                    rankedEntry: rankedContext,
                    signal: sig
                )
            }
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

    static func crossoverAccessibilityLabel(fandoms: [String]) -> String? {
        let names = fandoms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard names.count > 1 else { return nil }
        return "Crossover with \(names.dropFirst().joined(separator: ", "))"
    }

    static func statusText(
        readingState: SavedWork.ReadingState,
        chapterLabel: String?,
        isWantToRead: Bool,
        queueCount: Int,
        isInLibrary: Bool
    ) -> String? {
        if readingState == .finished { return "Finished" }
        if readingState == .inProgress {
            let chapter = chapterLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
            return chapter.flatMap { $0.isEmpty ? nil : "Reading · \($0)" } ?? "Reading"
        }
        if isWantToRead { return "Want to Read" }
        if queueCount > 0 { return "In a queue" }
        return isInLibrary ? "In Library" : nil
    }

    static func localStatus(for work: SavedWork?) -> String? {
        guard let work else { return nil }
        let chapter = work.readingProgressLabel.flatMap { $0.hasPrefix("Ch ") ? $0 : nil }
        return statusText(
            readingState: work.readingState,
            chapterLabel: chapter,
            isWantToRead: work.isOnSavedForLaterShelf,
            queueCount: work.activeQueueMemberships.count,
            isInLibrary: !work.isQueueOnlyWork
        )
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

    /// Expand/collapse control. Search/fandom rows place the plain chevron on the
    /// kicker line; established rows retain their circular control.
    @ViewBuilder
    private var expandButton: some View {
        let button = Button {
            toggleExpanded()
        } label: {
            // No rotation animation (see WorkRowExpandButton).
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(presentation == .fandomTop
                    ? .system(size: 14, weight: .semibold)
                    : .caption.weight(.semibold))
        }
        if presentation == .fandomTop {
            button
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityLabel(expanded ? "Show less" : "Show more")
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        } else if presentation == .searchLedger {
            button
                .buttonStyle(.plain)
                .foregroundStyle(themeManager.accentInk)
                .frame(width: 20, height: 20)
                .layoutFreeHitTarget(30, action: toggleExpanded)
                .accessibilityLabel(expanded ? "Show less" : "Show more")
        } else {
            button
                .buttonStyle(.kudosSecondaryCircle)
                .minimumHitTarget()
                .transaction {
                    $0.animation = nil
                    $0.disablesAnimations = true
                }
                .accessibilityLabel(expanded ? "Show less" : "Show more")
        }
    }

    private func toggleExpanded() {
        // List snapshots both cell layouts when its height animates, causing
        // row/header ghosting (filmed 2026-11-03); keep relayout instant.
        expandedBinding.wrappedValue.toggle()
    }

    /// AO3's freeform/additional tags, defensively filtered against the categorized
    /// groups before display so expanded cards never repeat a tag across sections.
    private var additionalTags: [String] {
        Self.additionalTags(for: work)
    }

    private static func additionalTags(for work: AO3WorkSummary) -> [String] {
        let categorized = Set((work.fandoms + work.warnings + work.relationships + work.characters)
            .map(normalizedTag))
        var seen = Set<String>()
        return work.tags.filter { tag in
            let key = normalizedTag(tag)
            guard !categorized.contains(key), seen.insert(key).inserted else { return false }
            return true
        }
    }

    private static func normalizedTag(_ tag: String) -> String {
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

    @ViewBuilder
    private func inlineTagGroup(_ label: String, _ tags: [String], field: AO3TagSearch.Field) -> some View {
        if !tags.isEmpty {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) {
                    inlineTagLabel(label)
                    WorkDetailTagLinks(tags: tags, field: field)
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    inlineTagLabel(label)
                        .frame(width: 84, alignment: .leading)
                    WorkDetailTagLinks(tags: tags, field: field)
                }
            }
        }
    }

    private func inlineTagLabel(_ label: String) -> some View {
        Text(label)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 1)
            .accessibilityAddTraits(.isHeader)
    }
}

// Its own extension so the type body stays within the lint limit.
extension AO3WorkRow {
    enum SelectionEdge: Equatable {
        case none
        case leading
    }

    static func selectionEdge(isSelecting: Bool) -> SelectionEdge {
        isSelecting ? .leading : .none
    }

    static func separatorInset(isSelecting: Bool) -> CGFloat? {
        isSelecting ? 115 : nil
    }

    private var rowSeparatorInset: CGFloat? {
        Self.separatorInset(isSelecting: isSelecting)
    }

    @ViewBuilder
    private var ledgerIdentity: some View {
        if presentation == .fandomTop {
            resultListIdentity
        } else {
            searchLedgerIdentity
        }
    }

    private var resultListIdentity: some View {
        VStack(alignment: .leading, spacing: 5) {
            if primaryFandom != nil || isExpandable || badgeTitle != nil {
                if dynamicTypeSize.isAccessibilitySize {
                    // Beside the badges the kicker stayed one line and was cut
                    // ("THE LOCKED T…"). It takes the width and wraps, as a
                    // page kicker does; the badges wrap under it.
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            fandomLabel
                            crossoverMark
                        }
                        if isExpandable || badgeTitle != nil {
                            HStack(spacing: 5) {
                                if let badgeTitle { UpdateMarker(text: badgeTitle) }
                                if isExpandable && showsExpandButton {
                                    Spacer(minLength: 0)
                                    expandButton
                                }
                            }
                        }
                    }
                } else {
                    HStack(alignment: .center, spacing: 5) {
                        fandomLabel
                        crossoverMark
                        Spacer(minLength: 0)
                        if let badgeTitle { UpdateMarker(text: badgeTitle) }
                        if isExpandable && showsExpandButton {
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
            }
            // Two lines: AO3 writes a pseud as "pseud (login)", so co-authors outgrow one line.
            AO3AuthorBylineView(
                names: work.authors,
                identities: work.authorIdentities,
                font: .subheadline
            )
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

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
                                if isExpandable && showsExpandButton {
                                    expandButton
                                }
                            }
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 5) {
                        fandomLabel
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
                        if isExpandable && showsExpandButton {
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
                if let badgeTitle {
                    SubjectStateBadge(title: badgeTitle, color: themeManager.effectiveTint)
                }
                Spacer(minLength: 4)
            }
            // Two lines: AO3 writes a pseud as "pseud (login)", so co-authors outgrow one line.
            AO3AuthorBylineView(
                names: work.authors,
                identities: work.authorIdentities,
                font: .subheadline
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
                additionalCount: presentation == .fandomTop
                    ? 0
                    : (expanded ? 0 : max(0, nonemptyFandoms.count - 1)),
                action: { router.searchAO3(.fandom, fandom) }
            )
        }
    }

    @ViewBuilder
    private var crossoverMark: some View {
        if let label = Self.crossoverAccessibilityLabel(fandoms: nonemptyFandoms) {
            WorkCrossoverMark(color: palette.accent, accessibilityLabel: label)
        }
    }
}

private struct WorkCrossoverMark: View {
    let color: Color
    let accessibilityLabel: String

    @ScaledMetric(relativeTo: .caption) private var size: CGFloat = 12
    @ScaledMetric(relativeTo: .caption) private var stroke: CGFloat = 1.5

    var body: some View {
        ZStack {
            Circle()
                .stroke(color, lineWidth: stroke)
                .frame(width: size, height: size)
                .offset(x: -size * 0.22)
            Circle()
                .stroke(color, lineWidth: stroke)
                .frame(width: size, height: size)
                .offset(x: size * 0.22)
        }
        .frame(width: size * 1.45, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}
