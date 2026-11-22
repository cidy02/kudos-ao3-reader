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

    @Test func inspectorSplitMatchesPhysicalTrailingPaneForBothDirectionsAndRailSides() throws {
        // Asymmetric 951 pt window, fold at 455.5...495.5, 84 pt rail.
        var railRight = ReaderHostRegions(verticalBar: .right)
        railRight.fold = CGRect(x: 455.5, y: 0, width: 40, height: 669)
        let openRight = DuoLayoutSignal(regions: railRight, width: 951, isVerticalFoldActive: false)
        let bookRight = DuoLayoutSignal(regions: railRight, width: 951, isVerticalFoldActive: true)

        // LTR + rail right: inspector on physical right (371.5), clearance 40 Open / 56 Book.
        let ltrRightOpen = try #require(openRight.inspectorSplit(rightToLeft: false))
        #expect(ltrRightOpen.inspectorWidth == 371.5)
        #expect(ltrRightOpen.leadingFoldClearance == 40)
        #expect(ltrRightOpen.leadingPaneTrailingReserve == 411.5)
        let ltrRightBook = try #require(bookRight.inspectorSplit(rightToLeft: false))
        #expect(ltrRightBook.inspectorWidth == 371.5)
        #expect(ltrRightBook.leadingFoldClearance == 56)
        #expect(ltrRightBook.leadingPaneTrailingReserve == 427.5)

        // RTL + rail right: logical trailing inspector is physical left (0...455.5 = 455.5),
        // clearance 40 Open / 56 Book so results start at x=495.5 / 511.5 (never before the fold).
        let rtlRightOpen = try #require(openRight.inspectorSplit(rightToLeft: true))
        #expect(rtlRightOpen.inspectorWidth == 455.5)
        #expect(rtlRightOpen.leadingFoldClearance == 40)
        #expect(rtlRightOpen.leadingPaneTrailingReserve == 495.5)
        let rtlRightBook = try #require(bookRight.inspectorSplit(rightToLeft: true))
        #expect(rtlRightBook.inspectorWidth == 455.5)
        #expect(rtlRightBook.leadingFoldClearance == 56)
        #expect(rtlRightBook.leadingPaneTrailingReserve == 511.5)

        // 180° rotated: rail on physical left (0...84).
        var railLeft = ReaderHostRegions(verticalBar: .left)
        railLeft.fold = CGRect(x: 455.5, y: 0, width: 40, height: 669)
        let openLeft = DuoLayoutSignal(regions: railLeft, width: 951, isVerticalFoldActive: false)

        // LTR + rail left: inspector on physical right (495.5...951 = 455.5).
        let ltrLeftOpen = try #require(openLeft.inspectorSplit(rightToLeft: false))
        #expect(ltrLeftOpen.inspectorWidth == 455.5)
        #expect(ltrLeftOpen.leadingFoldClearance == 40)
        #expect(ltrLeftOpen.leadingPaneTrailingReserve == 495.5)

        // RTL + rail left: inspector on physical left between rail and fold (84...455.5 = 371.5).
        let rtlLeftOpen = try #require(openLeft.inspectorSplit(rightToLeft: true))
        #expect(rtlLeftOpen.inspectorWidth == 371.5)
        #expect(rtlLeftOpen.leadingFoldClearance == 40)
        #expect(rtlLeftOpen.leadingPaneTrailingReserve == 411.5)
    }

    @Test func searchBulkSelectionKeepsLeadingPaneBoundWithoutInspector() {
        var regions = ReaderHostRegions(verticalBar: .right)
        regions.fold = CGRect(x: 455.5, y: 0, width: 40, height: 669)
        let open = DuoLayoutSignal(regions: regions, width: 951, isVerticalFoldActive: false)
        let book = DuoLayoutSignal(regions: regions, width: 951, isVerticalFoldActive: true)

        // 867 pt viewport minus trailing reserve leaves exact leading pane width (455.5 Open / 439.5 Book LTR).
        #expect(867 - open.searchLeadingFoldClearance(rightToLeft: false, inspectorVisible: false) == 455.5)
        #expect(867 - book.searchLeadingFoldClearance(rightToLeft: false, inspectorVisible: false) == 439.5)
        // RTL leading pane is physical right (371.5 Open / 355.5 Book).
        #expect(867 - open.searchLeadingFoldClearance(rightToLeft: true, inspectorVisible: false) == 371.5)
        #expect(867 - book.searchLeadingFoldClearance(rightToLeft: true, inspectorVisible: false) == 355.5)

        // Ordinary screens keep zero inset.
        #expect(DuoLayoutSignal().searchLeadingFoldClearance(rightToLeft: false, inspectorVisible: false) == 0)
    }

    @Test func libraryFilterFallbackClearsTheFoldInOpenAndBookForBothDirections() {
        var railRight = ReaderHostRegions(verticalBar: .right)
        railRight.fold = CGRect(x: 455.5, y: 0, width: 40, height: 669)
        let openRight = DuoLayoutSignal(regions: railRight, width: 951, isVerticalFoldActive: false)
        let bookRight = DuoLayoutSignal(regions: railRight, width: 951, isVerticalFoldActive: true)

        // Open Duo LTR with Library Filters open: host is 0...495.5, needs 40 pt trailing clearance -> 455.5.
        #expect(openRight.singlePaneTrailingFoldClearance(
            viewportWidth: 495.5, viewportMinX: 0, rightToLeft: false
        ) == 40)
        // Open Duo RTL with Library Filters open (inspector 0...455.5): host is 455.5...867 (411.5), needs 40 pt.
        #expect(openRight.singlePaneTrailingFoldClearance(
            viewportWidth: 411.5, viewportMinX: 455.5, rightToLeft: true
        ) == 40)
        // Book Duo LTR where DashboardRegionHost already excluded the active 40 pt division (viewport 0...455.5):
        // needs only the 16 pt Book inset, never double-subtracting 56 pt.
        #expect(bookRight.singlePaneTrailingFoldClearance(
            viewportWidth: 455.5,
            viewportMinX: 0,
            rightToLeft: false,
            activeDivision: CGRect(x: 455.5, y: 0, width: 40, height: 669)
        ) == 16)
        // Book Duo RTL where viewport starts after the active division (495.5...867 = 371.5, local division -40...0):
        // needs only the 16 pt Book inset.
        #expect(bookRight.singlePaneTrailingFoldClearance(
            viewportWidth: 371.5,
            viewportMinX: 495.5,
            rightToLeft: true,
            activeDivision: CGRect(x: -40, y: 0, width: 40, height: 669)
        ) == 16)
        // Full split viewport returns 0 (two-pane split applies instead).
        #expect(openRight.singlePaneTrailingFoldClearance(
            viewportWidth: 867, viewportMinX: 0, rightToLeft: false
        ) == 0)
        // Ordinary phone returns 0.
        #expect(DuoLayoutSignal().singlePaneTrailingFoldClearance(
            viewportWidth: 393, viewportMinX: 0, rightToLeft: false
        ) == 0)
    }

    @Test func scrollAnchorsSurviveOpenBookAndFallbackLayoutSwaps() {
        var state = DuoScrollAnchorState()
        // Initial mount never forces a scroll.
        let initial = state.beginTransition(to: .openSplit)
        #expect(initial.shared == nil && initial.leading == nil && initial.trailing == nil)

        // Open flat: leading pane ends at y=520; trailing pane continues to Subscriptions (546...780).
        state.recordFrame(DuoScrollAnchorRect(minY: 0, maxY: 20), for: "stats", pane: .leading)
        state.recordFrame(DuoScrollAnchorRect(minY: 46, maxY: 280), for: "resume", pane: .leading)
        state.recordFrame(DuoScrollAnchorRect(minY: 306, maxY: 520), for: "readingNow", pane: .leading)
        state.recordFrame(DuoScrollAnchorRect(minY: 0, maxY: 220), for: "chapters", pane: .trailing)
        state.recordFrame(DuoScrollAnchorRect(minY: 246, maxY: 520), for: "queues", pane: .trailing)
        state.recordFrame(DuoScrollAnchorRect(minY: 546, maxY: 780), for: "subscriptions", pane: .trailing)

        state.recordScroll(fromTop: 540, previousFromTop: 0, pane: .shared, mode: .openSplit)
        #expect(state.trailingAnchor == "subscriptions")
        #expect(state.leadingAnchor == "readingNow")
        #expect(state.sharedAnchor == "subscriptions")

        // Fold Open -> Book: each pane restores its own section.
        let toBook = state.beginTransition(to: .bookSplit)
        #expect(toBook.leading == "readingNow")
        #expect(toBook.trailing == "subscriptions")

        // In Book pose, register new frames and scroll trailing pane to "queues", then return to Open.
        state.recordFrame(DuoScrollAnchorRect(minY: 0, maxY: 220), for: "chapters", pane: .trailing)
        state.recordFrame(DuoScrollAnchorRect(minY: 246, maxY: 520), for: "queues", pane: .trailing)
        state.recordFrame(DuoScrollAnchorRect(minY: 0, maxY: 280), for: "resume", pane: .leading)
        state.recordFrame(DuoScrollAnchorRect(minY: 306, maxY: 520), for: "collections", pane: .leading)

        // Zero-delta mount callback does not overwrite anchors or interaction order.
        state.recordScroll(fromTop: 0, previousFromTop: 0, pane: .leading, mode: .bookSplit)
        state.recordScroll(fromTop: 250, previousFromTop: 540, pane: .trailing, mode: .bookSplit)
        #expect(state.lastInteractedBookPane == .trailing)

        let bookToFallback = state.beginTransition(to: .fallback)
        #expect(bookToFallback.shared == "queues")

        // Browse/Library fallback -> Open split preserves the visible section/card.
        state.recordFrame(DuoScrollAnchorRect(minY: 0, maxY: 100), for: "jumpBackIn", pane: .shared)
        state.recordFrame(DuoScrollAnchorRect(minY: 420, maxY: 640), for: "category:Movies", pane: .shared)
        state.recordScroll(fromTop: 430, previousFromTop: 0, pane: .shared, mode: .fallback)
        let fallbackToOpen = state.beginTransition(to: .openSplit)
        #expect(fallbackToOpen.shared == "category:Movies")
    }

    @Test func browseJumpBackInChipsCapToFoldPaneAtAccessibilitySizesOnly() {
        #expect(MediaBrowserView.jumpBackInChipMaxWidth(isAccessibilitySize: false, foldPaneWidth: nil) == 260)
        #expect(MediaBrowserView.jumpBackInChipMaxWidth(isAccessibilitySize: false, foldPaneWidth: 455.5) == 260)
        #expect(MediaBrowserView.jumpBackInChipMaxWidth(isAccessibilitySize: true, foldPaneWidth: nil) == nil)
        #expect(MediaBrowserView.jumpBackInChipMaxWidth(isAccessibilitySize: true, foldPaneWidth: 455.5) == 439.5)
        #expect(MediaBrowserView.jumpBackInChipMaxWidth(isAccessibilitySize: true, foldPaneWidth: 439.5) == 423.5)
    }

    @Test func navigationSignalsDistinguishEveryDuoPoseFromOrdinaryScreens() {
        let phone = DuoLayoutSignal()
        #expect(!phone.isMeasured)
        #expect(!phone.isDuo)
        #expect(!phone.usesSingleRailActionGroup)
        #expect(!phone.hidesHomeSecondaryToolbarActions)
        #expect(!phone.separatesSearchTab)

        var measuredPhone = DuoLayoutSignal()
        measuredPhone.width = 393
        #expect(measuredPhone.isMeasured)
        #expect(!measuredPhone.isDuo)
        #expect(!measuredPhone.usesSingleRailActionGroup)
        #expect(!measuredPhone.hidesHomeSecondaryToolbarActions)
        #expect(!measuredPhone.separatesSearchTab)

        let cover = DuoLayoutSignal(regions: ReaderHostRegions(verticalBar: .right), width: 466)
        #expect(cover.isMeasured)
        #expect(cover.isDuo)
        #expect(cover.usesSingleRailActionGroup)
        #expect(cover.hidesHomeSecondaryToolbarActions)
        #expect(cover.separatesSearchTab)

        var openRegions = ReaderHostRegions(verticalBar: .right)
        openRegions.fold = CGRect(x: 455.5, y: 0, width: 40, height: 669)
        let open = DuoLayoutSignal(regions: openRegions, width: 951, isVerticalFoldActive: false)
        let book = DuoLayoutSignal(regions: openRegions, width: 951, isVerticalFoldActive: true)
        for pose in [open, book] {
            #expect(pose.isDuo)
            #expect(pose.usesSingleRailActionGroup)
            #expect(pose.hidesHomeSecondaryToolbarActions)
            #expect(pose.separatesSearchTab)
        }

        var uprightRegions = ReaderHostRegions(verticalBar: .none)
        uprightRegions.fold = CGRect(x: 0, y: 455.5, width: 669, height: 40)
        let upright = DuoLayoutSignal(regions: uprightRegions, width: 669)
        #expect(upright.isDuo)
        #expect(!upright.usesSingleRailActionGroup)
        #expect(upright.hidesHomeSecondaryToolbarActions)
        #expect(upright.separatesSearchTab)
    }

    @Test func accountPresentationMatchesBoardAcrossEveryPoseAndDirection() throws {
        // Unmeasured default never flashes a modal sheet before DuoLayoutProbe measures.
        let unmeasured = DuoLayoutSignal()
        #expect(unmeasured.accountPresentation() == .sheet)
        #expect(!unmeasured.presentsAccountAsSheet(isPresentingAccount: true, onHome: true))

        // Measured ordinary iPhone/iPad presents standard sheet.
        var phone = DuoLayoutSignal()
        phone.width = 393
        #expect(phone.accountPresentation() == .sheet)
        #expect(phone.presentsAccountAsSheet(isPresentingAccount: true, onHome: true))
        #expect(!phone.presentsAccountAsSheet(isPresentingAccount: false, onHome: true))

        // Duo Cover (vertical rail, no vertical fold): standard sheet.
        let cover = DuoLayoutSignal(regions: ReaderHostRegions(verticalBar: .right), width: 466)
        #expect(cover.accountPresentation() == .sheet)
        #expect(cover.presentsAccountAsSheet(isPresentingAccount: true, onHome: true))

        // Duo Upright portrait (horizontal fold, no rail): form sheet (~541 pt).
        var uprightRegions = ReaderHostRegions(verticalBar: .none)
        uprightRegions.fold = CGRect(x: 0, y: 455.5, width: 669, height: 40)
        let upright = DuoLayoutSignal(regions: uprightRegions, width: 669)
        #expect(upright.accountPresentation() == .formSheet)
        #expect(upright.presentsAccountAsSheet(isPresentingAccount: true, onHome: true))

        // Duo Open & Book landscape: trailing inspector from fold centre to screen edge.
        var railRight = ReaderHostRegions(verticalBar: .right)
        railRight.fold = CGRect(x: 455.5, y: 0, width: 40, height: 669)
        let openRight = DuoLayoutSignal(regions: railRight, width: 951, isVerticalFoldActive: false)
        let bookRight = DuoLayoutSignal(regions: railRight, width: 951, isVerticalFoldActive: true)

        let ltrOpen = try #require(openRight.accountPresentation(rightToLeft: false).inspectorGeometry)
        #expect(ltrOpen.foldHalfWidth == 391.5)
        #expect(ltrOpen.trailingRailReserve == DuoLayoutSignal.railReserve)
        #expect(ltrOpen.fullFoldHalfWidth == 475.5)
        #expect(!openRight.presentsAccountAsSheet(isPresentingAccount: true, onHome: true))
        #expect(openRight.presentsAccountAsSheet(isPresentingAccount: true, onHome: false))

        let rtlOpen = try #require(openRight.accountPresentation(rightToLeft: true).inspectorGeometry)
        #expect(rtlOpen.foldHalfWidth == 475.5)
        #expect(rtlOpen.trailingRailReserve == 0)
        #expect(rtlOpen.fullFoldHalfWidth == 475.5)

        let ltrBook = try #require(bookRight.accountPresentation(rightToLeft: false).inspectorGeometry)
        #expect(ltrBook.fullFoldHalfWidth == 475.5)
        #expect(ltrBook.leadingFoldClearance == 56)

        // 180° left-rail landscape: LTR has no rail on the trailing pane; RTL does.
        var railLeft = ReaderHostRegions(verticalBar: .left)
        railLeft.fold = CGRect(x: 455.5, y: 0, width: 40, height: 669)
        let openLeft = DuoLayoutSignal(regions: railLeft, width: 951, isVerticalFoldActive: false)
        let ltrLeft = try #require(openLeft.accountPresentation(rightToLeft: false).inspectorGeometry)
        #expect(ltrLeft.foldHalfWidth == 475.5)
        #expect(ltrLeft.trailingRailReserve == 0)
        #expect(ltrLeft.fullFoldHalfWidth == 475.5)
        let rtlLeft = try #require(openLeft.accountPresentation(rightToLeft: true).inspectorGeometry)
        #expect(rtlLeft.foldHalfWidth == 391.5)
        #expect(rtlLeft.trailingRailReserve == DuoLayoutSignal.railReserve)
        #expect(rtlLeft.fullFoldHalfWidth == 475.5)
    }
}
#endif
