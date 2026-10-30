import SwiftUI

/// Where a chapter bar is drawn. Width and gap stay fixed until the line is
/// full, then the bars shrink (I-15). Rows are the ledger and New Chapters
/// lines; cards are the Resume card.
enum ChapterBarScale: Equatable {
    case row
    case card

    /// 6 pt on a row, 14 pt on a card.
    var nominalWidth: CGFloat {
        switch self {
        case .row: 6
        case .card: 14
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

/// Pure bar layout. Views only draw what this returns.
enum ChapterBarGeometry {
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

    /// One bar per planned chapter. `weights` is one length per posted chapter;
    /// nil, or a count that is not `posted`, means every bar is the same height.
    /// Unposted chapters take the average posted length when lengths are known.
    /// `progress` is the fraction of the downloaded work (0…1); nil has not been
    /// opened. The last `newChapterCount` posted chapters are the new-chapter
    /// variant, drawn apart from read and unread.
    static func items(
        planned: Int,
        posted: Int,
        progress: Double?,
        weights: [Double]?,
        newChapterCount: Int = 0
    ) -> [ChapterBarItem] {
        let planned = max(0, planned)
        let posted = min(max(0, posted), planned)
        guard planned > 0 else { return [] }
        let known = weights.flatMap { values -> [Double]? in
            guard values.count == posted, posted > 0, values.allSatisfy({ $0 > 0 }) else { return nil }
            return values
        }
        let postedWeights = (0 ..< posted).map { known?[$0] ?? 1 }
        let unpostedWeight = known.map { $0.reduce(0, +) / Double($0.count) } ?? 1
        let total = postedWeights.reduce(0, +)
        let fraction = progress.map { min(max($0, 0), 1) }
        var remaining = (fraction ?? 0) * total
        let fresh = min(max(0, newChapterCount), posted)
        let freshStart = posted - fresh

        return (0 ..< planned).map { index in
            let weight: Double
            let role: ChapterBarRole
            if index >= posted {
                weight = unpostedWeight
                role = .notPosted
            } else {
                weight = postedWeights[index]
                if fraction == nil || fraction == 0 {
                    role = .postedUnread
                } else if remaining >= weight - 0.000_001 {
                    role = .read
                    remaining -= weight
                } else if remaining > 0.000_001 {
                    role = .current(fill: remaining / weight)
                    remaining = 0
                } else {
                    role = .postedUnread
                }
            }
            if index >= freshStart && index < posted && fresh > 0 {
                return ChapterBarItem(role: .newChapter, weight: weight)
            }
            return ChapterBarItem(role: role, weight: weight)
        }
    }

    /// "Ch 7 · 58%". The chapter is where the progress falls; the percent is the
    /// whole downloaded work. Nothing at zero: a row must not claim a session
    /// that never happened.
    static func progressLabel(chapters: String, progress: Double?, isFinished: Bool) -> String? {
        let fraction: Double? = isFinished ? 1 : progress
        guard let fraction, fraction > 0 else { return nil }
        let percent = Int((min(fraction, 1) * 100).rounded())
        let posted = SavedWork.postedChapterCount(from: chapters)
        guard posted > 0 else { return "\(percent)%" }
        let chapter = readingChapter(posted: posted, progress: fraction, weights: nil)
        return "Ch \(chapter) · \(percent)%"
    }

    /// 1-based story chapter that contains `progress` across equal posted chapters,
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
        var text = "\(read) of \(posted) posted chapters read"
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
    static func items(
        chapters: String,
        progress: Double?,
        isFinished: Bool = false,
        weights: [Int]?,
        newChapterCount: Int = 0
    ) -> [ChapterBarItem] {
        let posted = SavedWork.postedChapterCount(from: chapters)
        let planned = max(SavedWork.totalChapterCount(from: chapters) ?? posted, posted)
        let fraction: Double? = isFinished ? 1 : progress
        let lengths = weights?.map(Double.init)
        return ChapterBarGeometry.items(
            planned: planned,
            posted: posted,
            progress: fraction,
            weights: lengths,
            newChapterCount: newChapterCount
        )
    }
}

/// One bar per planned chapter. Read is the app colour on a row and white on a
/// gradient. The current chapter is partly filled. Posted-unread is faint.
/// Not-yet-posted is dashed. New chapters are app red either way.
struct ChapterBars: View {
    var items: [ChapterBarItem]
    var scale: ChapterBarScale = .row
    /// Resume card and other gradient surfaces. Read bars turn white.
    var onGradient = false
    var accessibilityLabel: String?

    @Environment(\.accentFill) private var accentFill
    @ScaledMetric(relativeTo: .caption) private var trackHeight: CGFloat = 16

    private var height: CGFloat {
        scale == .row ? trackHeight : scale.trackHeight
    }

    var body: some View {
        let label = accessibilityLabel ?? ChapterBarGeometry.accessibilityLabel(for: items)
        Group {
            if items.isEmpty {
                Color.clear.frame(height: 0)
            } else {
                GeometryReader { geo in
                    let metrics = ChapterBarGeometry.metrics(
                        count: items.count,
                        availableWidth: geo.size.width,
                        nominalWidth: scale.nominalWidth,
                        gap: scale.gap
                    )
                    let tallest = items.map(\.weight).max() ?? 1
                    HStack(alignment: .bottom, spacing: metrics.gap) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            bar(item, metrics: metrics, tallest: tallest)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
                .frame(height: height)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var readColor: Color {
        onGradient ? .white : accentFill
    }

    private var faint: Color {
        Color.primary.opacity(onGradient ? 0.28 : 0.14)
    }

    private func bar(_ item: ChapterBarItem, metrics: ChapterBarGeometry.Metrics, tallest: Double) -> some View {
        let fraction = tallest > 0 ? item.weight / tallest : 1
        let barHeight = max(2, height * fraction)
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
                    .fill(accentFill)
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
