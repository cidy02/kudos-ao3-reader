import SwiftUI

extension EnvironmentValues {
    /// Card space after the host's safe area and content gutters, not the screen.
    @Entry var carouselCardAvailableWidth: CGFloat?
    /// A grid's stretched column width. Carousels leave this nil and stay at 120 pt.
    @Entry var carouselGridCardWidth: CGFloat?
}

extension ScrollView {
    /// Keeps sideways scrolling inside the usable viewport, even when shadows
    /// need to escape vertically. Content keeps its existing horizontal padding.
    @MainActor @ViewBuilder func horizontalScrollViewport(
        preservesShadows: Bool = false,
        cardGutter: CGFloat = 0
    ) -> some View {
        #if os(iOS)
        HorizontalScrollViewport(scrollView: self, preservesShadows: preservesShadows, cardGutter: cardGutter)
        #else
        if preservesShadows {
            scrollClipDisabled()
        } else {
            self
        }
        #endif
    }
}

#if os(iOS)
private struct HorizontalScrollViewport<Content: View>: View {
    let scrollView: ScrollView<Content>
    let preservesShadows: Bool
    let cardGutter: CGFloat
    @State private var availableWidth: CGFloat?
    @Environment(\.carouselCardAvailableWidth) private var inheritedWidth
    @Namespace private var viewportSpace

    init(scrollView: ScrollView<Content>, preservesShadows: Bool, cardGutter: CGFloat) {
        self.scrollView = scrollView
        self.preservesShadows = preservesShadows
        self.cardGutter = cardGutter
    }

    var body: some View {
        // This layout container already receives the parent's usable width.
        ZStack(alignment: .topLeading) {
            ScrollView(scrollView.axes, showsIndicators: scrollView.showsIndicators) {
                scrollView.content
                    .mask {
                        GeometryReader { proxy in
                            if let viewport = proxy.bounds(of: .named(viewportSpace)) {
                                // Convert viewport bounds into the moving content's
                                // coordinates. Only cards/chips and their shadows
                                // are masked; the scroll/page background is outside.
                                Path(HorizontalScrollViewportMetrics.clipRect(
                                    viewportBounds: viewport,
                                    contentHeight: proxy.size.height,
                                    preservesShadows: preservesShadows
                                ))
                            }
                        }
                    }
            }
            .environment(\.carouselCardAvailableWidth, availableWidth ?? inheritedWidth)
            // SwiftUI adds the safe area; the HStack still owns its design gutter.
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .scrollClipDisabled(preservesShadows)
        }
        .coordinateSpace(.named(viewportSpace))
        .onGeometryChange(for: CGFloat.self) { proxy in
            max(0, proxy.size.width - 2 * cardGutter)
        } action: { availableWidth = $0 > 0 ? $0 : nil }
    }
}
#endif

enum HorizontalScrollViewportMetrics {
    static func clipRect(viewportBounds: CGRect, contentHeight: CGFloat, preservesShadows: Bool) -> CGRect {
        // Three of the current card shadow radii plus their offset fit in 32pt.
        let overflow: CGFloat = preservesShadows ? 32 : 0
        return CGRect(
            x: viewportBounds.minX, y: -overflow,
            width: viewportBounds.width, height: contentHeight + 2 * overflow
        )
    }
}

/// The grid and its cards must use the same measured width. Measuring here,
/// inside the caller's padding, also handles a grid hosted in a narrower pane.
struct CarouselCardGrid<Content: View>: View {
    let uniformHeights: Bool
    var columnCount: Int?
    var containerWidth: CGFloat?
    var columnSpacing: CGFloat
    /// 120 pt covers stretch. Any other base width (the 150 pt stacks) does not.
    private let baseCardWidth: CGFloat
    @ViewBuilder var content: () -> Content
    @State private var availableWidth: CGFloat?
    @ScaledMetric(relativeTo: .body) private var gridMinimum = CarouselCardMetrics.gridMinimumWidth
    private var cardSize: ScaledCarouselCardSize

    init(
        uniformHeights: Bool = false,
        columnCount: Int? = nil,
        containerWidth: CGFloat? = nil,
        columnSpacing: CGFloat = CarouselCardMetrics.compactGridColumnSpacing,
        cardWidth: CGFloat = CarouselCardMetrics.width,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.uniformHeights = uniformHeights
        self.columnCount = columnCount
        self.containerWidth = containerWidth
        self.columnSpacing = columnSpacing
        baseCardWidth = cardWidth
        cardSize = ScaledCarouselCardSize(width: cardWidth)
        self.content = content
    }

    var body: some View {
        #if os(iOS)
        grid(minimum: cardSize.width(in: containerWidth ?? availableWidth))
            .environment(\.carouselCardAvailableWidth, containerWidth ?? availableWidth)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { availableWidth = $0 > 0 ? $0 : nil }
        #else
        grid(minimum: cardSize.width)
        #endif
    }

    private func grid(minimum: CGFloat) -> some View {
        Group {
            if uniformHeights {
                cells(minimum: minimum).uniformWorkCardHeights()
            } else {
                cells(minimum: minimum)
            }
        }
    }

    private func cells(minimum: CGFloat) -> some View {
        let available = containerWidth ?? availableWidth
        let columns = gridColumns(in: available, fallbackMinimum: minimum)
        return LazyVGrid(
            columns: columns.items,
            alignment: columns.alignment,
            spacing: CarouselCardMetrics.compactGridSpacing
        ) {
            content()
        }
        .environment(\.carouselGridCardWidth, columns.cardWidth)
    }

    /// Cover grids: at least 112 pt per column, then each card stretches to fill
    /// the row. An explicit count (a shelf page) keeps that count and still
    /// stretches. Any other base width keeps the pre-branch adaptive columns
    /// (`4948b820`) and does not publish a stretched width.
    private func gridColumns(
        in available: CGFloat?, fallbackMinimum: CGFloat
    ) -> (items: [GridItem], cardWidth: CGFloat?, alignment: HorizontalAlignment) {
        guard CarouselCardMetrics.stretchesToFill(baseWidth: baseCardWidth) else {
            return legacyColumns(fallbackMinimum: fallbackMinimum)
        }
        guard let available, available > 0 else {
            return (
                CarouselCardMetrics.adaptiveCardColumns(
                    minimum: fallbackMinimum, spacing: columnSpacing
                ),
                nil,
                .leading
            )
        }
        let count = columnCount.map { max(1, $0) } ?? CarouselCardMetrics.gridColumnCount(
            availableWidth: available, minimum: gridMinimum, spacing: columnSpacing
        )
        let cardWidth = CarouselCardMetrics.gridCardWidth(
            availableWidth: available, columns: count, spacing: columnSpacing
        )
        return (
            Array(
                repeating: GridItem(.fixed(max(cardWidth, 1)), spacing: columnSpacing),
                count: count
            ),
            cardWidth,
            .leading
        )
    }

    /// `4948b820`: a counted shelf page is fixed at the card's own width;
    /// otherwise `.adaptive`, centred, capped at that width.
    private func legacyColumns(
        fallbackMinimum: CGFloat
    ) -> (items: [GridItem], cardWidth: CGFloat?, alignment: HorizontalAlignment) {
        if let columnCount {
            let count = max(1, columnCount)
            return (
                Array(
                    repeating: GridItem(.fixed(max(fallbackMinimum, 1)), spacing: columnSpacing),
                    count: count
                ),
                nil,
                .leading
            )
        }
        return (
            CarouselCardMetrics.adaptiveCardColumns(
                minimum: fallbackMinimum, spacing: columnSpacing
            ),
            nil,
            .center
        )
    }
}

/// Compact shelves keep T-447's scrolling path. Wide shelves page bounded,
/// row-major two-row grids; a division gives each pane its own complete pages.
struct DashboardCardShelf<Content: View>: View {
    var groupsInSinglePane: Bool = false
    var compactSpacing: CGFloat = 12
    /// Between cards side by side in the wide grids; the column count allows for it.
    var columnSpacing: CGFloat = CarouselCardMetrics.compactGridColumnSpacing
    @ViewBuilder var content: () -> Content
    @Environment(\.dashboardContentRegions) private var regions
    @Environment(\.layoutDirection) private var direction
    private let baseCardWidth: CGFloat
    private var cardSize: ScaledCarouselCardSize
    @State private var visiblePage: Int? = 0

    init(
        groupsInSinglePane: Bool = false,
        compactSpacing: CGFloat = 12,
        columnSpacing: CGFloat = CarouselCardMetrics.compactGridColumnSpacing,
        cardWidth: CGFloat = CarouselCardMetrics.width,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.groupsInSinglePane = groupsInSinglePane
        self.compactSpacing = compactSpacing
        self.columnSpacing = columnSpacing
        baseCardWidth = cardWidth
        cardSize = ScaledCarouselCardSize(width: cardWidth)
        self.content = content
    }

    var body: some View {
        #if os(iOS)
        // One column in a single pane would page one card at a time with no hint
        // of the next; the compact scroll keeps it in view.
        if let regions, regions.viewportPanes.count > 1
            || (groupsInSinglePane && AdaptiveContentRegions.columns(
                in: regions.viewport.width, cardWidth: cardSize.width(in: nil), spacing: columnSpacing) > 1)
            || AdaptiveContentRegions.usesGroupedShelves(in: regions.viewport.size) {
            let panes = direction == .rightToLeft ? Array(regions.viewportPanes.reversed()) : regions.viewportPanes
            let columns = panes.map {
                AdaptiveContentRegions.columns(in: $0.width, cardWidth: cardSize.width(in: nil), spacing: columnSpacing)
            }
            Group(subviews: content()) { cards in
                let pages = AdaptiveContentRegions.shelfPages(count: cards.count, columns: columns)
                DashboardRegionRow(panes: panes, width: regions.viewport.width) {
                    ForEach(panes.indices, id: \.self) { pane in
                        paneShelf(cards: cards, pages: pages, pane: pane,
                                  columns: columns[pane], width: panes[pane].width)
                    }
                }
                .uniformWorkCardHeights()
                .environment(\.carouselCardAvailableWidth, max(0, (panes.map(\.width).min() ?? 32) - 32))
                .onChange(of: pages.count) { _, count in
                    visiblePage = count > 0 ? min(visiblePage ?? 0, count - 1) : nil
                }
            }
        } else {
            compactShelf
        }
        #else
        compactShelf
        #endif
    }

    private var compactShelf: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: compactSpacing) { content() }
                .uniformWorkCardHeights()
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        }
        .horizontalScrollViewport(preservesShadows: true, cardGutter: 16)
    }

    #if os(iOS)
    private func paneShelf(
        cards: SubviewsCollection, pages: [[[Int]]], pane: Int, columns: Int, width: CGFloat
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(pages.indices, id: \.self) { page in
                    CarouselCardGrid(
                        columnCount: columns,
                        containerWidth: max(0, width - 32),
                        columnSpacing: columnSpacing,
                        cardWidth: baseCardWidth
                    ) {
                        ForEach(pages[page][pane], id: \.self) { index in
                            cards[index]
                                .accessibilitySortPriority(Double(cards.count - index))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .frame(width: width, alignment: .leading)
                    .id(page)
                }
            }
            .scrollTargetLayout()
        }
        .horizontalScrollViewport(preservesShadows: true, cardGutter: 16)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $visiblePage, anchor: .leading)
        .environment(\.carouselCardAvailableWidth, max(0, width - 32))
    }
    #endif
}
