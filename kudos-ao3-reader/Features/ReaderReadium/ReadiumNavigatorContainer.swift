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

/// Thin SwiftUI host for an already-built `EPUBNavigatorViewController`. Adds a
/// downward swipe gesture on top of Readium so the reader can be dismissed without
/// interfering with the navigator's built-in page turns.
struct ReadiumNavigatorContainer: UIViewControllerRepresentable {
    let controller: EPUBNavigatorViewController
    let readingMode: ReadingMode
    /// UIKit peel surface — pan samples set `transform` here, not SwiftUI `@State`.
    let dismissSurface: ReaderDismissDragSurface
    let reduceMotion: Bool
    /// Fired on pan `.began` / after unfreeze so progress + visual metrics freeze.
    let onDismissInteractionActiveChange: (Bool) -> Void
    /// `shouldDismiss` plus an `unfreeze` callback the view invokes after cancel
    /// spring-back completes (or immediately when there is nothing to animate).
    /// Successful dismiss must **not** call `unfreeze` — leave the page frozen
    /// until view teardown so locator ingestion stays blocked.
    let onDismissDragEnded: (_ shouldDismiss: Bool, _ unfreeze: @escaping () -> Void) -> Void
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
            dismissSurface: dismissSurface,
            reduceMotion: reduceMotion,
            onDismissInteractionActiveChange: onDismissInteractionActiveChange,
            onDismissDragEnded: onDismissDragEnded
        )
        context.coordinator.install(on: controller)
        return host
    }

    func updateUIViewController(_ host: ReaderHighlightHostController, context: Context) {
        host.onHighlight = onHighlight
        host.onAddNote = onAddNote
        context.coordinator.update(
            readingMode: readingMode,
            dismissSurface: dismissSurface,
            reduceMotion: reduceMotion,
            onDismissInteractionActiveChange: onDismissInteractionActiveChange,
            onDismissDragEnded: onDismissDragEnded
        )
        context.coordinator.install(on: controller)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private var readingMode: ReadingMode = .scroll
        private weak var dismissSurface: ReaderDismissDragSurface?
        private var reduceMotion = false
        private var onDismissInteractionActiveChange: (Bool) -> Void = { _ in }
        private var onDismissDragEnded: (Bool, @escaping () -> Void) -> Void = { _, unfreeze in unfreeze() }
        private weak var installedView: UIView?
        private var dismissPan: UIPanGestureRecognizer?
        /// Latched once a drag is recognized as a downward dismiss, so minor sideways
        /// wobble mid-drag doesn't snap the sheet back to rest (the old jank source).
        private var dismissLatched = false
        /// Scroll views frozen for the duration of a latched dismiss.
        /// One scroll view's pre-freeze state, captured so the dismiss freeze can
        /// restore exactly what it changed if the gesture is cancelled. A named
        /// type rather than a 5-wide tuple: the members are all read back
        /// individually in `unfreezePage`, where positional tuple access would
        /// be easy to transpose silently (`bounces` and `alwaysBounce` are both
        /// `Bool` and adjacent).
        private struct FrozenScroll {
            let scrollView: UIScrollView
            let offset: CGPoint
            let wasEnabled: Bool
            let bounces: Bool
            let alwaysBounce: Bool
        }

        private var frozenScrolls: [FrozenScroll] = []
        /// Lightweight cover of the live EPUB for the whole dismiss gesture + settle
        /// (`snapshotView`, not a CPU `drawHierarchy` bitmap). Strongly retained while
        /// installed so hierarchy churn mid-drag cannot drop it.
        private var pageSnapshotView: UIView?
        /// Subviews hidden under the snapshot so WebKit stops compositing every frame
        /// while the card peels.
        private var hiddenUnderSnapshot: [UIView] = []
        /// Bumped on each dismiss `.began` so a late cancel-spring unfreeze from a
        /// previous gesture cannot thaw a newer freeze.
        private var dismissGeneration = 0

        func update(
            readingMode: ReadingMode,
            dismissSurface: ReaderDismissDragSurface,
            reduceMotion: Bool,
            onDismissInteractionActiveChange: @escaping (Bool) -> Void,
            onDismissDragEnded: @escaping (Bool, @escaping () -> Void) -> Void
        ) {
            self.readingMode = readingMode
            self.dismissSurface = dismissSurface
            self.reduceMotion = reduceMotion
            self.onDismissInteractionActiveChange = onDismissInteractionActiveChange
            self.onDismissDragEnded = onDismissDragEnded
        }

        func install(on controller: EPUBNavigatorViewController) {
            guard let view = controller.view else { return }
            // Readium's own EPUBSpreadView.setupWebView() unconditionally sets
            // showsVerticalScrollIndicator = false on every spread's WKWebView, with
            // no configuration flag to opt back in (swift-toolkit/Sources/Navigator/
            // EPUB/EPUBSpreadView.swift) — and it recreates spread views (re-applying
            // that) on every chapter/page change. Run unconditionally, not gated by
            // the `installedView` early-return below, so a freshly created spread's
            // scroll view gets caught the next time SwiftUI re-renders this
            // representable (which locator/chrome-state changes already do often).
            restoreNativeScrollIndicators(in: view)
            guard installedView !== view else { return }

            if let dismissPan {
                dismissPan.view?.removeGestureRecognizer(dismissPan)
                self.dismissPan = nil
            }

            // No drag-to-dismiss recogniser of our own any more. The reader is pushed
            // with the system zoom transition (`WorkCardZoomTransition.swift`), which
            // brings its own interactive dismissal — dragging the page collapses it
            // back into the card it came from. Running both meant our peel won the
            // gesture and the dismissal kept feeling hand-rolled, which is what the
            // owner reported.
            //
            // The peel machinery below (`handleDismissPan`, the delegate methods,
            // `ReaderDismissDragSurface`) is left in place for one build so the two
            // can be compared on device; `dismissPan` simply stays nil, so none of it
            // runs. See T-186 for the removal, which also has to preserve the peel
            // host's `safeAreaRegions = []` — the page box and the open skeleton both
            // depend on the reader being full-bleed.

            installedView = view
        }

        // MARK: Swipe-down dismiss

        @objc private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let translation = gesture.translation(in: view)
            let velocity = gesture.velocity(in: view)

            switch gesture.state {
            case .began:
                dismissLatched = false
                // Invalidate any pending cancel-spring unfreeze from a prior peel.
                dismissGeneration += 1
                // Freeze progress/visual BEFORE any setContentOffset side-effects.
                onDismissInteractionActiveChange(true)
                // Pin the page the instant our pan begins (shouldBegin already
                // gated top+downward). Waiting until the 8pt latch let UIScrollView
                // rubber-band first — text slid under the title pill.
                freezePageForDismiss(in: view, includeSnapshot: false)
            case .changed:
                // Only fight scroll until the still cover is in place — after that,
                // underlying WebKit is hidden and per-frame offset pinning is wasted work.
                if pageSnapshotView == nil {
                    reinstateFrozenOffsets()
                }
                if !dismissLatched {
                    // Latch the *card* peel once the drag is clearly intentional.
                    // Scroll is already frozen from `.began`.
                    let startsDismiss = translation.y > 8
                        && translation.y > abs(translation.x) * 1.1
                    guard startsDismiss else { return }
                    dismissLatched = true
                    // Freeze WebKit + peel a full-card bitmap in the window.
                    // Live SwiftUI is hidden; only the bitmap moves.
                    freezePageForDismiss(in: view, includeSnapshot: true)
                    dismissSurface?.beginCardSnapshotIfNeeded()
                }
                // UIKit transform only — never touch SwiftUI @State per sample.
                let y = rubberBandedDistance(max(0, translation.y))
                dismissSurface?.applyInteractiveOffset(y, reduceMotion: reduceMotion)
            case .ended:
                if dismissLatched {
                    let passesDistance = translation.y > 110
                    let passesVelocity = translation.y > 40 && velocity.y > 900
                    let shouldDismiss = passesDistance || passesVelocity
                    // Keep freeze through spring-back / fly-off; surface animates
                    // in the SwiftUI handler via the shared dismissSurface.
                    // Cancel path unfreezes from the spring completion (not a fixed
                    // timer). Successful dismiss must leave freeze latched until
                    // teardown — do not call `unfreeze` on that path.
                    let generation = dismissGeneration
                    onDismissDragEnded(shouldDismiss) { [weak self] in
                        guard let self, self.dismissGeneration == generation else { return }
                        self.unfreezePageAfterDismiss()
                    }
                } else {
                    // Began (and froze) but never latched — release immediately.
                    dismissSurface?.reset(reduceMotion: reduceMotion)
                    let generation = dismissGeneration
                    onDismissDragEnded(false) { [weak self] in
                        guard let self, self.dismissGeneration == generation else { return }
                        self.unfreezePageAfterDismiss()
                    }
                }
                dismissLatched = false
            case .cancelled, .failed:
                dismissSurface?.reset(reduceMotion: reduceMotion)
                let generation = dismissGeneration
                onDismissDragEnded(false) { [weak self] in
                    guard let self, self.dismissGeneration == generation else { return }
                    self.unfreezePageAfterDismiss()
                }
                dismissLatched = false
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view else { return true }
            let velocity = pan.velocity(in: view)
            let translation = pan.translation(in: view)

            // Dismiss pan: downward, vertical-dominant, top-of-page in scroll mode.
            let downwardIntent = velocity.y > 0 || translation.y > 0
            let verticalVelocity = abs(velocity.y) > abs(velocity.x) * 1.25
            let verticalTranslation = translation.y > abs(translation.x) * 1.25
            guard downwardIntent, verticalVelocity || verticalTranslation else { return false }
            return readingMode != .scroll || isAtTop(in: view)
        }

        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        ) -> Bool {
            // Scroll must not track alongside us — rubber-band was the remaining
            // "text under title pill" motion. Competing pans wait on us via
            // `shouldBeRequiredToFailBy` so dismiss still wins at top-of-page.
            false
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Competing pans (UIScrollView / page-turn) wait for our dismiss pan
            // to fail. At top+downward we begin and they never start. Otherwise
            // shouldBegin is false, we fail, and they proceed as normal.
            guard gestureRecognizer === dismissPan else { return false }
            return otherGestureRecognizer is UIPanGestureRecognizer
        }

        /// Pin scroll (and optionally cover with a still snapshot).
        /// - Parameter includeSnapshot: false on `.began` (cheap pin only); true
        ///   once the card peel latches so settle animations stay frozen.
        private func freezePageForDismiss(in root: UIView, includeSnapshot: Bool) {
            // Keep existing freeze bookkeeping if we're only upgrading to a snapshot.
            if frozenScrolls.isEmpty {
                let scrolls = collectScrollViews(in: root)
                frozenScrolls = scrolls.map { sv in
                    let top = -sv.adjustedContentInset.top
                    // Clamp out any in-progress top overscroll so we don't freeze
                    // mid-rubber-band (text already under the title pill).
                    var offset = sv.contentOffset
                    if offset.y < top {
                        offset = CGPoint(x: offset.x, y: top)
                    }
                    // Only write offset when it actually changes — a no-op
                    // setContentOffset still makes WebKit/Readium re-settle and
                    // was corrupting resume position on swipe-down dismiss.
                    if sv.contentOffset != offset {
                        sv.setContentOffset(offset, animated: false)
                    }
                    sv.layer.removeAllAnimations()
                    return FrozenScroll(
                        scrollView: sv,
                        offset: offset,
                        wasEnabled: sv.isScrollEnabled,
                        bounces: sv.bounces,
                        alwaysBounce: sv.alwaysBounceVertical
                    )
                }
                for entry in frozenScrolls {
                    entry.scrollView.isScrollEnabled = false
                    entry.scrollView.bounces = false
                    entry.scrollView.alwaysBounceVertical = false
                    entry.scrollView.panGestureRecognizer.isEnabled = false
                }
            } else {
                reinstateFrozenOffsets()
            }

            guard includeSnapshot, pageSnapshotView == nil else { return }
            guard root.bounds.width > 1, root.bounds.height > 1 else { return }
            // Prefer `snapshotView` (reuses the composited layer tree). Fall back to
            // a one-shot CPU render only if WebKit refuses a live snapshot — that path
            // was the multi‑ms hitch at peel latch on ProMotion, so keep it rare.
            let snapshot: UIView
            if let live = root.snapshotView(afterScreenUpdates: false) {
                snapshot = live
            } else if let image = cpuSnapshotImage(for: root) {
                let imageView = UIImageView(image: image)
                imageView.contentMode = .scaleToFill
                imageView.clipsToBounds = true
                snapshot = imageView
            } else {
                return
            }
            snapshot.frame = root.bounds
            snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            snapshot.isUserInteractionEnabled = false
            snapshot.accessibilityElementsHidden = true
            // One still layer for the rest of the gesture — no per-frame WebKit paint.
            snapshot.layer.shouldRasterize = true
            snapshot.layer.rasterizationScale = root.traitCollection.displayScale
            root.addSubview(snapshot)
            pageSnapshotView = snapshot
            // Hide everything under the cover so WKWebView / tiles stop compositing
            // while SwiftUI translates the card (the main continuous-chug source).
            hiddenUnderSnapshot = root.subviews.filter { $0 !== snapshot && !$0.isHidden }
            for subview in hiddenUnderSnapshot {
                subview.isHidden = true
            }
        }

        /// Last-resort full-frame CPU raster. Avoid on the hot path — only when
        /// `snapshotView` is unavailable.
        private func cpuSnapshotImage(for root: UIView) -> UIImage? {
            let format = UIGraphicsImageRendererFormat()
            format.scale = root.traitCollection.displayScale
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(bounds: root.bounds, format: format)
            return renderer.image { _ in
                root.drawHierarchy(in: root.bounds, afterScreenUpdates: false)
            }
        }

        private func reinstateFrozenOffsets() {
            for entry in frozenScrolls where entry.scrollView.contentOffset != entry.offset {
                entry.scrollView.setContentOffset(entry.offset, animated: false)
            }
        }

        private func unfreezePageAfterDismiss() {
            for subview in hiddenUnderSnapshot {
                subview.isHidden = false
            }
            hiddenUnderSnapshot = []
            pageSnapshotView?.removeFromSuperview()
            pageSnapshotView = nil
            for entry in frozenScrolls {
                entry.scrollView.panGestureRecognizer.isEnabled = true
                entry.scrollView.isScrollEnabled = entry.wasEnabled
                entry.scrollView.bounces = entry.bounces
                entry.scrollView.alwaysBounceVertical = entry.alwaysBounce
                if entry.scrollView.contentOffset != entry.offset {
                    entry.scrollView.setContentOffset(entry.offset, animated: false)
                }
            }
            frozenScrolls = []
            // Re-enable locator/visual updates only after freeze teardown so a
            // late scroll notification cannot overwrite the flushed position.
            // (No-op when exit is latched — `setDismissInteractionActive(false)`
            // refuses to clear once a successful dismiss committed.)
            onDismissInteractionActiveChange(false)
        }

        private func rubberBandedDistance(_ distance: CGFloat) -> CGFloat {
            guard distance > 150 else { return distance }
            return 150 + (distance - 150) * 0.5
        }

        private func isAtTop(in view: UIView) -> Bool {
            guard let scrollView = primaryScrollView(in: view) else { return true }
            let top = -scrollView.adjustedContentInset.top
            return scrollView.contentOffset.y <= top + 18
        }

        private func primaryScrollView(in view: UIView) -> UIScrollView? {
            let scrollViews = collectScrollViews(in: view)
            return scrollViews.first {
                !$0.isHidden && $0.alpha > 0 && $0.contentSize.height > $0.bounds.height + 1
            } ?? scrollViews.first
        }

        private func collectScrollViews(in view: UIView) -> [UIScrollView] {
            var result = (view as? UIScrollView).map { [$0] } ?? []
            for subview in view.subviews {
                result.append(contentsOf: collectScrollViews(in: subview))
            }
            return result
        }

        /// A2: the system scrollbar Readium suppresses (see `install(on:)`'s
        /// comment). Only the vertical indicator — horizontal stays off, since
        /// paged mode's horizontal scroll view is page-snapped, not a continuous
        /// scroll a horizontal bar would meaningfully represent.
        private func restoreNativeScrollIndicators(in root: UIView) {
            for scrollView in collectScrollViews(in: root) {
                scrollView.showsVerticalScrollIndicator = true
            }
        }
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
