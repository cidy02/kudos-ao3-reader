import SwiftUI

/// Where a chapter bar is drawn. Width and gap stay fixed until the line is
/// full, then the bars shrink (I-15). Rows are the ledger and New Chapters
/// lines; cards are the Resume card.
enum ChapterBarScale: Equatable {
    case row
    case card

    /// 6 pt on a row; 27 pt cap on a card so a few chapters do not stretch across the card.
    var nominalWidth: CGFloat {
        switch self {
        case .row: 6
        case .card: 27
        }
    }

    /// Minimum bar width before chapters group (`ceil(n / fit)`): 3 pt in a row, 4 pt on a card.
    var minBarWidth: CGFloat {
        switch self {
        case .row: 3
        case .card: 4
        }
    }

    /// Default bar count that fits when no container width has been measured yet.
    var defaultFit: Int {
        switch self {
        case .row: 36
        case .card: 46
        }
    }

    /// Default container width used before `GeometryReader` measures (`326` on a card, `200` on a row).
    var defaultAvailableWidth: CGFloat {
        switch self {
        case .row: 200
        case .card: 326
        }
    }

    /// The Work row draws a 2 pt gap. Cards take 4, the wide end of I-15's
    /// 2/3/4, so a 14 pt bar is not packed tighter than a 6 pt one.
    var gap: CGFloat {
        switch self {
        case .row: 2
        case .card: 4
        }
    }

    var trackHeight: CGFloat {
        switch self {
        case .row: 16
        case .card: 76
        }
    }
}

/// How far a reader is through one planned chapter.
enum ChapterBarRole: Equatable {
    /// Read through. App colour on a row; white when the bar sits on a gradient.
    case read
    /// The chapter being read, filled from the bottom by `fill` (0…1).
    case current(fill: Double)
    /// Posted, not read yet.
    case postedUnread
    /// Planned, not posted. Drawn dashed.
    case notPosted
    /// A chapter posted since the reader last looked. Always app red.
    case newChapter
}

struct ChapterBarItem: Equatable {
    var role: ChapterBarRole
    /// Relative height. The tallest bar fills the track; the rest scale to it.
    var weight: Double
}

struct ChapterBarLayout: Equatable {
    struct Source: Equatable {
        var planned: Int?
        var posted: Int
        var read: Int?
        var chapterProgress: Double
        var progress: Double?
        var isFinished: Bool
        var weights: [Double]?
        var heights: [Double]?
        var newChapterCount: Int
        var scale: ChapterBarScale
        var fit: Int?
    }

    var bars: [ChapterBarItem]
    /// Non-nil (0…1) for a finished one-chapter work (1/1), which draws a plain progress track instead of bars.
    var trackFill: Double?
    /// True when the author has not set a chapter total (AO3 "12/?"): draw three fading dots after the posted bars, never a dashed bar.
    var showsOpenTotalDots: Bool
    /// How many chapters each bar represents (`1` while chapters fit, `ceil(count / fit)` when grouped).
    var chaptersPerBar: Int
    /// `"Each bar is k chapters"` when `chaptersPerBar > 1`, nil otherwise.
    var groupNote: String?
    var metrics: ChapterBarGeometry.Metrics
    var accessibilityLabel: String
    fileprivate var source: Source?

    var isEmpty: Bool {
        bars.isEmpty && trackFill == nil
    }

    init(
        bars: [ChapterBarItem] = [],
        trackFill: Double? = nil,
        showsOpenTotalDots: Bool = false,
        chaptersPerBar: Int = 1,
        groupNote: String? = nil,
        metrics: ChapterBarGeometry.Metrics = .init(width: 0, gap: 0, radius: 0),
        accessibilityLabel: String = "",
        source: Source? = nil
    ) {
        self.bars = bars
        self.trackFill = trackFill
        self.showsOpenTotalDots = showsOpenTotalDots
        self.chaptersPerBar = chaptersPerBar
        self.groupNote = groupNote
        self.metrics = metrics
        self.accessibilityLabel = accessibilityLabel
        self.source = source
    }

    init(items: [ChapterBarItem], scale: ChapterBarScale = .row) {
        self.bars = items
        self.trackFill = nil
        self.showsOpenTotalDots = false
        self.chaptersPerBar = 1
        self.groupNote = nil
        self.metrics = ChapterBarGeometry.metrics(
            count: items.count,
            availableWidth: scale.defaultAvailableWidth,
            nominalWidth: scale.nominalWidth,
            gap: scale.gap
        )
        self.accessibilityLabel = ChapterBarGeometry.accessibilityLabel(for: items)
        self.source = nil
    }

    func resolved(availableWidth: CGFloat, scale: ChapterBarScale) -> ChapterBarLayout {
        if let source {
            return ChapterBarGeometry.layout(
                planned: source.planned,
                posted: source.posted,
                read: source.read,
                chapterProgress: source.chapterProgress,
                progress: source.progress,
                isFinished: source.isFinished,
                weights: source.weights,
                heights: source.heights,
                newChapterCount: source.newChapterCount,
                scale: scale,
                availableWidth: availableWidth,
                fit: source.fit
            )
        }
        guard !bars.isEmpty else { return self }
        var copy = self
        let widthForMetrics = availableWidth > 0 ? availableWidth : scale.defaultAvailableWidth
        copy.metrics = ChapterBarGeometry.metrics(
            count: bars.count,
            availableWidth: widthForMetrics,
            nominalWidth: scale.nominalWidth,
            gap: scale.gap
        )
        return copy
    }

    static func == (lhs: ChapterBarLayout, rhs: ChapterBarLayout) -> Bool {
        lhs.bars == rhs.bars
            && lhs.trackFill == rhs.trackFill
            && lhs.showsOpenTotalDots == rhs.showsOpenTotalDots
            && lhs.chaptersPerBar == rhs.chaptersPerBar
            && lhs.groupNote == rhs.groupNote
            && lhs.metrics == rhs.metrics
            && lhs.accessibilityLabel == rhs.accessibilityLabel
    }
}

/// Pure bar layout. Views only draw what this returns.
enum ChapterBarGeometry {
    static let openDotsWidth: CGFloat = 24

    struct Metrics: Equatable {
        var width: CGFloat
        var gap: CGFloat
        var radius: CGFloat
    }

    /// Fixed width and gap while they fit. Past that, the width shrinks and the
    /// gap stays; the gap shrinks only when the width would otherwise go to
    /// nothing. Radius is `min(3, width / 2)`. An unknown width (0, before
    /// layout) keeps the nominal size.
    static func metrics(
        count: Int,
        availableWidth: CGFloat,
        nominalWidth: CGFloat,
        gap: CGFloat
    ) -> Metrics {
        guard count > 0, nominalWidth > 0 else {
            return Metrics(width: 0, gap: 0, radius: 0)
        }
        let width: CGFloat
        let usedGap: CGFloat
        if availableWidth <= 0 {
            width = nominalWidth
            usedGap = gap
        } else if count == 1 {
            width = min(nominalWidth, availableWidth)
            usedGap = gap
        } else {
            let natural = CGFloat(count) * nominalWidth + CGFloat(count - 1) * gap
            if natural <= availableWidth {
                width = nominalWidth
                usedGap = gap
            } else {
                let gapBudget = CGFloat(count - 1) * gap
                if availableWidth > gapBudget {
                    width = (availableWidth - gapBudget) / CGFloat(count)
                    usedGap = gap
                } else {
                    let scale = availableWidth / natural
                    width = nominalWidth * scale
                    usedGap = gap * scale
                }
            }
        }
        return Metrics(width: width, gap: usedGap, radius: min(3, width / 2))
    }

    /// The one rule for chapter bars (Resume card, Work Detail, Home rows, library and search rows):
    /// 1. A finished one-chapter work (1/1): no bars, a plain progress track.
    /// 2. Total unknown (AO3 "12/?"): one bar per posted chapter, then three fading dots; never a dashed bar.
    /// 3. More chapters than fit (4 pt minimum on a card, 3 pt in a row): equal groups of `ceil(n / fit)`
    ///    chapters per bar + a note. A group counts as posted when any chapter in it is.
    /// 4. Otherwise one bar per chapter; dashed = planned but not posted, capped at 27 pt wide on a card.
    /// Lengths unknown (not downloaded) keep every bar one height. Read is capped at posted.
    static func layout(
        planned: Int?,
        posted: Int,
        read: Int? = nil,
        chapterProgress: Double = 0,
        progress: Double? = nil,
        isFinished: Bool = false,
        weights: [Double]? = nil,
        heights: [Double]? = nil,
        newChapterCount: Int = 0,
        scale: ChapterBarScale = .card,
        availableWidth: CGFloat = 0,
        fit: Int? = nil
    ) -> ChapterBarLayout {
        let posted = max(0, posted)
        let total: Int? = if let planned, planned >= posted, planned > 0 {
            planned
        } else {
            nil
        }
        let count = total ?? posted
        let source = ChapterBarLayout.Source(
            planned: planned,
            posted: posted,
            read: read,
            chapterProgress: chapterProgress,
            progress: progress,
            isFinished: isFinished,
            weights: weights,
            heights: heights,
            newChapterCount: newChapterCount,
            scale: scale,
            fit: fit
        )
        guard count > 0 else {
            return ChapterBarLayout(source: source)
        }

        func usable(_ values: [Double]?) -> [Double]? {
            values.flatMap { $0.count == posted && posted > 0 && $0.allSatisfy { $0 > 0 } ? $0 : nil }
        }
        let known = usable(weights)
        let postedWeights = (0 ..< posted).map { known?[$0] ?? 1 }
        let drawn = usable(heights) ?? known
        let postedHeights = (0 ..< posted).map { drawn?[$0] ?? 1 }
        let unpostedHeight = drawn.map { $0.reduce(0, +) / Double($0.count) } ?? 1
        let fresh = min(max(0, newChapterCount), posted)
        let freshStart = posted - fresh

        let chapterRoles: [ChapterBarRole]
        let chapterFills: [Double]
        let readCount: Int
        if let read {
            let clampedRead = isFinished ? posted : min(max(0, read), posted)
            let inChapter = clampedRead >= posted ? 0 : min(max(chapterProgress, 0), 1)
            var roles: [ChapterBarRole] = []
            var fills: [Double] = []
            roles.reserveCapacity(posted)
            fills.reserveCapacity(posted)
            for index in 0 ..< posted {
                if index < clampedRead {
                    roles.append(.read)
                    fills.append(1)
                } else if index == clampedRead, inChapter >= 1 - 0.000_001 {
                    roles.append(.read)
                    fills.append(1)
                } else if index == clampedRead, inChapter > 0.000_001 {
                    roles.append(.current(fill: inChapter))
                    fills.append(inChapter)
                } else {
                    roles.append(.postedUnread)
                    fills.append(0)
                }
            }
            chapterRoles = roles
            chapterFills = fills
            readCount = roles.filter { if case .read = $0 { return true }; return false }.count
        } else {
            let totalWeight = postedWeights.reduce(0, +)
            let fraction: Double? = isFinished ? 1 : progress.map { min(max($0, 0), 1) }
            var remaining = (fraction ?? 0) * totalWeight
            var roles: [ChapterBarRole] = []
            var fills: [Double] = []
            roles.reserveCapacity(posted)
            fills.reserveCapacity(posted)
            for index in 0 ..< posted {
                let span = postedWeights[index]
                if fraction == nil || fraction == 0 {
                    roles.append(.postedUnread)
                    fills.append(0)
                } else if remaining >= span - 0.000_001 {
                    roles.append(.read)
                    fills.append(1)
                    remaining -= span
                } else if remaining > 0.000_001 {
                    let fill = remaining / span
                    roles.append(.current(fill: fill))
                    fills.append(fill)
                    remaining = 0
                } else {
                    roles.append(.postedUnread)
                    fills.append(0)
                }
            }
            chapterRoles = roles
            chapterFills = fills
            readCount = roles.filter { if case .read = $0 { return true }; return false }.count
        }

        if total == 1, posted == 1 {
            let fill: Double
            if isFinished || readCount >= 1 {
                fill = 1
            } else if let progress {
                fill = min(max(progress, 0), 1)
            } else if chapterProgress > 0 {
                fill = min(max(chapterProgress, 0), 1)
            } else if fresh > 0 {
                fill = 1
            } else {
                fill = 0
            }
            let percent = Int((fill * 100).rounded())
            let label: String
            if scale == .row, read == nil, progress == nil, chapterProgress == 0 {
                label = fresh > 0 ? "New work, one chapter" : "One chapter"
            } else {
                label = "One chapter, \(percent) percent read"
            }
            let widthForTrack = availableWidth > 0 ? availableWidth : (scale == .row ? 96 : scale.defaultAvailableWidth)
            let trackWidth = scale == .row ? min(96, widthForTrack) : widthForTrack
            return ChapterBarLayout(
                bars: [],
                trackFill: fill,
                showsOpenTotalDots: false,
                chaptersPerBar: 1,
                groupNote: nil,
                metrics: Metrics(width: trackWidth, gap: 0, radius: 3),
                accessibilityLabel: label,
                source: source
            )
        }

        let showsOpenTotalDots = (total == nil)
        let resolvedFit: Int
        if let fit {
            resolvedFit = max(4, fit)
        } else if availableWidth > 0 {
            let widthForBars = showsOpenTotalDots ? max(0, availableWidth - openDotsWidth) : availableWidth
            resolvedFit = max(4, Int(floor((widthForBars + scale.gap) / (scale.minBarWidth + scale.gap))))
        } else {
            resolvedFit = scale.defaultFit
        }
        let chaptersPerBar = max(1, Int(ceil(Double(count) / Double(resolvedFit))))
        let bars: [ChapterBarItem]
        if chaptersPerBar == 1 {
            bars = (0 ..< count).map { index in
                if index >= posted {
                    return ChapterBarItem(role: .notPosted, weight: unpostedHeight)
                }
                let weight = postedHeights[index]
                if index >= freshStart, fresh > 0 {
                    return ChapterBarItem(role: .newChapter, weight: weight)
                }
                return ChapterBarItem(role: chapterRoles[index], weight: weight)
            }
        } else {
            var grouped: [ChapterBarItem] = []
            var groupIndex = 0
            while groupIndex * chaptersPerBar < count {
                let from = groupIndex * chaptersPerBar
                let to = min(count, from + chaptersPerBar)
                let liveEnd = min(to, posted)
                let live = max(0, liveEnd - from)
                if live == 0 {
                    grouped.append(ChapterBarItem(role: .notPosted, weight: unpostedHeight))
                } else {
                    let weight = (from ..< liveEnd).reduce(0.0) { $0 + postedHeights[$1] } / Double(live)
                    let freshInGroup = fresh > 0 ? (from ..< liveEnd).filter { $0 >= freshStart }.count : 0
                    let role: ChapterBarRole
                    if freshInGroup == live {
                        role = .newChapter
                    } else {
                        let onSum = (from ..< liveEnd).reduce(0.0) { sum, i in
                            let on = (i >= freshStart && fresh > 0) ? 1.0 : chapterFills[i]
                            return sum + on
                        }
                        let fill = onSum / Double(live)
                        if fill >= 1 - 0.000_001 {
                            role = .read
                        } else if fill > 0.000_001 {
                            role = .current(fill: fill)
                        } else {
                            role = .postedUnread
                        }
                    }
                    grouped.append(ChapterBarItem(role: role, weight: weight))
                }
                groupIndex += 1
            }
            bars = grouped
        }

        let widthForMetrics = availableWidth > 0 ? availableWidth : scale.defaultAvailableWidth
        let barsAvailableWidth = showsOpenTotalDots ? max(0, widthForMetrics - openDotsWidth) : widthForMetrics
        let metrics = Self.metrics(
            count: bars.count,
            availableWidth: barsAvailableWidth,
            nominalWidth: scale.nominalWidth,
            gap: scale.gap
        )
        let groupNote = chaptersPerBar > 1 ? "Each bar is \(chaptersPerBar) chapters" : nil
        let label = spokenSummary(
            read: readCount,
            posted: posted,
            total: total,
            fresh: fresh,
            chaptersPerBar: chaptersPerBar,
            scale: scale
        )
        return ChapterBarLayout(
            bars: bars,
            trackFill: nil,
            showsOpenTotalDots: showsOpenTotalDots,
            chaptersPerBar: chaptersPerBar,
            groupNote: groupNote,
            metrics: metrics,
            accessibilityLabel: label,
            source: source
        )
    }

    private static func spokenSummary(
        read: Int,
        posted: Int,
        total: Int?,
        fresh: Int,
        chaptersPerBar: Int,
        scale: ChapterBarScale
    ) -> String {
        var text: String
        if scale == .row, read == 0, fresh > 0 {
            text = "\(fresh) \(fresh == 1 ? "new chapter" : "new chapters"), \(posted) posted"
        } else {
            text = "Chapters: \(read) read, \(posted) posted"
            if fresh > 0 {
                text += ", \(fresh) new"
            }
        }
        if let total {
            if total > posted {
                text += ", \(total - posted) not posted yet"
            }
        } else {
            text += ", total not set by the author"
        }
        if chaptersPerBar > 1 {
            text += ". Each bar is \(chaptersPerBar) chapters"
        }
        return text
    }

    /// Convenience forwarding to `layout(...)`.
    static func items(
        planned: Int?,
        posted: Int,
        progress: Double?,
        weights: [Double]?,
        heights: [Double]? = nil,
        newChapterCount: Int = 0
    ) -> [ChapterBarItem] {
        layout(
            planned: planned,
            posted: posted,
            progress: progress,
            weights: weights,
            heights: heights,
            newChapterCount: newChapterCount
        ).bars
    }

    /// "Ch 7 · 58%". The chapter is where the progress falls; the percent is the
    /// whole downloaded work. Nothing at zero: a row must not claim a session
    /// that never happened.
    static func progressLabel(
        chapters: String, progress: Double?, isFinished: Bool, weights: [Int]? = nil
    ) -> String? {
        let fraction: Double? = isFinished ? 1 : progress
        guard let fraction, fraction > 0 else { return nil }
        let percent = Int((min(fraction, 1) * 100).rounded())
        let posted = SavedWork.postedChapterCount(from: chapters)
        guard posted > 0 else { return "\(percent)%" }
        let chapter = readingChapter(posted: posted, progress: fraction, weights: weights?.map(Double.init))
        return "Ch \(chapter) · \(percent)%"
    }

    /// 1-based story chapter that contains `progress` across the posted chapters (equal
    /// without `weights`, which are Readium positions per chapter),
    /// or the last posted chapter when the work is finished.
    static func readingChapter(posted: Int, progress: Double, weights: [Double]?) -> Int {
        guard posted > 0 else { return 1 }
        let fraction = min(max(progress, 0), 1)
        if fraction >= 1 { return posted }
        let known = weights.flatMap { $0.count == posted && $0.allSatisfy { $0 > 0 } ? $0 : nil }
        let postedWeights = (0 ..< posted).map { known?[$0] ?? 1 }
        let total = postedWeights.reduce(0, +)
        var remaining = fraction * total
        for index in 0 ..< posted {
            let weight = postedWeights[index]
            if remaining < weight - 0.000_001 || index == posted - 1 {
                return index + 1
            }
            remaining -= weight
        }
        return posted
    }

    static func accessibilityLabel(for items: [ChapterBarItem]) -> String {
        let read = items.filter { if case .read = $0.role { return true }; return false }.count
        let posted = items.filter {
            switch $0.role {
            case .notPosted: return false
            default: return true
            }
        }.count
        let unposted = items.count - posted
        var text = "Chapters: \(read) read, \(posted) posted"
        if unposted > 0 {
            text += ", \(unposted) not posted yet"
        }
        let fresh = items.filter { if case .newChapter = $0.role { return true }; return false }.count
        if fresh > 0 {
            text += ", \(fresh) new"
        }
        return text
    }
}

/// Bars built from the chapter stat a work already stores, plus optional
/// per-chapter lengths. No lengths, or a count that disagrees with the posted
/// chapters, keeps every bar the same height.
enum ChapterBarModel {
    static func layout(
        chapters: String,
        read: Int? = nil,
        chapterProgress: Double = 0,
        progress: Double?,
        isFinished: Bool = false,
        weights: [Int]?,
        heights: [Int]? = nil,
        newChapterCount: Int = 0,
        scale: ChapterBarScale = .card,
        availableWidth: CGFloat = 0,
        fit: Int? = nil
    ) -> ChapterBarLayout {
        let posted = SavedWork.postedChapterCount(from: chapters)
        let planned = SavedWork.totalChapterCount(from: chapters)
        return ChapterBarGeometry.layout(
            planned: planned,
            posted: posted,
            read: read,
            chapterProgress: chapterProgress,
            progress: progress,
            isFinished: isFinished,
            weights: weights?.map(Double.init),
            heights: heights?.map(Double.init),
            newChapterCount: newChapterCount,
            scale: scale,
            availableWidth: availableWidth,
            fit: fit
        )
    }

    static func items(
        chapters: String,
        progress: Double?,
        isFinished: Bool = false,
        weights: [Int]?,
        heights: [Int]? = nil,
        newChapterCount: Int = 0
    ) -> [ChapterBarItem] {
        layout(
            chapters: chapters,
            progress: progress,
            isFinished: isFinished,
            weights: weights,
            heights: heights,
            newChapterCount: newChapterCount
        ).bars
    }
}

/// Draws what `ChapterBarGeometry.layout` returns: bars (with optional fading
/// dots for an unknown total and a grouping note when grouped) or a plain
/// progress track for a 1/1 work.
struct ChapterBars: View {
    var layout: ChapterBarLayout
    var scale: ChapterBarScale = .row
    /// Resume card and other gradient surfaces. Read bars turn white.
    var onGradient = false
    /// Resume uses 52pt on Home/Up next and 34pt on Work Detail.
    var height: CGFloat?
    var accessibilityLabel: String?

    @Environment(\.accentInk) private var accentInk
    @ScaledMetric(relativeTo: .caption) private var trackHeight: CGFloat = 16
    @State private var measuredWidth: CGFloat = 0

    init(
        layout: ChapterBarLayout,
        scale: ChapterBarScale = .row,
        onGradient: Bool = false,
        height: CGFloat? = nil,
        accessibilityLabel: String? = nil
    ) {
        self.layout = layout
        self.scale = scale
        self.onGradient = onGradient
        self.height = height
        self.accessibilityLabel = accessibilityLabel
    }

    init(
        items: [ChapterBarItem],
        scale: ChapterBarScale = .row,
        onGradient: Bool = false,
        height: CGFloat? = nil,
        accessibilityLabel: String? = nil
    ) {
        self.layout = ChapterBarLayout(items: items, scale: scale)
        self.scale = scale
        self.onGradient = onGradient
        self.height = height
        self.accessibilityLabel = accessibilityLabel
    }

    private var resolvedHeight: CGFloat {
        height ?? (scale == .row ? trackHeight : scale.trackHeight)
    }

    var body: some View {
        let current = layout.resolved(availableWidth: measuredWidth, scale: scale)
        let label = accessibilityLabel ?? current.accessibilityLabel
        Group {
            if current.isEmpty {
                Color.clear.frame(height: 0)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        let resolved = layout.resolved(availableWidth: geo.size.width, scale: scale)
                        if let trackFill = resolved.trackFill {
                            trackView(fill: trackFill, availableWidth: geo.size.width)
                        } else {
                            let metrics = resolved.metrics
                            let tallest = resolved.bars.map(\.weight).max() ?? 1
                            HStack(alignment: .bottom, spacing: metrics.gap) {
                                ForEach(Array(resolved.bars.enumerated()), id: \.offset) { _, item in
                                    bar(item, metrics: metrics, tallest: tallest)
                                }
                                if resolved.showsOpenTotalDots {
                                    openTotalDots
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        }
                    }
                    .frame(height: resolvedHeight)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { measuredWidth = $0 }

                    if scale == .card, let note = current.groupNote {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(onGradient ? Color.white.opacity(0.85) : .secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var readColor: Color {
        onGradient ? .white : accentInk
    }

    private var faint: Color {
        Color.primary.opacity(onGradient ? 0.28 : 0.14)
    }

    private func trackView(fill: Double, availableWidth: CGFloat) -> some View {
        let clamped = min(max(fill, 0), 1)
        let maxW = scale == .row ? min(96, availableWidth > 0 ? availableWidth : 96) : max(0, availableWidth)
        return ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(faint)
            Capsule(style: .continuous)
                .fill(readColor)
                .frame(width: maxW * clamped)
        }
        .frame(width: maxW, height: 6, alignment: .leading)
        .clipShape(Capsule(style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var openTotalDots: some View {
        let dotColor: Color = onGradient ? .white : .secondary
        return HStack(spacing: 3) {
            Circle().fill(dotColor).frame(width: 4, height: 4)
            Circle().fill(dotColor.opacity(0.7)).frame(width: 4, height: 4)
            Circle().fill(dotColor.opacity(0.4)).frame(width: 4, height: 4)
        }
        .padding(.leading, 3)
        .padding(.bottom, 3)
        .accessibilityHidden(true)
    }

    private func bar(_ item: ChapterBarItem, metrics: ChapterBarGeometry.Metrics, tallest: Double) -> some View {
        let fraction = tallest > 0 ? item.weight / tallest : 1
        let barHeight = max(2, resolvedHeight * fraction)
        return Group {
            switch item.role {
            case .notPosted:
                RoundedRectangle(cornerRadius: metrics.radius, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 1.5]))
                    .foregroundStyle(Color.primary.opacity(onGradient ? 0.55 : 0.35))
            case .current(let fill):
                filled(barHeight, color: readColor, portion: fill, metrics: metrics, under: faint)
            case .read:
                RoundedRectangle(cornerRadius: metrics.radius, style: .continuous)
                    .fill(readColor)
            case .postedUnread:
                RoundedRectangle(cornerRadius: metrics.radius, style: .continuous)
                    .fill(faint)
            case .newChapter:
                RoundedRectangle(cornerRadius: metrics.radius, style: .continuous)
                    .fill(accentInk)
            }
        }
        .frame(width: metrics.width, height: barHeight)
    }

    private func filled(
        _ barHeight: CGFloat,
        color: Color,
        portion: Double,
        metrics: ChapterBarGeometry.Metrics,
        under: Color
    ) -> some View {
        let clamped = min(max(portion, 0), 1)
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: metrics.radius, style: .continuous)
                .fill(under)
            Rectangle()
                .fill(color)
                .frame(height: max(clamped > 0 ? 2 : 0, barHeight * clamped))
        }
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius, style: .continuous))
    }
}
