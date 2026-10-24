import SwiftUI

/// All rectangles are local to the consuming viewport. SDK frames already
/// include interaction margins; expanding them again would waste usable space.
nonisolated struct AdaptiveContentRegions: Equatable {
    struct Reservation: Equatable {
        var frame: CGRect
        var isActive: Bool = true
    }

    let safeBounds: CGRect
    let activeReservations: [CGRect]
    let panes: [CGRect]

    init(bounds: CGRect, safeAreaInsets: EdgeInsets = EdgeInsets(), reservations: [Reservation] = []) {
        let safe = CGRect(
            x: bounds.minX + safeAreaInsets.leading,
            y: bounds.minY + safeAreaInsets.top,
            width: max(0, bounds.width - safeAreaInsets.leading - safeAreaInsets.trailing),
            height: max(0, bounds.height - safeAreaInsets.top - safeAreaInsets.bottom)
        )
        safeBounds = safe
        activeReservations = reservations.filter(\.isActive).map(\.frame)
        panes = activeReservations.reduce([safe]) { regions, exclusion in
            regions.flatMap { Self.subtract(exclusion, from: $0) }
        }.filter { $0.width > 0 && $0.height > 0 }.sorted { $0.minX < $1.minX }
    }

    /// Project exclusions across the scroll axis: scrolling text must never
    /// enter a partial-height division further down the dashboard.
    private static func subtract(_ exclusion: CGRect, from pane: CGRect) -> [CGRect] {
        guard exclusion.maxX > pane.minX, exclusion.minX < pane.maxX,
              exclusion.maxY > pane.minY, exclusion.minY < pane.maxY else { return [pane] }
        if exclusion.height >= exclusion.width {
            let left = min(pane.maxX, max(pane.minX, exclusion.minX))
            let right = min(pane.maxX, max(pane.minX, exclusion.maxX))
            return [
                CGRect(x: pane.minX, y: pane.minY, width: left - pane.minX, height: pane.height),
                CGRect(x: right, y: pane.minY, width: pane.maxX - right, height: pane.height)
            ]
        }
        let top = min(pane.maxY, max(pane.minY, exclusion.minY))
        let bottom = min(pane.maxY, max(pane.minY, exclusion.maxY))
        return [
            CGRect(x: pane.minX, y: pane.minY, width: pane.width, height: top - pane.minY),
            CGRect(x: pane.minX, y: bottom, width: pane.width, height: pane.maxY - bottom)
        ]
    }

    /// A horizontal exclusion needs a bounded viewport on one side, rather
    /// than a vertical scroll that eventually moves content through the fold.
    var viewport: CGRect {
        guard !panes.isEmpty else { return .zero }
        if panes.count == 1 { return panes[0] }
        guard panes.allSatisfy({ $0.minY == safeBounds.minY && $0.height == safeBounds.height }) else {
            return panes.max(by: { $0.width * $0.height < $1.width * $1.height }) ?? .zero
        }
        return safeBounds
    }

    var viewportPanes: [CGRect] {
        panes.compactMap { pane in
            let visible = pane.intersection(viewport)
            guard !visible.isNull, visible.width > 0, visible.height > 0 else { return nil }
            return visible.offsetBy(dx: -viewport.minX, dy: -viewport.minY)
        }
    }

    @MainActor static func columns(in width: CGFloat, cardWidth: CGFloat, gutter: CGFloat = 16) -> Int {
        let usable = max(0, width - 2 * gutter)
        return max(1, Int((usable + CarouselCardMetrics.compactGridColumnSpacing)
            / (max(1, cardWidth) + CarouselCardMetrics.compactGridColumnSpacing)))
    }

    @MainActor static func hasDashboardHeight(_ height: CGFloat) -> Bool {
        height >= 2 * CarouselCardMetrics.height + CarouselCardMetrics.compactGridSpacing + 24
    }

    @MainActor static func usesGroupedShelves(in size: CGSize) -> Bool {
        hasDashboardHeight(size.height) && columns(in: size.width, cardWidth: CarouselCardMetrics.width) >= 3
    }

    /// One logical page spans panes, but each pane scrolls only complete cards.
    /// Indices are assigned across a row before advancing to the next row.
    static func shelfPages(count: Int, columns: [Int]) -> [[[Int]]] {
        guard count > 0, !columns.isEmpty else { return [] }
        let columns = columns.map { max(1, $0) }
        let rowWidth = columns.reduce(0, +)
        let rows = columns.allSatisfy { $0 > 1 } ? 2 : 1
        let capacity = rowWidth * rows
        return stride(from: 0, to: count, by: capacity).map { start in
            columns.indices.map { pane in
                let preceding = columns.prefix(pane).reduce(0, +)
                return (0..<rows).flatMap { row in
                    (0..<columns[pane]).compactMap { column in
                        let index = start + row * rowWidth + preceding + column
                        return index < count ? index : nil
                    }
                }
            }
        }
    }

    @MainActor func resumePanes(hasNext: Bool, cardWidth: CGFloat, rightToLeft: Bool = false) -> [CGRect]? {
        let physical = viewportPanes
        if physical.count > 1 {
            let ordered = rightToLeft ? Array(physical.reversed()) : physical
            return Array(ordered.prefix(hasNext ? 2 : 1))
        }
        guard hasNext, Self.hasDashboardHeight(viewport.height),
              Self.heroFits(in: viewport.width, cardWidth: cardWidth) else { return nil }
        let minimumHero = max(300, cardWidth)
        let minimumNext = 2 * cardWidth + 12 + 32
        let heroWidth = min(max(520, minimumHero), min(max(minimumHero, viewport.width * 0.48),
                                                    viewport.width - minimumNext - 24))
        let nextWidth = viewport.width - heroWidth - 24
        return [
            CGRect(x: rightToLeft ? viewport.width - heroWidth : 0, y: 0,
                   width: heroWidth, height: viewport.height),
            CGRect(x: rightToLeft ? 0 : heroWidth + 24, y: 0,
                   width: nextWidth, height: viewport.height)
        ]
    }

    static func heroFits(in width: CGFloat, cardWidth: CGFloat) -> Bool {
        // Both a readable hero and two natural-size neighbouring cards must fit.
        width >= max(300, cardWidth) + 24 + 2 * cardWidth + 12 + 32
    }
}

extension EnvironmentValues {
    @Entry var dashboardContentRegions: AdaptiveContentRegions?
}

/// Measure outside the vertical scroll: reservations stay in viewport coordinates
/// even while sections move. No device identity, screen bounds or fold constants.
struct DashboardRegionHost<Content: View>: View {
    @Environment(\.dashboardContentRegions) private var inheritedRegions
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if os(iOS)
        if inheritedRegions != nil {
            content()
        } else {
            GeometryReader { proxy in
                let regions = regions(in: proxy)
                let viewport = regions.viewport
                content()
                    .environment(\.dashboardContentRegions, regions)
                    .frame(width: viewport.width, height: viewport.height)
                    .position(x: viewport.midX, y: viewport.midY)
                    .opacity(viewport.isEmpty ? 0 : 1)
                    .accessibilityHidden(viewport.isEmpty)
            }
        }
        #else
        content()
        #endif
    }

    #if os(iOS)
    private func regions(in proxy: GeometryProxy) -> AdaptiveContentRegions {
        var reservations: [AdaptiveContentRegions.Reservation] = []
        if #available(iOS 27.1, *) {
            reservations = (proxy.reservedRegions(kind: .division, layoutDirectionBehavior: .fixed)
                + proxy.reservedRegions(kind: .occlusion, layoutDirectionBehavior: .fixed))
                .map { .init(frame: $0.frame, isActive: $0.isActive) }
        }
        // This host participates in normal safe-area layout, like T-447's
        // viewport: its proposal already excludes navigation/tab chrome.
        return AdaptiveContentRegions(bounds: CGRect(origin: .zero, size: proxy.size), reservations: reservations)
    }
    #endif
}

/// Intrinsic height, physical pane coordinates, logical child/VoiceOver order.
struct DashboardRegionRow: Layout {
    var panes: [CGRect]
    var width: CGFloat
    var fillsHeight = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = zip(subviews, panes).map { view, pane in
            view.sizeThatFits(ProposedViewSize(width: pane.width, height: nil)).height
        }.max() ?? 0
        return CGSize(width: width, height: fillsHeight ? proposal.height ?? height : height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, pane) in zip(subviews, panes) {
            view.place(
                at: CGPoint(x: bounds.minX + pane.minX, y: bounds.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: pane.width, height: fillsHeight ? bounds.height : nil)
            )
        }
    }
}

extension View {
    func dashboardLeadingRegion(fillsHeight: Bool = false) -> some View {
        modifier(DashboardLeadingRegion(fillsHeight: fillsHeight))
    }
}

private struct DashboardLeadingRegion: ViewModifier {
    var fillsHeight: Bool
    @Environment(\.dashboardContentRegions) private var regions
    @Environment(\.layoutDirection) private var direction

    func body(content: Content) -> some View {
        if let regions, regions.viewportPanes.count > 1,
           let pane = direction == .rightToLeft ? regions.viewportPanes.last : regions.viewportPanes.first {
            DashboardRegionRow(panes: [pane], width: regions.viewport.width, fillsHeight: fillsHeight) {
                content.environment(\.dashboardContentRegions, nil)
            }
        } else {
            content
        }
    }
}
