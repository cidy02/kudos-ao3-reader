import Foundation
import Testing
@testable import Kudos

struct PromptMemeFixtureTests {

    private final class BundleAnchor {}

    @Test func parsePromptMemeRequestsFixtureReturns4Prompts() throws {
        let url = try #require(
            Bundle(for: BundleAnchor.self)
                .url(forResource: "ao3_challenge_requests", withExtension: "html")
        )
        let html = try String(contentsOf: url, encoding: .utf8)
        let page = try AO3Client.parsePromptMemePage(html, slug: "winter_meme", page: 1)
        #expect(page.prompts.count == 4)
    }
}
