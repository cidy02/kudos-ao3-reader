import SwiftUI
import WebKit
#if canImport(UIKit)
import UIKit
#endif

// Backs the legacy WKWebView reader (`ReaderView`), which is macOS-only now — iOS
// uses the Readium navigator. Excluded from iOS builds.
#if os(macOS)

/// Owns the reader's web view: injects the theme/layout stylesheet, turns pages
/// in paged mode, reports page position, and signals chapter boundaries.
@Observable
final class ReaderController: NSObject {
    let webView: WKWebView

    /// 1-based page position within the current chapter (paged mode).
    var page = 1
    var pageTotal = 1

    /// Called when paging forward past the last page / back before the first.
    var onReachedEnd: (() -> Void)?
    var onReachedStart: (() -> Void)?
    /// Called when the user scrolls to the bottom of the chapter (scrolled mode).
    var onReachedScrollBottom: (() -> Void)?
    /// Called when the user taps an external (http/https) link inside the EPUB —
    /// e.g. an AO3 work/author/tag reference. The host routes it to the Browse tab
    /// instead of letting it navigate away inside the reader's web view.
    var onOpenExternalURL: ((URL) -> Void)?
    /// Called with the normalized intra-chapter position (0…1) reported by the
    /// layout script — the fraction of the chapter's content above the
    /// viewport's leading edge, in both scrolled and paged modes. Already gated
    /// against stale loads; see `ReaderBridgeMessage`.
    var onProgressFraction: ((Double) -> Void)?

    #if os(iOS)
    /// Called when the reading area is tapped (toggles the chrome).
    var onTap: (() -> Void)?
    /// Called when a downward scroll should hide the chrome (passes hidden = true).
    var onChromeHiddenChange: ((Bool) -> Void)?
    private var chromeHidden = false
    private var lastScrollY: CGFloat = 0
    private var scrollObservation: NSKeyValueObservation?
    #endif

    private let proxy = ReaderScriptProxy()
    private var loadedURL: URL?
    private var landOnLast = false
    /// Normalized position (0…1) to restore once the chapter's layout is ready.
    private var pendingRestoreFraction: Double?
    /// Monotonic id for the current chapter load. The layout script echoes it
    /// in every message; `ReaderBridgeMessage.parse` drops mismatches so a late
    /// callback from an old chapter's document can't overwrite current state.
    private var generation = 0
    private var css = ""
    private var mode: ReadingMode = .scroll
    private var columns = 1
    private var margin = 28
    private var safeTop = 0
    private var safeBottom = 0

    override init() {
        let configuration = WKWebViewConfiguration()
        // Process pools are shared by WebKit automatically on modern iOS.
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        proxy.controller = self
        configuration.userContentController.add(proxy, name: "reader")
        webView.navigationDelegate = self
        #if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        #endif
        #if os(iOS)
        // The web view runs full-screen; let the EPUB's own CSS env(safe-area-*)
        // padding handle the insets instead of the scroll view double-insetting.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        installReaderGestures()
        #endif
    }

    #if os(iOS)
    /// Keeps the controller's notion of chrome visibility in sync with the view
    /// (e.g. after a tap toggle) so scroll-driven hiding doesn't fight it.
    func syncChromeHidden(_ hidden: Bool) {
        chromeHidden = hidden
    }

    /// A tap toggles the chrome; a downward scroll hides it. The recognizer doesn't
    /// cancel touches, so text selection, links and page swipes still work.
    private func installReaderGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleReaderTap))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        webView.addGestureRecognizer(tap)

        scrollObservation = webView.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
            guard let self else { return }
            let y = scrollView.contentOffset.y
            let dy = y - lastScrollY
            lastScrollY = y
            // Only a genuine user-driven scroll hides the chrome. Showing the chrome
            // changes the safe area, which shifts the content and nudges contentOffset;
            // without this guard the observer read that shift as a downward scroll and
            // instantly re-hid the chrome, so a tap appeared to "bounce" the page
            // instead of toggling the controls. Layout shifts aren't during a drag.
            guard scrollView.isDragging || scrollView.isDecelerating else { return }
            // Auto-hide only on a deliberate downward scroll; revealing is tap-only,
            // so a chapter load (offset resets to 0) never flashes the chrome back.
            if dy > 6, y > 0, !chromeHidden {
                chromeHidden = true
                onChromeHiddenChange?(true)
            }
        }
    }

    @objc private func handleReaderTap() {
        onTap?()
    }
    #endif

    /// Updates style/layout settings, re-applying immediately if a page is loaded.
    /// `safeTop`/`safeBottom` are the device's fixed safe-area insets (passed from the
    /// host) so the full-screen reader pads past the notch / home indicator.
    func configure(css: String, mode: ReadingMode, columns: Int, margin: Int = 28,
                   safeTop: Int = 0, safeBottom: Int = 0) {
        self.css = css
        self.mode = mode
        self.columns = columns
        self.margin = margin
        self.safeTop = safeTop
        self.safeBottom = safeBottom
        if loadedURL != nil { inject() }
    }

    /// Loads a chapter. `landOnLast` (backward paging) wins over
    /// `restoreFraction` (a remembered/persisted position); both apply after
    /// the page's layout script has run, so the layout they target exists.
    func load(_ url: URL, readAccess: URL, landOnLast: Bool, restoreFraction: Double? = nil) {
        self.landOnLast = landOnLast
        pendingRestoreFraction = landOnLast ? nil : restoreFraction
        generation += 1
        loadedURL = url
        page = 1
        pageTotal = 1
        webView.loadFileURL(url, allowingReadAccessTo: readAccess)
    }

    func nextPage() {
        webView.evaluateJavaScript("window.readerStep(1)") { [weak self] result, _ in
            if (result as? String) == "end" { self?.onReachedEnd?() }
        }
    }

    func prevPage() {
        webView.evaluateJavaScript("window.readerStep(-1)") { [weak self] result, _ in
            if (result as? String) == "start" { self?.onReachedStart?() }
        }
    }

    fileprivate func handleMessage(_ body: Any) {
        guard let message = ReaderBridgeMessage.parse(body, currentGeneration: generation) else { return }
        switch message {
        case let .key(key):
            if key == "ArrowLeft" { prevPage() } else { nextPage() }
        case .reachedScrollBottom:
            onReachedScrollBottom?()
        case let .pagePosition(newPage, newTotal):
            page = newPage
            pageTotal = newTotal
            // The paged fraction is derived here rather than posted separately:
            // the page's leading edge sits page-1 pages into total pages.
            onProgressFraction?(Double(newPage - 1) / Double(newTotal))
        case let .progress(fraction):
            onProgressFraction?(fraction)
        }
    }

    private func inject() {
        webView.evaluateJavaScript(
            ReaderStylesheet.layoutScript(css: css, mode: mode, columns: columns, margin: margin,
                                          safeTop: safeTop, safeBottom: safeBottom,
                                          generation: generation)
        )
    }
}

extension ReaderController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        inject()
        if landOnLast {
            landOnLast = false
            webView.evaluateJavaScript("window.readerLast && window.readerLast();")
        } else if let fraction = pendingRestoreFraction {
            // Restore after inject() has applied the layout, so the scroll
            // height / page count the fraction maps onto actually exists.
            pendingRestoreFraction = nil
            webView.evaluateJavaScript("window.readerRestore && window.readerRestore(\(fraction));")
        }
    }

    /// Web links in EPUB content (AO3 work/author/tag pages, external sites) should
    /// open in the in-app Browse tab, not hijack the reader's web view. The reader
    /// only ever loads local `file://` chapters, so *any* attempt to navigate to a
    /// web URL is a tapped content link — cancel it and hand it off. The app's own
    /// `loadFileURL` and in-chapter anchor jumps (`file://` fragments) keep their
    /// `file` scheme and proceed in place.
    func webView(_: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            decisionHandler(.cancel)
            onOpenExternalURL?(url)
            return
        }
        decisionHandler(.allow)
    }
}

#if os(iOS)
extension ReaderController: UIGestureRecognizerDelegate {
    /// Let our tap coexist with the web view's own gestures (selection, links, swipes).
    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
#endif

/// Weak forwarder so the web view's content controller doesn't retain the controller.
private final class ReaderScriptProxy: NSObject, WKScriptMessageHandler {
    weak var controller: ReaderController?

    func userContentController(
        _: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        controller?.handleMessage(message.body)
    }
}

#endif
