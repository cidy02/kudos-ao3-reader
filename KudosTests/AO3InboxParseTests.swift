import Testing
@testable import Kudos

/// Verifies the AO3 Inbox parser against the page's real structure (otwarchive
/// `inbox/show.html.erb`): `li#feedback_comment_<id>` entries classed
/// read/unread inside `ol.comment.index.group`, each with an `h4.heading.byline`
/// (commenter link, commentable `/…/comments/<id>` link, `span.posted.datetime`),
/// a `div.icon` avatar, and a `blockquote.userstuff` body.
struct AO3InboxParseTests {
    /// A representative inbox: a registered-pseud unread comment on a chaptered
    /// work, a guest comment already replied to, and a tag comment (no work).
    private let html = """
    <html><body>
    <h2 class="heading">My Inbox (12 comments, 3 unread)</h2>
    <form id="inbox-form" class="inbox manage" action="/users/tester/inbox" method="post">
      <ol class="comment index group">
        <li class="unread comment group even" role="article" id="feedback_comment_9001">
          <h4 class="heading byline">
            <a href="/users/reader1/pseuds/ReaderOne">ReaderOne</a> on
            <a href="/works/123456/comments/9001">Chapter 3 of My Great Fic</a>
            <span class="posted datetime">3 days ago</span>
          </h4>
          <div class="icon">
            <a href="/users/reader1/pseuds/ReaderOne"><img alt="" class="icon"
              src="https://example.com/icons/1/standard.png"></a>
          </div>
          <blockquote class="userstuff"><p>Loved this chapter so much!</p></blockquote>
          <h5 class="landmark heading">Comment Actions</h5>
          <ul class="actions" role="menu">
            <li><span class="unread">Unread</span></li>
            <li><a href="/comments/9001/reply">Reply</a></li>
            <li><label><input type="checkbox" name="inbox_comments[]" value="1">Select</label></li>
          </ul>
        </li>
        <li class="read comment group odd" role="article" id="feedback_comment_9002">
          <h4 class="heading byline">
            <span>Driveby Guest</span><span class="role"> (Guest)</span> on
            <a href="/works/123456/comments/9002">My Great Fic</a>
            <span class="posted datetime">5 days ago</span>
          </h4>
          <div class="icon"><span class="visitor icon"></span></div>
          <blockquote class="userstuff"><p>Nice one.</p></blockquote>
          <ul class="actions" role="menu">
            <li><span class="replied" title="replied to">&#10004;</span></li>
          </ul>
        </li>
        <li class="read comment group even" role="article" id="feedback_comment_9003">
          <h4 class="heading byline">
            <a href="/users/tagfan/pseuds/tagfan">tagfan</a> on
            <a href="/tags/Some%20Tag/comments/9003">Some Tag</a>
            <span class="posted datetime">2 weeks ago</span>
          </h4>
          <div class="icon"></div>
          <blockquote class="userstuff"><p>Tag comment body</p></blockquote>
        </li>
      </ol>
    </form>
    <ol class="pagination actions">
      <li>1</li><li><a href="?page=2">2</a></li><li><a href="?page=2">Next</a></li>
    </ol>
    </body></html>
    """

    @Test func parsesEntriesWithIdentityWorkAndState() throws {
        let page = try AO3Client.parseInboxPage(html, page: 1)
        #expect(page.items.count == 3)

        let first = try #require(page.items.first)
        #expect(first.id == 9001)
        #expect(first.commenterName == "ReaderOne")
        #expect(!first.isGuest)
        #expect(first.commenterIdentity?.route?.username == "reader1")
        #expect(first.commenterIdentity?.route?.pseud == "ReaderOne")
        #expect(first.avatarURL?.absoluteString == "https://example.com/icons/1/standard.png")
        #expect(first.subjectTitle == "Chapter 3 of My Great Fic")
        #expect(first.workID == 123456)
        #expect(first.excerpt == "Loved this chapter so much!")
        #expect(first.postedAgo == "3 days ago")
        #expect(first.isUnread)
        #expect(!first.isReplied)
    }

    @Test func parsesGuestCommentAndRepliedState() throws {
        let page = try AO3Client.parseInboxPage(html, page: 1)
        let guest = page.items[1]
        #expect(guest.id == 9002)
        #expect(guest.commenterName == "Driveby Guest")
        #expect(guest.isGuest)
        #expect(guest.commenterIdentity == nil)
        #expect(guest.avatarURL == nil)
        #expect(guest.workID == 123456)
        #expect(!guest.isUnread)
        #expect(guest.isReplied)
    }

    @Test func tagCommentHasNoWorkButKeepsWebLink() throws {
        let page = try AO3Client.parseInboxPage(html, page: 1)
        let tag = page.items[2]
        #expect(tag.workID == nil)
        #expect(tag.subjectTitle == "Some Tag")
        #expect(tag.subjectURL?.path.contains("/tags/") == true)
    }

    @Test func readsHeadingTotalsAndPagination() throws {
        let page = try AO3Client.parseInboxPage(html, page: 1)
        #expect(page.totalComments == 12)
        #expect(page.unreadCount == 3)
        #expect(page.currentPage == 1)
        #expect(page.totalPages == 2)
    }

    @Test func recognizedEmptyInboxParsesAsEmpty() throws {
        // AO3 renders the heading (and the filter form) even with no comments.
        let empty = """
        <html><body>
        <h2 class="heading">My Inbox (0 comments, 0 unread)</h2>
        <form class="narrow-hidden filters" id="inbox-filters" action="/users/tester/inbox"></form>
        </body></html>
        """
        let page = try AO3Client.parseInboxPage(empty, page: 1)
        #expect(page.items.isEmpty)
        #expect(page.totalComments == 0)
        #expect(page.totalPages == 1)
    }

    @Test func unrecognizedMarkupThrowsInsteadOfFabricatingEmpty() {
        let drifted = "<html><body><h1>Archive of Our Own</h1><p>maintenance</p></body></html>"
        #expect(throws: AO3Error.self) {
            _ = try AO3Client.parseInboxPage(drifted, page: 1)
        }
    }

    @Test func buildsInboxURL() {
        #expect(
            AO3Client.inboxURL(username: "tester", page: 1)?.absoluteString
                == "https://archiveofourown.org/users/tester/inbox"
        )
        #expect(
            AO3Client.inboxURL(username: "tester", page: 3)?.absoluteString
                == "https://archiveofourown.org/users/tester/inbox?page=3"
        )
        #expect(AO3Client.inboxURL(username: "   ", page: 1) == nil)
    }
}
