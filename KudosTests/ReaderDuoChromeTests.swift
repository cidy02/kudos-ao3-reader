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
        // A new size or no bar starts afresh.
        let cover = hidden.updating(
            size: CGSize(width: 466, height: 678),
            safeInsets: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0),
            verticalBar: .right, preserveStatusBarTop: true
        )
        #expect(cover.safeInsets.right == ReaderPageBoxGeometry.verticalBarReserve)
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

    @Test func theDuoMenuLeavesOutWhatTheGroupShows() {
        #expect(ReaderFanMenu.groupItemIDs == ["contents", "settings", "bookmark", "readAloud"])
    }
}
#endif
