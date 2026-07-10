import Foundation
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
          <li class="relationships"><a class="tag" href="#">Naruto/Hinata</a></li>
          <li class="characters"><a class="tag" href="#">Hinata Hyuuga</a></li>
          <li class="freeforms"><a class="tag" href="#">Fluff</a></li>
          <li class="freeforms"><a class="tag" href="#">Angst</a></li>
          <li><a class="tag" href="#">Uncategorized</a></li>
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
        #expect(work.relationships == ["Naruto/Hinata"])
        #expect(work.characters == ["Hinata Hyuuga"])
        // "Additional Tags" is the catch-all: freeforms + any uncategorized tag.
        #expect(work.tags == ["Fluff", "Angst", "Uncategorized"])
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

    @Test func buildsHistoryURL() {
        // The reading-history page is the readings page with no `show` filter.
        #expect(
            AO3Client.historyURL(username: "alice", page: 1)?.absoluteString
                == "https://archiveofourown.org/users/alice/readings"
        )
        #expect(
            AO3Client.historyURL(username: "alice", page: 4)?.absoluteString
                == "https://archiveofourown.org/users/alice/readings?page=4"
        )
        #expect(AO3Client.historyURL(username: "", page: 1) == nil)
    }

    @Test func buildsSubscriptionsURL() {
        // Scoped to ?type=works so AO3 returns only work subscriptions (and pages them).
        #expect(
            AO3Client.subscriptionsURL(username: "alice", page: 1)?.absoluteString
                == "https://archiveofourown.org/users/alice/subscriptions?type=works"
        )
        #expect(
            AO3Client.subscriptionsURL(username: "alice", page: 2)?.absoluteString
                == "https://archiveofourown.org/users/alice/subscriptions?type=works&page=2"
        )
    }

    // Subscriptions-page parsing is covered by AO3SubscriptionsParseTests — the page is
    // a <dl> of <dt> items, not the li.work.blurb markup this once assumed.

    @Test func buildsSeriesPageURL() throws {
        let series = try #require(URL(string: "https://archiveofourown.org/series/55"))
        #expect(AO3Client.seriesPageURL(series, page: 1)?.absoluteString
            == "https://archiveofourown.org/series/55")
        #expect(AO3Client.seriesPageURL(series, page: 3)?.absoluteString
            == "https://archiveofourown.org/series/55?page=3")
        // An existing page param is replaced, not duplicated.
        let paged = try #require(URL(string: "https://archiveofourown.org/series/55?page=2"))
        #expect(AO3Client.seriesPageURL(paged, page: 4)?.absoluteString
            == "https://archiveofourown.org/series/55?page=4")
    }

    // MARK: AO3 bookmarks page

    @Test func buildsBookmarksURL() {
        #expect(
            AO3Client.bookmarksURL(username: "carol", page: 1)?.absoluteString
                == "https://archiveofourown.org/users/carol/bookmarks"
        )
        #expect(
            AO3Client.bookmarksURL(username: "carol", page: 2)?.absoluteString
                == "https://archiveofourown.org/users/carol/bookmarks?page=2"
        )
        #expect(AO3Client.bookmarksURL(username: "  ", page: 1) == nil)
    }

    /// A bookmarks page: one bookmarked work (id in `bookmark_111`, real work id in
    /// the `/works/789` link) plus a bookmarked series (no `/works/` link). Only the
    /// work should parse; the series bookmark is skipped.
    static let bookmarksHTML = """
    <html><body>
    <ol class="bookmark index group">
      <li id="bookmark_111" class="bookmark blurb group">
        <div class="header module">
          <h4 class="heading">
            <a href="/works/789">Bookmarked Work</a> by <a rel="author" href="/users/carol">carol</a>
          </h4>
          <ul class="required-tags">
            <li><span class="rating"><span class="text">Teen And Up Audiences</span></span></li>
          </ul>
        </div>
        <dl class="stats"><dd class="kudos">42</dd></dl>
        <div class="user module group">
          <blockquote class="userstuff notes"><p>my private note</p></blockquote>
        </div>
      </li>
      <li id="bookmark_222" class="bookmark blurb group">
        <div class="header module">
          <h4 class="heading">
            <a href="/series/55">A Bookmarked Series</a> by <a rel="author" href="/users/dave">dave</a>
          </h4>
        </div>
      </li>
    </ol>
    </body></html>
    """

    @Test func parsesBookmarkedWorksAndSkipsSeries() throws {
        let page = try AO3Client.parseBookmarksPage(Self.bookmarksHTML, page: 1)
        #expect(page.works.count == 1)
        let work = try #require(page.works.first)
        #expect(work.id == 789)   // from the /works/ link, not bookmark_111
        #expect(work.title == "Bookmarked Work")
        #expect(work.authors == ["carol"])
        #expect(work.rating == "Teen And Up Audiences")
        #expect(work.kudos == 42)
    }

    // MARK: Work page tag groups

    static let workHTML = """
    <html><body>
    <h2 class="title heading">A Test Work</h2>
    <h3 class="byline heading"><a rel="author" href="/users/alice">alice</a></h3>
    <div class="summary module">
      <blockquote class="userstuff"><p>A fuller summary.</p></blockquote>
    </div>
    <dl class="work meta group">
      <dd class="rating tags"><ul><li><a class="tag" href="#">Teen And Up Audiences</a></li></ul></dd>
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
      <dd class="published">01 Jan 2026</dd>
      <dt>Completed:</dt><dd class="status">02 Jan 2026</dd>
      <dd class="series"><span class="position">Part 2 of <a href="/series/777">My Series</a></span></dd>
      <dl class="stats">
        <dd class="words">12,345</dd>
        <dd class="chapters">5/10</dd>
        <dd class="kudos">890</dd>
        <dd class="comments">76</dd>
        <dd class="hits">54,321</dd>
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
        #expect(groups.comments == 76)
        #expect(groups.hits == 54321)
    }

    @Test func parsesWorkPageMetadata() throws {
        let metadata = try AO3Client.parseWorkMetadata(from: Self.workHTML, workID: 12345)
        #expect(metadata.id == 12345)
        #expect(metadata.title == "A Test Work")
        #expect(metadata.authors == ["alice"])
        #expect(metadata.summary == "A fuller summary.")
        #expect(metadata.rating == "Teen And Up Audiences")
        #expect(metadata.fandoms == ["Naruto"])
        #expect(metadata.relationships == ["Naruto/Hinata"])
        #expect(metadata.characters == ["Hinata Hyuuga", "Naruto Uzumaki"])
        #expect(metadata.freeforms == ["Fluff"])
        #expect(metadata.warnings == ["No Archive Warnings Apply"])
        #expect(metadata.categories == ["Gen"])
        #expect(metadata.language == "English")
        #expect(metadata.words == 12345)
        #expect(metadata.chapters == "5/10")
        #expect(metadata.kudos == 890)
        #expect(metadata.comments == 76)
        #expect(metadata.hits == 54321)
        #expect(metadata.datePublished == "01 Jan 2026")
        #expect(metadata.dateUpdated == "02 Jan 2026")
        #expect(metadata.isComplete == true)
        #expect(metadata.seriesTitle == "My Series")
        #expect(metadata.seriesURL == "https://archiveofourown.org/series/777")
        #expect(metadata.seriesPosition == 2)
    }

    /// AO3 doesn't class the "Completed:"/"Updated:" `<dt>` label itself — only its
    /// sibling `<dd class="status">` carries a class. This guards against reading the
    /// label from a nonexistent `dt.status` selector (which would silently always miss
    /// and fall back to the chapters-ratio heuristic).
    @Test func parsesWorkInProgressStatusFromUnclassedLabel() throws {
        let wipHTML = """
        <html><body>
        <h2 class="title heading">A WIP</h2>
        <dl class="work meta group">
          <dt>Updated:</dt><dd class="status">03 Jan 2026</dd>
          <dl class="stats">
            <dd class="chapters">3/?</dd>
          </dl>
        </dl>
        </body></html>
        """
        let metadata = try AO3Client.parseWorkMetadata(from: wipHTML, workID: 1)
        #expect(metadata.dateUpdated == "03 Jan 2026")
        #expect(metadata.isComplete == false)
    }

    // MARK: Fandom index (/media/<name>/fandoms) — linear-scan parser

    /// Two letter-group `<ol>`s mirroring AO3's fandom index markup: entities in
    /// names, comma-grouped counts, whitespace, a count-less entry, a duplicate
    /// name across groups, a swapped-attribute-order link, and a non-index `<ol>`
    /// (letter nav) that must be skipped.
    static let fandomIndexHTML = """
    <html><body>
    <ol class="alphabet fandom listbox group">
      <li><a href="#A">A</a></li>
    </ol>
    <ol class="fandom index group">
      <li>
        <a class="tag" href="/tags/A*20Song/works">A Song of Ice &amp; Fire</a>
        (12,345)
      </li>
      <li><a class="tag" href="/tags/Arcane/works">Arcane</a> (987)</li>
      <li><a class="tag" href="/tags/Uncounted/works">Uncounted Fandom</a></li>
    </ol>
    <ol class="fandom index group">
      <li><a href="/tags/Boruto/works" class="tag">Boruto</a> (56)</li>
      <li><a class="tag" href="/tags/Arcane/works">Arcane</a> (987)</li>
      <li><a href="/media">Not a tag link</a> (999)</li>
    </ol>
    </body></html>
    """

    @Test func parsesFandomIndexNamesCountsAndEntities() {
        let fandoms = AO3Client.parseFandomIndex(Self.fandomIndexHTML)

        #expect(fandoms.map(\.name) == [
            "A Song of Ice & Fire", "Arcane", "Uncounted Fandom", "Boruto"
        ])
        #expect(fandoms[0].workCount == 12345) // entities decoded, commas stripped
        #expect(fandoms[1].workCount == 987)
        #expect(fandoms[2].workCount == nil) // no "(n)" after the link
        #expect(fandoms[3].workCount == 56) // href-before-class attribute order
    }

    @Test func fandomIndexSkipsNavListsAndDuplicates() {
        let fandoms = AO3Client.parseFandomIndex(Self.fandomIndexHTML)

        // The alphabet nav <ol> has "fandom" but not "index" in its class list —
        // its "A" anchor must not become a fandom; the repeated "Arcane" appears once.
        #expect(!fandoms.contains { $0.name == "A" })
        #expect(fandoms.count(where: { $0.name == "Arcane" }) == 1)
        // Plain links inside an index block (no class="tag") are skipped.
        #expect(!fandoms.contains { $0.name == "Not a tag link" })
    }

    @Test func fandomIndexOfUnrelatedHTMLIsEmpty() {
        #expect(AO3Client.parseFandomIndex("<html><body><p>maintenance</p></body></html>").isEmpty)
        #expect(AO3Client.parseFandomIndex("").isEmpty)
    }
}
