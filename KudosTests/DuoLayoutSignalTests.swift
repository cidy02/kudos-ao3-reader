import CoreGraphics
import Foundation
import Testing
@testable import Kudos

#if os(iOS)
@MainActor
struct DuoLayoutSignalTests {
    @Test func defaultSignalIsAnOrdinaryScreen() {
        let signal = DuoLayoutSignal()
        #expect(!signal.hasVerticalBar)
        #expect(!signal.isUprightFold)
        #expect(signal.inspectorWidth == nil)
    }

    @Test func flatLandscapeIsARailWithAVerticalFold() {
        var regions = ReaderHostRegions(verticalBar: .right)
        regions.fold = CGRect(x: 455, y: 0, width: 40, height: 669)
        let signal = DuoLayoutSignal(regions: regions, width: 951)
        #expect(signal.hasVerticalBar)
        #expect(!signal.isUprightFold)
        #expect(signal.inspectorWidth == 951 - 495 - DuoLayoutSignal.railReserve)
    }

    @Test func uprightIsAFoldWithNoRail() {
        var regions = ReaderHostRegions(verticalBar: .none)
        regions.fold = CGRect(x: 0, y: 470, width: 669, height: 10)
        #expect(DuoLayoutSignal(regions: regions, width: 669).isUprightFold)
    }

    @Test func appAndReaderAgreeOnEveryBarAndFoldInput() {
        let folds: [CGRect?] = [nil, CGRect(x: 455, y: 0, width: 40, height: 669), CGRect(x: 0, y: 470, width: 669, height: 10)]
        for bar in [ReaderVerticalBar.none, .left, .right] {
            for fold in folds {
                var regions = ReaderHostRegions(verticalBar: bar)
                regions.fold = fold
                let signal = DuoLayoutSignal(regions: regions, width: 951)
                let layout = ReaderChromeLayout.resolve(regions)
                #expect(signal.isUprightFold == (layout == .foldTopBar))
                if case .rail = layout { #expect(signal.hasVerticalBar) } else { #expect(!signal.hasVerticalBar) }
            }
        }
    }

    @Test func narrowPaneKeepsTheDefaultInspectorWidth() {
        var regions = ReaderHostRegions(verticalBar: .right)
        regions.fold = CGRect(x: 300, y: 0, width: 40, height: 400)
        #expect(DuoLayoutSignal(regions: regions, width: 480).inspectorWidth == nil)
    }

    @Test func categoryGridGoesTwoAcrossWhenCardsCannotHoldTheirLabel() {
        #expect(LibraryFilterPanel.categoryColumnCount(gridWidth: 358, labelWidth: 38) == 3)
        #expect(LibraryFilterPanel.categoryColumnCount(gridWidth: 300, labelWidth: 38) == 2)
        // Larger text needs wider cards for the same grid.
        #expect(LibraryFilterPanel.categoryColumnCount(gridWidth: 358, labelWidth: 60) == 2)
    }

    @Test func openFoldPanesKeepFortyPointClearanceAcrossTheFold() throws {
        var regions = ReaderHostRegions(verticalBar: .right)
        regions.fold = CGRect(x: 455.5, y: 0, width: 40, height: 669)
        let signal = DuoLayoutSignal(regions: regions, width: 951, isVerticalFoldActive: false)
        let panes = try #require(signal.foldPanes(viewportWidth: 867, viewportMinX: 0, viewportHeight: 669))
        #expect(!panes.isBookPose)
        #expect(panes.left == CGRect(x: 0, y: 0, width: 455.5, height: 669))
        #expect(panes.right == CGRect(x: 495.5, y: 0, width: 371.5, height: 669))
        #expect(panes.foldClearance == 40)
        #expect(signal.isFoldSplitLandscape)
        #expect(signal.searchLeadingFoldClearance == 40)
    }

    @Test func zeroWidthCreaseStillKeepsFortyPointOpenClearance() throws {
        var regions = ReaderHostRegions(verticalBar: .right)
        regions.fold = CGRect(x: 475.5, y: 0, width: 0, height: 669)
        let signal = DuoLayoutSignal(regions: regions, width: 951, isVerticalFoldActive: false)
        let panes = try #require(signal.foldPanes(viewportWidth: 867, viewportMinX: 0, viewportHeight: 669))
        #expect(!panes.isBookPose)
        #expect(panes.left.maxX == 455.5)
        #expect(panes.right.minX == 495.5)
        #expect(panes.foldClearance == 40)
    }

    @Test func bookPoseInsetsEachPaneSixteenPointsFromTheFoldShadow() throws {
        var regions = ReaderHostRegions(verticalBar: .right)
        regions.fold = CGRect(x: 455.5, y: 0, width: 40, height: 669)
        let signal = DuoLayoutSignal(regions: regions, width: 951, isVerticalFoldActive: true)
        let panes = try #require(signal.foldPanes(viewportWidth: 867, viewportMinX: 0, viewportHeight: 669))
        #expect(panes.isBookPose)
        #expect(panes.left == CGRect(x: 0, y: 0, width: 439.5, height: 669))
        #expect(panes.right == CGRect(x: 511.5, y: 0, width: 355.5, height: 669))
        #expect(panes.foldClearance == 72)
        #expect(signal.searchLeadingFoldClearance == 56)
    }

    @Test func rotatedLeftBarTranslatesWindowFoldIntoViewportCoordinates() throws {
        var regions = ReaderHostRegions(verticalBar: .left)
        regions.fold = CGRect(x: 455.5, y: 0, width: 40, height: 669)
        let signal = DuoLayoutSignal(regions: regions, width: 951, isVerticalFoldActive: false)
        let panes = try #require(signal.foldPanes(viewportWidth: 867, viewportMinX: 84, viewportHeight: 669))
        #expect(panes.left.width == 371.5)
        #expect(panes.right.minX == 411.5)
        #expect(panes.right.width == 455.5)
        #expect(signal.inspectorWidth == 951 - 495.5)
    }

    @Test func foldPanesCollapseWhenInspectorNarrowsHostOrWithoutVerticalFold() {
        var openRegions = ReaderHostRegions(verticalBar: .right)
        openRegions.fold = CGRect(x: 455.5, y: 0, width: 40, height: 669)
        let open = DuoLayoutSignal(regions: openRegions, width: 951)
        // Library with filter inspector open (~495 pt left host) drops back to one column.
        #expect(open.foldPanes(viewportWidth: 495, viewportMinX: 0, viewportHeight: 669) == nil)

        // Cover (rail, no fold), Upright (horizontal fold, no rail), and iPhone/iPad (default) never split.
        let cover = DuoLayoutSignal(regions: ReaderHostRegions(verticalBar: .right), width: 466)
        #expect(cover.foldPanes(viewportWidth: 382, viewportHeight: 678) == nil)
        #expect(!cover.isFoldSplitLandscape)

        var uprightRegions = ReaderHostRegions(verticalBar: .none)
        uprightRegions.fold = CGRect(x: 0, y: 455.5, width: 669, height: 40)
        let upright = DuoLayoutSignal(regions: uprightRegions, width: 669)
        #expect(upright.foldPanes(viewportWidth: 669, viewportHeight: 951) == nil)
        #expect(!upright.isFoldSplitLandscape)

        let phone = DuoLayoutSignal()
        #expect(phone.foldPanes(viewportWidth: 393, viewportHeight: 852) == nil)
        #expect(!phone.isFoldSplitLandscape)
    }

    @Test func libraryDuoPaneSplitMatchesBoardAndBalancesCustomArrangements() {
        let defaultSplit = LibraryPageArrangement.default.duoPaneSections()
        #expect(defaultSplit.leading.map(\.id) == [.favourites, .collections])
        #expect(defaultSplit.trailing.map(\.id) == [.downloaded])

        let oneSection = LibraryPageArrangement(
            sections: [LibraryPageSection(id: .favourites, style: .carousel)],
            buttons: [.collections, .downloaded]
        ).duoPaneSections()
        #expect(oneSection.leading.map(\.id) == [.favourites])
        #expect(oneSection.trailing.isEmpty)

        let fiveSections = LibraryPageArrangement(
            sections: [
                LibraryPageSection(id: .favourites, style: .carousel),
                LibraryPageSection(id: .collections, style: .carousel),
                LibraryPageSection(id: .downloaded, style: .carousel),
                LibraryPageSection(id: .readingNow, style: .carousel),
                LibraryPageSection(id: .finished, style: .list)
            ],
            buttons: [.wantToRead]
        ).duoPaneSections()
        #expect(fiveSections.leading.count == 3)
        #expect(fiveSections.trailing.count == 2)
    }

    @Test func browseCategorySpansAlignGutterToTheFoldAndKeepAX5SingleColumn() throws {
        var regions = ReaderHostRegions(verticalBar: .right)
        regions.fold = CGRect(x: 455.5, y: 0, width: 40, height: 669)
        let open = DuoLayoutSignal(regions: regions, width: 951)
        let openPanes = try #require(open.foldPanes(viewportWidth: 867, viewportHeight: 669))

        let ltrSpans = MediaBrowserView.duoCategoryColumnSpans(
            panes: openPanes, gutter: 16, isAccessibilitySize: false, rightToLeft: false
        )
        #expect(ltrSpans.count == 2)
        #expect(ltrSpans[0] == MasonryLayout.ColumnSpan(minX: 0, width: 439.5))
        #expect(ltrSpans[1] == MasonryLayout.ColumnSpan(minX: 479.5, width: 355.5))
        // Window x: left 16...455.5, right 495.5...851 -> exact 40 pt clear at 455.5...495.5.
        #expect(ltrSpans[1].minX - (ltrSpans[0].minX + ltrSpans[0].width) == 40)

        let axSpans = MediaBrowserView.duoCategoryColumnSpans(
            panes: openPanes, gutter: 16, isAccessibilitySize: true, rightToLeft: false
        )
        #expect(axSpans == [MasonryLayout.ColumnSpan(minX: 0, width: 439.5)])

        let book = DuoLayoutSignal(regions: regions, width: 951, isVerticalFoldActive: true)
        let bookPanes = try #require(book.foldPanes(viewportWidth: 867, viewportHeight: 669))
        let bookSpans = MediaBrowserView.duoCategoryColumnSpans(
            panes: bookPanes, gutter: 16, isAccessibilitySize: false, rightToLeft: false
        )
        #expect(bookSpans[0] == MasonryLayout.ColumnSpan(minX: 0, width: 423.5))
        #expect(bookSpans[1] == MasonryLayout.ColumnSpan(minX: 495.5, width: 339.5))
        #expect(bookSpans[1].minX - (bookSpans[0].minX + bookSpans[0].width) == 72)
    }

    @Test func horizontalScrollClipRectTrimsOnlyTheFoldFacingEdge() {
        let viewport = CGRect(x: 0, y: 0, width: 471.5, height: 220)
        let leadingPane = HorizontalScrollViewportMetrics.clipRect(
            viewportBounds: viewport, contentHeight: 220, preservesShadows: true,
            trimLeading: 0, trimTrailing: 16, rightToLeft: false
        )
        #expect(leadingPane.minX == 0)
        #expect(leadingPane.width == 455.5)

        let trailingPane = HorizontalScrollViewportMetrics.clipRect(
            viewportBounds: CGRect(x: 0, y: 0, width: 387.5, height: 220),
            contentHeight: 220, preservesShadows: true,
            trimLeading: 16, trimTrailing: 0, rightToLeft: false
        )
        #expect(trailingPane.minX == 16)
        #expect(trailingPane.width == 371.5)

        let rtlLeading = HorizontalScrollViewportMetrics.clipRect(
            viewportBounds: viewport, contentHeight: 220, preservesShadows: false,
            trimLeading: 0, trimTrailing: 16, rightToLeft: true
        )
        #expect(rtlLeading.minX == 16)
        #expect(rtlLeading.width == 455.5)
    }
}
#endif
