import Foundation
import ObjectiveC
import WebKit
#if os(iOS)
import UIKit
#endif

/// Shared WebKit isolation for both readers (M8).
///
/// Untrusted EPUB JavaScript must not share the default `WKWebsiteDataStore`
/// (the store that holds the AO3 session cookie) and must not navigate the
/// reader web view off the publication origin. Readium 3.9.0 only cancels
/// `.linkActivated`, so a script-driven `window.location` assignment would
/// otherwise leave the book.
enum ReaderPublicationOrigin: Equatable, Sendable {
    /// Readium serves the book over its custom `readium:` scheme.
    case readiumScheme
    /// Legacy macOS reader loads `file://` chapters under this directory.
    case fileRoot(URL)
}

nonisolated enum ReaderWebNavigationPolicy {
    static let readiumScheme = "readium"

    /// True only when `url` stays inside the loaded publication. HTTP(S),
    /// `javascript:`, `data:`, and `file://` paths outside the book directory
    /// all return false.
    static func allowsInReaderNavigation(to url: URL, origin: ReaderPublicationOrigin) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "about" { return true }
        switch origin {
        case .readiumScheme:
            return scheme == readiumScheme
        case let .fileRoot(root):
            guard url.isFileURL || scheme == "file" else { return false }
            let rootPath = normalizedDirectoryPath(root)
            let targetPath = url.standardizedFileURL.resolvingSymlinksInPath().path
            return targetPath == rootPath || targetPath.hasPrefix(rootPath + "/")
        }
    }

    static func isWebURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    private static func normalizedDirectoryPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        if path.hasSuffix("/") { return String(path.dropLast()) }
        return path
    }
}

enum ReaderWebIsolation {
    static let isolatedDataStore = WKWebsiteDataStore.nonPersistent()
    /// Set by `ReadiumBook.open` so newly created spread web views can hand
    /// tapped HTTP(S) links to Browse without the container knowing the book.
    static var onReadiumOpenExternalURL: ((URL) -> Void)?

    static func applyIsolatedStore(to configuration: WKWebViewConfiguration) {
        configuration.websiteDataStore = isolatedDataStore
    }

    /// Installs a one-time hook so Readium's `WKWebViewConfiguration` (which
    /// registers the `readium` scheme handler and otherwise uses the default
    /// store) is forced onto `isolatedDataStore` *before* the web view is
    /// created. Browse / login web views never register that scheme.
    static func installReadiumStoreIsolation() {
        ReadiumStoreHook.install()
    }

    #if os(iOS)
    /// Wraps each WKWebView's navigation delegate so off-origin navigations
    /// of *any* type (not just `.linkActivated`) are cancelled. The original
    /// Readium delegate still sees in-origin decisions.
    static func installNavigationGuards(
        in root: UIView,
        origin: ReaderPublicationOrigin,
        onOpenExternalURL: ((URL) -> Void)?
    ) {
        for webView in collectWebViews(in: root) {
            NavigationGuardStore.install(
                on: webView,
                origin: origin,
                onOpenExternalURL: onOpenExternalURL
            )
        }
    }

    private static func collectWebViews(in view: UIView) -> [WKWebView] {
        var result = (view as? WKWebView).map { [$0] } ?? []
        for subview in view.subviews {
            result.append(contentsOf: collectWebViews(in: subview))
        }
        return result
    }
    #endif
}

// MARK: - Readium store hook

private enum ReadiumStoreHook {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        let cls: AnyClass = WKWebViewConfiguration.self
        let original = #selector(WKWebViewConfiguration.setURLSchemeHandler(_:forURLScheme:))
        let swizzled = #selector(WKWebViewConfiguration.kudos_setURLSchemeHandler(_:forURLScheme:))
        guard let originalMethod = class_getInstanceMethod(cls, original),
              let swizzledMethod = class_getInstanceMethod(cls, swizzled)
        else { return }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

extension WKWebViewConfiguration {
    @objc func kudos_setURLSchemeHandler(
        _ handler: (any WKURLSchemeHandler)?,
        forURLScheme urlScheme: String
    ) {
        kudos_setURLSchemeHandler(handler, forURLScheme: urlScheme)
        if urlScheme == ReaderWebNavigationPolicy.readiumScheme {
            websiteDataStore = ReaderWebIsolation.isolatedDataStore
        }
    }
}

// MARK: - Navigation guard

/// Forwards to Readium / the legacy controller, but vetoes off-origin
/// navigations first. Retained by `NavigationGuardStore` because
/// `WKWebView.navigationDelegate` is weak.
final class ReaderWebNavigationGuard: NSObject, WKNavigationDelegate {
    weak var original: (any WKNavigationDelegate)?
    let origin: ReaderPublicationOrigin
    var onOpenExternalURL: ((URL) -> Void)?

    init(
        original: (any WKNavigationDelegate)?,
        origin: ReaderPublicationOrigin,
        onOpenExternalURL: ((URL) -> Void)?
    ) {
        self.original = original
        self.origin = origin
        self.onOpenExternalURL = onOpenExternalURL
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let url = navigationAction.request.url,
           !ReaderWebNavigationPolicy.allowsInReaderNavigation(to: url, origin: origin) {
            decisionHandler(.cancel)
            if navigationAction.navigationType == .linkActivated,
               ReaderWebNavigationPolicy.isWebURL(url) {
                onOpenExternalURL?(url)
            }
            return
        }
        if let original {
            original.webView?(webView, decidePolicyFor: navigationAction, decisionHandler: decisionHandler)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        original?.webView?(webView, didFinish: navigation)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        original?.webView?(webView, didFail: navigation, withError: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        original?.webViewWebContentProcessDidTerminate?(webView)
    }
}

private enum NavigationGuardStore {
    /// Strong values, weak keys: a dead spread's web view drops its guard.
    private static let guards = NSMapTable<WKWebView, ReaderWebNavigationGuard>.weakToStrongObjects()

    static func install(
        on webView: WKWebView,
        origin: ReaderPublicationOrigin,
        onOpenExternalURL: ((URL) -> Void)?
    ) {
        if let existing = guards.object(forKey: webView) {
            existing.onOpenExternalURL = onOpenExternalURL
            return
        }
        if webView.navigationDelegate is ReaderWebNavigationGuard { return }
        let guardDelegate = ReaderWebNavigationGuard(
            original: webView.navigationDelegate,
            origin: origin,
            onOpenExternalURL: onOpenExternalURL
        )
        guards.setObject(guardDelegate, forKey: webView)
        webView.navigationDelegate = guardDelegate
    }
}
