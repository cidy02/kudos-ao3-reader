import Testing
import Foundation
import WebKit
@testable import Kudos

@MainActor
@Suite("AO3CookieBridge M14 Tests")
struct AO3CookieBridgeM14Tests {
    @Test("Non-identity cookies are not persisted")
    func captureAO3CookiesFiltersNonIdentity() async throws {
        let store = WKWebsiteDataStore.default().httpCookieStore
        
        let identityCookie = HTTPCookie(properties: [
            .domain: ".archiveofourown.org",
            .path: "/",
            .name: "_otwarchive_session",
            .value: "secret",
            .secure: "TRUE"
        ])!
        
        let nonIdentityCookie = HTTPCookie(properties: [
            .domain: ".archiveofourown.org",
            .path: "/",
            .name: "viewed_adult",
            .value: "true",
            .secure: "TRUE"
        ])!
        
        await store.setCookie(identityCookie)
        await store.setCookie(nonIdentityCookie)
        
        let captured = await AO3CookieBridge.captureAO3Cookies()
        
        #expect(captured.contains { $0.name == "_otwarchive_session" }, "Identity cookie was missing")
        #expect(!captured.contains { $0.name == "viewed_adult" }, "Non-identity cookie was persisted")
        
        // Cleanup
        await store.deleteCookie(identityCookie)
        await store.deleteCookie(nonIdentityCookie)
    }
}
