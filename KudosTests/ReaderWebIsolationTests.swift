import Foundation
import Testing
import WebKit
@testable import Kudos

struct ReaderWebIsolationTests {
    @Test func isolatedStoreIsNonPersistentAndNotTheDefaultStore() {
        let configuration = WKWebViewConfiguration()
        #expect(configuration.websiteDataStore.isPersistent)
        ReaderWebIsolation.applyIsolatedStore(to: configuration)
        #expect(configuration.websiteDataStore.isPersistent == false)
        #expect(configuration.websiteDataStore !== WKWebsiteDataStore.default())
    }

    @Test func readiumSchemeHookForcesANonPersistentStore() {
        ReaderWebIsolation.installReadiumStoreIsolation()
        let configuration = WKWebViewConfiguration()
        #expect(configuration.websiteDataStore.isPersistent)
        configuration.setURLSchemeHandler(DummySchemeHandler(), forURLScheme: "readium")
        #expect(configuration.websiteDataStore.isPersistent == false)
        #expect(configuration.websiteDataStore === ReaderWebIsolation.isolatedDataStore)
    }

    @Test func unrelatedSchemeHandlersDoNotStealTheIsolatedStore() {
        ReaderWebIsolation.installReadiumStoreIsolation()
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(DummySchemeHandler(), forURLScheme: "custom")
        #expect(configuration.websiteDataStore.isPersistent)
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
    }
}

private final class DummySchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {}
    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}
