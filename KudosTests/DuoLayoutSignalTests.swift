import CoreGraphics
import Foundation
import Testing
@testable import Kudos

@MainActor
struct DuoLayoutSignalTests {
    @Test func defaultSignalIsAnOrdinaryScreen() {
        let signal = DuoLayoutSignal()
        #expect(!signal.hasVerticalBar)
        #expect(!signal.isUprightFold)
        #expect(signal.inspectorWidth == nil)
    }

    @Test func inspectorRunsFromTheFoldToTheRail() {
        // Duo inner screen, flat, landscape: 951 wide, fold 40 pt clear around x 475.
        let signal = DuoLayoutSignal(
            hasVerticalBar: true, verticalFold: CGRect(x: 455, y: 0, width: 40, height: 669), width: 951
        )
        #expect(signal.inspectorWidth == 951 - 495 - DuoLayoutSignal.railReserve)
    }

    @Test func narrowPaneKeepsTheDefaultInspectorWidth() {
        let signal = DuoLayoutSignal(
            hasVerticalBar: true, verticalFold: CGRect(x: 300, y: 0, width: 40, height: 400), width: 480
        )
        #expect(signal.inspectorWidth == nil)
    }

    @Test func uprightFoldNeedsAHorizontalFoldAndNoRail() {
        #expect(DuoLayoutSignal(hasHorizontalFold: true).isUprightFold)
        #expect(!DuoLayoutSignal(hasVerticalBar: true, hasHorizontalFold: true).isUprightFold)
    }
}
