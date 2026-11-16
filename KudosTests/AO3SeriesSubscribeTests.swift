import Foundation
import Testing
@testable import Kudos

/// Local stand-in for AO3 behind `URLSession.protocolClasses`: nothing here
/// reaches archiveofourown.org.
private final class SeriesSubscribeStub: URLProtocol, @unchecked Sendable {
    struct Hit: Sendable {
        var method: String
        var url: URL
        var body: String
        var referer: String?
        var csrfHeader: String?
    }

    private static let lock = NSLock()
    private static var hits: [Hit] = []
    private static var getHTML = ""
    private static var postStatus = 200
    private static var postBody = ""
    private static var onGET: (@Sendable () async -> Void)?

    static func reset(
        getHTML: String = "",
        postStatus: Int = 200,
        postBody: String = #"<div class="flash notice">You are now following The Coast Road.</div>"#,
        onGET: (@Sendable () async -> Void)? = nil
    ) {
        lock.lock()
        hits = []
        Self.getHTML = getHTML
        Self.postStatus = postStatus
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
        let hit = Hit(
            method: method,
            url: url,
            body: Self.bodyText(of: request),
            referer: request.value(forHTTPHeaderField: "Referer"),
            csrfHeader: request.value(forHTTPHeaderField: "X-CSRF-Token")
        )
        Self.lock.lock()
        Self.hits.append(hit)
        let getHTML = Self.getHTML
        let postStatus = Self.postStatus
        let postBody = Self.postBody
        let onGET = Self.onGET
        Self.lock.unlock()

        let isGET = method == "GET"
        Task {
            if isGET { await onGET?() }
            let body = isGET ? getHTML : postBody
            let status = isGET ? 200 : postStatus
            let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
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

@Suite(.serialized)
@MainActor
struct AO3SeriesSubscribeTests {
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
        config.protocolClasses = [SeriesSubscribeStub.self]
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

    private func seriesHTML(seriesID: Int, subscriptionID: Int? = nil) -> String {
        let form: String
        if let subscriptionID {
            form = """
            <form class="ajax-create-destroy" id="edit_subscription_\(subscriptionID)"
                  action="/users/alice/subscriptions/\(subscriptionID)" method="post">
              <input type="hidden" name="_method" value="delete">
              <input type="hidden" name="subscription[subscribable_id]" value="\(seriesID)">
              <input type="hidden" name="subscription[subscribable_type]" value="Series">
              <input type="submit" name="commit" value="Unsubscribe">
            </form>
            """
        } else {
            form = """
            <form class="ajax-create-destroy" id="new_subscription"
                  action="/users/alice/subscriptions" method="post">
              <input type="hidden" name="subscription[subscribable_id]" value="\(seriesID)">
              <input type="hidden" name="subscription[subscribable_type]" value="Series">
              <input type="submit" name="commit" value="Subscribe">
            </form>
            """
        }
        return """
        <html>
          <head><meta name="csrf-token" content="series-csrf"></head>
          <body class="logged-in">
            <ul class="navigation actions">
              <li>\(form)</li>
            </ul>
          </body>
        </html>
        """
    }

    @Test func subscribesToSeriesWithTypeSeriesAndSeriesID() async throws {
        SeriesSubscribeStub.reset(getHTML: seriesHTML(seriesID: 42))
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")

        let message = try await auth.toggleSubscribe(seriesID: 42, using: stubClient())
        #expect(message == "Subscribed.")

        let hits = SeriesSubscribeStub.recorded()
        #expect(hits.count == 2)
        #expect(hits[0].method == "GET")
        #expect(hits[0].url.absoluteString == "https://archiveofourown.org/series/42")

        let post = hits[1]
        #expect(post.method == "POST")
        #expect(post.url.absoluteString == "https://archiveofourown.org/users/alice/subscriptions")
        #expect(post.referer == "https://archiveofourown.org/series/42")
        #expect(post.csrfHeader == "series-csrf")
        let posted = fields(post.body)
        #expect(posted["authenticity_token"] == "series-csrf")
        #expect(posted["subscription[subscribable_id]"] == "42")
        #expect(posted["subscription[subscribable_type]"] == "Series")
    }

    @Test func unsubscribesWhenAlreadySubscribedOnSeriesPage() async throws {
        SeriesSubscribeStub.reset(
            getHTML: seriesHTML(seriesID: 42, subscriptionID: 789),
            postBody: #"<div class="flash notice">You have successfully unsubscribed from The Coast Road.</div>"#
        )
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")

        let message = try await auth.toggleSubscribe(seriesID: 42, using: stubClient())
        #expect(message == "Unsubscribed.")

        let hits = SeriesSubscribeStub.recorded()
        #expect(hits.count == 2)
        let post = hits[1]
        #expect(post.method == "POST")
        #expect(post.url.absoluteString == "https://archiveofourown.org/users/alice/subscriptions/789")
        let posted = fields(post.body)
        #expect(posted["_method"] == "delete")
        #expect(posted["authenticity_token"] == "series-csrf")
    }

    @Test func signedOutDoesNotSendAnyRequest() async throws {
        SeriesSubscribeStub.reset(getHTML: seriesHTML(seriesID: 42))
        let auth = makeAuth()

        await #expect(throws: AO3WriteError.notSignedIn) {
            _ = try await auth.toggleSubscribe(seriesID: 42, using: stubClient())
        }
        #expect(SeriesSubscribeStub.recorded().isEmpty)

        var handlerCalls = 0
        let model = AO3SeriesSubscribeModel { _, _ in
            handlerCalls += 1
            return "Subscribed."
        }
        model.tapped(seriesID: 42, auth: auth)
        #expect(handlerCalls == 0)
        #expect(model.banner == AO3WriteError.notSignedIn.errorDescription)
        #expect(model.writeFailures == 1)
        #expect(!model.isWorking)
    }

    @Test func failureSurfacesErrorAndPreservesSubscribedState() async throws {
        SeriesSubscribeStub.reset(
            getHTML: seriesHTML(seriesID: 42),
            postStatus: 422,
            postBody: #"<div class="flash error">Subscription failed.</div>"#
        )
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")

        await #expect(throws: AO3WriteError.rejected("Subscription failed.")) {
            _ = try await auth.toggleSubscribe(seriesID: 42, using: stubClient())
        }

        let client = stubClient()
        let model = AO3SeriesSubscribeModel { seriesID, auth in
            try await auth.toggleSubscribe(seriesID: seriesID, using: client)
        }
        model.tapped(seriesID: 42, auth: auth)
        await model.waitForCurrentTask()

        #expect(!model.isSubscribed)
        #expect(model.banner == "Subscription failed.")
        #expect(model.writeFailures == 1)
        #expect(model.writeSuccesses == 0)
        #expect(!model.isWorking)
    }

    @Test func noRequestWhenCancelled() async throws {
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")

        // 1. Cancelling the unsubscribe confirmation dialog sends zero requests.
        var handlerCalls = 0
        let model = AO3SeriesSubscribeModel { _, _ in
            handlerCalls += 1
            return "Unsubscribed."
        }
        model.syncFromSeriesPage(html: seriesHTML(seriesID: 42, subscriptionID: 789), isLoggedIn: true)
        #expect(model.isSubscribed)
        model.tapped(seriesID: 42, auth: auth)
        #expect(model.isConfirmingUnsubscribe)
        model.cancelUnsubscribe()
        #expect(!model.isConfirmingUnsubscribe)
        #expect(handlerCalls == 0)
        #expect(model.isSubscribed)

        // 2. Cancelling the in-flight task before POST sends no POST request.
        let getEntered = Signal()
        let getRelease = Signal()
        SeriesSubscribeStub.reset(
            getHTML: seriesHTML(seriesID: 42),
            onGET: {
                await getEntered.fire()
                await getRelease.wait()
            }
        )
        let client = stubClient()
        let task = Task {
            try await auth.toggleSubscribe(seriesID: 42, using: client)
        }
        await getEntered.wait()
        task.cancel()
        await getRelease.fire()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        let posts = SeriesSubscribeStub.recorded().filter { $0.method == "POST" }
        #expect(posts.isEmpty)
    }

    @Test func flashless200AndUnrelatedAlreadySubscribedBodyDoNotReportSubscribed() async throws {
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")

        // 1. Flashless 200 whose prose contains "already subscribed" is unconfirmed, not success.
        SeriesSubscribeStub.reset(
            getHTML: seriesHTML(seriesID: 42),
            postStatus: 200,
            postBody: "<div class='summary'><p>Reader note: already subscribed.</p></div>"
        )
        await #expect(throws: AO3WriteError.unconfirmed) {
            _ = try await auth.toggleSubscribe(seriesID: 42, using: stubClient())
        }

        let unconfirmedClient = stubClient()
        let model = AO3SeriesSubscribeModel { seriesID, auth in
            try await auth.toggleSubscribe(seriesID: seriesID, using: unconfirmedClient)
        }
        model.tapped(seriesID: 42, auth: auth)
        await model.waitForCurrentTask()
        #expect(!model.isSubscribed)
        #expect(model.banner == AO3WriteError.unconfirmed.errorDescription)
        #expect(model.writeFailures == 1)
        #expect(model.writeSuccesses == 0)

        // 2. Error flash rejects even if unrelated body text says "already subscribed".
        SeriesSubscribeStub.reset(
            getHTML: seriesHTML(seriesID: 42),
            postStatus: 422,
            postBody: """
            <div class="flash error">Rate limit exceeded.</div>
            <p class="summary">Notes say already subscribed elsewhere.</p>
            """
        )
        await #expect(throws: AO3WriteError.rejected("Rate limit exceeded.")) {
            _ = try await auth.toggleSubscribe(seriesID: 42, using: stubClient())
        }

        // 3. Parsed error flash saying "already subscribed" still returns the benign message.
        SeriesSubscribeStub.reset(
            getHTML: seriesHTML(seriesID: 42),
            postStatus: 422,
            postBody: #"<div class="flash error">You have already subscribed to this series.</div>"#
        )
        let already = try await auth.toggleSubscribe(seriesID: 42, using: stubClient())
        #expect(already == "You're already subscribed.")
    }

    @Test func loggedOutSeriesPageThrowsAuthenticationRequiredBeforePOST() async throws {
        let loggedOutSeriesHTML = """
        <html>
          <head><meta name="csrf-token" content="guest-csrf"></head>
          <body class="series-show">
            <div id="header"><a href="/users/login">Log In</a></div>
            <div id="main"><h2 class="heading">The Coast Road</h2></div>
          </body>
        </html>
        """
        SeriesSubscribeStub.reset(getHTML: loggedOutSeriesHTML)
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")

        await #expect(throws: AO3Error.authenticationRequired) {
            _ = try await auth.toggleSubscribe(seriesID: 42, using: stubClient())
        }

        let hits = SeriesSubscribeStub.recorded()
        #expect(hits.count == 1)
        #expect(hits[0].method == "GET")
        #expect(hits.filter { $0.method == "POST" }.isEmpty)
    }

    @Test func syncStateRequiresSignedInPage1IgnoresMidWriteSyncAndIsolatesCacheBySession() async throws {
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")

        let writeEntered = Signal()
        let writeRelease = Signal()
        let model = AO3SeriesSubscribeModel { _, _ in
            await writeEntered.fire()
            await writeRelease.wait()
            return "Subscribed."
        }

        // Before page 1 finishes, state is unknown.
        #expect(!model.hasSyncedSubscription)
        model.syncFromSeriesPage(html: seriesHTML(seriesID: 42, subscriptionID: 789), isLoggedIn: false)
        #expect(!model.hasSyncedSubscription)
        #expect(!model.isSubscribed)

        // Page 1 sync sets state and marks it known.
        model.syncFromSeriesPage(html: seriesHTML(seriesID: 42), isLoggedIn: true)
        #expect(model.hasSyncedSubscription)
        #expect(!model.isSubscribed)

        // A stale page-1 sync arriving while a write is in flight must not overwrite isSubscribed.
        model.tapped(seriesID: 42, auth: auth)
        await writeEntered.wait()
        #expect(model.isWorking)
        model.syncFromSeriesPage(html: seriesHTML(seriesID: 42, subscriptionID: 789), isLoggedIn: true)
        #expect(!model.isSubscribed)
        await writeRelease.fire()
        await model.waitForCurrentTask()
        #expect(model.isSubscribed)

        model.reset()
        #expect(!model.hasSyncedSubscription)
        #expect(!model.isSubscribed)

        // Re-logging in as the same user changes sessionScopedCacheScope, isolating cached series HTML.
        let url = URL(string: "https://archiveofourown.org/series/999042")!
        let firstScope = AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth)
        let firstKey = AO3AuthorPageCache.Key(url: url, authenticationScope: firstScope)
        await AO3AuthorPageCache.shared.insert(
            seriesHTML(seriesID: 999042, subscriptionID: 789), for: firstKey
        )

        await auth.logout()
        await auth.login(username: "alice", password: "pw")
        let secondScope = AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth)
        let secondKey = AO3AuthorPageCache.Key(url: url, authenticationScope: secondScope)
        #expect(firstScope != secondScope)
        #expect(await AO3AuthorPageCache.shared.value(for: secondKey) == nil)

        await AO3AuthorProfileFetcher.invalidate(url, auth: auth, cacheScope: firstScope)
        #expect(await AO3AuthorPageCache.shared.value(for: firstKey) == nil)
    }
}
