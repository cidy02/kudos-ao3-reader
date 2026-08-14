import Testing
import Foundation
@testable import Kudos

@Suite("AO3StoredCookie M10 Tests")
struct AO3StoredCookieM10Tests {
    @Test("SameSite policy survives Codable roundtrip and HTTPCookie conversion")
    func sameSitePolicyIsPersisted() throws {
        let cookie = HTTPCookie(properties: [
            .domain: ".archiveofourown.org",
            .path: "/",
            .name: "test",
            .value: "secret",
            .sameSitePolicy: HTTPCookieStringPolicy.sameSiteLax
        ])!
        
        let stored = AO3StoredCookie(cookie)
        
        let data = try JSONEncoder().encode(stored)
        let decoded = try JSONDecoder().decode(AO3StoredCookie.self, from: data)
        
        let restoredCookie = decoded.httpCookie
        #expect(restoredCookie?.sameSitePolicy == .sameSiteLax)
    }
}
