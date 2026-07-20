import SwiftUI

/// AO3-style page navigation arranged as one calm row: single-step arrows flank a
/// windowed set of page numbers (1 … 5 6 7 … 142). Long-pressing (or right-
/// clicking) an arrow opens a menu to jump to the corresponding end.
/// `SearchView` supplies the same card surface as rows.
struct SearchPaginationBar: View {
    let currentPage: Int
    let totalPages: Int
    let onSelect: (Int) -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: 0) {
            navButton(.backward)

            // 5pt, not 18: the arrows' own .minimumHitTarget() (44pt) already
            // reserves ~6.5pt of invisible margin on each side, which now
            // supplies most of the visual separation this spacer used to.
            // Keeping the old 18pt here would double-charge that gap against
            // the ViewThatFits budget below and force the compact fallback
            // sooner than before the arrows grew (HIG Wave 3 review-fix F1).
            // Spacer still expands to fill extra room, so wide bars are
            // unaffected — only the minimum shrank.
            Spacer(minLength: 5)

            // Keep the full AO3-style anchor window when it fits. On compact
            // cards, fall back to nearby pages so the bar never exceeds its row.
            ViewThatFits(in: .horizontal) {
                pageItems(items)
                pageItems(compactItems)
            }
            .layoutPriority(1)

            Spacer(minLength: 5)

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

        // A real Button (not a bare Image + gesture) so Tab / Full Keyboard Access
        // can focus and activate it (HIG audit A9-F1). `.contextMenu` replaces the
        // old bespoke hidden long-press gesture with a standard, labeled system
        // menu for the jump-to-end action — still only revealed by a long-press/
        // right-click, not visible up front, but a native affordance a user has
        // already learned elsewhere, plus proper VoiceOver exposure: SwiftUI
        // auto-exposes contextMenu content as a VoiceOver custom action, so no
        // separate `.accessibilityAction(named:)` is needed here; adding one
        // would just register the same "First/Last page" action twice.
        return Button {
            if enabled { onSelect(tapPage) }
        } label: {
            Image(systemName: isBackward ? "chevron.left" : "chevron.right")
                .font(.caption.weight(.bold))
                // min-, not exact-, frame: parity with pageButton's pill so the
                // chevron can grow with Dynamic Type instead of clipping against
                // a fixed 31×31 circle (T-115 UI-3's Dynamic-Type sub-point).
                .frame(minWidth: 31, minHeight: 31)
                .background(
                    Circle().fill(enabled ? Color.accentColor.opacity(0.12)
                        : Color.secondary.opacity(0.06))
                )
                .foregroundStyle(enabled ? Color.accentColor : Color.secondary.opacity(0.35))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(enabled)
        // Grows the tap/focus region to 44pt without touching the 31pt visual
        // chrome above (HIG audit UI-3). Last modifier per its own doc comment.
        .minimumHitTarget()
        .contextMenu {
            // Gated on the item's presence, not just its action: an empty
            // contextMenu doesn't present at all, so a disabled arrow's
            // long-press/right-click stays fully inert (matching its pre-Button
            // behavior) instead of showing a menu with a silently no-op item,
            // and VoiceOver's auto-exposed custom action disappears along with
            // it rather than advertising an action that does nothing.
            if enabled {
                Button(endLabel) { onSelect(endPage) }
            }
        }
        .accessibilityLabel(tapLabel)
        .accessibilityHint("Long-press for \(endLabel.lowercased()).")
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
                .foregroundStyle(isCurrent ? theme.onEffectiveTint : Color.primary)
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
        // Self-documenting floor, not an enlargement: the label above already
        // carries `.frame(minWidth: 31, minHeight: 31)`, so every pill is
        // already ≥31×31 before this modifier — 28 < 31 adds no size. Its only
        // real effect is `.contentShape(Rectangle())` making the capsule's
        // corner regions tappable (the label's own `.contentShape(Capsule())`
        // otherwise excludes them). The 44pt default was deliberately NOT used
        // here: pills sit only 6pt apart in `pageItems`, which is `.fixedSize`
        // inside a `.layoutPriority(1)` `ViewThatFits` — a genuine 44pt-per-pill
        // minimum would widen the row and fall back to the cramped
        // `compactItems` variant sooner (HIG audit UI-3/A9-F1; kept at 31pt,
        // same conclusion Wave 3's review-fix round reached for the arrows'
        // hit region vs. their 31pt visual chrome).
        .minimumHitTarget(28)
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

    /// Page window for the narrow-width fallback: the current page and its
    /// neighbors, as a range that is valid for ANY input pair. Pagination state
    /// is remote-derived, and `currentPage ≤ totalPages` currently holds only
    /// because `AO3Client.paginationTotal(in:currentPage:)` happens to seed its
    /// max-scan with the requested page — an accident of the parser, not a
    /// contract. Unclamped, a stale `currentPage` past a shrunken `totalPages`
    /// (e.g. 7 of 5) would build `6...5` and trap at render time — and
    /// `ViewThatFits` evaluates `compactItems` on every `body` pass, even when
    /// the full window is the variant displayed.
    static func compactPageWindow(currentPage: Int, totalPages: Int) -> ClosedRange<Int> {
        let last = max(totalPages, 1)
        let anchor = min(max(currentPage, 1), last)
        return max(1, anchor - 1) ... min(last, anchor + 1)
    }

    /// A narrow-width fallback that keeps the current page and its neighbors.
    private var compactItems: [Item] {
        Self.compactPageWindow(currentPage: currentPage, totalPages: totalPages)
            .map { Item(id: $0, kind: .page($0)) }
    }
}
