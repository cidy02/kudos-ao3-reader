import SwiftUI
import Testing
@testable import Kudos

@MainActor
@Suite
struct CarouselCardSizingTests {
    @Test(arguments: [CGFloat(343), 361, 434, 800])
    func ordinaryCardsKeepTheirExistingSize(availableWidth: CGFloat) {
        let ratio = CarouselCardMetrics.clampRatio(
            scaledWidth: CarouselCardMetrics.width, availableWidth: availableWidth
        )
        #expect(ratio == 1)
        // Shelf covers are 120 pt (I-14). An unclamped card keeps that width.
        #expect(CarouselCardMetrics.width == 120)
        #expect(CarouselCardMetrics.width * ratio == CarouselCardMetrics.width)
        #expect(CarouselCardMetrics.height * ratio == CarouselCardMetrics.height)
    }

    @Test(arguments: [CGFloat(180), 278, 343, 434])
    func largeCardsFitTheGivenContainer(availableWidth: CGFloat) {
        let scaledWidth: CGFloat = 720
        let scaledHeight = scaledWidth * CGFloat(2).squareRoot()
        let ratio = CarouselCardMetrics.clampRatio(scaledWidth: scaledWidth, availableWidth: availableWidth)
        let width = scaledWidth * ratio
        let height = scaledHeight * ratio
        #expect(abs(width - availableWidth) < 0.000_001)
        #expect(abs(height / width - CGFloat(2).squareRoot()) < 0.000_001)
    }

    @Test func aNarrowContainerCanClampEvenAnUnscaledCard() {
        let ratio = CarouselCardMetrics.clampRatio(scaledWidth: 164, availableWidth: 120)
        #expect(abs(164 * ratio - 120) < 0.000_001)
    }

    @Test func wideningTheContainerRestoresTheScaledSizeWithoutEnlargingIt() {
        let narrow = CarouselCardMetrics.clampRatio(scaledWidth: 320, availableWidth: 210)
        let wide = CarouselCardMetrics.clampRatio(scaledWidth: 320, availableWidth: 600)
        #expect(abs(320 * narrow - 210) < 0.000_001)
        #expect(wide == 1)
    }

    @Test(arguments: [CGFloat(0), -20])
    func noSpaceNeverProducesANegativeSize(availableWidth: CGFloat) {
        #expect(CarouselCardMetrics.clampRatio(scaledWidth: 164, availableWidth: availableWidth) == 0)
    }

    #if os(iOS)
    @Test func theSizeHelperReadsItsContainerWidth() throws {
        let natural = try renderedSize(in: 10_000)
        for width in [CGFloat(120), 278, 343] {
            let actual = try renderedSize(in: width)
            #expect(abs(actual.width - min(natural.width, width)) < 0.000_001)
            #expect(abs(actual.height / actual.width - natural.height / natural.width) < 0.000_001)
        }
    }

    private func renderedSize(in width: CGFloat) throws -> CGSize {
        var received: CGSize?
        let probe = CarouselSizeProbe { received = $0 }
            .dynamicTypeSize(.accessibility5)
            .environment(\.carouselCardAvailableWidth, width)
        let renderer = ImageRenderer(content: probe)
        _ = renderer.cgImage
        return try #require(received)
    }
    #endif

    @Test func onlyThe120PointCoverGridStretches() {
        #expect(CarouselCardMetrics.stretchesToFill(baseWidth: CarouselCardMetrics.width))
        #expect(!CarouselCardMetrics.stretchesToFill(baseWidth: CarouselCardMetrics.stackWidth))
        // A stack that inherits a cover column keeps its own width.
        #expect(CarouselCardMetrics.resolvedCardWidth(
            designWidth: CarouselCardMetrics.stackWidth, scaledWidth: 150, gridCardWidth: 114
        ) == 150)
        #expect(CarouselCardMetrics.resolvedCardWidth(
            designWidth: CarouselCardMetrics.width, scaledWidth: 120, gridCardWidth: 112
        ) == 112)
        #expect(CarouselCardMetrics.resolvedCardWidth(
            designWidth: CarouselCardMetrics.width, scaledWidth: 120, gridCardWidth: nil
        ) == 120)
    }

    @Test func gridsFitAsManyColumnsAs112PointsAllowAndStretch() {
        let spacing = CarouselCardMetrics.compactGridColumnSpacing
        #expect(CarouselCardMetrics.gridMinimumWidth == 112)
        // Board 01: three columns land on the 112 pt floor.
        #expect(CarouselCardMetrics.gridColumnCount(
            availableWidth: 360, minimum: 112, spacing: spacing
        ) == 3)
        #expect(CarouselCardMetrics.gridCardWidth(
            availableWidth: 360, columns: 3, spacing: spacing
        ) == 112)
        // A 390 pt phone has 358 pt of content. Three exact 112 pt columns need
        // 360; the 2 pt tolerance keeps the row 3-up.
        #expect(CarouselCardMetrics.gridColumnCount(
            availableWidth: 358, minimum: 112, spacing: spacing
        ) == 3)
        let filled = CarouselCardMetrics.gridCardWidth(
            availableWidth: 358, columns: 3, spacing: spacing
        )
        #expect(abs(filled - (CGFloat(358) - 2 * spacing) / 3) < 0.001)
        // Cover aspect stays width × 1.42 whatever the column becomes.
        let stretched = CarouselCardMetrics.gridCardWidth(
            availableWidth: 358, columns: 2, spacing: spacing
        )
        #expect(abs(stretched * 1.42 - stretched / CarouselCardMetrics.width * CarouselCardMetrics.artHeight) < 0.001)
    }

    @Test func theClipUsesTheAlreadyUsableViewportWidth() {
        let viewport = CGRect(x: 0, y: 0, width: 380, height: 240)
        let clip = HorizontalScrollViewportMetrics.clipRect(
            viewportBounds: viewport, contentHeight: 240, preservesShadows: true
        )
        #expect(clip.minX == 0)
        #expect(clip.maxX == 380)
        #expect(clip.minY == -32)
        #expect(clip.maxY == 272)
    }

    @Test(arguments: [CGFloat(-16), 0, 164, 1000])
    func theClipFollowsTheViewportInMovingContent(offset: CGFloat) {
        let viewport = CGRect(x: offset, y: 0, width: 380, height: 240)
        let clip = HorizontalScrollViewportMetrics.clipRect(
            viewportBounds: viewport, contentHeight: 240, preservesShadows: false
        )
        #expect(clip == viewport)
    }
}

#if os(iOS)
private struct CarouselSizeProbe: View {
    var cardSize = ScaledCarouselCardSize()
    let report: (CGSize) -> Void

    var body: some View {
        report(CGSize(width: cardSize.width, height: cardSize.height))
        return Color.clear.frame(width: 1, height: 1)
    }
}
#endif
