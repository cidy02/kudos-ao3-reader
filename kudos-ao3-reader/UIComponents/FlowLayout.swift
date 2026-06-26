import SwiftUI

/// A simple wrapping layout: places subviews left-to-right and wraps to a new row
/// when the next one won't fit. Used for variable-width pill collections such as
/// the work's tag chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = rows(maxWidth: maxWidth, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + rowSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var y = bounds.minY
        for row in rows(maxWidth: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = clampedSize(subviews[index], maxWidth: bounds.width)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    /// A subview's size, capped to the available width. A single item wider than the
    /// row (e.g. a long fandom name like "My Hero Academia | …") is re-measured
    /// against `maxWidth` so its text wraps within the container instead of spilling
    /// past the card's edge.
    private func clampedSize(_ subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let intrinsic = subview.sizeThatFits(.unspecified)
        guard maxWidth.isFinite, intrinsic.width > maxWidth else { return intrinsic }
        return subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = clampedSize(subviews[index], maxWidth: maxWidth)
            let projected = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if projected > maxWidth, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
