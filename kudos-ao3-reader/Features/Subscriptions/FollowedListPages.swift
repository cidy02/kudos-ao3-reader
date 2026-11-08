import Foundation

/// Series and author pages for Subscriptions › Following. Load more captures
/// the account scope before the request and drops the page if that scope
/// changed, so one account's unstructured task cannot append into another's list.
@MainActor
@Observable
final class FollowedListPages {
    var series: [AO3FollowedSeries] = []
    var authors: [AO3FollowedAuthor] = []
    var seriesPage = 1
    var seriesTotal = 1
    var authorsPage = 1
    var authorsTotal = 1
    var loadingMoreSeries = false
    var loadingMoreAuthors = false

    func loadMore(
        _ kind: AO3SubscriptionListType,
        scope: () -> String,
        fetch: (Int) async throws -> AO3SubscriptionIndexPage
    ) async throws {
        let page: Int
        let total: Int
        switch kind {
        case .series:
            page = seriesPage
            total = seriesTotal
            guard !loadingMoreSeries else { return }
        case .users:
            page = authorsPage
            total = authorsTotal
            guard !loadingMoreAuthors else { return }
        case .works:
            return
        }
        let next = page + 1
        guard next <= total else { return }
        let requested = scope()
        setLoading(kind, true)
        defer { setLoading(kind, false) }
        let loaded = try await fetch(next)
        guard !Task.isCancelled, scope() == requested else { return }
        switch kind {
        case .series:
            appendSeries(loaded.series)
            seriesPage = loaded.currentPage
            seriesTotal = max(seriesTotal, loaded.totalPages)
        case .users:
            appendAuthors(loaded.authors)
            authorsPage = loaded.currentPage
            authorsTotal = max(authorsTotal, loaded.totalPages)
        case .works:
            break
        }
    }

    private func setLoading(_ kind: AO3SubscriptionListType, _ loading: Bool) {
        switch kind {
        case .series: loadingMoreSeries = loading
        case .users: loadingMoreAuthors = loading
        case .works: break
        }
    }

    private func appendSeries(_ incoming: [AO3FollowedSeries]) {
        let seen = Set(series.map(\.subscriptionID))
        series.append(contentsOf: incoming.filter { !seen.contains($0.subscriptionID) })
    }

    private func appendAuthors(_ incoming: [AO3FollowedAuthor]) {
        let seen = Set(authors.map(\.subscriptionID))
        authors.append(contentsOf: incoming.filter { !seen.contains($0.subscriptionID) })
    }
}
