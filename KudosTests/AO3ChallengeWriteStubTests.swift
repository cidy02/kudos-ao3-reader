import Foundation
import Testing
@testable import Kudos

/// Local stand-in for AO3 behind `URLSession.protocolClasses`: nothing here
/// reaches archiveofourown.org. A GET is a write's CSRF fetch and gets a page
/// with a token; a POST gets `postBody` (a flash notice unless a test says so).
private final class ChallengeWriteStub: URLProtocol, @unchecked Sendable {
    struct Hit: Sendable {
        var method: String
        var url: URL
        var body: String
    }

    private static let lock = NSLock()
    private static var hits: [Hit] = []
    private static var postBody = ""
    private static var onGET: (@Sendable () async -> Void)?

    static func reset(
        postBody: String = #"<div class="flash notice">Assignment updates complete!</div>"#,
        onGET: (@Sendable () async -> Void)? = nil
    ) {
        lock.lock()
        hits = []
        Self.postBody = postBody
        Self.onGET = onGET
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
        let method = request.httpMethod ?? "GET"
        let hit = Hit(method: method, url: url, body: Self.bodyText(of: request))
        Self.lock.lock()
        Self.hits.append(hit)
        let postBody = Self.postBody
        let onGET = Self.onGET
        Self.lock.unlock()

        let isGET = method == "GET"
        Task {
            if isGET { await onGET?() }
            let page = isGET
                ? #"<html><head><meta name="csrf-token" content="stub-csrf"></head></html>"#
                : postBody
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(page.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    /// URLSession hands a protocol its POST body as a stream.
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

/// 1cb's two writes, against otwarchive's `challenge_assignments#update_multiple`
/// (routes: `put :update_multiple`; `default_<id>` / `cover_<id>` fields).
@Suite(.serialized)
@MainActor
struct AO3ChallengeWriteStubTests {
    private func makeAuth() -> AO3AuthService {
        AO3AuthService(
            vault: MemoryAO3SessionVault(),
            validator: InboxTestSessionValidator(),
            loginPerformer: DynamicInboxTestLoginPerformer(),
            cookieManager: MockAO3CookieManager(),
            removalTracker: MemoryAO3SessionRemovalTracker()
        )
    }

    private func stubClient() -> AO3Client {
        let config = AO3Client.makeAnonymousSessionConfiguration()
        config.protocolClasses = [ChallengeWriteStub.self]
        return AO3Client(session: URLSession(configuration: config), paceSleep: { _ in })
    }

    private func fields(_ body: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in body.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            let key = parts[0].removingPercentEncoding ?? parts[0]
            result[key] = parts.count > 1 ? (parts[1].removingPercentEncoding ?? parts[1]) : ""
        }
        return result
    }

    @Test func reportADefaultTicksTheOwnersDefaultBox() async throws {
        ChallengeWriteStub.reset()
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        try await auth.markAssignmentDefaulted(
            slug: "fest", assignmentID: 81, expectedGeneration: auth.sessionGeneration, using: stubClient()
        )
        let hits = ChallengeWriteStub.recorded()
        try #require(hits.map(\.method) == ["GET", "POST"])
        // The CSRF comes from the Open list, the page that renders default_<id>.
        #expect(hits[0].url.absoluteString == "https://archiveofourown.org/collections/fest/assignments?unfulfilled=true")
        #expect(hits[1].url.path == "/collections/fest/assignments/update_multiple")
        let posted = fields(hits[1].body)
        #expect(posted["_method"] == "put")
        #expect(posted["authenticity_token"] == "stub-csrf")
        #expect(posted["default_81"] == "1")
        #expect(posted.count == 3)
    }

    @Test func claimAPinchHitNamesTheViewerAsPinchHitter() async throws {
        ChallengeWriteStub.reset()
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        try await auth.claimPinchHit(
            slug: "fest", assignmentID: 82, byline: "alice",
            expectedGeneration: auth.sessionGeneration, using: stubClient()
        )
        let hits = ChallengeWriteStub.recorded()
        try #require(hits.map(\.method) == ["GET", "POST"])
        // The Defaulted list is the page with the Pinch Hitter field.
        #expect(hits[0].url.absoluteString == "https://archiveofourown.org/collections/fest/assignments")
        let posted = fields(hits[1].body)
        #expect(posted["cover_82"] == "alice")
        #expect(posted["_method"] == "put")
    }

    @Test func aScreenLoadedUnderAnotherSessionSendsNothing() async throws {
        ChallengeWriteStub.reset()
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let loaded = auth.sessionGeneration
        await auth.logout()
        await auth.login(username: "bob", password: "pw")
        await #expect(throws: CancellationError.self) {
            try await auth.markAssignmentDefaulted(
                slug: "fest", assignmentID: 81, expectedGeneration: loaded, using: stubClient()
            )
        }
        #expect(ChallengeWriteStub.recorded().isEmpty)
    }

    @Test func anAO3ErrorFlashIsReportedNotSwallowed() async throws {
        ChallengeWriteStub.reset(postBody: #"<div class="flash error">We couldn't find the user zed to assign that to.</div>"#)
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        await #expect(throws: AO3ChallengeWriteError.rejected("We couldn't find the user zed to assign that to.")) {
            try await auth.claimPinchHit(
                slug: "fest", assignmentID: 82, byline: "zed",
                expectedGeneration: auth.sessionGeneration, using: stubClient()
            )
        }
    }

    @Test func aBare200DoesNotConfirmAnAssignmentWrite() async throws {
        ChallengeWriteStub.reset(postBody: "<html><body>Ambiguous response</body></html>")
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        await #expect(throws: AO3ChallengeWriteError.unconfirmed) {
            try await auth.markAssignmentDefaulted(
                slug: "fest", assignmentID: 81,
                expectedGeneration: auth.sessionGeneration, using: stubClient()
            )
        }
    }

    @Test func challengeSettingsSaveStopsWhenTheSessionChangesDuringCSRF() async throws {
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let loaded = auth.sessionGeneration
        ChallengeWriteStub.reset(onGET: { await auth.logout() })
        let form = AO3ChallengeSettingsForm(
            actionURL: AO3ChallengeURL.giftExchange(slug: "fest"),
            httpMethodOverride: "put",
            csrfToken: "old",
            kind: .giftExchange,
            collectionSlug: "fest",
            settings: AO3ChallengeSettings(collectionSlug: "fest", kind: .giftExchange)
        )
        await #expect(throws: CancellationError.self) {
            try await auth.updateChallengeSettings(
                form, expectedGeneration: loaded, using: stubClient()
            )
        }
        #expect(ChallengeWriteStub.recorded().map(\.method) == ["GET"])
    }

    @Test func membershipAcceptAndDeclineStopWhenTheSessionChangesDuringCSRF() async throws {
        for action in ["accept", "decline"] {
            let auth = makeAuth()
            await auth.login(username: "alice", password: "pw")
            let loaded = auth.sessionGeneration
            ChallengeWriteStub.reset(onGET: { await auth.logout() })
            await #expect(throws: CancellationError.self) {
                if action == "accept" {
                    try await auth.acceptMember(
                        slug: "fest", participantID: 4,
                        expectedGeneration: loaded, using: stubClient()
                    )
                } else {
                    try await auth.declineMember(
                        slug: "fest", participantID: 4,
                        expectedGeneration: loaded, using: stubClient()
                    )
                }
            }
            #expect(ChallengeWriteStub.recorded().map(\.method) == ["GET"])
        }
    }
}
