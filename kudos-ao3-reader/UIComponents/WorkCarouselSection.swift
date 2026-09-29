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

    /// 1b/1c: 11pt from the header to the cards; 1d: 10pt to the first row. The
    /// shelf's scroll view pads 6pt above its cards for their shadow, and the
    /// ledger 2pt, so the stack spacing is what is left.
    private var headerSpacing: CGFloat {
        layout == .shelves ? 11 - 6 : 10 - 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: headerSpacing) {
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
                        // The card shadows fall past the shelf; clipped, they
                        // ended in a hard-edged band across the page.
                        .scrollClipDisabled()
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

/// A ledger section as `List` rows rather than a stacked `VStack`, so each work
/// row can carry swipe actions — only a `List` row offers them (owner,
/// 2026-09-29: the Library ledger had none). Same header, same collapse key, so
/// switching layouts keeps a section folded or open.
///
/// The header is an ordinary row, not a `Section` header: a plain list pins
/// section headers to the top while scrolling, which the dashboard never did.
struct WorkLedgerListSection<Rows: View, Empty: View>: View {
    private let title: String
    private let hasItems: Bool
    private let itemCount: Int?
    private let onSeeAll: (() -> Void)?
    private let rows: () -> Rows
    private let emptyState: () -> Empty
    private let topSpacing: CGFloat

    @AppStorage private var collapsed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        collapseKey: String,
        hasItems: Bool,
        itemCount: Int? = nil,
        onSeeAll: (() -> Void)? = nil,
        topSpacing: CGFloat = 22,
        @ViewBuilder rows: @escaping () -> Rows,
        @ViewBuilder emptyState: @escaping () -> Empty
    ) {
        self.title = title
        self.hasItems = hasItems
        self.itemCount = itemCount
        self.onSeeAll = onSeeAll
        self.rows = rows
        self.emptyState = emptyState
        self.topSpacing = topSpacing
        _collapsed = AppStorage(wrappedValue: false, "section.collapsed.\(collapseKey)")
    }

    var body: some View {
        Group {
            SectionRuleHeader(
                title: title,
                count: itemCount,
                isCollapsed: collapsed,
                onToggleCollapse: {
                    withAnimationUnlessReduced(.snappy(duration: 0.22), reduceMotion: reduceMotion) {
                        collapsed.toggle()
                    }
                },
                onSeeAll: hasItems ? onSeeAll : nil
            )
            // 1d: 22pt between sections, 10pt to the first row (5 here + the
            // row's own 5).
            .dashboardListRow(EdgeInsets(top: topSpacing, leading: 0, bottom: 5, trailing: 0))

            if !collapsed {
                if hasItems {
                    rows()
                } else {
                    emptyState()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .dashboardListRow(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }
            }
        }
    }
}

extension View {
    /// A dashboard row in a plain `List`: the page's own spacing, no separator,
    /// and no row fill — the rows paint their own card.
    func dashboardListRow(
        _ insets: EdgeInsets = EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16)
    ) -> some View {
        listRowInsets(insets)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
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
