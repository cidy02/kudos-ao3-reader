import SwiftUI
import WebKit

#if os(macOS)
typealias PlatformViewRepresentable = NSViewRepresentable
#else
typealias PlatformViewRepresentable = UIViewRepresentable
#endif

/// Owns a WKWebView and exposes browsing state to SwiftUI. Intercepts EPUB
/// downloads and forwards the saved file to `onImport` for library insertion.
@Observable
final class BrowserModel: NSObject {
    let webView: WKWebView

    var urlString = ""
    var pageTitle = ""
    var canGoBack = false
    var canGoForward = false
    var isLoading = false

    /// Called when an EPUB finishes downloading: (savedFileURL, sourcePageURL).
    var onImport: ((URL, URL?) -> Void)?

    private var pendingDestinations: [WKDownload: URL] = [:]

    static let home = URL(string: "https://archiveofourown.org")!

    #if os(iOS)
    /// Whether the bottom tab bar should hide (true while scrolling the page down).
    var tabBarHidden = false
    private var scrollObservation: NSKeyValueObservation?
    private var lastScrollY: CGFloat = 0
    #endif

    override init() {
        let configuration = WKWebViewConfiguration()
        // Default data store persists cookies, so the user's AO3 login sticks.
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        #if os(iOS)
        observeScroll()
        #endif
        load(BrowserModel.home)
    }

    #if os(iOS)
    /// Tracks the web view's scroll direction so the tab bar can hide on scroll
    /// down and reappear on scroll up (Safari-like).
    private func observeScroll() {
        scrollObservation = webView.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
            guard let self else { return }
            let y = scrollView.contentOffset.y
            let dy = y - self.lastScrollY
            self.lastScrollY = y

            var hide = self.tabBarHidden
            if y <= 0 {
                hide = false                 // at the top, always show
            } else if dy > 4 {
                hide = true                  // scrolling down
            } else if dy < -4 {
                hide = false                 // scrolling up
            }
            if hide != self.tabBarHidden { self.tabBarHidden = hide }
        }
    }
    #endif

    func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    func loadFromAddressBar() {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let url = URL(string: trimmed), url.scheme != nil {
            load(url)
        } else if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let search = URL(string: "https://archiveofourown.org/works/search?work_search[query]=\(encoded)") {
            load(search)
        }
    }

    func goHome() { load(BrowserModel.home) }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }

    private func syncState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        if let url = webView.url { urlString = url.absoluteString }
        pageTitle = webView.title ?? ""
    }

    /// The current page as a bookmark candidate, if a URL is loaded.
    var currentBookmark: (title: String, url: URL)? {
        guard let url = webView.url else { return nil }
        let title = (webView.title?.isEmpty == false) ? webView.title! : url.host() ?? url.absoluteString
        return (title, url)
    }
}

// MARK: - Navigation & download handling

extension BrowserModel: WKNavigationDelegate, WKDownloadDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        let response = navigationResponse.response
        let isEPUB = response.mimeType == "application/epub+zip"
            || response.url?.pathExtension.lowercased() == "epub"
        decisionHandler(isEPUB ? .download : .allow)
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        download.delegate = self
    }

    func webView(
        _ webView: WKWebView,
        didStartProvisionalNavigation navigation: WKNavigation!
    ) {
        isLoading = true
        syncState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        syncState()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        isLoading = false
        syncState()
    }

    // WKDownloadDelegate

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let destination = Storage.tempDownloadURL(suggestedName: suggestedFilename)
        try? FileManager.default.removeItem(at: destination)
        pendingDestinations[download] = destination
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let destination = pendingDestinations.removeValue(forKey: download) else { return }
        onImport?(destination, webView.url)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        pendingDestinations.removeValue(forKey: download)
    }
}

/// Thin SwiftUI wrapper that hosts the shared WKWebView on macOS and iOS.
struct WebView: PlatformViewRepresentable {
    let webView: WKWebView

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    #else
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    #endif
}
