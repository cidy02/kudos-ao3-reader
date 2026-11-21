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
}
#endif
