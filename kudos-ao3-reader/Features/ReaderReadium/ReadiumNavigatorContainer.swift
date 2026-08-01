import OSLog
import SwiftData
import SwiftUI
#if os(iOS)
import ReadiumNavigator
import ReadiumShared
import UIKit
import WebKit
#endif

/// `ReadiumNavigatorContainer` — the representable that puts Readium's navigator
/// on screen — plus the two bridging extensions that map app types onto
/// Readium's (`ReaderTheme` → navigator theme, `Locator` persistence).
///
/// Split out of `ReadiumReaderView.swift` (see `ReadiumBook.swift` for why).
/// Pure code movement.

#if os(iOS)

/// Thin SwiftUI host for an already-built `EPUBNavigatorViewController`.
///
/// It used to add a downward swipe gesture for dismissal; the system zoom transition
/// now owns that, so what remains is hosting plus the selection-menu callbacks.
struct ReadiumNavigatorContainer: UIViewControllerRepresentable {
    let controller: EPUBNavigatorViewController
    let readingMode: ReadingMode
    let reduceMotion: Bool
    /// Selection-menu callbacks, delivered via the host controller because
    /// Readium routes custom editing actions through the responder chain.
    var onHighlight: () -> Void = {}
    var onAddNote: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> ReaderHighlightHostController {
        let host = ReaderHighlightHostController(navigator: controller)
        host.onHighlight = onHighlight
        host.onAddNote = onAddNote
        context.coordinator.update(
            readingMode: readingMode,
            reduceMotion: reduceMotion
        )
        context.coordinator.install(on: controller)
        return host
    }

    func updateUIViewController(_ host: ReaderHighlightHostController, context: Context) {
        host.onHighlight = onHighlight
        host.onAddNote = onAddNote
        context.coordinator.update(
            readingMode: readingMode,
            reduceMotion: reduceMotion
        )
        context.coordinator.install(on: controller)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private var readingMode: ReadingMode = .scroll
        private var reduceMotion = false
        private weak var installedView: UIView?
        /// Latched once a drag is recognized as a downward dismiss, so minor sideways
        /// wobble mid-drag doesn't snap the sheet back to rest (the old jank source).
        private var dismissLatched = false

        /// Lightweight cover of the live EPUB for the whole dismiss gesture + settle
        /// (`snapshotView`, not a CPU `drawHierarchy` bitmap). Strongly retained while
        /// installed so hierarchy churn mid-drag cannot drop it.
        /// Subviews hidden under the snapshot so WebKit stops compositing every frame
        /// while the card peels.
        /// Bumped on each dismiss `.began` so a late cancel-spring unfreeze from a
        /// previous gesture cannot thaw a newer freeze.
        private var dismissGeneration = 0

        func update(
            readingMode: ReadingMode,
            reduceMotion: Bool
        ) {
            self.readingMode = readingMode
            self.reduceMotion = reduceMotion
        }

        func install(on controller: EPUBNavigatorViewController) {
            guard let view = controller.view else { return }
            guard installedView !== view else { return }

            // No drag-to-dismiss recogniser here. The reader is pushed with the
            // system zoom transition (`WorkCardZoomTransition.swift`), whose own
            // interactive dismissal collapses the page back into the card it came
            // from — verified on device to preserve the reading position, which was
            // the one thing the old peel's freeze/latch machinery existed to protect.

            installedView = view
        }

        // MARK: Swipe-down dismiss












    }

}

// MARK: - Theme mapping

extension ReaderTheme {
    /// The matching Readium navigator theme. Readium has no OLED case of its own —
    /// `.dark` gives the navigator's chrome (e.g. its own default selection color)
    /// the right dark-mode behavior, while `backgroundColor`/`textColor` above are
    /// passed through `EPUBPreferences` explicitly, so the true-black page and text
    /// colors are unaffected by this mapping.
    var readiumTheme: ReadiumNavigator.Theme {
        switch self {
        case .light: .light
        case .sepia: .sepia
        case .dark, .oled: .dark
        }
    }
}

// MARK: - Locator persistence (public-API only)

extension Locator {
    /// A JSON string suitable for storing in SwiftData. The toolkit's own
    /// `jsonString()` is internal, so round-trip through Foundation JSON using the
    /// public `jsonObject` / `JSONValue` accessors.
    var persistenceString: String? {
        let dict = jsonObject.mapValues(\.any)
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    /// Rebuilds a `Locator` from `persistenceString`; nil if absent/invalid.
    init?(persistenceString: String) {
        guard !persistenceString.isEmpty,
              let data = persistenceString.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data),
              let json = JSONValue(any),
              let locator = try? Locator(json: json, warnings: nil)
        else { return nil }
        self = locator
    }
}

#endif
