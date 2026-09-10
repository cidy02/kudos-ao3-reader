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
/// Whether a dashboard lays its sections out as shelves of cover cards or as a
/// ledger of full-width rows — the choice spec 1c puts in the "…" menu, and the
/// difference between artboards 1c and 1d.
///
/// Persisted per dashboard rather than per section: the spec draws it as one
/// decision about how the whole page reads, and a page half in one mode and half
/// in the other is neither.
nonisolated enum WorkSectionLayout: String, CaseIterable {
    case shelves
    case ledger

    var title: String {
        switch self {
        case .shelves: "Shelves"
        case .ledger: "Ledger"
        }
    }

    var symbol: String {
        switch self {
        case .shelves: "rectangle.grid.2x2"
        case .ledger: "list.bullet"
        }
    }
}

struct WorkCarouselSection<Cards: View, Empty: View>: View {
    private let title: String
    private let hasItems: Bool
    /// Shown beside the label, in the spec's monospaced dim figure. Nil hides
    /// it — a section whose count is not a fact worth stating (an AO3-paged
    /// list showing one page of many) should not print a misleading one.
    private let itemCount: Int?
    /// Shelves scrolls the cards sideways; ledger stacks them down the page. The
    /// header is identical either way, which is the point — the page changes how
    /// it reads without changing what it is.
    private let layout: WorkSectionLayout
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
        layout: WorkSectionLayout = .shelves,
        onSeeAll: (() -> Void)? = nil,
        @ViewBuilder cards: @escaping () -> Cards,
        @ViewBuilder emptyState: @escaping () -> Empty
    ) {
        self.title = title
        self.hasItems = hasItems
        self.itemCount = itemCount
        self.layout = layout
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
                    switch layout {
                    case .shelves:
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 12) { cards() }
                                .uniformWorkCardHeights()
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                        }
                    case .ledger:
                        // No `uniformWorkCardHeights` here: that exists to stop a
                        // shelf of side-by-side cards ragging at different heights.
                        // Stacked rows have no such problem, and forcing them to a
                        // common height would pad every short row to match the
                        // tallest title on the page.
                        VStack(spacing: 10) { cards() }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 2)
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
