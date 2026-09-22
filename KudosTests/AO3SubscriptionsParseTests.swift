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

    /// The unsubscribe form is the `<dd>` after the work `<dt>`. Series and
    /// user rows have forms too, and they are not stored: those rows are not works.
    @Test func readsTheUnsubscribeActionBesideEachWork() throws {
        let index = try AO3Client.parseSubscriptionsIndex(html, page: 1)
        #expect(index.page.works.map(\.id) == [45_678_901, 12_345])
        #expect(index.unsubscribePaths == [
            45_678_901: "/users/me/subscriptions/1",
            12_345: "/users/me/subscriptions/2"
        ])
    }

    /// A work `<dt>` with no sibling `<dd>` keeps the work and omits the path.
    /// The form that belongs to the next work is not borrowed.
    @Test func aWorkWithoutAnUnsubscribeFormKeepsTheRowAndOmitsThePath() throws {
        let bare = """
        <html><body>
        <dl class="subscription index group">
          <dt>
            <a href="/works/11">Bare</a>
            by <a href="/users/a/pseuds/a" rel="author">a</a>
          </dt>
          <dt>
            <a href="/works/22">Formed</a>
            by <a href="/users/b/pseuds/b" rel="author">b</a>
          </dt>
          <dd><form action="/users/me/subscriptions/9" method="post"></form></dd>
        </dl>
        </body></html>
        """
        let index = try AO3Client.parseSubscriptionsIndex(bare, page: 1)
        #expect(index.page.works.map(\.id) == [11, 22])
        #expect(index.unsubscribePaths == [22: "/users/me/subscriptions/9"])
    }
}
