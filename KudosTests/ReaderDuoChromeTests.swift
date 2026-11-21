import Foundation
import Testing

#if os(iOS)
import UIKit
@testable import Kudos
#endif

#if os(iOS)
/// T-562a: the Duo reader bars. Numbers are the Duo simulator's own (cover 466×678,
/// inner 951×669 / 669×951, an 84 pt vertical bar, the fold at x 455.5–495.5) and
/// the boards' (rail 64 pt, bar 503→865 open, 16→380 cover, 440 wide portrait).
@MainActor
struct ReaderDuoChromeTests {
    private static let innerFold = CGRect(x: 455.5, y: 0, width: 40, height: 669)

    @Test func layoutFollowsTheBarEdgeAndTheFoldNeverTheDevice() {
        #expect(ReaderChromeLayout.resolve(ReaderHostRegions()) == .standard)
        #expect(ReaderChromeLayout.resolve(ReaderHostRegions(verticalBar: .right)) == .rail(.right))
        #expect(ReaderChromeLayout.resolve(
            ReaderHostRegions(verticalBar: .right, fold: Self.innerFold)
        ) == .rail(.right))
        #expect(ReaderChromeLayout.resolve(
            ReaderHostRegions(fold: CGRect(x: 0, y: 455.5, width: 669, height: 40))
        ) == .foldTopBar)
    }

    @Test func openLandscapePutsTheBarOnTheRightPageClearOfTheFold() {
        let regions = ReaderHostRegions(verticalBar: .right, barStatusBottom: 124, fold: Self.innerFold)
        let placement = ReaderDuoChromePlacement.resolve(
            layout: .rail(.right), size: CGSize(width: 951, height: 669),
            safe: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84), regions: regions
        )
        #expect(placement.railCenterInset == 42)
        #expect(placement.railTop == 134)
        #expect(placement.barLeft == 503.5)
        #expect(placement.barRight == 86)
    }

    @Test func coverBarRunsFromTheEdgeToTheRail() {
        let regions = ReaderHostRegions(verticalBar: .right, barStatusBottom: 174)
        let placement = ReaderDuoChromePlacement.resolve(
            layout: .rail(.right), size: CGSize(width: 466, height: 678),
            safe: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84), regions: regions
        )
        #expect(placement.barLeft == 16)
        #expect(466 - placement.barRight == 380)
        #expect(placement.railTop == 184)
    }

    @Test func aLeadingBarMirrorsTheRail() {
        let regions = ReaderHostRegions(verticalBar: .left, barStatusBottom: 124, fold: Self.innerFold)
        let placement = ReaderDuoChromePlacement.resolve(
            layout: .rail(.left), size: CGSize(width: 951, height: 669),
            safe: UIEdgeInsets(top: 0, left: 84, bottom: 34, right: 0), regions: regions
        )
        #expect(placement.barLeft == 86)
        #expect(placement.barRight == 951 - 455.5 + 8)
    }

    @Test func withoutAStatusBlockTheRailStartsBelowTheSafeTop() {
        let placement = ReaderDuoChromePlacement.resolve(
            layout: .rail(.right), size: CGSize(width: 466, height: 678),
            safe: UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0),
            regions: ReaderHostRegions(verticalBar: .right)
        )
        // The rail never sits in less than its own reserve.
        #expect(placement.railCenterInset == ReaderPageBoxGeometry.verticalBarReserve / 2)
        #expect(placement.railTop == 30)
    }

    @Test func portraitBarIsCentredAndNarrowsOnASmallScreen() {
        let wide = ReaderDuoChromePlacement.resolve(
            layout: .foldTopBar, size: CGSize(width: 669, height: 951),
            safe: UIEdgeInsets(top: 82, left: 0, bottom: 34, right: 0), regions: ReaderHostRegions()
        )
        #expect(wide.barLeft == 114.5)
        #expect(wide.barRight == 114.5)
        let narrow = ReaderDuoChromePlacement.resolve(
            layout: .foldTopBar, size: CGSize(width: 400, height: 800),
            safe: .zero, regions: ReaderHostRegions()
        )
        #expect(narrow.barLeft == 16)
        #expect(narrow.barRight == 16)
    }

    @Test func theVerticalBarInsetHoldsWhenTheStatusBarHides() {
        let size = CGSize(width: 951, height: 669)
        // First report while the status bar is hidden: the rail's reserve.
        let opened = ReaderPageBoxGeometry().updating(
            size: size, safeInsets: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0),
            verticalBar: .right, preserveStatusBarTop: true
        )
        #expect(opened.safeInsets.right == ReaderPageBoxGeometry.verticalBarReserve)
        let shown = opened.updating(
            size: size, safeInsets: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84),
            verticalBar: .right, preserveStatusBarTop: false
        )
        #expect(shown.safeInsets.right == 84)
        // Hiding the status bar again must not widen the page.
        let hidden = shown.updating(
            size: size, safeInsets: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0),
            verticalBar: .right, preserveStatusBarTop: true
        )
        #expect(hidden == shown)
        // A fold or rotation keeps the widest bar seen; no bar uses the system's insets.
        let cover = hidden.updating(
            size: CGSize(width: 466, height: 678),
            safeInsets: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0),
            verticalBar: .right, preserveStatusBarTop: true
        )
        #expect(cover.safeInsets.right == 84)
        let phone = hidden.updating(
            size: size, safeInsets: UIEdgeInsets(top: 0, left: 62, bottom: 21, right: 62),
            preserveStatusBarTop: true
        )
        #expect(phone.safeInsets.right == 62)
        #expect(phone.verticalBar == .none)
    }

    @Test func theStatusBlockBottomSurvivesAHiddenStatusBar() {
        let shown = ReaderHostRegions(verticalBar: .right, barStatusBottom: 124)
        let hidden = ReaderHostRegions(verticalBar: .right)
        #expect(hidden.merging(previous: shown, sameSize: true).barStatusBottom == 124)
        #expect(hidden.merging(previous: shown, sameSize: false).barStatusBottom == 0)
        let otherEdge = ReaderHostRegions(verticalBar: .left)
        #expect(otherEdge.merging(previous: shown, sameSize: true).barStatusBottom == 0)
    }

    @Test func onlyThePortraitTopBarReservesABandAboveThePage() {
        #expect(ReadiumBook.topBarReserve(for: ReaderHostRegions()) == 0)
        #expect(ReadiumBook.topBarReserve(for: ReaderHostRegions(verticalBar: .right, fold: Self.innerFold)) == 0)
        #expect(ReadiumBook.topBarReserve(
            for: ReaderHostRegions(fold: CGRect(x: 0, y: 455.5, width: 669, height: 40))
        ) == ReaderDuoChromePlacement.topBarReserve)
    }

    @Test func compactChapterLabelShortensChaptersAndKeepsMatterNames() {
        #expect(ReaderPositionSummary.Place.chapter(index: 7, total: 20).shortLabel == "Ch 7 of 20")
        #expect(ReaderPositionSummary.Place.chapter(index: 7, total: 1).shortLabel == "Ch 7 of 7")
        #expect(ReaderPositionSummary.Place.preface.shortLabel == "Preface")
        #expect(ReaderPositionSummary.Place.other.shortLabel.isEmpty)
        let summary = ReaderPositionSummary(
            page: 4, pageCount: 18, percent: 30, place: .chapter(index: 7, total: 20),
            remainingInChapter: nil, remainingInWork: nil
        )
        #expect(summary.chapterShortLabel == "Ch 7 of 20")
    }

    @Test func theDuoMenuLeavesOutWhatTheGroupShowsAndKeepsReadAloudSettings() {
        let pills: [ReaderFanMenuPill] = [
            .init(id: "contents", title: "Contents", systemImage: "list.bullet", action: {}),
            .init(id: "bookmarks", title: "Bookmarks & Highlights", systemImage: "bookmark", action: {}),
            .init(id: "find", title: "Find in Work", systemImage: "magnifyingglass", action: {}),
            .init(id: "comments", title: "Comments", systemImage: "bubble.left.and.bubble.right", action: {}),
            .init(id: "rebuild", title: "Rebuild from Original", systemImage: "arrow.triangle.2.circlepath", action: {}),
            .init(id: "settings", title: "Themes & Settings", systemImage: "textformat.size", action: {})
        ]
        var settingsOpened = false
        let roundActions: [ReaderFanRoundAction] = [
            .init(id: "kudos", systemImage: "heart", accessibilityLabel: "Give kudos", action: {}),
            .init(
                id: "readAloud", systemImage: "waveform", accessibilityLabel: "Read aloud",
                isEnabled: false, action: {}
            ).withSettingsAction { settingsOpened = true },
            .init(id: "rotationLock", systemImage: "lock.open.rotation", accessibilityLabel: "Lock rotation", action: {}),
            .init(id: "bookmark", systemImage: "bookmark", accessibilityLabel: "Add bookmark", action: {})
        ]

        let standard = ReaderFanMenu.resolvedItems(pills: pills, roundActions: roundActions, inGroup: false)
        #expect(standard.find?.id == "find")
        #expect(standard.comments?.id == "comments")
        #expect(standard.readAloud?.id == "readAloud")
        #expect(standard.pillRows.map(\.id) == ["contents", "bookmarks", "settings"])
        #expect(standard.roundActionRows.map(\.id) == ["kudos", "rotationLock", "bookmark"])
        #expect(standard.readAloudSettings != nil)
        #expect(standard.rebuild?.id == "rebuild")

        let duo = ReaderFanMenu.resolvedItems(pills: pills, roundActions: roundActions, inGroup: true)
        #expect(duo.find?.id == "find")
        #expect(duo.comments?.id == "comments")
        #expect(duo.readAloud == nil)
        #expect(duo.pillRows.map(\.id) == ["bookmarks"])
        #expect(duo.roundActionRows.map(\.id) == ["kudos", "rotationLock"])
        #expect(duo.rebuild?.id == "rebuild")
        // Read Aloud Settings stays reachable even when Read Aloud is disabled.
        duo.readAloudSettings?()
        #expect(settingsOpened)
    }

    @Test func liveOcclusionsFixRailStatusAfterHiddenPortraitToLandscapeRotation() {
        let book = ReadiumBook()
        let portrait = CGSize(width: 669, height: 951)
        let landscape = CGSize(width: 951, height: 669)
        let portraitFold = CGRect(x: 0, y: 455.5, width: 669, height: 40)

        // Open in portrait (no vertical bar -> statusBottomBySize stays empty).
        book.updatePageBoxGeometry(
            size: portrait,
            safeInsets: UIEdgeInsets(top: 82, left: 0, bottom: 34, right: 0),
            regions: ReaderHostRegions(fold: portraitFold)
        )
        // Rotate to landscape with bars hidden, then reveal bars before occlusion activates.
        book.updatePageBoxGeometry(
            size: landscape,
            safeInsets: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0),
            regions: ReaderHostRegions(verticalBar: .right, barStatusBottom: 0, fold: Self.innerFold)
        )
        book.chromeHidden = false
        book.updatePageBoxGeometry(
            size: landscape,
            safeInsets: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84),
            regions: ReaderHostRegions(verticalBar: .right, barStatusBottom: 0, fold: Self.innerFold)
        )
        #expect(book.hostRegions.barStatusBottom == 0)

        // SwiftUI's live occlusion probe delivers the activated status block ~14 ms later.
        book.updateLiveOcclusions([CGRect(x: 867, y: 0, width: 84, height: 124)], in: landscape)
        #expect(book.hostRegions.barStatusBottom == 124)
        let placement = ReaderDuoChromePlacement.resolve(
            layout: .rail(.right), size: landscape,
            safe: book.pageBoxGeometry.safeInsets, regions: book.hostRegions
        )
        #expect(placement.railTop == 134)

        // Rotate 180° to `.left` with bars hidden: reuses same-size status bottom and accepts live `.left` occlusion.
        book.chromeHidden = true
        book.updatePageBoxGeometry(
            size: landscape,
            safeInsets: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0),
            regions: ReaderHostRegions(verticalBar: .left, barStatusBottom: 0, fold: Self.innerFold)
        )
        #expect(book.hostRegions.barStatusBottom == 124)
        book.updateLiveOcclusions([CGRect(x: 0, y: 0, width: 84, height: 128)], in: landscape)
        #expect(book.hostRegions.barStatusBottom == 128)
    }

    @Test func coverLandscapeClampsFallbackRailTopAboveHomeIndicator() {
        let size = CGSize(width: 678, height: 466)
        let safe = UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84)
        let placement = ReaderDuoChromePlacement.resolve(
            layout: .rail(.right), size: size, safe: safe,
            regions: ReaderHostRegions(verticalBar: .right, barStatusBottom: 174)
        )
        #expect(placement.railTop + ReaderDuoChromePlacement.railHeight <= size.height - safe.bottom)
        #expect(placement.railTop == 150)
    }

    @Test func hiddenOrientationChangesHoldDuoInsetsWithoutReflow() async {
        // Portrait -> Landscape with bars hidden reserves full 84 pt bar column up front.
        #expect(ReaderPageBoxGeometry.verticalBarReserve == 84)
        let book = ReadiumBook()
        let portrait = CGSize(width: 669, height: 951)
        let landscape = CGSize(width: 951, height: 669)
        let portraitFold = CGRect(x: 0, y: 455.5, width: 669, height: 40)

        book.updatePageBoxGeometry(
            size: landscape,
            safeInsets: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0),
            regions: ReaderHostRegions(verticalBar: .right, fold: Self.innerFold)
        )
        await book.pageBoxRemeasureTask?.value
        #expect(book.pageBoxGeometry.safeInsets.right == 84)
        // First show reports safe.right = 84: page box did not change -> no reflow remeasure.
        book.chromeHidden = false
        book.updatePageBoxGeometry(
            size: landscape,
            safeInsets: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84),
            regions: ReaderHostRegions(verticalBar: .right, barStatusBottom: 124, fold: Self.innerFold)
        )
        #expect(book.pageBoxRemeasureTask == nil)
        #expect(book.pageBoxGeometry.safeInsets.right == 84)

        // Landscape -> Portrait with bars hidden holds the 82 pt upright status-bar reserve.
        book.chromeHidden = true
        book.updatePageBoxGeometry(
            size: portrait,
            safeInsets: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0),
            regions: ReaderHostRegions(fold: portraitFold)
        )
        await book.pageBoxRemeasureTask?.value
        #expect(book.pageBoxGeometry.safeInsets.top == ReaderPageBoxGeometry.foldTopBarTopReserve)
        // Showing bars in Portrait reports safe.top = 82: zero reflow and no remeasure.
        book.chromeHidden = false
        book.updatePageBoxGeometry(
            size: portrait,
            safeInsets: UIEdgeInsets(top: 82, left: 0, bottom: 34, right: 0),
            regions: ReaderHostRegions(fold: portraitFold)
        )
        #expect(book.pageBoxRemeasureTask == nil)
        #expect(book.pageBoxGeometry.safeInsets.top == 82)
    }

    @Test func transientStandardFrameDuringUnfoldDoesNotDropDuoLayout() async {
        let book = ReadiumBook()
        let cover = CGSize(width: 466, height: 678)
        let open = CGSize(width: 951, height: 669)

        book.updatePageBoxGeometry(
            size: cover,
            safeInsets: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84),
            regions: ReaderHostRegions(verticalBar: .right, barStatusBottom: 174)
        )
        #expect(ReaderChromeLayout.resolve(book.hostRegions) == .rail(.right))

        // Intermediate Cover -> Open frame arrives with bar=none and fold=nil.
        book.updatePageBoxGeometry(
            size: open,
            safeInsets: UIEdgeInsets(top: 82, left: 0, bottom: 34, right: 0),
            regions: ReaderHostRegions()
        )
        #expect(ReaderChromeLayout.resolve(book.hostRegions) == .rail(.right))
        #expect(book.pendingStandardLayoutTask != nil)

        // Real Open frame arrives 35 ms later and cancels the deferred drop.
        book.updatePageBoxGeometry(
            size: open,
            safeInsets: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84),
            regions: ReaderHostRegions(verticalBar: .right, barStatusBottom: 124, fold: Self.innerFold)
        )
        #expect(book.pendingStandardLayoutTask == nil)
        #expect(ReaderChromeLayout.resolve(book.hostRegions) == .rail(.right))

        // A genuine permanent move to a standard display commits once the debounce elapses.
        book.updatePageBoxGeometry(
            size: CGSize(width: 402, height: 874),
            safeInsets: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0),
            regions: ReaderHostRegions()
        )
        #expect(ReaderChromeLayout.resolve(book.hostRegions) == .rail(.right))
        await book.pendingStandardLayoutTask?.value
        #expect(ReaderChromeLayout.resolve(book.hostRegions) == .standard)
        book.cancelPageBoxRemeasure()
    }

    @Test func foldFrameRequiresBoundsIntersectionAndAcceptsZeroThicknessCrease() {
        let sheetBounds = CGRect(x: 0, y: 0, width: 400, height: 669)
        let outOfBoundsFold = CGRect(x: 455.5, y: 0, width: 40, height: 669)
        #expect(ReaderHostRegions.foldFrame(from: [outOfBoundsFold], in: sheetBounds) == nil)

        let portraitBounds = CGRect(x: 0, y: 0, width: 669, height: 951)
        let zeroHeightCrease = CGRect(x: 0, y: 475, width: 669, height: 0)
        #expect(ReaderHostRegions.foldFrame(from: [zeroHeightCrease], in: portraitBounds) == zeroHeightCrease)
    }

    @Test func borrowedStatusBlockFallbackDoesNotStickAfterLiveOcclusionArrives() throws {
        let book = ReadiumBook()
        let cover = CGSize(width: 466, height: 678)
        let landscape = CGSize(width: 951, height: 669)

        // Measure Cover's taller 174 pt status block on the right edge.
        book.updatePageBoxGeometry(
            size: cover,
            safeInsets: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84),
            regions: ReaderHostRegions(verticalBar: .right, barStatusBottom: 174)
        )
        #expect(book.hostRegions.barStatusBottom == 174)

        // Unfold with chrome hidden into unmeasured Open Landscape: borrows 174 pt.
        book.updatePageBoxGeometry(
            size: landscape,
            safeInsets: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0),
            regions: ReaderHostRegions(verticalBar: .right, barStatusBottom: 0, fold: Self.innerFold)
        )
        #expect(book.hostRegions.barStatusBottom == 174)

        // A second same-size unmeasured report arrives before live occlusion activates.
        book.chromeHidden = false
        book.updatePageBoxGeometry(
            size: landscape,
            safeInsets: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84),
            regions: ReaderHostRegions(verticalBar: .right, barStatusBottom: 0, fold: Self.innerFold)
        )
        #expect(book.hostRegions.barStatusBottom == 174)

        // Live SwiftUI occlusion reports Open Landscape's real 124 pt status block:
        // live geometry must win over the borrowed 174 pt fallback.
        book.updateLiveOcclusions([CGRect(x: 867, y: 0, width: 84, height: 124)], in: landscape)
        #expect(book.hostRegions.barStatusBottom == 124)
        let placement = ReaderDuoChromePlacement.resolve(
            layout: .rail(.right), size: landscape,
            safe: book.pageBoxGeometry.safeInsets, regions: book.hostRegions
        )
        #expect(placement.railTop == 134)
        let panel = try #require(ReaderDuoSettingsPanelPlacement.resolve(
            layout: .rail(.right), chrome: placement, size: landscape,
            safe: book.pageBoxGeometry.safeInsets, regions: book.hostRegions, chromeTop: 0
        ))
        #expect(panel.top == 194)

        // Subsequent unmeasured report at this size keeps the real 124 pt measurement.
        book.chromeHidden = true
        book.updatePageBoxGeometry(
            size: landscape,
            safeInsets: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0),
            regions: ReaderHostRegions(verticalBar: .right, barStatusBottom: 0, fold: Self.innerFold)
        )
        #expect(book.hostRegions.barStatusBottom == 124)
        book.cancelPageBoxRemeasure()
    }

    @Test func repeatedStandardReportsDoNotRestartDeferredDropDeadline() async throws {
        let book = ReadiumBook()
        book.updatePageBoxGeometry(
            size: CGSize(width: 466, height: 678),
            safeInsets: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84),
            regions: ReaderHostRegions(verticalBar: .right, barStatusBottom: 174)
        )
        #expect(ReaderChromeLayout.resolve(book.hostRegions) == .rail(.right))

        // First standard report starts the 120 ms deadline.
        book.updatePageBoxGeometry(
            size: CGSize(width: 400, height: 870),
            safeInsets: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0),
            regions: ReaderHostRegions()
        )
        let firstTask = try #require(book.pendingStandardLayoutTask)

        // Repeated standard reports during a resize update pending geometry without cancelling the timer.
        book.updatePageBoxGeometry(
            size: CGSize(width: 410, height: 880),
            safeInsets: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0),
            regions: ReaderHostRegions()
        )
        #expect(!firstTask.isCancelled)
        book.updatePageBoxGeometry(
            size: CGSize(width: 420, height: 890),
            safeInsets: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0),
            regions: ReaderHostRegions()
        )
        #expect(!firstTask.isCancelled)

        await firstTask.value
        #expect(book.pendingStandardLayoutTask == nil)
        #expect(ReaderChromeLayout.resolve(book.hostRegions) == .standard)
        #expect(book.pageBoxGeometry.size == CGSize(width: 420, height: 890))
        book.cancelPageBoxRemeasure()
    }
}
#endif
