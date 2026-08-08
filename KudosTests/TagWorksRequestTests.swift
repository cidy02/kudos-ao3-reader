import Foundation
import Testing
@testable import Kudos

/// Pins the tag-link → tag-works-screen URL.
///
/// AO3's own markup links a tag as `/tags/<name>` — its *info* page — and that
/// page carries no work blurbs (measured 2026-08-07: 0 on `/tags/Frozen (Disney
/// Movies)` vs 20 on the same path plus `/works`). Every route into this screen
/// comes from such a link, so the screen showed "No works found" for tags with
/// hundreds of thousands of works until the listing segment was added here.
struct TagWorksRequestTests {
    private func request(_ string: String) throws -> AO3TagWorksRequest {
        AO3TagWorksRequest(url: try #require(URL(string: string)), title: "t")
    }

    @Test func aBareTagLinkBecomesItsWorksListing() throws {
        let url = try request("https://archiveofourown.org/tags/Frozen%20(Disney%20Movies)").url
        #expect(url.absoluteString == "https://archiveofourown.org/tags/Frozen%20(Disney%20Movies)/works")
    }

    /// AO3 writes `&` in a tag path as `*a*` and percent-encodes the rest. Rebuilding
    /// the path from decoded components would re-encode the `*a*`'s neighbours and
    /// 404; this asserts the original encoding survives byte for byte.
    @Test func ao3sOwnPathEscapesSurviveUntouched() throws {
        let url = try request("https://archiveofourown.org/tags/Naruto%20(Anime%20*a*%20Manga)").url
        #expect(url.absoluteString == "https://archiveofourown.org/tags/Naruto%20(Anime%20*a*%20Manga)/works")
    }

    @Test func aLinkThatAlreadyPointsAtWorksIsUnchanged() throws {
        let string = "https://archiveofourown.org/tags/Fluff/works"
        #expect(try request(string).url.absoluteString == string)
    }

    /// `/bookmarks` is a different listing under the same tag — appending `/works`
    /// to it would build a path AO3 does not serve.
    @Test func anotherSubListingIsLeftAlone() throws {
        let string = "https://archiveofourown.org/tags/Fluff/bookmarks"
        #expect(try request(string).url.absoluteString == string)
    }

    @Test func aQueryStringSurvivesTheRewrite() throws {
        let url = try request("https://archiveofourown.org/tags/Fluff?page=2").url
        #expect(url.path == "/tags/Fluff/works")
        #expect(url.query == "page=2")
    }

    @Test func aTrailingSlashDoesNotDoubleUp() throws {
        let url = try request("https://archiveofourown.org/tags/Fluff/").url
        #expect(url.absoluteString == "https://archiveofourown.org/tags/Fluff/works")
    }
}
