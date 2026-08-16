import Testing
import Foundation
@testable import Kudos

@Suite("AO3StoredCookie M10 Tests")
struct AO3StoredCookieM10Tests {
    @Test("SameSite policy survives Codable roundtrip and HTTPCookie conversion")
    func sameSitePolicyIsPersisted() throws {
        let cookie = try #require(HTTPCookie(properties: [
            .domain: ".archiveofourown.org",
            .path: "/",
            .name: "test",
            .value: "secret",
            .sameSitePolicy: HTTPCookieStringPolicy.sameSiteLax
        ]))
        // If Foundation dropped Lax at construction, later nil==nil would pass.
        #expect(cookie.sameSitePolicy == .sameSiteLax)

        let stored = AO3StoredCookie(cookie)
        #expect(stored.sameSitePolicy == HTTPCookieStringPolicy.sameSiteLax.rawValue)
        #expect(stored.name == cookie.name)
        #expect(stored.value == cookie.value)

        let data = try JSONEncoder().encode(stored)
        let decoded = try JSONDecoder().decode(AO3StoredCookie.self, from: data)
        #expect(decoded.sameSitePolicy == HTTPCookieStringPolicy.sameSiteLax.rawValue)

        let restoredCookie = try #require(decoded.httpCookie)
        #expect(restoredCookie.sameSitePolicy == .sameSiteLax)
        #expect(restoredCookie.name == cookie.name)
        #expect(restoredCookie.value == cookie.value)
    }
}
