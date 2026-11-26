import Foundation
import Testing
@testable import Kudos

private final class WritingP3FixtureAnchor {}

/// Independent local URLProtocol stub for T-575 Part 3b (P3) regression tests.
private final class WritingP3StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated struct Hit: Sendable {
        var method: String
        var url: URL
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
        let hit = Hit(method: request.httpMethod ?? "GET", url: url)
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
}

/// Regression tests for T-575 Part 3b (P3-1 through P3-10).
@Suite(.serialized)
@MainActor
struct AO3WritingRequestsP3Tests {

    private func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle(for: WritingP3FixtureAnchor.self).url(forResource: name, withExtension: "html")
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
        config.protocolClasses = [WritingP3StubProtocol.self]
        return AO3Client(session: URLSession(configuration: config), paceSleep: { _ in })
    }

    // MARK: - P3-2: Partial multi-import preserves both IDs and failed-URL errors

    @Test func partialMultiImportKeepsBothImportedIDsAndFailedURLs() async throws {
        let auth = await makeSignedInAuth()
        let partialHTML = try fixture("ao3_work_import_several").replacingOccurrences(
            of: #"<div class="flash notice">"#,
            with: """
            <div class="flash error"><h3>Failed Imports</h3><dl>
              <dt>https://example.com/broken-1</dt><dd>Story could not be downloaded.</dd>
              <dt>https://example.com/broken-2</dt><dd>We couldn't find any text.</dd>
            </dl></div>
            <div class="flash notice">
            """
        )

        let parsed = try AO3Client.parseImportResult(
            status: 200,
            body: partialHTML,
            finalURL: URL(string: "https://archiveofourown.org/works/import")
        )
        guard case let .several(ids, failures) = parsed else {
            Issue.record("Expected .several with failures, got \(parsed)")
            return
        }
        #expect(ids == [7001, 7002])
        let failureText = try #require(failures)
        #expect(failureText.contains("https://example.com/broken-1"))
        #expect(failureText.contains("Story could not be downloaded."))
        #expect(failureText.contains("https://example.com/broken-2"))
        #expect(failureText.contains("We couldn't find any text."))

        let importForm = try AO3Client.parseImportForm(from: try fixture("ao3_work_import_form"))
        let importRequest = AO3ImportRequest(
            urls: ["https://example.com/ok-1", "https://example.com/broken-1"],
            languageID: "1"
        )
        WritingP3StubProtocol.reset { _ in
            WritingP3StubProtocol.Reply(
                status: 200,
                body: partialHTML,
                finalURL: URL(string: "https://archiveofourown.org/works/import")
            )
        }
        let outcome = await AO3ImportSubmissionFlow.run(
            request: importRequest,
            form: importForm,
            submit: { req, form in try await auth.importWorks(req, form: form, using: stubClient()) }
        )
        #expect(outcome == .several([7001, 7002], failures: failureText))
    }

    // MARK: - P3-3: Orphan `.works` pairs IDs from link hrefs, not request order

    @Test func orphanWorksPairsEachIDFromItsOwnLinkRegardlessOfRequestOrder() async throws {
        let auth = await makeSignedInAuth()
        // Request asks for [22, 11], while AO3 renders DB order [11, 22].
        let dbOrderHTML = try fixture("ao3_orphan_work")
            .replacingOccurrences(
                of: #"<dt>[\s\S]*?</dt>"#,
                with: #"<dt><a href="/works/11">First Story</a></dt><dt><a href="/works/22">Second Story</a></dt>"#,
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"<input type="hidden" name="work_ids[]" id="work_ids_0" value="424242" autocomplete="off">"#,
                with: """
                <input type="hidden" name="work_ids[]" id="work_ids_0" value="11" autocomplete="off">
                <input type="hidden" name="work_ids[]" id="work_ids_1" value="22" autocomplete="off">
                """
            )

        let form = try AO3Client.parseOrphanForm(from: dbOrderHTML, target: .works([22, 11]))
        #expect(form.workItems == [
            AO3OrphanCopyWork(workID: 11, title: "First Story"),
            AO3OrphanCopyWork(workID: 22, title: "Second Story")
        ])

        let resolved = try await OrphanSubmissionFlow.resolveCopyItems(
            for: .works([22, 11]), form: form, auth: auth, using: stubClient()
        )
        #expect(resolved == [
            OrphanSubmissionFlow.WorkCopyItem(workID: 11, title: "First Story"),
            OrphanSubmissionFlow.WorkCopyItem(workID: 22, title: "Second Story")
        ])

        // Failing to copy work 22 must name "Second Story", not "First Story", and send no orphan POST.
        var orphanCalls = 0
        let outcome = await OrphanSubmissionFlow.run(
            target: .works([22, 11]),
            keepPseudCopy: false,
            keepLocalCopy: true,
            finalAlertDecision: .confirmed,
            form: form,
            resolveWorks: { resolved },
            copyWork: { workID in
                if workID == 22 { throw AO3Error.network("Timed out") }
            },
            submitOrphan: { _, _, _ in
                orphanCalls += 1
                return "Orphaning was successful."
            }
        )
        #expect(orphanCalls == 0)
        if case let .copyFailed(workTitle, _) = outcome {
            #expect(workTitle == "Second Story")
        } else {
            Issue.record("Expected copyFailed for Second Story, got \(outcome)")
        }

        // Mismatched link href IDs fail parsing instead of pairing wrong IDs.
        let wrongLinkHTML = dbOrderHTML.replacingOccurrences(of: "/works/22", with: "/works/99")
        #expect(throws: AO3Error.parse) {
            _ = try AO3Client.parseOrphanForm(from: wrongLinkHTML, target: .works([22, 11]))
        }
    }

    // MARK: - P3-4: Remove Me fails closed on unrecognised pages

    @Test func removeMeFailsClosedWithParseErrorAndSendsNoPostOnUnrecognizedPage() async throws {
        let unrecognizedHTML = """
        <!DOCTYPE html>
        <html><head><meta name="csrf-token" content="decoy-csrf=="></head>
        <body class="logged-in"><div id="main"><p>Unexpected page layout</p></div></body></html>
        """

        #expect(throws: AO3Error.parse) {
            _ = try AO3Client.removeMeButtonState(
                in: unrecognizedHTML,
                actionPath: "/works/424242/remove_user_creatorship",
                isRecognizedOwnerPage: { _ in false }
            )
        }

        let auth = await makeSignedInAuth()
        WritingP3StubProtocol.reset { _ in WritingP3StubProtocol.Reply(body: unrecognizedHTML) }
        await #expect(throws: AO3Error.parse) {
            _ = try await auth.removeMeAsCoCreator(workID: 424242, using: stubClient())
        }
        #expect(WritingP3StubProtocol.recorded().map(\.method) == ["GET"])

        WritingP3StubProtocol.reset { _ in WritingP3StubProtocol.Reply(body: unrecognizedHTML) }
        await #expect(throws: AO3Error.parse) {
            _ = try await auth.removeMeAsCoCreator(seriesID: 77, using: stubClient())
        }
        #expect(WritingP3StubProtocol.recorded().map(\.method) == ["GET"])
    }

    // MARK: - P3-5: Co-creator checkbox selector accepts older Rails `[selected][]`

    @Test func coCreatorRequestsParsesOlderRailsSelectedCheckboxNames() throws {
        let baseHTML = try fixture("ao3_creatorships")

        for checkboxName in ["[selected][]", "creatorship[selected][]"] {
            let olderRailsHTML = baseHTML.replacingOccurrences(
                of: #"name="selected[]""#,
                with: "name=\"\(checkboxName)\""
            )
            let page = try AO3Client.parseCoCreatorRequests(from: olderRailsHTML, page: 1)
            #expect(page.requests.map(\.id) == [501, 502])
            #expect(page.requests.map(\.title) == ["The Weight of Water", "Chapter 3 of Salt and Static"])
        }
    }

    // MARK: - P3-7: Import link counting splits on any whitespace

    @Test func importValidationCountsLinksSeparatedBySpacesTabsAndNewlines() {
        let mixed = AO3ImportValidation.evaluate(
            urlsText: "https://example.com/1   https://example.com/2\thttps://example.com/3\nhttps://example.com/4",
            mode: .works,
            languageID: "1"
        )
        #expect(mixed.urls == [
            "https://example.com/1",
            "https://example.com/2",
            "https://example.com/3",
            "https://example.com/4"
        ])
        #expect(mixed.canImport)

        let oneLine26 = (1 ... 26).map { "https://example.com/w/\($0)" }.joined(separator: " ")
        let overWorks = AO3ImportValidation.evaluate(urlsText: oneLine26, mode: .works, languageID: "1")
        #expect(overWorks.urls.count == 26)
        #expect(overWorks.isOverLimit)
        #expect(!overWorks.canImport)

        let tabSeparated201 = (1 ... 201).map { "https://example.com/c/\($0)" }.joined(separator: "\t")
        let overChapters = AO3ImportValidation.evaluate(
            urlsText: tabSeparated201, mode: .chapters, languageID: "1"
        )
        #expect(overChapters.urls.count == 201)
        #expect(overChapters.isOverLimit)
        #expect(!overChapters.canImport)
    }

    // MARK: - P3-8 & P3-9: Demo fixture has no `pseuds_to_apply`; bulk Orphan caps at 100

    @Test func demoImportFixtureHasNoPseudsToApplyAndBulkOrphanCapsAt100Works() throws {
        let demoImportHTML = try fixture("ao3_demo_work_import_form")
        #expect(!demoImportHTML.contains("pseuds_to_apply"))
        let parsed = try AO3Client.parseImportForm(from: demoImportHTML)
        #expect(!parsed.languageOptions.isEmpty)

        #expect(EditMultipleWorksView.maxOrphanWorks == 100)
        #expect(!EditMultipleWorksView.canOrphan(workCount: 0))
        #expect(EditMultipleWorksView.canOrphan(workCount: 1))
        #expect(EditMultipleWorksView.canOrphan(workCount: 100))
        #expect(!EditMultipleWorksView.canOrphan(workCount: 101))
        #expect(EditMultipleWorksView.orphanFootnote(for: 101).contains("Orphan up to 100 works at a time"))
    }

    // MARK: - P3-10: Series Remove Me button state and parent-screen refresh signal

    @Test func seriesFormParsesCanRemoveMeAndSeriesWritesBumpLastSeriesWrite() async throws {
        let soleEdit = try AO3Client.parseSeriesForm(from: try fixture("ao3_series_edit"))
        #expect(!soleEdit.canRemoveMe)

        let cocreatedEditHTML = """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><title>Edit Series</title></head>
        <body class="logged-in"><div id="main">
        <h2 class="heading">Edit Series</h2>
        <ul class="navigation actions" role="navigation">
          <li><a href="/series/77/edit">Edit Series</a></li>
          <li><form class="button_to" method="post" action="/series/77/remove_user_creatorship">
            <input type="hidden" name="_method" value="patch">
            <input type="hidden" name="authenticity_token" value="series-remove-csrf==">
            <input type="submit" value="Remove Me As Co-Creator">
          </form></li>
        </ul>
        <form action="/series/77" method="post" class="series">
          <input type="hidden" name="authenticity_token" value="csrf-series">
          <input type="hidden" name="_method" value="patch">
          <input type="text" name="series[title]" value="Water Cycle">
        </form></div></body></html>
        """
        let cocreatedEdit = try AO3Client.parseSeriesForm(from: cocreatedEditHTML)
        #expect(cocreatedEdit.canRemoveMe)

        let auth = await makeSignedInAuth()
        #expect(auth.lastSeriesWrite == nil)

        // Sole-creator redirect leaves lastSeriesWrite untouched.
        let orphanSeriesHTML = try fixture("ao3_orphan_series")
        WritingP3StubProtocol.reset { request in
            if request.httpMethod == "GET" { return WritingP3StubProtocol.Reply(body: cocreatedEditHTML) }
            return WritingP3StubProtocol.Reply(
                status: 200,
                body: orphanSeriesHTML,
                finalURL: URL(string: "https://archiveofourown.org/orphans/new?series_id=77")
            )
        }
        await #expect(throws: AO3WorkWriteError.onlyCreator) {
            _ = try await auth.removeMeAsCoCreator(seriesID: 77, using: stubClient())
        }
        #expect(auth.lastSeriesWrite == nil)

        // Successful Remove Me bumps lastSeriesWrite so parent screens refresh.
        WritingP3StubProtocol.reset { request in
            if request.httpMethod == "GET" { return WritingP3StubProtocol.Reply(body: cocreatedEditHTML) }
            return WritingP3StubProtocol.Reply(
                body: """
                <html><body class="logged-in"><div id="main">
                <div class="flash notice">You have been removed as a creator from the series and its works.</div>
                </div></body></html>
                """
            )
        }
        _ = try await auth.removeMeAsCoCreator(seriesID: 77, using: stubClient())
        #expect(auth.lastSeriesWrite == AO3SeriesWrite(seriesID: 77, count: 1, title: nil))

        // Successful series Orphan bumps lastSeriesWrite again.
        let orphanForm = try AO3Client.parseOrphanForm(from: orphanSeriesHTML, target: .series(77))
        WritingP3StubProtocol.reset { _ in
            WritingP3StubProtocol.Reply(
                body: """
                <html><body class="logged-in"><div id="main">
                <div class="flash notice">Orphaning was successful.</div>
                </div></body></html>
                """
            )
        }
        _ = try await auth.orphan(.series(77), keepPseudCopy: false, form: orphanForm, using: stubClient())
        #expect(auth.lastSeriesWrite == AO3SeriesWrite(seriesID: 77, count: 2, title: nil))
    }
}
