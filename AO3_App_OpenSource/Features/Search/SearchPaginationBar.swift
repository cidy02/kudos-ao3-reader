import SwiftUI

/// AO3-style page navigation arranged as a compact card: directional controls and
/// a clear page status sit above a windowed set of page numbers
/// (1 … 5 6 7 … 142). `SearchView` supplies the same card surface as result rows.
struct SearchPaginationBar: View {
    let currentPage: Int
    let totalPages: Int
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    navButton("chevron.left.2", label: "First page",
                              page: 1, enabled: currentPage > 1)
                    navButton("chevron.left", label: "Previous page",
                              page: currentPage - 1, enabled: currentPage > 1)
                }

                Spacer(minLength: 6)

                VStack(spacing: 1) {
                    Text("Page \(currentPage)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Text("of \(totalPages)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                Spacer(minLength: 6)

                HStack(spacing: 5) {
                    navButton("chevron.right", label: "Next page",
                              page: currentPage + 1, enabled: currentPage < totalPages)
                    navButton("chevron.right.2", label: "Last page",
                              page: totalPages, enabled: currentPage < totalPages)
                }
            }

            HStack(spacing: 6) {
                ForEach(items) { item in
                    switch item.kind {
                    case .page(let page):
                        pageButton(page)
                    case .ellipsis:
                        Image(systemName: "ellipsis")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 18, height: 31)
                            .accessibilityHidden(true)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private func navButton(_ symbol: String, label: String,
                           page: Int, enabled: Bool) -> some View {
        Button {
            onSelect(page)
        } label: {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .frame(width: 31, height: 31)
                .background(
                    Circle().fill(enabled ? Color.accentColor.opacity(0.12)
                        : Color.secondary.opacity(0.06))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.accentColor : Color.secondary.opacity(0.35))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func pageButton(_ page: Int) -> some View {
        let isCurrent = page == currentPage
        let label = displayLabel(page)
        // Short labels render as round bubbles; wide ones (e.g. "999", "1.2k")
        // widen into ovals so the number isn't cramped in a circle.
        let isWide = label.count > 2
        return Button {
            onSelect(page)
        } label: {
            Text(label)
                .font(.footnote.weight(isCurrent ? .bold : .medium))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(isCurrent ? Color.white : Color.primary)
                .padding(.horizontal, isWide ? 9 : 0)
                .frame(minWidth: 31, minHeight: 31)
                .background(
                    Capsule().fill(isCurrent ? Color.accentColor
                        : Color.primary.opacity(0.055))
                )
                .overlay {
                    if !isCurrent {
                        Capsule().strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Page \(page)")
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }

    /// Numbers in the immediate window around the current page stay exact (so
    /// adjacent pages are distinguishable); the far first/last anchors abbreviate
    /// once they pass 999 (1000 → "1k", 1200 → "1.2k", 1500000 → "1.5m").
    private func displayLabel(_ page: Int) -> String {
        abs(page - currentPage) <= 1 ? "\(page)" : Self.abbreviate(page)
    }

    static func abbreviate(_ page: Int) -> String {
        switch page {
        case ..<1_000: return "\(page)"
        case ..<1_000_000: return trimmed(Double(page) / 1_000) + "k"
        default: return trimmed(Double(page) / 1_000_000) + "m"
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
        for page in (currentPage - 1)...(currentPage + 1)
            where page >= 1 && page <= totalPages {
            numbers.insert(page)
        }
        var result: [Item] = []
        var previous = 0
        for page in numbers.sorted() {
            if page - previous > 1 {
                result.append(Item(id: -page, kind: .ellipsis))   // negative id stays unique
            }
            result.append(Item(id: page, kind: .page(page)))
            previous = page
        }
        return result
    }
}
