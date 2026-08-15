import Foundation
import Testing
import WebKit
#if os(iOS)
import UIKit
#endif
@testable import Kudos

@MainActor
struct ReaderWebIsolationTests {
    @Test func isolatedStoreIsNonPersistentAndNotTheDefaultStore() {
        let configuration = WKWebViewConfiguration()
        #expect(configuration.websiteDataStore.isPersistent)
        #expect(configuration.websiteDataStore === WKWebsiteDataStore.default())
        ReaderWebIsolation.applyIsolatedStore(to: configuration)
        assertReaderStoreIsIsolated(configuration.websiteDataStore)
        #expect(configuration.websiteDataStore === ReaderWebIsolation.isolatedDataStore)
        #expect(
            configuration.websiteDataStore.httpCookieStore
                !== WKWebsiteDataStore.default().httpCookieStore
        )
    }

    @Test func isolatedDataStoreItselfIsNeverDefaultOrPersistent() {
        assertReaderStoreIsIsolated(ReaderWebIsolation.isolatedDataStore)
        #expect(WKWebsiteDataStore.default().isPersistent)
    }

    @Test func webViewBuiltFromIsolatedConfigurationDoesNotUseTheDefaultStore() {
        let configuration = WKWebViewConfiguration()
        ReaderWebIsolation.applyIsolatedStore(to: configuration)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        assertReaderStoreIsIsolated(webView.configuration.websiteDataStore)
        #expect(webView.configuration.websiteDataStore === ReaderWebIsolation.isolatedDataStore)
        #expect(
            webView.configuration.websiteDataStore.httpCookieStore
                !== WKWebsiteDataStore.default().httpCookieStore
        )
    }

    @Test func readiumSchemeHookForcesANonPersistentStore() {
        ReaderWebIsolation.installReadiumStoreIsolation()
        let configuration = WKWebViewConfiguration()
        #expect(configuration.websiteDataStore.isPersistent)
        #expect(configuration.websiteDataStore === WKWebsiteDataStore.default())
        configuration.setURLSchemeHandler(DummySchemeHandler(), forURLScheme: "readium")
        assertReaderStoreIsIsolated(configuration.websiteDataStore)
        #expect(configuration.websiteDataStore === ReaderWebIsolation.isolatedDataStore)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        assertReaderStoreIsIsolated(webView.configuration.websiteDataStore)
        #expect(webView.configuration.websiteDataStore === ReaderWebIsolation.isolatedDataStore)
    }

    @Test func unrelatedSchemeHandlersDoNotStealTheIsolatedStore() {
        ReaderWebIsolation.installReadiumStoreIsolation()
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(DummySchemeHandler(), forURLScheme: "custom")
        #expect(configuration.websiteDataStore.isPersistent)
        #expect(configuration.websiteDataStore === WKWebsiteDataStore.default())
    }

    @Test func policyAllowsReadiumAndAboutAndRejectsTheWeb() {
        let origin = ReaderPublicationOrigin.readiumScheme
        #expect(ReaderWebNavigationPolicy.allowsInReaderNavigation(
            to: URL(string: "readium://abc/chapter.xhtml")!,
            origin: origin
        ))
        #expect(ReaderWebNavigationPolicy.allowsInReaderNavigation(
            to: URL(string: "about:blank")!,
            origin: origin
        ))
        #expect(!ReaderWebNavigationPolicy.allowsInReaderNavigation(
            to: URL(string: "https://evil.example/navigated")!,
            origin: origin
        ))
        #expect(!ReaderWebNavigationPolicy.allowsInReaderNavigation(
            to: URL(string: "http://127.0.0.1:8098/navigated")!,
            origin: origin
        ))
        #expect(!ReaderWebNavigationPolicy.allowsInReaderNavigation(
            to: URL(string: "javascript:alert(1)")!,
            origin: origin
        ))
    }

    @Test func policyRejectsJavascriptAndDataForBothOrigins() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReaderWebIsolation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let origins: [ReaderPublicationOrigin] = [.readiumScheme, .fileRoot(root)]
        let forbidden = [
            "javascript:alert(1)",
            "JAVASCRIPT:void(0)",
            "data:text/html,<script>document.cookie</script>",
            "blob:https://evil.example/probe",
            "vbscript:msgbox(1)",
        ]
        for origin in origins {
            for raw in forbidden {
                let url = try #require(URL(string: raw))
                #expect(!ReaderWebNavigationPolicy.allowsInReaderNavigation(to: url, origin: origin))
            }
        }
        #expect(ReaderWebNavigationPolicy.forbiddenReaderSchemes.isSuperset(of: [
            "javascript", "data",
        ]))
    }

    @Test func policyAllowsFileURLsOnlyUnderThePublicationRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReaderWebIsolation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let chapter = root.appendingPathComponent("chapter.xhtml")
        try Data("<p>hi</p>".utf8).write(to: chapter)
        let origin = ReaderPublicationOrigin.fileRoot(root)

        #expect(ReaderWebNavigationPolicy.allowsInReaderNavigation(to: chapter, origin: origin))
        #expect(ReaderWebNavigationPolicy.allowsInReaderNavigation(
            to: URL(string: chapter.absoluteString + "#note")!,
            origin: origin
        ))
        #expect(!ReaderWebNavigationPolicy.allowsInReaderNavigation(
            to: URL(fileURLWithPath: "/etc/passwd"),
            origin: origin
        ))
        #expect(!ReaderWebNavigationPolicy.allowsInReaderNavigation(
            to: URL(string: "https://archiveofourown.org/")!,
            origin: origin
        ))
        #expect(!ReaderWebNavigationPolicy.allowsInReaderNavigation(
            to: URL(string: "javascript:alert(1)")!,
            origin: origin
        ))
        #expect(!ReaderWebNavigationPolicy.allowsInReaderNavigation(
            to: URL(string: "data:text/html,hello")!,
            origin: origin
        ))
    }

    @Test func navigationGuardCancelsScriptDrivenOffPublicationNavigation() throws {
        let webView = WKWebView()
        let navGuard = ReaderWebNavigationGuard(
            original: nil,
            origin: .readiumScheme,
            onOpenExternalURL: nil
        )
        var opened: URL?
        navGuard.onOpenExternalURL = { opened = $0 }

        let cancelled = [
            "javascript:alert(1)",
            "data:text/html,hello",
            "https://evil.example/navigated",
        ]
        for raw in cancelled {
            let action = ScriptedNavigationAction(url: try #require(URL(string: raw)))
            var policy: WKNavigationActionPolicy?
            navGuard.webView(webView, decidePolicyFor: action) { policy = $0 }
            #expect(policy == .cancel)
        }
        // Script-driven (`navigationType == .other`) must not open Browse.
        #expect(opened == nil)

        var allowed: WKNavigationActionPolicy?
        navGuard.webView(
            webView,
            decidePolicyFor: ScriptedNavigationAction(
                url: try #require(URL(string: "readium://abc/chapter.xhtml"))
            )
        ) { allowed = $0 }
        #expect(allowed == .allow)
    }

    #if os(iOS)
    @Test func installNavigationGuardsWrapsExistingWebViews() {
        let host = UIView()
        let webView = WKWebView()
        host.addSubview(webView)
        #expect(!(webView.navigationDelegate is ReaderWebNavigationGuard))
        ReaderWebIsolation.installNavigationGuards(
            in: host,
            origin: .readiumScheme,
            onOpenExternalURL: nil
        )
        #expect(webView.navigationDelegate is ReaderWebNavigationGuard)
    }
    #endif

    /// Cookie jars can be probed through `WKHTTPCookieStore` without loading a
    /// page. A live `document.cookie` / `window.location` probe still needs a
    /// real Readium spread on a device.
    @Test func cookiesDoNotCrossBetweenIsolatedAndDefaultStores() async throws {
        let isolatedStore = ReaderWebIsolation.isolatedDataStore
        let defaultStore = WKWebsiteDataStore.default()
        assertReaderStoreIsIsolated(isolatedStore)
        #expect(isolatedStore.httpCookieStore !== defaultStore.httpCookieStore)

        let isolatedCookie = try #require(HTTPCookie(properties: [
            .domain: "m8-isolation.test",
            .path: "/",
            .name: "kudos-m8-iso-\(UUID().uuidString)",
            .value: "isolated-only",
        ]))
        let defaultCookie = try #require(HTTPCookie(properties: [
            .domain: "m8-isolation.test",
            .path: "/",
            .name: "kudos-m8-def-\(UUID().uuidString)",
            .value: "default-only",
        ]))

        await CookieProbe.set(isolatedCookie, in: isolatedStore.httpCookieStore)
        await CookieProbe.set(defaultCookie, in: defaultStore.httpCookieStore)

        let defaultCookies = await CookieProbe.allCookies(in: defaultStore.httpCookieStore)
        let isolatedCookies = await CookieProbe.allCookies(in: isolatedStore.httpCookieStore)

        await CookieProbe.delete(isolatedCookie, from: isolatedStore.httpCookieStore)
        await CookieProbe.delete(defaultCookie, from: defaultStore.httpCookieStore)

        #expect(!defaultCookies.contains { $0.name == isolatedCookie.name })
        #expect(!isolatedCookies.contains { $0.name == defaultCookie.name })
        #expect(isolatedCookies.contains { $0.name == isolatedCookie.name })
        #expect(defaultCookies.contains { $0.name == defaultCookie.name })
    }
}

private func assertReaderStoreIsIsolated(_ store: WKWebsiteDataStore) {
    #expect(store.isPersistent == false)
    #expect(store !== WKWebsiteDataStore.default())
}

private enum CookieProbe {
    static func allCookies(in store: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
    }

    static func set(_ cookie: HTTPCookie, in store: WKHTTPCookieStore) async {
        await withCheckedContinuation { continuation in
            store.setCookie(cookie) { continuation.resume() }
        }
    }

    static func delete(_ cookie: HTTPCookie, from store: WKHTTPCookieStore) async {
        await withCheckedContinuation { continuation in
            store.delete(cookie) { continuation.resume() }
        }
    }
}

/// `WKNavigationAction` has no public initializer; a script-driven
/// `window.location` assignment reports as `.other`.
private final class ScriptedNavigationAction: WKNavigationAction {
    private let urlRequest: URLRequest

    override var request: URLRequest { urlRequest }
    override var navigationType: WKNavigationType { .other }

    init(url: URL) {
        urlRequest = URLRequest(url: url)
        super.init()
    }
}

private final class DummySchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {}
    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}
