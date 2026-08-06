import SwiftUI

/// A simple wrapping layout: places subviews left-to-right and wraps to a new row
/// when the next one won't fit. Used for variable-width pill collections such as
/// the work's tag chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8
    /// Stretches each row to the full available width by splitting its leftover
    /// space evenly across that row's gaps, so the first subview sits on the
    /// leading edge and the last on the trailing edge. Off by default: the tag
    /// chips and secondary stat rows want their natural left-to-right packing.
    ///
    /// A wrapped final row stays ragged (standard typographic justification) —
    /// spreading two leftovers across a whole line reads as a mistake. A single
    /// row is always justified, since it is both the first row and the last.
    var justifiesRows = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = rows(maxWidth: maxWidth, subviews: subviews)
        let naturalWidth = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + rowSpacing * CGFloat(max(0, rows.count - 1))
        // Justification only means something if the layout actually claims the
        // width it was offered — otherwise it reports its natural size, gets
        // placed at that size, and has no leftover space to distribute.
        let width = justifiesRows && maxWidth.isFinite ? maxWidth : min(naturalWidth, maxWidth)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout Void) {
        var y = bounds.minY
        let rows = rows(maxWidth: bounds.width, subviews: subviews)
        for (rowIndex, row) in rows.enumerated() {
            let isLastRow = rowIndex == rows.count - 1
            let justifies = justifiesRows && row.indices.count > 1 && (!isLastRow || rows.count == 1)
            let gapSpacing = justifies
                ? spacing + max(0, bounds.width - row.width) / CGFloat(row.indices.count - 1)
                : spacing
            var x = bounds.minX
            for index in row.indices {
                let size = clampedSize(subviews[index], maxWidth: bounds.width)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + gapSpacing
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
