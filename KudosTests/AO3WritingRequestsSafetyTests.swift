import Foundation
import Testing
@testable import Kudos

private final class SafetyFlowFixtureAnchor {}

/// Local URLProtocol stub for P1-1 / P2-2 safety flow tests. Nothing reaches AO3.
private final class SafetyFlowStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated struct Hit: Sendable {
        var method: String
        var url: URL
        var cookieHeader: String?
    }

    nonisolated enum Action: Sendable {
        case respond(status: Int = 200, body: String = "", headers: [String: String]? = nil)
        case fail(URLError.Code)
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
        let hit = Hit(
            method: request.httpMethod ?? "GET",
            url: url,
            cookieHeader: request.value(forHTTPHeaderField: "Cookie")
        )
        Self.lock.lock()
        Self.hits.append(hit)
        let index = Self.hits.count
        let responder = Self.handler
        Self.lock.unlock()

        switch responder?(request, index) ?? .respond() {
        case let .respond(status, body, headers):
            guard let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case let .fail(code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}
}

/// Honest tests for T-575 Part 3a P1-1 (series copy enumeration), P1-2 (mid-copy
/// cancellation), and P2-2 (post-send ambiguous write outcomes & Import gating).
@Suite(.serialized)
@MainActor
struct AO3WritingRequestsSafetyTests {

    private func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle(for: SafetyFlowFixtureAnchor.self).url(forResource: name, withExtension: "html")
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
        config.protocolClasses = [SafetyFlowStubProtocol.self]
        return AO3Client(session: URLSession(configuration: config), paceSleep: { _ in })
    }

    private func makeOrphanForm(target: AO3OrphanTarget, titles: [String]) -> AO3OrphanForm {
        AO3OrphanForm(
            target: target,
            actionURL: AO3Client.orphansCreateURL(),
            csrfToken: "orphan-csrf==",
            titles: titles,
            pseudOptions: [
                AO3FormOption(value: "true", title: "Take my pseud off as well"),
                AO3FormOption(value: "false", title: "Leave a copy of my pseud on")
            ],
            cautionTexts: [],
            submitLabel: "Yes, I'm sure"
        )
    }

    private func makeImportForm() -> AO3ImportForm {
        AO3ImportForm(
            actionURL: AO3Client.importWorkURL(),
            csrfToken: "import-csrf==",
            languageOptions: [AO3FormOption(value: "1", title: "English")],
            selectedLanguageID: "1",
            encodingOptions: [],
            ratingOptions: [],
            warningOptions: [],
            categoryOptions: [],
            commentPermissionOptions: [],
            defaultCommentPermissions: "disable_anon"
        )
    }

    // MARK: - P1-1: Series copy enumerates every work (including restricted) and fails closed on gaps

    @Test func seriesCopyIncludesRestrictedWorkOmittedFromAnonymousPageAndAbortsOnSaveFailure() async throws {
        let auth = await makeSignedInAuth()
        let manageHTML = try fixture("ao3_series_manage_with_restricted")
        let anonymousShowHTML = try fixture("ao3_series_show_anonymous")
        let signedInShowHTML = try fixture("ao3_series_show_signed_in")

        // Positive control: the anonymous series page omits restricted work 502.
        let anonymousWorks = try AO3Client.parseSearchPage(anonymousShowHTML, page: 1).works
        #expect(anonymousWorks.map(\.id) == [501])

        // Signed-in requests receive the full page; anonymous requests get the truncated page.
        SafetyFlowStubProtocol.reset { request, _ in
            let hasCookie = (request.value(forHTTPHeaderField: "Cookie") ?? "").isEmpty == false
            if request.url?.path == "/series/77/manage" {
                return .respond(status: hasCookie ? 200 : 302, body: manageHTML)
            }
            if request.url?.path == "/series/77" {
                return .respond(body: hasCookie ? signedInShowHTML : anonymousShowHTML)
            }
            return .respond(status: 404, body: "")
        }

        let client = stubClient()
        let form = makeOrphanForm(target: .series(77), titles: ["Water Cycle"])
        let items = try await OrphanSubmissionFlow.resolveCopyItems(
            for: .series(77),
            form: form,
            auth: auth,
            using: client
        )
        #expect(items == [
            OrphanSubmissionFlow.WorkCopyItem(workID: 501, title: "Open Skies"),
            OrphanSubmissionFlow.WorkCopyItem(workID: 502, title: "Locked Vault")
        ])
        let hits = SafetyFlowStubProtocol.recorded()
        #expect(hits.map(\.url.path) == ["/series/77/manage", "/series/77"])
        #expect(hits.allSatisfy { ($0.cookieHeader ?? "").isEmpty == false })

        // Failure to save restricted work 502 must abort with copyFailed and send ZERO orphan requests.
        var copiedIDs: [Int] = []
        var orphanCalls = 0
        let outcome = await OrphanSubmissionFlow.run(
            target: .series(77),
            keepPseudCopy: false,
            keepLocalCopy: true,
            finalAlertDecision: .confirmed,
            form: form,
            resolveWorks: {
                try await OrphanSubmissionFlow.resolveCopyItems(
                    for: .series(77), form: form, auth: auth, using: client
                )
            },
            copyWork: { workID in
                copiedIDs.append(workID)
                if workID == 502 { throw AO3Error.network("Timed out") }
            },
            submitOrphan: { _, _, _ in
                orphanCalls += 1
                return "Orphaning was successful."
            }
        )
        #expect(copiedIDs == [501, 502])
        #expect(orphanCalls == 0)
        if case let .copyFailed(workTitle, _) = outcome {
            #expect(workTitle == "Locked Vault")
        } else {
            Issue.record("Expected copyFailed for Locked Vault, got \(outcome)")
        }
    }

    @Test func seriesCopyFailsClosedWhenManageListsDraftOrUnenumerableWork() async throws {
        let auth = await makeSignedInAuth()
        let form = makeOrphanForm(target: .series(77), titles: ["Water Cycle"])

        // 1. Draft in manage page: AO3 refuses downloading drafts, so nothing is orphaned.
        let manageWithDraft = try fixture("ao3_series_manage_with_restricted").replacingOccurrences(
            of: "<h3 class=\"heading\">Locked Vault</h3>",
            with: "<h3 class=\"heading\">Unposted Epilogue (DRAFT)</h3>"
        )
        SafetyFlowStubProtocol.reset { request, _ in
            if request.url?.path == "/series/77/manage" { return .respond(body: manageWithDraft) }
            return .respond(status: 500, body: "")
        }
        var orphanCalls = 0
        let draftOutcome = await OrphanSubmissionFlow.run(
            target: .series(77),
            keepPseudCopy: false,
            keepLocalCopy: true,
            finalAlertDecision: .confirmed,
            form: form,
            resolveWorks: {
                try await OrphanSubmissionFlow.resolveCopyItems(
                    for: .series(77), form: form, auth: auth, using: stubClient()
                )
            },
            copyWork: { _ in Issue.record("Must not copy any work when a draft blocks enumeration") },
            submitOrphan: { _, _, _ in
                orphanCalls += 1
                return "Orphaning was successful."
            }
        )
        #expect(orphanCalls == 0)
        if case let .copyFailed(workTitle, _) = draftOutcome {
            #expect(workTitle == "Unposted Epilogue (DRAFT)")
        } else {
            Issue.record("Expected copyFailed for draft, got \(draftOutcome)")
        }

        // 2. Manage lists a non-draft work missing from signed-in /series/:id: fail closed.
        let manageWithExtra = try fixture("ao3_series_manage_with_restricted")
        let truncatedShow = try fixture("ao3_series_show_anonymous")
            .replacingOccurrences(of: "<body>", with: "<body class=\"logged-in\">")
        SafetyFlowStubProtocol.reset { request, _ in
            if request.url?.path == "/series/77/manage" { return .respond(body: manageWithExtra) }
            return .respond(body: truncatedShow)
        }
        let missingOutcome = await OrphanSubmissionFlow.run(
            target: .series(77),
            keepPseudCopy: false,
            keepLocalCopy: true,
            finalAlertDecision: .confirmed,
            form: form,
            resolveWorks: {
                try await OrphanSubmissionFlow.resolveCopyItems(
                    for: .series(77), form: form, auth: auth, using: stubClient()
                )
            },
            copyWork: { _ in Issue.record("Must not copy partial series") },
            submitOrphan: { _, _, _ in
                orphanCalls += 1
                return "Orphaning was successful."
            }
        )
        #expect(orphanCalls == 0)
        if case let .copyFailed(workTitle, _) = missingOutcome {
            #expect(workTitle == "Locked Vault")
        } else {
            Issue.record("Expected copyFailed for unenumerable work, got \(missingOutcome)")
        }
    }

    // MARK: - P1-2: Cancelling mid-copy stops the orphan flow completely

    @Test func orphanFlowCancelsDuringCopyStepAndSendsZeroOrphanRequests() async {
        let form = makeOrphanForm(target: .works([101, 102]), titles: ["First", "Second"])
        var copiedIDs: [Int] = []
        var orphanCalls = 0
        var copyStarted = false
        var shouldReleaseCopy = false
        var copyStartedWaiter: CheckedContinuation<Void, Never>?
        var releaseCopyWaiter: CheckedContinuation<Void, Never>?

        let task = Task {
            await OrphanSubmissionFlow.run(
                target: .works([101, 102]),
                keepPseudCopy: false,
                keepLocalCopy: true,
                finalAlertDecision: .confirmed,
                form: form,
                resolveWorks: {
                    [
                        OrphanSubmissionFlow.WorkCopyItem(workID: 101, title: "First"),
                        OrphanSubmissionFlow.WorkCopyItem(workID: 102, title: "Second")
                    ]
                },
                copyWork: { workID in
                    copiedIDs.append(workID)
                    if workID == 101 {
                        copyStarted = true
                        copyStartedWaiter?.resume()
                        copyStartedWaiter = nil
                        if !shouldReleaseCopy {
                            await withCheckedContinuation { continuation in
                                if shouldReleaseCopy {
                                    continuation.resume()
                                } else {
                                    releaseCopyWaiter = continuation
                                }
                            }
                        }
                    }
                },
                submitOrphan: { _, _, _ in
                    orphanCalls += 1
                    return "Orphaning was successful."
                }
            )
        }

        if !copyStarted {
            await withCheckedContinuation { continuation in
                if copyStarted {
                    continuation.resume()
                } else {
                    copyStartedWaiter = continuation
                }
            }
        }
        task.cancel()
        shouldReleaseCopy = true
        releaseCopyWaiter?.resume()
        releaseCopyWaiter = nil

        let outcome = await task.value
        #expect(outcome == .cancelled)
        #expect(copiedIDs == [101])
        #expect(orphanCalls == 0)
    }

    // MARK: - P2-2: Post-send errors become "may have gone through" and gate Import

    @Test func importAndOrphanMapPostSendErrorsToMayHaveGoneThroughAndGateRetry() async {
        let auth = await makeSignedInAuth()
        let importForm = makeImportForm()
        let importRequest = AO3ImportRequest(urls: ["https://example.com/story"], languageID: "1")
        let validVerdict = AO3ImportValidation.evaluate(
            urlsText: "https://example.com/story", mode: .works, languageID: "1"
        )

        // Post-send timeout via real URLProtocol -> mayHaveGoneThrough.
        SafetyFlowStubProtocol.reset { _, _ in .fail(.timedOut) }
        let timedOutImport = await AO3ImportSubmissionFlow.run(
            request: importRequest,
            form: importForm,
            submit: { req, form in try await auth.importWorks(req, form: form, using: stubClient()) }
        )
        #expect(timedOutImport == .mayHaveGoneThrough(AO3ImportSubmissionFlow.mayHaveGoneThroughMessage))
        if case let .mayHaveGoneThrough(message) = timedOutImport {
            #expect(message == "This may have gone through on AO3. Check Drafts before trying again.")
            // Import stays disabled until the user dismisses the ambiguous-outcome message.
            #expect(!AO3ImportSubmissionFlow.canSubmit(
                verdict: validVerdict, isSubmitting: false, ambiguousOutcomeMessage: message
            ))
            #expect(AO3ImportSubmissionFlow.canSubmit(
                verdict: validVerdict, isSubmitting: false, ambiguousOutcomeMessage: nil
            ))
        }

        // Gateway 504 after POST -> unconfirmed -> mayHaveGoneThrough.
        SafetyFlowStubProtocol.reset { _, _ in .respond(status: 504, body: "<html><body>504</body></html>") }
        let gatewayTimeoutImport = await AO3ImportSubmissionFlow.run(
            request: importRequest,
            form: importForm,
            submit: { req, form in try await auth.importWorks(req, form: form, using: stubClient()) }
        )
        #expect(gatewayTimeoutImport == .mayHaveGoneThrough(AO3ImportSubmissionFlow.mayHaveGoneThroughMessage))

        // Dropped connection -> mayHaveGoneThrough; offline -> failed (not ambiguous).
        let droppedImport = await AO3ImportSubmissionFlow.run(
            request: importRequest,
            form: importForm,
            submit: { _, _ in throw URLError(.networkConnectionLost) }
        )
        #expect(droppedImport == .mayHaveGoneThrough(AO3ImportSubmissionFlow.mayHaveGoneThroughMessage))

        let offlineImport = await AO3ImportSubmissionFlow.run(
            request: importRequest,
            form: importForm,
            submit: { _, _ in throw URLError(.notConnectedToInternet) }
        )
        guard case .failed = offlineImport else {
            Issue.record("Expected failed for offline pre-send error, got \(offlineImport)")
            return
        }

        // Orphan: post-send timeout -> mayHaveGoneThrough with orphan-specific wording.
        let orphanForm = makeOrphanForm(target: .work(424242), titles: ["The Weight of Water"])
        SafetyFlowStubProtocol.reset { _, _ in .fail(.timedOut) }
        let timedOutOrphan = await OrphanSubmissionFlow.run(
            target: .work(424242),
            keepPseudCopy: false,
            keepLocalCopy: false,
            finalAlertDecision: .confirmed,
            form: orphanForm,
            resolveWorks: { [] },
            copyWork: { _ in },
            submitOrphan: { target, keepPseud, form in
                try await auth.orphan(target, keepPseudCopy: keepPseud, form: form, using: stubClient())
            }
        )
        #expect(timedOutOrphan == .mayHaveGoneThrough(OrphanSubmissionFlow.mayHaveGoneThroughMessage))
        if case let .mayHaveGoneThrough(message) = timedOutOrphan {
            #expect(message.contains("Check your works on AO3 before trying again."))
        }

        // Orphan: maintenance (edge answer, never reached AO3) -> failed, not mayHaveGoneThrough.
        let maintenanceOrphan = await OrphanSubmissionFlow.run(
            target: .work(424242),
            keepPseudCopy: false,
            keepLocalCopy: false,
            finalAlertDecision: .confirmed,
            form: orphanForm,
            resolveWorks: { [] },
            copyWork: { _ in },
            submitOrphan: { _, _, _ in throw AO3Error.maintenance }
        )
        guard case .failed = maintenanceOrphan else {
            Issue.record("Expected failed for maintenance, got \(maintenanceOrphan)")
            return
        }
    }
}
