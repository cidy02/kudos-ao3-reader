import Foundation
import Testing

#if os(iOS)
import ReadiumNavigator
import UIKit
@testable import Kudos
#endif

#if os(iOS)
/// T-562b: Themes & Settings as a panel by the Duo bars, and the upright Duo reading
/// one page. Sizes are the Duo simulator's (see `ReaderDuoChromeTests`); the board
/// is `Duo-Open-Reader` `showSettings` (360 wide, right 84, top 150).
@MainActor
struct ReaderDuoSettingsPanelTests {
    private static let innerFold = CGRect(x: 455.5, y: 0, width: 40, height: 669)
    private static let portraitFold = CGRect(x: 0, y: 455.5, width: 669, height: 40)

    private func panel(
        _ layout: ReaderChromeLayout, size: CGSize, safe: UIEdgeInsets,
        regions: ReaderHostRegions, chromeTop: CGFloat = 0
    ) -> ReaderDuoSettingsPanelPlacement? {
        let chrome = ReaderDuoChromePlacement.resolve(layout: layout, size: size, safe: safe, regions: regions)
        return ReaderDuoSettingsPanelPlacement.resolve(
            layout: layout, chrome: chrome, size: size, safe: safe, regions: regions, chromeTop: chromeTop
        )
    }

    @Test func onlyTheDuoLayoutsUseThePanel() {
        #expect(!ReaderChromeLayout.standard.showsSettingsAsPanel)
        #expect(ReaderChromeLayout.rail(.right).showsSettingsAsPanel)
        #expect(ReaderChromeLayout.foldTopBar.showsSettingsAsPanel)
        #expect(panel(.standard, size: CGSize(width: 402, height: 874), safe: .zero, regions: ReaderHostRegions()) == nil)
    }

    @Test func openFlatHugsTheRailOnTheTrailingPageLevelWithAa() throws {
        let placement = try #require(panel(
            .rail(.right), size: CGSize(width: 951, height: 669),
            safe: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84),
            regions: ReaderHostRegions(verticalBar: .right, barStatusBottom: 124, fold: Self.innerFold)
        ))
        #expect(placement.width == 360)
        // Its right edge is the position bar's: 12 pt from the rail.
        #expect(951 - (placement.left + placement.width) == 86)
        #expect(placement.left >= Self.innerFold.maxX)
        // railTop 134 + Close 48 + 10 + the group's 2: the Aa button's top.
        #expect(placement.top == 194)
        #expect(placement.top + placement.height == 669 - 34)
    }

    @Test func aLeadingRailKeepsThePanelOnItsOwnPage() throws {
        let placement = try #require(panel(
            .rail(.left), size: CGSize(width: 951, height: 669),
            safe: UIEdgeInsets(top: 0, left: 84, bottom: 34, right: 0),
            regions: ReaderHostRegions(verticalBar: .left, barStatusBottom: 124, fold: Self.innerFold)
        ))
        #expect(placement.left == 86)
        #expect(placement.left + placement.width <= Self.innerFold.minX)
    }

    @Test func coverPanelStaysLeftOfTheStatusColumn() throws {
        let placement = try #require(panel(
            .rail(.right), size: CGSize(width: 466, height: 678),
            safe: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84),
            regions: ReaderHostRegions(verticalBar: .right, barStatusBottom: 174)
        ))
        #expect(placement.width == 360)
        #expect(placement.left == 20)
        // Done sits inside the panel, which ends before the 84 pt bar column.
        #expect(placement.left + placement.width <= 466 - 84)
        #expect(placement.top == 244)
    }

    @Test func aShortScreenGivesUpTheAnchorRatherThanShowASliver() throws {
        let placement = try #require(panel(
            .rail(.right), size: CGSize(width: 466, height: 400),
            safe: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84),
            regions: ReaderHostRegions(verticalBar: .right, barStatusBottom: 174)
        ))
        #expect(placement.height == ReaderDuoSettingsPanelPlacement.minimumHeight)
        #expect(placement.top == 86)
    }

    @Test func uprightPanelSitsUnderTheTopBarAndAboveTheFold() throws {
        let placement = try #require(panel(
            .foldTopBar, size: CGSize(width: 669, height: 951),
            safe: UIEdgeInsets(top: 82, left: 0, bottom: 34, right: 0),
            regions: ReaderHostRegions(fold: Self.portraitFold), chromeTop: 82
        ))
        #expect(placement.top == 82 + ReaderDuoChromePlacement.topBarReserve)
        #expect(placement.left + placement.width == 669 - 16)
        #expect(placement.top + placement.height == Self.portraitFold.minY - 8)
    }

    @Test func uprightPanelCrossesAFoldThatLeavesNoRoom() throws {
        let placement = try #require(panel(
            .foldTopBar, size: CGSize(width: 669, height: 951),
            safe: UIEdgeInsets(top: 82, left: 0, bottom: 34, right: 0),
            regions: ReaderHostRegions(fold: CGRect(x: 0, y: 300, width: 669, height: 40)), chromeTop: 82
        ))
        #expect(placement.top + placement.height == 951 - 34)
    }

    @Test func uprightDuoReadsOnePageWithTwoPageSpreadOn() {
        #expect(!ReaderChromeLayout.foldTopBar.allowsTwoPageSpread)
        #expect(ReaderChromeLayout.rail(.right).allowsTwoPageSpread)
        #expect(ReaderChromeLayout.standard.allowsTwoPageSpread)
        let upright = ReadiumReaderStyleMapper.columnCount(
            readingMode: .paged, twoPageSpread: true && ReaderChromeLayout.foldTopBar.allowsTwoPageSpread,
            bookPose: false, tabletopPose: false
        )
        #expect(upright == .one)
        let open = ReadiumReaderStyleMapper.columnCount(
            readingMode: .paged, twoPageSpread: true && ReaderChromeLayout.rail(.right).allowsTwoPageSpread,
            bookPose: false, tabletopPose: false
        )
        #expect(open == .two)
    }
}
#endif
