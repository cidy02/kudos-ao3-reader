import Foundation
import Testing
@testable import Kudos

/// Refine on Subscriptions (1p.6): the index rows carry only title, id and
/// author, so a facet judges each row on its work-page summary once fetched and
/// keeps a row nothing is known about yet.
@MainActor
struct AO3SubscriptionsRefineTests {
    @Test func aFacetKeepsUnknownRowsAndJudgesEnrichedOnes() {
        let unknown = AO3WorkSummary.subscription(id: 1, title: "Unknown", authors: ["A"])
        let teenRow = AO3WorkSummary.subscription(id: 2, title: "Teen", authors: ["B"])
        let explicitRow = AO3WorkSummary.subscription(id: 3, title: "Explicit", authors: ["C"])
        let enriched = [
            2: summary(id: 2, rating: "Teen And Up Audiences"),
            3: summary(id: 3, rating: "Explicit")
        ]
        var filters = AO3SearchFilters()
        filters.rating = .teen

        let visible = AO3SubscriptionsRefine.visible(
            works: [unknown, teenRow, explicitRow],
            enriched: enriched,
            filters: filters
        )
        #expect(visible.map(\.id) == [1, 2])
        // The index rows come back, not their summaries: only the choice changes.
        #expect(visible.map(\.title) == ["Unknown", "Teen"])
        // The unknown row stays on the list but is not a match: the panel
        // counts it apart ("1 of the 3 works on this page match · 1 not
        // checked yet").
        let pending = AO3SubscriptionsRefine.pendingCount(
            works: [unknown, teenRow, explicitRow], enriched: enriched, filters: filters
        )
        #expect(pending == 1)
        #expect(visible.count - pending == 1)
    }

    @Test func withNoFacetEveryRowStays() {
        let rows = [
            AO3WorkSummary.subscription(id: 1, title: "One", authors: []),
            AO3WorkSummary.subscription(id: 2, title: "Two", authors: [])
        ]
        let visible = AO3SubscriptionsRefine.visible(
            works: rows, enriched: [2: summary(id: 2, rating: "Explicit")], filters: AO3SearchFilters()
        )
        #expect(visible.map(\.id) == [1, 2])
        #expect(AO3SubscriptionsRefine.pendingCount(
            works: rows, enriched: [2: summary(id: 2, rating: "Explicit")], filters: AO3SearchFilters()
        ) == 0)
    }

    @Test func aRowWithARatingOrAFandomIsNoLongerIndexOnly() {
        #expect(AO3SubscriptionsRefine.isIndexOnly(.subscription(id: 1, title: "T", authors: [])))
        #expect(!AO3SubscriptionsRefine.isIndexOnly(summary(id: 1, rating: "Mature")))
    }

    private func summary(id: Int, rating: String) -> AO3WorkSummary {
        AO3WorkSummary(
            id: id, title: "Enriched \(id)", authors: [], authorIdentities: [],
            fandoms: ["Fandom"], rating: rating,
            warnings: [], categories: [], isComplete: true, dateUpdated: "",
            tags: [], summary: "", language: "English", words: 1000, chapters: "1/1",
            comments: nil, kudos: nil, hits: nil,
            seriesTitle: nil, seriesURL: nil, seriesPosition: nil
        )
    }
}
