import SwiftUI
import WebKit

#if os(macOS)
import AppKit
typealias PlatformViewRepresentable = NSViewRepresentable
private typealias BrowserPlatformColor = NSColor
#else
import UIKit
typealias PlatformViewRepresentable = UIViewRepresentable
private typealias BrowserPlatformColor = UIColor
#endif

/// A small, scoped site skin that maps AO3's current default selectors onto the
/// app's themes. Light deliberately leaves AO3's native skin untouched.
enum BrowserThemeStyle {
    private struct Palette {
        let scheme: String
        let background: String
        let raised: String
        let recessed: String
        let text: String
        let secondaryText: String
        let link: String
        let visitedLink: String
        let border: String
        let control: String
        let activeControl: String
    }

    static func isAO3URL(_ url: URL?) -> Bool {
        guard let host = url?.host()?.lowercased() else { return false }
        return host == "archiveofourown.org" || host.hasSuffix(".archiveofourown.org")
    }

    static func css(for theme: ReaderTheme) -> String? {
        guard let palette = palette(for: theme) else { return nil }
        return """
        :root { color-scheme: \(palette.scheme) !important; }
        html, body, #outer, #inner, #main, #dashboard, #workskin,
        .region, .group, .group .group, .module, .index, .index .index,
        .flash, fieldset, form dl, table, th, td, textarea, input, select,
        .secondary, .dropdown, .notice, ul.notes, #modal, div.dynamic,
        .dynamic form, .autocomplete, #ui-datepicker-div {
          background-color: \(palette.background) !important;
          color: \(palette.text) !important;
          border-color: \(palette.border) !important;
          outline-color: \(palette.border) !important;
          box-shadow: none !important;
        }
        #header, #footer, #header ul.primary, #dashboard ul,
        #header .menu, #small_login, .toggled form, .listbox,
        .listbox .index, li.blurb, .blurb .blurb, blockquote,
        form blockquote.userstuff, div.comment, li.comment,
        .splash .news li, code, pre {
          background: \(palette.raised) !important;
          color: \(palette.text) !important;
          border-color: \(palette.border) !important;
          box-shadow: none !important;
        }
        #outer, .javascript, .filters .group, .thread .even,
        tr:hover, td:hover, .ui-sortable li:hover {
          background-color: \(palette.recessed) !important;
        }
        body, p, li, dt, dd, blockquote, .userstuff, .summary,
        .notes, .stats, .meta, .datetime, .byline, label,
        h1, h2, h3, h4, h5, h6, .heading, .group .heading {
          color: \(palette.text) !important;
        }
        .footnote, .help, .tip, .landmark + *, .series .divider,
        ::placeholder {
          color: \(palette.secondaryText) !important;
        }
        a, a:link, a.tag, #header a, #header a:visited,
        #dashboard a, .blurb h4 a:link, a.work {
          color: \(palette.link) !important;
        }
        a:visited, .actions a:visited, .action a:visited {
          color: \(palette.visitedLink) !important;
        }
        a:hover, a:focus, .actions a:hover, .actions button:hover,
        .actions input:hover {
          color: \(palette.link) !important;
        }
        input, textarea, select, option {
          background: \(palette.recessed) !important;
          color: \(palette.text) !important;
          border-color: \(palette.border) !important;
          box-shadow: none !important;
        }
        input:focus, textarea:focus, select:focus {
          background: \(palette.raised) !important;
          outline-color: \(palette.link) !important;
        }
        .actions a, .actions a:link, .action, .action:link,
        .actions button, .actions input, input[type="submit"], button,
        .current, .actions label, #header .actions a {
          background: \(palette.control) !important;
          background-image: none !important;
          color: \(palette.text) !important;
          border-color: \(palette.border) !important;
          box-shadow: none !important;
          text-shadow: none !important;
        }
        .actions a:active, .current, a.current, .current a:visited {
          background: \(palette.activeControl) !important;
          color: \(palette.text) !important;
          border-color: \(palette.link) !important;
        }
        li.blurb, fieldset, form dl, .picture .header,
        #header .menu li, table, th, td, hr {
          border-color: \(palette.border) !important;
        }
        mark, ::selection {
          background: \(palette.activeControl) !important;
          color: \(palette.text) !important;
        }
        """
    }

    static func injectionScript(for theme: ReaderTheme, url: URL?) -> String {
        guard isAO3URL(url), let css = css(for: theme) else {
            return """
            (function(){
              var style = document.getElementById('kudos-app-theme');
              if (style) style.remove();
              if (document.documentElement) {
                document.documentElement.style.removeProperty('color-scheme');
              }
            })();
            """
        }

        let encoded = Data(css.utf8).base64EncodedString()
        return """
        (function(){
          var id = 'kudos-app-theme';
          var style = document.getElementById(id);
          if (!style) {
            style = document.createElement('style');
            style.id = id;
            (document.head || document.documentElement).appendChild(style);
          }
          style.textContent = atob('\(encoded)');
        })();
        """
    }

    private static func palette(for theme: ReaderTheme) -> Palette? {
        switch theme {
        case .light:
            return nil
        case .sepia:
            return Palette(
                scheme: "light",
                background: "#FBF0D9",
                raised: "#F6E8CB",
                recessed: "#ECDDBD",
                text: "#5B4636",
                secondaryText: "#79624F",
                link: "#8A5A2B",
                visitedLink: "#6F5744",
                border: "#C8B28A",
                control: "#E7D3AC",
                activeControl: "#D8BE8C"
            )
        case .dark:
            return Palette(
                scheme: "dark",
                background: "#16161A",
                raised: "#222228",
                recessed: "#111115",
                text: "#CFCFD4",
                secondaryText: "#A5A5AD",
                link: "#7FB0E8",
                visitedLink: "#AD93D8",
                border: "#3A3A42",
                control: "#2D2D35",
                activeControl: "#44444F"
            )
        }
    }
}

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
    private var currentTheme: ReaderTheme = .light

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
        webView.isOpaque = false
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

    func applyTheme(_ theme: ReaderTheme) {
        currentTheme = theme
        webView.underPageBackgroundColor = underPageColor(for: theme)
        injectCurrentTheme()
    }

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

    private func injectCurrentTheme() {
        let script = BrowserThemeStyle.injectionScript(for: currentTheme, url: webView.url)
        webView.evaluateJavaScript(script)
    }

    private func underPageColor(for theme: ReaderTheme) -> BrowserPlatformColor {
        switch theme {
        case .light:
            return BrowserPlatformColor(red: 1, green: 1, blue: 1, alpha: 1)
        case .sepia:
            return BrowserPlatformColor(
                red: 251 / 255, green: 240 / 255, blue: 217 / 255, alpha: 1
            )
        case .dark:
            return BrowserPlatformColor(
                red: 22 / 255, green: 22 / 255, blue: 26 / 255, alpha: 1
            )
        }
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

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        injectCurrentTheme()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        syncState()
        injectCurrentTheme()
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
