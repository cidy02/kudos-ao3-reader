import SwiftUI

extension EnvironmentValues {
    /// Card space after the host's safe area and content gutters, not the screen.
    @Entry var carouselCardAvailableWidth: CGFloat?
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
    @ViewBuilder var content: () -> Content
    @State private var availableWidth: CGFloat?
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
        LazyVGrid(
            columns: columnCount.map { count in
                Array(repeating: GridItem(.fixed(minimum), spacing: columnSpacing), count: count)
            } ?? CarouselCardMetrics.adaptiveCardColumns(minimum: minimum, spacing: columnSpacing),
            alignment: columnCount == nil ? .center : .leading,
            spacing: CarouselCardMetrics.compactGridSpacing
        ) {
            content()
        }
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
