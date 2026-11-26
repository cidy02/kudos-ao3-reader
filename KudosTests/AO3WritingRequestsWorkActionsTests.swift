import Foundation
import Testing
@testable import Kudos

private final class WritingWorkRequestsFixtureAnchor {}

/// Independent local URLProtocol stub for T-575 Actions 4–6 so this suite can
/// run safely alongside `AO3WritingRequestsTests` with no shared static state.
private final class WritingWorkRequestsStub: URLProtocol, @unchecked Sendable {
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

private typealias WorkStubReply = WritingWorkRequestsStub.Reply

private nonisolated func workRequestFlash(_ kind: String, _ text: String) -> String {
    """
    <html><body class="logged-in"><div id="main">
    <div class="flash \(kind)">\(text)</div>
    </div></body></html>
    """
}

/// T-575 Actions 4–6 (orphan, remove me as co-creator, import from URL) against
/// otwarchive master `452391b6` fixtures and a local URLProtocol stub.
@Suite(.serialized)
@MainActor
struct AO3WritingRequestsWorkActionsTests {

    private func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle(for: WritingWorkRequestsFixtureAnchor.self).url(forResource: name, withExtension: "html")
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
        config.protocolClasses = [WritingWorkRequestsStub.self]
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

    // MARK: - 4. Orphan

    @Test func parsesOrphanFixturesAndDetectsNotOwned() async throws {
        let workForm = try AO3Client.parseOrphanForm(
            from: try fixture("ao3_orphan_work"), target: .work(424242)
        )
        #expect(workForm.csrfToken == "orphan-work-csrf==")
        #expect(workForm.titles == ["The Weight of Water"])
        #expect(workForm.pseudOptions.map(\.value) == ["true", "false"])
        #expect(workForm.submitLabel == "Yes, I'm sure")

        let seriesForm = try AO3Client.parseOrphanForm(
            from: try fixture("ao3_orphan_series"), target: .series(77)
        )
        #expect(seriesForm.csrfToken == "orphan-series-csrf==")
        #expect(seriesForm.titles == ["Water Cycle"])
        #expect(seriesForm.pseudOptions.map(\.value) == ["true", "false"])

        let denied = workRequestFlash("error", "You don't have permission to orphan that!")
        #expect(throws: AO3WorkWriteError.notOwned) {
            _ = try AO3Client.parseOrphanForm(from: denied, target: .work(999))
        }

        let auth = await makeSignedInAuth()
        WritingWorkRequestsStub.reset { _ in WorkStubReply(body: denied) }
        await #expect(throws: AO3WorkWriteError.notOwned) {
            _ = try await auth.loadOrphanForm(.work(999), using: stubClient())
        }
    }

    @Test func orphanBodiesCoverOneWorkSeveralWorksAndSeriesWithBothUseDefaultValues() async throws {
        let auth = await makeSignedInAuth()
        let workForm = try AO3Client.parseOrphanForm(
            from: try fixture("ao3_orphan_work"), target: .work(424242)
        )
        let seriesForm = try AO3Client.parseOrphanForm(
            from: try fixture("ao3_orphan_series"), target: .series(77)
        )
        let severalHTML = try fixture("ao3_orphan_work")
            .replacingOccurrences(
                of: #"<dt>[\s\S]*?</dt>"#,
                with: #"<dt><a href="/works/11">First</a></dt><dt><a href="/works/22">Second</a></dt>"#,
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"<input type="hidden" name="work_ids[]" id="work_ids_0" value="424242" autocomplete="off">"#,
                with: """
                <input type="hidden" name="work_ids[]" id="work_ids_0" value="11" autocomplete="off">
                <input type="hidden" name="work_ids[]" id="work_ids_1" value="22" autocomplete="off">
                """
            )
        let severalForm = try AO3Client.parseOrphanForm(from: severalHTML, target: .works([11, 22]))

        WritingWorkRequestsStub.reset { _ in WorkStubReply(body: severalHTML) }
        let loaded = try await auth.loadOrphanForm(.works([11, 22]), using: stubClient())
        #expect(loaded.titles == ["First", "Second"])
        let getURL = try #require(WritingWorkRequestsStub.recorded().first?.url)
        let queryItems = URLComponents(url: getURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(queryItems == [
            URLQueryItem(name: "work_ids[]", value: "11"),
            URLQueryItem(name: "work_ids[]", value: "22")
        ])

        let cases: [(AO3OrphanTarget, AO3OrphanForm, Bool, [String: [String]])] = [
            (.work(424242), workForm, false, [
                "authenticity_token": ["orphan-work-csrf=="], "use_default": ["true"],
                "work_ids[]": ["424242"], "commit": ["Yes, I'm sure"]
            ]),
            (.work(424242), workForm, true, [
                "authenticity_token": ["orphan-work-csrf=="], "use_default": ["false"],
                "work_ids[]": ["424242"], "commit": ["Yes, I'm sure"]
            ]),
            (.works([11, 22]), severalForm, false, [
                "authenticity_token": ["orphan-work-csrf=="], "use_default": ["true"],
                "work_ids[]": ["11", "22"], "commit": ["Yes, I'm sure"]
            ]),
            (.works([11, 22]), severalForm, true, [
                "authenticity_token": ["orphan-work-csrf=="], "use_default": ["false"],
                "work_ids[]": ["11", "22"], "commit": ["Yes, I'm sure"]
            ]),
            (.series(77), seriesForm, false, [
                "authenticity_token": ["orphan-series-csrf=="], "use_default": ["true"],
                "series_id": ["77"], "commit": ["Yes, I'm sure"]
            ]),
            (.series(77), seriesForm, true, [
                "authenticity_token": ["orphan-series-csrf=="], "use_default": ["false"],
                "series_id": ["77"], "commit": ["Yes, I'm sure"]
            ])
        ]

        for (target, form, keepPseud, expected) in cases {
            WritingWorkRequestsStub.reset { _ in
                WorkStubReply(body: workRequestFlash("notice", "Orphaning was successful."))
            }
            let notice = try await auth.orphan(target, keepPseudCopy: keepPseud, form: form, using: stubClient())
            #expect(notice == "Orphaning was successful.")
            let hits = WritingWorkRequestsStub.recorded()
            #expect(hits.count == 1)
            #expect(hits[0].method == "POST")
            #expect(hits[0].url.absoluteString == "https://archiveofourown.org/orphans")
            let fields = formFields(hits[0].body)
            #expect(fields == expected)
            #expect(fields["pseud_id"] == nil)
        }
    }

    // MARK: - 5. Remove me as co-creator

    @Test func workFormParsesCanRemoveMeAndCanOrphanFlags() throws {
        let cocreated = try AO3Client.parseWorkForm(from: try fixture("ao3_work_edit_cocreated"))
        #expect(cocreated.canRemoveMe)
        #expect(cocreated.canOrphan)
        #expect(cocreated.workID == 424242)

        let draft = try AO3Client.parseWorkForm(from: try fixture("ao3_work_new_draft"))
        #expect(!draft.canRemoveMe)
        #expect(!draft.canOrphan)
    }

    @Test func removeMeAsCoCreatorPostsPatchAndDetectsOnlyCreator() async throws {
        let auth = await makeSignedInAuth()
        let cocreatedHTML = try fixture("ao3_work_edit_cocreated")
        let soleCreatorWorkHTML = try fixture("ao3_work_edit")
        let orphanWorkHTML = try fixture("ao3_orphan_work")
        let orphanSeriesHTML = try fixture("ao3_orphan_series")

        // Work success.
        WritingWorkRequestsStub.reset { request in
            if request.httpMethod == "GET" { return WorkStubReply(body: cocreatedHTML) }
            return WorkStubReply(
                body: workRequestFlash("notice", "You have been removed as a creator from the work.")
            )
        }
        let workNotice = try await auth.removeMeAsCoCreator(workID: 424242, using: stubClient())
        #expect(workNotice == "You have been removed as a creator from the work.")
        let workHits = WritingWorkRequestsStub.recorded()
        #expect(workHits.map(\.method) == ["GET", "POST"])
        #expect(workHits[0].url.absoluteString == "https://archiveofourown.org/works/424242/edit")
        #expect(workHits[1].url.absoluteString == "https://archiveofourown.org/works/424242/remove_user_creatorship")
        #expect(formFields(workHits[1].body) == [
            "_method": ["patch"], "authenticity_token": ["remove-me-button-csrf=="]
        ])

        // Sole creator detected before POST when edit page omits the Remove Me button.
        WritingWorkRequestsStub.reset { _ in WorkStubReply(body: soleCreatorWorkHTML) }
        await #expect(throws: AO3WorkWriteError.onlyCreator) {
            _ = try await auth.removeMeAsCoCreator(workID: 424242, using: stubClient())
        }
        #expect(WritingWorkRequestsStub.recorded().map(\.method) == ["GET"])

        // Sole creator detected on AO3 redirect to /orphans/new?work_id=...; nothing else sent.
        WritingWorkRequestsStub.reset { request in
            if request.httpMethod == "GET" { return WorkStubReply(body: cocreatedHTML) }
            return WorkStubReply(
                status: 200,
                body: orphanWorkHTML,
                finalURL: URL(string: "https://archiveofourown.org/orphans/new?work_id=424242")
            )
        }
        await #expect(throws: AO3WorkWriteError.onlyCreator) {
            _ = try await auth.removeMeAsCoCreator(workID: 424242, using: stubClient())
        }
        #expect(WritingWorkRequestsStub.recorded().map { "\($0.method) \($0.url.path)" } == [
            "GET /works/424242/edit", "POST /works/424242/remove_user_creatorship"
        ])

        // Series success + series only-creator redirect.
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
        WritingWorkRequestsStub.reset { request in
            if request.httpMethod == "GET" { return WorkStubReply(body: seriesPage) }
            return WorkStubReply(
                body: workRequestFlash("notice", "You have been removed as a creator from the series and its works.")
            )
        }
        let seriesNotice = try await auth.removeMeAsCoCreator(seriesID: 77, using: stubClient())
        #expect(seriesNotice == "You have been removed as a creator from the series and its works.")
        let seriesPost = try #require(WritingWorkRequestsStub.recorded().last)
        #expect(seriesPost.url.absoluteString == "https://archiveofourown.org/series/77/remove_user_creatorship")
        #expect(formFields(seriesPost.body) == [
            "_method": ["patch"], "authenticity_token": ["series-remove-csrf=="]
        ])

        WritingWorkRequestsStub.reset { request in
            if request.httpMethod == "GET" { return WorkStubReply(body: seriesPage) }
            return WorkStubReply(
                status: 302,
                body: orphanSeriesHTML,
                headers: ["Location": "/orphans/new?series_id=77"]
            )
        }
        await #expect(throws: AO3WorkWriteError.onlyCreator) {
            _ = try await auth.removeMeAsCoCreator(seriesID: 77, using: stubClient())
        }
        #expect(WritingWorkRequestsStub.recorded().count == 2)
    }

    // MARK: - 6. Import from a URL

    @Test func parsesImportFormFixture() throws {
        let form = try AO3Client.parseImportForm(from: try fixture("ao3_work_import_form"))
        #expect(form.actionURL.absoluteString == "https://archiveofourown.org/works/import")
        #expect(form.csrfToken == "import-form-csrf==")
        #expect(form.languageOptions.map(\.value) == ["", "1", "2", "3"])
        #expect(form.encodingOptions.map(\.value) == ["", "ISO-8859-1", "UTF-8", "Windows-1252"])
        #expect(form.ratingOptions.map(\.value).contains("Teen And Up Audiences"))
        #expect(form.warningOptions.map(\.value) == [
            "Choose Not To Use Archive Warnings", "No Archive Warnings Apply"
        ])
        #expect(form.categoryOptions.map(\.value) == ["F/F", "Gen", "M/M"])
        #expect(form.defaultCommentPermissions == "disable_anon")
    }

    @Test func importBodySendsSingleWorkKeysOmitsEmptyArraysAndNeverArchivistFields() throws {
        let archivistKeys = [
            "importing_for_others", "external_author_name", "external_author_email",
            "external_coauthor_name", "external_coauthor_email"
        ]
        // Single-value `work[...]` keys ensure `params[:work]` exists; warning and
        // category checkboxes (`include_hidden: !include_blank`, `include_blank: true`
        // in `_work_form_tags.html.erb:39,74`) are omitted by browsers when unchecked.
        let requiredSingleWorkKeys = [
            "work[rating_string]", "work[fandom_string]",
            "work[relationship_string]", "work[character_string]", "work[freeform_string]"
        ]

        let basic = AO3ImportRequest(
            urls: ["https://example.com/story-1", "https://example.com/story-2"],
            languageID: "1"
        )
        let basicFields = formFields(String(decoding: AO3AuthService.formEncoded(
            basic.parameters(csrfToken: "tok")
        ), as: UTF8.self))
        for key in requiredSingleWorkKeys { #expect(basicFields[key] == [""], "Expected blank key \(key)") }
        #expect(basicFields["work[archive_warning_strings][]"] == nil)
        #expect(basicFields["work[category_strings][]"] == nil)
        for key in archivistKeys { #expect(basicFields[key] == nil, "Must never send archivist key \(key)") }
        #expect(basicFields["urls"] == ["https://example.com/story-1\nhttps://example.com/story-2"])
        #expect(basicFields["import_multiple"] == ["works"])
        #expect(basicFields["language_id"] == ["1"])
        #expect(basicFields["encoding"] == [""])
        #expect(basicFields["pseuds_to_apply"] == nil)
        #expect(basicFields["detect_tags"] == ["true"])
        #expect(basicFields["override_tags"] == nil)
        #expect(basicFields["post_without_preview"] == nil)
        #expect(basicFields["restricted"] == nil)
        #expect(basicFields["moderated_commenting_enabled"] == nil)
        #expect(basicFields["comment_permissions"] == ["disable_anon"])

        // Override mode with no warnings/categories chosen still omits both array keys
        // and keeps AO3's default `detect_tags=true` (`new_import.html.erb:109`).
        let overrideEmptyArrays = AO3ImportRequest(
            urls: ["https://example.com/story-1"],
            languageID: "1",
            overrideTags: true,
            tags: AO3WorkTagSet(rating: "General Audiences", fandoms: ["Original Work"])
        )
        let overrideEmptyFields = formFields(String(decoding: AO3AuthService.formEncoded(
            overrideEmptyArrays.parameters(csrfToken: "tok")
        ), as: UTF8.self))
        #expect(overrideEmptyFields["work[archive_warning_strings][]"] == nil)
        #expect(overrideEmptyFields["work[category_strings][]"] == nil)
        #expect(overrideEmptyFields["detect_tags"] == ["true"])
        #expect(overrideEmptyFields["pseuds_to_apply"] == nil)
        #expect(overrideEmptyFields["work[rating_string]"] == ["General Audiences"])
        #expect(overrideEmptyFields["work[fandom_string]"] == ["Original Work"])

        let override = AO3ImportRequest(
            urls: ["https://example.com/ch1", "https://example.com/ch2"],
            importMultiple: .chapters,
            languageID: "1",
            encoding: "UTF-8",
            postWithoutPreview: true,
            restricted: true,
            commentPermissions: "enable_all",
            moderatedCommenting: true,
            overrideTags: true,
            tags: AO3WorkTagSet(
                rating: "Mature",
                warnings: ["No Archive Warnings Apply"],
                categories: ["F/F", "Gen"],
                fandoms: ["Original Work"],
                relationships: ["A/B"],
                characters: ["A", "B"],
                additionalTags: ["Fluff"]
            ),
            notes: "Imported from blog."
        )
        let overrideFields = formFields(String(decoding: AO3AuthService.formEncoded(
            override.parameters(csrfToken: "tok")
        ), as: UTF8.self))
        for key in archivistKeys { #expect(overrideFields[key] == nil) }
        #expect(overrideFields["pseuds_to_apply"] == nil)
        #expect(overrideFields["import_multiple"] == ["chapters"])
        #expect(overrideFields["encoding"] == ["UTF-8"])
        #expect(overrideFields["post_without_preview"] == ["1"])
        #expect(overrideFields["restricted"] == ["1"])
        #expect(overrideFields["moderated_commenting_enabled"] == ["1"])
        #expect(overrideFields["comment_permissions"] == ["enable_all"])
        #expect(overrideFields["override_tags"] == ["1"])
        #expect(overrideFields["detect_tags"] == ["true"])
        #expect(overrideFields["work[rating_string]"] == ["Mature"])
        #expect(overrideFields["work[archive_warning_strings][]"] == ["No Archive Warnings Apply"])
        #expect(overrideFields["work[category_strings][]"] == ["F/F", "Gen"])
        #expect(overrideFields["work[fandom_string]"] == ["Original Work"])
        #expect(overrideFields["work[relationship_string]"] == ["A/B"])
        #expect(overrideFields["work[character_string]"] == ["A, B"])
        #expect(overrideFields["work[freeform_string]"] == ["Fluff"])
        #expect(overrideFields["notes"] == ["Imported from blog."])
    }

    @Test func importWorksClassifiesDraftPostedSeveralAndFailedResults() async throws {
        let auth = await makeSignedInAuth()
        let formHTML = try fixture("ao3_work_import_form")
        let severalHTML = try fixture("ao3_work_import_several")
        let failedHTML = try fixture("ao3_work_import_failed")

        WritingWorkRequestsStub.reset { _ in WorkStubReply(body: formHTML) }
        let form = try await auth.loadImportForm(using: stubClient())
        #expect(
            WritingWorkRequestsStub.recorded().first?.url.absoluteString
                == "https://archiveofourown.org/works/new?import=true"
        )

        let request = AO3ImportRequest(urls: ["https://example.com/story"], languageID: "1")

        // Single draft redirect -> /works/:id/preview.
        WritingWorkRequestsStub.reset { _ in
            WorkStubReply(
                status: 200,
                body: "<html><body><div id=\"main\"><div id=\"previewpane\"></div></div></body></html>",
                finalURL: URL(string: "https://archiveofourown.org/works/7001/preview")
            )
        }
        #expect(try await auth.importWorks(request, form: form, using: stubClient()) == .draft(7001))
        let postHit = try #require(WritingWorkRequestsStub.recorded().first)
        #expect(postHit.method == "POST")
        #expect(postHit.url.absoluteString == "https://archiveofourown.org/works/import")

        // Single posted redirect -> /works/:id.
        WritingWorkRequestsStub.reset { _ in
            WorkStubReply(
                status: 200,
                body: "<html><body><div id=\"main\"></div></body></html>",
                finalURL: URL(string: "https://archiveofourown.org/works/7002")
            )
        }
        #expect(try await auth.importWorks(request, form: form, using: stubClient()) == .posted(7002))

        // Several works imported -> renders import page with notice + work links.
        WritingWorkRequestsStub.reset { _ in
            WorkStubReply(
                status: 200,
                body: severalHTML,
                finalURL: URL(string: "https://archiveofourown.org/works/import")
            )
        }
        #expect(
            try await auth.importWorks(request, form: form, using: stubClient())
                == .several([7001, 7002], failures: nil)
        )

        // Failure -> re-renders form with error flash.
        WritingWorkRequestsStub.reset { _ in
            WorkStubReply(
                status: 200,
                body: failedHTML,
                finalURL: URL(string: "https://archiveofourown.org/works/import")
            )
        }
        let expectedError = "We couldn't successfully import that work, sorry: "
            + "Story could not be downloaded from https://example.com/missing."
        #expect(try await auth.importWorks(request, form: form, using: stubClient()) == .failed(expectedError))
    }

    @Test func newWriteErrorsProvidePlainUserFacingDescriptions() {
        #expect(AO3WorkWriteError.stateChanged.errorDescription?.isEmpty == false)
        #expect(AO3WorkWriteError.onlyCreator.errorDescription?.isEmpty == false)
        #expect(AO3WorkWriteError.notOwned.errorDescription?.isEmpty == false)
        #expect(AO3WorkWriteError.rejected("AO3 error").errorDescription == "AO3 error")
    }
}
