import Foundation
import Testing
@testable import Kudos

/// Verifies the AO3 subscriptions parser against the page's real markup: a
/// `<dl class="subscription index group">` of `<dt>` items (not work blurbs), mixing
/// work, series, and user subscriptions. Only work subscriptions should surface.
struct AO3SubscriptionsParseTests {
    /// A representative subscriptions page: two works (one with co-authors), plus a
    /// series and a user subscription that must be ignored, and a pagination control.
    private let html = """
    <html><body>
    <dl class="subscription index group">
      <dt>
        <a href="/works/45678901">A Study in Pink</a>
        by <a href="/users/holmes/pseuds/holmes" rel="author">holmes</a>
      </dt>
      <dd><form action="/users/me/subscriptions/1" method="post"></form></dd>
      <dt>
        <a href="/works/12345">Another Fic</a>
        by <a href="/users/writer/pseuds/penname" rel="author">penname</a>
        and <a href="/users/cowriter/pseuds/cowriter" rel="author">cowriter</a>
      </dt>
      <dd><form action="/users/me/subscriptions/2" method="post"></form></dd>
      <dt>
        <a href="/series/999">My Series</a>
        by <a href="/users/seriesauthor/pseuds/seriesauthor" rel="author">seriesauthor</a>
      </dt>
      <dd><form action="/users/me/subscriptions/3" method="post"></form></dd>
      <dt>
        <a href="/users/someuser">someuser</a>
      </dt>
      <dd><form action="/users/me/subscriptions/4" method="post"></form></dd>
    </dl>
    <ol class="pagination actions">
      <li>1</li><li>2</li><li><a href="?type=works&amp;page=3">3</a></li>
      <li><a href="?type=works&amp;page=2">Next</a></li>
    </ol>
    </body></html>
    """

    @Test func keepsOnlyWorkSubscriptions() throws {
        let page = try AO3Client.parseSubscriptionsPage(html, page: 1)
        // The series and user subscriptions carry no /works/ link and are dropped.
        #expect(page.works.count == 2)
        #expect(page.works.map(\.id) == [45678901, 12345])
        #expect(page.works.map(\.title) == ["A Study in Pink", "Another Fic"])
    }

    @Test func readsTitleAndAllBylineAuthors() throws {
        let page = try AO3Client.parseSubscriptionsPage(html, page: 1)
        #expect(page.works[0].authors == ["holmes"])
        #expect(page.works[0].authorIdentities.first?.route?.username == "holmes")
        // Co-authored works list every byline pseud.
        #expect(page.works[1].authors == ["penname", "cowriter"])
        #expect(page.works[1].authorIdentities.count == 2)
        #expect(page.works[1].authorText == "penname, cowriter")
    }

    @Test func usesLargestPaginationNumberForTotal() throws {
        let page = try AO3Client.parseSubscriptionsPage(html, page: 1)
        #expect(page.currentPage == 1)
        #expect(page.totalPages == 3)
    }

    // MARK: Series and user indexes
    //
    // Fixtures follow otwarchive's subscriptions index (see the HTML comments),
    // not the shortened work-list sample above.

    @Test func parsesSeriesSubscriptionsFromTheIndexTemplate() throws {
        let page = try AO3Client.parseSubscriptionIndex(fixture("ao3_subscriptions_series"), page: 1, type: .series)
        #expect(page.authors.isEmpty)
        #expect(page.currentPage == 1)
        #expect(page.totalPages == 3)
        #expect(page.series.map(\.subscriptionID) == [17, 18, 19])
        #expect(page.series.map(\.title) == ["The Long Road", "Quiet Things", "Deleted item"])
        #expect(page.series.map(\.seriesID) == [4242, 7, nil])

        let linked = page.series[0]
        #expect(linked.url?.path == "/series/4242")
        #expect(linked.creatorNames == ["Pen (writer)", "quill"])
        #expect(linked.creatorIdentities[0].route?.username == "writer")
        #expect(linked.creatorIdentities[0].route?.pseud == "Pen")
        #expect(linked.creatorIdentities[1].route?.username == "quill")

        let anonymous = page.series[1]
        #expect(anonymous.creatorNames == ["Anonymous"])
        #expect(anonymous.creatorIdentities.first?.kind == .anonymous)
        #expect(anonymous.creatorIdentities.first?.route == nil)

        #expect(page.series[2].url == nil)
        #expect(page.series[2].navigationSummary == nil)
        #expect(linked.navigationSummary?.id == 4242)
    }

    @Test func parsesUserSubscriptionsFromTheIndexTemplate() throws {
        let page = try AO3Client.parseSubscriptionIndex(fixture("ao3_subscriptions_users"), page: 1, type: .users)
        #expect(page.series.isEmpty)
        #expect(page.totalPages == 1)
        #expect(page.authors.map(\.subscriptionID) == [21, 22])
        #expect(page.authors.map(\.name) == ["someuser", "Deleted item"])
        #expect(page.authors[0].route?.username == "someuser")
        #expect(page.authors[0].route?.pseud == nil)
        #expect(page.authors[1].route == nil)
    }

    @Test func emptySeriesIndexIsARealEmptyPage() throws {
        let html = """
        <h2 class="heading">My Series Subscriptions</h2>
        <dl class="subscription index group"></dl>
        """
        let page = try AO3Client.parseSubscriptionIndex(html, page: 1, type: .series)
        #expect(page.series.isEmpty)
        #expect(page.totalPages == 1)
    }

    @Test func missingSubscriptionListThrowsInsteadOfLookingEmpty() {
        #expect(throws: AO3Error.self) {
            try AO3Client.parseSubscriptionIndex(
                "<html><body><p>Nothing followed</p></body></html>",
                page: 1,
                type: .series
            )
        }
    }

    @Test func seriesIndexThatContainsAWorkLinkThrows() {
        let html = """
        <dl class="subscription index group">
          <dt><a href="/works/456">Nope</a></dt>
          <dd><form action="/users/alice/subscriptions/9" method="post">
            <input type="hidden" name="_method" value="delete" />
          </form></dd>
        </dl>
        """
        #expect(throws: AO3Error.self) {
            try AO3Client.parseSubscriptionIndex(html, page: 1, type: .series)
        }
    }

    @Test func userIndexRejectsASeriesShapedRow() throws {
        #expect(throws: AO3Error.self) {
            try AO3Client.parseSubscriptionIndex(fixture("ao3_subscriptions_series"), page: 1, type: .users)
        }
    }

    private final class BundleAnchor {}

    private func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle(for: BundleAnchor.self).url(forResource: name, withExtension: "html")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }
}
