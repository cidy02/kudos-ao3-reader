import Foundation
import Testing
@testable import Kudos

/// T-267: AO3's preview page, the draft a first preview makes, and the
/// chapter delete. Markup follows otwarchive's `chapters/preview.html.erb`,
/// `works/preview.html.erb`, `chapters/_chapter.html.erb`,
/// `*/_posting_fieldset.html.erb` and `chapters/confirm_delete.html.erb`.
@MainActor
struct WritingPreviewParsingTests {
    static let chapterPreview = """
    <html><head><meta name="csrf-token" content="fresh=="></head><body>
    <form action="/works/search" method="get"><input name="work_search[query]"></form>
    <div id="main">
    <div class="flash notice">This is a draft chapter in a posted work. It will be kept unless the work is deleted.</div>
    <h2 class="heading">Preview</h2>
    <div id="previewpane"><div class="work"><div id="work-skin" class="wrapper"><div id="workskin">
      <div id="chapters"><div class="chapter draft" id="chapter-13">
        <div class="chapter group">
          <h3 class="title"><a href="/works/424242/chapters/9001">Chapter 13</a>: What the tide leaves</h3>
          <h4 class="heading byline">Chapter by <a rel="author" href="/users/w/pseuds/w">w</a></h4>
          <div id="summary" class="summary module">
            <h3 class="heading">Summary:</h3>
            <blockquote class="userstuff"><p>Later that night.</p></blockquote>
          </div>
        </div>
        <div class="userstuff module" role="article">
          <h3 class="landmark heading" id="work">Chapter Text</h3>
          <p>The tide came in <em>without asking</em>.</p>
          <p><img src="https://example.com/tide.png" alt="">He had been early.</p>
        </div>
        <div class="chapter preface group">
          <div class="end notes module" id="chapter_13_endnotes">
            <h3 class="heading">Notes:</h3>
            <blockquote class="userstuff"><p>Thanks for reading.</p></blockquote>
          </div>
        </div>
      </div></div>
    </div></div></div></div>
    <form class="edit_chapter" id="edit_chapter_9001" action="/works/424242/chapters/9001" method="post">
      <input type="hidden" name="_method" value="patch">
      <input type="hidden" name="authenticity_token" value="fresh==">
      <fieldset><ul class="actions">
        <li><input type="submit" name="save_button" value="Save Draft"></li>
        <li><input type="submit" name="edit_button" value="Edit"></li>
        <li><input type="submit" name="post_button" value="Post"></li>
      </ul></fieldset>
    </form>
    </div></body></html>
    """

    /// Headings as "# …", everything else as its plain text.
    static func lines(_ preview: AO3PreviewHTML) -> [String] {
        preview.blocks.map { block in
            switch block {
            case let .heading(text): "# " + text
            case let .label(text): text
            case let .text(document): document.blocks.flatMap(\.runs).map(\.text).joined()
            }
        }
    }

    @Test func aChapterPreviewNamesTheDraftAndReadsInOrder() throws {
        let preview = try AO3Client.parsePreviewHTML(from: Self.chapterPreview)
        // The form after the pane is the preview's own; the header search is not.
        #expect(preview.workID == 424242)
        #expect(preview.chapterID == 9001)
        #expect(preview.csrfToken == "fresh==")
        #expect(preview.notice?.hasPrefix("This is a draft chapter") == true)
        #expect(Self.lines(preview) == [
            "# Chapter 13: What the tide leaves", "Summary:", "Later that night.",
            "The tide came in without asking.", "He had been early.",
            "Notes:", "Thanks for reading."
        ])
        #expect(!preview.html.contains("tide.png"))
    }

    @Test func aWorkPreviewReadsTheFormInsideThePane() throws {
        let html = """
        <html><head><meta name="csrf-token" content="w=="></head><body><div id="main">
        <div id="previewpane"><div class="draft work">
          <dl class="work meta group"><dd class="rating tags">Teen And Up Audiences</dd></dl>
          <div id="work-skin" class="wrapper"><div id="workskin">
            <div class="preface group">
              <h2 class="title heading">The Weight of Water</h2>
              <h3 class="byline heading"><a rel="author" href="/users/w">w</a></h3>
              <div class="summary module"><h3 class="heading">Summary:</h3>
                <blockquote class="userstuff"><p>Gojo teaches.</p></blockquote></div>
            </div>
            <div id="chapters"><div class="userstuff"><p>It rained.</p></div></div>
          </div></div>
        </div>
        <form class="edit_work" id="edit_work_77" action="/works/77" method="post">
          <input type="hidden" name="_method" value="patch">
          <fieldset><ul class="actions">
            <li><input type="submit" name="save_button" value="Save As Draft"></li>
            <li><input type="submit" name="edit_button" value="Edit"></li>
            <li><input type="submit" name="post_button" value="Post"></li>
          </ul></fieldset>
        </form></div>
        </div></body></html>
        """
        let preview = try AO3Client.parsePreviewHTML(from: html)
        #expect(preview.workID == 77)
        #expect(preview.chapterID == nil)
        #expect(Self.lines(preview) == ["# The Weight of Water", "Summary:", "Gojo teaches.", "It rained."])
        #expect(!preview.html.contains("edit_button"))
    }

    /// `render :new` on a validation failure is the form again, not a preview.
    @Test func aReRenderedFormIsNotAPreview() {
        let refused = """
        <html><body><div id="main"><div id="error" class="error">
          <h4>Sorry! We couldn't save this chapter because:</h4><ul><li>Content can't be blank</li></ul>
        </div><div id="chapter-form"><form action="/works/1/chapters"></form></div></div></body></html>
        """
        #expect(throws: AO3WorkWriteError.rejected("Content can't be blank")) {
            try AO3Client.parsePreviewHTML(from: refused)
        }
        #expect(throws: AO3WorkWriteError.previewUnavailable) {
            try AO3Client.parsePreviewHTML(from: "<html><body><div id=\"main\"></div></body></html>")
        }
    }

    // MARK: Adopting the draft a first preview made

    private func newChapterForm() -> AO3ChapterForm {
        AO3ChapterForm(
            workID: 424242, chapterID: nil,
            actionURL: AO3Client.chaptersURL(workID: 424242),
            httpMethodOverride: nil, csrfToken: "old==", title: "What the tide leaves",
            position: "13", content: "<p>The tide came in.</p>", isDraft: true
        )
    }

    @Test func aNewChapterAdoptsTheDraftItsPreviewMade() throws {
        let preview = try AO3Client.parsePreviewHTML(from: Self.chapterPreview)
        let form = try newChapterForm().adopting(preview)
        #expect(form.chapterID == 9001)
        #expect(form.actionURL == AO3Client.chapterURL(workID: 424242, chapterID: 9001))
        #expect(form.isDraft)
        // Post from the preview updates the draft: AO3's own preview form is a
        // PATCH carrying `post_button`, which `chapters#update` posts on.
        let params = Dictionary(form.parameters(submit: .post), uniquingKeysWith: { $1 })
        #expect(params[AO3WorkFormField.methodOverride] == "patch")
        #expect(params[AO3WorkFormField.authenticityToken] == "fresh==")
        #expect(params["post_button"] == "1")
        #expect(params[AO3WorkFormField.chapterOnlyContent] == "<p>The tide came in.</p>")
    }

    @Test func aPreviewThatDoesNotNameTheDraftIsUnconfirmed() throws {
        var preview = try AO3Client.parsePreviewHTML(from: Self.chapterPreview)
        preview.workID = 5
        #expect(throws: AO3WorkWriteError.unconfirmed) { try newChapterForm().adopting(preview) }
        preview.workID = 424242
        preview.chapterID = nil
        #expect(throws: AO3WorkWriteError.unconfirmed) { try newChapterForm().adopting(preview) }
    }

    /// Previewing what AO3 already has only renders; nothing moves.
    @Test func anExistingChapterKeepsItsIdentity() throws {
        var existing = newChapterForm()
        existing.chapterID = 12
        existing.actionURL = AO3Client.chapterURL(workID: 424242, chapterID: 12)
        existing.httpMethodOverride = "patch"
        let preview = try AO3Client.parsePreviewHTML(from: Self.chapterPreview)
        let adopted = try existing.adopting(preview)
        #expect(adopted.chapterID == 12)
        #expect(adopted.actionURL == existing.actionURL)
    }

    @Test func aNewWorkAdoptsTheDraftItsPreviewMade() throws {
        let form = AO3WorkForm(
            kind: .new, workID: nil, actionURL: URL(string: "https://archiveofourown.org/works")!,
            httpMethodOverride: nil, csrfToken: "old==", isDraft: true, isPosted: false
        )
        var preview = AO3PreviewHTML(html: "")
        #expect(throws: AO3WorkWriteError.unconfirmed) { try form.adopting(preview) }
        preview.workID = 77
        let adopted = try form.adopting(preview)
        #expect(adopted.workID == 77)
        #expect(adopted.kind == .draft)
        #expect(adopted.actionURL == AO3Client.workURL(workID: 77))
        #expect(adopted.parameters(submit: WorkEditView.postSubmit).contains { $0 == ("_method", "patch") })
    }
}

// MARK: - Writes, against a local stub only

/// Answers every request locally from `routes`; nothing reaches AO3.
private final class WritingWriteStub: URLProtocol, @unchecked Sendable {
    struct Hit: Sendable {
        var method: String
        var path: String
        var body: String
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var hits: [Hit] = []
    /// "METHOD path" → bodies, one per request, the last repeating; status 200.
    nonisolated(unsafe) private static var routes: [String: [String]] = [:]

    static func reset(_ newRoutes: [String: String]) {
        reset(sequences: newRoutes.mapValues { [$0] })
    }

    static func reset(sequences: [String: [String]]) {
        lock.lock()
        hits = []
        routes = sequences
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
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            stream.close()
        }
        Self.lock.lock()
        Self.hits.append(Hit(method: method, path: path, body: String(decoding: data, as: UTF8.self)))
        let bodies = Self.routes["\(method) \(path)"] ?? []
        if bodies.count > 1 { Self.routes["\(method) \(path)"] = Array(bodies.dropFirst()) }
        let body = bodies.first
        Self.lock.unlock()
        guard let url = request.url, let body,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
@MainActor
struct WritingWriteStubTests {
    private func makeAuth() -> AO3AuthService {
        AO3AuthService(
            vault: MemoryAO3SessionVault(),
            validator: InboxTestSessionValidator(),
            loginPerformer: DynamicInboxTestLoginPerformer(),
            cookieManager: MockAO3CookieManager(),
            removalTracker: MemoryAO3SessionRemovalTracker()
        )
    }

    private func stubClient(paceSleep: (@Sendable (TimeInterval) async throws -> Void)? = nil) -> AO3Client {
        let config = AO3Client.makeAnonymousSessionConfiguration()
        config.protocolClasses = [WritingWriteStub.self]
        return AO3Client(
            session: URLSession(configuration: config),
            nextAllowedRequestAt: paceSleep == nil ? .distantPast : Date().addingTimeInterval(60),
            paceSleep: paceSleep ?? { _ in }
        )
    }

    static let confirmPath = "/works/424242/chapters/9001/confirm_delete"
    /// `chapters/confirm_delete.html.erb`: `form_for(@chapter, method: :delete)`
    /// resolves to the shallow `/chapters/:id`.
    static let confirmPage = """
    <html><head><meta name="csrf-token" content="del=="></head><body><div id="main">
    <h2 class="heading">Delete Chapter</h2>
    <form class="simple destroy" action="/chapters/9001" method="post">
      <input type="hidden" name="_method" value="delete">
      <input type="hidden" name="authenticity_token" value="del==">
      <p class="caution notice">Are you sure you want to <strong><em>delete</em></strong> Chapter 13 of
      The Weight of Water? This will delete all comments on the chapter as well and cannot be undone!</p>
      <p class="actions"><input type="submit" name="commit" value="Yes, Delete Chapter"></p>
    </form></div></body></html>
    """

    private func page(flash kind: String, _ text: String) -> String {
        "<html><body><div id=\"main\"><div class=\"flash \(kind)\">\(text)</div></div></body></html>"
    }

    @Test func deletingAChapterSendsAO3sOwnDeleteForm() async throws {
        WritingWriteStub.reset([
            "GET \(Self.confirmPath)": Self.confirmPage,
            "POST /chapters/9001": page(flash: "notice", "The chapter was successfully deleted.")
        ])
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let result = try await auth.deleteChapter(
            workID: 424242, chapterID: 9001, expectedGeneration: auth.sessionGeneration, using: stubClient()
        )
        #expect(result == "The chapter was successfully deleted.")
        let hits = WritingWriteStub.recorded()
        #expect(hits.map { "\($0.method) \($0.path)" } == ["GET \(Self.confirmPath)", "POST /chapters/9001"])
        let body = try #require(hits.last?.body)
        #expect(body.contains("_method=delete"))
        #expect(body.contains("authenticity_token=del%3D%3D"))
    }

    /// `chapters#destroy` refuses the only chapter with a flash error.
    @Test func aRefusedDeleteSurfacesAO3sReason() async throws {
        let reason = "You can't delete the only chapter in your work."
        WritingWriteStub.reset([
            "GET \(Self.confirmPath)": Self.confirmPage,
            "POST /chapters/9001": page(flash: "error", reason)
        ])
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        await #expect(throws: AO3WorkWriteError.rejected(reason)) {
            try await auth.deleteChapter(
                workID: 424242, chapterID: 9001, expectedGeneration: auth.sessionGeneration, using: stubClient()
            )
        }
    }

    @Test func aDeleteFromAnEarlierSessionSendsNothing() async throws {
        WritingWriteStub.reset(["GET \(Self.confirmPath)": Self.confirmPage])
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let opened = auth.sessionGeneration
        await auth.logout()
        await auth.login(username: "bob", password: "pw")
        await #expect(throws: CancellationError.self) {
            try await auth.deleteChapter(workID: 424242, chapterID: 9001, expectedGeneration: opened, using: stubClient())
        }
        #expect(WritingWriteStub.recorded().isEmpty)
    }

    /// Bob signs in while alice's confirm page is loading. The write fence
    /// alone would pass bob's cookie with alice's delete; the check after the
    /// GET stops it.
    @Test func aSessionChangeDuringTheConfirmPageDeletesNothing() async throws {
        WritingWriteStub.reset([
            "GET \(Self.confirmPath)": Self.confirmPage,
            "POST /chapters/9001": page(flash: "notice", "The chapter was successfully deleted.")
        ])
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let opened = auth.sessionGeneration
        let client = stubClient(paceSleep: { @MainActor _ in
            guard auth.username == "alice" else { return }
            await auth.logout()
            await auth.login(username: "bob", password: "pw")
        })
        await #expect(throws: CancellationError.self) {
            try await auth.deleteChapter(workID: 424242, chapterID: 9001, expectedGeneration: opened, using: client)
        }
        #expect(auth.username == "bob")
        #expect(WritingWriteStub.recorded().map(\.method) == ["GET"])
    }

    // MARK: 1br Remove works

    static let managePath = "/series/77/manage"

    /// `series/_series_order.html.erb`: bare titles, no work links.
    static func managePage(_ rows: [(serial: Int, title: String)]) -> String {
        let items = rows.enumerated().map { index, row in
            """
            <li id="serial_\(row.serial)" class="serial-position-list">
              <input type="text" name="serial_works[]" class="number serial-position-field">
              <span id='position-for-\(row.serial)'>\(index + 1)</span>.
              <h3 class="heading">\(row.title)</h3>
            </li>
            """
        }.joined()
        return """
        <html><head><meta name="csrf-token" content="ser=="></head><body><div id="main">
        <div id="manage-series"><form action="/series/77/update_positions" method="post">
        <ul id="sortable_series_list">\(items)</ul></form></div></div></body></html>
        """
    }

    /// AO3's "Remove Work From Series" link, as Rails UJS sends it; the manage
    /// page read back afterwards is the proof (the redirect carries no flash).
    @Test func removingAWorkFromASeriesSendsAO3sDeleteAndReadsTheRowsBack() async throws {
        WritingWriteStub.reset(sequences: [
            "GET \(Self.managePath)": [
                Self.managePage([(11, "Salt and Static"), (22, "The Weight of Water"), (33, "Long Way")]),
                Self.managePage([(11, "Salt and Static"), (33, "Long Way")])
            ],
            "POST /serial_works/22": ["<html><body><div id=\"main\">Water</div></body></html>"]
        ])
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let rows = try await auth.removeWorkFromSeries(
            seriesID: 77, serialWorkID: 22, expectedGeneration: auth.sessionGeneration, using: stubClient()
        )
        #expect(rows.map(\.serialWorkID) == [11, 33])
        let hits = WritingWriteStub.recorded()
        #expect(hits.map { "\($0.method) \($0.path)" }
            == ["GET \(Self.managePath)", "POST /serial_works/22", "GET \(Self.managePath)"])
        let body = try #require(hits.dropFirst().first?.body)
        #expect(body.contains("_method=delete"))
        #expect(body.contains("authenticity_token=ser%3D%3D"))
    }

    /// A 200 with the row still listed is not a removal.
    @Test func aRemovalTheManagePageDoesNotShowIsUnconfirmed() async throws {
        let page = Self.managePage([(11, "Salt and Static"), (22, "The Weight of Water")])
        WritingWriteStub.reset(sequences: [
            "GET \(Self.managePath)": [page],
            "POST /serial_works/22": ["<html><body></body></html>"]
        ])
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        await #expect(throws: AO3WorkWriteError.unconfirmed) {
            try await auth.removeWorkFromSeries(
                seriesID: 77, serialWorkID: 22, expectedGeneration: auth.sessionGeneration, using: stubClient()
            )
        }
    }

    @Test func aRemovalFromAnEarlierSessionSendsNothing() async throws {
        WritingWriteStub.reset(["GET \(Self.managePath)": Self.managePage([(11, "A"), (22, "B")])])
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let opened = auth.sessionGeneration
        await auth.logout()
        await auth.login(username: "bob", password: "pw")
        await #expect(throws: CancellationError.self) {
            try await auth.removeWorkFromSeries(
                seriesID: 77, serialWorkID: 22, expectedGeneration: opened, using: stubClient()
            )
        }
        #expect(WritingWriteStub.recorded().isEmpty)
    }

    /// Bob signs in while alice's manage page (the CSRF GET) is loading.
    @Test func aSessionChangeDuringTheManagePageRemovesNothing() async throws {
        WritingWriteStub.reset(["GET \(Self.managePath)": Self.managePage([(11, "A"), (22, "B")])])
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let opened = auth.sessionGeneration
        let client = stubClient(paceSleep: { @MainActor _ in
            guard auth.username == "alice" else { return }
            await auth.logout()
            await auth.login(username: "bob", password: "pw")
        })
        await #expect(throws: CancellationError.self) {
            try await auth.removeWorkFromSeries(seriesID: 77, serialWorkID: 22, expectedGeneration: opened, using: client)
        }
        #expect(WritingWriteStub.recorded().map(\.method) == ["GET"])
    }

    // MARK: 1br reorder (T-274)

    /// AO3's own sortable payload: `serial[]` = the manage page's ids in the
    /// new order, one POST, then the manage page read back.
    @Test func reorderingPostsTheManagePagesIDsInOrderAndReadsThemBack() async throws {
        WritingWriteStub.reset(sequences: [
            "GET \(Self.managePath)": [
                Self.managePage([(11, "A"), (22, "B"), (33, "C")]),
                Self.managePage([(22, "B"), (11, "A"), (33, "C")])
            ],
            "POST /series/77/update_positions": ["<html><body><div id=\"main\">Water</div></body></html>"]
        ])
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let rows = try await auth.reorderSeries(
            seriesID: 77, orderedSerialWorkIDs: [22, 11, 33],
            expectedGeneration: auth.sessionGeneration, using: stubClient()
        )
        #expect(rows.map(\.serialWorkID) == [22, 11, 33])
        let hits = WritingWriteStub.recorded()
        #expect(hits.map { "\($0.method) \($0.path)" } == [
            "GET \(Self.managePath)", "POST /series/77/update_positions", "GET \(Self.managePath)"
        ])
        #expect(hits[1].body == "authenticity_token=ser%3D%3D&serial%5B%5D=22&serial%5B%5D=11&serial%5B%5D=33")
    }

    /// The old order read back is not a save.
    @Test func aReorderTheManagePageDoesNotShowIsUnconfirmed() async throws {
        WritingWriteStub.reset(sequences: [
            "GET \(Self.managePath)": [Self.managePage([(11, "A"), (22, "B")])],
            "POST /series/77/update_positions": ["<html><body></body></html>"]
        ])
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        await #expect(throws: AO3WorkWriteError.unconfirmed) {
            try await auth.reorderSeries(
                seriesID: 77, orderedSerialWorkIDs: [22, 11],
                expectedGeneration: auth.sessionGeneration, using: stubClient()
            )
        }
    }

    /// A list that is not exactly AO3's current one is never sent: renumbering
    /// part of a series leaves two works at one position.
    @Test func aReorderOfAListAO3NoLongerHasSendsNothing() async throws {
        WritingWriteStub.reset(["GET \(Self.managePath)": Self.managePage([(11, "A"), (22, "B"), (44, "D")])])
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        await #expect(throws: AO3WorkWriteError.self) {
            try await auth.reorderSeries(
                seriesID: 77, orderedSerialWorkIDs: [22, 11, 33],
                expectedGeneration: auth.sessionGeneration, using: stubClient()
            )
        }
        #expect(WritingWriteStub.recorded().map(\.method) == ["GET"])
    }

    @Test func aReorderFromAnEarlierSessionSendsNothing() async throws {
        WritingWriteStub.reset(["GET \(Self.managePath)": Self.managePage([(11, "A"), (22, "B")])])
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let opened = auth.sessionGeneration
        await auth.logout()
        await auth.login(username: "bob", password: "pw")
        await #expect(throws: CancellationError.self) {
            try await auth.reorderSeries(
                seriesID: 77, orderedSerialWorkIDs: [22, 11], expectedGeneration: opened, using: stubClient()
            )
        }
        #expect(WritingWriteStub.recorded().isEmpty)
    }

    // MARK: 1bn bulk Delete (T-274)

    static let showMultiplePath = "/users/alice/works/show_multiple"
    static let showMultiplePage = """
    <html><head><meta name="csrf-token" content="bulk=="></head><body><div id="main">
    <h2 class="heading">Edit Multiple Works</h2></div></body></html>
    """

    /// `works/confirm_delete_multiple`'s form: `work_ids[]` and "Yes, Delete
    /// Works" to `delete_multiple`, whose redirect carries AO3's notice.
    @Test func deletingSelectedWorksPostsAO3sConfirmForm() async throws {
        WritingWriteStub.reset([
            "GET \(Self.showMultiplePath)": Self.showMultiplePage,
            "POST /users/alice/works/delete_multiple": """
            <html><body><div id="main"><div class="flash notice">Your works Tide, Salt were deleted.</div>
            </div></body></html>
            """
        ])
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let notice = try await auth.deleteWorks(
            workIDs: [101, 202], expectedGeneration: auth.sessionGeneration, using: stubClient()
        )
        #expect(notice == "Your works Tide, Salt were deleted.")
        let hits = WritingWriteStub.recorded()
        #expect(hits.map { "\($0.method) \($0.path)" }
            == ["GET \(Self.showMultiplePath)", "POST /users/alice/works/delete_multiple"])
        #expect(hits[1].body == "authenticity_token=bulk%3D%3D&work_ids%5B%5D=101&work_ids%5B%5D=202"
            + "&commit=Yes%2C%20Delete%20Works")
    }

    @Test func aBulkDeleteFromAnEarlierSessionSendsNothing() async throws {
        WritingWriteStub.reset(["GET \(Self.showMultiplePath)": Self.showMultiplePage])
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let opened = auth.sessionGeneration
        await auth.logout()
        await auth.login(username: "bob", password: "pw")
        await #expect(throws: CancellationError.self) {
            try await auth.deleteWorks(workIDs: [101], expectedGeneration: opened, using: stubClient())
        }
        #expect(WritingWriteStub.recorded().isEmpty)
    }

    /// Bob signs in while alice's token page loads: nothing is deleted.
    @Test func aSessionChangeDuringTheBulkDeleteTokenPageDeletesNothing() async throws {
        WritingWriteStub.reset(["GET \(Self.showMultiplePath)": Self.showMultiplePage])
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let opened = auth.sessionGeneration
        let client = stubClient(paceSleep: { @MainActor _ in
            guard auth.username == "alice" else { return }
            await auth.logout()
            await auth.login(username: "bob", password: "pw")
        })
        await #expect(throws: CancellationError.self) {
            try await auth.deleteWorks(workIDs: [101], expectedGeneration: opened, using: client)
        }
        #expect(WritingWriteStub.recorded().map(\.method) == ["GET"])
    }

    /// Previewing a new chapter is AO3's `preview_button` on create; the page
    /// that comes back names the draft it made.
    @Test func previewingANewChapterPostsPreviewAndLearnsTheDraft() async throws {
        WritingWriteStub.reset(["POST /works/424242/chapters": WritingPreviewParsingTests.chapterPreview])
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let form = AO3ChapterForm(
            workID: 424242, chapterID: nil, actionURL: AO3Client.chaptersURL(workID: 424242),
            httpMethodOverride: nil, csrfToken: "old==", content: "<p>The tide.</p>"
        )
        let preview = try await auth.previewChapter(form, using: stubClient())
        let hits = WritingWriteStub.recorded()
        #expect(hits.map(\.method) == ["POST"])
        #expect(hits.first?.body.contains("preview_button=1") == true)
        #expect(hits.first?.body.contains("post_without_preview_button") == false)
        #expect(try form.adopting(preview).chapterID == 9001)
    }

    // MARK: Grok review of T-267 (P0, P2)

    private func newChapter() -> AO3ChapterForm {
        AO3ChapterForm(
            workID: 424242, chapterID: nil, actionURL: AO3Client.chaptersURL(workID: 424242),
            httpMethodOverride: nil, csrfToken: "old==", content: "<p>The tide.</p>", isDraft: true
        )
    }

    /// AO3 saved the draft and says so; a caution beside the notice, or the
    /// writer's own `class="error"` in the text (AO3 keeps writer classes),
    /// used to read as a refusal, skip `adopting`, and let the next Preview or
    /// Post create a second chapter.
    @Test func aSavedDraftIsNotRefusedByACautionOrTheWritersOwnErrorClass() async throws {
        let caution = WritingPreviewParsingTests.chapterPreview.replacingOccurrences(
            of: "<h2 class=\"heading\">Preview</h2>",
            with: "<div class=\"flash caution\">Check your collections.</div><h2 class=\"heading\">Preview</h2>"
        )
        let ownClasses = WritingPreviewParsingTests.chapterPreview
            .replacingOccurrences(of: "<div class=\"flash notice\">", with: "<div class=\"gone\">")
            .replacingOccurrences(
                of: "<p>The tide came in <em>without asking</em>.</p>",
                with: "<div class=\"error\"><p>Error: late.</p></div><div class=\"flash caution\">x</div>"
            )
        #expect(ownClasses.contains("<div class=\"error\"><p>") && !ownClasses.contains("flash notice"))
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        for page in [caution, ownClasses] {
            WritingWriteStub.reset(["POST /works/424242/chapters": page])
            let preview = try await auth.previewChapter(newChapter(), using: stubClient())
            #expect(try newChapter().adopting(preview).chapterID == 9001)
        }
        #expect(AO3Client.workWriteError(in: ownClasses) == nil)
    }

    /// The real refusals still refuse: the layout's error flash and
    /// `error_messages_for`, both `#main`'s own children.
    @Test func aRealRefusalStillRefuses() {
        let flash = "<html><body><div id=\"main\"><div class=\"flash error\">No.</div></div></body></html>"
        #expect(AO3Client.workWriteError(in: flash) == "No.")
        let list = """
        <html><body><div id="main"><div id="error" class="error"><h4>Sorry!</h4>
        <ul><li>Title can't be blank</li></ul></div></div></body></html>
        """
        #expect(AO3Client.workWriteError(in: list) == "Title can't be blank")
    }

    /// Post work, through the service with the button the view posts, onto
    /// a work page whose text carries the writer's own `class="error"`.
    @Test func postingAWorkSendsPostButtonAndReadsTheNotice() async throws {
        WritingWriteStub.reset(["POST /works": """
        <html><body><div id="main"><div class="flash notice">Work was successfully posted.</div>
        <div id="workskin"><div class="userstuff"><div class="error"><p>Error 404</p></div></div></div>
        </div></body></html>
        """])
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        var form = AO3WorkForm(
            kind: .new, workID: nil, actionURL: URL(string: "https://archiveofourown.org/works")!,
            httpMethodOverride: nil, csrfToken: "w==", isDraft: true, isPosted: false
        )
        form.title = "Tide"
        form.rating = "Teen And Up Audiences"
        form.warnings = ["No Archive Warnings Apply"]
        form.fandoms = ["Original Work"]
        form.languageID = "1"
        form.chapter = AO3WorkChapterDraft(content: "<p>It rained.</p>")
        let notice = try await auth.saveWork(form, submit: WorkEditView.postSubmit, using: stubClient())
        #expect(notice == "Work was successfully posted.")
        let body = try #require(WritingWriteStub.recorded().first?.body)
        #expect(body.contains("post_button=1"))
        #expect(!body.contains("post_without_preview_button"))
    }

    /// AddChapterView's own sequence: Preview (AO3 makes the draft), Edit,
    /// Preview again, Post. Everything after the first request goes to the
    /// draft, so there is one chapter.
    @Test func previewEditPreviewPostStaysOnTheDraftAO3Made() async throws {
        let posted = "<html><body><div id=\"main\"><div class=\"flash notice\">Chapter was successfully posted."
            + "</div></div></body></html>"
        WritingWriteStub.reset(sequences: [
            "POST /works/424242/chapters": [WritingPreviewParsingTests.chapterPreview],
            "POST /works/424242/chapters/9001": [WritingPreviewParsingTests.chapterPreview, posted]
        ])
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let client = stubClient()
        var form = try newChapter().adopting(try await auth.previewChapter(newChapter(), using: client))
        form.content = "<p>The tide came in, edited.</p>"
        form = try form.adopting(try await auth.previewChapter(form, using: client))
        try await auth.updateChapter(form, submit: .post, using: client)
        let hits = WritingWriteStub.recorded()
        #expect(hits.map { "\($0.method) \($0.path)" } == [
            "POST /works/424242/chapters", "POST /works/424242/chapters/9001", "POST /works/424242/chapters/9001"
        ])
        #expect(hits[1].body.contains("_method=patch") && hits[1].body.contains("preview_button=1"))
        #expect(hits[1].body.contains("edited"))
        #expect(hits[2].body.contains("_method=patch") && hits[2].body.contains("post_button=1"))
    }

    // MARK: Grok review of M1b (T-277)

    private func draftChapter() throws -> AO3ChapterForm {
        try newChapter().adopting(try AO3Client.parsePreviewHTML(from: WritingPreviewParsingTests.chapterPreview))
    }

    /// `chapters#update` previews an unposted chapter with `flash[:notice]`,
    /// not `flash.now`, so its draft banner shows again on the next page. When
    /// that page is the Post's `render :edit`, the `error_messages_for` list
    /// beside the banner is still AO3 refusing — the banner made it read as posted.
    @Test func aRefusalBesideALeftoverDraftNoticeStillRefuses() async throws {
        let refused = """
        <html><body><div id="main"><div class="flash notice">This is a draft chapter in a posted work. \
        It will be kept unless the work is deleted.</div><div class="flash"></div>
        <h2 class="heading">Edit Chapter</h2>
        <div id="error" class="error"><h4>Sorry! We couldn't save this chapter because:</h4>
        <ul><li>Content must be less than 510000 characters long.</li></ul></div>
        <form class="edit_chapter" action="/works/424242/chapters/9001" method="post">
        <textarea name="chapter[content]">It went successfully.</textarea></form>
        </div></body></html>
        """
        WritingWriteStub.reset(["POST /works/424242/chapters/9001": refused])
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let form = try draftChapter()
        await #expect(throws: AO3WorkWriteError.rejected("Content must be less than 510000 characters long.")) {
            try await auth.updateChapter(form, submit: .post, using: stubClient())
        }
    }

    /// Only AO3's notice says a write went through; the writer's own
    /// "successfully" in a re-rendered form is not it.
    @Test func theWritersOwnSuccessfullyIsNotAO3SayingSo() async throws {
        WritingWriteStub.reset(["POST /works/424242/chapters/9001": """
        <html><body><div id="main"><h2 class="heading">Edit Chapter</h2>
        <form class="edit_chapter" action="/works/424242/chapters/9001" method="post">
        <textarea name="chapter[content]">It went successfully.</textarea></form></div></body></html>
        """])
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let form = try draftChapter()
        await #expect(throws: AO3WorkWriteError.unconfirmed) {
            try await auth.updateChapter(form, submit: .post, using: stubClient())
        }
    }

    /// With no notice and no `#previewpane` to stand behind, only `#main`'s
    /// own children refuse: a writer may keep `class="flash error"` (AO3 keeps
    /// writer classes) but cannot set `id="error"`.
    @Test func aWritersOwnErrorClassesOnTheWorkPageDoNotRefuse() {
        let page = """
        <html><body><div id="main"><div class="work"><div id="workskin"><div class="userstuff">
        <div class="flash error">No.</div><div class="error"><ul><li>Title can't be blank</li></ul></div>
        </div></div></div></div></body></html>
        """
        #expect(AO3Client.workWriteError(in: page) == nil)
    }

    /// AO3 deletes a series with its last work (`SerialWork#delete_empty_series`),
    /// and the screen's list can be stale, so the live manage page — the token
    /// GET — must still list this work and another.
    @Test func theLastWorkOnTheLiveManagePageIsNeverRemoved() async throws {
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        for live in [[(22, "The Weight of Water")], [(11, "Salt and Static"), (33, "Long Way")]] {
            WritingWriteStub.reset(["GET \(Self.managePath)": Self.managePage(live)])
            await #expect(throws: AO3WorkWriteError.self) {
                try await auth.removeWorkFromSeries(
                    seriesID: 77, serialWorkID: 22, expectedGeneration: auth.sessionGeneration, using: stubClient()
                )
            }
            #expect(WritingWriteStub.recorded().map(\.method) == ["GET"])
        }
    }

    /// The proof is AO3's own `#sortable_series_list`: another list earlier on
    /// the page that never held the work does not show it gone.
    @Test func aRemovalIsJudgedFromTheSortableListItself() async throws {
        let before = Self.managePage([(11, "Salt and Static"), (22, "The Weight of Water")])
        let decoy = before.replacingOccurrences(
            of: "<div id=\"manage-series\">",
            with: "<ul class=\"serial-works\"><li id=\"serial_11\"><h3 class=\"heading\">Salt</h3></li></ul>"
                + "<div id=\"manage-series\">"
        )
        WritingWriteStub.reset(sequences: [
            "GET \(Self.managePath)": [before, decoy],
            "POST /serial_works/22": ["<html><body><div id=\"main\">Water</div></body></html>"]
        ])
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        await #expect(throws: AO3WorkWriteError.unconfirmed) {
            try await auth.removeWorkFromSeries(
                seriesID: 77, serialWorkID: 22, expectedGeneration: auth.sessionGeneration, using: stubClient()
            )
        }
    }

    /// Bob signs in while alice's read-back loads: his page cannot confirm her removal.
    @Test func aReadBackUnderAnotherSessionConfirmsNothing() async throws {
        WritingWriteStub.reset(sequences: [
            "GET \(Self.managePath)": [
                Self.managePage([(11, "Salt and Static"), (22, "The Weight of Water")]),
                Self.managePage([(11, "Salt and Static")])
            ],
            "POST /serial_works/22": ["<html><body><div id=\"main\">Water</div></body></html>"]
        ])
        let auth = makeAuth()
        await auth.login(username: "alice", password: "pw")
        let paces = PaceCount()
        let client = stubClient(paceSleep: { @MainActor _ in
            paces.value += 1
            guard paces.value == 3 else { return }
            await auth.logout()
            await auth.login(username: "bob", password: "pw")
        })
        await #expect(throws: AO3WorkWriteError.unconfirmed) {
            try await auth.removeWorkFromSeries(
                seriesID: 77, serialWorkID: 22, expectedGeneration: auth.sessionGeneration, using: client
            )
        }
        #expect(WritingWriteStub.recorded().map(\.method) == ["GET", "POST", "GET"])
    }
}

@MainActor
private final class PaceCount {
    var value = 0
}
