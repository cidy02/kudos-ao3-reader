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
        isScrollInteracting: Bool = false, isPaged: Bool = true, pageCount: Int? = 20,
        explicitUserTurn: Bool = false,
        jumpEchoUntil: Date = .distantPast,
        relayoutEchoUntil: Date = .distantPast
    ) -> Bool {
        ReaderChromeAutoHide.isUserTurn(
            from: from, to: to, jumpInFlight: jumpInFlight, isScrubbing: isScrubbing,
            isScrollInteracting: isScrollInteracting, isPaged: isPaged, pageCount: pageCount,
            explicitUserTurn: explicitUserTurn,
            jumpEchoUntil: jumpEchoUntil, relayoutEchoUntil: relayoutEchoUntil, now: now
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
        #expect(turn(from: page4, to: next, pageCount: 20))
    }

    @Test func theSameSettleAgainIsNotATurn() {
        #expect(!turn(from: page4, to: page4))
        #expect(!turn(from: page4, to: page4, pageCount: nil, explicitUserTurn: true))
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

    @Test func aJumpAndItsEchoDoNotHideUnlessUserExplicitlyTurns() {
        // Scrubber release, Contents, bookmarks, search, Read Aloud: all jumps.
        #expect(!turn(from: page4, to: page5, jumpInFlight: true))
        #expect(!turn(from: page4, to: page5, jumpInFlight: true, explicitUserTurn: true))
        #expect(!turn(from: page4, to: page5, jumpEchoUntil: now.addingTimeInterval(0.3)))
        // An explicit committed user turn is not masked by a prior jump's echo.
        #expect(turn(from: page4, to: page5, explicitUserTurn: true, jumpEchoUntil: now.addingTimeInterval(0.3)))
        // Relayout echoes still hold until they expire.
        #expect(!turn(from: page4, to: page5, explicitUserTurn: true, relayoutEchoUntil: now.addingTimeInterval(0.3)))
        // Once the echo window has passed, the reader's own turn hides again.
        #expect(turn(from: page4, to: page5, jumpEchoUntil: now.addingTimeInterval(-0.01)))
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

    @Test func geometryChangeSuppressesTurnsUntilRelayoutEchoExpires() throws {
        // Fresh book with a controlled clock and no prior preference submission, so
        // removing geometry's relayout echo breaks this test.
        let book = ReadiumBook()
        let nav = AutoHideTestNavigator()
        var clock = Date(timeIntervalSinceReferenceDate: 10_000)
        book.autoHideNow = { clock }
        book.seedInitialPreferences(EPUBPreferences(scroll: false))
        defer { book.cancelPageBoxRemeasure() }

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

        // Geometry change clears metrics and arms the 1.2 s relayout echo.
        book.updatePageBoxGeometry(size: CGSize(width: 402, height: 874), safeInsets: .zero)
        // Re-establish pagination so suppression comes solely from the geometry echo.
        book.acceptLayoutPageCount(4, measuredPage: 1, preferHorizontal: true, isFinalAttempt: false)
        book.acceptLayoutPageCount(4, measuredPage: 1, preferHorizontal: true, isFinalAttempt: false)

        book.navigator(nav, locationDidChange: p2)
        #expect(turns == 0)

        clock = clock.addingTimeInterval(ReaderChromeAutoHide.relayoutEchoWindow - 0.05)
        book.navigator(nav, locationDidChange: p3)
        #expect(turns == 0)

        // Once the geometry echo expires, ordinary turns hide controls again.
        clock = clock.addingTimeInterval(0.1)
        book.navigator(nav, locationDidChange: p4)
        #expect(turns == 1)
    }

    @Test func bookScrubAndGoToJumpSuppressTurnHideWhileExplicitTurnBeatsJumpEcho() async throws {
        let book = ReadiumBook()
        let nav = AutoHideTestNavigator()
        var clock = Date(timeIntervalSinceReferenceDate: 20_000)
        book.autoHideNow = { clock }
        book.seedInitialPreferences(EPUBPreferences(scroll: false))
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

        // Scrubbing suppresses turn-hide.
        book.isScrubbing = true
        book.navigator(nav, locationDidChange: p2)
        #expect(turns == 0)
        book.isScrubbing = false

        // Programmatic jump suppresses its in-flight and post-jump echo settles.
        book.go(to: p3)
        book.navigator(nav, locationDidChange: p3)
        #expect(turns == 0)
        await Task.yield()
        clock = clock.addingTimeInterval(0.2)
        book.navigator(nav, locationDidChange: p2)
        #expect(turns == 0)

        // An explicit committed user turn within the jump echo window still hides.
        book.noteExplicitUserTurn()
        book.navigator(nav, locationDidChange: p3)
        #expect(turns == 1)

        // After the jump echo expires, non-explicit turns hide normally again.
        clock = clock.addingTimeInterval(ReaderChromeAutoHide.jumpEchoWindow)
        book.navigator(nav, locationDidChange: p4)
        #expect(turns == 2)
    }

    @Test func unmeasuredPagedPositionBoundaryCrossingDoesNotHide() throws {
        let before = Place(href: "chapter1.xhtml", position: 2, progression: 0.250)
        let after = Place(href: "chapter1.xhtml", position: 3, progression: 0.251)
        let largerSameResource = Place(href: "chapter1.xhtml", position: 3, progression: 0.31)
        let nextChapter = Place(href: "chapter2.xhtml", position: 4, progression: 0.0)

        #expect(!turn(from: before, to: after, isPaged: true, pageCount: nil))
        #expect(!turn(from: before, to: largerSameResource, isPaged: true, pageCount: nil))
        #expect(turn(from: before, to: nextChapter, isPaged: true, pageCount: nil))
        #expect(turn(from: before, to: largerSameResource, isPaged: true, pageCount: nil, explicitUserTurn: true))

        // Live ReadiumBook before pageBarReady: position-boundary wobble stays silent,
        // explicit directional turn and chapter change hide.
        let book = ReadiumBook()
        let nav = AutoHideTestNavigator()
        book.seedInitialPreferences(EPUBPreferences(scroll: false))
        let ch1 = try #require(AnyURL(string: "OEBPS/chapter1.xhtml"))
        let ch2 = try #require(AnyURL(string: "OEBPS/chapter2.xhtml"))
        var turns = 0
        book.onUserPageTurn = { turns += 1 }

        book.navigator(nav, locationDidChange: Locator(href: ch1, mediaType: .xhtml, locations: .init(progression: 0.250, position: 2)))
        book.navigator(nav, locationDidChange: Locator(href: ch1, mediaType: .xhtml, locations: .init(progression: 0.251, position: 3)))
        #expect(!book.pageBarReady)
        #expect(turns == 0)

        book.noteExplicitUserTurn()
        book.navigator(nav, locationDidChange: Locator(href: ch1, mediaType: .xhtml, locations: .init(progression: 0.50, position: 4)))
        #expect(turns == 1)

        // Explicit attribution was consumed by the turn above; a later wobble stays silent.
        book.navigator(nav, locationDidChange: Locator(href: ch1, mediaType: .xhtml, locations: .init(progression: 0.501, position: 5)))
        #expect(turns == 1)

        // Cross-chapter navigation still hides even before pagination is measured.
        book.navigator(nav, locationDidChange: Locator(href: ch2, mediaType: .xhtml, locations: .init(progression: 0.0, position: 6)))
        #expect(turns == 2)
    }

    @Test func scrollModeLocatorUpdateDoesNotOverwriteMeasuredDOMPage() throws {
        let book = ReadiumBook()
        let nav = AutoHideTestNavigator()
        book.seedInitialPreferences(EPUBPreferences(scroll: true))
        let href = try #require(AnyURL(string: "OEBPS/chapter1.xhtml"))
        let start = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 0.0, position: 1))
        let stopped = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 1.45 / 2.6, position: 2))

        book.navigator(nav, locationDidChange: start)
        book.acceptLayoutPageCount(3, measuredPage: 2, preferHorizontal: false, isFinalAttempt: false)
        book.acceptLayoutPageCount(3, measuredPage: 2, preferHorizontal: false, isFinalAttempt: false)
        #expect(book.readingPosition?.page == 2)
        #expect(book.readingPosition?.pageCount == 3)

        book.navigator(nav, locationDidChange: stopped)
        #expect(book.readingPosition?.page == 2)
        #expect(book.readingPosition?.pageCount == 3)
    }

    @Test func openSeedsPreferencesAndUnchangedSubmitSkipsNavigatorResubmit() async throws {
        // Opens a real local EPUB fixture without calling `seedInitialPreferences`,
        // so removing the opening seed in `ReadiumBook.open` breaks this test.
        let epubURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/demo_work.epub")
        let initialPrefs = EPUBPreferences(fontSize: 1.0, scroll: false)
        let book = ReadiumBook()
        var clock = Date(timeIntervalSinceReferenceDate: 30_000)
        book.autoHideNow = { clock }
        defer {
            book.cancelPageBoxRemeasure()
            book.clearVisualPageMetrics()
        }
        await book.open(
            fileURL: epubURL,
            initialLocator: nil,
            config: EPUBNavigatorViewController.Configuration(preferences: initialPrefs)
        )
        #expect(book.phase == .ready)
        let navigator = try #require(book.navigator)
        let spy = PresentationSpyDelegate()
        navigator.delegate = spy
        defer { navigator.delegate = book }

        let href = try #require(AnyURL(string: "OEBPS/chapter1.xhtml"))
        let p1 = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 0.0, position: 1))
        let p2 = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 0.25, position: 2))
        let p3 = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 0.50, position: 3))
        let p4 = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 0.75, position: 4))

        var turns = 0
        book.onUserPageTurn = { turns += 1 }
        book.navigator(navigator, locationDidChange: p1)
        book.acceptLayoutPageCount(4, measuredPage: 1, preferHorizontal: true, isFinalAttempt: false)
        book.acceptLayoutPageCount(4, measuredPage: 1, preferHorizontal: true, isFinalAttempt: false)

        // Closing an unchanged panel neither arms relayout echo nor calls navigator.submitPreferences.
        #expect(!book.submit(initialPrefs))
        #expect(spy.presentationChanges == 0)
        book.navigator(navigator, locationDidChange: p2)
        #expect(turns == 1)

        // A real preference change forwards once, suppresses during the relayout echo,
        // and lets turns hide again once the echo expires.
        let largerPrefs = EPUBPreferences(fontSize: 1.25, scroll: false)
        #expect(book.submit(largerPrefs))
        #expect(spy.presentationChanges == 1)
        book.navigator(navigator, locationDidChange: p3)
        #expect(turns == 1)

        #expect(!book.submit(largerPrefs))
        #expect(spy.presentationChanges == 1)

        clock = clock.addingTimeInterval(ReaderChromeAutoHide.relayoutEchoWindow + 0.05)
        book.navigator(navigator, locationDidChange: p4)
        #expect(turns == 2)
    }
}

private final class PresentationSpyDelegate: NSObject, EPUBNavigatorDelegate {
    var presentationChanges = 0
    func navigator(_: Navigator, presentError _: NavigatorError) {}
    func navigator(_: VisualNavigator, presentationDidChange _: VisualNavigatorPresentation) {
        presentationChanges += 1
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
