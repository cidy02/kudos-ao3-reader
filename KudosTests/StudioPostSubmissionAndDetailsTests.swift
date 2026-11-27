import Foundation
import Testing
@testable import Kudos

// MARK: - Local-only URLProtocol stub for Studio S5 posting tests (never contacts AO3)

private final class StudioPostURLStub: URLProtocol, @unchecked Sendable {
    nonisolated struct Hit: Sendable {
        var method: String
        var path: String
        var body: String
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var hits: [Hit] = []
    nonisolated(unsafe) private static var responder: (@Sendable (URLRequest) -> (status: Int, body: String))?

    static func reset(_ handler: @escaping @Sendable (URLRequest) -> (status: Int, body: String)) {
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
        let body = Self.bodyText(of: request)
        let hit = Hit(method: request.httpMethod ?? "GET", path: url.path, body: body)
        Self.lock.lock()
        Self.hits.append(hit)
        let handler = Self.responder
        Self.lock.unlock()

        guard let reply = handler?(request),
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: reply.status,
                  httpVersion: "HTTP/1.1",
                  headerFields: nil
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

private nonisolated func studioPostFlashHTML(_ text: String) -> String {
    """
    <html><body class="logged-in"><div id="main">
    <div class="flash notice">\(text)</div>
    </div></body></html>
    """
}

private nonisolated func parseStudioFormFields(_ body: String) -> [String: [String]] {
    var result: [String: [String]] = [:]
    for pair in body.split(separator: "&") {
        let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
        let key = parts[0].replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? parts[0]
        let rawVal = parts.count > 1 ? parts[1] : ""
        let value = rawVal.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? rawVal
        result[key, default: []].append(value)
    }
    return result
}

// MARK: - 3. Edit Posted changes summary & diff (`Studio-Edit-Posted`)

@MainActor
struct StudioEditPostedDiffTests {
    @Test func identicalSnapshotsReportNoChangesForBothBaselineSources() {
        let snap = StudioPostedChapterSnapshot(
            title: "Spring Tide",
            summary: "",
            notesBefore: "<p>Note</p>",
            notesAfter: "",
            bodyHTML: "<p>The pier held.</p>"
        )

        let fromAO3 = StudioPostedChapterDiff.compare(posted: snap, current: snap, baselineSource: .loadedFromAO3)
        #expect(!fromAO3.hasAnyChanges)
        #expect(fromAO3.paragraphsChanged == 0)
        #expect(fromAO3.wordDelta == 0)
        #expect(fromAO3.summaryLine == "No changes since posted")

        let fromSession = StudioPostedChapterDiff.compare(
            posted: snap,
            current: snap,
            baselineSource: .editorSessionStart
        )
        #expect(!fromSession.hasAnyChanges)
        #expect(fromSession.summaryLine == "No local changes since opening")
    }

    @Test func modifiedMiddleParagraphComputesParagraphCountWordDeltaAndReconstructsBothVersions() {
        let oldMid = "Her father did not come down to watch. He stood at the top of the slipway."
        let newMid = "Her father came down to watch, which was much worse for everyone. "
            + "He stood at the top of the slipway."
        let posted = StudioPostedChapterSnapshot(
            title: "Spring Tide",
            summary: "",
            notesBefore: "",
            notesAfter: "",
            bodyHTML: """
            <p>Everyone in the village said the spring tide would take the old pier.</p>
            <p>\(oldMid)</p>
            <p>When the water went out again the pier was still there.</p>
            """
        )
        let current = StudioPostedChapterSnapshot(
            title: "Spring Tide",
            summary: "",
            notesBefore: "",
            notesAfter: "",
            bodyHTML: """
            <p>Everyone in the village said the spring tide would take the old pier.</p>
            <p>\(newMid)</p>
            <p>When the water went out again the pier was still there.</p>
            """
        )

        let diff = StudioPostedChapterDiff.compare(posted: posted, current: current)
        #expect(diff.hasAnyChanges)
        #expect(diff.paragraphsChanged == 1)
        #expect(diff.wordDelta == 4)
        #expect(!diff.titleChanged)
        #expect(!diff.notesChanged)
        #expect(diff.summaryLine == "1 paragraph changed · +4 words · notes and title unchanged")
        #expect(diff.paragraphs.count == 3)
        #expect(diff.paragraphs[0].kind == .unchanged)
        #expect(diff.paragraphs[1].kind == .modified)
        #expect(diff.paragraphs[2].kind == .unchanged)

        // Verify the diff spans reconstruct both versions without pinning boundary splits (T1).
        let modifiedSpans = diff.paragraphs[1].spans
        let reconstructedPosted = modifiedSpans
            .filter { $0.kind != .inserted }
            .map(\.text)
            .joined()
        let reconstructedCurrent = modifiedSpans
            .filter { $0.kind != .deleted }
            .map(\.text)
            .joined()
        #expect(reconstructedPosted == oldMid)
        #expect(reconstructedCurrent == newMid)
    }

    @Test func addedDeletedParagraphsAndNegativeWordDeltaReportAccurately() {
        let posted = StudioPostedChapterSnapshot(
            title: "Ch 3",
            summary: "",
            notesBefore: "",
            notesAfter: "",
            bodyHTML: "<p>First paragraph stays.</p><p>Removed paragraph with five words.</p>"
        )
        let current = StudioPostedChapterSnapshot(
            title: "Ch 3",
            summary: "",
            notesBefore: "",
            notesAfter: "",
            bodyHTML: "<p>First paragraph stays.</p>"
        )

        let diff = StudioPostedChapterDiff.compare(posted: posted, current: current)
        #expect(diff.paragraphsChanged == 1)
        #expect(diff.wordDelta == -5)
        #expect(diff.summaryLine == "1 paragraph changed · -5 words · notes and title unchanged")
        #expect(diff.paragraphs.last?.kind == .deleted)
    }

    @Test func titleSummaryAndNotesChangesAppearInMetadataDiffsAndSummaryLine() {
        let posted = StudioPostedChapterSnapshot(
            title: "Spring Tide",
            summary: "Old summary",
            notesBefore: "Old begin",
            notesAfter: "Old end",
            bodyHTML: "<p>Unchanged body.</p>"
        )
        let titleOnly = StudioPostedChapterSnapshot(
            title: "Neap Tide",
            summary: "Old summary",
            notesBefore: "Old begin",
            notesAfter: "Old end",
            bodyHTML: "<p>Unchanged body.</p>"
        )
        let titleDiff = StudioPostedChapterDiff.compare(posted: posted, current: titleOnly)
        #expect(titleDiff.hasAnyChanges)
        #expect(titleDiff.titleChanged)
        #expect(!titleDiff.notesChanged)
        #expect(titleDiff.metadataDiffs.map(\.id) == ["title"])
        #expect(titleDiff.summaryLine == "No paragraphs changed · title changed · notes unchanged")

        let notesAndTitle = StudioPostedChapterSnapshot(
            title: "Neap Tide",
            summary: "Old summary",
            notesBefore: "New begin",
            notesAfter: "Old end",
            bodyHTML: "<p>Unchanged body.</p>"
        )
        let bothDiff = StudioPostedChapterDiff.compare(posted: posted, current: notesAndTitle)
        #expect(bothDiff.titleChanged)
        #expect(bothDiff.notesBeforeChanged)
        #expect(!bothDiff.notesAfterChanged)
        #expect(bothDiff.metadataDiffs.map(\.id) == ["title", "notesBefore"])
        #expect(bothDiff.summaryLine == "No paragraphs changed · notes and title changed")
    }

    @Test func smartQuotesDoNotTriggerSpuriousParagraphDiff() {
        let posted = StudioPostedChapterSnapshot(
            title: "",
            summary: "",
            notesBefore: "",
            notesAfter: "",
            bodyHTML: "<p>\"Don't go,\" she said.</p>"
        )
        let current = StudioPostedChapterSnapshot(
            title: "",
            summary: "",
            notesBefore: "",
            notesAfter: "",
            bodyHTML: "<p>“Don’t go,” she said.</p>"
        )
        let diff = StudioPostedChapterDiff.compare(posted: posted, current: current)
        #expect(diff.paragraphsChanged == 0)
        #expect(!diff.hasAnyChanges)
    }

    @Test func cjkParagraphDiffReconstructsBothStrings() {
        let posted = StudioPostedChapterSnapshot(
            title: "",
            summary: "",
            notesBefore: "",
            notesAfter: "",
            bodyHTML: "<p>潮が引いたあと桟橋が残った。</p>"
        )
        let current = StudioPostedChapterSnapshot(
            title: "",
            summary: "",
            notesBefore: "",
            notesAfter: "",
            bodyHTML: "<p>潮が静かに引いたあと古い桟橋が残った。</p>"
        )
        let diff = StudioPostedChapterDiff.compare(posted: posted, current: current)
        #expect(diff.paragraphsChanged == 1)
        #expect(diff.wordDelta > 0)
        let spans = diff.paragraphs[0].spans
        #expect(spans.filter { $0.kind != .inserted }.map(\.text).joined() == "潮が引いたあと桟橋が残った。")
        #expect(spans.filter { $0.kind != .deleted }.map(\.text).joined() == "潮が静かに引いたあと古い桟橋が残った。")
    }
}

// MARK: - 4. Work Details order & sole-creator vs co-creator gating (`Studio-Work-Details`)

@MainActor
struct StudioWorkDetailsModelTests {
    @Test func sectionsAndRowsFollowAO3EditPageOrder() {
        let form = StudioPostTestFixtures.makePostedWorkForm(canRemoveMe: true, canOrphan: true)
        let model = StudioWorkDetailsModel.build(form: form, username: "quietharbor")

        #expect(model.sectionOrder == [
            .about,
            .tags,
            .creators,
            .connections,
            .whoCanSeeAndComment,
            .giveUpOrDelete
        ])

        #expect(model.section(.about)?.rows.map(\.id) == [.title, .summary, .notes, .language])
        #expect(model.section(.tags)?.rows.map(\.id) == [.editTags])
        #expect(model.section(.connections)?.rows.map(\.id) == [.series, .collections, .giftFor, .inspiredBy])
        #expect(model.section(.whoCanSeeAndComment)?.rows.map(\.id) == [
            .whoCanSee,
            .whoCanComment,
            .approveComments
        ])
        #expect(model.section(.giveUpOrDelete)?.rows.map(\.id) == [.orphanWork, .deleteWork])
    }

    @Test func soleCreatorHidesRemoveMeWhileCoCreatorShowsIt() {
        let soleForm = StudioPostTestFixtures.makePostedWorkForm(canRemoveMe: false, canOrphan: true)
        let soleCreators = StudioWorkDetailsModel.build(form: soleForm, username: "quietharbor")
            .section(.creators)
        #expect(soleCreators?.rows.map(\.id) == [.creatorPseud("quietharbor"), .inviteCoCreator])
        #expect(soleCreators?.rows.contains { $0.id == .removeMeAsCoCreator } == false)

        let coForm = StudioPostTestFixtures.makePostedWorkForm(canRemoveMe: true, canOrphan: true)
        let coCreators = StudioWorkDetailsModel.build(form: coForm, username: "quietharbor")
            .section(.creators)
        #expect(coCreators?.rows.map(\.id) == [
            .creatorPseud("quietharbor"),
            .inviteCoCreator,
            .removeMeAsCoCreator
        ])
        let removeRow = coCreators?.rows.first { $0.id == .removeMeAsCoCreator }
        #expect(removeRow?.tone == .destructive)
    }

    @Test func draftWorkHidesOrphanAndLabelsDeleteDraft() {
        var draftForm = StudioPostTestFixtures.makePostedWorkForm(canRemoveMe: false, canOrphan: false)
        draftForm.kind = .draft
        draftForm.isDraft = true
        draftForm.isPosted = false

        let danger = StudioWorkDetailsModel.build(form: draftForm, username: "quietharbor")
            .section(.giveUpOrDelete)
        #expect(danger?.rows.map(\.id) == [.deleteWork])
        #expect(danger?.rows.first?.label == "Delete Draft…")

        let unsavedNew = StudioPostTestFixtures.makeNewWorkForm()
        let unsavedModel = StudioWorkDetailsModel.build(form: unsavedNew, username: "quietharbor")
        #expect(unsavedModel.section(.giveUpOrDelete) == nil)
    }

    @Test func rowSummariesFormatTagsNotesAndConnections() {
        let form = StudioPostTestFixtures.makePostedWorkForm()
        let model = StudioWorkDetailsModel.build(form: form, username: "quietharbor")

        #expect(model.section(.about)?.rows.first { $0.id == .notes }?.value == "Beginning, end")
        #expect(model.section(.about)?.rows.first { $0.id == .language }?.value == "English")
        let tagsSub = model.section(.tags)?.rows.first?.subtitle
        #expect(tagsSub == "Teen And Up · No Archive Warnings Apply · Gen · 6 more")
        #expect(model.section(.connections)?.rows.first { $0.id == .series }?.value == "Harbour Lights")
        #expect(model.section(.connections)?.rows.first { $0.id == .collections }?.value == "Lighthouses Week")
        #expect(model.section(.connections)?.rows.first { $0.id == .giftFor }?.value == "anne_at_lyme")
        #expect(model.section(.connections)?.rows.first { $0.id == .inspiredBy }?.value == "None")
    }
}

// MARK: - 5. Chapter editor routing & posted menu wiring

@MainActor
struct StudioEditorRoutingAndMenuTests {
    @Test func postRoutingSelectsRightSheetOrUpdatePath() {
        #expect(
            StudioEditorPostRouting.route(
                isPosted: true,
                ao3WorkID: 424242,
                ao3ChapterID: 9001,
                isUnpostedWorkDraft: false,
                hasPostCallback: true,
                isSignedIn: true
            ) == .updatePosted
        )

        #expect(
            StudioEditorPostRouting.route(
                isPosted: false,
                ao3WorkID: 424242,
                ao3ChapterID: nil,
                isUnpostedWorkDraft: false,
                hasPostCallback: true,
                isSignedIn: true
            ) == .postChapter(workID: 424242, chapterID: nil)
        )

        #expect(
            StudioEditorPostRouting.route(
                isPosted: false,
                ao3WorkID: 77,
                ao3ChapterID: nil,
                isUnpostedWorkDraft: true,
                hasPostCallback: true,
                isSignedIn: true
            ) == .postNewWork(existingDraftWorkID: 77)
        )

        #expect(
            StudioEditorPostRouting.route(
                isPosted: false,
                ao3WorkID: nil,
                ao3ChapterID: nil,
                isUnpostedWorkDraft: true,
                hasPostCallback: false,
                isSignedIn: true
            ) == .postNewWork(existingDraftWorkID: nil)
        )

        #expect(
            StudioEditorPostRouting.route(
                isPosted: false,
                ao3WorkID: nil,
                ao3ChapterID: nil,
                isUnpostedWorkDraft: true,
                hasPostCallback: false,
                isSignedIn: false
            ) == .unavailable
        )
    }

    @Test func postedMenuWiringExposesCompareAndDiscardWhenEnabled() {
        var fired: [String] = []
        let capabilities = ChapterEditorMenuCapabilities(
            isPosted: true,
            hasUnpostedChanges: true,
            canPostOrUpdate: true,
            canCompareWithPosted: true,
            canDiscardChanges: true
        )
        let handlers = ChapterEditorMoreMenuHandlers(
            postOrUpdate: { fired.append("update") },
            compareWithPosted: { fired.append("compare") },
            discardChanges: { fired.append("discard") }
        )
        let wiring = ChapterEditorMoreMenuWiring(capabilities: capabilities, handlers: handlers)
        let model = wiring.model()
        let actions = wiring.actions()

        #expect(model.allVisibleActionIDs.contains(.compareWithPosted))
        #expect(model.allVisibleActionIDs.contains(.discardChanges))
        #expect(model.showsUnpostedDot)

        actions.dispatch(.compareWithPosted)
        actions.dispatch(.discardChanges)
        actions.dispatch(.postOrUpdate)
        #expect(fired == ["compare", "discard", "update"])
    }
}

// MARK: - 6. Submission flows & stubbed AO3AuthService writes (no network)

@Suite(.serialized)
@MainActor
struct StudioPostSubmissionTests {
    private func makeSignedInAuth(username: String = "quietharbor") async -> AO3AuthService {
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

    private func makeStubClient() -> AO3Client {
        let config = AO3Client.makeAnonymousSessionConfiguration()
        config.protocolClasses = [StudioPostURLStub.self]
        return AO3Client(session: URLSession(configuration: config), paceSleep: { _ in })
    }

    @Test func postChapterFlowCreatesNewChapterAndSkipsUnchangedTotal() async {
        let work = StudioPostTestFixtures.makePostedWorkForm()
        let chapter = StudioPostTestFixtures.makeChapterForm(chapterID: nil, position: "4", wipLength: "8")
        let checks = StudioPostChapterChecker.checks(chapterForm: chapter, workForm: work)

        var createdSubmits: [AO3WorkSubmitAction] = []
        var updatedSubmits: [AO3WorkSubmitAction] = []
        var totalUpdates: [(Int, Int)] = []

        let outcome = await StudioPostChapterSubmissionFlow.run(
            action: .post,
            chapterForm: chapter,
            workForm: work,
            checks: checks,
            newWorkTotal: 8,
            expectedGeneration: 1,
            currentGeneration: { 1 },
            createChapter: { _, submit in
                createdSubmits.append(submit)
                return "Chapter was posted."
            },
            updateChapter: { _, submit in
                updatedSubmits.append(submit)
                return "Updated."
            },
            updateWorkTotals: { workID, total in
                totalUpdates.append((workID, total))
                return "Totals updated."
            }
        )

        #expect(outcome == .succeeded(notice: "Chapter was posted.", isDraft: false))
        #expect(createdSubmits == [.postWithoutPreview])
        #expect(updatedSubmits.isEmpty)
        #expect(totalUpdates.isEmpty)
    }

    @Test func postChapterFlowUpdatesExistingDraftAndWritesChangedWorkTotalSequentially() async {
        let work = StudioPostTestFixtures.makePostedWorkForm()
        let draftChapter = StudioPostTestFixtures.makeChapterForm(chapterID: 9001, position: "4", wipLength: "10")
        let checks = StudioPostChapterChecker.checks(chapterForm: draftChapter, workForm: work)

        var callOrder: [String] = []
        let outcome = await StudioPostChapterSubmissionFlow.run(
            action: .post,
            chapterForm: draftChapter,
            workForm: work,
            checks: checks,
            newWorkTotal: 10,
            expectedGeneration: 2,
            currentGeneration: { 2 },
            createChapter: { _, _ in
                callOrder.append("create")
                return ""
            },
            updateChapter: { _, submit in
                callOrder.append("update:\(submit.rawValue)")
                return "Draft chapter posted."
            },
            updateWorkTotals: { workID, total in
                callOrder.append("totals:\(workID):\(total)")
                return "Work total updated."
            }
        )

        #expect(outcome == .succeeded(notice: "Draft chapter posted.", isDraft: false))
        #expect(callOrder == ["update:post_button", "totals:424242:10"])
    }

    @Test func postChapterFlowBlocksOnFailingCheckAndSessionChangeAndReportsPartialTotalFailure() async {
        let work = StudioPostTestFixtures.makePostedWorkForm()
        let emptyChapter = StudioPostTestFixtures.makeChapterForm(content: "")
        let failingChecks = StudioPostChapterChecker.checks(chapterForm: emptyChapter, workForm: work)

        var called = false
        let blocked = await StudioPostChapterSubmissionFlow.run(
            action: .post,
            chapterForm: emptyChapter,
            workForm: work,
            checks: failingChecks,
            newWorkTotal: nil,
            expectedGeneration: 1,
            currentGeneration: { 1 },
            createChapter: { _, _ in called = true; return "" },
            updateChapter: { _, _ in called = true; return "" },
            updateWorkTotals: { _, _ in called = true; return "" }
        )
        if case .blockedByChecks = blocked {
            // Expected.
        } else {
            Issue.record("Expected blockedByChecks, got \(blocked)")
        }
        #expect(!called)

        let validChapter = StudioPostTestFixtures.makeChapterForm()
        let passingChecks = StudioPostChapterChecker.checks(chapterForm: validChapter, workForm: work)
        let stale = await StudioPostChapterSubmissionFlow.run(
            action: .post,
            chapterForm: validChapter,
            workForm: work,
            checks: passingChecks,
            newWorkTotal: nil,
            expectedGeneration: 1,
            currentGeneration: { 2 },
            createChapter: { _, _ in called = true; return "" },
            updateChapter: { _, _ in called = true; return "" },
            updateWorkTotals: { _, _ in called = true; return "" }
        )
        #expect(stale == .sessionChanged)
        #expect(!called)

        let partial = await StudioPostChapterSubmissionFlow.run(
            action: .post,
            chapterForm: validChapter,
            workForm: work,
            checks: passingChecks,
            newWorkTotal: 12,
            expectedGeneration: 1,
            currentGeneration: { 1 },
            createChapter: { _, _ in "Saved chapter" },
            updateChapter: { _, _ in "" },
            updateWorkTotals: { _, _ in throw AO3WorkWriteError.rejected("Temporarily busy") }
        )
        if case let .savedChapterButTotalFailed(message) = partial {
            #expect(message.contains("chapter was saved"))
        } else {
            Issue.record("Expected savedChapterButTotalFailed, got \(partial)")
        }

        let ambiguous = await StudioPostChapterSubmissionFlow.run(
            action: .post,
            chapterForm: validChapter,
            workForm: work,
            checks: passingChecks,
            newWorkTotal: nil,
            expectedGeneration: 1,
            currentGeneration: { 1 },
            createChapter: { _, _ in throw URLError(.timedOut) },
            updateChapter: { _, _ in "" },
            updateWorkTotals: { _, _ in "" }
        )
        if case .mayHaveGoneThrough = ambiguous {
            // Expected.
        } else {
            Issue.record("Expected mayHaveGoneThrough, got \(ambiguous)")
        }
    }

    @Test func newWorkFlowBlocksPostWhenRequiredMissingButAllowsDraftSave() async {
        var incomplete = StudioPostTestFixtures.makeNewWorkForm()
        incomplete.title = "Draft Title"
        incomplete.rating = "Teen And Up Audiences"
        incomplete.fandoms = ["Original Work"]
        incomplete.languageID = "1"
        incomplete.chapter = AO3WorkChapterDraft(content: "<p>Hello world.</p>")

        var savedSubmits: [AO3WorkSubmitAction] = []
        let blocked = await StudioPostNewWorkSubmissionFlow.run(
            action: .post,
            form: incomplete,
            expectedGeneration: 1,
            currentGeneration: { 1 },
            saveWork: { _, submit in
                savedSubmits.append(submit)
                return "Posted"
            }
        )
        #expect(blocked == .missingRequired(["Archive Warning"]))
        #expect(savedSubmits.isEmpty)

        let draft = await StudioPostNewWorkSubmissionFlow.run(
            action: .saveDraft,
            form: incomplete,
            expectedGeneration: 1,
            currentGeneration: { 1 },
            saveWork: { _, submit in
                savedSubmits.append(submit)
                return "Draft was successfully created."
            }
        )
        #expect(draft == .succeeded(notice: "Draft was successfully created.", isDraft: true))
        #expect(savedSubmits == [.saveDraft])
    }

    @Test func stubbedAuthServicePostsChapterThroughExistingEndpoint() async {
        let auth = await makeSignedInAuth()
        let client = makeStubClient()

        StudioPostURLStub.reset { _ in
            (200, studioPostFlashHTML("Chapter has been posted!"))
        }
        let work = StudioPostTestFixtures.makePostedWorkForm()
        let chapter = StudioPostTestFixtures.makeChapterForm(chapterID: nil, position: "4", wipLength: "8")
        let checks = StudioPostChapterChecker.checks(chapterForm: chapter, workForm: work)

        let chapterOutcome = await StudioPostChapterSubmissionFlow.run(
            action: .post,
            chapterForm: chapter,
            workForm: work,
            checks: checks,
            newWorkTotal: 8,
            expectedGeneration: auth.sessionGeneration,
            currentGeneration: { auth.sessionGeneration },
            createChapter: { form, submit in
                try await auth.createChapter(form, submit: submit, using: client)
            },
            updateChapter: { form, submit in
                try await auth.updateChapter(form, submit: submit, using: client)
            },
            updateWorkTotals: { _, _ in "" }
        )
        #expect(chapterOutcome == .succeeded(notice: "Chapter has been posted!", isDraft: false))
        let chapterHits = StudioPostURLStub.recorded()
        #expect(chapterHits.count == 1)
        #expect(chapterHits[0].method == "POST")
        #expect(chapterHits[0].path == "/works/424242/chapters")
        let chapterFields = parseStudioFormFields(chapterHits[0].body)
        #expect(chapterFields[AO3WorkFormField.postWithoutPreviewButton] == ["1"])
        #expect(chapterFields[AO3WorkFormField.chapterOnlyTitle] == ["The Boatyard"])
    }

    @Test func stubbedAuthServicePostsAndSavesNewWorkThroughExistingEndpoint() async {
        let auth = await makeSignedInAuth()
        let client = makeStubClient()

        StudioPostURLStub.reset { _ in
            (200, studioPostFlashHTML("Work was successfully posted."))
        }
        var newWork = StudioPostTestFixtures.makeNewWorkForm()
        newWork.title = "The Harbour Pilot's Daughter"
        newWork.rating = "Teen And Up Audiences"
        newWork.warnings = ["No Archive Warnings Apply"]
        newWork.fandoms = ["Original Work"]
        newWork.languageID = "1"
        newWork.chapter = AO3WorkChapterDraft(content: "<p>The harbour bell rang twice.</p>")

        let workOutcome = await StudioPostNewWorkSubmissionFlow.run(
            action: .post,
            form: newWork,
            expectedGeneration: auth.sessionGeneration,
            currentGeneration: { auth.sessionGeneration },
            saveWork: { form, submit in
                try await auth.saveWork(form, submit: submit, using: client)
            }
        )
        #expect(workOutcome == .succeeded(notice: "Work was successfully posted.", isDraft: false))
        let workHits = StudioPostURLStub.recorded()
        #expect(workHits.count == 1)
        #expect(workHits[0].method == "POST")
        #expect(workHits[0].path == "/works")
        let workFields = parseStudioFormFields(workHits[0].body)
        #expect(workFields[AO3WorkFormField.postButton] == ["1"])
        #expect(workFields[AO3WorkFormField.title] == ["The Harbour Pilot's Daughter"])
        #expect(workFields[AO3WorkFormField.rating] == ["Teen And Up Audiences"])
        #expect(workFields[AO3WorkFormField.warnings] == ["No Archive Warnings Apply"])
        #expect(workFields[AO3WorkFormField.fandoms] == ["Original Work"])
        #expect(workFields[AO3WorkFormField.languageID] == ["1"])
        #expect(workFields[AO3WorkFormField.chapterContent] == ["<p>The harbour bell rang twice.</p>"])

        StudioPostURLStub.reset { _ in
            (200, studioPostFlashHTML("Draft was successfully created."))
        }
        let draftOutcome = await StudioPostNewWorkSubmissionFlow.run(
            action: .saveDraft,
            form: newWork,
            expectedGeneration: auth.sessionGeneration,
            currentGeneration: { auth.sessionGeneration },
            saveWork: { form, submit in
                try await auth.saveWork(form, submit: submit, using: client)
            }
        )
        #expect(draftOutcome == .succeeded(notice: "Draft was successfully created.", isDraft: true))
        let draftHits = StudioPostURLStub.recorded()
        #expect(draftHits.count == 1)
        let draftFields = parseStudioFormFields(draftHits[0].body)
        #expect(draftFields[AO3WorkFormField.saveButton] == ["1"])
    }
}
