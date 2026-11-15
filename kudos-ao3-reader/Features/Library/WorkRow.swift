import SwiftData
import SwiftUI

/// Leading checkmark circle for multi-select work rows (e.g. Add Works sheet, board 06).
struct WorkLeadingSelectionCheck: View {
    var isSelected: Bool

    var body: some View {
        Group {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .accentFill)
            } else {
                Image(systemName: "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

/// One row representing a saved work, reused across Library and Bookmarks. Mirrors
/// the Search result row (`AO3WorkRow`) — title, author, fandoms, summary, and a
/// stats line — so the two lists read consistently, plus a Library-specific
/// favorite marker. The richer fields (fandoms, word count, chapters, kudos) fill
/// in once the work has been refreshed from AO3 in the background.
struct WorkRow: View {
    /// `.standard` is the full row: title, author and fandom, a tag preview,
    /// summary, expandable tag groups, the stats line, and a progress bar.
    /// `.ledger` is the scan row: fandom label, title, author, a two-line
    /// summary, every stat, and chapter bars.
    enum Presentation: Equatable {
        case standard
        case ledger
    }

    let work: SavedWork
    /// Driven by a list's "expand/collapse all" toggle; each card follows it and can
    /// still be toggled individually afterwards. Mirrors `AO3WorkRow`.
    var expandAll: Bool = false
    /// When true, a leading selection circle sits beside the status grid
    /// and the caller is expected to route taps to selection instead of navigation.
    var isSelecting: Bool = false
    var isSelected: Bool = false
    /// False reserves the 24pt leading selection column without drawing the circle, so
    /// `SensitiveWorkRow` can overlay an unblurred `WorkLeadingSelectionCheck` in the exact slot.
    var showsSelectionIndicator: Bool = true
    /// False suppresses the row's own expand/collapse button — used when a caller
    /// (SensitiveWorkRow's blurred branch) renders its own copy externally instead,
    /// so the two don't compete for the same top-trailing corner.
    var showsExpandButton: Bool = true
    /// Lets a caller drive (and observe) this row's expanded state from outside —
    /// used by SensitiveWorkRow's blurred branch, which renders its own unblurred
    /// expand button but still needs it to expand the blurred content underneath.
    /// Falls back to purely-internal state when nil.
    var externalExpanded: Binding<Bool>?
    var presentation: Presentation = .standard
    /// 1aj draws a filled gold star beside the title on Favorites. Off elsewhere:
    /// 1ah and 1ai draw no star, so this is not a property of being favourited but
    /// of being on the screen that is about it. A shelf whose old default was the
    /// detailed card passes true, so the star is not lost when that list becomes
    /// a ledger.
    var showsFavoriteStar = false
    /// Kept so existing call sites compile. A ledger row always prints every stat;
    /// the flag no longer chooses a shorter line.
    var showsFullLedgerStats = false
    /// Detailed rows only. Off hides the summary paragraph; tags still expand.
    /// A ledger row still shows a two-line summary when the work has one.
    var showsSummary = true
    /// When false, skips tag lines and tag groups in the remainder.
    var showsTags = true
    /// When false, skips the reading progress bar in the remainder.
    var showsProgress = true
    /// Kept so existing call sites compile; selection in `WorkRow` is always leading.
    var leadingSelection = true
    /// New chapters since the reader last looked. Draws the "+N" badge and marks
    /// those bars. Only Subscriptions has a count today.
    var badgeCount = 0
    /// Results pages put the grid beside the title block only.
    var wide = false
    /// False when a footnote under this row draws the separator for the whole block.
    var showsSeparator = true

    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("showsZeroStats") private var showsZeroStats = true
    @AppStorage(WorkSymbolPlacement.storageKey) private var symbolPlacement: WorkSymbolPlacement = .defaultValue
    @State private var internalExpanded = false
    @State private var chapterLengths: ChapterLengths?

    private var expandedBinding: Binding<Bool> {
        externalExpanded ?? $internalExpanded
    }

    /// The four-tag grid's 24pt tiles.
    static let ledgerTileSize: CGFloat = 24

    /// Worth an expand toggle only when there's more to reveal than the clamped view:
    /// a long summary or any categorized tags. Exposed statically so SensitiveWorkRow
    /// can decide whether to render an external expand button without building a row.
    static func isExpandable(for work: SavedWork, showsSummary: Bool = true) -> Bool {
        let summary = showsSummary ? work.summary.strippingHTML() : ""
        return isExpandable(strippedSummary: summary, for: work, showsSummary: showsSummary)
    }

    /// Core of `isExpandable(for:)`, taking an already-stripped summary so `body`
    /// (which needs the stripped text anyway) strips it once per render, not per use.
    /// A hidden summary is not a reason to expand.
    private static func isExpandable(
        strippedSummary: String, for work: SavedWork, showsSummary: Bool = true
    ) -> Bool {
        (showsSummary && strippedSummary.count > 120) || !work.workRelationships.isEmpty
            || !work.workCharacters.isEmpty || !work.workFreeforms.isEmpty
            || (!work.hasCategorizedWorkTags && !work.workTags.isEmpty)
    }

    @ViewBuilder
    var body: some View {
        let _ = showsFullLedgerStats
        Group {
            switch presentation {
            case .standard: standardRow
            // A ledger row does not expand. The facts a disclosure used to reveal
            // are on Work Detail, one tap away. Owner's call, 2026-09-12.
            case .ledger:
                ledgerRow.task(id: ChapterLengthCache.taskKey(for: work)) {
                    chapterLengths = await ChapterLengthCache.lengths(for: work)
                }
            }
        }
        .downloadDimmed(work)
        .onChange(of: expandAll, initial: true) { _, value in
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { expandedBinding.wrappedValue = value }
        }
    }

    // MARK: - Ledger

    private var subjectHue: Double {
        CoverArt.workHue(fandoms: work.workFandoms, title: work.title)
    }

    private var subjectPalette: SubjectPalette {
        theme.appTheme.subjectPalette(hue: subjectHue)
    }

    private var nonemptyFandomNames: [String] {
        work.workFandoms.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var ledgerSummaryText: String {
        work.summary.strippingHTML()
    }

    private var ledgerFigures: WorkStat.LedgerFigures {
        WorkStat.ledgerFigures(
            language: work.language,
            wordCount: work.wordCount,
            chapters: work.chapters,
            comments: work.comments,
            kudos: work.kudos,
            bookmarks: work.bookmarks,
            hits: work.hits,
            dateUpdated: work.dateUpdated,
            showsZeroStats: showsZeroStats,
            zeroCountsRequireWords: true
        )
    }

    private var chapterBarLayout: ChapterBarLayout {
        ChapterBarModel.layout(
            chapters: work.chapters,
            progress: work.readingProgress,
            isFinished: work.isFinished,
            weights: chapterLengths?.positions,
            heights: chapterLengths?.words,
            newChapterCount: badgeCount,
            scale: .row
        )
    }

    private var chapterProgressLabel: String? {
        ChapterBarGeometry.progressLabel(
            chapters: work.chapters,
            progress: work.readingProgress,
            isFinished: work.isFinished,
            weights: chapterLengths?.positions
        )
    }

    enum SelectionEdge: Equatable {
        case none
        case leading
    }

    static func selectionEdge(isSelecting: Bool) -> SelectionEdge {
        isSelecting ? .leading : .none
    }

    /// Where the text column starts once the leading check is in the row: screen
    /// padding, the 22 pt check, the status-icon grid, and the gaps either side.
    /// Set by eye against boards 08/09 rather than derived, so re-check it if the
    /// check's size or `WorkRowMetrics.gridColumn` changes.
    static let selectingSeparatorInset: CGFloat = 115

    static func separatorInset(isSelecting: Bool) -> CGFloat? {
        isSelecting ? selectingSeparatorInset : nil
    }

    static func summaryRunsFullWidth(
        placement: WorkSymbolPlacement,
        isStacked: Bool,
        hasSummary: Bool
    ) -> Bool {
        placement == .beside && !isStacked && hasSummary
    }

    static func fullWidthSummaryLeadingPadding(isSelecting: Bool) -> CGFloat {
        isSelecting ? WorkRowMetrics.selectingUnderTitleInset - WorkRowMetrics.screenInset : 0
    }

    private var ledgerRow: some View {
        let summaryRunsFullWidth = Self.summaryRunsFullWidth(
            placement: symbolPlacement,
            isStacked: dynamicTypeSize.isAccessibilitySize,
            hasSummary: !ledgerSummaryText.isEmpty
        )
        return WorkPlainRow(
            wide: wide || summaryRunsFullWidth,
            showsSeparator: showsSeparator,
            separatorInset: Self.separatorInset(isSelecting: isSelecting)
        ) {
            selectionCheck
        } symbols: { arrangement in
            symbols(arrangement)
        } heading: { includesByline in
            // The author already leads the remainder unless the summary runs full
            // width, which is Beside the Title only. Leave it there.
            ledgerHeading(includesByline: includesByline && summaryRunsFullWidth)
        } byline: {
            EmptyView()
        } remainder: {
            fullWidthSummaryRemainder(enabled: summaryRunsFullWidth) {
                if !summaryRunsFullWidth { ledgerByline }
                if !ledgerSummaryText.isEmpty {
                    Text(ledgerSummaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                WorkLedgerStatsLine(figures: ledgerFigures)
                WorkChapterBarLine(layout: chapterBarLayout, label: chapterProgressLabel)
            }
        }
    }

    /// The fandom above the title, on every row (owner, 2026-11-09): the first fandom, "+N" for the rest.
    @ViewBuilder
    private var fandomLabel: some View {
        if let fandom = nonemptyFandomNames.first {
            WorkFandomLabel(
                title: FandomDisplayName.bareTitle(fandom),
                palette: subjectPalette,
                additionalCount: max(0, nonemptyFandomNames.count - 1),
                action: { router.searchAO3(.fandom, fandom) }
            )
        }
    }

    @ViewBuilder
    private func ledgerHeading(includesByline: Bool) -> some View {
        fandomLabel
        titleLine(showsFavorite: showsFavoriteStar && work.isFavorite, favoriteTint: .subjectFavoriteGold)
        if includesByline { ledgerByline }
    }

    @ViewBuilder
    private var ledgerByline: some View {
        if !work.author.isEmpty {
            AO3AuthorBylineView(
                displayText: work.author,
                identities: work.verifiedAuthorIdentities,
                font: .subheadline,
                compact: !dynamicTypeSize.isAccessibilitySize
            )
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Standard

    private var standardProgress: Double? {
        if work.isFinished { return 1 }
        guard let progress = work.readingProgress, progress > 0 else { return nil }
        return progress
    }

    @ViewBuilder
    private var standardRow: some View {
        let summaryText = showsSummary ? work.summary.strippingHTML() : ""
        let isExpandable = Self.isExpandable(
            strippedSummary: summaryText, for: work, showsSummary: showsSummary
        )
        let summaryRunsFullWidth = Self.summaryRunsFullWidth(
            placement: symbolPlacement,
            isStacked: dynamicTypeSize.isAccessibilitySize,
            hasSummary: !summaryText.isEmpty
        )
        WorkPlainRow(
            wide: wide || summaryRunsFullWidth,
            showsSeparator: showsSeparator,
            separatorInset: Self.separatorInset(isSelecting: isSelecting),
            insertsByline: hasStandardByline
        ) {
            selectionCheck
        } symbols: { arrangement in
            symbols(arrangement)
        } heading: { includesByline in
            standardHeading(isExpandable: isExpandable, includesByline: includesByline)
        } byline: {
            authorAndFandoms
        } remainder: {
            fullWidthSummaryRemainder(enabled: summaryRunsFullWidth) {
                standardRemainder(summaryText: summaryText)
            }
        }
    }

    private func fullWidthSummaryRemainder<Content: View>(
        enabled: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading) // full width: keep chip rows on the leading edge
            .padding(.leading, enabled ? Self.fullWidthSummaryLeadingPadding(isSelecting: isSelecting) : 0)
    }

    /// Author, plus every fandom once the row is expanded. Empty when there is
    /// nothing to move under the symbol row.
    private var hasStandardByline: Bool {
        !work.author.isEmpty || (expandedBinding.wrappedValue && nonemptyFandomNames.count > 1)
    }

    @ViewBuilder
    private func standardHeading(isExpandable: Bool, includesByline: Bool) -> some View {
        fandomLabel
        titleLine(
            showsFavorite: work.isFavorite,
            favoriteTint: theme.appTheme.favoriteColor,
            dateUpdated: work.dateUpdated,
            datePublished: work.datePublished,
            showsExpand: isExpandable && showsExpandButton && showsTags
        )
        if includesByline { authorAndFandoms }
    }

    @ViewBuilder
    private func standardRemainder(summaryText: String) -> some View {
        if showsTags && !expandedBinding.wrappedValue {
            WorkTagLineView(
                relationships: work.workRelationships,
                characters: work.workCharacters,
                freeforms: work.hasCategorizedWorkTags ? work.workFreeforms : work.workTags,
                onTap: { tag, field in router.searchAO3(field, tag) }
            )
        }
        if !summaryText.isEmpty {
            Text(summaryText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(expandedBinding.wrappedValue || dynamicTypeSize.isAccessibilitySize ? nil : 3)
                .multilineTextAlignment(.leading)
                .animation(nil, value: expandedBinding.wrappedValue)
        }
        if showsTags && expandedBinding.wrappedValue {
            WorkRowExpandedDetails(animate: !expandAll) {
                VStack(alignment: .leading, spacing: 12) {
                    if work.hasCategorizedWorkTags {
                        chipGroup("Relationships", work.workRelationships, field: .relationship)
                        chipGroup("Characters", work.workCharacters, field: .character)
                        chipGroup("Additional Tags", work.workFreeforms, field: .freeform)
                    } else {
                        chipGroup("Tags", work.workTags, field: .freeform)
                    }
                }
            }
        }
        WorkListStatsRow(
            rating: work.rating.isEmpty ? nil : work.rating,
            categories: work.workCategories,
            warnings: work.workWarnings,
            completion: work.completionStatus,
            language: work.language,
            wordCount: work.wordCount,
            chapters: work.chapters,
            comments: work.comments,
            kudos: work.kudos,
            bookmarks: work.bookmarks,
            hits: work.hits,
            datePublished: work.datePublished.isEmpty ? nil : work.datePublished,
            isExpanded: expandedBinding.wrappedValue
        )
        if showsProgress, let standardProgress {
            WorkReadProgressBar(progress: standardProgress)
        }
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
            categories: work.workCategories,
            warnings: work.workWarnings,
            completion: work.completionStatus,
            tileSize: Self.ledgerTileSize,
            announcesToVoiceOver: true,
            arrangement: arrangement
        )
    }

    private func titleLine(
        showsFavorite: Bool,
        favoriteTint: Color,
        dateUpdated: String? = nil,
        datePublished: String? = nil,
        showsExpand: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(work.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            WorkPlusBadge(count: badgeCount)
            Spacer(minLength: 4)
            if showsFavorite {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(favoriteTint)
                    .accessibilityHidden(true)
            }
            if let dateUpdated {
                WorkUpdatedDateBadge(dateUpdated: dateUpdated, datePublished: datePublished)
            }
            if showsExpand { expandButton }
        }
    }

    /// The author; the fandoms are the label above the title. An expanded row
    /// still names every fandom, so "+N" never hides one for good.
    @ViewBuilder
    private var authorAndFandoms: some View {
        if !work.author.isEmpty {
            AO3AuthorBylineView(
                displayText: work.author,
                identities: work.verifiedAuthorIdentities,
                font: .subheadline,
                compact: !dynamicTypeSize.isAccessibilitySize
            )
        }
        if expandedBinding.wrappedValue, nonemptyFandomNames.count > 1 {
            Text(nonemptyFandomNames.joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var expandButton: some View {
        WorkRowExpandButton(expanded: expandedBinding)
    }

    /// A labeled group of tappable tag chips; each runs an AO3 search for that tag
    /// (matching AO3WorkRow). Borderless so a chip tap doesn't trigger navigation.
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

/// The bordered circular expand/collapse toggle shared by `WorkRow` and
/// `SensitiveWorkRow`'s blurred branch (which renders its own copy outside the
/// blur so it stays legible and tappable, driving the row's content via a
/// `Binding` rather than owning its own state).
struct WorkRowExpandButton: View {
    @Binding var expanded: Bool

    var body: some View {
        Button {
            // List snapshots both cell layouts when its height animates, causing
            // row/header ghosting (filmed 2026-11-03); keep relayout instant.
            expanded.toggle()
        } label: {
            // No rotation animation: on collapse List rebuilds the row and any
            // animation here slid the whole button in from the top (filmed 2026-11-03).
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.kudosSecondaryCircle)
        .minimumHitTarget()
        // The details fade leaks into List's late relayout; keep the style background with the instant glyph swap.
        .transaction {
            $0.animation = nil
            $0.disablesAnimations = true
        }
        .accessibilityLabel(expanded ? "Show less" : "Show more")
    }
}

/// Fades only content whose insertion does not change during the animation. The
/// parent row has already completed its instant List relayout before this appears.
struct WorkRowExpandedDetails<Content: View>: View {
    var animate: Bool
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        // Scoped to opacity: a withAnimation here also animated the List's late
        // relayout, sliding the row's chevron ~40 px (filmed 2026-11-03).
        content()
            .animation(reduceMotion || !animate ? nil : .easeOut(duration: 0.2)) {
                $0.opacity(isVisible || reduceMotion || !animate ? 1 : 0)
            }
            .onAppear { isVisible = true }
    }
}
