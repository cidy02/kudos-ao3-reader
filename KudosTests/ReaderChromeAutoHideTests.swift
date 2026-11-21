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
        // A relayout echo holds a settle inferred from locator movement alone (T-562e: a
        // navigator-confirmed turn from after the relayout is not an echo; see below).
        #expect(!turn(from: page4, to: page5, relayoutEchoUntil: now.addingTimeInterval(0.3)))
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
        let nav = DirectionalAutoHideTestNavigator()
        var clock = Date(timeIntervalSinceReferenceDate: 20_000)
        book.autoHideNow = { clock }
        book.seedInitialPreferences(EPUBPreferences(scroll: false))
        book.bindPageTurns(to: nav)
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

        // A rejected directional input within the jump echo window must NOT let a
        // delayed jump echo settle bypass jump-echo suppression.
        nav.goBackwardResult = false
        let rejected = await nav.sendKey(.arrowLeft)
        #expect(!rejected)
        book.navigator(nav, locationDidChange: p3)
        #expect(turns == 0)

        // An accepted hardware key through the installed directional adapter within the
        // jump echo window hides controls.
        nav.goForwardResult = true
        let accepted = await nav.sendKey(.arrowRight)
        #expect(accepted)
        book.navigator(nav, locationDidChange: p2)
        #expect(turns == 1)

        // After the jump echo expires, non-explicit turns hide normally again.
        clock = clock.addingTimeInterval(ReaderChromeAutoHide.jumpEchoWindow)
        book.navigator(nav, locationDidChange: p4)
        #expect(turns == 2)
    }

    @Test func unmeasuredPagedPositionBoundaryCrossingDoesNotHide() async throws {
        let before = Place(href: "chapter1.xhtml", position: 2, progression: 0.250)
        let after = Place(href: "chapter1.xhtml", position: 3, progression: 0.251)
        let largerSameResource = Place(href: "chapter1.xhtml", position: 3, progression: 0.31)
        let nextChapter = Place(href: "chapter2.xhtml", position: 4, progression: 0.0)

        #expect(!turn(from: before, to: after, isPaged: true, pageCount: nil))
        #expect(!turn(from: before, to: largerSameResource, isPaged: true, pageCount: nil))
        #expect(turn(from: before, to: nextChapter, isPaged: true, pageCount: nil))
        #expect(turn(from: before, to: largerSameResource, isPaged: true, pageCount: nil, explicitUserTurn: true))

        // Live ReadiumBook before pageBarReady: position-boundary wobble stays silent;
        // accepted directional input and chapter change hide; rejected input stays silent.
        let book = ReadiumBook()
        let nav = DirectionalAutoHideTestNavigator()
        book.seedInitialPreferences(EPUBPreferences(scroll: false))
        book.bindPageTurns(to: nav)
        let ch1 = try #require(AnyURL(string: "OEBPS/chapter1.xhtml"))
        let ch2 = try #require(AnyURL(string: "OEBPS/chapter2.xhtml"))
        var turns = 0
        book.onUserPageTurn = { turns += 1 }

        book.navigator(nav, locationDidChange: Locator(href: ch1, mediaType: .xhtml, locations: .init(progression: 0.250, position: 2)))
        book.navigator(nav, locationDidChange: Locator(href: ch1, mediaType: .xhtml, locations: .init(progression: 0.251, position: 3)))
        #expect(!book.pageBarReady)
        #expect(turns == 0)

        // Accepted key turn through the installed directional path hides.
        nav.goForwardResult = true
        let accepted = await nav.sendKey(.arrowRight)
        #expect(accepted)
        book.navigator(nav, locationDidChange: Locator(href: ch1, mediaType: .xhtml, locations: .init(progression: 0.50, position: 4)))
        #expect(turns == 1)

        // Explicit attribution was consumed by the turn above; a later wobble stays silent.
        book.navigator(nav, locationDidChange: Locator(href: ch1, mediaType: .xhtml, locations: .init(progression: 0.501, position: 5)))
        #expect(turns == 1)

        // Rejected space key at boundary must NOT arm attribution for a subsequent wobble.
        nav.goForwardResult = false
        let rejected = await nav.sendKey(.space)
        #expect(!rejected)
        book.navigator(nav, locationDidChange: Locator(href: ch1, mediaType: .xhtml, locations: .init(progression: 0.502, position: 6)))
        #expect(turns == 1)

        // Cross-chapter navigation still hides even before pagination is measured.
        book.navigator(nav, locationDidChange: Locator(href: ch2, mediaType: .xhtml, locations: .init(progression: 0.0, position: 7)))
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

    @Test func committedTurnBeforePageBarReadyUsesViewportSpanAndIgnoresWobble() throws {
        // Finding 1 verify-first: before `pageBarReady` (~first 450 ms), Readium still
        // reports the visible page span (`first...last`) on `viewportDidChange` before
        // `locationDidChange`. A committed Slide swipe / Curl drag to the next visual
        // page must hide controls; a same-page wobble crossing a position boundary must not.
        let book = ReadiumBook()
        let nav = ViewportAutoHideTestNavigator()
        book.seedInitialPreferences(EPUBPreferences(scroll: false))
        let href = try #require(AnyURL(string: "OEBPS/chapter1.xhtml"))

        var turns = 0
        book.onUserPageTurn = { turns += 1 }

        // Opening settle on page 1 of a 4-page chapter (pageBarReady is still false).
        let vp1 = NavigatorViewport(
            resources: [.init(href: href, progression: 0.0 ... 0.25)],
            progression: 0.0 ... 0.25
        )
        nav.viewport = vp1
        book.navigator(nav, viewportDidChange: vp1)
        let loc1 = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 0.0, position: 1))
        book.navigator(nav, locationDidChange: loc1)
        #expect(!book.pageBarReady)
        #expect(turns == 0)

        // Same-page wobble crossing a position boundary stays silent.
        let vp1Wobble = NavigatorViewport(
            resources: [.init(href: href, progression: 0.002 ... 0.252)],
            progression: 0.002 ... 0.252
        )
        nav.viewport = vp1Wobble
        book.navigator(nav, viewportDidChange: vp1Wobble)
        let loc1Wobble = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 0.002, position: 2))
        book.navigator(nav, locationDidChange: loc1Wobble)
        #expect(turns == 0)

        // Committed Slide swipe / Curl drag to page 2 before `pageBarReady` hides controls.
        let vp2 = NavigatorViewport(
            resources: [.init(href: href, progression: 0.25 ... 0.50)],
            progression: 0.25 ... 0.50
        )
        nav.viewport = vp2
        book.navigator(nav, viewportDidChange: vp2)
        let loc2 = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 0.25, position: 2))
        book.navigator(nav, locationDidChange: loc2)
        #expect(!book.pageBarReady)
        #expect(turns == 1)
    }

    @Test func viewportSpanRulesCoverWobbleReflowSinglePageAndClampedLastPage() {
        let p1 = Place(href: "ch1", position: 1, progression: 0.0, viewportProgression: 0.0 ... 0.25)
        let p1Wobble = Place(href: "ch1", position: 2, progression: 0.002, viewportProgression: 0.002 ... 0.252)
        let p2 = Place(href: "ch1", position: 2, progression: 0.25, viewportProgression: 0.25 ... 0.50)

        #expect(turn(from: p1, to: p2, isPaged: true, pageCount: nil, explicitUserTurn: false))
        // Same-page wobble stays silent even if explicit attribution were live.
        #expect(!turn(from: p1, to: p1Wobble, isPaged: true, pageCount: nil, explicitUserTurn: true))

        // Single-page chapter (`0...1`) has no intra-chapter turns.
        let single1 = Place(href: "ch1", position: 1, progression: 0.0, viewportProgression: 0.0 ... 1.0)
        let singleWobble = Place(href: "ch1", position: 1, progression: 0.04, viewportProgression: 0.04 ... 1.0)
        #expect(!turn(from: single1, to: singleWobble, isPaged: true, pageCount: nil, explicitUserTurn: true))

        // Async font/image reflow shifting 20 -> 21 pages while staying on column 14 stays silent.
        let col14Of20 = Place(href: "ch1", position: 10, progression: 0.70, viewportProgression: 0.70 ... 0.75)
        let col14Of21 = Place(
            href: "ch1", position: 10, progression: 14.0 / 21.0,
            viewportProgression: (14.0 / 21.0) ... (15.0 / 21.0)
        )
        #expect(!turn(from: col14Of20, to: col14Of21, isPaged: true, pageCount: nil, explicitUserTurn: false))

        // Non-integer clamped last page still counts as a real turn.
        let penult = Place(href: "ch1", position: 3, progression: 0.5714, viewportProgression: 0.5714 ... 0.8571)
        let last = Place(href: "ch1", position: 4, progression: 0.8571, viewportProgression: 0.8571 ... 1.0)
        #expect(turn(from: penult, to: last, isPaged: true, pageCount: nil, explicitUserTurn: false))
    }

    @Test func committedSlideAndCurlGesturesHideDuringJumpEchoWhileCancelledStaySilent() async throws {
        let book = ReadiumBook()
        let nav = AutoHideTestNavigator()
        var clock = Date(timeIntervalSinceReferenceDate: 40_000)
        book.autoHideNow = { clock }
        book.seedInitialPreferences(EPUBPreferences(scroll: false))
        let href = try #require(AnyURL(string: "OEBPS/chapter1.xhtml"))

        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let spreadScroll = UIScrollView(frame: host.bounds)
        spreadScroll.isPagingEnabled = true
        spreadScroll.contentSize = CGSize(width: 390 * 4, height: 844)
        spreadScroll.contentOffset = .zero
        host.addSubview(spreadScroll)
        let curlPan = UIPanGestureRecognizer()
        host.addGestureRecognizer(curlPan)

        let tracker = book.committedGestureTracker
        tracker.observeSlideScrollView(spreadScroll)
        tracker.observeCurlPan(curlPan, in: host)

        var turns = 0
        book.onUserPageTurn = { turns += 1 }

        // Opening settle on page 1 (unmeasured, no viewport).
        let p1 = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 0.0, position: 1))
        let p1Wobble = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 0.002, position: 2))
        let p2 = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 0.25, position: 2))
        let p2Wobble = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 0.252, position: 3))
        let p3 = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 0.50, position: 3))

        book.navigator(nav, locationDidChange: p1)
        #expect(!book.pageBarReady)

        // Simulate a Contents/scrub jump that arms the 600 ms jump echo window.
        book.go(to: p1)
        await Task.yield()
        clock = clock.addingTimeInterval(0.15)

        // Cancelled Slide swipe (dragged, snapped back to page 0) stays silent.
        tracker.notePanStateChanged(spreadScroll.panGestureRecognizer, state: .began)
        spreadScroll.contentOffset = CGPoint(x: 0, y: 0)
        tracker.notePanStateChanged(spreadScroll.panGestureRecognizer, state: .ended)
        book.navigator(nav, locationDidChange: p1Wobble)
        #expect(turns == 0)

        // Committed Slide swipe (snapped to page 1) hides even before pageBarReady AND during jump echo.
        tracker.notePanStateChanged(spreadScroll.panGestureRecognizer, state: .began)
        spreadScroll.contentOffset = CGPoint(x: 390, y: 0)
        tracker.notePanStateChanged(spreadScroll.panGestureRecognizer, state: .ended)
        book.navigator(nav, locationDidChange: p2)
        #expect(turns == 1)

        // Arm another jump echo, then test Curl drag cancel vs commit.
        book.go(to: p2)
        await Task.yield()
        clock = clock.addingTimeInterval(0.15)

        // Cancelled Curl drag (reverted back to page 1) stays silent.
        tracker.notePanStateChanged(curlPan, state: .began)
        spreadScroll.contentOffset = CGPoint(x: 390, y: 0)
        tracker.notePanStateChanged(curlPan, state: .ended)
        book.navigator(nav, locationDidChange: p2Wobble)
        #expect(turns == 1)

        // Committed Curl drag (landed on page 2) hides even before pageBarReady AND during jump echo.
        tracker.notePanStateChanged(curlPan, state: .began)
        spreadScroll.contentOffset = CGPoint(x: 780, y: 0)
        tracker.notePanStateChanged(curlPan, state: .ended)
        book.navigator(nav, locationDidChange: p3)
        #expect(turns == 2)
    }

    @Test func rejectedGoBackwardDoesNotArmHideForSamePageSettle() async throws {
        // Finding 2 verify-first: a rejected backward turn (no navigator / end of book)
        // must not arm attribution that a same-page wobble consumes to hide controls.
        let book = ReadiumBook()
        let nav = AutoHideTestNavigator()
        book.seedInitialPreferences(EPUBPreferences(scroll: false))
        let href = try #require(AnyURL(string: "OEBPS/chapter1.xhtml"))

        var turns = 0
        book.onUserPageTurn = { turns += 1 }

        let start = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 0.250, position: 2))
        let wobble = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 0.251, position: 3))
        book.navigator(nav, locationDidChange: start)
        #expect(!book.pageBarReady)

        // Trigger a rejected backward move (navigator is nil -> moved == false), and a
        // same-page wobble arrives before/around the rejection settles.
        book.goBackward()
        book.navigator(nav, locationDidChange: wobble)
        await Task.yield()
        #expect(turns == 0)
    }

    @Test func directionalTurnSettleBeforeResultHoldsUntilConfirmedAndScopesPerAttempt() async throws {
        let book = ReadiumBook()
        let nav = DirectionalAutoHideTestNavigator()
        book.seedInitialPreferences(EPUBPreferences(scroll: false))
        book.bindPageTurns(to: nav)
        let href = try #require(AnyURL(string: "OEBPS/chapter1.xhtml"))

        var turns = 0
        book.onUserPageTurn = { turns += 1 }

        let p1 = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 0.0, position: 1))
        let p2 = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 0.25, position: 2))
        let wobble = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 0.251, position: 3))
        let p3 = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 0.50, position: 4))
        book.navigator(nav, locationDidChange: p1)
        #expect(!book.pageBarReady)

        // Case 1: settle arrives while `goForward` is still in flight; held until `true`.
        var turnsBeforeReturn = -1
        nav.onGoForward = {
            book.navigator(nav, locationDidChange: p2)
            turnsBeforeReturn = turns
            return true
        }
        let movedForward = await nav.sendKey(.arrowRight)
        #expect(movedForward)
        #expect(turnsBeforeReturn == 0)
        #expect(turns == 1)

        // Held candidate was already consumed on confirmation — a following wobble stays silent.
        book.navigator(nav, locationDidChange: wobble)
        #expect(turns == 1)

        // Case 2: settle arrives while `goBackward` is in flight, then move is rejected (`false`).
        let rejectedWobble = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 0.252, position: 4))
        nav.onGoBackward = {
            book.navigator(nav, locationDidChange: rejectedWobble)
            return false
        }
        let movedBackward = await nav.sendKey(.arrowLeft)
        #expect(!movedBackward)
        #expect(turns == 1)

        // Case 3: overlapping rejection does not clear an earlier successful move's attribution.
        nav.onGoForward = nil
        nav.onGoBackward = nil
        nav.goForwardResult = true
        nav.goBackwardResult = false
        #expect(await nav.sendKey(.arrowRight))
        #expect(!(await nav.sendKey(.arrowLeft)))
        book.navigator(nav, locationDidChange: p3)
        #expect(turns == 2)
    }

    // MARK: T-562e (Codex review of T-562d, round 2)

    @Test func confirmedTurnBypassesRelayoutWindowButInferredSettleDoesNot() {
        let later = now.addingTimeInterval(1)
        #expect(turn(from: page4, to: page5, explicitUserTurn: true, relayoutEchoUntil: later))
        #expect(!turn(from: page4, to: page5, explicitUserTurn: false, relayoutEchoUntil: later))
    }

    @Test func swipeOrKeyCommittedDuringRelayoutWindowHides() async throws {
        // Finding 1: after a geometry change (pagination unmeasured, relayout window
        // live) a navigator-confirmed key turn and a committed Slide swipe both hide.
        let book = ReadiumBook()
        let nav = DirectionalAutoHideTestNavigator()
        var clock = Date(timeIntervalSinceReferenceDate: 60_000)
        book.autoHideNow = { clock }
        book.seedInitialPreferences(EPUBPreferences(scroll: false))
        book.bindPageTurns(to: nav)
        defer { book.cancelPageBoxRemeasure() }
        let href = try #require(AnyURL(string: "OEBPS/chapter1.xhtml"))
        func loc(_ progression: Double, _ position: Int) -> Locator {
            Locator(href: href, mediaType: .xhtml, locations: .init(progression: progression, position: position))
        }

        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let scroll = RecordingPagedScrollView(frame: host.bounds)
        scroll.isPagingEnabled = true
        scroll.contentSize = CGSize(width: 390 * 4, height: 844)
        host.addSubview(scroll)
        book.committedGestureTracker.attach(to: host)

        var turns = 0
        book.onUserPageTurn = { turns += 1 }
        book.navigator(nav, locationDidChange: loc(0.0, 1))
        book.updatePageBoxGeometry(size: CGSize(width: 402, height: 874), safeInsets: .zero)
        #expect(!book.pageBarReady)
        clock = clock.addingTimeInterval(0.3)

        nav.goForwardResult = true
        nav.onGoForward = {
            book.navigator(nav, locationDidChange: loc(0.25, 2))
            return true
        }
        #expect(await nav.sendKey(.arrowRight))
        #expect(turns == 1)

        scroll.recorder.fire(.began)
        scroll.contentOffset = CGPoint(x: 390, y: 0)
        scroll.recorder.fire(.ended)
        book.navigator(nav, locationDidChange: loc(0.50, 3))
        #expect(turns == 2)
    }

    @Test func reflowMovingTheAnchorToAnotherColumnIsNotATurn() {
        // Finding 3: column 8 of 10 becomes column 7 of 9 when a late image or font
        // changes the page count; no user input, no measured pagination.
        let before = Place(href: "ch1", position: 5, progression: 0.80, viewportProgression: 0.80 ... 0.90)
        let after = Place(
            href: "ch1", position: 5, progression: 7.0 / 9.0,
            viewportProgression: (7.0 / 9.0) ... (8.0 / 9.0)
        )
        #expect(!turn(from: before, to: after, isPaged: true, pageCount: nil, explicitUserTurn: false))
        // A confirmed user turn that lands during the reflow still hides.
        #expect(turn(from: before, to: after, isPaged: true, pageCount: nil, explicitUserTurn: true))
    }

    @Test func followingAnInternalLinkDoesNotHide() async throws {
        // Finding 4: Readium follows internal links with its own `go(to:)`.
        let book = ReadiumBook()
        let nav = DirectionalAutoHideTestNavigator()
        var clock = Date(timeIntervalSinceReferenceDate: 70_000)
        book.autoHideNow = { clock }
        book.seedInitialPreferences(EPUBPreferences(scroll: false))
        let ch1 = try #require(AnyURL(string: "OEBPS/chapter1.xhtml"))
        let ch2 = try #require(AnyURL(string: "OEBPS/chapter2.xhtml"))
        let a = Locator(href: ch1, mediaType: .xhtml, locations: .init(progression: 0.0, position: 1))
        let b = Locator(href: ch2, mediaType: .xhtml, locations: .init(progression: 0.0, position: 9))
        let ch3 = try #require(AnyURL(string: "OEBPS/chapter3.xhtml"))
        let c = Locator(href: ch3, mediaType: .xhtml, locations: .init(progression: 0.0, position: 17))

        var turns = 0
        book.onUserPageTurn = { turns += 1 }
        book.navigator(nav, locationDidChange: a)
        clock = clock.addingTimeInterval(5) // opening and relayout windows long gone

        let link = ReadiumShared.Link(href: "OEBPS/chapter2.xhtml")
        #expect(book.navigator(nav, shouldNavigateToLink: link))
        clock = clock.addingTimeInterval(0.4)
        book.navigator(nav, locationDidChange: b)
        book.navigator(nav, didJumpTo: b)
        #expect(turns == 0)

        // Once the echo expires an ordinary page turn hides again.
        clock = clock.addingTimeInterval(ReaderChromeAutoHide.linkJumpLead + 0.1)
        book.navigator(nav, locationDidChange: c)
        #expect(turns == 1)
    }

    @Test func slideAndCurlPansReachTheTrackerThroughTheirProductionActionTargets() async throws {
        // Finding 5: deliver pans through the targets `attach` really registered (the
        // test recognizers record `addTarget`); removing either `addTarget` fails this.
        let book = ReadiumBook()
        let nav = AutoHideTestNavigator()
        var clock = Date(timeIntervalSinceReferenceDate: 80_000)
        book.autoHideNow = { clock }
        book.seedInitialPreferences(EPUBPreferences(scroll: false))
        let href = try #require(AnyURL(string: "OEBPS/chapter1.xhtml"))
        func loc(_ progression: Double, _ position: Int) -> Locator {
            Locator(href: href, mediaType: .xhtml, locations: .init(progression: progression, position: position))
        }

        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let scroll = RecordingPagedScrollView(frame: host.bounds)
        scroll.isPagingEnabled = true
        scroll.contentSize = CGSize(width: 390 * 4, height: 844)
        host.addSubview(scroll)
        let curl = RecordingPageCurlPan()
        host.addGestureRecognizer(curl)
        book.committedGestureTracker.attach(to: host)
        #expect(!scroll.recorder.recordedTargets.isEmpty)
        #expect(!curl.recordedTargets.isEmpty)

        var turns = 0
        book.onUserPageTurn = { turns += 1 }
        book.navigator(nav, locationDidChange: loc(0.0, 1))
        book.go(to: loc(0.0, 1))
        await Task.yield()
        clock = clock.addingTimeInterval(0.15)

        scroll.recorder.fire(.began)
        scroll.contentOffset = CGPoint(x: 390, y: 0)
        scroll.recorder.fire(.ended)
        book.navigator(nav, locationDidChange: loc(0.25, 2))
        #expect(turns == 1)

        book.go(to: loc(0.25, 2))
        await Task.yield()
        clock = clock.addingTimeInterval(0.15)
        curl.fire(.began)
        scroll.contentOffset = CGPoint(x: 780, y: 0)
        curl.fire(.ended)
        book.navigator(nav, locationDidChange: loc(0.50, 3))
        #expect(turns == 2)
    }

    @Test func openWiresProductionDirectionalInputPathForAcceptedAndRejectedTurns() async throws {
        // Finding 3 regression: opens a real local EPUB through `ReadiumBook.open`
        // (no manual `bindPageTurns`, no direct `beginExplicitUserTurn` calls).
        // Removing `bindPageTurns` in `open(...)` or disconnecting the tracking
        // callbacks in `ReadiumPageTurnController.bind` fails this test.
        let epubURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/demo_work.epub")
        let initialPrefs = EPUBPreferences(fontSize: 1.0, scroll: false)
        let book = ReadiumBook()
        var clock = Date(timeIntervalSinceReferenceDate: 50_000)
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
        #expect(book.pageTurns.hasInstalledDirectionalObservers)

        let navigator = try #require(book.navigator)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: frame)
        window.frame = frame
        let previousRoot = window.rootViewController
        window.rootViewController = navigator
        window.isHidden = false
        window.layoutIfNeeded()
        defer {
            window.rootViewController = previousRoot
            window.isHidden = true
        }

        // Wait for Readium to render and report the opening settle on page 1 of chapter 1.
        for _ in 0 ..< 100 where book.settledLocationCount == 0 {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(book.settledLocationCount >= 1)
        #expect(book.committedGestureTracker.hasObservedGestures)

        // Keep pagination unmeasured so turn attribution (not pageCount) is exercised.
        book.cancelPageBoxRemeasure()
        book.clearVisualPageMetrics()
        #expect(!book.pageBarReady)

        var turns = 0
        book.onUserPageTurn = { turns += 1 }

        // 1. Rejected left-edge tap AND key at start of chapter 1 (goLeft returns false)
        // must NOT arm a hide that a subsequent same-page wobble consumes, and the
        // rejected edge tap must not fall through to the centre-tap chrome toggle.
        book.chromeHidden = false
        let leftEdge = CGPoint(x: 24, y: navigator.view.bounds.height / 2)
        let leftTouch = SyntheticTouch(location: leftEdge)
        navigator.touchesBegan([leftTouch], with: nil)
        try await Task.sleep(nanoseconds: 30_000_000)
        navigator.touchesEnded([leftTouch], with: nil)
        try await Task.sleep(nanoseconds: 50_000_000)
        let rejectedKey = await book.pageTurns.dispatchKeyEventForTesting(
            KeyEvent(phase: .down, key: .arrowLeft)
        )
        #expect(!rejectedKey)
        let current = try #require(book.currentLocator)
        let wobble = current.copy(locations: {
            $0.progression = ($0.progression ?? 0) + 0.001
            $0.position = ($0.position ?? 1) + 1
        })
        book.navigator(AutoHideTestNavigator(), locationDidChange: wobble)
        #expect(turns == 0)
        #expect(!book.chromeHidden)

        // 2. Arm a jump echo, then fire a REAL right-edge tap directly through
        // `EPUBNavigatorViewController.touchesBegan`/`touchesEnded` -> Readium's
        // `DirectionalNavigationAdapter` -> `ReadiumBook`'s production callback.
        // Only the live production callback allows this turn to bypass jump echo.
        book.go(to: current)
        for _ in 0 ..< 60 where book.hasJumpInFlight {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        #expect(!book.hasJumpInFlight)
        clock = clock.addingTimeInterval(0.15)
        let rightEdge = CGPoint(x: max(1, navigator.view.bounds.width - 24), y: navigator.view.bounds.height / 2)
        let rightTouch = SyntheticTouch(location: rightEdge)
        navigator.touchesBegan([rightTouch], with: nil)
        try await Task.sleep(nanoseconds: 30_000_000)
        navigator.touchesEnded([rightTouch], with: nil)

        // Wait for Readium's settled `locationDidChange` from the accepted right-edge tap.
        for _ in 0 ..< 80 where turns == 0 {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(turns == 1)

        // 3. Arm another jump echo on page 2, then fire an accepted hardware key
        // (`.arrowLeft`) through the installed production `DirectionalNavigationAdapter`.
        let onPage2 = try #require(book.currentLocator)
        book.go(to: onPage2)
        for _ in 0 ..< 60 where book.hasJumpInFlight {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        #expect(!book.hasJumpInFlight)
        clock = clock.addingTimeInterval(0.15)
        let acceptedKey = await book.pageTurns.dispatchKeyEventForTesting(
            KeyEvent(phase: .down, key: .arrowLeft)
        )
        #expect(acceptedKey)
        for _ in 0 ..< 80 where turns == 1 {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(turns == 2)
    }
}

/// Records the target/action pairs `addTarget` registers and lets a test fire them
/// with a chosen state, so a pan reaches the tracker the way UIKit would deliver it.
private class RecordingPan: UIPanGestureRecognizer {
    private(set) var recordedTargets: [(target: AnyObject, action: Selector)] = []
    weak var hostView: UIView?
    private var forced: UIGestureRecognizer.State = .possible

    override var state: UIGestureRecognizer.State {
        get { forced }
        set { forced = newValue }
    }

    override var view: UIView? { hostView ?? super.view }

    override func addTarget(_ target: Any, action: Selector) {
        super.addTarget(target, action: action)
        if let object = target as? AnyObject { recordedTargets.append((object, action)) }
    }

    func fire(_ newState: UIGestureRecognizer.State) {
        forced = newState
        for (target, action) in recordedTargets {
            _ = (target as? NSObject)?.perform(action, with: self)
        }
    }
}

private final class RecordingPageCurlPan: RecordingPan {}

private final class RecordingPagedScrollView: UIScrollView {
    let recorder = RecordingPan()
    override var panGestureRecognizer: UIPanGestureRecognizer { recorder }
    override init(frame: CGRect) {
        super.init(frame: frame)
        recorder.hostView = self
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}

private final class SyntheticTouch: UITouch {
    private let point: CGPoint

    init(location: CGPoint) {
        self.point = location
        super.init()
    }

    override var type: UITouch.TouchType { .direct }

    override func location(in view: UIView?) -> CGPoint { point }
}

private final class DirectionalAutoHideTestNavigator: @preconcurrency VisualNavigator {
    let publication = Publication(manifest: Manifest())
    let view: UIView! = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    var presentation = VisualNavigatorPresentation(readingProgression: .ltr, scroll: false, axis: .horizontal)
    var currentLocation: Locator?
    var goForwardResult = false
    var goBackwardResult = false
    var onGoForward: (@MainActor () async -> Bool)?
    var onGoBackward: (@MainActor () async -> Bool)?
    private var observers: [(token: InputObservableToken, observer: any InputObserving)] = []

    func addObserver(_ observer: any InputObserving) -> InputObservableToken {
        let token = InputObservableToken()
        observers.append((token, observer))
        return token
    }

    func removeObserver(_ token: InputObservableToken) {
        observers.removeAll { $0.token == token }
    }

    func go(to locator: Locator, options: NavigatorGoOptions) async -> Bool { false }
    func go(to link: ReadiumShared.Link, options: NavigatorGoOptions) async -> Bool { false }

    func goForward(options: NavigatorGoOptions) async -> Bool {
        if let onGoForward { return await onGoForward() }
        return goForwardResult
    }

    func goBackward(options: NavigatorGoOptions) async -> Bool {
        if let onGoBackward { return await onGoBackward() }
        return goBackwardResult
    }

    @discardableResult
    func sendKey(_ key: Key) async -> Bool {
        var event = KeyEvent(phase: .down, key: key)
        var handled = false
        for (_, observer) in observers {
            if await observer.didReceive(event) {
                handled = true
                event.phase = .cancel
            }
        }
        return handled
    }
}

private final class ViewportAutoHideTestNavigator: @preconcurrency ViewportObservingNavigator {
    let publication = Publication(manifest: Manifest())
    let view: UIView! = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    var presentation = VisualNavigatorPresentation(readingProgression: .ltr, scroll: false, axis: .horizontal)
    var currentLocation: Locator? { nil }
    var viewport: NavigatorViewport?
    func addObserver(_ observer: InputObserving) -> InputObservableToken { InputObservableToken() }
    func removeObserver(_ token: InputObservableToken) {}
    func go(to locator: Locator, options: NavigatorGoOptions) async -> Bool { false }
    func go(to link: ReadiumShared.Link, options: NavigatorGoOptions) async -> Bool { false }
    func goForward(options: NavigatorGoOptions) async -> Bool { false }
    func goBackward(options: NavigatorGoOptions) async -> Bool { false }
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
