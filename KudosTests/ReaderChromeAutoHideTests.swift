import Foundation
import Testing

#if os(iOS)
@testable import Kudos
#endif

#if os(iOS)
/// T-562b (owner, after Apple Books): turning a page hides the reader's controls;
/// jumps, scrubs and relayouts do not; nothing hides them while something is open
/// over the page or VoiceOver runs; every show and hide fades.
struct ReaderChromeAutoHideTests {
    private typealias Place = ReaderChromeAutoHide.Place
    private let now = Date(timeIntervalSinceReferenceDate: 1000)
    private let page4 = Place(href: "chapter1.xhtml", position: 4, progression: 0.25)
    private let page5 = Place(href: "chapter1.xhtml", position: 5, progression: 0.31)

    private func turn(
        from: Place?, to: Place, jumpInFlight: Bool = false, isScrubbing: Bool = false,
        echoUntil: Date = .distantPast
    ) -> Bool {
        ReaderChromeAutoHide.isUserTurn(
            from: from, to: to, jumpInFlight: jumpInFlight, isScrubbing: isScrubbing,
            echoUntil: echoUntil, now: now
        )
    }

    @Test func aTurnToTheNextPageHides() {
        #expect(turn(from: page4, to: page5))
        // Back counts too, and a turn into the next chapter.
        #expect(turn(from: page5, to: page4))
        #expect(turn(from: page5, to: Place(href: "chapter2.xhtml", position: 6, progression: 0)))
    }

    @Test func aPageInsideOnePositionStillCounts() {
        let next = Place(href: "chapter1.xhtml", position: 4, progression: 0.28)
        #expect(turn(from: page4, to: next))
    }

    @Test func theSameSettleAgainIsNotATurn() {
        #expect(!turn(from: page4, to: page4))
    }

    @Test func aScrubDoesNotHide() {
        #expect(!turn(from: page4, to: page5, isScrubbing: true))
    }

    @Test func aJumpAndItsEchoDoNotHide() {
        // Scrubber release, Contents, bookmarks, search, Read Aloud: all jumps.
        #expect(!turn(from: page4, to: page5, jumpInFlight: true))
        #expect(!turn(from: page4, to: page5, echoUntil: now.addingTimeInterval(0.3)))
        // Once the echo window has passed, the reader's own turn hides again.
        #expect(turn(from: page4, to: page5, echoUntil: now.addingTimeInterval(-0.01)))
    }

    @Test func theFirstSettleAfterOpeningIsNotATurn() {
        #expect(!turn(from: nil, to: page5))
    }

    @Test func aPanelOrSheetOpenKeepsTheControls() {
        #expect(ReaderChromeAutoHide.hidesControls(controlsShowing: true, overlayOpen: false, voiceOverRunning: false))
        #expect(!ReaderChromeAutoHide.hidesControls(controlsShowing: true, overlayOpen: true, voiceOverRunning: false))
        #expect(!ReaderChromeAutoHide.hidesControls(controlsShowing: false, overlayOpen: false, voiceOverRunning: false))
    }

    @Test func voiceOverKeepsTheControls() {
        #expect(!ReaderChromeAutoHide.hidesControls(controlsShowing: true, overlayOpen: false, voiceOverRunning: true))
    }

    @Test func theFadeIsAQuarterSecondAndOutlastsNoEchoWindow() {
        #expect(ReaderChromeAutoHide.fadeDuration == 0.25)
        #expect(ReaderChromeAutoHide.jumpEchoWindow > ReaderChromeAutoHide.fadeDuration)
        #expect(ReaderChromeAutoHide.relayoutEchoWindow >= ReaderChromeAutoHide.jumpEchoWindow)
    }
}
#endif
