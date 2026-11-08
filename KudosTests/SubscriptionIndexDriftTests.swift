import Testing
@testable import Kudos

/// Zero rows from the series/user index are a real empty list only when the
/// `dl.subscription.index.group` container itself is empty. Leftover markup is drift.
struct SubscriptionIndexDriftTests {
    @Test func whitespaceOnlyIndexIsARealEmptyPage() throws {
        let html = """
        <h2 class="heading">My Series Subscriptions</h2>
        <dl class="subscription index group">
        </dl>
        """
        let page = try AO3Client.parseSubscriptionIndex(html, page: 1, type: .series)
        #expect(page.series.isEmpty)
        #expect(page.authors.isEmpty)
    }

    @Test func aRecognizedSeriesRowStillParses() throws {
        let html = """
        <dl class="subscription index group">
          <dt>
            <a href="/series/4242">The Long Road</a>
            by <a rel="author" href="/users/writer/pseuds/Pen">Pen (writer)</a>
          </dt>
          <dd>
            <form action="/users/alice/subscriptions/17" method="post">
              <input type="hidden" name="_method" value="delete" />
            </form>
          </dd>
        </dl>
        """
        let page = try AO3Client.parseSubscriptionIndex(html, page: 1, type: .series)
        #expect(page.series.map(\.title) == ["The Long Road"])
        #expect(page.series.map(\.subscriptionID) == [17])
    }

    @Test func leftoverMarkupDoesNotReadAsAnEmptyFollowList() {
        let drifted = """
        <h2 class="heading">My Series Subscriptions</h2>
        <dl class="subscription index group">
          <li class="subscription"><a href="/series/1">Drifted</a></li>
        </dl>
        """
        let prose = """
        <dl class="subscription index group">
          The list markup changed and this is no longer a row.
        </dl>
        """
        #expect(throws: AO3Error.self) {
            try AO3Client.parseSubscriptionIndex(drifted, page: 2, type: .series)
        }
        #expect(throws: AO3Error.self) {
            try AO3Client.parseSubscriptionIndex(prose, page: 1, type: .users)
        }
    }
}
