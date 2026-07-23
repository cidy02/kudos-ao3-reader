import Foundation
import Testing
@testable import Kudos

private final class InboxBundleAnchor {}

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

    private func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle(for: InboxBundleAnchor.self).url(forResource: name, withExtension: "html")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func visibleWorkMetadataDeduplicatesInScreenOrder() {
        #expect(AO3InboxModel.uniqueWorkIDs([123, 456, 123, 789, 456]) == [123, 456, 789])
        #expect(AO3InboxModel.uniqueWorkIDs([]).isEmpty)
    }

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
        #expect(first.canReply)
        #expect(first.chapterPosition == 3)
        #expect(first.chapterIndicatorTitle == "Chapter 3")
        #expect(first.workTitle == "My Great Fic")
        #expect(first.participantRole(workAuthors: ["ReaderOne"]) == .author)
        #expect(first.participantRole(workAuthors: []) == .user)
        #expect(first.participantRole(
            workAuthors: ["ReaderOne"], currentUsername: "reader1"
        ) == .me)
        let creator = try #require(AO3AuthorIdentity(
            displayName: "Work Pseud", href: "/users/reader1/pseuds/Work%20Pseud"
        ))
        #expect(first.participantRole(
            workAuthors: ["Work Pseud"],
            workAuthorIdentities: [creator],
            currentUsername: "someoneElse"
        ) == .author)
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
        #expect(!guest.canReply)
        #expect(guest.chapterPosition == nil)
        #expect(guest.workTitle == "My Great Fic")
        #expect(guest.participantRole(workAuthors: ["Someone Else"]) == .guest)
    }

    @Test func tagCommentHasNoWorkButKeepsWebLink() throws {
        let page = try AO3Client.parseInboxPage(html, page: 1)
        let tag = page.items[2]
        #expect(tag.workID == nil)
        #expect(tag.subjectTitle == "Some Tag")
        #expect(tag.subjectURL?.path.contains("/tags/") == true)
    }

    @Test func anonymousCreatorAlwaysResolvesToAuthorRole() {
        #expect(AO3CommentParticipantRole.resolve(
            name: "Anonymous Creator",
            isGuest: false,
            isAnonymousCreator: true,
            workAuthors: []
        ) == .author)
        #expect(AO3CommentParticipantRole.resolve(
            name: "Anonymous Creator", isGuest: true, workAuthors: []
        ) == .guest)
    }

    @Test func readsHeadingTotalsAndPagination() throws {
        let page = try AO3Client.parseInboxPage(html, page: 1)
        #expect(page.totalComments == 12)
        #expect(page.unreadCount == 3)
        #expect(page.currentPage == 1)
        #expect(page.totalPages == 2)
    }

    @Test func parsesFixtureDerivedBulkFormAndDistinctInboxRowIDs() throws {
        let page = try AO3Client.parseInboxPage(try fixture("ao3_inbox_manage"), page: 1)
        let form = try #require(page.bulkForm)

        #expect(form.actionURL.path == "/users/tester/inbox")
        #expect(form.htmlMethod == "post")
        #expect(form.httpMethodOverride == "put")
        #expect(form.csrfToken == "csrf-inbox-123==")
        #expect(form.hiddenFields.contains(AO3FormField(name: "source", value: "inbox")))
        #expect(form.checkboxFieldName == "inbox_comments[]")
        #expect(form.actionFields[.markRead] == AO3FormField(name: "read", value: "Mark Read"))
        #expect(form.actionFields[.markUnread] == AO3FormField(name: "unread", value: "Mark Unread"))
        #expect(form.actionFields[.delete] == AO3FormField(name: "delete", value: "Delete From Inbox"))
        #expect(page.items.map(\.id) == [9001, 9002, 9003])
        #expect(page.items.compactMap(\.bulkSelectionField?.value) == ["501", "502", "503"])
    }

    @Test func parsesFixtureDerivedFiltersAndBuildsTheirGETURL() throws {
        let page = try AO3Client.parseInboxPage(try fixture("ao3_inbox_manage"), page: 1)
        let filters = try #require(page.filterForm)
        let read = try #require(filters.fields.first(where: { $0.name == "filters[read]" }))
        let replied = try #require(filters.fields.first(where: { $0.name == "filters[replied_to]" }))
        let date = try #require(filters.fields.first(where: { $0.name == "filters[date]" }))

        #expect(read.title == "Read")
        #expect(read.options.map(\.value) == ["all", "false", "true"])
        #expect(read.selectedValue == "false")
        #expect(replied.title == "Replied To")
        #expect(replied.selectedValue == "all")
        #expect(date.title == "Sort by Date")
        #expect(date.selectedValue == "desc")

        let url = try #require(filters.url(values: [
            read.name: "true",
            replied.name: "false",
            date.name: "asc"
        ], page: 2))
        let values = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.compactMap { item in item.value.map { (item.name, $0) } } ?? [])
        #expect(values["locale"] == "en")
        #expect(values["filters[read]"] == "true")
        #expect(values["filters[replied_to]"] == "false")
        #expect(values["filters[date]"] == "asc")
        #expect(values["page"] == "2")
    }

    @MainActor
    @Test func buildsFixtureDerivedBulkRequestBody() throws {
        let page = try AO3Client.parseInboxPage(try fixture("ao3_inbox_manage"), page: 1)
        let form = try #require(page.bulkForm)
        let body = AO3AuthService.formEncoded(try #require(
            form.parameters(for: Array(page.items.prefix(2)), action: .markRead)
        ))
        #expect(String(decoding: body, as: UTF8.self) ==
            "_method=put&authenticity_token=csrf-inbox-123%3D%3D&source=inbox"
                + "&inbox_comments%5B%5D=501&inbox_comments%5B%5D=502&read=Mark%20Read")
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

    // MARK: T91-RF6 — admin-hidden/unavailable rows

    /// AO3's current template renders an admin-hidden comment as a bare
    /// `<li id="feedback_comment_…">` with no `h4.heading.byline` — just a
    /// message and its actions/checkbox. Before the fix, `parseInboxItem`
    /// threw on this shape and the page's `compactMap` silently discarded it;
    /// this proves the row survives as a minimal, still-selectable tombstone
    /// instead of vanishing from `items`.
    @Test func adminHiddenRowBecomesATombstoneInsteadOfBeingDropped() throws {
        let html = """
        <html><body>
        <h2 class="heading">My Inbox (2 comments, 1 unread)</h2>
        <ol class="comment index group">
          <li class="unread comment group even" role="article" id="feedback_comment_9001">
            <h4 class="heading byline">
              <a href="/users/reader1/pseuds/ReaderOne">ReaderOne</a> on
              <a href="/works/123456/comments/9001">My Great Fic</a>
              <span class="posted datetime">3 days ago</span>
            </h4>
            <div class="icon">
              <a href="/users/reader1/pseuds/ReaderOne"><img alt="" class="icon"
                src="https://example.com/icons/1/standard.png"></a>
            </div>
            <blockquote class="userstuff"><p>Loved this chapter so much!</p></blockquote>
            <ul class="actions" role="menu">
              <li><label><input type="checkbox" name="inbox_comments[]" value="1">Select</label></li>
            </ul>
          </li>
          <li class="read comment group odd" role="article" id="feedback_comment_9099">
            <p>This comment has been hidden by an admin.</p>
            <ul class="actions" role="menu">
              <li><label><input type="checkbox" name="inbox_comments[]" value="2">Select</label></li>
            </ul>
          </li>
        </ol>
        </body></html>
        """
        let page = try AO3Client.parseInboxPage(html, page: 1)
        #expect(page.items.count == 2)

        let tombstone = try #require(page.items.last)
        #expect(tombstone.id == 9099)
        #expect(tombstone.isUnavailable)
        #expect(!tombstone.isUnread)
        #expect(tombstone.subjectTitle.isEmpty)
        #expect(tombstone.excerpt.isEmpty)
        #expect(!tombstone.canReply)
        #expect(tombstone.bulkSelectionField?.value == "2")

        let normal = try #require(page.items.first)
        #expect(!normal.isUnavailable)
    }

    /// If AO3 rendered rows but *none* of them could be represented at all
    /// (markup drift beyond the known admin-hidden tombstone shape — here, a
    /// row whose own id doesn't even parse), the page must fail honestly
    /// instead of returning an empty `items` array that the UI would render
    /// as a fabricated "No comments yet."
    @Test func allUnparseableRowsFailInsteadOfFabricatingEmptyInbox() {
        let malformed = """
        <html><body>
        <h2 class="heading">My Inbox (1 comments, 0 unread)</h2>
        <ol class="comment index group">
          <li class="read comment group even" role="article" id="feedback_comment_">
            <p>This comment is currently unavailable.</p>
          </li>
        </ol>
        </body></html>
        """
        #expect(throws: AO3Error.self) {
            _ = try AO3Client.parseInboxPage(malformed, page: 1)
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
