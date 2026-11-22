#if os(iOS)
import Foundation
import ReadiumNavigator
import ReadiumShared
import UIKit

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
#endif
