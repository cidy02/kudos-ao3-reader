import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A dashboard section used across Home and Library: a bold Title 3 header with a grey
/// count and a trailing See All or action link, over a horizontal card carousel ending in a
/// "+N more" tile when items remain hidden (T-483).
///
/// Follows the Kudos See All rule: See All and "+N more" appear only when content is hidden.
/// When everything fits, the trailing link names its action (e.g. "Organise").
struct WorkCarouselSection<Cards: View, Empty: View>: View {
    private let title: String
    private let hasItems: Bool
    /// Shown beside the label, in the spec's grey figure. Nil hides
    /// it — a section whose count is not a fact worth stating (an AO3-paged
    /// list showing one page of many) should not print a misleading one.
    private let itemCount: Int?
    /// Wins over `itemCount` when a section's count is not a bare number,
    /// such as Downloaded's "98 · 2.1 GB".
    private let countText: String?
    /// Between cards side by side on a shelf.
    private let cardSpacing: CGFloat
    private let cardWidth: CGFloat
    /// Visible card count, defaulting to min(itemCount, 12).
    private let visibleCount: Int?
    /// Action label when everything fits (e.g. "Organise").
    private let actionTitle: String?
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
        countText: String? = nil,
        cardSpacing: CGFloat = CarouselCardMetrics.compactGridColumnSpacing,
        cardWidth: CGFloat = CarouselCardMetrics.width,
        visibleCount: Int? = nil,
        actionTitle: String? = nil,
        onSeeAll: (() -> Void)? = nil,
        @ViewBuilder cards: @escaping () -> Cards,
        @ViewBuilder emptyState: @escaping () -> Empty
    ) {
        self.title = title
        self.hasItems = hasItems
        self.itemCount = itemCount
        self.countText = countText
        self.cardSpacing = cardSpacing
        self.cardWidth = cardWidth
        self.visibleCount = visibleCount
        self.actionTitle = actionTitle
        self.onSeeAll = onSeeAll
        self.cards = cards
        self.emptyState = emptyState
        _collapsed = AppStorage(wrappedValue: false, "section.collapsed.\(collapseKey)")
    }

    /// 1b/1c: 11pt from the header to the cards. The shelf's scroll view pads
    /// 6pt above its cards for their shadow, so the stack spacing is what is left.
    private var headerSpacing: CGFloat { 11 - 6 }

    private var decision: SectionSeeAllDecision {
        SectionSeeAllDecision(
            totalCount: itemCount ?? 0,
            visibleCount: visibleCount ?? min(itemCount ?? 0, 12),
            actionTitleWhenFitting: actionTitle
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: headerSpacing) {
            header
            if !collapsed {
                if hasItems {
                    DashboardCardShelf(
                        compactSpacing: cardSpacing,
                        columnSpacing: cardSpacing,
                        cardWidth: cardWidth
                    ) {
                        cards()
                        if decision.showsCarouselMoreTile, let onSeeAll {
                            CarouselMoreTile(
                                count: decision.hiddenCount,
                                sectionTitle: title,
                                action: onSeeAll
                            )
                        }
                    }
                } else {
                    emptyState()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .dashboardLeadingRegion()
                }
            }
        }
    }

    private var header: some View {
        SectionRuleHeader(
            title: title,
            count: itemCount,
            countText: countText,
            actionTitle: decision.headerLinkLabel,
            isCollapsed: collapsed,
            onToggleCollapse: {
                withAnimationUnlessReduced(.snappy(duration: 0.22), reduceMotion: reduceMotion) {
                    collapsed.toggle()
                }
            },
            onSeeAll: hasItems && decision.headerLinkLabel != nil ? onSeeAll : nil
        )
        .dashboardLeadingRegion()
    }
}

/// Trailing "+N more" tile that closes a carousel shelf when works remain hidden (T-483).
///
/// Per the See All rule and spec (boards 00, 01, 56):
/// 16 pt corner radius (I-7), 96 pt wide, secondary surface fill, app accent ink,
/// opening the shelf's category page.
struct CarouselMoreTile: View {
    let count: Int
    let sectionTitle: String
    var width: CGFloat = 96
    let action: () -> Void

    @Environment(\.uniformWorkCardHeight) private var uniformHeight

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("+\(count)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("more")
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.accentInk)
            .frame(width: width)
            .frame(height: uniformHeight ?? 166)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    #if os(iOS)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    #else
                    .fill(Color(nsColor: .controlBackgroundColor))
                    #endif
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(count) more in \(sectionTitle)")
    }
}

/// Trailing "N more" row that closes a content list when works remain hidden (T-483).
///
/// Per I-17, aligns with the list's separator inset (e.g. 79 pt on ledger rows, 16 pt on edge-aligned rows)
/// and opens the category page.
struct ListMoreRow: View {
    let count: Int
    var sectionTitle: String? = nil
    var leadingInset: CGFloat = 16
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("\(count) more")
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.accentInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, leadingInset)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(sectionTitle != nil ? "\(count) more in \(sectionTitle!)" : "\(count) more")
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
    private let visibleCount: Int?
    private let actionTitle: String?
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
        visibleCount: Int? = nil,
        actionTitle: String? = nil,
        onSeeAll: (() -> Void)? = nil,
        topSpacing: CGFloat = 22,
        @ViewBuilder rows: @escaping () -> Rows,
        @ViewBuilder emptyState: @escaping () -> Empty
    ) {
        self.title = title
        self.hasItems = hasItems
        self.itemCount = itemCount
        self.visibleCount = visibleCount
        self.actionTitle = actionTitle
        self.onSeeAll = onSeeAll
        self.topSpacing = topSpacing
        self.rows = rows
        self.emptyState = emptyState
        _collapsed = AppStorage(wrappedValue: false, "section.collapsed.\(collapseKey)")
    }

    private var decision: SectionSeeAllDecision {
        SectionSeeAllDecision(
            totalCount: itemCount ?? 0,
            visibleCount: visibleCount ?? min(itemCount ?? 0, 12),
            actionTitleWhenFitting: actionTitle
        )
    }

    var body: some View {
        Group {
            SectionRuleHeader(
                title: title,
                count: itemCount,
                actionTitle: decision.headerLinkLabel,
                isCollapsed: collapsed,
                onToggleCollapse: {
                    withAnimationUnlessReduced(.snappy(duration: 0.22), reduceMotion: reduceMotion) {
                        collapsed.toggle()
                    }
                },
                onSeeAll: hasItems && decision.headerLinkLabel != nil ? onSeeAll : nil
            )
            // 1d: 22pt between sections, 10pt to the first row (5 here + the
            // row's own 5).
            .dashboardListRow(EdgeInsets(top: topSpacing, leading: 0, bottom: 5, trailing: 0))

            if !collapsed {
                if hasItems {
                    rows()
                    if decision.showsListMoreRow, let onSeeAll {
                        ListMoreRow(
                            count: decision.hiddenCount,
                            sectionTitle: title,
                            leadingInset: 79,
                            action: onSeeAll
                        )
                        .dashboardListRow(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 16))
                    }
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
