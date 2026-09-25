import Testing
@testable import Kudos

/// Home's Subscriptions header and empty state, and the Recently Updated empty
/// state beside it (wave-3 audit 1b.7, 1b.8, 1b.9).
@MainActor
struct HomeSubscriptionsTests {
    /// Home loads page 1 only. The header may print the number of cards only
    /// when that page was the whole list, which is what an exact count records.
    @Test func headerCountsOnlyAWholeList() {
        #expect(HomeSubscriptionsCount.itemCount(
            shown: 12,
            recorded: AO3AccountListCount(itemsOnPage: 12, totalPages: 1)
        ) == 12)
        // 25 is otwarchive's ITEMS_PER_PAGE: a second page means more exist.
        #expect(HomeSubscriptionsCount.itemCount(
            shown: 25,
            recorded: AO3AccountListCount(itemsOnPage: 25, totalPages: 2)
        ) == nil)
        #expect(HomeSubscriptionsCount.itemCount(shown: 3, recorded: nil) == nil)
    }

    @Test func aFailedLoadDoesNotSayNotSubscribed() {
        let failed = HomeSubscriptionsCopy.emptyMessage(isLoggedIn: true, loadFailed: true)
        #expect(!failed.contains("not subscribed"))
        #expect(failed.contains("Couldn't load"))

        #expect(HomeSubscriptionsCopy.emptyMessage(isLoggedIn: true, loadFailed: false)
            == "You're not subscribed to anything yet. Subscribe to works or series to see updates here.")
        // Signed out wins over a stale failure flag.
        for loadFailed in [false, true] {
            #expect(HomeSubscriptionsCopy.emptyMessage(isLoggedIn: false, loadFailed: loadFailed)
                == "Log in to AO3 to see the works and series you subscribe to.")
        }
    }

    /// Recently Updated is built from unfinished library works, not from
    /// subscriptions, so its empty state must not name them.
    @Test func recentlyUpdatedEmptyStateDoesNotNameSubscriptions() {
        #expect(!HomeSectionKind.recentlyUpdated.emptyMessage.lowercased().contains("subscri"))
    }
}
