import SwiftUI

/// AO3-style page navigation arranged as one calm row: single-step arrows flank a
/// windowed set of page numbers (1 … 5 6 7 … 142). Long-pressing an arrow jumps
/// to the corresponding end. `SearchView` supplies the same card surface as rows.
struct SearchPaginationBar: View {
    let currentPage: Int
    let totalPages: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            navButton(.backward)

            Spacer(minLength: 18)

            // Keep the full AO3-style anchor window when it fits. On compact
            // cards, fall back to nearby pages so the bar never exceeds its row.
            ViewThatFits(in: .horizontal) {
                pageItems(items)
                pageItems(compactItems)
            }
            .layoutPriority(1)

            Spacer(minLength: 18)

            navButton(.forward)
        }
        .frame(maxWidth: .infinity)
    }

    private func pageItems(_ items: [Item]) -> some View {
        HStack(spacing: 6) {
            ForEach(items) { item in
                switch item.kind {
                case let .page(page):
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
        .fixedSize(horizontal: true, vertical: false)
    }

    private func navButton(_ direction: Direction) -> some View {
        let isBackward = direction == .backward
        let enabled = isBackward ? currentPage > 1 : currentPage < totalPages
        let tapPage = Self.navigationPage(
            direction, longPress: false, currentPage: currentPage, totalPages: totalPages
        )
        let endPage = Self.navigationPage(
            direction, longPress: true, currentPage: currentPage, totalPages: totalPages
        )
        let tapLabel = isBackward ? "Previous page" : "Next page"
        let endLabel = isBackward ? "First page" : "Last page"

        return Image(systemName: isBackward ? "chevron.left" : "chevron.right")
            .font(.caption.weight(.bold))
            .frame(width: 31, height: 31)
            .background(
                Circle().fill(enabled ? Color.accentColor.opacity(0.12)
                    : Color.secondary.opacity(0.06))
            )
            .contentShape(Circle())
            .foregroundStyle(enabled ? Color.accentColor : Color.secondary.opacity(0.35))
            .allowsHitTesting(enabled)
            .gesture(
                LongPressGesture(minimumDuration: 0.45)
                    .exclusively(before: TapGesture())
                    .onEnded { result in
                        switch result {
                        case .first:
                            onSelect(endPage)
                        case .second:
                            onSelect(tapPage)
                        }
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(tapLabel)
            .accessibilityHint("Long-press for \(endLabel.lowercased()).")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if enabled { onSelect(tapPage) }
            }
            .accessibilityAction(named: Text(endLabel)) {
                if enabled { onSelect(endPage) }
            }
    }

    enum Direction {
        case backward
        case forward
    }

    static func navigationPage(_ direction: Direction, longPress: Bool,
                               currentPage: Int, totalPages: Int) -> Int {
        switch (direction, longPress) {
        case (.backward, true):
            1
        case (.backward, false):
            max(1, currentPage - 1)
        case (.forward, true):
            totalPages
        case (.forward, false):
            min(totalPages, currentPage + 1)
        }
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
        case ..<1000: "\(page)"
        case ..<1_000_000: trimmed(Double(page) / 1000) + "k"
        default: trimmed(Double(page) / 1_000_000) + "m"
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
        for page in (currentPage - 1) ... (currentPage + 1)
            where page >= 1 && page <= totalPages {
            numbers.insert(page)
        }
        var result: [Item] = []
        var previous = 0
        for page in numbers.sorted() {
            if page - previous > 1 {
                result.append(Item(id: -page, kind: .ellipsis)) // negative id stays unique
            }
            result.append(Item(id: page, kind: .page(page)))
            previous = page
        }
        return result
    }

    /// A narrow-width fallback that keeps the current page and its neighbors.
    private var compactItems: [Item] {
        let pages = max(1, currentPage - 1) ... min(totalPages, currentPage + 1)
        return pages.map { Item(id: $0, kind: .page($0)) }
    }
}
