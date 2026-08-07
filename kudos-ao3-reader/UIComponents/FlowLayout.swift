import SwiftUI

/// A simple wrapping layout: places subviews left-to-right and wraps to a new row
/// when the next one won't fit. Used for variable-width pill collections such as
/// the work's tag chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8
    /// Where a row sits in the width it was offered. `.leading` by default: the
    /// tag chips and secondary stat rows want their natural left-to-right packing.
    enum RowAlignment {
        /// Natural packing against the leading edge.
        case leading
        /// The row keeps its natural gaps and the leftover splits either side of
        /// it. Every row centres, wrapped ones included — unlike justification,
        /// a centred short row reads as deliberate.
        case center
        /// Stretched to the full width by splitting the leftover evenly across
        /// that row's gaps, so the first subview sits on the leading edge and the
        /// last on the trailing edge.
        ///
        /// A wrapped final row stays ragged (standard typographic justification) —
        /// spreading two leftovers across a whole line reads as a mistake. A
        /// single row is always justified, since it is both first and last.
        case justified
    }

    var rowAlignment: RowAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = rows(maxWidth: maxWidth, subviews: subviews)
        let naturalWidth = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + rowSpacing * CGFloat(max(0, rows.count - 1))
        // Justifying and centring only mean something if the layout actually
        // claims the width it was offered — otherwise it reports its natural
        // size, gets placed at that size, and has no leftover to distribute.
        let claimsFullWidth = rowAlignment != .leading && maxWidth.isFinite
        let width = claimsFullWidth ? maxWidth : min(naturalWidth, maxWidth)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout Void) {
        var y = bounds.minY
        let rows = rows(maxWidth: bounds.width, subviews: subviews)
        for (rowIndex, row) in rows.enumerated() {
            let isLastRow = rowIndex == rows.count - 1
            let leftover = max(0, bounds.width - row.width)
            let justifies = rowAlignment == .justified
                && row.indices.count > 1
                && (!isLastRow || rows.count == 1)
            let gapSpacing = justifies
                ? spacing + leftover / CGFloat(row.indices.count - 1)
                : spacing
            var x = rowAlignment == .center ? bounds.minX + leftover / 2 : bounds.minX
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
