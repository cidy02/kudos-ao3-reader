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
}
