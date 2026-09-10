import SwiftUI

/// A dashboard section used across Home and Library: a header with a collapse
/// toggle and a `>` chevron that opens the full vertical list, over a horizontal
/// card carousel (or a per-section empty state). Collapse state persists per
/// section via `@AppStorage`.
///
/// Per the layout spec: horizontal cards by default, collapsible, and a `>` chevron
/// (not a "See all" button) that opens the full list. Follows the Kudos design
/// philosophy — simple and scannable by default, with depth one tap away.
///
/// The header itself is `SectionRuleHeader` (see `SubjectSurface.swift`) — the
/// redesign's kicker / count / hairline / chevron treatment, shared with every
/// other shelf in the app so Home and Library read as one surface.
struct WorkCarouselSection<Cards: View, Empty: View>: View {
    private let title: String
    private let hasItems: Bool
    /// Shown beside the label, in the spec's monospaced dim figure. Nil hides
    /// it — a section whose count is not a fact worth stating (an AO3-paged
    /// list showing one page of many) should not print a misleading one.
    private let itemCount: Int?
    private let onSeeAll: (() -> Void)?
    private let cards: () -> Cards
    private let emptyState: () -> Empty

    @AppStorage private var collapsed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        collapseKey: String,
        hasItems: Bool,
        itemCount: Int? = nil,
        onSeeAll: (() -> Void)? = nil,
        @ViewBuilder cards: @escaping () -> Cards,
        @ViewBuilder emptyState: @escaping () -> Empty
    ) {
        self.title = title
        self.hasItems = hasItems
        self.itemCount = itemCount
        self.onSeeAll = onSeeAll
        self.cards = cards
        self.emptyState = emptyState
        _collapsed = AppStorage(wrappedValue: false, "section.collapsed.\(collapseKey)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header
            if !collapsed {
                if hasItems {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) { cards() }
                            .uniformWorkCardHeights()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                    }
                } else {
                    emptyState()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                }
            }
        }
    }

    private var header: some View {
        SectionRuleHeader(
            title: title,
            count: itemCount,
            isCollapsed: collapsed,
            onToggleCollapse: {
                withAnimationUnlessReduced(.snappy(duration: 0.22), reduceMotion: reduceMotion) {
                    collapsed.toggle()
                }
            },
            // Only when there is content: a chevron into an empty list is a
            // promise the destination cannot keep.
            onSeeAll: hasItems ? onSeeAll : nil
        )
    }
}

/// A small, reusable section empty-state label for the carousels.
struct SectionEmptyState: View {
    let message: String
    var systemImage: String = "tray"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }
}
