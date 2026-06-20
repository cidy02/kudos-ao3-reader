import Testing
@testable import Kudos

/// Tests AO3's HTML scraping against fixed sample markup (the CSS structure AO3
/// emits), so the selectors in `parseSearchPage` / `parseWorkTags` are covered
/// without any network access.
@MainActor
struct AO3ClientTests {
    // MARK: Search results page

    /// One work blurb + a 3-page pagination footer, mirroring AO3's `works/search`.
    static let searchHTML = """
    <html><body>
    <ol class="work index group">
      <li id="work_12345" class="work blurb group">
        <div class="header module">
          <h4 class="heading">
            <a href="/works/12345">A Test Work</a> by
            <a rel="author" href="/users/alice">alice</a>
          </h4>
          <h5 class="fandoms heading">
            <a class="tag" href="/tags/Naruto/works">Naruto</a>
          </h5>
          <ul class="required-tags">
            <li><span class="rating"><span class="text">Teen And Up Audiences</span></span></li>
            <li><span class="warnings"><span class="text">No Archive Warnings Apply</span></span></li>
            <li><span class="category"><span class="text">Gen</span></span></li>
            <li><span class="iswip"><span class="text">Complete Work</span></span></li>
          </ul>
          <p class="datetime">25 Dec 2024</p>
        </div>
        <ul class="series">
          <li>Part <strong>2</strong> of <a href="/series/777">My Series</a></li>
        </ul>
        <blockquote class="userstuff summary"><p>A short summary.</p></blockquote>
        <ul class="tags commas">
          <li class="freeforms"><a class="tag" href="#">Fluff</a></li>
          <li class="freeforms"><a class="tag" href="#">Angst</a></li>
        </ul>
        <dl class="stats">
          <dd class="language">English</dd>
          <dd class="words">12,345</dd>
          <dd class="chapters">5/10</dd>
          <dd class="comments">7</dd>
          <dd class="kudos">890</dd>
          <dd class="hits">10,111</dd>
        </dl>
      </li>
    </ol>
    <ol class="pagination actions">
      <li class="previous">Previous</li>
      <li><a href="?page=1">1</a></li>
      <li><a href="?page=2">2</a></li>
      <li><a href="?page=3">3</a></li>
      <li class="next">Next</li>
    </ol>
    </body></html>
    """

    @Test func parsesSearchBlurbFields() throws {
        let page = try AO3Client.parseSearchPage(Self.searchHTML, page: 1)
        let work = try #require(page.works.first)
        #expect(work.id == 12345)
        #expect(work.title == "A Test Work")
        #expect(work.authors == ["alice"])
        #expect(work.fandoms == ["Naruto"])
        #expect(work.rating == "Teen And Up Audiences")
        #expect(work.isComplete == true)
        #expect(work.tags == ["Fluff", "Angst"])
        #expect(work.summary == "A short summary.")
        #expect(work.words == 12345)
        #expect(work.chapters == "5/10")
        #expect(work.comments == 7)
        #expect(work.kudos == 890)
        #expect(work.hits == 10111)
        #expect(work.seriesTitle == "My Series")
        #expect(work.seriesPosition == 2)
        #expect(work.seriesURL == "https://archiveofourown.org/series/777")
    }

    @Test func parsesPaginationTotal() throws {
        let page = try AO3Client.parseSearchPage(Self.searchHTML, page: 1)
        #expect(page.currentPage == 1)
        #expect(page.totalPages == 3)
    }

    @Test func emptyResultsYieldNoWorks() throws {
        let page = try AO3Client.parseSearchPage("<html><body>No results.</body></html>", page: 2)
        #expect(page.works.isEmpty)
        // With no pagination footer, total falls back to the current page.
        #expect(page.totalPages == 2)
    }

    // MARK: Marked for Later (reading list)

    @Test func buildsMarkedForLaterURL() {
        #expect(
            AO3Client.markedForLaterURL(username: "alice", page: 1)?.absoluteString
                == "https://archiveofourown.org/users/alice/readings?show=to-read"
        )
        #expect(
            AO3Client.markedForLaterURL(username: "alice", page: 3)?.absoluteString
                == "https://archiveofourown.org/users/alice/readings?show=to-read&page=3"
        )
        #expect(AO3Client.markedForLaterURL(username: "   ", page: 1) == nil)
    }

    /// The readings page adds a `reading` class to each blurb `<li>` but is otherwise
    /// the same work-blurb markup as search — so `parseSearchPage` reads it directly.
    static let readingsHTML = """
    <html><body>
    <ol class="reading work index group">
      <li id="work_555" class="reading work blurb group">
        <div class="header module">
          <h4 class="heading">
            <a href="/works/555">Queued Work</a> by <a rel="author" href="/users/bob">bob</a>
          </h4>
          <ul class="required-tags">
            <li><span class="rating"><span class="text">General Audiences</span></span></li>
          </ul>
        </div>
        <h4 class="viewed heading">Marked for Later</h4>
      </li>
    </ol>
    </body></html>
    """

    @Test func parsesReadingsBlurbLikeSearch() throws {
        let page = try AO3Client.parseSearchPage(Self.readingsHTML, page: 1)
        let work = try #require(page.works.first)
        #expect(work.id == 555)
        #expect(work.title == "Queued Work")
        #expect(work.authors == ["bob"])
        #expect(work.rating == "General Audiences")
    }

    // MARK: Work page tag groups

    static let workHTML = """
    <html><body>
    <dl class="work meta group">
      <dd class="fandom tags"><ul class="commas"><li><a class="tag" href="#">Naruto</a></li></ul></dd>
      <dd class="warning tags"><ul><li><a class="tag" href="#">No Archive Warnings Apply</a></li></ul></dd>
      <dd class="relationship tags"><ul><li><a class="tag" href="#">Naruto/Hinata</a></li></ul></dd>
      <dd class="character tags"><ul>
        <li><a class="tag" href="#">Hinata Hyuuga</a></li>
        <li><a class="tag" href="#">Naruto Uzumaki</a></li>
      </ul></dd>
      <dd class="freeform tags"><ul><li><a class="tag" href="#">Fluff</a></li></ul></dd>
      <dd class="category tags"><ul><li><a class="tag" href="#">Gen</a></li></ul></dd>
      <dd class="language">English</dd>
      <dl class="stats">
        <dd class="words">12,345</dd>
        <dd class="chapters">5/10</dd>
        <dd class="kudos">890</dd>
      </dl>
    </dl>
    </body></html>
    """

    @Test func parsesWorkPageTagGroups() throws {
        let groups = try AO3Client.parseWorkTags(from: Self.workHTML)
        #expect(groups.fandoms == ["Naruto"])
        #expect(groups.relationships == ["Naruto/Hinata"])
        #expect(groups.characters == ["Hinata Hyuuga", "Naruto Uzumaki"])
        #expect(groups.freeforms == ["Fluff"])
        #expect(groups.warnings == ["No Archive Warnings Apply"])
        #expect(groups.categories == ["Gen"])
        #expect(groups.language == "English")
        #expect(groups.words == 12345)
        #expect(groups.chapters == "5/10")
        #expect(groups.kudos == 890)
    }
}
