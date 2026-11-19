#if os(iOS)
import Foundation
import ReadiumNavigator
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
/// Keys still move. `animatedTransition` is false in scroll mode, with Reduce
/// Motion, and for None. Slide, Fast Fade and Curl animate in paged mode.
/// Progress is not written here. Readium reports one `locationDidChange` when
/// the turn settles, and that remains the only save.
@MainActor
final class ReadiumPageTurnController {
    private var adapter: DirectionalNavigationAdapter?
    private var chromeToken: InputObservableToken?
    private weak var boundNavigator: EPUBNavigatorViewController?
    private var observers: [NSObjectProtocol] = []

    /// Options for `goForward` / `goBackward`. Refreshes first so a style,
    /// layout or Reduce Motion change applies to this call even if the
    /// notification has not been delivered yet.
    var goOptions: NavigatorGoOptions {
        refresh()
        return NavigatorGoOptions(animated: adapter?.animatedTransition ?? false)
    }

    func bind(to navigator: EPUBNavigatorViewController, toggleChrome: @escaping @MainActor () -> Void) {
        if let chromeToken, let boundNavigator {
            boundNavigator.removeObserver(chromeToken)
        }
        // Defaults: horizontal edges (30% of the width, at least 80 pt),
        // ignore taps while scrolling, arrows and space. That is Readium's
        // own edge policy — not a second set of zones.
        let adapter = DirectionalNavigationAdapter(animatedTransition: false)
        adapter.bind(to: navigator)
        chromeToken = navigator.addObserver(.activate { _ in
            toggleChrome()
            return true
        })
        self.adapter = adapter
        boundNavigator = navigator
        refresh()
        startObserving()
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
#endif
