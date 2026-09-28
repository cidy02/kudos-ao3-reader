import Foundation
import Testing
@testable import Kudos

/// 1p.4: Series and Authors are `type=` pages of the same subscriptions index.
/// Each keeps only its own rows, even when handed a mixed page.
struct AO3NamedSubscriptionsParseTests {
    private let html = """
    <html><body>
    <dl class="subscription index group">
      <dt><a href="/works/12345">A Work</a> by <a href="/users/w/pseuds/w">w</a></dt>
      <dd><form action="/users/me/subscriptions/1" method="post"></form></dd>
      <dt>
        <a href="/series/999">My Series</a>
        by <a href="/users/seriesauthor/pseuds/pen" rel="author">pen</a>
        and <a href="/users/co/pseuds/co" rel="author">co</a>
      </dt>
      <dd><form action="/users/me/subscriptions/3" method="post"></form></dd>
      <dt><a href="/users/someuser">someuser</a></dt>
      <dd><form action="/users/me/subscriptions/4" method="post"></form></dd>
      <dt><a href="https://archiveofourown.org/users/other">other</a></dt>
    </dl>
    <ol class="pagination actions"><li>1</li><li><a href="?type=series&amp;page=2">2</a></li></ol>
    </body></html>
    """

    @Test func seriesScopeKeepsSeriesRowsWithTheirBylineAndForm() throws {
        let page = try AO3Client.parseNamedSubscriptions(html, scope: .series, page: 1)
        #expect(page.rows.map(\.path) == ["/series/999"])
        let row = try #require(page.rows.first)
        #expect(row.name == "My Series")
        #expect(row.creators.map(\.displayName) == ["pen", "co"])
        #expect(row.unsubscribePath == "/users/me/subscriptions/3")
        #expect(row.seriesSummary?.id == 999)
        #expect(row.seriesSummary?.url.absoluteString == "https://archiveofourown.org/series/999")
        #expect(row.authorRoute == nil)
        #expect(page.totalPages == 2)
    }

    /// A series byline links `/users/…/pseuds/…`; that is not an author row.
    /// An absolute user link is, and a row without a `<dd>` has no form.
    @Test func usersScopeKeepsOnlyUserRows() throws {
        let page = try AO3Client.parseNamedSubscriptions(html, scope: .users, page: 1)
        #expect(page.rows.map(\.path) == ["/users/someuser", "/users/other"])
        #expect(page.rows.map(\.unsubscribePath) == ["/users/me/subscriptions/4", nil])
        #expect(page.rows.map(\.creators.isEmpty) == [true, true])
        #expect(page.rows.first?.authorRoute?.username == "someuser")
        #expect(page.rows.first?.seriesSummary == nil)
    }

    @Test func scopeIsTheTypeParameter() throws {
        let url = try #require(AO3Client.subscriptionsURL(username: "me", page: 2, type: "series"))
        #expect(url.absoluteString == "https://archiveofourown.org/users/me/subscriptions?type=series&page=2")
        #expect(AO3Client.subscriptionsURL(username: "me", page: 1)?.query == "type=works")
    }

    @Test func subtitleCountsThePageInTheScopesNoun() {
        #expect(AO3NamedSubscriptionsCopy.subtitle(scope: .series, count: 1, currentPage: 1, totalPages: 1)
            == "1 series")
        #expect(AO3NamedSubscriptionsCopy.subtitle(scope: .users, count: 3, currentPage: 2, totalPages: 4)
            == "3 authors · page 2 of 4")
    }
}
