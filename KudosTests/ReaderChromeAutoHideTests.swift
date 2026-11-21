import Foundation
import Testing

#if os(iOS)
import ReadiumNavigator
import ReadiumShared
import UIKit
@testable import Kudos
@testable import ReadiumNavigator
#endif

#if os(iOS)
/// T-562b / T-562f (owner, after Apple Books): the reader's controls hide only when the
/// reader's own input commits a page turn, reported once by the input path: an accepted
/// edge tap / key / page-turner, a Slide or Curl drag the release tracker commits, or a
/// trackpad Slide turn. A reflow, link, jump, scrub, cancelled drag or rejected input
/// never hides them; nothing hides them while something is open over the page or
/// VoiceOver runs; every show and hide fades.
@MainActor
struct ReaderChromeAutoHideTests {
    private let href1 = AnyURL(string: "OEBPS/chapter1.xhtml")!
    private let href2 = AnyURL(string: "OEBPS/chapter2.xhtml")!

    private func loc(_ progression: Double, _ position: Int, chapter: Int = 1) -> Locator {
        Locator(
            href: chapter == 1 ? href1 : href2, mediaType: .xhtml,
            locations: .init(progression: progression, position: position)
        )
    }

    /// Polls until `done` (a hosted gesture resolves on its own Task).
    private func wait(_ done: () -> Bool) async throws {
        for _ in 0 ..< 400 where !done() {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func fastTracker(_ book: ReadiumBook) -> ReaderCommittedGestureTracker {
        let tracker = book.committedGestureTracker
        tracker.pollNanoseconds = 2_000_000
        tracker.maxPolls = 25
        return tracker
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

    // MARK: - No inference from settles

    @Test func settlesAloneNeverHide() throws {
        // Reflow, late link destination, chapter change, measured page change, viewport
        // change: none of them is input, so none reports a turn.
        let book = ReadiumBook()
        let nav = AutoHideTestNavigator()
        book.seedInitialPreferences(EPUBPreferences(scroll: false))
        var turns = 0
        book.onUserPageTurn = { turns += 1 }

        book.navigator(nav, locationDidChange: loc(0.0, 1))
        book.acceptLayoutPageCount(4, measuredPage: 1, preferHorizontal: true, isFinalAttempt: false)
        book.acceptLayoutPageCount(4, measuredPage: 1, preferHorizontal: true, isFinalAttempt: false)
        book.navigator(nav, locationDidChange: loc(0.25, 2))
        book.navigator(nav, locationDidChange: loc(0.50, 3))
        book.navigator(nav, locationDidChange: loc(0.0, 9, chapter: 2))
        // Reflow: the same anchor lands in another column (10 -> 9 pages, 201 -> 200 pages).
        book.navigator(nav, locationDidChange: loc(7.0 / 9.0, 10, chapter: 2))
        book.navigator(nav, locationDidChange: loc(99.0 / 200.0, 10, chapter: 2))
        // A link whose destination is reported long after the link was tapped.
        let link = ReadiumShared.Link(href: "OEBPS/chapter2.xhtml")
        #expect(book.navigator(DirectionalAutoHideTestNavigator(), shouldNavigateToLink: link))
        book.navigator(nav, locationDidChange: loc(0.0, 20, chapter: 2))
        #expect(turns == 0)
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

        // Closing an unchanged panel does not call navigator.submitPreferences.
        #expect(!book.submit(initialPrefs))
        #expect(spy.presentationChanges == 0)
        // A real preference change forwards once; repeating it does not.
        let largerPrefs = EPUBPreferences(fontSize: 1.25, scroll: false)
        #expect(book.submit(largerPrefs))
        #expect(spy.presentationChanges == 1)
        #expect(!book.submit(largerPrefs))
        #expect(spy.presentationChanges == 1)
    }

    // MARK: - Edge tap, key, page-turner

    @Test func anAcceptedKeyReportsOnceAndARejectedOneNever() async throws {
        let book = ReadiumBook()
        let nav = DirectionalAutoHideTestNavigator()
        book.bindPageTurns(to: nav)
        var turns = 0
        book.onUserPageTurn = { turns += 1 }

        nav.goBackwardResult = false
        #expect(await nav.sendKey(.arrowLeft) == false)
        #expect(turns == 0)

        nav.goForwardResult = true
        #expect(await nav.sendKey(.arrowRight))
        #expect(turns == 1)
        // The settle that follows is not a second report.
        book.navigator(nav, locationDidChange: loc(0.25, 2))
        #expect(turns == 1)
    }

    @Test func aJumpOrRelayoutBeginningMidTurnDropsTheTurn() async throws {
        let book = ReadiumBook()
        let nav = DirectionalAutoHideTestNavigator()
        book.bindPageTurns(to: nav)
        defer { book.cancelPageBoxRemeasure() }
        var turns = 0
        book.onUserPageTurn = { turns += 1 }
        nav.goForwardResult = true

        nav.onGoForward = {
            book.go(to: self.loc(0.9, 9))
            return true
        }
        _ = await nav.sendKey(.arrowRight)
        #expect(turns == 0)

        for _ in 0 ..< 60 where book.hasJumpInFlight { try await Task.sleep(nanoseconds: 10_000_000) }
        nav.onGoForward = {
            book.updatePageBoxGeometry(size: CGSize(width: 402, height: 874), safeInsets: .zero)
            return true
        }
        _ = await nav.sendKey(.arrowRight)
        #expect(turns == 0)

        nav.onGoForward = nil
        _ = await nav.sendKey(.arrowRight)
        #expect(turns == 1)
    }

    // MARK: - Drags and trackpad

    private func hostWithSlide() -> (host: UIView, scroll: RecordingPagedScrollView) {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let scroll = RecordingPagedScrollView(frame: host.bounds)
        scroll.isPagingEnabled = true
        scroll.contentSize = CGSize(width: 390 * 4, height: 844)
        host.addSubview(scroll)
        return (host, scroll)
    }

    @Test func aSlideDragReportsOnlyWhenItCommitsAndNeverWhenItSnapsBack() async throws {
        let book = ReadiumBook()
        let nav = AutoHideTestNavigator()
        let (host, scroll) = hostWithSlide()
        let tracker = fastTracker(book)
        tracker.attach(to: host)
        #expect(!scroll.recorder.recordedTargets.isEmpty)
        var turns = 0
        book.onUserPageTurn = { turns += 1 }
        book.navigator(nav, locationDidChange: loc(0.0, 1))

        // Cancelled: released back on page 0, then a reflow moves the page index.
        scroll.recorder.fire(.began)
        scroll.recorder.fire(.ended)
        try await wait { !tracker.hasPendingResolution }
        scroll.contentOffset = CGPoint(x: 390, y: 0)
        book.navigator(nav, locationDidChange: loc(0.25, 2))
        try await Task.sleep(nanoseconds: 30_000_000)
        #expect(turns == 0)

        // Committed: released onto the next page.
        scroll.contentOffset = .zero
        scroll.recorder.fire(.began)
        scroll.contentOffset = CGPoint(x: 390, y: 0)
        scroll.recorder.fire(.ended)
        try await wait { turns > 0 }
        #expect(turns == 1)
        try await wait { !tracker.hasPendingResolution }
        #expect(turns == 1)
    }

    @Test func aCurlDragReportsWhenItCommitsAndNotWhenItIsCancelled() async throws {
        let book = ReadiumBook()
        let nav = AutoHideTestNavigator()
        let (host, scroll) = hostWithSlide()
        let curl = RecordingPageCurlPan()
        host.addGestureRecognizer(curl)
        let tracker = fastTracker(book)
        tracker.maxPolls = 8
        tracker.attach(to: host)
        #expect(!curl.recordedTargets.isEmpty)
        var turns = 0
        book.onUserPageTurn = { turns += 1 }
        book.navigator(nav, locationDidChange: loc(0.0, 1))

        curl.fire(.began)
        curl.fire(.cancelled)
        try await wait { !tracker.hasPendingResolution }
        // A reflow after the cancelled drag has been given up on.
        scroll.contentOffset = CGPoint(x: 390, y: 0)
        try await Task.sleep(nanoseconds: 30_000_000)
        #expect(turns == 0)

        scroll.contentOffset = .zero
        curl.fire(.began)
        scroll.contentOffset = CGPoint(x: 780, y: 0)
        curl.fire(.ended)
        try await wait { turns > 0 }
        #expect(turns == 1)
    }

    @Test func aTrackpadSlideTurnReportsWhenItMovesThePage() async throws {
        let book = ReadiumBook()
        let nav = AutoHideTestNavigator()
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let trackpad = RecordingPan()
        trackpad.markIndirect()
        host.addGestureRecognizer(trackpad)
        let tracker = fastTracker(book)
        tracker.maxPolls = 8
        tracker.attach(to: host)
        #expect(tracker.hasObservedIndirectPan)
        #expect(!trackpad.recordedTargets.isEmpty)
        var turns = 0
        book.onUserPageTurn = { turns += 1 }
        book.navigator(nav, locationDidChange: loc(0.0, 1))

        // A scroll below Readium's threshold turns nothing.
        trackpad.fire(.began)
        trackpad.fire(.ended)
        try await wait { !tracker.hasPendingResolution }
        #expect(turns == 0)

        // A scroll that turns the page: Readium goes forward and reports the new place.
        trackpad.fire(.began)
        book.navigator(nav, locationDidChange: loc(0.25, 2))
        trackpad.fire(.ended)
        try await wait { turns > 0 }
        #expect(turns == 1)
    }

    @Test func aLinkOrJumpAfterTheDragEndsDropsIt() async throws {
        let book = ReadiumBook()
        let nav = DirectionalAutoHideTestNavigator()
        let (host, scroll) = hostWithSlide()
        let tracker = fastTracker(book)
        tracker.attach(to: host)
        var turns = 0
        book.onUserPageTurn = { turns += 1 }
        book.navigator(nav, locationDidChange: loc(0.0, 1))

        scroll.recorder.fire(.began)
        scroll.contentOffset = CGPoint(x: 390, y: 0)
        scroll.recorder.fire(.ended)
        _ = book.navigator(nav, shouldNavigateToLink: ReadiumShared.Link(href: "OEBPS/chapter2.xhtml"))
        try await wait { !tracker.hasPendingResolution }
        try await Task.sleep(nanoseconds: 30_000_000)
        #expect(turns == 0)
    }

    @Test func openWiresProductionDirectionalInputPathForAcceptedAndRejectedTurns() async throws {
        // Opens a real local EPUB through `ReadiumBook.open` (no manual `bindPageTurns`):
        // real touches and keys through Readium's `DirectionalNavigationAdapter`.
        let epubURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/demo_work.epub")
        let initialPrefs = EPUBPreferences(fontSize: 1.0, scroll: false)
        let book = ReadiumBook()
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

        for _ in 0 ..< 100 where book.settledLocationCount == 0 {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(book.settledLocationCount >= 1)
        #expect(book.committedGestureTracker.hasObservedGestures)

        var turns = 0
        book.onUserPageTurn = { turns += 1 }

        // Rejected left-edge tap AND key at the start of chapter 1 report nothing and
        // the rejected edge tap does not fall through to the centre-tap chrome toggle.
        book.chromeHidden = false
        let leftTouch = SyntheticTouch(location: CGPoint(x: 24, y: navigator.view.bounds.height / 2))
        navigator.touchesBegan([leftTouch], with: nil)
        try await Task.sleep(nanoseconds: 30_000_000)
        navigator.touchesEnded([leftTouch], with: nil)
        try await Task.sleep(nanoseconds: 50_000_000)
        let rejectedKey = await book.pageTurns.dispatchKeyEventForTesting(
            KeyEvent(phase: .down, key: .arrowLeft)
        )
        #expect(!rejectedKey)
        let current = try #require(book.currentLocator)
        book.navigator(AutoHideTestNavigator(), locationDidChange: current.copy(locations: {
            $0.progression = ($0.progression ?? 0) + 0.001
            $0.position = ($0.position ?? 1) + 1
        }))
        #expect(turns == 0)
        #expect(!book.chromeHidden)

        // An accepted right-edge tap, then an accepted key, each report once.
        let rightEdge = CGPoint(x: max(1, navigator.view.bounds.width - 24), y: navigator.view.bounds.height / 2)
        let rightTouch = SyntheticTouch(location: rightEdge)
        navigator.touchesBegan([rightTouch], with: nil)
        try await Task.sleep(nanoseconds: 30_000_000)
        navigator.touchesEnded([rightTouch], with: nil)
        try await wait { turns > 0 }
        #expect(turns == 1)

        let acceptedKey = await book.pageTurns.dispatchKeyEventForTesting(
            KeyEvent(phase: .down, key: .arrowRight)
        )
        #expect(acceptedKey)
        try await wait { turns > 1 }
        #expect(turns == 2)
    }
}

/// P1 (Codex review of T-562e): closing the reader while Readium still awaits an
/// animated edge turn must leave its in-flight pointer dispatch safe.
@MainActor
struct ReadiumPageTurnTeardownTests {
    @Test func releasingTheBindingMidTurnLeavesInFlightObserversSafe() async throws {
        let stub = DirectionalAutoHideTestNavigator()
        var gate: CheckedContinuation<Void, Never>?
        var turnStarted = false
        stub.onGoForward = {
            turnStarted = true
            await withCheckedContinuation { gate = $0 }
            return true
        }
        var controller: ReadiumPageTurnController? = ReadiumPageTurnController()
        controller?.bind(to: stub, toggleChrome: {})
        let observers = stub.observers.map(\.observer)
        #expect(observers.count >= 3)

        let pointer = Pointer.touch(TouchPointer(id: 1))
        let edge = CGPoint(x: 380, y: 400)
        let events = [
            PointerEvent(pointer: pointer, phase: .down, location: edge, modifiers: []),
            PointerEvent(pointer: pointer, phase: .up, location: edge, modifiers: []),
        ]
        // Mirrors Readium's `CompositeInputObserver`: every observer, later ones with `.cancel`.
        let dispatch = Task { @MainActor in
            for var event in events {
                for observer in observers where await observer.didReceive(event) {
                    event.phase = .cancel
                }
            }
        }
        for _ in 0 ..< 200 where !turnStarted { try await Task.sleep(nanoseconds: 5_000_000) }
        #expect(turnStarted)

        // The reader closes while the animated turn is still awaited.
        controller = nil
        gate?.resume()
        await dispatch.value
        for observer in observers {
            #expect(await observer.didReceive(events[1]) == false)
        }
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

    func markIndirect() {
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
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
    private(set) var observers: [(token: InputObservableToken, observer: any InputObserving)] = []

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
