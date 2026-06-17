import SwiftUI

/// AO3-style page navigation grouped into a single connected pill: first/prev, a
/// small windowed set of page numbers with ellipses (1 … 5 6 7 … 142), then
/// next/last. Sits at the top and bottom edges of the results list rather than
/// floating, mirroring AO3's own layout.
struct SearchPaginationBar: View {
    let currentPage: Int
    let totalPages: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 1) {
            navSeg("chevron.left.2", page: 1, enabled: currentPage > 1)
            navSeg("chevron.left", page: currentPage - 1, enabled: currentPage > 1)

            ForEach(items) { item in
                switch item.kind {
                case .page(let n): pageSeg(n)
                case .ellipsis:
                    Text("…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 30)
                }
            }

            navSeg("chevron.right", page: currentPage + 1, enabled: currentPage < totalPages)
            navSeg("chevron.right.2", page: totalPages, enabled: currentPage < totalPages)
        }
        .padding(3)
        .glassEffect(.regular, in: .capsule)   // one connected pill, not separate bubbles
        .frame(maxWidth: .infinity)
    }

    private func navSeg(_ symbol: String, page: Int, enabled: Bool) -> some View {
        Button {
            onSelect(page)
        } label: {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? .primary : .tertiary)
        .disabled(!enabled)
    }

    private func pageSeg(_ n: Int) -> some View {
        let isCurrent = n == currentPage
        let label = displayLabel(n)
        // Short labels render as round bubbles; wide ones (e.g. "999", "1.2k")
        // widen into ovals so the number isn't cramped in a circle.
        let isWide = label.count > 2
        return Button {
            onSelect(n)
        } label: {
            Text(label)
                .font(.footnote.weight(isCurrent ? .semibold : .regular))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(isCurrent ? Color.white : Color.primary)
                .padding(.horizontal, isWide ? 9 : 0)
                .frame(minWidth: 30, minHeight: 30)
                .background { if isCurrent { Capsule().fill(Color.accentColor) } }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Numbers in the immediate window around the current page stay exact (so
    /// adjacent pages are distinguishable); the far first/last anchors abbreviate
    /// once they pass 999 (1000 → "1k", 1200 → "1.2k", 1500000 → "1.5m").
    private func displayLabel(_ n: Int) -> String {
        abs(n - currentPage) <= 1 ? "\(n)" : Self.abbreviate(n)
    }

    static func abbreviate(_ n: Int) -> String {
        switch n {
        case ..<1_000: return "\(n)"
        case ..<1_000_000: return trimmed(Double(n) / 1_000) + "k"
        default: return trimmed(Double(n) / 1_000_000) + "m"
        }
    }

    /// One decimal place, dropping a trailing ".0" (1.0 → "1", 1.2 → "1.2").
    private static func trimmed(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
    }

    /// Page tokens with ellipses: always 1 and last, plus a window around current.
    private struct Item: Identifiable {
        let id: Int
        let kind: Kind
        enum Kind { case page(Int), ellipsis }
    }

    private var items: [Item] {
        guard totalPages > 1 else { return [] }
        var numbers = Set<Int>([1, totalPages])
        for p in (currentPage - 1)...(currentPage + 1) where p >= 1 && p <= totalPages {
            numbers.insert(p)
        }
        var result: [Item] = []
        var previous = 0
        for n in numbers.sorted() {
            if n - previous > 1 {
                result.append(Item(id: -n, kind: .ellipsis))   // negative id stays unique
            }
            result.append(Item(id: n, kind: .page(n)))
            previous = n
        }
        return result
    }
}
