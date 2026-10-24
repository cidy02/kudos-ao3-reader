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
            .environment(\.carouselCardAvailableWidth, availableWidth)
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
    @ViewBuilder var content: () -> Content
    @State private var availableWidth: CGFloat?
    private var cardSize = ScaledCarouselCardSize()

    init(uniformHeights: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.uniformHeights = uniformHeights
        self.content = content
    }

    var body: some View {
        #if os(iOS)
        grid(minimum: cardSize.width(in: availableWidth))
            .environment(\.carouselCardAvailableWidth, availableWidth)
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
            columns: CarouselCardMetrics.adaptiveCardColumns(minimum: minimum),
            spacing: CarouselCardMetrics.compactGridSpacing
        ) {
            content()
        }
    }
}
