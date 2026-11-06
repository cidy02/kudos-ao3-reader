import Foundation
import Testing
@testable import Kudos

struct ColdStartScanViewTests {
    @Test("Identity copy is visible-ready and pluralized")
    func identityCopy() {
        let progress = ColdStartScanView.Progress(
            phase: .running,
            checked: 1,
            total: 35,
            username: "saltwindow"
        )

        #expect(
            ColdStartScanView(progress: progress).identityText
                == "Signed in as saltwindow · 35 follows · 1 checked · 34 to go"
        )
    }

    @Test("Finished singular follow copy omits zero to go")
    func finishedIdentityCopy() {
        let progress = ColdStartScanView.Progress(
            phase: .finished,
            checked: 1,
            total: 1,
            username: "saltwindow"
        )

        #expect(
            ColdStartScanView(progress: progress).identityText
                == "Signed in as saltwindow · 1 follow · 1 checked"
        )
    }

    @Test("Estimates round up to minutes and never show seconds")
    func estimateCopy() {
        #expect(ColdStartScanView.formatEstimate(.zero) == nil)
        #expect(ColdStartScanView.formatEstimate(.seconds(1)) == "about a minute left")
        #expect(ColdStartScanView.formatEstimate(.seconds(60)) == "about a minute left")
        #expect(ColdStartScanView.formatEstimate(.seconds(61)) == "about 2 minutes left")
    }
}
