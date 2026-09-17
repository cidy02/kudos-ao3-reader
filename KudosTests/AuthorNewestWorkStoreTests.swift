import Foundation
import Testing
@testable import Kudos

/// The tri-state cache contract that 1ak's "With new work" filter rests on.
///
/// The filter may only run once *every* registered author has an answer, and it
/// must tell "not fetched" from "fetched, and there is nothing". Collapsing those
/// two is the silent-omission bug the filter exists to prevent, so the distinction
/// is pinned here rather than left to the view that reads it.
@MainActor
struct AuthorNewestWorkStoreTests {
    private let scope = "test-scope"

    @Test func aNeverFetchedAuthorHasNoAnswer() {
        AuthorNewestWorkStore.removeAll()
        #expect(AuthorNewestWorkStore.cached(username: "nobody", scope: scope) == nil)
    }

    @Test func fetchedAndEmptyIsStillAnAnswer() {
        AuthorNewestWorkStore.removeAll()
        AuthorNewestWorkStore.store(nil, username: "empty", scope: scope)

        // The outer optional says an answer arrived; the inner one says this author
        // has no visible works. A batch counts it resolved and the filter reads it
        // as "no new work" — never as "unknown".
        let outer = AuthorNewestWorkStore.cached(username: "empty", scope: scope)
        #expect(outer != nil)
        #expect((outer ?? nil) == nil)
    }

    @Test func aStoredWorkComesBack() {
        AuthorNewestWorkStore.removeAll()
        let work = AO3WorkSummary.subscription(id: 7, title: "Newest", authors: [])
        AuthorNewestWorkStore.store(work, username: "writer", scope: scope)

        let answer = AuthorNewestWorkStore.cached(username: "writer", scope: scope) ?? nil
        #expect(answer?.id == 7)
    }

    @Test func anAnswerExpiresWithTheTTL() {
        AuthorNewestWorkStore.removeAll()
        let stored = Date(timeIntervalSince1970: 1_000_000)
        AuthorNewestWorkStore.store(nil, username: "stale", scope: scope, now: stored)

        let inside = stored.addingTimeInterval(AuthorNewestWorkStore.ttl - 1)
        let outside = stored.addingTimeInterval(AuthorNewestWorkStore.ttl + 1)

        #expect(AuthorNewestWorkStore.cached(username: "stale", scope: scope, now: inside) != nil)
        // Expiry returns the author to "not fetched" — which is exactly why
        // readiness cannot be a flag the batch sets once and never revisits.
        #expect(AuthorNewestWorkStore.cached(username: "stale", scope: scope, now: outside) == nil)
    }

    @Test func oneSessionsAnswerNeverLeaksIntoAnother() {
        AuthorNewestWorkStore.removeAll()
        AuthorNewestWorkStore.store(nil, username: "shared", scope: "session-a")

        #expect(AuthorNewestWorkStore.cached(username: "shared", scope: "session-a") != nil)
        #expect(AuthorNewestWorkStore.cached(username: "shared", scope: "session-b") == nil)
    }

    @Test func lookupIgnoresBylineCase() {
        AuthorNewestWorkStore.removeAll()
        let work = AO3WorkSummary.subscription(id: 3, title: "Cased", authors: [])
        AuthorNewestWorkStore.store(work, username: "MixedCase", scope: scope)

        // The prefetch de-duplicates usernames case-insensitively, so a lookup that
        // did not agree would refetch the same author and never reach a complete
        // batch.
        let answer = AuthorNewestWorkStore.cached(username: "mixedcase", scope: scope) ?? nil
        #expect(answer?.id == 3)
    }
}
