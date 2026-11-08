import Foundation

/// Which list `SubscriptionsController#index` renders. The query value is the
/// plural form the subscriptions subnav actually requests (`type=works|series|users`).
enum AO3SubscriptionListType: String, Sendable {
    case works
    case series
    case users
}

/// One series row on the signed-in user's `?type=series` subscriptions page.
/// `seriesID` is nil when the template printed the name with no link (the
/// subscribable is gone). There is no Unfollow here: `AO3WriteActions.unsubscribe`
/// only knows how to read a work page.
nonisolated struct AO3FollowedSeries: Identifiable, Hashable, Sendable {
    /// Subscription record id from the row's delete form. Stable when the series is gone.
    let subscriptionID: Int
    var title: String
    var creatorNames: [String]
    var creatorIdentities: [AO3AuthorIdentity]
    var seriesID: Int?
    var url: URL?

    var id: Int { subscriptionID }

    /// Sparse summary so an existing series destination can open this row.
    /// The subscriptions index has no stats; the series page loads those.
    var navigationSummary: AO3SeriesSummary? {
        guard let seriesID, let url else { return nil }
        return AO3SeriesSummary(
            id: seriesID,
            title: title,
            creatorNames: creatorNames,
            creatorIdentities: creatorIdentities,
            fandoms: [],
            summary: "",
            words: nil,
            workCount: nil,
            dateUpdated: "",
            isComplete: nil,
            url: url
        )
    }
}

/// One author row on the signed-in user's `?type=users` subscriptions page.
/// `route` is nil when the template printed the name with no link.
nonisolated struct AO3FollowedAuthor: Identifiable, Hashable, Sendable {
    let subscriptionID: Int
    var name: String
    var route: AO3AuthorRoute?

    var id: Int { subscriptionID }
}

/// One page of a series or user subscriptions index.
nonisolated struct AO3SubscriptionIndexPage: Sendable {
    var series: [AO3FollowedSeries]
    var authors: [AO3FollowedAuthor]
    var currentPage: Int
    var totalPages: Int
}
