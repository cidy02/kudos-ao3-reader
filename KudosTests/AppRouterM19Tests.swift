import Testing
import Foundation
#if os(iOS)
import UIKit
import ObjectiveC
#endif
@testable import Kudos

@MainActor
@Suite("AppRouter M19 Tests")
struct AppRouterM19Tests {
    @Test("AppRouter externalizes non-HTTP and non-AO3 URLs")
    func unguardedURLSinkIsClosed() throws {
        #if os(iOS)
        #expect(
            SystemOpenSpy.install(),
            "could not swizzle UIApplication.open — cannot assert the opener was not invoked"
        )
        #endif
        let router = AppRouter()

        let javascript = try #require(URL(string: "javascript:alert(1)"))
        #expect(javascript.scheme?.lowercased() == "javascript")
        #if os(iOS)
        SystemOpenSpy.reset()
        #endif
        router.open(javascript)
        #expect(router.pendingURL == nil, "javascript: was stored as pendingURL")
        #expect(!router.isPresentingWebBrowser, "Hostile URL '\(javascript)' was opened in the in-app browser")
        #if os(iOS)
        #expect(
            !SystemOpenSpy.openedURLs.contains(javascript),
            "javascript: was handed to the system opener"
        )
        #endif

        let data = try #require(URL(string: "data:text/html,<html>"))
        #expect(data.scheme?.lowercased() == "data")
        #if os(iOS)
        SystemOpenSpy.reset()
        #endif
        router.open(data)
        #expect(router.pendingURL == nil, "data: was stored as pendingURL")
        #expect(!router.isPresentingWebBrowser, "Hostile URL '\(data)' was opened in the in-app browser")
        #if os(iOS)
        #expect(
            !SystemOpenSpy.openedURLs.contains(data),
            "data: was handed to the system opener"
        )
        #endif

        let file = try #require(URL(string: "file:///etc/passwd"))
        #expect(file.scheme?.lowercased() == "file")
        #if os(iOS)
        SystemOpenSpy.reset()
        #endif
        router.open(file)
        #expect(router.pendingURL == nil, "file: was stored as pendingURL")
        #expect(!router.isPresentingWebBrowser, "Hostile URL '\(file)' was opened in the in-app browser")
        #if os(iOS)
        #expect(
            !SystemOpenSpy.openedURLs.contains(file),
            "file: was handed to the system opener"
        )
        #endif

        let evil = try #require(URL(string: "https://evil.com"))
        #expect(evil.scheme?.lowercased() == "https")
        #if os(iOS)
        SystemOpenSpy.reset()
        #endif
        router.open(evil)
        #expect(router.pendingURL == nil, "non-AO3 https was stored as pendingURL")
        #expect(!router.isPresentingWebBrowser, "Hostile URL '\(evil)' was opened in the in-app browser")
        // Positive control: the spy is live. Non-AO3 http(s) must reach the
        // system opener. A dead spy would leave this list empty and fail here
        // rather than silently blessing a javascript:/data: hand-off.
        #if os(iOS)
        #expect(
            SystemOpenSpy.openedURLs.contains(evil),
            "non-AO3 https did not invoke the system opener — spy is dead"
        )
        #endif

        let foreignHTTP = try #require(URL(string: "http://example.org"))
        #expect(foreignHTTP.scheme?.lowercased() == "http")
        #if os(iOS)
        SystemOpenSpy.reset()
        #endif
        router.open(foreignHTTP)
        #expect(router.pendingURL == nil, "non-AO3 http was stored as pendingURL")
        #expect(!router.isPresentingWebBrowser, "Hostile URL '\(foreignHTTP)' was opened in the in-app browser")
        #if os(iOS)
        #expect(
            SystemOpenSpy.openedURLs.contains(foreignHTTP),
            "non-AO3 http did not invoke the system opener — spy is dead"
        )
        #endif

        // A no-op `open()` would pass every reject above. A legitimate AO3
        // https URL must still present the in-app sheet.
        let ao3 = try #require(URL(string: "https://archiveofourown.org/works/1"))
        #expect(ao3.scheme?.lowercased() == "https")
        #if os(iOS)
        SystemOpenSpy.reset()
        #endif
        router.open(ao3)
        #expect(router.pendingURL == ao3, "AO3 https URL was not stored as pendingURL")
        #expect(router.isPresentingWebBrowser, "AO3 https URL did not open the in-app browser")
        #if os(iOS)
        #expect(
            !SystemOpenSpy.openedURLs.contains(ao3),
            "AO3 https was handed to the system opener instead of the in-app sheet"
        )
        #endif
    }
}

#if os(iOS)
/// Records `UIApplication.open` so M19 can fail if a hostile scheme is handed
/// to the system opener. `AppRouter.swift` is out of scope for an injectable
/// seam; the test spies the production call instead.
@MainActor
enum SystemOpenSpy {
    private(set) static var openedURLs: [URL] = []
    private static var isInstalled = false

    @discardableResult
    static func install() -> Bool {
        if isInstalled { return true }
        let original = NSSelectorFromString("openURL:options:completionHandler:")
        let swizzled = #selector(
            UIApplication.kudos_test_openURL(_:options:completionHandler:)
        )
        guard let originalMethod = class_getInstanceMethod(UIApplication.self, original),
              let swizzledMethod = class_getInstanceMethod(UIApplication.self, swizzled)
        else { return false }
        method_exchangeImplementations(originalMethod, swizzledMethod)
        isInstalled = true
        return true
    }

    static func reset() {
        openedURLs = []
    }

    static func record(_ url: URL) {
        openedURLs.append(url)
    }
}

extension UIApplication {
    @objc func kudos_test_openURL(
        _ url: URL,
        options: [UIApplication.OpenExternalURLOptionsKey: Any],
        completionHandler: (@MainActor @Sendable (Bool) -> Void)?
    ) {
        SystemOpenSpy.record(url)
        completionHandler?(false)
    }
}
#endif
