#if os(iOS)
import Foundation
import ReadiumNavigator
import ReadiumShared
import UIKit
import WebKit

/// Edge-zone taps and hardware keys for one open book, on stock Readium.
///
/// The navigator does not retain a `DirectionalNavigationAdapter`, so this
/// object does. The centre-tap chrome toggle is registered *after* `bind(to:)`.
/// Readium delivers a handled edge tap to later observers as `.cancel`, and
/// the activate recogniser treats that as not a tap, so the bars stay put.
/// A centre tap is not an edge, the adapter returns false, and the bars toggle.
///
/// Scroll mode ignores edge taps (`ignoreWhileScrolling`, Readium's default).
/// Keys still move. `animatedTransition` is false in scroll mode and for None
/// (and, for Fast Fade and Curl, with Reduce Motion). Slide, Fast Fade and Curl
/// animate in paged mode; Slide under Reduce Motion becomes a Fast Fade in the fork.
/// Progress is not written here. Readium reports one `locationDidChange` when
/// the turn settles, and that remains the only save.
@MainActor
final class ReadiumPageTurnController {
    private var adapter: DirectionalNavigationAdapter?
    private var trackingNavigator: DirectionalTurnTrackingNavigator?
    private var chromeToken: InputObservableToken?
    private weak var boundNavigator: (any VisualNavigator)?
    private var observers: [NSObjectProtocol] = []

    /// Options for `goForward` / `goBackward`. Refreshes first so a style,
    /// layout or Reduce Motion change applies to this call even if the
    /// notification has not been delivered yet.
    var goOptions: NavigatorGoOptions {
        refresh()
        return NavigatorGoOptions(animated: adapter?.animatedTransition ?? false)
    }

    func bind(
        to navigator: any VisualNavigator,
        toggleChrome: @escaping @MainActor () -> Void,
        onBeginUserTurn: @escaping @MainActor () -> UInt64 = { 0 },
        onEndUserTurn: @escaping @MainActor (UInt64, Bool) -> Void = { _, _ in }
    ) {
        adapter?.unbind()
        adapter = nil
        trackingNavigator = nil
        if let chromeToken, let boundNavigator {
            boundNavigator.removeObserver(chromeToken)
        }
        chromeToken = nil
        // Defaults: horizontal edges (30% of the width, at least 80 pt),
        // ignore taps while scrolling, arrows and space. That is Readium's
        // own edge policy — not a second set of zones. Wrapping `navigator`
        // lets us observe whether Readium accepted or rejected each move
        // (`moved: Bool`) without modifying `DirectionalNavigationAdapter`.
        let proxy = DirectionalTurnTrackingNavigator(
            base: navigator,
            onBeginTurn: onBeginUserTurn,
            onEndTurn: onEndUserTurn
        )
        let adapter = DirectionalNavigationAdapter(animatedTransition: false)
        adapter.bind(to: proxy)
        chromeToken = navigator.addObserver(.activate { _ in
            toggleChrome()
            return true
        })
        self.trackingNavigator = proxy
        self.adapter = adapter
        boundNavigator = navigator
        refresh()
        startObserving()
    }

    /// True once `DirectionalNavigationAdapter` registered its input observers
    /// through the turn-tracking proxy.
    var hasInstalledDirectionalObservers: Bool {
        !(trackingNavigator?.installedObservers.isEmpty ?? true)
    }

    /// Drives the exact `InputObserving` instances registered by `DirectionalNavigationAdapter`
    /// on the bound navigator. Used by regression tests to verify the production wiring.
    @discardableResult
    func dispatchKeyEventForTesting(_ event: KeyEvent) async -> Bool {
        guard let proxy = trackingNavigator else { return false }
        var handled = false
        var current = event
        for (_, observer) in proxy.installedObservers {
            if await observer.didReceive(current) {
                handled = true
                current.phase = .cancel
            }
        }
        return handled
    }

    func refresh() {
        let style = ReaderPageTurnStyle.stored(in: .standard)
        let mode = ReadingMode(rawValue: UserDefaults.standard.string(forKey: "readerMode") ?? "") ?? .scroll
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        adapter?.animatedTransition = ReaderPageTurnPolicy.animatedTransition(
            style: style,
            readingMode: mode,
            reduceMotion: reduceMotion
        )
    }

    private func startObserving() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: UserDefaults.standard,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            },
            center.addObserver(
                forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            },
        ]
    }

    isolated deinit {
        let center = NotificationCenter.default
        for token in observers {
            center.removeObserver(token)
        }
    }
}

/// Proxies a `VisualNavigator` for `DirectionalNavigationAdapter` so each edge tap
/// or keyboard navigation reports both its start token and Readium's `moved: Bool`
/// result back to `ReadiumBook`.
@MainActor
final class DirectionalTurnTrackingNavigator: VisualNavigator {
    private weak var base: (any VisualNavigator)?
    private let onBeginTurn: @MainActor () -> UInt64
    private let onEndTurn: @MainActor (UInt64, Bool) -> Void
    private(set) var installedObservers: [(token: InputObservableToken, observer: any InputObserving)] = []
    /// Directional moves begun so far; lets an observer wrapper see whether one call
    /// matched an edge zone, whether or not Readium then accepted the move.
    private(set) var beganTurnCount = 0

    init(
        base: any VisualNavigator,
        onBeginTurn: @escaping @MainActor () -> UInt64,
        onEndTurn: @escaping @MainActor (UInt64, Bool) -> Void
    ) {
        self.base = base
        self.onBeginTurn = onBeginTurn
        self.onEndTurn = onEndTurn
    }

    var publication: Publication {
        base?.publication ?? Publication(manifest: Manifest())
    }

    var currentLocation: Locator? {
        base?.currentLocation
    }

    var view: UIView! {
        base?.view
    }

    var presentation: VisualNavigatorPresentation {
        base?.presentation ?? VisualNavigatorPresentation(
            readingProgression: .ltr, scroll: false, axis: .horizontal
        )
    }

    @discardableResult
    func addObserver(_ observer: any InputObserving) -> InputObservableToken {
        let wrapped = EdgeActivationObserver(inner: observer, proxy: self)
        let token = base?.addObserver(wrapped) ?? InputObservableToken()
        installedObservers.append((token, wrapped))
        return token
    }

    func removeObserver(_ token: InputObservableToken) {
        installedObservers.removeAll { $0.token == token }
        base?.removeObserver(token)
    }

    @discardableResult
    func go(to locator: Locator, options: NavigatorGoOptions) async -> Bool {
        await base?.go(to: locator, options: options) ?? false
    }

    @discardableResult
    func go(to link: ReadiumShared.Link, options: NavigatorGoOptions) async -> Bool {
        await base?.go(to: link, options: options) ?? false
    }

    @discardableResult
    func goForward(options: NavigatorGoOptions) async -> Bool {
        guard let base else { return false }
        return await track { await base.goForward(options: options) }
    }

    @discardableResult
    func goBackward(options: NavigatorGoOptions) async -> Bool {
        guard let base else { return false }
        return await track { await base.goBackward(options: options) }
    }

    @discardableResult
    func goLeft(options: NavigatorGoOptions) async -> Bool {
        guard let base else { return false }
        return await track { await base.goLeft(options: options) }
    }

    @discardableResult
    func goRight(options: NavigatorGoOptions) async -> Bool {
        guard let base else { return false }
        return await track { await base.goRight(options: options) }
    }

    func firstVisibleElementLocator() async -> Locator? {
        await base?.firstVisibleElementLocator()
    }

    private func track(_ move: () async -> Bool) async -> Bool {
        beganTurnCount += 1
        let token = onBeginTurn()
        let moved = await move()
        onEndTurn(token, moved)
        return moved
    }
}

/// Wraps one of `DirectionalNavigationAdapter`'s observers. A pointer event that
/// landed in an edge zone starts a directional move whether or not Readium accepts
/// it; Readium reports only `moved`, so a rejected edge tap (first page, last page)
/// would reach the later centre-tap observer and toggle the controls. Consuming the
/// event here keeps an edge tap an edge tap. Keys pass through untouched.
///
/// The proxy is weak: Readium's in-flight pointer dispatch holds these observers past
/// the reader's close (an animated edge turn is still awaited), so a released binding
/// must answer `false`, not trap.
@MainActor
final class EdgeActivationObserver: InputObserving {
    private let inner: any InputObserving
    private weak var proxy: DirectionalTurnTrackingNavigator?

    init(inner: any InputObserving, proxy: DirectionalTurnTrackingNavigator) {
        self.inner = inner
        self.proxy = proxy
    }

    func didReceive(_ event: PointerEvent) async -> Bool {
        guard let proxy else { return false }
        let before = proxy.beganTurnCount
        let handled = await inner.didReceive(event)
        return handled || proxy.beganTurnCount != before
    }

    func didReceive(_ event: KeyEvent) async -> Bool {
        await inner.didReceive(event)
    }
}

/// Passively observes the inputs Readium turns pages with other than edge taps and
/// keys, and reports a turn exactly once when the input has committed one (T-562f):
/// a Slide paging scroll view or Curl pan recognizer released onto another page or
/// chapter, and a trackpad / scroll-wheel Slide turn (Readium's indirect-scroll pan).
/// A drag that snaps back to its starting page reports nothing. A jump, scrub, link,
/// relayout or close bumps `currentGeneration`, which drops every gesture in flight.
@MainActor
final class ReaderCommittedGestureTracker: NSObject {
    /// How often an ended gesture is checked, and for how many checks. Covers Slide
    /// deceleration, Curl's commit spring and the animated trackpad turn.
    var pollNanoseconds: UInt64 = 50_000_000
    var maxPolls = 30

    private struct WeakBox<T: AnyObject> {
        weak var value: T?
    }

    private enum GestureOrigin {
        case pagedScroll(scrollView: WeakBox<UIScrollView>, startPage: Int, startHref: String?)
        case curl(
            spreadScrollView: WeakBox<UIScrollView>,
            startSpreadPage: Int?,
            paginationScrollView: WeakBox<UIScrollView>,
            startPaginationPage: Int?,
            startHref: String?
        )
        case indirect(startPlace: String?)
    }

    private struct ActiveGesture {
        var origin: GestureOrigin
        var generation: UInt64
    }

    private enum Verdict {
        case committed, cancelled, undecided
    }

    var isInteractionBlocked: () -> Bool = { false }
    var currentGeneration: () -> UInt64 = { 0 }
    var currentHref: () -> String? = { nil }
    /// Chapter, position and progression of the settled locator, as one comparable key.
    var currentPlaceKey: () -> String? = { nil }
    var onCommit: () -> Void = {}

    private weak var rootView: UIView?
    private let observedPans = NSHashTable<UIPanGestureRecognizer>.weakObjects()
    private let curlPans = NSHashTable<UIPanGestureRecognizer>.weakObjects()
    private let indirectPans = NSHashTable<UIPanGestureRecognizer>.weakObjects()
    private var activeGestures: [ObjectIdentifier: ActiveGesture] = [:]
    private var resolutions: [UInt64: Task<Void, Never>] = [:]
    private var nextResolution: UInt64 = 0

    /// Idempotently attaches passive targets to paged scroll views (Slide), Readium's
    /// `PageCurlPanRecognizer` (Curl) and its indirect-scroll pan (trackpad Slide).
    func attach(to rootView: UIView) {
        self.rootView = rootView
        walkAndAttach(in: rootView)
    }

    /// Directly observes a paged `UIScrollView`'s pan recognizer (also used by tests).
    func observeSlideScrollView(_ scrollView: UIScrollView) {
        observe(scrollView.panGestureRecognizer)
    }

    /// Directly observes a Curl `UIPanGestureRecognizer` inside `rootView` (also used by tests).
    func observeCurlPan(_ pan: UIPanGestureRecognizer, in rootView: UIView) {
        self.rootView = rootView
        curlPans.add(pan)
        observe(pan)
    }

    /// Directly observes the indirect-scroll (trackpad / mouse wheel) pan.
    func observeIndirectPan(_ pan: UIPanGestureRecognizer) {
        indirectPans.add(pan)
        observe(pan)
    }

    private func observe(_ pan: UIPanGestureRecognizer) {
        guard !observedPans.contains(pan) else { return }
        observedPans.add(pan)
        pan.addTarget(self, action: #selector(handlePan(_:)))
    }

    /// Records the state of a pan gesture (production action target + test entry point).
    func notePanStateChanged(_ pan: UIPanGestureRecognizer, state overrideState: UIGestureRecognizer.State? = nil) {
        let state = overrideState ?? pan.state
        if indirectPans.contains(pan) {
            handleIndirectPan(pan, state: state)
        } else if curlPans.contains(pan) {
            handleCurlPan(pan, state: state)
        } else if let scrollView = pan.view as? UIScrollView {
            handleSlidePan(pan, scrollView: scrollView, state: state)
        }
    }

    func invalidate() {
        activeGestures.removeAll()
        for task in resolutions.values { task.cancel() }
        resolutions.removeAll()
    }

    /// True once at least one Slide scroll view or Curl pan recognizer has been attached.
    var hasObservedGestures: Bool {
        observedPans.anyObject != nil
    }

    /// True while an ended gesture is still waiting to be committed or dropped.
    var hasPendingResolution: Bool {
        !resolutions.isEmpty
    }

    /// True once Readium's indirect-scroll pan has been attached.
    var hasObservedIndirectPan: Bool {
        indirectPans.anyObject != nil
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        notePanStateChanged(pan)
    }

    private static func isIndirectScrollPan(_ pan: UIPanGestureRecognizer) -> Bool {
        let types = pan.allowedTouchTypes.map(\.intValue)
        return types == [UITouch.TouchType.indirect.rawValue]
    }

    private func walkAndAttach(in view: UIView) {
        if let scrollView = view as? UIScrollView,
           scrollView.isPagingEnabled || scrollView.superview is WKWebView {
            observeSlideScrollView(scrollView)
        }
        if let recognizers = view.gestureRecognizers {
            for recognizer in recognizers {
                guard let pan = recognizer as? UIPanGestureRecognizer else { continue }
                if String(describing: type(of: pan)).contains("PageCurl"), let rootView {
                    observeCurlPan(pan, in: rootView)
                } else if Self.isIndirectScrollPan(pan) {
                    observeIndirectPan(pan)
                }
            }
        }
        for subview in view.subviews {
            walkAndAttach(in: subview)
        }
    }

    private func handleSlidePan(
        _ pan: UIPanGestureRecognizer,
        scrollView: UIScrollView,
        state: UIGestureRecognizer.State
    ) {
        let key = ObjectIdentifier(pan)
        switch state {
        case .began:
            guard scrollView.isPagingEnabled, !isInteractionBlocked(),
                  let startPage = Self.startingPageIndex(of: scrollView, pan: pan) else {
                activeGestures.removeValue(forKey: key)
                return
            }
            activeGestures[key] = ActiveGesture(
                origin: .pagedScroll(
                    scrollView: WeakBox(value: scrollView),
                    startPage: startPage,
                    startHref: currentHref()
                ),
                generation: currentGeneration()
            )
        case .ended:
            finish(key)
        case .cancelled, .failed:
            activeGestures.removeValue(forKey: key)
        default:
            break
        }
    }

    private func handleCurlPan(_ pan: UIPanGestureRecognizer, state: UIGestureRecognizer.State) {
        let key = ObjectIdentifier(pan)
        switch state {
        case .began:
            guard !isInteractionBlocked() else {
                activeGestures.removeValue(forKey: key)
                return
            }
            let spreadScroll = rootView.flatMap(Self.primarySpreadScrollView(in:))
            let paginationScroll = rootView.flatMap(Self.paginationScrollView(in:))
            activeGestures[key] = ActiveGesture(
                origin: .curl(
                    spreadScrollView: WeakBox(value: spreadScroll),
                    startSpreadPage: spreadScroll.flatMap(Self.snappedPageIndex(of:)),
                    paginationScrollView: WeakBox(value: paginationScroll),
                    startPaginationPage: paginationScroll.flatMap(Self.snappedPageIndex(of:)),
                    startHref: currentHref()
                ),
                generation: currentGeneration()
            )
        case .ended, .cancelled:
            // Readium's `PageCurlPanStateMachine.release` can still commit a drag
            // past `distanceCommit` when UIKit ends it via `.cancelled` (e.g. edge exit),
            // so the outcome is read from the pages, not from the state.
            finish(key)
        case .failed:
            activeGestures.removeValue(forKey: key)
        default:
            break
        }
    }

    private func handleIndirectPan(_ pan: UIPanGestureRecognizer, state: UIGestureRecognizer.State) {
        let key = ObjectIdentifier(pan)
        switch state {
        case .began:
            guard !isInteractionBlocked() else {
                activeGestures.removeValue(forKey: key)
                return
            }
            // Readium turns the page itself once the scroll passes its threshold;
            // `began` fixes where the reader was.
            activeGestures[key] = ActiveGesture(
                origin: .indirect(startPlace: currentPlaceKey()),
                generation: currentGeneration()
            )
        case .ended:
            finish(key)
        case .cancelled, .failed:
            activeGestures.removeValue(forKey: key)
        default:
            break
        }
    }

    /// Resolves an ended gesture at its own completion: reports at the moment the
    /// pages show it committed, or drops it when it snapped back / never turned.
    private func finish(_ key: ObjectIdentifier) {
        guard let active = activeGestures.removeValue(forKey: key),
              active.generation == currentGeneration(),
              !isInteractionBlocked() else { return }
        nextResolution &+= 1
        let id = nextResolution
        resolutions[id] = Task { @MainActor [weak self] in
            var polls = 0
            while let self, !Task.isCancelled {
                guard active.generation == currentGeneration(), !isInteractionBlocked() else { break }
                switch verdict(of: active.origin) {
                case .committed:
                    resolutions.removeValue(forKey: id)
                    onCommit()
                    return
                case .cancelled:
                    resolutions.removeValue(forKey: id)
                    return
                case .undecided:
                    break
                }
                polls += 1
                if polls >= maxPolls { break }
                try? await Task.sleep(nanoseconds: pollNanoseconds)
            }
            self?.resolutions.removeValue(forKey: id)
        }
    }

    private func verdict(of origin: GestureOrigin) -> Verdict {
        switch origin {
        case let .pagedScroll(scrollBox, startPage, startHref):
            if let startHref, let href = currentHref(), href != startHref { return .committed }
            guard let scrollView = scrollBox.value,
                  let page = Self.snappedPageIndex(of: scrollView) else { return .cancelled }
            if scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating {
                return .undecided
            }
            return page != startPage ? .committed : .cancelled
        case let .curl(spreadBox, startSpreadPage, paginationBox, startPaginationPage, startHref):
            if let startHref, let href = currentHref(), href != startHref { return .committed }
            if let pagination = paginationBox.value, let startPaginationPage,
               let page = Self.snappedPageIndex(of: pagination), page != startPaginationPage {
                return .committed
            }
            if let spread = spreadBox.value, let startSpreadPage,
               let page = Self.snappedPageIndex(of: spread), page != startSpreadPage {
                return .committed
            }
            return .undecided
        case let .indirect(startPlace):
            guard let startPlace, let place = currentPlaceKey() else { return .cancelled }
            return place != startPlace ? .committed : .undecided
        }
    }

    static func snappedPageIndex(of scrollView: UIScrollView) -> Int? {
        let width = scrollView.bounds.width
        guard width > 32, scrollView.contentOffset.x.isFinite else { return nil }
        return Int((max(0, scrollView.contentOffset.x) / width).rounded())
    }

    private static func startingPageIndex(of scrollView: UIScrollView, pan: UIPanGestureRecognizer) -> Int? {
        let width = scrollView.bounds.width
        guard width > 32, scrollView.contentOffset.x.isFinite else { return nil }
        let translationX = pan.translation(in: scrollView.superview ?? scrollView).x
        let rawX = scrollView.contentOffset.x + (translationX.isFinite ? translationX : 0)
        let clampedX = scrollView.contentSize.width >= width
            ? min(scrollView.contentSize.width - width, max(0, rawX))
            : max(0, rawX)
        return Int((clampedX / width).rounded())
    }

    private static func primarySpreadScrollView(in root: UIView) -> UIScrollView? {
        let rootBounds = root.bounds
        let rootArea = max(1, rootBounds.width * rootBounds.height)
        var best: (scrollView: UIScrollView, area: CGFloat)?
        func visit(_ view: UIView) {
            if let web = view as? WKWebView {
                if web.bounds.width > 32, web.bounds.height > 32, !web.isHidden, web.alpha > 0.01 {
                    let frameInRoot = web.convert(web.bounds, to: root)
                    let intersection = frameInRoot.intersection(rootBounds)
                    if !intersection.isNull, intersection.width > 32, intersection.height > 32 {
                        let area = intersection.width * intersection.height
                        if area >= rootArea * 0.55, best.map({ area > $0.area }) ?? true {
                            best = (web.scrollView, area)
                        }
                    }
                }
                return
            }
            for subview in view.subviews {
                visit(subview)
            }
        }
        visit(root)
        if let webScroll = best?.scrollView { return webScroll }
        // Fallback for unit-test hierarchies hosting a plain paged `UIScrollView` without a `WKWebView`.
        return firstPagedScrollView(in: root, excludingWebViews: false)
    }

    private static func paginationScrollView(in root: UIView) -> UIScrollView? {
        firstPagedScrollView(in: root, excludingWebViews: true)
    }

    private static func firstPagedScrollView(in view: UIView, excludingWebViews: Bool) -> UIScrollView? {
        if let scrollView = view as? UIScrollView, scrollView.isPagingEnabled {
            if !excludingWebViews || !(scrollView.superview is WKWebView) {
                return scrollView
            }
        }
        for subview in view.subviews {
            if excludingWebViews, subview is WKWebView { continue }
            if let found = firstPagedScrollView(in: subview, excludingWebViews: excludingWebViews) {
                return found
            }
        }
        return nil
    }
}
#endif
