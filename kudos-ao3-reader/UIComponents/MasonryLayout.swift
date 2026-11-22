import CoreGraphics
import SwiftUI

/// A two-column (or n-column) masonry layout: places each subview in whichever
/// column is currently shortest, so variable-height cards pack evenly without
/// artificial column balancing hacks.
struct MasonryLayout: Layout {
    /// An explicit column's x-origin and width inside the layout's bounds. Used
    /// when a grid aligns its gutter with a display fold instead of splitting evenly.
    nonisolated struct ColumnSpan: Equatable, Sendable {
        let minX: CGFloat
        let width: CGFloat
    }

    var columns: Int = 2
    var spacing: CGFloat = 10
    var rowSpacing: CGFloat = 10
    /// Explicit column spans (nil uses `columns` equal-width tracks).
    var columnSpans: [ColumnSpan]?

    /// Guards against `columns <= 0`.
    private var safeColumns: Int { max(1, columns) }

    init(
        columns: Int = 2,
        spacing: CGFloat = 10,
        rowSpacing: CGFloat = 10,
        columnSpans: [ColumnSpan]? = nil
    ) {
        self.columns = columns
        self.spacing = spacing
        self.rowSpacing = rowSpacing
        self.columnSpans = columnSpans
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = proposal.width ?? proposal.replacingUnspecifiedDimensions().width
        return arrange(count: subviews.count, width: width) { index, columnWidth in
            subviews[index].sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
        }.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        guard !subviews.isEmpty else { return }
        let arrangement = arrange(count: subviews.count, width: bounds.width) { index, columnWidth in
            subviews[index].sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
        }
        for (index, subview) in subviews.enumerated() {
            let frame = arrangement.frames[index]
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    /// Pure placement logic, separated so it can be verified in Swift Testing tests.
    func arrange(sizes: [CGSize], width: CGFloat) -> (origins: [CGPoint], size: CGSize) {
        let result = arrange(count: sizes.count, width: width) { index, _ in sizes[index] }
        return (result.frames.map(\.origin), result.size)
    }

    /// Pure placement supporting unequal column widths (e.g. a fold-aligned gutter).
    func arrange(
        count: Int,
        width: CGFloat,
        measure: (_ index: Int, _ columnWidth: CGFloat) -> CGSize
    ) -> (frames: [CGRect], size: CGSize) {
        guard count > 0 else { return ([], .zero) }
        let spans = resolvedSpans(for: width)
        var heights = Array(repeating: CGFloat(0), count: spans.count)
        var frames: [CGRect] = []
        frames.reserveCapacity(count)

        for index in 0..<count {
            let col = shortestColumn(heights)
            let span = spans[col]
            let itemSize = measure(index, span.width)
            frames.append(CGRect(x: span.minX, y: heights[col], width: span.width, height: itemSize.height))
            heights[col] += itemSize.height + rowSpacing
        }

        let contentHeight = (heights.max() ?? 0) - rowSpacing
        return (frames, CGSize(width: width, height: max(0, contentHeight)))
    }

    func columnWidth(for totalWidth: CGFloat) -> CGFloat {
        max(0, (totalWidth - spacing * CGFloat(safeColumns - 1)) / CGFloat(safeColumns))
    }

    private func resolvedSpans(for totalWidth: CGFloat) -> [ColumnSpan] {
        if let columnSpans, !columnSpans.isEmpty { return columnSpans }
        let width = columnWidth(for: totalWidth)
        return (0..<safeColumns).map { col in
            ColumnSpan(minX: CGFloat(col) * (width + spacing), width: width)
        }
    }

    private func shortestColumn(_ heights: [CGFloat]) -> Int {
        heights.indices.min { heights[$0] < heights[$1] } ?? 0
    }
}
