import Foundation
import SwiftUI

/// The pure decisions behind artboards 1h / Queue details, kept out of the views
/// so each one can be handed fixtures: the progress strip's counts, the "Last
/// read" row, and the kicker path.
enum ReadingQueueFacts {
    /// The design's queue rows estimate silent reading at 200 words per minute
    /// and round to five minutes so the line stays useful rather than precise.
    static let wordsPerMinute: Double = 200

    static func rowDetail(workCount: Int, totalWordCount: Int, offlineCount: Int) -> String {
        rowDetail(
            workCount: workCount,
            timeEstimate: readingTimeEstimate(wordCount: totalWordCount),
            offlineCount: offlineCount
        )
    }

    /// Computes the queue header detail line using each work's remaining reading
    /// time so the queue header and What Fits read the same time-left rule.
    static func headerDetail(for works: [SavedWork], offlineCount: Int) -> String {
        let timeEstimate = remainingMinutes(for: works).flatMap { readingTimeEstimate(minutes: $0) }
        return rowDetail(
            workCount: works.count,
            timeEstimate: timeEstimate,
            offlineCount: offlineCount
        )
    }

    private static func rowDetail(workCount: Int, timeEstimate: String?, offlineCount: Int) -> String {
        guard workCount > 0 else { return "No works yet" }
        var parts = ["\(workCount) work\(workCount == 1 ? "" : "s")"]
        if let timeEstimate {
            parts.append(timeEstimate)
        }
        let offline = min(max(offlineCount, 0), workCount)
        if offline == workCount {
            parts.append("all offline")
        } else if offline > 0 {
            parts.append("\(offline) offline")
        }
        return parts.joined(separator: " · ")
    }

    /// Computes the queue plan facts line ("8 works · about 9 h 40 min · 6 offline")
    /// from a list of saved works, matching the queue organizer and shelf cards.
    static func planFacts(
        for works: [SavedWork],
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> String {
        let offlineCount = works.filter {
            $0.hasEPUB && fileExists($0.fileURL)
        }.count
        let totalWordCount = works.allSatisfy { $0.wordCount > 0 }
            ? works.reduce(0) { $0 + $1.wordCount }
            : 0
        return rowDetail(
            workCount: works.count,
            totalWordCount: totalWordCount,
            offlineCount: offlineCount
        )
    }

    /// Unrounded reading time in minutes at `wordsPerMinute` (200 wpm), or nil
    /// when `wordCount <= 0` so works without word counts are never guessed.
    static func estimatedMinutes(wordCount: Int) -> Double? {
        guard wordCount > 0 else { return nil }
        return Double(wordCount) / wordsPerMinute
    }

    /// Unread share of a work (`0` when finished, `1` before reading starts,
    /// `1 - clampedProgress` once reading has started).
    static func unreadShare(for work: SavedWork) -> Double {
        if work.isFinished { return 0 }
        guard work.hasStartedReading else { return 1 }
        let progress = min(max(work.readingProgress ?? 0, 0), 1)
        return max(0, 1 - progress)
    }

    /// Remaining reading minutes for a single work using `estimatedMinutes` and
    /// `unreadShare`, or nil when `wordCount <= 0`.
    static func minutesLeft(for work: SavedWork) -> Double? {
        guard let total = estimatedMinutes(wordCount: work.wordCount) else { return nil }
        return total * unreadShare(for: work)
    }

    /// Total remaining minutes across a queue's works; withholds the estimate
    /// (`nil`) if any unfinished work lacks a word count or nothing remains.
    static func remainingMinutes(for works: [SavedWork]) -> Double? {
        guard !works.isEmpty,
              works.allSatisfy({ $0.isFinished || $0.wordCount > 0 })
        else { return nil }
        let total = works.reduce(0.0) { $0 + (minutesLeft(for: $1) ?? 0) }
        return total > 0 ? total : nil
    }

    static func readingTimeEstimate(wordCount: Int) -> String? {
        guard let rawMinutes = estimatedMinutes(wordCount: wordCount) else { return nil }
        return readingTimeEstimate(minutes: rawMinutes)
    }

    static func readingTimeEstimate(minutes rawMinutes: Double) -> String? {
        guard rawMinutes > 0 else { return nil }
        let minutes = max(5, Int((rawMinutes / 5).rounded()) * 5)
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 {
            return "about \(hours) h" + (remainder > 0 ? " \(remainder) min" : "")
        }
        return "about \(minutes) min"
    }

    /// 1h's strip and its legend. Three buckets that always sum to the queue's
    /// size: a work with no copy on disk (`.freedHistory`) is neither finished nor
    /// being read, so it counts as unread rather than dropping out of the total.
    struct Progress: Equatable {
        var finished = 0
        var inProgress = 0
        var unread = 0

        var total: Int { finished + inProgress + unread }
    }

    static func progress(of states: [SavedWork.ReadingState]) -> Progress {
        states.reduce(into: Progress()) { progress, state in
            switch state {
            case .finished: progress.finished += 1
            case .inProgress: progress.inProgress += 1
            case .unread, .freedHistory: progress.unread += 1
            }
        }
    }

    /// One queue-bar segment follows its work, rather than grouping finished
    /// and started works together. Unknown legacy progress keeps the old 45% cue.
    static func segmentFill(state: SavedWork.ReadingState, progress: Double?) -> Double {
        switch state {
        case .finished: 1
        case .inProgress: min(max(progress ?? 0.45, 0), 1)
        case .unread, .freedHistory: 0
        }
    }

    /// Spec 1b's "next up 3": the 1-based place of the first work not yet
    /// finished, in queue order. Nil when every work is finished (or none).
    static func nextUpPosition(states: [SavedWork.ReadingState]) -> Int? {
        states.firstIndex { $0 != .finished }.map { $0 + 1 }
    }

    /// The one "Up next" rule for the queue page and the covers waiting behind
    /// its identity card: the first work not yet finished, else the first (a
    /// fully read queue). `inLine` is everything else, in queue order.
    static func upNext(in works: [SavedWork]) -> (upNext: SavedWork?, inLine: [SavedWork]) {
        let states = works.map(\.readingState)
        guard let index = nextUpPosition(states: states).map({ $0 - 1 }) ?? (works.isEmpty ? nil : 0)
        else { return (nil, []) }
        var inLine = works
        return (inLine.remove(at: index), inLine)
    }

    /// Compact queue footer used outside the redesigned row: "7 works · next up 3".
    static func cardFooter(states: [SavedWork.ReadingState]) -> String {
        let count = "\(states.count) work\(states.count == 1 ? "" : "s")"
        guard let position = nextUpPosition(states: states) else { return count }
        return "\(count) · next up \(position)"
    }

    /// Queue details' "Last read": the latest of the member works' own dates.
    static func lastRead(_ dates: [Date?]) -> Date? {
        dates.compactMap(\.self).max()
    }

    /// "Home › Queues" or "Library › Queues", plus "› Queue details" one level in.
    static func kicker(origin: String, isDetails: Bool = false) -> String {
        "\(origin) › Queues" + (isDetails ? " › Queue details" : "")
    }

    /// Whether the queue page's drag handles are live. Reorder always shows the
    /// whole queue (filters step aside), so its drag is live. 1bg: selecting
    /// keeps the handle live too — select and reorder are no longer exclusive —
    /// except under a filter, whose narrowed order can't be written back.
    static func isDragLive(isReordering: Bool, isSelecting: Bool, isNarrowed: Bool) -> Bool {
        isReordering || (isSelecting && !isNarrowed)
    }

    /// The strip's legend — spec 1h: "2 finished · 1 in progress · 9 unread ·
    /// 9 of 12 kept offline".
    static func legend(_ progress: Progress, offlineCount: Int) -> String {
        let offline = offlineCount == progress.total
            ? "all \(progress.total) kept offline"
            : "\(offlineCount) of \(progress.total) kept offline"
        return "\(progress.finished) finished · \(progress.inProgress) in progress · "
            + "\(progress.unread) unread · \(offline)"
    }

    /// Redesigned queue page status legend (T-491, board 04):
    /// "2 finished · 1 in progress · 5 to go".
    static func progressLegend(_ progress: Progress) -> String {
        var parts: [String] = []
        if progress.finished > 0 {
            parts.append("\(progress.finished) finished")
        }
        if progress.inProgress > 0 {
            parts.append("\(progress.inProgress) in progress")
        }
        if progress.unread > 0 {
            parts.append("\(progress.unread) to go")
        }
        if parts.isEmpty {
            return progress.total > 0 ? "All finished" : "Empty queue"
        }
        return parts.joined(separator: " · ")
    }
}

/// 1h's quick filters: All · Unread · Offline · WIP, each with its count. Shaped
/// like `FavoriteQuickFilter`; Unread is the strip's unread bucket and Offline is
/// the header's "kept offline" set, so the chip counts agree with both.
enum QueueQuickFilter: String, CaseIterable, Identifiable {
    case all
    case unread
    case offline
    case wip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .unread: "Unread"
        case .offline: "Offline"
        case .wip: "WIP"
        }
    }

    /// `preservedIDs` is the caller's on-disk check (`hasEPUB` and the file
    /// exists), passed in so this stays a rule rather than a file-system read.
    func apply(to works: [SavedWork], preservedIDs: Set<UUID>) -> [SavedWork] {
        switch self {
        case .all: works
        case .unread: works.filter { $0.readingState == .unread || $0.readingState == .freedHistory }
        case .offline: works.filter { preservedIDs.contains($0.id) }
        // AO3's posted status, as in `FavoriteQuickFilter.wip`.
        case .wip: works.filter { !$0.isComplete }
        }
    }

    static func counts(in works: [SavedWork], preservedIDs: Set<UUID>) -> [QueueQuickFilter: Int] {
        Dictionary(uniqueKeysWithValues: allCases.map {
            ($0, $0.apply(to: works, preservedIDs: preservedIDs).count)
        })
    }
}

/// 1h's strip: one segment per work. Page summaries default to finished / 45%
/// started / unread; queue rows pass each work's real progress. A `Canvas` keeps
/// a long queue to one view; past 40 works the gaps close and it reads as one bar.
struct QueueProgressStrip: View {
    let progress: ReadingQueueFacts.Progress
    let palette: SubjectPalette
    /// Per-work fill in queue order. Nil keeps the page strip's bucket summary.
    var fills: [Double]? = nil
    /// 1h's page strip; 1b's queue card draws a thinner one (3.5, 2.5 apart).
    var height: CGFloat = 5
    var gap: CGFloat = 3

    var body: some View {
        Canvas { context, size in
            let segmentFills = fills ?? Array(repeating: 1.0, count: progress.finished)
                + Array(repeating: 0.45, count: progress.inProgress)
                + Array(repeating: 0.0, count: progress.unread)
            let count = segmentFills.count
            guard count > 0 else { return }
            let spacing: CGFloat = count > 40 ? 0 : gap
            let width = (size.width - spacing * CGFloat(count - 1)) / CGFloat(count)
            let radius = spacing == 0 ? 0 : size.height / 2
            for index in 0 ..< count {
                let rect = CGRect(x: CGFloat(index) * (width + spacing), y: 0, width: width, height: size.height)
                context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(palette.accent.opacity(0.20)))
                let fill = CGFloat(min(max(segmentFills[index], 0), 1))
                guard fill > 0 else { continue }
                var filled = rect
                filled.size.width *= fill
                context.fill(Path(roundedRect: filled, cornerRadius: radius), with: .color(palette.accent))
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .accessibilityElement()
        .accessibilityLabel(
            "\(progress.finished) of \(progress.total) finished, \(progress.inProgress) in progress, \(progress.unread) to go"
        )
    }
}

/// Redesigned queue page header (T-491, board 04):
/// Cover stack (96×96) in queue colour, title (Title 1, 28pt bold), description/notes,
/// detail line ("8 works · about 9 h 40 min · 6 offline"),
/// segmented bar in the queue colour,
/// legend ("2 finished · 1 in progress · 5 to go") + neutral tag chips.
struct QueuePageHeader<FilterRail: View>: View {
    let queue: ReadingQueue
    let works: [SavedWork]
    let preservedIDs: Set<UUID>
    let palette: SubjectPalette
    let onAddTag: () -> Void
    let onOpenSource: (QueueSavedSearchLink) -> Void
    let onManageSources: () -> Void
    let onRemoveSource: (QueueSavedSearchLink) -> Void
    @ViewBuilder var filterRail: () -> FilterRail

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(PrivacyGate.self) private var gate
    @AppStorage("hideMatureContent") private var hideMature = true

    var body: some View {
        let progress = ReadingQueueFacts.progress(of: works.map(\.readingState))
        let fills = works.map {
            ReadingQueueFacts.segmentFill(state: $0.readingState, progress: $0.readingProgress)
        }
        let detailLine = ReadingQueueFacts.headerDetail(
            for: works,
            offlineCount: preservedIDs.count
        )

        VStack(alignment: .leading, spacing: 14) {
            headerTop(detailLine: detailLine)

            if queue.kind != .smart, !queue.allVisibleSources.isEmpty {
                fromSourcesBlock
            }

            if !works.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    QueueProgressStrip(
                        progress: progress,
                        palette: palette,
                        fills: fills,
                        height: 5,
                        gap: 3
                    )

                    progressAndTagsRow(progress: progress)
                }
            }

            filterRail()
        }
    }

    @ViewBuilder
    private var fromSourcesBlock: some View {
        let sources = queue.allVisibleSources
        VStack(alignment: .leading, spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    fromSourcesHeading(count: sources.count)
                    manageSourcesButton
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    fromSourcesHeading(count: sources.count)
                    Spacer(minLength: 8)
                    manageSourcesButton
                }
            }

            ForEach(sources) { link in
                if let kind = link.knownSourceKind {
                    sourceCard(link: link, kind: kind)
                }
            }
        }
    }

    private func fromSourcesHeading(count: Int) -> some View {
        Text("From sources")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondaryInk)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel("From sources, \(count)")
    }

    private var manageSourcesButton: some View {
        Button("Sources", action: onManageSources)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.accentInk)
            .buttonStyle(.plain)
            .minimumHitTarget()
            .accessibilityLabel("Manage sources for \(queue.displayName)")
    }

    private func sourceCard(link: QueueSavedSearchLink, kind: QueueSourceKind) -> some View {
        let name = link.effectiveDisplayName
        let subtitle = link.effectiveSubtitle
        let count = link.displayedNewCount
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
        return Button { onOpenSource(link) } label: {
            HStack(spacing: 10) {
                Image(systemName: kind.symbolName)
                    .foregroundStyle(.secondaryInk)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                layout {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 4) }
                    if let count {
                        Text(QueueSourceChecks.badge(count))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.accentInk)
                    }
                }
                // Stacked at AX sizes there is no Spacer: keep the card full width (third review).
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondaryInk)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(QueueSourceChecks.sourceAccessibilityLabel(
            name: name,
            kind: kind,
            count: link.newResultCount,
            filters: link.search?.filters
        ))
        .accessibilityAction(named: "Remove source") {
            onRemoveSource(link)
        }
        .contextMenu {
            Button { onOpenSource(link) } label: {
                Label("Open on AO3", systemImage: kind.symbolName)
            }
            Button(role: .destructive) { onRemoveSource(link) } label: {
                Label("Remove Source", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func headerTop(detailLine: String) -> some View {
        let titleBlock = VStack(alignment: .leading, spacing: 2) {
            Text(queue.displayName)
                .font(.title.bold())
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .subjectOwnHeadingScrollEffect()

            if let notes = queue.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(detailLine)
                .font(.footnote)
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }

        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                coverStack
                titleBlock
            }
        } else {
            HStack(alignment: .center, spacing: 14) {
                coverStack
                titleBlock
                Spacer(minLength: 0)
            }
        }
    }

    private var coverStack: some View {
        StackedWorkCover(
            kind: .queue,
            name: queue.displayName,
            identity: queue.id,
            hue: queue.hue,
            pickedHex: queue.colorHex,
            // StackedWorkCover's rule: a concealed work's fandom colour stays out.
            backs: Array(works.filter { !gate.isConcealed($0, enabled: hideMature) }.prefix(CoverStackLayout.maxBacks)),
            size: CGSize(width: 96, height: 96)
        )
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func progressAndTagsRow(progress: ReadingQueueFacts.Progress) -> some View {
        let legend = ReadingQueueFacts.progressLegend(progress)
        let sortedTags = queue.tags.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 6) {
                Text(legend)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .lineLimit(1)

                Spacer(minLength: 8)

                tagChips(sortedTags)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(legend)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)

                tagChips(sortedTags)
            }
        }
    }

    @ViewBuilder
    private func tagChips(_ sortedTags: [Tag]) -> some View {
        FlowLayout(spacing: 6, rowSpacing: 6) {
            ForEach(sortedTags) { tag in
                TagChip(text: tag.name)
            }
            Button(action: onAddTag) {
                TagChip(text: "+ Tag")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add tag to queue")
        }
    }
}

/// Under 1h's header, straight on the wash: the strip and its legend, the
/// queue's tags ending in a dashed "+ Tag" (`onAddTag` opens `QueueTagSheet`),
/// the quick filters with their counts, then `filterRail` — the Library's
/// active-filter labels, which the queue page passes only while they narrow.
struct QueueHeaderDetails<FilterRail: View>: View {
    let works: [SavedWork]
    /// The page's on-disk check, so Offline agrees with the header tally.
    let preservedIDs: Set<UUID>
    let tags: [Tag]
    let palette: SubjectPalette
    @Binding var quickFilter: QueueQuickFilter
    let onAddTag: () -> Void
    @ViewBuilder var filterRail: () -> FilterRail

    @ScaledMetric(relativeTo: .caption) private var legendSize: CGFloat = 11.5

    var body: some View {
        let progress = ReadingQueueFacts.progress(of: works.map(\.readingState))
        let counts = QueueQuickFilter.counts(in: works, preservedIDs: preservedIDs)
        VStack(alignment: .leading, spacing: 8) {
            if !works.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    QueueProgressStrip(progress: progress, palette: palette)
                    Text(ReadingQueueFacts.legend(progress, offlineCount: preservedIDs.count))
                        .font(.system(size: legendSize))
                        .foregroundStyle(.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, SubjectMetrics.gutter)
            }
            // The same tag label the organizer's rows draw (1h, 1i).
            FlowLayout(spacing: 6, rowSpacing: 6) {
                ForEach(tags.sorted { $0.name < $1.name }) { tag in
                    QueueRowTagLabel(text: tag.name)
                }
                Button(action: onAddTag) {
                    QueueRowTagLabel(text: "+ Tag", dashed: true)
                }
                .buttonStyle(.plain)
                // The chip follows Dynamic Type; the tap area never drops below 44pt.
                .layoutFreeHitTarget(action: onAddTag)
                .accessibilityLabel("Add a tag to this queue")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SubjectMetrics.gutter)
            .padding(.bottom, 4)
            SubjectPillRail(
                options: QueueQuickFilter.allCases,
                title: { "\($0.title) \((counts[$0] ?? 0).compactCount)" },
                selection: $quickFilter,
                palette: palette
            )
            .padding(.horizontal, SubjectMetrics.gutter)
            filterRail()
        }
    }
}

/// Spec 1bg: the queue's own name, a hairline, then "N / total" in the same
/// tabular-monospace figure the queue page's other counts use.
struct QueueSelectionStatusRow: View {
    let queueName: String
    let selectedCount: Int
    let total: Int

    @ScaledMetric(relativeTo: .caption) private var queueNameSize: CGFloat = 11
    @ScaledMetric(relativeTo: .caption) private var countSize: CGFloat = 11

    var body: some View {
        HStack(spacing: 8) {
            Text(queueName.uppercased())
                .font(.system(size: queueNameSize, weight: .bold))
                .tracking(11 * 0.13)
                .foregroundStyle(.secondaryInk)
                .lineLimit(1)
            Rectangle()
                .fill(Color.primary.opacity(0.14))
                .frame(height: 0.5)
            Text("\(selectedCount) / \(total)")
                .font(.system(size: countSize, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondaryInk)
        }
        .combinedAccessibilityRow("\(queueName), \(selectedCount) of \(total) selected")
    }
}

/// A standalone ledger row used to sit on this wash. T-478 draws no card: the
/// row pads itself. The type stays so a caller can keep the slot.
struct WorkLedgerCardBackground: View {
    let work: SavedWork

    var body: some View {
        let _ = work.id
        return Color.clear.accessibilityHidden(true)
    }
}
