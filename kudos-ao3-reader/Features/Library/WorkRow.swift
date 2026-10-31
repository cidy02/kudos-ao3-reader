import SwiftData
import SwiftUI

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
    /// When true, a selection bubble takes the top-right corner (where the expand
    /// control normally sits) and the expand control shifts to its left instead of
    /// disappearing.
    var isSelecting: Bool = false
    var isSelected: Bool = false
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
    @State private var internalExpanded = false
    @State private var chapterWeights: [Int]?

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
                ledgerRow.task(id: chapterCacheKey) { await loadChapterWeights() }
            }
        }
        .downloadDimmed(work)
        .onChange(of: expandAll, initial: true) { _, value in expandedBinding.wrappedValue = value }
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

    /// File size and modification date, so a replaced EPUB measures again.
    /// "none" when there is no download: those bars stay equal.
    private var chapterCacheKey: String {
        guard work.hasEPUB else { return "none" }
        let values = try? work.fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = values?.fileSize ?? -1
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? -1
        return "\(work.id.uuidString)-\(size)-\(modified)"
    }

    private var chapterBarItems: [ChapterBarItem] {
        ChapterBarModel.items(
            chapters: work.chapters,
            progress: work.readingProgress,
            isFinished: work.isFinished,
            weights: chapterWeights,
            newChapterCount: badgeCount
        )
    }

    private var chapterProgressLabel: String? {
        ChapterBarGeometry.progressLabel(
            chapters: work.chapters,
            progress: work.readingProgress,
            isFinished: work.isFinished
        )
    }

    private func loadChapterWeights() async {
        guard work.hasEPUB else {
            chapterWeights = nil
            return
        }
        let id = work.id
        let url = work.fileURL
        let measured = await Task.detached(priority: .utility) {
            ChapterLengthCache.weights(workID: id, fileURL: url)
        }.value
        guard work.modelContext != nil else { return }
        chapterWeights = measured
    }

    private var ledgerRow: some View {
        WorkPlainRow(wide: wide, showsSeparator: showsSeparator) {
            statusGrid
        } heading: {
            ledgerHeading
        } remainder: {
            if !work.author.isEmpty {
                AO3AuthorBylineView(
                    displayText: work.author,
                    identities: work.verifiedAuthorIdentities,
                    font: .subheadline,
                    compact: !dynamicTypeSize.isAccessibilitySize
                )
                .fixedSize(horizontal: false, vertical: true)
            }
            if !ledgerSummaryText.isEmpty {
                Text(ledgerSummaryText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            WorkLedgerStatsLine(figures: ledgerFigures)
            WorkChapterBarLine(items: chapterBarItems, label: chapterProgressLabel)
        }
    }

    @ViewBuilder
    private var ledgerHeading: some View {
        if let fandom = nonemptyFandomNames.first {
            WorkFandomLabel(
                title: FandomDisplayName.bareTitle(fandom),
                palette: subjectPalette,
                additionalCount: max(0, nonemptyFandomNames.count - 1),
                action: { router.searchAO3(.fandom, fandom) }
            )
        }
        titleLine(showsFavorite: showsFavoriteStar && work.isFavorite, favoriteTint: .subjectFavoriteGold)
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
        WorkPlainRow(wide: wide, showsSeparator: showsSeparator) {
            statusGrid
        } heading: {
            standardHeading(isExpandable: isExpandable)
        } remainder: {
            standardRemainder(summaryText: summaryText)
        }
    }

    @ViewBuilder
    private func standardHeading(isExpandable: Bool) -> some View {
        titleLine(
            showsFavorite: work.isFavorite,
            favoriteTint: theme.appTheme.favoriteColor,
            dateUpdated: work.dateUpdated,
            datePublished: work.datePublished,
            showsExpand: isExpandable && showsExpandButton
        )
        authorAndFandoms
    }

    @ViewBuilder
    private func standardRemainder(summaryText: String) -> some View {
        if !expandedBinding.wrappedValue {
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
        if expandedBinding.wrappedValue {
            if work.hasCategorizedWorkTags {
                chipGroup("Relationships", work.workRelationships, field: .relationship)
                chipGroup("Characters", work.workCharacters, field: .character)
                chipGroup("Additional Tags", work.workFreeforms, field: .freeform)
            } else {
                chipGroup("Tags", work.workTags, field: .freeform)
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
        if let standardProgress {
            WorkReadProgressBar(progress: standardProgress)
        }
    }

    private var statusGrid: some View {
        WorkStatusIconGrid(
            rating: work.rating.isEmpty ? nil : work.rating,
            categories: work.workCategories,
            warnings: work.workWarnings,
            completion: work.completionStatus,
            tileSize: Self.ledgerTileSize,
            announcesToVoiceOver: true
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
            if isSelecting {
                WorkSelectionBubble(isSelected: isSelected)
            }
        }
    }

    @ViewBuilder
    private var authorAndFandoms: some View {
        if !work.author.isEmpty || !nonemptyFandomNames.isEmpty {
            ViewThatFits(in: .horizontal) {
                byline(wraps: false)
                byline(wraps: true)
            }
        }
    }

    private func byline(wraps: Bool) -> some View {
        let layout = wraps
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 4))
        return layout {
            if !work.author.isEmpty {
                AO3AuthorBylineView(
                    displayText: work.author,
                    identities: work.verifiedAuthorIdentities,
                    font: .subheadline,
                    compact: !dynamicTypeSize.isAccessibilitySize
                )
            }
            if !work.author.isEmpty, !nonemptyFandomNames.isEmpty {
                Text("·")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            if !nonemptyFandomNames.isEmpty {
                Text(nonemptyFandomNames.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(expandedBinding.wrappedValue || dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .animation(nil, value: expandedBinding.wrappedValue)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
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
            // No `withAnimation`: these rows live in a `List`, and animating a
            // row's height change makes it composite a snapshot of the old cell
            // over the new one. Toggling instantly relayouts in one frame.
            expanded.toggle()
        } label: {
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.kudosSecondaryCircle)
        .minimumHitTarget()
        .accessibilityLabel(expanded ? "Show less" : "Show more")
    }
}
