import Foundation
import SwiftUI

/// The pure decisions behind artboards 1h / Queue details, kept out of the views
/// so each one can be handed fixtures: the progress strip's counts, the "Last
/// read" row, and the kicker path.
enum ReadingQueueFacts {
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

    /// Spec 1b's "next up 3": the 1-based place of the first work not yet
    /// finished, in queue order. Nil when every work is finished (or none).
    static func nextUpPosition(states: [SavedWork.ReadingState]) -> Int? {
        states.firstIndex { $0 != .finished }.map { $0 + 1 }
    }

    /// The queue card's footer — spec 1b: "7 works · next up 3".
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

    /// The strip's legend — spec 1h: "2 finished · 1 in progress · 9 unread ·
    /// 9 of 12 kept offline".
    static func legend(_ progress: Progress, offlineCount: Int) -> String {
        let offline = offlineCount == progress.total
            ? "all \(progress.total) kept offline"
            : "\(offlineCount) of \(progress.total) kept offline"
        return "\(progress.finished) finished · \(progress.inProgress) in progress · "
            + "\(progress.unread) unread · \(offline)"
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

/// 1h's strip: one segment per work — finished filled, in progress half filled
/// (as the artboard draws it), unread faint. A `Canvas` so a long queue is one
/// view, not hundreds; past 40 works the gaps close and it reads as one bar.
struct QueueProgressStrip: View {
    let progress: ReadingQueueFacts.Progress
    let palette: SubjectPalette

    var body: some View {
        Canvas { context, size in
            let count = progress.total
            guard count > 0 else { return }
            let gap: CGFloat = count > 40 ? 0 : 3
            let width = (size.width - gap * CGFloat(count - 1)) / CGFloat(count)
            let radius = gap == 0 ? 0 : size.height / 2
            for index in 0 ..< count {
                let rect = CGRect(x: CGFloat(index) * (width + gap), y: 0, width: width, height: size.height)
                context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(palette.accent.opacity(0.22)))
                let fill: CGFloat = index < progress.finished ? 1
                    : index < progress.finished + progress.inProgress ? 0.45 : 0
                guard fill > 0 else { continue }
                var filled = rect
                filled.size.width *= fill
                context.fill(Path(roundedRect: filled, cornerRadius: radius), with: .color(palette.accent))
            }
        }
        .frame(height: 5)
        .clipShape(Capsule())
        .accessibilityElement()
        .accessibilityLabel(
            "\(progress.finished) finished, \(progress.inProgress) in progress, \(progress.unread) unread"
        )
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

    var body: some View {
        let progress = ReadingQueueFacts.progress(of: works.map(\.readingState))
        let counts = QueueQuickFilter.counts(in: works, preservedIDs: preservedIDs)
        VStack(alignment: .leading, spacing: 8) {
            if !works.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    QueueProgressStrip(progress: progress, palette: palette)
                    Text(ReadingQueueFacts.legend(progress, offlineCount: preservedIDs.count))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, SubjectMetrics.headerGutter)
            }
            FlowLayout(spacing: 6, rowSpacing: 6) {
                ForEach(tags.sorted { $0.name < $1.name }) { tag in
                    SubjectChip(text: tag.name)
                }
                Button(action: onAddTag) {
                    SubjectChip(text: "+ Tag", style: .dashed)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add a tag to this queue")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SubjectMetrics.headerGutter)
            .padding(.bottom, 4)
            SubjectPillRail(
                options: QueueQuickFilter.allCases,
                title: { "\($0.title) \(counts[$0] ?? 0)" },
                selection: $quickFilter,
                palette: palette
            )
            .padding(.horizontal, SubjectMetrics.gutter)
            filterRail()
        }
    }
}

/// 1h: "In line carries a list / grid switch in its section header". Grid is
/// the cover grid; list is the ledger — or Detailed, if the overflow menu set it.
struct QueueInLineHeader: View {
    let count: Int
    @Binding var mode: WorkListDisplayMode

    var body: some View {
        HStack(spacing: 8) {
            SectionRuleHeader(title: "In Line", count: count)
            Picker("Layout", selection: Binding(
                get: { mode == .compact },
                set: { mode = $0 ? .compact : .ledger }
            )) {
                Image(systemName: "list.bullet").accessibilityLabel("List").tag(false)
                Image(systemName: "square.grid.2x2").accessibilityLabel("Grid").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .controlSize(.small)
            .padding(.trailing, SubjectMetrics.gutter)
        }
    }
}

/// Spec 1bg: the queue's own name, a hairline, then "N / total" in the same
/// tabular-monospace figure the queue page's other counts use.
struct QueueSelectionStatusRow: View {
    let queueName: String
    let selectedCount: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(queueName.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(11 * 0.13)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Rectangle()
                .fill(Color.primary.opacity(0.14))
                .frame(height: 0.5)
            Text("\(selectedCount) / \(total)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .combinedAccessibilityRow("\(queueName), \(selectedCount) of \(total) selected")
    }
}

/// The ledger card a standalone `WorkRow(.ledger)` sits on outside a `List` —
/// the same fill, wash and hairline `.cardRow(tintHue:)` paints inside one.
struct WorkLedgerCardBackground: View {
    let work: SavedWork

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let palette = themeManager.appTheme.subjectPalette(
            hue: CoverArt.workHue(fandoms: work.workFandoms, title: work.title)
        )
        let rowShape = RoundedRectangle(cornerRadius: SubjectMetrics.rowRadius, style: .continuous)
        rowShape
            .fill(themeManager.appTheme.cardSurface)
            .overlay(rowShape.fill(palette.rowWash))
            .overlay(rowShape.strokeBorder(palette.rowBorder, lineWidth: 0.5))
    }
}
