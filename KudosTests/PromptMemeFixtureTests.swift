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

    /// The close date is on a page AO3 serves to owners only. Asking for it
    /// again with every page and claim, for a viewer AO3 refuses, was two
    /// signed-in requests each time that could not succeed.
    @Test func theCloseDateIsAskedForOnceAndOnlyForAnOwner() {
        // An owner, first load: ask.
        #expect(PromptMemeView.readsSchedule(viewerIsOwner: true, attempted: false, hasDate: false))
        // The same owner on page 2 or after a claim, whether or not a date came back: don't.
        #expect(!PromptMemeView.readsSchedule(viewerIsOwner: true, attempted: true, hasDate: false))
        #expect(!PromptMemeView.readsSchedule(viewerIsOwner: true, attempted: true, hasDate: true))
        // A refresh clears `attempted`: retry only if no date was obtained.
        #expect(!PromptMemeView.readsSchedule(viewerIsOwner: true, attempted: false, hasDate: true))
        // A participant or a moderator: never.
        #expect(!PromptMemeView.readsSchedule(viewerIsOwner: false, attempted: false, hasDate: false))
    }
}
