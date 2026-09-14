import Foundation
import Testing
@testable import Kudos

/// The in-session account-list counts cache: approximate-count derivation from
/// already-parsed pages, TTL expiry, and authentication-scope isolation.
@MainActor
struct AO3AccountListCountsTests {
    @Test func singlePageIsExact() {
        let count = AO3AccountListCount(itemsOnPage: 7, totalPages: 1)
        #expect(count.exact == 7)
        #expect(count.lowerBound == nil)
        #expect(count.displayText == "7")
    }

    @Test func paginatedListIsALowerBound() {
        // 20 items on the first page of 12 pages → at least 220 (11 full pages).
        let count = AO3AccountListCount(itemsOnPage: 20, totalPages: 12)
        #expect(count.exact == nil)
        #expect(count.lowerBound == 220)
        #expect(count.displayText == "220+")
    }

    @Test func emptySinglePageShowsZero() {
        let count = AO3AccountListCount(itemsOnPage: 0, totalPages: 1)
        #expect(count.displayText == "0")
    }

    @Test func recordsAndExpiresByTTL() {
        let cache = AO3AccountListCountsCache(ttl: 60)
        let start = Date()
        cache.record(
            AO3AccountListCount(exact: 5),
            kind: .collections,
            authenticationScope: "signed-in:tester",
            now: start
        )
        #expect(
            cache.count(for: .collections, authenticationScope: "signed-in:tester", now: start)?
                .exact == 5
        )
        let later = start.addingTimeInterval(61)
        #expect(
            cache.count(for: .collections, authenticationScope: "signed-in:tester", now: later)
                == nil
        )
    }

    @Test func scopesNeverLeakAcrossAccounts() {
        let cache = AO3AccountListCountsCache()
        cache.record(
            AO3AccountListCount(exact: 9),
            kind: .myWorks,
            authenticationScope: "signed-in:alice"
        )
        #expect(cache.count(for: .myWorks, authenticationScope: "signed-in:bob") == nil)
        #expect(cache.count(for: .myWorks, authenticationScope: "anonymous") == nil)
        #expect(cache.count(for: .myWorks, authenticationScope: "signed-in:alice")?.exact == 9)
    }

    @Test func recordsAParsedPage() {
        let cache = AO3AccountListCountsCache()
        let page = AO3SearchPage(
            works: (1...20).map { AO3WorkSummary.subscription(id: $0, title: "W\($0)", authors: []) },
            currentPage: 1,
            totalPages: 3
        )
        cache.record(page: page, kind: .subscriptions, authenticationScope: "signed-in:alice")
        let stored = cache.count(for: .subscriptions, authenticationScope: "signed-in:alice")
        #expect(stored?.lowerBound == 40)
        #expect(stored?.displayText == "40+")
    }

    @Test func laterWeakerPageDoesNotDowngradeAStrongerCachedEstimate() {
        // Page 1 of 5 (20/page) records "80+". Paginating on to the short final
        // page (6 items) must not overwrite that with a weaker "6+".
        let cache = AO3AccountListCountsCache()
        let firstPage = AO3SearchPage(
            works: (1...20).map { AO3WorkSummary.subscription(id: $0, title: "W\($0)", authors: []) },
            currentPage: 1,
            totalPages: 5
        )
        cache.record(page: firstPage, kind: .markedForLater, authenticationScope: "signed-in:alice")
        let lastPage = AO3SearchPage(
            works: (1...6).map { AO3WorkSummary.subscription(id: $0, title: "W\($0)", authors: []) },
            currentPage: 5,
            totalPages: 5
        )
        cache.record(page: lastPage, kind: .markedForLater, authenticationScope: "signed-in:alice")
        let stored = cache.count(for: .markedForLater, authenticationScope: "signed-in:alice")
        #expect(stored?.lowerBound == 80)
        #expect(stored?.displayText == "80+")
    }

    @Test func strongerLaterPageStillUpdatesAWeakerCachedEstimate() {
        let cache = AO3AccountListCountsCache()
        cache.record(
            AO3AccountListCount(itemsOnPage: 20, totalPages: 2),
            kind: .history,
            authenticationScope: "signed-in:alice"
        )
        cache.record(
            AO3AccountListCount(itemsOnPage: 20, totalPages: 12),
            kind: .history,
            authenticationScope: "signed-in:alice"
        )
        let stored = cache.count(for: .history, authenticationScope: "signed-in:alice")
        #expect(stored?.lowerBound == 220)
    }

    /// Every call site now scopes through `AO3AuthorProfileFetcher.
    /// sessionScopedCacheScope(for:)`, which folds `AO3AuthService.
    /// sessionGeneration` into the scope string — a same-username relogin
    /// bumps that generation, so a lookup under the new session's scope must
    /// not see a count recorded under the prior one (T91-RF3/RF5 parity).
    /// The cache class itself just needs distinct strings to treat as
    /// distinct keys, which this proves directly without touching auth.
    @Test func sameUsernameDifferentSessionGenerationDoesNotReuseAStaleCount() {
        let cache = AO3AccountListCountsCache()
        cache.record(
            AO3AccountListCount(exact: 41),
            kind: .history,
            authenticationScope: "signed-in:alice#session-1"
        )
        #expect(cache.count(for: .history, authenticationScope: "signed-in:alice#session-2") == nil)
        #expect(
            cache.count(for: .history, authenticationScope: "signed-in:alice#session-1")?.exact == 41
        )
    }

    @Test func exactCountIsNeverDowngradedByALowerBound() {
        let cache = AO3AccountListCountsCache()
        cache.record(AO3AccountListCount(exact: 3), kind: .collections, authenticationScope: "signed-in:alice")
        cache.record(
            AO3AccountListCount(itemsOnPage: 1, totalPages: 2),
            kind: .collections,
            authenticationScope: "signed-in:alice"
        )
        let stored = cache.count(for: .collections, authenticationScope: "signed-in:alice")
        #expect(stored?.exact == 3)
    }

    // MARK: Counts seeded from the dashboard nav

    private func action(_ label: String, _ path: String) -> AO3AuthorWebAction {
        AO3AuthorWebAction(
            label: label,
            url: URL(string: "https://archiveofourown.org\(path)")!,
            kind: .other
        )
    }

    @Test func dashboardNavLabelsCarryTheirListSize() {
        #expect(action("Works (535)", "/users/astolat/works").listCount == 535)
        #expect(action("Bookmarks (1,204)", "/users/astolat/bookmarks").listCount == 1204)
        #expect(action("Profile", "/users/astolat/profile").listCount == nil)
        // A parenthesised non-number is not a count.
        #expect(action("Works (some)", "/users/astolat/works").listCount == nil)
    }

    @Test func dashboardNavSeedsCountsWithoutOpeningAnyList() {
        let cache = AO3AccountListCountsCache()
        cache.record(
            dashboardActions: [
                action("Works (535)", "/users/astolat/works"),
                action("Series (40)", "/users/astolat/series"),
                action("Bookmarks (22)", "/users/astolat/bookmarks"),
                action("Collections (33)", "/users/astolat/collections"),
                action("Gifts (131)", "/users/astolat/gifts")
            ],
            username: "astolat",
            authenticationScope: "signed-in:astolat"
        )
        #expect(cache.count(for: .myWorks, authenticationScope: "signed-in:astolat")?.exact == 535)
        #expect(cache.count(for: .bookmarks, authenticationScope: "signed-in:astolat")?.exact == 22)
        #expect(cache.count(for: .collections, authenticationScope: "signed-in:astolat")?.exact == 33)
        // Series has no list load anywhere in the app that yields a count, so the
        // nav is the only place this figure can come from.
        #expect(cache.count(for: .series, authenticationScope: "signed-in:astolat")?.exact == 40)
        // Not in that nav, so they stay unknown until their own list loads.
        #expect(cache.count(for: .subscriptions, authenticationScope: "signed-in:astolat") == nil)
        #expect(cache.count(for: .history, authenticationScope: "signed-in:astolat") == nil)
    }

    @Test func aPseudSubRouteCountIsNeverTakenForTheAccounts() {
        let cache = AO3AccountListCountsCache()
        cache.record(
            dashboardActions: [action("Works (7)", "/users/astolat/pseuds/shalott/works")],
            username: "astolat",
            authenticationScope: "signed-in:astolat"
        )
        #expect(cache.count(for: .myWorks, authenticationScope: "signed-in:astolat") == nil)
    }

    @Test func aNewerExactCountReplacesAnOlderOne() {
        let cache = AO3AccountListCountsCache()
        cache.record(AO3AccountListCount(exact: 535), kind: .myWorks, authenticationScope: "signed-in:astolat")
        cache.record(AO3AccountListCount(exact: 536), kind: .myWorks, authenticationScope: "signed-in:astolat")
        #expect(cache.count(for: .myWorks, authenticationScope: "signed-in:astolat")?.exact == 536)
    }
}
