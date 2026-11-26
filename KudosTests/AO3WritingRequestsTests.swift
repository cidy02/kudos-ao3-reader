import Foundation
import Testing
@testable import Kudos

private final class WritingRequestsFixtureAnchor {}

/// Local URLProtocol stub for T-575 request-queue tests. Nothing reaches AO3.
private final class WritingRequestsStub: URLProtocol, @unchecked Sendable {
    nonisolated struct Hit: Sendable {
        var method: String
        var url: URL
        var body: String
    }

    nonisolated struct Reply: Sendable {
        var status: Int = 200
        var body: String
        var headers: [String: String]?
        var finalURL: URL?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var hits: [Hit] = []
    nonisolated(unsafe) private static var responder: (@Sendable (URLRequest) -> Reply)?

    static func reset(_ handler: @escaping @Sendable (URLRequest) -> Reply) {
        lock.lock()
        hits = []
        responder = handler
        lock.unlock()
    }

    static func recorded() -> [Hit] {
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
        let hit = Hit(method: request.httpMethod ?? "GET", url: url, body: Self.bodyText(of: request))
        Self.lock.lock()
        Self.hits.append(hit)
        let handler = Self.responder
        Self.lock.unlock()

        guard let reply = handler?(request),
              let response = HTTPURLResponse(
                  url: reply.finalURL ?? url,
                  statusCode: reply.status,
                  httpVersion: "HTTP/1.1",
                  headerFields: reply.headers
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func bodyText(of request: URLRequest) -> String {
        if let data = request.httpBody { return String(decoding: data, as: UTF8.self) }
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
        return String(decoding: data, as: UTF8.self)
    }
}

private typealias StubReply = WritingRequestsStub.Reply

private nonisolated func writingRequestFlash(_ kind: String, _ text: String) -> String {
    """
    <html><body class="logged-in"><div id="main">
    <div class="flash \(kind)">\(text)</div>
    </div></body></html>
    """
}

/// T-575 Actions 1–3 (co-creator invitations, gifts to you, related works)
/// against otwarchive master `452391b6` fixtures and a local URLProtocol stub.
@Suite(.serialized)
@MainActor
struct AO3WritingRequestsTests {

    private func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle(for: WritingRequestsFixtureAnchor.self).url(forResource: name, withExtension: "html")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

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

    private func stubClient() -> AO3Client {
        let config = AO3Client.makeAnonymousSessionConfiguration()
        config.protocolClasses = [WritingRequestsStub.self]
        return AO3Client(session: URLSession(configuration: config), paceSleep: { _ in })
    }

    private func formFields(_ body: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for pair in body.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            let key = parts[0].removingPercentEncoding ?? parts[0]
            let value = parts.count > 1 ? (parts[1].removingPercentEncoding ?? parts[1]) : ""
            result[key, default: []].append(value)
        }
        return result
    }

    // MARK: - 1. Co-creator requests

    @Test func parsesCoCreatorRequestsFixtureAndEmptyState() throws {
        let page = try AO3Client.parseCoCreatorRequests(from: try fixture("ao3_creatorships"), page: 1)
        #expect(page.csrfToken == "creatorships-csrf==")
        #expect(page.actionURL?.path == "/users/alice/creatorships")
        #expect(page.currentPage == 1)
        #expect(page.totalPages == 2)
        #expect(page.requests.count == 2)

        let work = page.requests[0]
        #expect(work.id == 501)
        #expect(work.title == "The Weight of Water")
        #expect(work.creationType == "Work")
        #expect(work.workID == 424242)
        #expect(work.chapterID == nil)
        #expect(work.invitedPseud == "alice_main")
        #expect(work.dateText == "15 Oct 2026")

        let chapter = page.requests[1]
        #expect(chapter.id == 502)
        #expect(chapter.title == "Chapter 3 of Salt and Static")
        #expect(chapter.creationType == "Chapter")
        #expect(chapter.chapterID == 9001)
        #expect(chapter.invitedPseud == "alice_alt")
        #expect(chapter.dateText == "18 Oct 2026")

        let empty = try AO3Client.parseCoCreatorRequests(from: try fixture("ao3_creatorships_empty"), page: 1)
        #expect(empty.requests.isEmpty)
        #expect(empty.csrfToken == "creatorships-empty-csrf==")
        #expect(empty.totalPages == 1)
    }

    @Test func answerCoCreatorRequestsPostsAcceptRejectAndHandlesCautionFlash() async throws {
        let auth = await makeSignedInAuth()
        let page1HTML = try fixture("ao3_creatorships")
        let page2HTML = page1HTML.replacingOccurrences(
            of: #"action="/users/alice/creatorships""#,
            with: #"action="/users/alice/creatorships?page=2""#
        )

        // Empty selection fails locally with zero network traffic.
        WritingRequestsStub.reset { _ in StubReply(body: page1HTML) }
        await #expect(throws: AO3WorkWriteError.rejected("Please select at least one co-creator request first.")) {
            _ = try await auth.answerCoCreatorRequests(ids: [], accept: true, page: 1, using: stubClient())
        }
        #expect(WritingRequestsStub.recorded().isEmpty)

        // Accept on page 2.
        WritingRequestsStub.reset { request in
            if request.httpMethod == "GET" { return StubReply(body: page2HTML) }
            return StubReply(body: """
            <html><body class="logged-in"><div id="main">
            <div class="flash notice"><ul>
              <li>You are now listed as a co-creator on <a href="/works/424242">The Weight of Water</a>.</li>
            </ul></div></div></body></html>
            """)
        }
        let accepted = try await auth.answerCoCreatorRequests(
            ids: [501, 502], accept: true, page: 2, using: stubClient()
        )
        #expect(accepted.contains("You are now listed as a co-creator on The Weight of Water."))
        let acceptHits = WritingRequestsStub.recorded()
        #expect(acceptHits.map(\.method) == ["GET", "POST"])
        #expect(acceptHits[0].url.absoluteString == "https://archiveofourown.org/users/alice/creatorships?page=2")
        #expect(acceptHits[1].url.absoluteString == "https://archiveofourown.org/users/alice/creatorships?page=2")
        #expect(formFields(acceptHits[1].body) == [
            "_method": ["put"],
            "authenticity_token": ["creatorships-csrf=="],
            "selected[]": ["501", "502"],
            "accept": ["Accept"]
        ])

        // Reject (decline) on page 1.
        WritingRequestsStub.reset { request in
            if request.httpMethod == "GET" { return StubReply(body: page1HTML) }
            return StubReply(body: writingRequestFlash("notice", "Requests rejected."))
        }
        let rejected = try await auth.answerCoCreatorRequests(
            ids: [502], accept: false, page: 1, using: stubClient()
        )
        #expect(rejected == "Requests rejected.")
        let rejectPost = try #require(WritingRequestsStub.recorded().last)
        #expect(rejectPost.url.absoluteString == "https://archiveofourown.org/users/alice/creatorships")
        #expect(formFields(rejectPost.body) == [
            "_method": ["put"],
            "authenticity_token": ["creatorships-csrf=="],
            "selected[]": ["502"],
            "reject": ["Reject"]
        ])

        // AO3 caution flash fails.
        WritingRequestsStub.reset { request in
            if request.httpMethod == "GET" { return StubReply(body: page1HTML) }
            return StubReply(
                body: writingRequestFlash("caution", "Please select at least one co-creator request first.")
            )
        }
        await #expect(throws: AO3WorkWriteError.rejected("Please select at least one co-creator request first.")) {
            _ = try await auth.answerCoCreatorRequests(ids: [501], accept: true, page: 1, using: stubClient())
        }
    }

    /// Ground truth (`otwarchive 452391b6` `CreatorshipsController#show`/`#update`):
    /// requesting a `page` past the last page renders HTTP 200 with `<p>No co-creator
    /// requests found.</p>` and no `<form>` (carrying only `<meta name="csrf-token">`
    /// and optional pagination for pages `1..total_pages`). `update` loads all of the
    /// user's unapproved creatorships regardless of page, so `answerCoCreatorRequests`
    /// falls back to the meta CSRF token and `pageURL`, succeeds if AO3 flashes a
    /// notice, and rejects if AO3 flashes caution (already answered/gone).
    @Test func answerCoCreatorRequestsHandlesPagePastLastPage() async throws {
        let auth = await makeSignedInAuth()
        let pastLastPageHTML = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta name="csrf-token" content="past-last-page-csrf==">
          <title>Co-Creator Requests | Archive of Our Own</title>
        </head>
        <body class="logged-in">
        <div id="main" class="creatorships-show region">
          <h2 class="heading">Co-Creator Requests</h2>
          <ol class="pagination actions" role="navigation">
            <li class="previous"><a rel="prev" href="/users/alice/creatorships?page=4">Previous</a></li>
            <li><a href="/users/alice/creatorships?page=1">1</a></li>
            <li><a href="/users/alice/creatorships?page=2">2</a></li>
          </ol>
          <p>No co-creator requests found.</p>
        </div>
        </body>
        </html>
        """

        let parsed = try AO3Client.parseCoCreatorRequests(from: pastLastPageHTML, page: 5)
        #expect(parsed.requests.isEmpty)
        #expect(parsed.actionURL == nil)
        #expect(parsed.csrfToken == "past-last-page-csrf==")
        #expect(parsed.currentPage == 5)

        // When AO3 still finds the selected id (e.g. shifted to an earlier page),
        // the PUT falls back to the meta CSRF token and `?page=5` URL.
        WritingRequestsStub.reset { request in
            if request.httpMethod == "GET" { return StubReply(body: pastLastPageHTML) }
            return StubReply(body: writingRequestFlash("notice", "Requests rejected."))
        }
        let notice = try await auth.answerCoCreatorRequests(
            ids: [501], accept: false, page: 5, using: stubClient()
        )
        #expect(notice == "Requests rejected.")
        let hits = WritingRequestsStub.recorded()
        #expect(hits.map(\.method) == ["GET", "POST"])
        #expect(hits[0].url.absoluteString == "https://archiveofourown.org/users/alice/creatorships?page=5")
        #expect(hits[1].url.absoluteString == "https://archiveofourown.org/users/alice/creatorships?page=5")
        #expect(formFields(hits[1].body) == [
            "_method": ["put"],
            "authenticity_token": ["past-last-page-csrf=="],
            "selected[]": ["501"],
            "reject": ["Reject"]
        ])

        // When the id is no longer pending on AO3, the caution flash is surfaced.
        WritingRequestsStub.reset { request in
            if request.httpMethod == "GET" { return StubReply(body: pastLastPageHTML) }
            return StubReply(
                body: writingRequestFlash("caution", "Please select at least one co-creator request first.")
            )
        }
        await #expect(throws: AO3WorkWriteError.rejected("Please select at least one co-creator request first.")) {
            _ = try await auth.answerCoCreatorRequests(ids: [501], accept: true, page: 5, using: stubClient())
        }
    }

    // MARK: - 2. Gifts to you

    @Test func parsesAcceptedAndRefusedGiftsFixtures() throws {
        let accepted = try AO3Client.parseGiftsPage(
            from: try fixture("ao3_gifts_accepted"), refused: false, page: 1
        )
        #expect(accepted.csrfToken == "gifts-accepted-csrf==")
        #expect(accepted.totalPages == 2)
        #expect(accepted.gifts.count == 2)

        let named = accepted.gifts[0]
        #expect(named.giftID == 8801)
        #expect(named.workID == 1001)
        #expect(named.title == "Two Voices at Dawn")
        #expect(named.creators == ["kestrel"])
        #expect(!named.isAnonymous)
        #expect(!named.isRefused)
        #expect(named.work.words == 3400)

        let anon = accepted.gifts[1]
        #expect(anon.giftID == 8802)
        #expect(anon.workID == 1002)
        #expect(anon.title == "Secret Lantern")
        #expect(anon.creators == ["Anonymous"])
        #expect(anon.isAnonymous)
        #expect(!anon.isRefused)

        let refused = try AO3Client.parseGiftsPage(
            from: try fixture("ao3_gifts_refused"), refused: true, page: 1
        )
        #expect(refused.csrfToken == "gifts-refused-csrf==")
        #expect(refused.gifts.count == 1)
        #expect(refused.gifts[0].giftID == 8803)
        #expect(refused.gifts[0].workID == 1003)
        #expect(refused.gifts[0].isRefused)
    }

    @Test func setGiftRefusedPostsToggleAndAbortsWhenStateChanged() async throws {
        let auth = await makeSignedInAuth()
        let acceptedHTML = try fixture("ao3_gifts_accepted")
        let refusedHTML = try fixture("ao3_gifts_refused")

        // Refuse an accepted gift.
        WritingRequestsStub.reset { request in
            if request.httpMethod == "GET" { return StubReply(body: acceptedHTML) }
            return StubReply(
                body: writingRequestFlash("notice", "This work will no longer be listed among your gifts.")
            )
        }
        let refuseNotice = try await auth.setGiftRefused(
            giftID: 8801, workID: 1001, refused: true, using: stubClient()
        )
        #expect(refuseNotice == "This work will no longer be listed among your gifts.")
        let refuseHits = WritingRequestsStub.recorded()
        #expect(refuseHits.map(\.method) == ["GET", "POST"])
        #expect(refuseHits[0].url.absoluteString == "https://archiveofourown.org/users/alice/gifts")
        #expect(refuseHits[1].url.absoluteString == "https://archiveofourown.org/gifts/8801/toggle_rejected")
        #expect(formFields(refuseHits[1].body) == ["authenticity_token": ["gifts-accepted-csrf=="]])

        // Accept a refused gift.
        WritingRequestsStub.reset { request in
            if request.httpMethod == "GET" { return StubReply(body: refusedHTML) }
            return StubReply(body: writingRequestFlash("notice", "This work will now be listed among your gifts."))
        }
        let acceptNotice = try await auth.setGiftRefused(
            giftID: 8803, workID: 1003, refused: false, using: stubClient()
        )
        #expect(acceptNotice == "This work will now be listed among your gifts.")
        let acceptHits = WritingRequestsStub.recorded()
        #expect(acceptHits.map(\.method) == ["GET", "POST"])
        #expect(acceptHits[0].url.absoluteString == "https://archiveofourown.org/users/alice/gifts?refused=true")
        #expect(acceptHits[1].url.absoluteString == "https://archiveofourown.org/gifts/8803/toggle_rejected")
        #expect(formFields(acceptHits[1].body) == ["authenticity_token": ["gifts-refused-csrf=="]])

        // Toggle guards: missing row or flipped link throws stateChanged and sends NO POST.
        WritingRequestsStub.reset { _ in StubReply(body: acceptedHTML) }
        await #expect(throws: AO3WorkWriteError.stateChanged) {
            _ = try await auth.setGiftRefused(giftID: 8803, workID: 1003, refused: true, using: stubClient())
        }
        #expect(WritingRequestsStub.recorded().map(\.method) == ["GET"])

        let flippedHTML = acceptedHTML.replacingOccurrences(of: ">Refuse Gift<", with: ">Accept Gift<")
        WritingRequestsStub.reset { _ in StubReply(body: flippedHTML) }
        await #expect(throws: AO3WorkWriteError.stateChanged) {
            _ = try await auth.setGiftRefused(giftID: 8801, workID: 1001, refused: true, using: stubClient())
        }
        #expect(WritingRequestsStub.recorded().map(\.method) == ["GET"])
    }

    // MARK: - 3. Related works

    @Test func parsesRelatedWorksIndexAndShowFixtures() throws {
        let index = try AO3Client.parseRelatedWorks(from: try fixture("ao3_related_works"))
        #expect(index.csrfToken == "rw-index-csrf==")
        #expect(index.translationsOfMe.count == 1)
        #expect(index.translationsByMe.count == 1)
        #expect(index.inspiredByMe.count == 1)
        #expect(index.thatInspiredMe.count == 1)

        let transOfMe = index.translationsOfMe[0]
        #expect(transOfMe.id == 301)
        #expect(transOfMe.childWork.workID == 201)
        #expect(transOfMe.childWork.title == "Le Poids de l'Eau")
        #expect(transOfMe.childWork.creators == ["translator"])
        #expect(transOfMe.parentWork.workID == 101)
        #expect(transOfMe.parentWork.title == "The Weight of Water")
        #expect(transOfMe.fromLanguage == "English")
        #expect(transOfMe.toLanguage == "Français")
        #expect(transOfMe.isApproved == false)
        #expect(transOfMe.action == .toggleReciprocal(isApproved: false))

        let transByMe = index.translationsByMe[0]
        #expect(transByMe.id == 302)
        #expect(transByMe.parentWork.workID == 102)
        #expect(transByMe.parentWork.creators == ["autor"])
        #expect(transByMe.childWork.workID == 202)
        #expect(transByMe.fromLanguage == "Deutsch")
        #expect(transByMe.toLanguage == "English")
        #expect(transByMe.isApproved == nil)
        #expect(transByMe.action == .removeLink)

        let inspiredOfMe = index.inspiredByMe[0]
        #expect(inspiredOfMe.id == 303)
        #expect(inspiredOfMe.childWork.workID == 203)
        #expect(inspiredOfMe.childWork.creators == ["fanwriter"])
        #expect(inspiredOfMe.parentWork.workID == 101)
        #expect(inspiredOfMe.isApproved == true)
        #expect(inspiredOfMe.action == .toggleReciprocal(isApproved: true))

        let inspiredByOthers = index.thatInspiredMe[0]
        #expect(inspiredByOthers.id == 304)
        #expect(inspiredByOthers.parentWork.workID == 104)
        #expect(inspiredByOthers.parentWork.creators == ["mentor"])
        #expect(inspiredByOthers.childWork.workID == 204)
        #expect(inspiredByOthers.action == .removeLink)

        let approveShow = try AO3Client.parseRelatedWorkShow(from: try fixture("ao3_related_work_approve"))
        #expect(approveShow.mode == .approve)
        #expect(approveShow.id == 301)
        #expect(approveShow.csrfToken == "rw-approve-csrf==")
        #expect(approveShow.commitValue == "Yes, link me!")

        let removeShow = try AO3Client.parseRelatedWorkShow(from: try fixture("ao3_related_work_remove"))
        #expect(removeShow.mode == .remove)
        #expect(removeShow.id == 303)
        #expect(removeShow.csrfToken == "rw-remove-csrf==")
        #expect(removeShow.commitValue == "Remove link")
    }

    @Test func relatedWorkWritesHonorToggleGuardAndDeleteMethod() async throws {
        let auth = await makeSignedInAuth()
        let approveHTML = try fixture("ao3_related_work_approve")
        let removeHTML = try fixture("ao3_related_work_remove")
        let indexHTML = try fixture("ao3_related_works")

        // Approve link (PATCH).
        WritingRequestsStub.reset { request in
            if request.httpMethod == "GET" { return StubReply(body: approveHTML) }
            return StubReply(body: writingRequestFlash("notice", "Link was successfully approved"))
        }
        let approvedMsg = try await auth.setRelatedWorkLinkApproved(id: 301, approved: true, using: stubClient())
        #expect(approvedMsg == "Link was successfully approved")
        let approveHits = WritingRequestsStub.recorded()
        #expect(approveHits.map(\.method) == ["GET", "POST"])
        #expect(approveHits[0].url.absoluteString == "https://archiveofourown.org/related_works/301")
        #expect(approveHits[1].url.absoluteString == "https://archiveofourown.org/related_works/301")
        #expect(formFields(approveHits[1].body) == [
            "_method": ["patch"],
            "authenticity_token": ["rw-approve-csrf=="],
            "commit": ["Yes, link me!"]
        ])

        // Remove approved link (PATCH).
        WritingRequestsStub.reset { request in
            if request.httpMethod == "GET" { return StubReply(body: removeHTML) }
            return StubReply(body: writingRequestFlash("notice", "Link was successfully removed"))
        }
        let removedMsg = try await auth.setRelatedWorkLinkApproved(id: 303, approved: false, using: stubClient())
        #expect(removedMsg == "Link was successfully removed")
        let removePost = try #require(WritingRequestsStub.recorded().last)
        #expect(formFields(removePost.body) == [
            "_method": ["patch"],
            "authenticity_token": ["rw-remove-csrf=="],
            "commit": ["Remove link"]
        ])

        // Toggle guards: mismatched show heading throws stateChanged and sends NO POST.
        WritingRequestsStub.reset { _ in StubReply(body: removeHTML) }
        await #expect(throws: AO3WorkWriteError.stateChanged) {
            _ = try await auth.setRelatedWorkLinkApproved(id: 303, approved: true, using: stubClient())
        }
        #expect(WritingRequestsStub.recorded().map(\.method) == ["GET"])

        WritingRequestsStub.reset { _ in StubReply(body: approveHTML) }
        await #expect(throws: AO3WorkWriteError.stateChanged) {
            _ = try await auth.setRelatedWorkLinkApproved(id: 301, approved: false, using: stubClient())
        }
        #expect(WritingRequestsStub.recorded().map(\.method) == ["GET"])

        // Delete own work's link (DELETE): AO3 redirects back without flash[:notice].
        let afterDelete = """
        <html><body class="logged-in"><div id="main">
        <h2 class="heading">alice's Related Works</h2></div></body></html>
        """
        WritingRequestsStub.reset { request in
            if request.httpMethod == "GET" { return StubReply(body: indexHTML) }
            return StubReply(body: afterDelete)
        }
        try await auth.removeMyRelatedWorkLink(id: 302, using: stubClient())
        let deleteHits = WritingRequestsStub.recorded()
        #expect(deleteHits.map(\.method) == ["GET", "POST"])
        #expect(deleteHits[0].url.absoluteString == "https://archiveofourown.org/users/alice/related_works")
        #expect(deleteHits[1].url.absoluteString == "https://archiveofourown.org/related_works/302")
        #expect(formFields(deleteHits[1].body) == [
            "_method": ["delete"],
            "authenticity_token": ["rw-delete-302-csrf=="]
        ])

        // Row still present or blank 200 throws .unconfirmed rather than faking success.
        WritingRequestsStub.reset { _ in StubReply(body: indexHTML) }
        await #expect(throws: AO3WorkWriteError.unconfirmed) {
            try await auth.removeMyRelatedWorkLink(id: 302, using: stubClient())
        }
        WritingRequestsStub.reset { request in
            StubReply(body: request.httpMethod == "GET" ? indexHTML : "<html><body></body></html>")
        }
        await #expect(throws: AO3WorkWriteError.unconfirmed) {
            try await auth.removeMyRelatedWorkLink(id: 302, using: stubClient())
        }
    }
}
