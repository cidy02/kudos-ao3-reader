import Foundation
import Testing

#if os(iOS)
import ReadiumNavigator
import ReadiumShared
import UIKit
@testable import Kudos
#endif

#if os(iOS)
/// T-562b (owner, after Apple Books): turning a page hides the reader's controls;
/// jumps, scrubs, cancelled drags, micro-scrolls and relayouts do not; nothing hides
/// them while something is open over the page or VoiceOver runs; every show and hide fades.
@MainActor
struct ReaderChromeAutoHideTests {
    private typealias Place = ReaderChromeAutoHide.Place
    private let now = Date(timeIntervalSinceReferenceDate: 1000)
    private let page4 = Place(href: "chapter1.xhtml", position: 4, progression: 0.25)
    private let page5 = Place(href: "chapter1.xhtml", position: 5, progression: 0.31)

    private func turn(
        from: Place?, to: Place, jumpInFlight: Bool = false, isScrubbing: Bool = false,
        isScrollInteracting: Bool = false, isPaged: Bool = true, pageCount: Int? = nil,
        echoUntil: Date = .distantPast
    ) -> Bool {
        ReaderChromeAutoHide.isUserTurn(
            from: from, to: to, jumpInFlight: jumpInFlight, isScrubbing: isScrubbing,
            isScrollInteracting: isScrollInteracting, isPaged: isPaged, pageCount: pageCount,
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

    @Test func cancelledSlideDragAndSubPageWobbleDoNotHide() {
        let p1 = Place(href: "chapter1.xhtml", position: 1, progression: 0.0)
        let midDrag = Place(href: "chapter1.xhtml", position: 2, progression: 0.18)
        let wobble = Place(href: "chapter1.xhtml", position: 1, progression: 0.08)
        let p2 = Place(href: "chapter1.xhtml", position: 2, progression: 0.25)

        #expect(!turn(from: p1, to: midDrag, isScrollInteracting: true, isPaged: true, pageCount: 4))
        #expect(!turn(from: p1, to: wobble, isScrollInteracting: false, isPaged: true, pageCount: 4))
        #expect(turn(from: p1, to: p2, isScrollInteracting: false, isPaged: true, pageCount: 4))
        // A single-page chapter has no intra-chapter turns, only cross-chapter turns.
        #expect(!turn(from: p1, to: wobble, isPaged: true, pageCount: 1))
        #expect(turn(from: p1, to: Place(href: "chapter2.xhtml", position: 2, progression: 0.0), isPaged: true, pageCount: 1))
    }

    @Test func tinyScrollNudgeDoesNotHideWhileRealScrollDoes() {
        let start = Place(href: "chapter1.xhtml", position: 1, progression: 0.20)
        let tinyNudge = Place(href: "chapter1.xhtml", position: 1, progression: 0.2005)
        let realScroll = Place(href: "chapter1.xhtml", position: 1, progression: 0.25)

        #expect(!turn(from: start, to: tinyNudge, isPaged: false, pageCount: 4))
        #expect(turn(from: start, to: realScroll, isPaged: false, pageCount: 4))
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
        #expect(!ReaderChromeAutoHide.hidesControls(
            controlsShowing: false, overlayOpen: false, voiceOverRunning: false
        ))
    }

    @Test func voiceOverKeepsTheControls() {
        #expect(!ReaderChromeAutoHide.hidesControls(controlsShowing: true, overlayOpen: false, voiceOverRunning: true))
    }

    // MARK: - Live ReadiumBook wiring

    @Test func bookUpdatesVisualPageBeforeFiringTurnAndIgnoresOpeningAndWobbles() throws {
        let book = ReadiumBook()
        let nav = AutoHideTestNavigator()
        book.seedInitialPreferences(EPUBPreferences(scroll: false))
        let href = try #require(AnyURL(string: "OEBPS/chapter1.xhtml"))
        let p2 = Locator(
            href: href, mediaType: .xhtml,
            locations: .init(progression: 0.25, totalProgression: 0.13, position: 2)
        )
        let wobble = Locator(
            href: href, mediaType: .xhtml,
            locations: .init(progression: 0.30, totalProgression: 0.15, position: 2)
        )
        let p1 = Locator(
            href: href, mediaType: .xhtml,
            locations: .init(progression: 0.0, totalProgression: 0.0, position: 1)
        )

        var pagesSeenDuringTurnCallback: [Int] = []
        book.onUserPageTurn = {
            if let page = book.readingPosition?.page {
                pagesSeenDuringTurnCallback.append(page)
            }
        }

        // First settle after opening is never a turn.
        book.navigator(nav, locationDidChange: p2)
        #expect(pagesSeenDuringTurnCallback.isEmpty)

        // Establish 4-page chapter bar on page 2.
        book.acceptLayoutPageCount(4, measuredPage: 2, preferHorizontal: true, isFinalAttempt: false)
        book.acceptLayoutPageCount(4, measuredPage: 2, preferHorizontal: true, isFinalAttempt: false)
        #expect(book.readingPosition?.page == 2)

        // Sub-page wobble on page 2 does not hide.
        book.navigator(nav, locationDidChange: wobble)
        #expect(pagesSeenDuringTurnCallback.isEmpty)

        // Committed turn back to page 1 updates visualPage BEFORE firing onUserPageTurn.
        book.navigator(nav, locationDidChange: p1)
        #expect(pagesSeenDuringTurnCallback == [1])
        #expect(book.readingPosition?.page == 1)
        #expect(book.readingPosition?.percent == 0)
    }

    @Test func bookUnchangedSubmitDoesNotMuteNextTurnWhileChangedSubmitAndGeometryAndScrubDo() throws {
        let book = ReadiumBook()
        let nav = AutoHideTestNavigator()
        let initialPrefs = EPUBPreferences(fontSize: 1.0, scroll: false)
        book.seedInitialPreferences(initialPrefs)

        let href = try #require(AnyURL(string: "OEBPS/chapter1.xhtml"))
        let p1 = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 0.0, position: 1))
        let p2 = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 0.25, position: 2))
        let p3 = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 0.50, position: 3))
        let p4 = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 0.75, position: 4))

        var turns = 0
        book.onUserPageTurn = { turns += 1 }

        book.navigator(nav, locationDidChange: p1)
        book.acceptLayoutPageCount(4, measuredPage: 1, preferHorizontal: true, isFinalAttempt: false)
        book.acceptLayoutPageCount(4, measuredPage: 1, preferHorizontal: true, isFinalAttempt: false)

        // Closing an unchanged panel re-submits initialPrefs: must NOT arm relayout echo.
        #expect(!book.submit(initialPrefs))
        book.navigator(nav, locationDidChange: p2)
        #expect(turns == 1)

        // Scrubbing suppresses turn-hide.
        book.isScrubbing = true
        book.navigator(nav, locationDidChange: p3)
        #expect(turns == 1)
        book.isScrubbing = false

        // A real preference change arms relayout echo and suppresses the next settle.
        #expect(book.submit(EPUBPreferences(fontSize: 1.25, scroll: false)))
        book.navigator(nav, locationDidChange: p4)
        #expect(turns == 1)

        // A real geometry change arms relayout echo too.
        book.updatePageBoxGeometry(size: CGSize(width: 402, height: 874), safeInsets: .zero)
        book.navigator(nav, locationDidChange: p1)
        #expect(turns == 1)
        book.cancelPageBoxRemeasure()
    }

    @Test func bookGoToJumpSuppressesTurnHide() throws {
        let book = ReadiumBook()
        let nav = AutoHideTestNavigator()
        book.seedInitialPreferences(EPUBPreferences(scroll: false))
        let href = try #require(AnyURL(string: "OEBPS/chapter1.xhtml"))
        let p1 = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 0.0, position: 1))
        let p3 = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 0.50, position: 3))

        var turns = 0
        book.onUserPageTurn = { turns += 1 }
        book.navigator(nav, locationDidChange: p1)
        book.acceptLayoutPageCount(4, measuredPage: 1, preferHorizontal: true, isFinalAttempt: false)
        book.acceptLayoutPageCount(4, measuredPage: 1, preferHorizontal: true, isFinalAttempt: false)

        book.go(to: p3)
        book.navigator(nav, locationDidChange: p3)
        #expect(turns == 0)
    }
}

private final class AutoHideTestNavigator: @preconcurrency Navigator {
    let publication = Publication(manifest: Manifest())
    var currentLocation: Locator? { nil }
    func go(to locator: Locator, options: NavigatorGoOptions) async -> Bool { false }
    func go(to link: ReadiumShared.Link, options: NavigatorGoOptions) async -> Bool { false }
    func goForward(options: NavigatorGoOptions) async -> Bool { false }
    func goBackward(options: NavigatorGoOptions) async -> Bool { false }
}
#endif
