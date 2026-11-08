import Testing
@testable import Kudos

@MainActor
struct FollowedListLoadTests {
    @Test func loadMoreKeepsThePageWhenTheAccountIsUnchanged() async throws {
        let pages = FollowedListPages()
        pages.series = [series(1, "Already shown")]
        pages.seriesTotal = 2

        try await pages.loadMore(.series, scope: { "signed-in:alice" }) { _ in
            AO3SubscriptionIndexPage(
                series: [series(2, "Next page")],
                authors: [],
                currentPage: 2,
                totalPages: 2
            )
        }

        #expect(pages.series.map(\.subscriptionID) == [1, 2])
        #expect(pages.seriesPage == 2)
        #expect(!pages.loadingMoreSeries)
    }

    @Test func loadMoreDropsThePageWhenTheAccountChanges() async throws {
        let pages = FollowedListPages()
        pages.series = [series(1, "Alice keeps")]
        pages.seriesPage = 1
        pages.seriesTotal = 3
        pages.authors = [author(8, "alice-author")]
        pages.authorsTotal = 2
        var scope = "signed-in:alice"

        try await pages.loadMore(.series, scope: { scope }) { _ in
            scope = "signed-in:bob"
            return AO3SubscriptionIndexPage(
                series: [series(99, "Bob's series")],
                authors: [],
                currentPage: 2,
                totalPages: 3
            )
        }
        try await pages.loadMore(.users, scope: { scope }) { _ in
            scope = "signed-in:cara"
            return AO3SubscriptionIndexPage(
                series: [],
                authors: [author(100, "Cara")],
                currentPage: 2,
                totalPages: 2
            )
        }

        #expect(pages.series.map(\.subscriptionID) == [1])
        #expect(pages.seriesPage == 1)
        #expect(pages.seriesTotal == 3)
        #expect(pages.authors.map(\.subscriptionID) == [8])
        #expect(pages.authorsPage == 1)
        #expect(!pages.loadingMoreSeries)
        #expect(!pages.loadingMoreAuthors)
    }

    private func series(_ id: Int, _ title: String) -> AO3FollowedSeries {
        AO3FollowedSeries(
            subscriptionID: id,
            title: title,
            creatorNames: [],
            creatorIdentities: [],
            seriesID: id,
            url: nil
        )
    }

    private func author(_ id: Int, _ name: String) -> AO3FollowedAuthor {
        AO3FollowedAuthor(subscriptionID: id, name: name, route: nil)
    }
}
