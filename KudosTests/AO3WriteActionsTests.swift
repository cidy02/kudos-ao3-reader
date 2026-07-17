import Foundation
import Testing
@testable import Kudos

/// Covers the pure, offline pieces of the native AO3 write actions: CSRF / pseud /
/// error parsing and form-body encoding. The actual POST endpoints can only be
/// confirmed against a live signed-in AO3 session.
struct AO3WriteActionsTests {
    @Test func parsesCSRFTokenFromMetaTag() {
        let html = """
        <html><head>
        <meta name="csrf-param" content="authenticity_token">
        <meta name="csrf-token" content="aB3/dEf+gh==">
        </head><body></body></html>
        """
        #expect(AO3Client.parseCSRFToken(from: html) == "aB3/dEf+gh==")
    }

    @Test func missingCSRFTokenReturnsNil() {
        #expect(AO3Client.parseCSRFToken(from: "<html><head></head></html>") == nil)
    }

    @Test func parsesSelectedDefaultPseud() {
        let html = """
        <form>
          <select name="comment[pseud_id]" id="comment_pseud_id">
            <option value="11">altpseud</option>
            <option value="22" selected="selected">mainpseud</option>
          </select>
        </form>
        """
        #expect(AO3Client.parseDefaultPseudID(from: html) == "22")
    }

    @Test func pseudFallsBackToFirstOptionWhenNoneSelected() {
        let html = """
        <select name="comment[pseud_id]">
          <option value="7">only</option>
        </select>
        """
        #expect(AO3Client.parseDefaultPseudID(from: html) == "7")
    }

    // Single-pseud accounts get a hidden input, not a select (otwarchive
    // `_comment_form.html.erb`: `f.hidden_field :pseud_id` unless the user has
    // multiple pseuds) — its value must be parsed and POSTed (CAA-1).
    @Test func parsesHiddenSinglePseudInput() {
        let html = """
        <form action="/works/1/comments" method="post" id="comment_for_1">
          <h4 class="heading">Comment as <span class="byline">solowriter</span>
            <input type="hidden" name="comment[pseud_id]" value="123456"
                   id="comment_pseud_id_for_1">
          </h4>
          <textarea name="comment[comment_content]"></textarea>
        </form>
        """
        #expect(AO3Client.parseDefaultPseudID(from: html) == "123456")
    }

    // Mirrors `ao3_api`'s `get_pseud_id` precedence: the hidden input is
    // checked before any select. (otwarchive never renders both in one form;
    // this pins the tiebreak all the same.)
    @Test func hiddenPseudInputWinsOverSelect() {
        let html = """
        <input type="hidden" name="comment[pseud_id]" value="11">
        <select name="comment[pseud_id]">
          <option value="99" selected="selected">other</option>
        </select>
        """
        #expect(AO3Client.parseDefaultPseudID(from: html) == "11")
    }

    /// The no-JS focused reply page (`/comments/<parent>?add_comment_reply_id=
    /// <parent>`): otwarchive's `_comment_actions.html.erb` renders the full
    /// comment form inside `add_comment_reply_placeholder_<parent>` with id
    /// `comment_for_<parent>`. Synthesized from those templates; sanitized ids.
    private let focusedReplyFormHTML = """
    <html><head>
    <meta name="csrf-param" content="authenticity_token">
    <meta name="csrf-token" content="replyTok3n==">
    </head><body>
    <div id="comments_placeholder">
      <ol class="thread">
        <li id="comment_777" class="comment group even">
          <blockquote class="userstuff"><p>Parent comment text</p></blockquote>
          <ul class="actions" id="navigation_for_comment_777" style="display:none;"></ul>
          <div id="add_comment_reply_placeholder_777" title="Reply to this">
            <div class="post comment" id="comment_form_for_777">
              <form action="/comments/777/comments" method="post" id="comment_for_777">
                <h4 class="heading">Comment as <span class="byline">solowriter</span>
                  <input type="hidden" name="comment[pseud_id]" value="654321"
                         id="comment_pseud_id_for_777">
                </h4>
                <textarea name="comment[comment_content]" id="comment_content_for_777"></textarea>
                <input type="submit" value="Comment" id="comment_submit_for_777">
              </form>
            </div>
          </div>
        </li>
      </ol>
    </div>
    </body></html>
    """

    @Test func parsesFocusedReplyFormCSRFAndPseud() {
        #expect(AO3Client.parseCSRFToken(from: focusedReplyFormHTML) == "replyTok3n==")
        #expect(AO3Client.parseDefaultPseudID(from: focusedReplyFormHTML) == "654321")
    }

    /// A page with a CSRF meta but no pseud control (adult interstitial, plain
    /// unfocused thread page, login bounce) must refuse before any POST — a
    /// pseud-less signed-in comment is guaranteed-rejected server-side, and ids
    /// are never synthesized (CAA-1).
    @Test func formLessPageRefusesToPostWithTypedError() {
        let interstitial = """
        <html><head><meta name="csrf-token" content="stillHasToken=="></head>
        <body><div class="works-show region">
        <p class="caution notice">This work could have adult content.</p>
        <a href="/works/1?view_adult=true">Proceed</a>
        </div></body></html>
        """
        #expect(AO3Client.parseCSRFToken(from: interstitial) != nil)
        #expect(throws: AO3WriteError.noPseudControl) {
            try AO3AuthService.requiredCommentPseudID(in: interstitial, preferredName: nil)
        }
        #expect(throws: AO3WriteError.noPseudControl) {
            try AO3AuthService.requiredCommentPseudID(in: interstitial, preferredName: "AnyPseud")
        }
    }

    @Test func requiredPseudReturnsTheResolvedID() throws {
        let id = try AO3AuthService.requiredCommentPseudID(
            in: focusedReplyFormHTML, preferredName: nil
        )
        #expect(id == "654321")
    }

    @Test func readsRenderedErrorList() {
        let html = """
        <html><body>
        <ul class="errorlist"><li>Comment content can't be blank</li></ul>
        </body></html>
        """
        #expect(AO3Client.writeErrorMessage(in: html) == "Comment content can't be blank")
        #expect(AO3Client.writeErrorMessage(in: "<html><body>fine</body></html>") == nil)
    }

    // otwarchive reports blocked comments and failed deletes as
    // `flash[:comment_error]` → `div.flash.comment_error` — a class the old
    // `.flash.error` selector never matched (CAA-2).
    @Test func recognizesCommentErrorFlash() {
        let html = """
        <html><body><div class="flash comment_error">
        Sorry, you have been blocked by one or more of this work's creators.
        </div></body></html>
        """
        #expect(AO3Client.writeErrorMessage(in: html)
            == "Sorry, you have been blocked by one or more of this work's creators.")
    }

    // The Inbox mass-edit failure branch sets `flash[:caution]` (T91-RF9).
    @Test func recognizesCautionFlash() {
        let html = """
        <html><body><div class="flash caution">Please select something first.</div></body></html>
        """
        #expect(AO3Client.writeErrorMessage(in: html) == "Please select something first.")
    }

    // otwarchive's static warning boxes (block/mute confirm pages, change-email)
    // are `div.caution.notice` — no `flash` class. `.flash.caution` must not
    // match them: `parseAuthorModerationForm` runs this scan over the confirm
    // page itself, and a false match would break block/mute entirely.
    @Test func staticCautionNoticeBoxIsNotAWriteError() {
        let confirmPage = """
        <html><body>
        <h2 class="heading">Block SomeUser</h2>
        <div class="caution notice"><p>Are you sure you want to block SomeUser?</p></div>
        </body></html>
        """
        #expect(AO3Client.writeErrorMessage(in: confirmPage) == nil)
    }

    // MARK: Write-response verdicts (CAA-2)

    @Test func commentNoticeIsPositiveSuccessEvidence() {
        let html = """
        <html><body><div class="flash comment_notice">Comment created!</div>
        <div id="comments_placeholder"><ol class="thread"></ol></div></body></html>
        """
        #expect(AO3Client.commentWriteVerdict(status: 200, body: html) == .success)
    }

    @Test func plainNoticeFlashIsAlsoSuccessEvidence() {
        // The unreviewed-delete branch and Inbox mass-edits confirm via
        // `flash[:notice]`, rendered by the application layout.
        let html = """
        <html><body><div class="flash notice">Comment deleted.</div></body></html>
        """
        #expect(AO3Client.commentWriteVerdict(status: 200, body: html) == .success)
    }

    @Test func bareOK200IsUnconfirmedNotSuccess() {
        // Maintenance pages, blank bodies, and interstitials return 200 with
        // neither flash — the write may or may not have landed.
        let maintenance = """
        <html><body><h1>Archive Down for Maintenance</h1>
        <p>The Archive of Our Own is briefly unavailable.</p></body></html>
        """
        #expect(AO3Client.commentWriteVerdict(status: 200, body: maintenance) == .unconfirmed)
        #expect(AO3Client.commentWriteVerdict(status: 200, body: "") == .unconfirmed)
    }

    @Test func moderationNoteIsNotSuccessEvidence() {
        // The moderated-work note inside the comment form is a bare `p.notice`;
        // only `div.flash.notice` (both classes) may confirm success.
        let html = """
        <html><body><p class="notice">
        This work's creator has chosen to moderate comments.
        </p></body></html>
        """
        #expect(AO3Client.commentWriteVerdict(status: 200, body: html) == .unconfirmed)
    }

    @Test func exactCommentFormNoticeCarriesHiddenPostEvidence() {
        let moderated = """
        <div id="add_comment_placeholder">
          <form id="comment_for_42">
            <p class="notice">Comments on this work are moderated.</p>
          </form>
        </div>
        """
        let ordinary = """
        <div id="add_comment_placeholder"><form id="comment_for_42"></form></div>
        """
        let unrelated = """
        <p class="notice">A notice outside the actual comment form.</p>
        <div id="add_comment_placeholder"><form id="comment_for_42"></form></div>
        """
        let moderatedReply = """
        <div id="add_comment_reply_placeholder_777">
          <form id="comment_for_777"><p class="notice">Replies are moderated.</p></form>
        </div>
        """
        #expect(AO3Client.commentFormMayHidePostedComment(moderated, commentableID: 42))
        #expect(!AO3Client.commentFormMayHidePostedComment(ordinary, commentableID: 42))
        #expect(!AO3Client.commentFormMayHidePostedComment(unrelated, commentableID: 42))
        #expect(AO3Client.commentFormMayHidePostedComment(
            moderatedReply, commentableID: 777
        ))
    }

    @Test func deleteFailureBodyIsRejectedDespite200() {
        // otwarchive redirects a failed delete WITH a 200 final page carrying
        // `flash[:comment_error]` — the status alone proves nothing.
        let html = """
        <html><body><div class="flash comment_error">We couldn't delete that comment.</div>
        </body></html>
        """
        #expect(AO3Client.commentWriteVerdict(status: 200, body: html)
            == .rejected("We couldn't delete that comment."))
    }

    @Test func errorFlashOutranksSuccessFlash() {
        let html = """
        <html><body>
        <div class="flash comment_error">Couldn't save comment!</div>
        <div class="flash notice">Unrelated notice.</div>
        </body></html>
        """
        #expect(AO3Client.commentWriteVerdict(status: 200, body: html)
            == .rejected("Couldn't save comment!"))
    }

    @Test func non2xxWithoutParsedMessageIsRejectedWithNilReason() {
        #expect(AO3Client.commentWriteVerdict(status: 500, body: "<html></html>")
            == .rejected(nil))
        #expect(AO3Client.commentWriteVerdict(status: 422, body: "")
            == .rejected(nil))
    }

    // MARK: Comment-form URL shapes (CAA-1)

    @MainActor
    @Test func commentFormURLsRenderTheActualForms() {
        // Top-level: the interstitial hides the form without `view_adult=true`.
        #expect(AO3AuthService.commentFormURL(workID: 42).absoluteString
            == "https://archiveofourown.org/works/42?view_adult=true")
        // Reply: only the focused thread page renders `form#comment_for_<parent>`.
        #expect(AO3AuthService.commentReplyFormURL(parentCommentID: 777).absoluteString
            == "https://archiveofourown.org/comments/777?add_comment_reply_id=777")
        // The POST endpoints themselves are unchanged.
        #expect(AO3AuthService.commentReplyEndpoint(parentCommentID: 777).absoluteString
            == "https://archiveofourown.org/comments/777/comments")
        #expect(AO3AuthService.commentsEndpoint(workID: 42).absoluteString
            == "https://archiveofourown.org/works/42/comments")
    }

    @Test func detectsSubscribedStateAndUnsubscribePath() {
        let subscribed = """
        <form action="/users/me/subscriptions/789" method="post">
          <input type="hidden" name="_method" value="delete">
          <input type="submit" value="Unsubscribe">
        </form>
        """
        let result = AO3Client.parseSubscription(from: subscribed)
        #expect(result.isSubscribed)
        #expect(result.unsubscribePath == "/users/me/subscriptions/789")
    }

    @Test func detectsNotSubscribedState() {
        let notSubscribed = """
        <form action="/users/me/subscriptions" method="post">
          <input type="hidden" name="subscription[subscribable_type]" value="Work">
          <input type="submit" value="Subscribe">
        </form>
        """
        let result = AO3Client.parseSubscription(from: notSubscribed)
        #expect(!result.isSubscribed)
        #expect(result.unsubscribePath == nil)
    }

    // MARK: Work-page action states (fixtures trimmed from live captures, 2026-07-16)

    private final class FixtureAnchor {}

    private func workFixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle(for: FixtureAnchor.self).url(forResource: name, withExtension: "html")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// A bookmarked work's page embeds the *edit* form (`/bookmarks/<id>` +
    /// `_method=put`) prefilled with the bookmark's current values — the state
    /// the actions menu shows as "Edit Bookmark on AO3".
    @Test func readsExistingBookmarkFromWorkPageEditForm() throws {
        let html = try workFixture("ao3_work_bookmarked_subscribed")
        let existing = try #require(AO3Client.parseExistingBookmark(from: html))
        #expect(existing.editPath == "/bookmarks/2997787566")
        #expect(existing.input.notes == "Test bookmark")
        #expect(existing.input.tags.isEmpty)
        #expect(existing.input.isPrivate)
        #expect(!existing.input.isRec)
        #expect(existing.collectionNames.isEmpty)
        // Same live page: the subscription form is the delete variant.
        #expect(AO3Client.parseSubscription(from: html).isSubscribed)
    }

    /// A never-bookmarked work renders only the create form
    /// (`/works/<id>/bookmarks`, no method override) → no existing bookmark.
    @Test func createOnlyBookmarkFormMeansNoExistingBookmark() throws {
        let html = try workFixture("ao3_work_unbookmarked")
        #expect(AO3Client.parseExistingBookmark(from: html) == nil)
        #expect(!AO3Client.parseSubscription(from: html).isSubscribed)
    }

    @Test func parsesCollectionsIndex() throws {
        let html = """
        <html><body>
        <ul class="collection index group">
          <li class="collection picture blurb group">
            <div class="header module group">
              <h4 class="heading">
                <a href="/collections/cool_fics">Cool Fics</a> by
                <a class="owner" href="/users/OwnerAccount">Owner Pseud</a> and
                <a class="mod" href="/users/ModAccount">Mod Pseud</a>
              </h4>
            </div>
          </li>
          <li class="collection blurb group">
            <h4 class="heading"><a href="/collections/another_one/profile">Another One</a></h4>
          </li>
        </ul>
        </body></html>
        """
        let collections = try AO3Client.parseCollections(from: html)
        #expect(collections.count == 2)
        #expect(collections.map(\.name) == ["cool_fics", "another_one"])
        #expect(collections.first?.title == "Cool Fics")
        #expect(collections.first?.maintainerNames == ["Owner Pseud", "Mod Pseud"])
        #expect(collections.first?.maintainerIdentities.map(\.route?.username)
            == ["OwnerAccount", "ModAccount"])
    }

    @Test func parsesBookmarkPseudField() {
        let html = """
        <select name="bookmark[pseud_id]">
          <option value="5" selected>me</option>
        </select>
        """
        #expect(AO3Client.parseDefaultPseudID(from: html, field: "bookmark[pseud_id]") == "5")
    }

    @MainActor
    @Test func formEncodingPercentEncodesKeysAndValues() {
        let body = AO3AuthService.formEncoded([
            ("authenticity_token", "a b/c"),
            ("kudo[commentable_id]", "12345"),
            ("kudo[commentable_type]", "Work"),
        ])
        let string = String(decoding: body, as: UTF8.self)
        #expect(string ==
            "authenticity_token=a%20b%2Fc&kudo%5Bcommentable_id%5D=12345&kudo%5Bcommentable_type%5D=Work")
    }
}
