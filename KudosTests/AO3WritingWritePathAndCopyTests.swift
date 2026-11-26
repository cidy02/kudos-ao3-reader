import Foundation
import SwiftData
import Testing
@testable import Kudos

private final class WritePathFixtureAnchor {}

/// Local URLProtocol stub supporting real `wasRedirectedTo:` redirect chains
/// (302/307/308) and unfollowed 3xx responses carrying `Location` headers.
private final class WritePathRedirectStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated struct Hit: Sendable {
        var method: String
        var url: URL
    }

    nonisolated enum Action: Sendable {
        case respond(
            status: Int = 200,
            body: String = "",
            headers: [String: String]? = nil,
            finalURL: URL? = nil
        )
        case redirect(to: URL, statusCode: Int, method: String? = nil)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var hits: [Hit] = []
    nonisolated(unsafe) private static var handler: (@Sendable (URLRequest, Int) -> Action)?

    static func reset(_ responder: @escaping @Sendable (URLRequest, Int) -> Action) {
        lock.lock()
        hits = []
        handler = responder
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
        let hit = Hit(method: request.httpMethod ?? "GET", url: url)
        Self.lock.lock()
        Self.hits.append(hit)
        let index = Self.hits.count
        let responder = Self.handler
        Self.lock.unlock()

        switch responder?(request, index) ?? .respond() {
        case let .respond(status, body, headers, finalURL):
            guard let response = HTTPURLResponse(
                url: finalURL ?? url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)

        case let .redirect(targetURL, statusCode, method):
            guard let redirectResponse = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": targetURL.absoluteString]
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            var redirectedRequest = URLRequest(url: targetURL)
            if let method { redirectedRequest.httpMethod = method }
            client?.urlProtocol(
                self,
                wasRedirectedTo: redirectedRequest,
                redirectResponse: redirectResponse
            )
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

/// P2-4 tests: shared `submitWriteWithURL` / `submitWrite` redirect behavior,
/// real 302 only-creator chains, and `OrphanSubmissionFlow.saveLocalCopy` branches.
@Suite(.serialized)
@MainActor
struct AO3WritingWritePathAndCopyTests {

    private func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle(for: WritePathFixtureAnchor.self).url(forResource: name, withExtension: "html")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func demoEPUBURL() throws -> URL {
        if let bundled = Bundle(for: WritePathFixtureAnchor.self).url(
            forResource: "demo_work", withExtension: "epub"
        ) {
            return bundled
        }
        let fallback = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/demo_work.epub")
        #expect(FileManager.default.fileExists(atPath: fallback.path))
        return fallback
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
        config.protocolClasses = [WritePathRedirectStubProtocol.self]
        return AO3Client(session: URLSession(configuration: config), paceSleep: { _ in })
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self, WorkCollection.self,
            ReadingQueue.self, ReadingQueueMembership.self, SavedSearch.self,
            QueueSavedSearchLink.self, SyncTombstone.self, ReadingAnnotation.self,
            ReadingSession.self, ReadingFavorite.self, FandomReadWatermark.self,
            FollowedTag.self, TagAlias.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Shared write path (`submitWriteWithURL` & `submitWrite` redirects)

    @Test func submitWriteWithURLReadsUnfollowed3xxLocationAndRejectsUntrustedHost() async throws {
        let auth = await makeSignedInAuth()
        let importURL = AO3Client.importWorkURL()

        // Unfollowed 303 with relative Location: http.url stays `/works/import`,
        // so finalURL must come from the Location header.
        WritePathRedirectStubProtocol.reset { _, _ in
            .respond(status: 303, body: "", headers: ["Location": "/works/7001/preview"])
        }
        let req1 = try auth.writeRequest(
            to: importURL, body: Data("a=1".utf8), csrf: "t", referer: importURL, ajax: false
        )
        let res1 = try await stubClient().submitWriteWithURL(req1) { [weak auth] prepared in
            auth?.writeSessionStamp == prepared
        }
        #expect(res1.status == 303)
        #expect(res1.finalURL?.absoluteString == "https://archiveofourown.org/works/7001/preview")

        // Untrusted off-host Location is ignored; finalURL stays the AO3 request URL.
        WritePathRedirectStubProtocol.reset { _, _ in
            .respond(status: 303, body: "", headers: ["Location": "https://evil.example/works/7001/preview"])
        }
        let req2 = try auth.writeRequest(
            to: importURL, body: Data("a=1".utf8), csrf: "t", referer: importURL, ajax: false
        )
        let res2 = try await stubClient().submitWriteWithURL(req2) { [weak auth] prepared in
            auth?.writeSessionStamp == prepared
        }
        #expect(res2.status == 303)
        #expect(res2.finalURL?.absoluteString == importURL.absoluteString)
    }

    @Test func submitWriteFollows302LoginRedirectAndRefuses307And308() async throws {
        let auth = await makeSignedInAuth()
        let endpoint = AO3AuthService.kudosEndpoint
        let loginURL = URL(string: "https://archiveofourown.org/users/login")!

        // Real 302 chain to /users/login -> AO3Error.authenticationRequired (2 hops).
        WritePathRedirectStubProtocol.reset { _, index in
            if index == 1 { return .redirect(to: loginURL, statusCode: 302, method: "GET") }
            return .respond(status: 200, body: "<html><body>Log In</body></html>", finalURL: loginURL)
        }
        let loginReq = try auth.writeRequest(
            to: endpoint, body: Data("k=1".utf8), csrf: "t", referer: endpoint, ajax: false
        )
        await #expect(throws: AO3Error.authenticationRequired) {
            _ = try await auth.submitWrite(loginReq, using: stubClient())
        }
        #expect(WritePathRedirectStubProtocol.recorded().map { "\($0.method) \($0.url.path)" } == [
            "POST /kudos.js", "GET /users/login"
        ])

        // 307 and 308 to a POST: the relay never follows them (`AO3RedirectCookieRelay.followsRedirect`),
        // so the task ends with the 3xx itself. Delivered as that final response, not through
        // `wasRedirectedTo:`: a URLProtocol that reports a redirect the delegate then refuses
        // crashed the test runner (out/t575-g3). This also covers the unfollowed-3xx `Location` branch.
        let targetURL = URL(string: "https://archiveofourown.org/works/424242")!
        for statusCode in [307, 308] {
            WritePathRedirectStubProtocol.reset { _, _ in
                .respond(status: statusCode, headers: ["Location": targetURL.absoluteString])
            }
            let req = try auth.writeRequest(
                to: endpoint, body: Data("k=1".utf8), csrf: "t", referer: endpoint, ajax: false
            )
            await #expect(throws: AO3WriteError.unconfirmed) {
                _ = try await auth.submitWrite(req, using: stubClient())
            }
            #expect(WritePathRedirectStubProtocol.recorded().count == 1)
        }

        // An unfollowed 307 whose Location is the login page now reads as sign-in required
        // (it used to be `unconfirmed`); the POST was not accepted either way.
        WritePathRedirectStubProtocol.reset { _, _ in
            .respond(status: 307, headers: ["Location": loginURL.absoluteString])
        }
        let loginRedirectReq = try auth.writeRequest(
            to: endpoint, body: Data("k=1".utf8), csrf: "t", referer: endpoint, ajax: false
        )
        await #expect(throws: AO3Error.authenticationRequired) {
            _ = try await auth.submitWrite(loginRedirectReq, using: stubClient())
        }
        #expect(WritePathRedirectStubProtocol.recorded().count == 1)
    }

    @Test func removeMeAsCoCreatorDetectsOnlyCreatorThroughReal302RedirectChain() async throws {
        let auth = await makeSignedInAuth()
        let cocreatedHTML = try fixture("ao3_work_edit_cocreated")
        let orphanWorkURL = URL(string: "https://archiveofourown.org/orphans/new?work_id=424242")!

        // Hop 1: GET /works/424242/edit (has Remove Me button).
        // Hop 2: POST /works/424242/remove_user_creatorship -> real 302 to /orphans/new?work_id=424242.
        // Hop 3: GET /orphans/new -> bare HTML with NO orphan form so ONLY the real 302 finalURL detects it.
        WritePathRedirectStubProtocol.reset { request, _ in
            if request.httpMethod == "GET", request.url?.path == "/works/424242/edit" {
                return .respond(body: cocreatedHTML)
            }
            if request.httpMethod == "POST", request.url?.path == "/works/424242/remove_user_creatorship" {
                return .redirect(to: orphanWorkURL, statusCode: 302, method: "GET")
            }
            return .respond(
                status: 200,
                body: "<html><body class=\"logged-in\"><div id=\"main\"></div></body></html>",
                finalURL: orphanWorkURL
            )
        }
        await #expect(throws: AO3WorkWriteError.onlyCreator) {
            _ = try await auth.removeMeAsCoCreator(workID: 424242, using: stubClient())
        }
        #expect(WritePathRedirectStubProtocol.recorded().map { "\($0.method) \($0.url.path)" } == [
            "GET /works/424242/edit",
            "POST /works/424242/remove_user_creatorship",
            "GET /orphans/new"
        ])

        // Same real 302 chain for a series.
        let seriesPage = """
        <html><head><meta name="csrf-token" content="series-csrf=="></head>
        <body class="logged-in"><div id="main"><ul class="navigation actions">
          <li><a href="/series/77/edit">Edit Series</a></li>
          <li><form class="button_to" method="post" action="/series/77/remove_user_creatorship">
            <input type="hidden" name="_method" value="patch">
            <input type="hidden" name="authenticity_token" value="series-remove-csrf==">
            <input type="submit" value="Remove Me As Co-Creator">
          </form></li>
        </ul></div></body></html>
        """
        let orphanSeriesURL = URL(string: "https://archiveofourown.org/orphans/new?series_id=77")!
        WritePathRedirectStubProtocol.reset { request, _ in
            if request.httpMethod == "GET", request.url?.path == "/series/77" {
                return .respond(body: seriesPage)
            }
            if request.httpMethod == "POST", request.url?.path == "/series/77/remove_user_creatorship" {
                return .redirect(to: orphanSeriesURL, statusCode: 302, method: "GET")
            }
            return .respond(
                status: 200,
                body: "<html><body class=\"logged-in\"><div id=\"main\"></div></body></html>",
                finalURL: orphanSeriesURL
            )
        }
        await #expect(throws: AO3WorkWriteError.onlyCreator) {
            _ = try await auth.removeMeAsCoCreator(seriesID: 77, using: stubClient())
        }
        #expect(WritePathRedirectStubProtocol.recorded().map { "\($0.method) \($0.url.path)" } == [
            "GET /series/77",
            "POST /series/77/remove_user_creatorship",
            "GET /orphans/new"
        ])
    }

    // MARK: - `saveLocalCopy` pending-deletion and missing-EPUB branches

    @Test func saveLocalCopyRevivesPendingDeletionWorkAndRestoresMissingEPUB() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let epubFixture = try demoEPUBURL()
        var filesToClean: [URL] = []
        defer {
            for url in filesToClean { try? FileManager.default.removeItem(at: url) }
        }

        // Branch 1: existing work in Recently Deleted with readable EPUB on disk ->
        // revives, retracts tombstone, sets isSaved, and does NOT re-download.
        let pendingWork = SavedWork(
            title: "Pending Copy",
            author: "alice",
            summary: "",
            sourceURL: AO3Client.workURL(workID: 987_001).absoluteString
        )
        pendingWork.ao3WorkID = 987_001
        pendingWork.hasEPUB = true
        pendingWork.isSaved = false
        context.insert(pendingWork)
        try FileManager.default.copyItem(at: epubFixture, to: pendingWork.fileURL)
        filesToClean.append(pendingWork.fileURL)
        PreservedWorkService.softDelete(pendingWork, in: context)

        #expect(pendingWork.isPendingDeletion)
        #expect(pendingWork.deletedAt != nil)
        let tombstonesBefore = try context.fetch(FetchDescriptor<SyncTombstone>())
        #expect(tombstonesBefore.contains { $0.recordID == pendingWork.id })

        var pendingDownloads = 0
        try await OrphanSubmissionFlow.saveLocalCopy(
            workID: 987_001,
            in: context,
            downloadEPUB: { _ in
                pendingDownloads += 1
                throw URLError(.cannotFindHost)
            }
        )
        #expect(pendingDownloads == 0)
        #expect(!pendingWork.isPendingDeletion)
        #expect(pendingWork.deletedAt == nil)
        #expect(pendingWork.permanentDeletionScheduledAt == nil)
        #expect(pendingWork.isSaved)
        let tombstonesAfter = try context.fetch(FetchDescriptor<SyncTombstone>())
        #expect(!tombstonesAfter.contains { $0.recordID == pendingWork.id })

        // Branch 2: existing work missing its EPUB on disk (`hasEPUB == false`) ->
        // downloads and restores a readable EPUB and sets `isSaved`.
        let missingEPUBWork = SavedWork(
            title: "Freed Copy",
            author: "alice",
            summary: "",
            sourceURL: AO3Client.workURL(workID: 987_002).absoluteString
        )
        missingEPUBWork.ao3WorkID = 987_002
        missingEPUBWork.hasEPUB = false
        missingEPUBWork.isSaved = false
        context.insert(missingEPUBWork)
        try context.save()
        filesToClean.append(missingEPUBWork.fileURL)
        try? FileManager.default.removeItem(at: missingEPUBWork.fileURL)
        #expect(!WorkReaderPreparation.hasReadableEPUB(for: missingEPUBWork))

        var restoredDownloads = 0
        try await OrphanSubmissionFlow.saveLocalCopy(
            workID: 987_002,
            in: context,
            downloadEPUB: { id in
                #expect(id == 987_002)
                restoredDownloads += 1
                let temp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("t575-restore-\(UUID().uuidString).epub")
                try FileManager.default.copyItem(at: epubFixture, to: temp)
                filesToClean.append(temp)
                return temp
            }
        )
        #expect(restoredDownloads == 1)
        #expect(missingEPUBWork.hasEPUB)
        #expect(WorkReaderPreparation.hasReadableEPUB(for: missingEPUBWork))
        #expect(missingEPUBWork.isSaved)
    }
}
