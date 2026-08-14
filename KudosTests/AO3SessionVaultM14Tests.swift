import Testing
import Foundation
@testable import Kudos

@Suite("AO3CookieBridge M14 Tests")
struct AO3CookieBridgeM14Tests {
    @Test("Non-identity cookies are not persisted")
    func captureAO3CookiesFiltersNonIdentity() throws {
        func cookie(name: String, value: String) throws -> HTTPCookie {
            try #require(HTTPCookie(properties: [
                .domain: ".archiveofourown.org",
                .path: "/",
                .name: name,
                .value: value,
                .secure: "TRUE"
            ]))
        }

        let sessionValue = "identity-bearing-session"
        let rememberValue = "remember-me-token"
        let identity = try cookie(
            name: AO3RequestDefaults.sessionCookieName, value: sessionValue
        )
        let remember = try cookie(name: "user_credentials", value: rememberValue)
        let nonIdentity = try cookie(name: "viewed_adult", value: "true")
        let analytics = try cookie(name: "_ga", value: "GA1.1.decoy")

        let captured = AO3CookieBridge.persistableCookies(from: [
            identity, remember, nonIdentity, analytics
        ])
        let names = Set(captured.map(\.name))

        #expect(captured.contains { $0.name == "_otwarchive_session" }, "Identity cookie was missing")
        #expect(!captured.contains { $0.name == "viewed_adult" }, "Non-identity cookie was persisted")
        #expect(names.contains(AO3RequestDefaults.sessionCookieName))
        #expect(names.contains("user_credentials"))
        #expect(!names.contains("_ga"))
        #expect(names == [
            AO3RequestDefaults.sessionCookieName,
            "user_credentials"
        ])

        let persistedSession = try #require(
            captured.first { $0.name == AO3RequestDefaults.sessionCookieName }
        )
        #expect(persistedSession.value == sessionValue)
        let persistedRemember = try #require(
            captured.first { $0.name == "user_credentials" }
        )
        #expect(persistedRemember.value == rememberValue)
    }
}
