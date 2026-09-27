import Foundation
import Testing
@testable import Kudos

/// Local stand-in for `URLSession`. `protocolClasses` handles the load, so a
/// regression that still dispatches does not POST to AO3.
private final class AO3WriteDispatchProbe: URLProtocol, @unchecked Sendable {
    struct Hit: Sendable {
        var method: String?
        var url: URL?
        var path: String?
        var body: String?
        var cookie: String?
        var preparedWriteSession: String?
        var handlesCookies: Bool
    }

    private static let lock = NSLock()
    private static var hits: [Hit] = []
    private static var postResponseBody = "fence-ok"
    private static var getResponseBody = #"<meta name="csrf-token" content="probe-csrf">"#

    static func reset(
        postBody: String = "fence-ok",
        getBody: String = #"<meta name="csrf-token" content="probe-csrf">"#
    ) {
        lock.lock()
        hits = []
        postResponseBody = postBody
        getResponseBody = getBody
        lock.unlock()
    }

    static func recorded() -> [Hit] {
        lock.lock()
        defer { lock.unlock() }
        return hits
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    /// URLSession hands a protocol the POST body as a stream, not `httpBody`.
    private static func bodyText(of request: URLRequest) -> String? {
        if let data = request.httpBody { return String(data: data, encoding: .utf8) }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while case let count = stream.read(&buffer, maxLength: buffer.count), count > 0 {
            data.append(buffer, count: count)
        }
        return String(data: data, encoding: .utf8)
    }

    override func startLoading() {
        let hit = Hit(
            method: request.httpMethod,
            url: request.url,
            path: request.url?.path,
            body: Self.bodyText(of: request),
            cookie: request.value(forHTTPHeaderField: "Cookie"),
            preparedWriteSession: request.value(
                forHTTPHeaderField: AO3Client.preparedWriteSessionHeader
            ),
            handlesCookies: request.httpShouldHandleCookies
        )
        Self.lock.lock()
        Self.hits.append(hit)
        let postBody = Self.postResponseBody
        let getBody = Self.getResponseBody
        Self.lock.unlock()

        // A GET is a write's CSRF fetch: answer with a page carrying the token.
        let isGET = request.httpMethod == "GET"
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url, statusCode: isGET ? 200 : 201, httpVersion: "HTTP/1.1", headerFields: nil
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let body = isGET ? getBody : postBody
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// `submitWrite` used to await `pace()` and then POST the Cookie it was handed.
/// A generation change inside that wait still sent the old account's write.
@Suite(.serialized)
@MainActor
struct AO3WriteDispatchFenceTests {
    private func makeAuth() -> AO3AuthService {
        AO3AuthService(
            vault: MemoryAO3SessionVault(),
            validator: InboxTestSessionValidator(),
            loginPerformer: DynamicInboxTestLoginPerformer(),
            cookieManager: MockAO3CookieManager(),
            removalTracker: MemoryAO3SessionRemovalTracker()
        )
    }

    private func probeSession() -> URLSession {
        let config = AO3Client.makeAnonymousSessionConfiguration()
        config.protocolClasses = [AO3WriteDispatchProbe.self]
        return URLSession(configuration: config)
    }

    private func preparedWrite(on auth: AO3AuthService) throws -> URLRequest {
        try auth.writeRequest(
            to: AO3AuthService.kudosEndpoint,
            body: Data("kudo=1".utf8),
            csrf: "csrf-token",
            referer: AO3AuthService.workURL(1),
            ajax: true
        )
    }

    /// A held generation still sends exactly once, with the explicit Cookie and
    /// without the stamp header that must never leave the process.
    @Test func anUnchangedGenerationStillDispatchesOnce() async throws {
        AO3WriteDispatchProbe.reset()
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let request = try preparedWrite(on: auth)
        let stamp = auth.writeSessionStamp
        #expect(
            request.value(forHTTPHeaderField: AO3Client.preparedWriteSessionHeader) == stamp
        )

        let client = AO3Client(
            session: probeSession(),
            nextAllowedRequestAt: Date().addingTimeInterval(60),
            paceSleep: { _ in }
        )
        let (status, body) = try await auth.submitWrite(request, using: client)

        #expect(status == 201)
        #expect(body == "fence-ok")
        let hits = AO3WriteDispatchProbe.recorded()
        #expect(hits.count == 1)
        #expect(hits.first?.handlesCookies == false)
        #expect(hits.first?.preparedWriteSession == nil)
        #expect(hits.first?.cookie?.contains("_otwarchive_session=session-alice") == true)
        #expect(auth.writeSessionStamp == stamp)
    }

    /// The generation that built the Cookie changes while `pace()` is suspended.
    /// Parent behavior dispatched after the sleep. This must not.
    @Test func aGenerationChangeDuringThePacingWaitDoesNotDispatch() async throws {
        AO3WriteDispatchProbe.reset()
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let request = try preparedWrite(on: auth)
        let prepared = auth.sessionGeneration
        let entered = Signal()
        let release = Signal()
        let client = AO3Client(
            session: probeSession(),
            nextAllowedRequestAt: Date().addingTimeInterval(60),
            paceSleep: { _ in
                await entered.fire()
                await release.wait()
            }
        )

        let task = Task {
            try await auth.submitWrite(request, using: client)
        }
        await entered.wait()
        #expect(auth.sessionGeneration == prepared)
        await auth.logout()
        #expect(auth.sessionGeneration != prepared)
        await release.fire()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(AO3WriteDispatchProbe.recorded().isEmpty)
    }

    /// A change after `writeRequest` and before `submitWrite` is the same queued
    /// write. The service that prepared it must no longer authorize it.
    @Test func aGenerationChangeAfterTheRequestWasBuiltDoesNotDispatch() async throws {
        AO3WriteDispatchProbe.reset()
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let request = try preparedWrite(on: auth)
        let prepared = auth.sessionGeneration
        await auth.logout()
        #expect(auth.sessionGeneration != prepared)

        let client = AO3Client(
            session: probeSession(),
            nextAllowedRequestAt: Date().addingTimeInterval(60),
            paceSleep: { _ in }
        )

        await #expect(throws: CancellationError.self) {
            try await auth.submitWrite(request, using: client)
        }
        #expect(AO3WriteDispatchProbe.recorded().isEmpty)
    }

    /// A second service can have the same integer generation. It still must not
    /// authorize a request carrying the first service's Cookie.
    @Test func anotherAuthServiceAtTheSameGenerationDoesNotDispatch() async throws {
        AO3WriteDispatchProbe.reset()
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let request = try preparedWrite(on: auth)
        let otherAuth = makeAuth()
        await otherAuth.login(username: "bob", password: "pw")
        #expect(otherAuth.sessionGeneration == auth.sessionGeneration)

        let client = AO3Client(
            session: probeSession(),
            nextAllowedRequestAt: Date().addingTimeInterval(60),
            paceSleep: { _ in }
        )

        await #expect(throws: CancellationError.self) {
            try await otherAuth.submitWrite(request, using: client)
        }
        #expect(AO3WriteDispatchProbe.recorded().isEmpty)
    }

    /// Every production caller uses `writeRequest`. A caller that bypasses it
    /// must fail closed rather than silently submitting an unfenced write.
    @Test func anUnstampedWriteDoesNotDispatch() async throws {
        AO3WriteDispatchProbe.reset()
        let auth = makeAuth()
        let client = AO3Client(session: probeSession())
        let request = URLRequest(url: AO3AuthService.kudosEndpoint)

        await #expect(throws: CancellationError.self) {
            try await auth.submitWrite(request, using: client)
        }
        #expect(AO3WriteDispatchProbe.recorded().isEmpty)
    }

    /// What `mark_as_read` redirects back to: the page it came from, with
    /// AO3's notice (Q19).
    private static let unmarkedNotice = #"<div class="flash notice">This work was removed from your "#
        + #"<a href="/users/alice/readings?show=to-read">Marked for Later list</a>.</div>"#

    /// 1o.4's Unmark: one CSRF GET of the work page, then one POST to
    /// `/works/:id/mark_as_read` carrying `_method=patch` (Q19). Stub only.
    @Test func unmarkForLaterPatchesMarkAsReadOnce() async throws {
        AO3WriteDispatchProbe.reset(postBody: Self.unmarkedNotice)
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let client = AO3Client(session: probeSession(), paceSleep: { _ in })

        let message = try await auth.unmarkForLater(
            workID: 42, expectedGeneration: auth.sessionGeneration, using: client
        )

        #expect(message == "Unmarked.")
        let hits = AO3WriteDispatchProbe.recorded()
        #expect(hits.map(\.method) == ["GET", "POST"])
        #expect(hits.map(\.path) == ["/works/42", "/works/42/mark_as_read"])
        #expect(hits.last?.body?.contains("_method=patch") == true)
        #expect(hits.last?.body?.contains("authenticity_token=probe-csrf") == true)
    }

    /// Bob signs in while alice's CSRF GET is out: alice's unmark must not post
    /// under bob's session.
    @Test func aSessionChangeDuringTheUnmarkCSRFFetchPostsNothing() async throws {
        AO3WriteDispatchProbe.reset()
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let client = AO3Client(
            session: probeSession(),
            nextAllowedRequestAt: Date().addingTimeInterval(60),
            paceSleep: { @MainActor _ in
                guard auth.username == "alice" else { return }
                await auth.logout()
                await auth.login(username: "bob", password: "pw")
            }
        )

        let tapped = auth.sessionGeneration
        await #expect(throws: CancellationError.self) {
            _ = try await auth.unmarkForLater(workID: 42, expectedGeneration: tapped, using: client)
        }
        #expect(auth.username == "bob")
        #expect(AO3WriteDispatchProbe.recorded().map(\.method) == ["GET"])
    }

    /// Alice taps Unmark; bob is signed in before the write's task runs. The
    /// generation is the tap's, so nothing goes out — not even the GET, which
    /// would carry bob's cookie.
    @Test func anUnmarkTappedUnderAnEarlierSessionSendsNothing() async throws {
        AO3WriteDispatchProbe.reset(postBody: Self.unmarkedNotice)
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let tapped = auth.sessionGeneration
        await auth.logout()
        await auth.login(username: "bob", password: "pw")
        let client = AO3Client(session: probeSession(), paceSleep: { _ in })

        await #expect(throws: CancellationError.self) {
            _ = try await auth.unmarkForLater(workID: 42, expectedGeneration: tapped, using: client)
        }
        #expect(AO3WriteDispatchProbe.recorded().isEmpty)
    }

    /// A final page with no flash (a maintenance page, an interstitial) is not
    /// an unmark, and AO3's error flash is its reason. Either way the caller
    /// keeps the row: only a returned message removes it.
    @Test func anUnmarkWithoutAO3sNoticeIsNotASuccess() async throws {
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let client = AO3Client(session: probeSession(), paceSleep: { _ in })

        AO3WriteDispatchProbe.reset(postBody: "<html><body><h2>Down for maintenance</h2></body></html>")
        await #expect(throws: AO3WriteError.unconfirmed) {
            _ = try await auth.unmarkForLater(
                workID: 42, expectedGeneration: auth.sessionGeneration, using: client
            )
        }

        AO3WriteDispatchProbe.reset(postBody: #"<div class="flash error">Sorry, you don't have permission.</div>"#)
        await #expect(throws: AO3WriteError.rejected("Sorry, you don't have permission.")) {
            _ = try await auth.unmarkForLater(
                workID: 42, expectedGeneration: auth.sessionGeneration, using: client
            )
        }
    }

    private func collectionForm() -> AO3CollectionForm {
        var form = AO3CollectionForm.blank
        form.name = "alice_fest"
        form.title = "Alice Fest"
        return form
    }

    /// The fence above compares a POST with its own CSRF GET, so a collection
    /// form loaded as alice and saved after bob signs in would pass it: the GET
    /// and the POST are both bob's. The form's own generation stops it first,
    /// before any request.
    @Test func aCollectionFormLoadedUnderAnEarlierSessionIsNotSaved() async throws {
        AO3WriteDispatchProbe.reset()
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let formGeneration = auth.sessionGeneration
        await auth.logout()
        await auth.login(username: "bob", password: "pw")
        #expect(auth.isLoggedIn)
        let client = AO3Client(session: probeSession(), paceSleep: { _ in })

        await #expect(throws: CancellationError.self) {
            try await auth.createCollection(collectionForm(), expectedGeneration: formGeneration, using: client)
        }
        await #expect(throws: CancellationError.self) {
            try await auth.updateCollection(
                slug: "alice_fest", form: collectionForm(), expectedGeneration: formGeneration, using: client
            )
        }
        await #expect(throws: CancellationError.self) {
            try await auth.deleteCollection(
                slug: "alice_fest", expectedGeneration: formGeneration, using: client
            )
        }
        #expect(AO3WriteDispatchProbe.recorded().isEmpty)
    }

    /// Bob signs in while alice's CSRF GET is out. Nothing downstream catches
    /// it: `writeRequest` would stamp bob's session, so the dispatch fence would
    /// send bob's cookie with alice's form. Only the check after the GET stops it.
    @Test func aSessionChangeDuringTheCollectionCSRFFetchPostsNothing() async throws {
        let auth = makeAuth()
        // Every request waits out its pace slot here. The first is the GET's,
        // after its Cookie was built and before the page comes back.
        let client = AO3Client(
            session: probeSession(),
            nextAllowedRequestAt: Date().addingTimeInterval(60),
            paceSleep: { @MainActor _ in
                guard auth.username == "alice" else { return }
                await auth.logout()
                await auth.login(username: "bob", password: "pw")
            }
        )

        for isUpdate in [false, true] {
            AO3WriteDispatchProbe.reset()
            await auth.logout()
            await auth.login(username: "alice", password: "pw")
            let formGeneration = auth.sessionGeneration

            await #expect(throws: CancellationError.self) {
                if isUpdate {
                    _ = try await auth.updateCollection(
                        slug: "alice_fest", form: collectionForm(), expectedGeneration: formGeneration, using: client
                    )
                } else {
                    _ = try await auth.createCollection(
                        collectionForm(), expectedGeneration: formGeneration, using: client
                    )
                }
            }
            #expect(auth.username == "bob")
            #expect(AO3WriteDispatchProbe.recorded().map(\.method) == ["GET"])
        }
    }

    /// Collection deletion follows AO3's owner flow: confirmation GET, then one
    /// method-override POST. The protocol stub keeps both requests local.
    @Test func collectionDeleteUsesTheConfirmationRouteAndOneDeletePost() async throws {
        AO3WriteDispatchProbe.reset(
            postBody: #"<div class="flash notice">Collection was successfully deleted.</div>"#,
            getBody: """
            <meta name="csrf-token" content="wrong-page-token">
            <form class="simple destroy" action="/collections/alice_fest" method="post">
              <input name="authenticity_token" value="probe-csrf">
              <input type="submit" value="Yes, Delete Collection">
            </form>
            """
        )
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let generation = auth.sessionGeneration
        let client = AO3Client(session: probeSession(), paceSleep: { _ in })

        let message = try await auth.deleteCollection(
            slug: "alice_fest", expectedGeneration: generation, using: client
        )

        #expect(message == "Collection was successfully deleted.")
        let hits = AO3WriteDispatchProbe.recorded()
        #expect(hits.map(\.method) == ["GET", "POST"])
        #expect(hits.first?.url?.path == "/collections/alice_fest/confirm_delete")
        #expect(hits.last?.url?.path == "/collections/alice_fest")
        #expect(hits.last?.body?.contains("_method=delete") == true)
        #expect(hits.last?.body?.contains("authenticity_token=probe-csrf") == true)
    }

    @Test func collectionDeleteRefusesAConfirmResponseWithoutTheDestroyForm() async throws {
        AO3WriteDispatchProbe.reset(
            getBody: #"<meta name="csrf-token" content="probe-csrf"><h2>Collections</h2>"#
        )
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let client = AO3Client(session: probeSession(), paceSleep: { _ in })

        await #expect(throws: AO3CollectionWriteError.self) {
            try await auth.deleteCollection(
                slug: "alice_fest", expectedGeneration: auth.sessionGeneration, using: client
            )
        }
        #expect(AO3WriteDispatchProbe.recorded().map(\.method) == ["GET"])
    }

    /// Bob signs in while alice's confirmation GET is out. Only the check after
    /// the GET stops the POST: the dispatch fence would pass bob's own stamp.
    @Test func aSessionChangeDuringTheDeleteCSRFFetchPostsNothing() async throws {
        // Every AO3 page carries the layout's csrf meta tag; the confirm page
        // adds the destroy form whose token the delete posts.
        AO3WriteDispatchProbe.reset(getBody: """
        <meta name="csrf-token" content="probe-csrf">
        <form class="simple destroy" action="/collections/alice_fest" method="post">
          <input name="authenticity_token" value="probe-csrf">
          <input type="submit" value="Yes, Delete Collection">
        </form>
        """)
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let generation = auth.sessionGeneration
        let client = AO3Client(
            session: probeSession(),
            nextAllowedRequestAt: Date().addingTimeInterval(60),
            paceSleep: { @MainActor _ in
                guard auth.username == "alice" else { return }
                await auth.logout()
                await auth.login(username: "bob", password: "pw")
            }
        )

        await #expect(throws: CancellationError.self) {
            try await auth.deleteCollection(
                slug: "alice_fest", expectedGeneration: generation, using: client
            )
        }
        #expect(auth.username == "bob")
        #expect(AO3WriteDispatchProbe.recorded().map(\.method) == ["GET"])
    }
}
