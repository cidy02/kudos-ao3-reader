import Testing
import Foundation
@testable import Kudos

@MainActor
@Suite("AppRouter M19 Tests")
struct AppRouterM19Tests {
    @Test("AppRouter externalizes non-HTTP and non-AO3 URLs")
    func unguardedURLSinkIsClosed() throws {
        let router = AppRouter()

        let javascript = try #require(URL(string: "javascript:alert(1)"))
        #expect(javascript.scheme?.lowercased() == "javascript")
        router.open(javascript)
        #expect(router.pendingURL == nil, "javascript: was stored as pendingURL")
        #expect(!router.isPresentingWebBrowser, "Hostile URL '\(javascript)' was opened in the in-app browser")

        let data = try #require(URL(string: "data:text/html,<html>"))
        #expect(data.scheme?.lowercased() == "data")
        router.open(data)
        #expect(router.pendingURL == nil, "data: was stored as pendingURL")
        #expect(!router.isPresentingWebBrowser, "Hostile URL '\(data)' was opened in the in-app browser")

        let file = try #require(URL(string: "file:///etc/passwd"))
        #expect(file.scheme?.lowercased() == "file")
        router.open(file)
        #expect(router.pendingURL == nil, "file: was stored as pendingURL")
        #expect(!router.isPresentingWebBrowser, "Hostile URL '\(file)' was opened in the in-app browser")

        let evil = try #require(URL(string: "https://evil.com"))
        #expect(evil.scheme?.lowercased() == "https")
        router.open(evil)
        #expect(router.pendingURL == nil, "non-AO3 https was stored as pendingURL")
        #expect(!router.isPresentingWebBrowser, "Hostile URL '\(evil)' was opened in the in-app browser")

        let foreignHTTP = try #require(URL(string: "http://example.org"))
        #expect(foreignHTTP.scheme?.lowercased() == "http")
        router.open(foreignHTTP)
        #expect(router.pendingURL == nil, "non-AO3 http was stored as pendingURL")
        #expect(!router.isPresentingWebBrowser, "Hostile URL '\(foreignHTTP)' was opened in the in-app browser")

        // A no-op `open()` would pass every reject above. A legitimate AO3
        // https URL must still present the in-app sheet.
        let ao3 = try #require(URL(string: "https://archiveofourown.org/works/1"))
        #expect(ao3.scheme?.lowercased() == "https")
        router.open(ao3)
        #expect(router.pendingURL == ao3, "AO3 https URL was not stored as pendingURL")
        #expect(router.isPresentingWebBrowser, "AO3 https URL did not open the in-app browser")
    }
}
