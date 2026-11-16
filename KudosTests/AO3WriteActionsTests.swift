import Foundation
import Testing
@testable import Kudos

private final class WorkSubscribeStub: URLProtocol, @unchecked Sendable {
    struct Hit: Sendable {
        var method: String
        var url: URL
        var body: String
        var referer: String?
        var csrfHeader: String?
    }

    private static let lock = NSLock()
    private static var html = ""
    private static var postStatus = 200
    private static var postBody = ""
    private static var responder: (@Sendable (URLRequest) -> (status: Int, body: String))?
    private static var hits: [Hit] = []

    static func reset(
        html: String = "",
        postStatus: Int = 200,
        postBody: String = #"<div class="flash notice">You are now following A Quiet Harbour.</div>"#,
        responder: (@Sendable (URLRequest) -> (status: Int, body: String))? = nil
    ) {
        lock.lock()
        self.html = html
        self.postStatus = postStatus
        self.postBody = postBody
        self.responder = responder
        hits = []
        lock.unlock()
    }

    static func recordedMethods() -> [String] {
        recordedHits().map(\.method)
    }

    static func recordedHits() -> [Hit] {
        lock.lock()
        defer { lock.unlock() }
        return hits
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let method = request.httpMethod ?? "GET"
        let hit = Hit(
            method: method,
            url: url,
            body: Self.bodyText(of: request),
            referer: request.value(forHTTPHeaderField: "Referer"),
            csrfHeader: request.value(forHTTPHeaderField: "X-CSRF-Token")
        )
        Self.lock.lock()
        Self.hits.append(hit)
        let html = Self.html
        let postStatus = Self.postStatus
        let postBody = Self.postBody
        let responder = Self.responder
        Self.lock.unlock()

        let (status, body): (Int, String) = if let responder {
            responder(request)
        } else if method == "GET" {
            (200, html)
        } else {
            (postStatus, postBody)
        }
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLSession hands a protocol its POST body as a stream.
    private static func bodyText(of request: URLRequest) -> String {
        if let data = request.httpBody { return String(bytes: data, encoding: .utf8) ?? "" }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}

/// Covers offline parsing, form encoding, and the work Subscribe decision with a
/// URLProtocol stub. The actual POST endpoints remain unverified against live AO3.
@Suite(.serialized)
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

    /// `error_messages_for` (otwarchive `validation_helper.rb`): the list a
    /// re-rendered form carries. Nothing matched it, so a refused bookmark said
    /// "Bookmarked." and closed its sheet (audit A4-3).
    @MainActor
    @Test func readsAO3sValidationList() {
        let html = """
        <html><body><div id="main">
        <div id="error" class="error"><h4>Sorry! We couldn't save this bookmark because:</h4>
        <ul><li>Notes must be less than 5000 characters long.</li></ul></div>
        <form><textarea>They finished successfully.</textarea></form>
        </div></body></html>
        """
        #expect(AO3Client.writeErrorMessage(in: html) == "Notes must be less than 5000 characters long.")
        #expect(throws: AO3WriteError.self) {
            try AO3AuthService.readingsWriteResult(
                status: 200, body: html, success: "Marked for later.", rejectedFallback: "Couldn't mark for later."
            )
        }
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
        #expect(AO3AuthService.workFormURL(workID: 42).absoluteString
            == "https://archiveofourown.org/works/42?view_adult=true")
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

    @MainActor
    @Test func workSubscribeIntentDoesNotSendTheOppositeWrite() async throws {
        let auth = AO3AuthService(
            vault: MemoryAO3SessionVault(),
            validator: InboxTestSessionValidator(),
            loginPerformer: DynamicInboxTestLoginPerformer(),
            cookieManager: MockAO3CookieManager(),
            removalTracker: MemoryAO3SessionRemovalTracker()
        )
        await auth.login(username: "alice", password: "pw")
        let config = AO3Client.makeAnonymousSessionConfiguration()
        config.protocolClasses = [WorkSubscribeStub.self]
        let client = AO3Client(session: URLSession(configuration: config), paceSleep: { _ in })

        WorkSubscribeStub.reset(html: """
        <html><head><meta name="csrf-token" content="token"></head><body class="logged-in">
          <form action="/users/alice/subscriptions" method="post">
            <input type="submit" value="Subscribe">
          </form>
        </body></html>
        """)
        let unsubscribed = try await auth.toggleSubscribe(workID: 42, to: false, using: client)
        #expect(unsubscribed == "Unsubscribed.")
        #expect(WorkSubscribeStub.recordedMethods() == ["GET"])

        WorkSubscribeStub.reset(html: """
        <html><head><meta name="csrf-token" content="token"></head><body class="logged-in">
          <form action="/users/alice/subscriptions/789" method="post">
            <input type="hidden" name="_method" value="delete">
            <input type="submit" value="Unsubscribe">
          </form>
        </body></html>
        """)
        let subscribed = try await auth.toggleSubscribe(workID: 42, to: true, using: client)
        #expect(subscribed == "You're already subscribed.")
        #expect(WorkSubscribeStub.recordedMethods() == ["GET"])
    }

    @MainActor
    private func makeSignedInAuth(username: String = "alice") async -> AO3AuthService {
        let auth = AO3AuthService(
            vault: MemoryAO3SessionVault(),
            validator: InboxTestSessionValidator(),
            loginPerformer: DynamicInboxTestLoginPerformer(),
            cookieManager: MockAO3CookieManager(),
            removalTracker: MemoryAO3SessionRemovalTracker()
        )
        await auth.login(username: username, password: "pw")
        return auth
    }

    private func stubWorkClient() -> AO3Client {
        let config = AO3Client.makeAnonymousSessionConfiguration()
        config.protocolClasses = [WorkSubscribeStub.self]
        return AO3Client(session: URLSession(configuration: config), paceSleep: { _ in })
    }

    private func formFields(_ body: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in body.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            let key = parts[0].removingPercentEncoding ?? parts[0]
            result[key] = parts.count > 1 ? (parts[1].removingPercentEncoding ?? parts[1]) : ""
        }
        return result
    }

    private func workSubscribeHTML(subscriptionID: Int? = nil) -> String {
        let form: String
        if let subscriptionID {
            form = """
            <form action="/users/alice/subscriptions/\(subscriptionID)" method="post">
              <input type="hidden" name="_method" value="delete">
              <input type="submit" value="Unsubscribe">
            </form>
            """
        } else {
            form = """
            <form action="/users/alice/subscriptions" method="post">
              <input type="hidden" name="subscription[subscribable_id]" value="42">
              <input type="hidden" name="subscription[subscribable_type]" value="Work">
              <input type="submit" value="Subscribe">
            </form>
            """
        }
        return """
        <html><head><meta name="csrf-token" content="work-csrf"></head><body class="logged-in">\(form)</body></html>
        """
    }

    @MainActor
    @Test func workSubscribePostsCreateAndDeleteWithWorkType() async throws {
        let auth = await makeSignedInAuth()

        // 1. Create POST for Work + flash notice confirmation.
        WorkSubscribeStub.reset(
            html: workSubscribeHTML(),
            postBody: #"<div class="flash notice">You are now following A Quiet Harbour.</div>"#
        )
        let subMessage = try await auth.toggleSubscribe(workID: 42, to: true, using: stubWorkClient())
        #expect(subMessage == "Subscribed.")
        let createHits = WorkSubscribeStub.recordedHits()
        #expect(createHits.count == 2)
        #expect(createHits[0].method == "GET")
        #expect(createHits[0].url.absoluteString == "https://archiveofourown.org/works/42?view_adult=true")
        let createPost = createHits[1]
        #expect(createPost.method == "POST")
        #expect(createPost.url.absoluteString == "https://archiveofourown.org/users/alice/subscriptions")
        #expect(createPost.referer == "https://archiveofourown.org/works/42?view_adult=true")
        #expect(createPost.csrfHeader == "work-csrf")
        let createFields = formFields(createPost.body)
        #expect(createFields["authenticity_token"] == "work-csrf")
        #expect(createFields["subscription[subscribable_id]"] == "42")
        #expect(createFields["subscription[subscribable_type]"] == "Work")

        // 2. Flashless 200 with summary prose saying "already subscribed" is unconfirmed.
        WorkSubscribeStub.reset(
            html: workSubscribeHTML(),
            postStatus: 200,
            postBody: "<div class='summary'><p>Reader note: already subscribed.</p></div>"
        )
        await #expect(throws: AO3WriteError.unconfirmed) {
            _ = try await auth.toggleSubscribe(workID: 42, to: true, using: stubWorkClient())
        }

        // 3. Parsed error flash saying "already subscribed" returns the benign message.
        WorkSubscribeStub.reset(
            html: workSubscribeHTML(),
            postStatus: 422,
            postBody: #"<div class="flash error">You have already subscribed to this work.</div>"#
        )
        let already = try await auth.toggleSubscribe(workID: 42, to: true, using: stubWorkClient())
        #expect(already == "You're already subscribed.")

        // 4. Delete POST for Work.
        WorkSubscribeStub.reset(
            html: workSubscribeHTML(subscriptionID: 789),
            postBody: #"<div class="flash notice">You have successfully unsubscribed from A Quiet Harbour.</div>"#
        )
        let unsubMessage = try await auth.toggleSubscribe(workID: 42, to: false, using: stubWorkClient())
        #expect(unsubMessage == "Unsubscribed.")
        let deleteHits = WorkSubscribeStub.recordedHits()
        #expect(deleteHits.count == 2)
        let deletePost = deleteHits[1]
        #expect(deletePost.method == "POST")
        #expect(deletePost.url.absoluteString == "https://archiveofourown.org/users/alice/subscriptions/789")
        let deleteFields = formFields(deletePost.body)
        #expect(deleteFields["_method"] == "delete")
        #expect(deleteFields["authenticity_token"] == "work-csrf")
    }

    @MainActor
    @Test func workSubscribeUsesViewAdultToBypassAdultInterstitial() async throws {
        let auth = await makeSignedInAuth()
        let subscribedFixture = try workFixture("ao3_work_bookmarked_subscribed")
            .replacingOccurrences(of: "<body>", with: "<body class=\"logged-in\">")
        let interstitial = """
        <html><head><meta name="csrf-token" content="interstitial-csrf"></head>
        <body class="logged-in"><p class="caution notice">This work could have adult content.</p>
        <a href="/works/42?view_adult=true">Proceed</a></body></html>
        """

        WorkSubscribeStub.reset(responder: { request in
            let hasViewAdult = request.url?.query?.contains("view_adult=true") == true
            if request.httpMethod == "GET" {
                return (200, hasViewAdult ? subscribedFixture : interstitial)
            }
            return (200, #"<div class="flash notice">Unsubscribed.</div>"#)
        })

        let states = try await auth.workActionStates(workID: 42, using: stubWorkClient())
        #expect(states.isSubscribed)
        #expect(states.existingBookmark?.editPath == "/bookmarks/2997787566")

        WorkSubscribeStub.reset(responder: { request in
            let hasViewAdult = request.url?.query?.contains("view_adult=true") == true
            if request.httpMethod == "GET" {
                return (200, hasViewAdult ? subscribedFixture : interstitial)
            }
            return (200, #"<div class="flash notice">Unsubscribed.</div>"#)
        })
        let message = try await auth.toggleSubscribe(workID: 42, to: false, using: stubWorkClient())
        #expect(message == "Unsubscribed.")
        let hits = WorkSubscribeStub.recordedHits()
        #expect(hits.map(\.method) == ["GET", "POST"])
        #expect(hits[0].url.absoluteString == "https://archiveofourown.org/works/42?view_adult=true")
        #expect(hits[1].url.absoluteString == "https://archiveofourown.org/users/AddictedFicLover/subscriptions/757074859")
    }

    @MainActor
    @Test func workSubscribeLoggedOutAndUnrecognisedPagesWriteNothing() async throws {
        let auth = await makeSignedInAuth()
        let loggedOut = """
        <html><head><meta name="csrf-token" content="guest"></head><body class="works-show">
          <div id="header"><a href="/users/login">Log In</a></div>
        </body></html>
        """
        for want: Bool? in [nil, false, true] {
            WorkSubscribeStub.reset(html: loggedOut)
            await #expect(throws: AO3Error.authenticationRequired) {
                _ = try await auth.toggleSubscribe(workID: 42, to: want, using: stubWorkClient())
            }
            #expect(WorkSubscribeStub.recordedMethods() == ["GET"])
        }

        let formless = """
        <html><head><meta name="csrf-token" content="tok"></head><body class="logged-in">
          <p class="caution notice">This work could have adult content.</p>
        </body></html>
        """
        for want in [false, true] {
            WorkSubscribeStub.reset(html: formless)
            await #expect(throws: AO3Error.parse) {
                _ = try await auth.toggleSubscribe(workID: 42, to: want, using: stubWorkClient())
            }
            #expect(WorkSubscribeStub.recordedMethods() == ["GET"])
        }
    }

    @MainActor
    @Test func workSubscribeNilIntentFormlessPageDoesNotPost() async throws {
        let auth = await makeSignedInAuth()
        WorkSubscribeStub.reset(html: """
        <html><head><meta name="csrf-token" content="tok"></head><body class="logged-in">
          <p class="caution notice">This work could have adult content.</p>
        </body></html>
        """)

        await #expect(throws: AO3Error.parse) {
            _ = try await auth.toggleSubscribe(workID: 42, to: nil, using: stubWorkClient())
        }
        #expect(WorkSubscribeStub.recordedMethods() == ["GET"])
    }

    @MainActor
    @Test func malformedDeleteFormAndUntrustedDeletePathNeverClaimOrCreate() async throws {
        let missingDeleteMethod = """
        <html><head><meta name="csrf-token" content="tok"></head><body class="logged-in">
          <form action="/users/alice/subscriptions/789" method="post">
            <input type="submit" value="Unsubscribe">
          </form>
        </body></html>
        """
        let confirmDeleteAll = """
        <form action="/users/alice/subscriptions/confirm_delete_all" method="post"></form>
        """
        let validCreateWithQuery = """
        <form action="/users/alice/subscriptions?locale=en" method="post"></form>
        """
        #expect(!AO3Client.hasSubscribeForm(in: missingDeleteMethod))
        #expect(!AO3Client.hasSubscribeForm(in: confirmDeleteAll))
        #expect(AO3Client.hasSubscribeForm(in: validCreateWithQuery))

        let auth = await makeSignedInAuth()
        for want in [false, true] {
            WorkSubscribeStub.reset(html: missingDeleteMethod)
            await #expect(throws: AO3Error.parse) {
                _ = try await auth.toggleSubscribe(workID: 42, to: want, using: stubWorkClient())
            }
            #expect(WorkSubscribeStub.recordedMethods() == ["GET"])
        }

        let untrustedDeletePaths = [
            "https://evil.example/users/alice/subscriptions/789",
            "http://[/subscriptions/789"
        ]
        for badAction in untrustedDeletePaths {
            let html = """
            <html><head><meta name="csrf-token" content="tok"></head><body class="logged-in">
              <form action="\(badAction)" method="post">
                <input type="hidden" name="_method" value="delete">
              </form>
            </body></html>
            """
            for want: Bool? in [nil, false, true] {
                WorkSubscribeStub.reset(html: html)
                await #expect(throws: AO3Error.parse) {
                    _ = try await auth.toggleSubscribe(workID: 42, to: want, using: stubWorkClient())
                }
                #expect(WorkSubscribeStub.recordedMethods() == ["GET"])
            }
        }
    }

    // MARK: AO3WorkActionsModel subscribe & state fencing

    @MainActor
    @Test func workActionsModelUpdatesStateFromIntentEvenWhenWorkIDWasNil() async throws {
        struct Call: Equatable { let workID: Int; let want: Bool }
        let auth = await makeSignedInAuth()
        var recorded: [Call] = []
        let model = AO3WorkActionsModel(subscribeHandler: { workID, want, _ in
            recorded.append(Call(workID: workID, want: want))
            return want ? "You're already subscribed." : "Unsubscribed."
        })

        var onSubscribedCount = 0
        model.subscribe(workID: 42, to: true, auth: auth) { onSubscribedCount += 1 }
        await model.waitForCurrentTask()
        #expect(recorded == [Call(workID: 42, want: true)])
        #expect(model.workPageStates?.isSubscribed == true)
        #expect(model.banner == "You're already subscribed.")
        #expect(model.writeSuccesses == 1)
        #expect(onSubscribedCount == 1)

        model.subscribe(workID: 42, to: false, auth: auth) { onSubscribedCount += 1 }
        await model.waitForCurrentTask()
        #expect(recorded == [Call(workID: 42, want: true), Call(workID: 42, want: false)])
        #expect(model.workPageStates?.isSubscribed == false)
        #expect(model.banner == "Unsubscribed.")
        #expect(model.writeSuccesses == 2)
        #expect(onSubscribedCount == 1)

        let failing = AO3WorkActionsModel(subscribeHandler: { _, _, _ in
            throw AO3WriteError.unconfirmed
        })
        var failingCallbackCount = 0
        failing.subscribe(workID: 42, to: true, auth: auth) { failingCallbackCount += 1 }
        await failing.waitForCurrentTask()
        #expect(failing.workPageStates == nil)
        #expect(failing.writeFailures == 1)
        #expect(failingCallbackCount == 0)
    }

    @MainActor
    @Test func workActionsModelKeepsExistingBookmarkAndRefreshesWhenStatesWereNil() async throws {
        let auth = await makeSignedInAuth()
        let savedBookmark = AO3ExistingBookmark(
            editPath: "/bookmarks/99",
            collectionNames: "",
            input: AO3AuthService.BookmarkInput(notes: "Keep me", tags: "angst", isPrivate: true, isRec: false)
        )

        // Case A: workPageStates already synced -> subscribe keeps existingBookmark with no extra fetch.
        var fetchCountA = 0
        let modelA = AO3WorkActionsModel(
            subscribeHandler: { _, want, _ in want ? "Subscribed." : "Unsubscribed." },
            workActionStatesHandler: { _, _ in
                fetchCountA += 1
                return AO3WorkActionStates(isSubscribed: false, existingBookmark: savedBookmark)
            }
        )
        modelA.refreshWorkPageStates(workID: 42, auth: auth)
        await modelA.waitForStateFetch()
        #expect(fetchCountA == 1)
        modelA.subscribe(workID: 42, to: true, auth: auth)
        await modelA.waitForCurrentTask()
        #expect(fetchCountA == 1)
        #expect(modelA.workPageStates?.isSubscribed == true)
        #expect(modelA.workPageStates?.existingBookmark == savedBookmark)

        // Case B: subscribe finishes while initial fetch is in flight -> old pre-write fetch is
        // superseded and post-write refresh restores existingBookmark.
        let firstFetchEntered = Signal()
        let firstFetchRelease = Signal()
        var fetchCountB = 0
        let modelB = AO3WorkActionsModel(
            subscribeHandler: { _, want, _ in want ? "Subscribed." : "Unsubscribed." },
            workActionStatesHandler: { _, _ in
                fetchCountB += 1
                if fetchCountB == 1 {
                    await firstFetchEntered.fire()
                    await firstFetchRelease.wait()
                    return AO3WorkActionStates(isSubscribed: false, existingBookmark: nil)
                }
                return AO3WorkActionStates(isSubscribed: true, existingBookmark: savedBookmark)
            }
        )
        modelB.refreshWorkPageStates(workID: 42, auth: auth)
        await firstFetchEntered.wait()
        modelB.subscribe(workID: 42, to: true, auth: auth)
        await modelB.waitForCurrentTask()
        await modelB.waitForStateFetch()
        await firstFetchRelease.fire()
        await Task.yield()

        #expect(fetchCountB == 2)
        #expect(modelB.workPageStates?.isSubscribed == true)
        #expect(modelB.workPageStates?.existingBookmark == savedBookmark)
    }

    @MainActor
    @Test func workActionsModelIsolatesStatesByGenerationAndHandlesCancelAndExpiry() async throws {
        let auth = await makeSignedInAuth(username: "alice")
        var fetchedGenerations: [Int] = []
        let model = AO3WorkActionsModel(
            subscribeHandler: { _, want, _ in want ? "Subscribed." : "Unsubscribed." },
            workActionStatesHandler: { _, service in
                let gen = service.sessionGeneration
                fetchedGenerations.append(gen)
                return AO3WorkActionStates(isSubscribed: gen == 1, existingBookmark: nil)
            }
        )

        model.refreshWorkPageStates(workID: 42, auth: auth)
        await model.waitForStateFetch()
        #expect(model.workPageStates?.isSubscribed == true)

        // Same work, same generation -> cached, no refetch.
        model.refreshWorkPageStates(workID: 42, auth: auth)
        await model.waitForStateFetch()
        #expect(fetchedGenerations.count == 1)

        // Logout + re-login as same user bumps sessionGeneration -> refetches for new session.
        await auth.logout()
        await auth.login(username: "alice", password: "pw")
        model.refreshWorkPageStates(workID: 42, auth: auth)
        await model.waitForStateFetch()
        #expect(fetchedGenerations.count == 2)
        #expect(model.workPageStates?.isSubscribed == false)

        // CancellationError is ignored quietly without banner or failure haptic.
        let cancelled = AO3WorkActionsModel(subscribeHandler: { _, _, _ in throw CancellationError() })
        cancelled.subscribe(workID: 42, to: true, auth: auth)
        await cancelled.waitForCurrentTask()
        #expect(cancelled.banner == nil)
        #expect(cancelled.writeFailures == 0)

        // Mid-flight generation change drops completion quietly.
        let switchEntered = Signal()
        let switchRelease = Signal()
        var callbackAfterSwitch = 0
        let switched = AO3WorkActionsModel(subscribeHandler: { _, _, _ in
            await switchEntered.fire()
            await switchRelease.wait()
            return "Subscribed."
        })
        switched.subscribe(workID: 42, to: true, auth: auth) { callbackAfterSwitch += 1 }
        await switchEntered.wait()
        await auth.logout()
        await auth.login(username: "bob", password: "pw")
        await switchRelease.fire()
        await switched.waitForCurrentTask()
        #expect(callbackAfterSwitch == 0)
        #expect(switched.banner == nil)
        #expect(switched.workPageStates == nil)

        // AO3Error.authenticationRequired expires the session and clears cached states.
        let expiryModel = AO3WorkActionsModel(
            subscribeHandler: { _, _, _ in throw AO3Error.authenticationRequired },
            workActionStatesHandler: { _, _ in
                AO3WorkActionStates(isSubscribed: true, existingBookmark: nil)
            }
        )
        expiryModel.refreshWorkPageStates(workID: 42, auth: auth)
        await expiryModel.waitForStateFetch()
        #expect(expiryModel.workPageStates != nil)

        expiryModel.subscribe(workID: 42, to: false, auth: auth)
        await expiryModel.waitForCurrentTask()
        #expect(!auth.isLoggedIn)
        #expect(auth.sessionHealth == .expired)
        #expect(expiryModel.workPageStates == nil)
        #expect(expiryModel.banner == AO3Error.authenticationRequired.errorDescription)
        #expect(expiryModel.writeFailures == 1)
    }

    @MainActor
    @Test func cachedBookmarkIsNotOfferedAfterAccountSwitch() async throws {
        let auth = await makeSignedInAuth(username: "alice")
        let savedBookmark = AO3ExistingBookmark(
            editPath: "/bookmarks/99",
            collectionNames: "",
            input: AO3AuthService.BookmarkInput(notes: "Alice's note", tags: "private-tag")
        )
        var writeCount = 0
        let model = AO3WorkActionsModel(
            workActionStatesHandler: { _, _ in
                AO3WorkActionStates(isSubscribed: false, existingBookmark: savedBookmark)
            },
            bookmarkHandler: { _, _, _ in
                writeCount += 1
                return "Bookmarked."
            }
        )
        model.refreshWorkPageStates(workID: 42, auth: auth)
        await model.waitForStateFetch()
        model.startBookmark(workID: 42, auth: auth)
        #expect(model.bookmarkInput == savedBookmark.input)
        #expect(model.bookmarkIsUpdate)
        model.submitBookmark(workID: 42, auth: auth)
        await model.waitForCurrentTask()
        #expect(model.isBookmarked(workID: 42, auth: auth))

        await auth.logout()
        await auth.login(username: "bob", password: "pw")
        #expect(!model.isBookmarked(workID: 42, auth: auth))
        model.submitBookmark(workID: 42, auth: auth)
        #expect(writeCount == 1)
        model.startBookmark(workID: 42, auth: auth)
        #expect(model.bookmarkInput == AO3AuthService.BookmarkInput())
        #expect(!model.bookmarkIsUpdate)
        model.bookmarkSessionDidChange()
        #expect(model.workPageStates == nil)
    }

    @MainActor
    @Test func pendingBookmarkCompletionDoesNotAffectNextAccount() async throws {
        let auth = await makeSignedInAuth(username: "alice")
        let entered = Signal()
        let release = Signal()
        var refreshCount = 0
        let model = AO3WorkActionsModel(
            workActionStatesHandler: { _, _ in
                refreshCount += 1
                return AO3WorkActionStates(isSubscribed: false, existingBookmark: nil)
            },
            bookmarkHandler: { _, _, _ in
                await entered.fire()
                await release.wait()
                return "Bookmarked."
            }
        )
        model.startBookmark(workID: 42, auth: auth)
        model.bookmarkInput.notes = "Alice's note"
        model.submitBookmark(workID: 42, auth: auth)
        await entered.wait()

        await auth.logout()
        await auth.login(username: "bob", password: "pw")
        model.bookmarkSessionDidChange()
        model.startBookmark(workID: 42, auth: auth)
        #expect(model.bookmarkInput.notes.isEmpty)
        await release.fire()
        await model.waitForCurrentTask()

        #expect(model.showingBookmark)
        #expect(model.bookmarkInput.notes.isEmpty)
        #expect(model.bookmarkSuccess == nil)
        #expect(model.bookmarkError == nil)
        #expect(!model.isBookmarked(workID: 42, auth: auth))
        #expect(model.writeSuccesses == 0)
        #expect(model.writeFailures == 0)
        #expect(refreshCount == 0)
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

    /// The state that makes `unsubscribe` and `toggleSubscribe` diverge, and the
    /// reason the Following list must not use the toggle.
    ///
    /// An unqualified `toggleSubscribe` would subscribe when a Following row went
    /// stale. The list's dedicated `unsubscribe` guards on this same parse.
    @Test("A stale Following row parses as not-subscribed, which is why Unfollow cannot use the toggle")
    func notSubscribedIsTheStaleRowState() {
        let staleRow = """
        <form action="/users/me/subscriptions" method="post">
          <input type="hidden" name="subscription[subscribable_type]" value="Work">
          <input type="submit" value="Subscribe">
        </form>
        """
        let state = AO3Client.parseSubscription(from: staleRow)
        #expect(!state.isSubscribed, "a plain toggle would branch to subscribe here")
        #expect(state.unsubscribePath == nil, "and there is no delete path to POST")
    }

    /// The failure these two states are easy to confuse, and the reason
    /// `unsubscribe` checks the session before reporting "not following".
    ///
    /// A work page is PUBLIC, so an expired session does not redirect to
    /// /users/login and `authenticatedPageHTML` does not throw — it returns a
    /// valid logged-out page. That page has no subscription controls at all, so
    /// `parseSubscription` reports not-subscribed exactly as it does for a work
    /// the user genuinely does not follow. Without the session check the list
    /// would quietly drop a row the user still follows.
    @Test("A logged-out work page is not evidence that the user stopped following")
    func loggedOutPageIsNotProofOfNoSubscription() {
        let loggedOut = """
        <html><body class="works-show">
          <div id="header"><a href="/users/login">Log In</a></div>
          <div id="main"><h2 class="title">A Quiet Harbour</h2></div>
        </body></html>
        """
        let signedIn = """
        <html><body class="works-show logged-in">
          <div id="header"><a href="/users/logout">Log Out</a></div>
          <form action="/users/me/subscriptions" method="post">
            <input type="submit" value="Subscribe">
          </form>
        </body></html>
        """

        // Indistinguishable on the subscription parse alone.
        #expect(!AO3Client.parseSubscription(from: loggedOut).isSubscribed)
        #expect(!AO3Client.parseSubscription(from: signedIn).isSubscribed)

        // Separable on the session, which is what `unsubscribe` branches on.
        #expect(!LiveAO3SessionValidator.isLoggedIn(html: loggedOut))
        #expect(LiveAO3SessionValidator.isLoggedIn(html: signedIn))
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
