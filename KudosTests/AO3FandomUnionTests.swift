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
        // If neither authoritative ID source is available, keep the existing
        // all-or-nothing fallback rather than silently dropping a sibling.
        let page = "<html><body><h2 class=\"heading\">No works found</h2></body></html>"
        #expect(AO3FandomUnion.filterID(fromTagWorksPage: page, tagName: "Nothing Here") == nil)
    }

    @Test func officialNestedFeedControlResolvesEvenWithoutSidebarFacets() {
        let page = """
        <div id="main"><div class="navigation actions module">
        <ul class="user navigation actions"><li>
        <a href="https://archiveofourown.org/tags/27785/feed.atom">RSS Feed</a>
        </li></ul></div><p>No works found.</p></div>
        """
        #expect(AO3FandomUnion.filterID(fromTagWorksPage: page, tagName: "Doctor Who (2005)") == 27_785)
    }

    @Test func sidebarFallbackMatchesTheExactFandomWithoutLosingItsYear() {
        let page = """
        <form id="work-filters"><label>
        <input name="include_work_search[fandom_ids][]" value="99117">
        <span class="indicator"></span><span>Doctor Who (1963) (9,958)</span></label>
        <label><input name="include_work_search[fandom_ids][]" value="27785">
        <span class="indicator"></span><span>Doctor Who (2005) (61,248)</span></label></form>
        """
        #expect(AO3FandomUnion.filterID(fromTagWorksPage: page, tagName: "Doctor Who (2005)") == 27_785)
        #expect(AO3FandomUnion.filterID(fromTagWorksPage: page, tagName: "Doctor Who") == nil)
    }

    @Test func sidebarFallbackDecodesNamesAndRejectsOtherTagTypesAndInvalidIDs() {
        let page = """
        <form id="work-filters">
        <label><input name="include_work_search[character_ids][]" value="12"><span>A &amp; B (6)</span></label>
        <label><input name="exclude_work_search[fandom_ids][]" value="13"><span>A &amp; B (6)</span></label>
        <label><input name="include_work_search[fandom_ids][]" value="-1"><span>A &amp; B (6)</span></label>
        <label><input name="include_work_search[fandom_ids][]" value="123"><span>A &amp; B (6)</span></label>
        </form>
        """
        #expect(AO3FandomUnion.filterID(fromTagWorksPage: page, tagName: "A & B") == 123)
    }

    @Test func feedURLsQuotedInProseOrOnOtherHostsDoNotIdentifyThePage() {
        let page = """
        <head><link rel="alternate" type="application/atom+xml" href="https://example.com/tags/17/feed.atom"></head>
        <body><p>See /tags/27785/feed.atom</p><a href="/tags/99117/feed.atom">Another feed</a></body>
        """
        #expect(AO3FandomUnion.filterID(fromTagWorksPage: page, tagName: "Doctor Who (2005)") == nil)
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
