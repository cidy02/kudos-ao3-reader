import Foundation
import Testing
@testable import Kudos

/// The family union, pinned to what was measured against live AO3 on 2026-09-11.
/// Two earlier attempts at this were wrong by reasoning rather than checking, so
/// each rule here is one of the things that was actually observed.
struct AO3FandomUnionTests {
    @Test func twoSiblingsBecomeAParenthesisedOrGroup() {
        // Parenthesised on purpose: AO3's query field ANDs its clauses, so an
        // ungrouped `filter_ids:A OR filter_ids:B` binds against the rest of the
        // query rather than against its own pair.
        #expect(AO3FandomUnion.queryClause(filterIDs: [27_785, 99_117]) == "filter_ids:(27785 OR 99117)")
    }

    @Test func oneSiblingNeedsNoGroup() {
        #expect(AO3FandomUnion.queryClause(filterIDs: [27_785]) == "filter_ids:27785")
    }

    @Test func noIDsMeansNoClause() {
        #expect(AO3FandomUnion.queryClause(filterIDs: []) == nil)
    }

    @Test func duplicatesCollapseAndOrderHolds() {
        // The clause is part of a URL that both the response cache and the
        // request coalescer key on, so the same family must always spell it the
        // same way.
        #expect(AO3FandomUnion.queryClause(filterIDs: [99_117, 27_785, 99_117])
            == "filter_ids:(99117 OR 27785)")
    }

    @Test func filterIDComesFromTheTagPagesFeedLink() {
        let page = """
        <html><head>
        <link rel="alternate" type="application/atom+xml" href="/tags/27785/feed.atom">
        </head><body><h2 class="heading">1 - 20 of 61,248 Works in Doctor Who (2005)</h2></body></html>
        """
        #expect(AO3FandomUnion.filterID(fromTagWorksPage: page, tagName: "Doctor Who (2005)") == 27_785)
    }

    @Test func aTagPageWithoutAFeedLinkYieldsNoID() {
        // A tag with no works prints no feed link. The caller treats nil as "no
        // union available" and keeps the intersection plus its tilde, rather
        // than showing a union that silently dropped a sibling.
        let page = "<html><body><h2 class=\"heading\">No works found</h2></body></html>"
        #expect(AO3FandomUnion.filterID(fromTagWorksPage: page, tagName: "Nothing Here") == nil)
    }

    @Test func theUnionClauseReachesTheSearchURL() {
        let url = AO3Client.searchURL(
            filters: AO3SearchFilters(),
            page: 1,
            additionalQueryClause: "filter_ids:(27785 OR 99117)"
        )
        let query = url?.query ?? ""
        #expect(query.contains("work_search%5Bquery%5D=filter_ids:(27785%20OR%2099117)")
            || query.contains("filter_ids:(27785 OR 99117)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "!"))
    }
}
