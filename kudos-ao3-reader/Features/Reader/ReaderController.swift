import SwiftUI
import WebKit

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
    /// Asks the host whether `url` is another item in the loaded spine. **Must be
    /// a pure lookup**: it runs while a WebKit navigation decision is still
    /// outstanding, so it must not start a load or mutate reader state — that's
    /// `onCrossSpineNavigation`'s job, and it runs afterwards.
    var recognizesSpineURL: ((URL) -> Bool)?
    /// Hands a recognized cross-chapter target (e.g. a note link into another
    /// chapter) to the host, which navigates via its own `currentIndex` path so
    /// the pill/TOC/progress/comments scope all follow (A7-F5). Called only after
    /// the WebKit decision has been finalized. Same-document fragment links never
    /// reach this callback; they're allowed to navigate in place.
    var onCrossSpineNavigation: ((URL) -> Void)?

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
        webView.setValue(false, forKey: "drawsBackground")
    }

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

    /// Idempotent teardown: clears every escaping callback and stops any
    /// in-flight load. The callback closures are what capture `ReaderView`'s
    /// `@State` storage (which owns this controller) — leaving them set after
    /// dismissal is what keeps the retain cycle alive across repeated
    /// open/close (A7-F3). Deliberately leaves `navigationDelegate` and the
    /// "reader" script message handler alone: `navigationDelegate` is a `weak`
    /// WKWebView property (doesn't retain, so it isn't part of the cycle), and
    /// nothing re-installs the handler on a later `.onAppear` — clearing it
    /// here would silently and permanently break the JS↔host bridge (layout
    /// injection, external-link routing) if this controller ever became
    /// visible again without being deallocated.
    func teardown() {
        onReachedEnd = nil
        onReachedStart = nil
        onReachedScrollBottom = nil
        onOpenExternalURL = nil
        onProgressFraction = nil
        recognizesSpineURL = nil
        onCrossSpineNavigation = nil
        webView.stopLoading()
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
    /// `file` scheme and proceed in place. A `file://` link to a *different* spine
    /// file (a cross-chapter note) is handed to `onCrossSpineNavigation` so the
    /// host can update `currentIndex` before navigating (A7-F5); same-document
    /// fragments fall through to `.allow` unchanged.
    func webView(_: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            decisionHandler(.cancel)
            onOpenExternalURL?(url)
            return
        }
        if url.scheme?.lowercased() == "file", isCrossSpineNavigation(to: url) {
            // Finalize the decision *before* handing off. The host's handler sets
            // `currentIndex`, which re-enters `loadCurrentChapter()` →
            // `webView.loadFileURL(...)`; starting a navigation while a decision is
            // still outstanding is undefined per WebKit's contract (and can log
            // "Completion handler … was not called"). Hence the split into a pure
            // `recognizesSpineURL` query and this action.
            decisionHandler(.cancel)
            if recognizesSpineURL?(url) == true {
                onCrossSpineNavigation?(url)
            }
            return
        }
        decisionHandler(.allow)
    }

    /// True when `url` (its fragment ignored, since `URL.path` never includes one)
    /// points at a different file than the currently loaded chapter.
    private func isCrossSpineNavigation(to url: URL) -> Bool {
        guard let loadedURL else { return false }
        return Self.fileKey(url) != Self.fileKey(loadedURL)
    }

    /// Symlink-normalized identity for a local chapter file, shared with
    /// `ReaderView`'s own spine lookup so both sides compare the same way. macOS
    /// hands out both `/var/…` and `/private/var/…` for the same file; comparing
    /// raw `path` strings would let that difference read as "same file" here (or
    /// as "unresolvable" there) and silently fall back to an uncorrected
    /// in-webview navigation — straight back to A7-F5, with no signal.
    static func fileKey(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

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
