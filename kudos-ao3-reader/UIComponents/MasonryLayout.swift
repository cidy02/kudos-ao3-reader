import CoreGraphics
import SwiftUI

/// A two-column (or n-column) masonry layout: places each subview in whichever
/// column is currently shortest, so variable-height cards pack evenly without
/// artificial column balancing hacks.
struct MasonryLayout: Layout {
    var columns: Int = 2
    var spacing: CGFloat = 10
    var rowSpacing: CGFloat = 10

    /// Guards against `columns <= 0`.
    private var safeColumns: Int { max(1, columns) }

    init(columns: Int = 2, spacing: CGFloat = 10, rowSpacing: CGFloat = 10) {
        self.columns = columns
        self.spacing = spacing
        self.rowSpacing = rowSpacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = proposal.width ?? proposal.replacingUnspecifiedDimensions().width
        let colWidth = columnWidth(for: width)
        let itemSizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: colWidth, height: nil)) }
        return arrange(sizes: itemSizes, width: width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        guard !subviews.isEmpty else { return }
        let colWidth = columnWidth(for: bounds.width)
        let itemSizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: colWidth, height: nil)) }
        let arrangement = arrange(sizes: itemSizes, width: bounds.width)
        for (index, subview) in subviews.enumerated() {
            let origin = arrangement.origins[index]
            let size = itemSizes[index]
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: ProposedViewSize(width: colWidth, height: size.height)
            )
        }
    }

    /// Pure placement logic, separated so it can be verified in Swift Testing tests.
    func arrange(sizes: [CGSize], width: CGFloat) -> (origins: [CGPoint], size: CGSize) {
        guard !sizes.isEmpty else { return ([], .zero) }
        let colWidth = columnWidth(for: width)
        var heights = Array(repeating: CGFloat(0), count: safeColumns)
        var origins: [CGPoint] = []
        origins.reserveCapacity(sizes.count)

        for itemSize in sizes {
            let col = shortestColumn(heights)
            let origin = CGPoint(
                x: CGFloat(col) * (colWidth + spacing),
                y: heights[col]
            )
            origins.append(origin)
            heights[col] += itemSize.height + rowSpacing
        }

        let contentHeight = (heights.max() ?? 0) - rowSpacing
        return (origins, CGSize(width: width, height: max(0, contentHeight)))
    }

    func columnWidth(for totalWidth: CGFloat) -> CGFloat {
        max(0, (totalWidth - spacing * CGFloat(safeColumns - 1)) / CGFloat(safeColumns))
    }

    private func shortestColumn(_ heights: [CGFloat]) -> Int {
        heights.indices.min { heights[$0] < heights[$1] } ?? 0
    }
}
