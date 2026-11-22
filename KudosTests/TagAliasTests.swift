import Foundation
import SwiftData
import Testing
@testable import Kudos

private final class TagAliasRedirectStubProtocol: URLProtocol, @unchecked Sendable {
    enum Action: Sendable {
        case redirect(to: URL, statusCode: Int = 302)
        case respond(finalURL: URL? = nil, statusCode: Int = 200, body: Data)
    }

    private static let lock = NSLock()
    private static var requests: [URLRequest] = []
    private static var handler: ((URLRequest, Int) -> Action)?

    static func reset(handler: @escaping (URLRequest, Int) -> Action) {
        lock.lock()
        requests = []
        self.handler = handler
        lock.unlock()
    }

    static var sent: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    // URLProtocol declares these as `class` methods; `static` cannot override them.
    // swiftlint:disable static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    // swiftlint:enable static_over_final_class

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let index = Self.requests.count
        let handler = Self.handler
        Self.lock.unlock()

        let requestURL = request.url ?? URL(string: "https://archiveofourown.org")!
        let action = handler?(request, index) ?? .respond(body: Data())

        switch action {
        case let .redirect(targetURL, statusCode):
            let redirectResponse = HTTPURLResponse(
                url: requestURL,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": targetURL.absoluteString]
            )!
            client?.urlProtocol(
                self,
                wasRedirectedTo: URLRequest(url: targetURL),
                redirectResponse: redirectResponse
            )
            client?.urlProtocolDidFinishLoading(self)
        case let .respond(finalURL, statusCode, body):
            let response = HTTPURLResponse(
                url: finalURL ?? requestURL,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/html; charset=utf-8"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

@Suite(.serialized)
@MainActor
struct TagAliasTests {
    private final class BundleAnchor {}

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

    private func makeClient() -> AO3Client {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TagAliasRedirectStubProtocol.self]
        let session = URLSession(configuration: config)
        return AO3Client(session: session, paceSleep: { _ in })
    }

    private func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle(for: BundleAnchor.self).url(forResource: name, withExtension: "html")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func minimalTagWorksHTML(
        fandoms: [String] = [],
        relationships: [String] = [],
        characters: [String] = [],
        freeforms: [String] = []
    ) -> String {
        func links(_ tags: [String]) -> String {
            tags.map { #"<a class="tag" href="/tags/placeholder/works">\#($0)</a>"# }
                .joined(separator: ", ")
        }
        let fandomHTML = fandoms.isEmpty
            ? ""
            : #"<h5 class="fandoms heading">\#(links(fandoms))</h5>"#
        let relHTML = relationships.isEmpty
            ? ""
            : #"<li class="relationships">\#(links(relationships))</li>"#
        let charHTML = characters.isEmpty
            ? ""
            : #"<li class="characters">\#(links(characters))</li>"#
        let freeHTML = freeforms.isEmpty
            ? ""
            : #"<li class="freeforms">\#(links(freeforms))</li>"#
        let workHeading = #"<h4 class="heading"><a href="/works/12345">Sample Fic</a> "#
            + #"by <a rel="author" href="/users/writer/pseuds/writer">writer</a></h4>"#
        return """
        <html><body>
        <div id="main" class="works-index">
          <h2 class="heading">1 - 1 of 1 Works in Placeholder</h2>
          <ol class="work index group">
            <li id="work_12345" class="work blurb group" role="article">
              <div class="header module">
                \(workHeading)
                \(fandomHTML)
              </div>
              <ul class="tags commas">\(relHTML)\(charHTML)\(freeHTML)</ul>
            </li>
          </ol>
        </div>
        </body></html>
        """
    }

    // MARK: - Redirect learning & zero-extra-requests

    @Test func redirectLearnsAliasFromFixturePairWithZeroExtraRequests() async throws {
        let client = makeClient()
        let facetsHTML = try fixture("ao3_tag_works_facets")
        let requestedURL = URL(string: "https://archiveofourown.org/tags/Leia%20x%20Han/works")!
        let finalURL = URL(string: "https://archiveofourown.org/tags/Leia%20Organa*s*Han%20Solo/works")!

        // Pattern 1: response directly carries finalURL after HTTP redirect —
        // proves zero follow-up or lookahead calls (exact 1 HTTP request).
        TagAliasRedirectStubProtocol.reset { request, _ in
            #expect(request.url?.path == "/tags/Leia x Han/works")
            return .respond(finalURL: finalURL, statusCode: 200, body: Data(facetsHTML.utf8))
        }

        let page = try await client.worksPage(at: requestedURL, page: 1)
        #expect(TagAliasRedirectStubProtocol.sent.count == 1)
        #expect(page.finalURL == finalURL)
        #expect(
            page.learnedTagAlias == LearnedTagAlias(
                name: "Leia x Han",
                canonicalName: "Leia Organa/Han Solo",
                kind: .relationship
            )
        )
    }

    @Test func http302RedirectLearnsAliasWithoutAnyLookahead() async throws {
        let client = makeClient()
        let html = minimalTagWorksHTML(fandoms: ["Boku no Hero Academia | My Hero Academia"])
        let requestedURL = URL(string: "https://archiveofourown.org/tags/MHA/works?view_adult=true")!
        let canonicalURL = URL(
            string: "https://archiveofourown.org/tags/Boku%20no%20Hero%20Academia%20%7C%20My%20Hero%20Academia/works"
        )!

        TagAliasRedirectStubProtocol.reset { _, index in
            if index == 1 {
                return .redirect(to: canonicalURL, statusCode: 302)
            }
            return .respond(finalURL: canonicalURL, statusCode: 200, body: Data(html.utf8))
        }

        var authRequest = URLRequest(url: requestedURL)
        authRequest.setValue("_otwarchive_session=test", forHTTPHeaderField: "Cookie")
        let page = try await client.worksPage(
            at: URL(string: "https://archiveofourown.org/tags/MHA/works")!,
            filters: AO3SearchFilters(),
            page: 1,
            request: authRequest
        )

        #expect(TagAliasRedirectStubProtocol.sent.map { $0.url?.path } == [
            "/tags/MHA/works",
            "/tags/Boku no Hero Academia | My Hero Academia/works"
        ])
        #expect(
            page.learnedTagAlias == LearnedTagAlias(
                name: "MHA",
                canonicalName: "Boku no Hero Academia | My Hero Academia",
                kind: .fandom
            )
        )
    }

    @Test func noAliasWhenFinalURLEqualsRequestedURL() async throws {
        let client = makeClient()
        let html = try fixture("ao3_tag_works")
        let requestedURL = URL(string: "https://archiveofourown.org/tags/Star%20Wars/works")!
        let normalizedFinalURL = URL(
            string: "https://archiveofourown.org/tags/Star%20Wars/works?view_adult=true"
        )!

        TagAliasRedirectStubProtocol.reset { _, _ in
            .respond(finalURL: normalizedFinalURL, statusCode: 200, body: Data(html.utf8))
        }

        let page = try await client.worksPage(at: requestedURL, page: 1)
        #expect(TagAliasRedirectStubProtocol.sent.count == 1)
        #expect(page.learnedTagAlias == nil)
    }

    @Test func noAliasWhenRedirectedToNonWorksTagPage() async throws {
        let client = makeClient()
        let html = "<html><body><div id='main'><h2 class='heading'>Unwrangled</h2></div></body></html>"
        let requestedURL = URL(string: "https://archiveofourown.org/tags/Unwrangled/works")!
        // Otwarchive sends non-canonical tags without a merger to `/tags/<tag>`, NOT `/works`.
        let nonWorksURL = URL(string: "https://archiveofourown.org/tags/Unwrangled")!

        TagAliasRedirectStubProtocol.reset { _, _ in
            .respond(finalURL: nonWorksURL, statusCode: 200, body: Data(html.utf8))
        }

        let page = try await client.worksPage(at: requestedURL, page: 1)
        #expect(TagAliasRedirectStubProtocol.sent.count == 1)
        #expect(page.learnedTagAlias == nil)
    }

    @Test func kindInferenceHandlesCharacterPlatonicFreeformAndCollectionScopedURLs() async throws {
        let client = makeClient()

        // Platonic "&" relationship retains "&" verbatim (versus "/" romantic ship).
        let requestedPlatonic = URL(string: "https://archiveofourown.org/tags/Obi-Wan%20%26%20Anakin/works")!
        let canonicalPlatonic = URL(string: "https://archiveofourown.org/tags/Anakin%20Skywalker%20*a*%20Obi-Wan%20Kenobi/works")!
        let platonicHTML = minimalTagWorksHTML(relationships: ["Anakin Skywalker & Obi-Wan Kenobi"])
        let platonicPage = try AO3Client.parseSearchPage(
            platonicHTML,
            page: 1,
            requestedURL: requestedPlatonic,
            finalURL: canonicalPlatonic
        )
        #expect(
            platonicPage.learnedTagAlias == LearnedTagAlias(
                name: "Obi-Wan & Anakin",
                canonicalName: "Anakin Skywalker & Obi-Wan Kenobi",
                kind: .relationship
            )
        )

        // Collection-scoped redirect learns character alias via blurbs.
        let requestedChar = URL(string: "https://archiveofourown.org/collections/yuletide/tags/J%20Barnes/works")!
        let canonicalChar = URL(string: "https://archiveofourown.org/collections/yuletide/tags/Bucky%20Barnes/works")!
        let charHTML = minimalTagWorksHTML(characters: ["Bucky Barnes"])
        let charPage = try AO3Client.parseSearchPage(
            charHTML,
            page: 1,
            requestedURL: requestedChar,
            finalURL: canonicalChar
        )
        #expect(
            charPage.learnedTagAlias == LearnedTagAlias(
                name: "J Barnes",
                canonicalName: "Bucky Barnes",
                kind: .character
            )
        )

        // Empty-work FandomWorksPage uses hintKind: .fandom.
        let requestedFandom = URL(string: "https://archiveofourown.org/tags/DW/works")!
        let canonicalFandom = URL(string: "https://archiveofourown.org/tags/Doctor%20Who/works")!
        TagAliasRedirectStubProtocol.reset { _, _ in
            .respond(finalURL: canonicalFandom, statusCode: 200, body: Data("<html><body>No works</body></html>".utf8))
        }
        let fandomPage = try await client.fandomWorksPage(fandom: "DW", filters: AO3SearchFilters())
        #expect(fandomPage.learnedTagAlias == LearnedTagAlias(name: "DW", canonicalName: "Doctor Who", kind: .fandom))
        #expect(AO3Client.tagWorksName(from: requestedFandom) == "DW")

        // Filter sidebar fallback identifies .freeform when no blurbs exist.
        let requestedFreeform = URL(string: "https://archiveofourown.org/tags/h*s*c/works")!
        let canonicalFreeform = URL(string: "https://archiveofourown.org/tags/Hurt*s*Comfort/works")!
        let facetOnlyHTML = """
        <html><body>
        <form id="work-filters"><dl><dd id="include_freeform_tags"><ul>
          <li><label for="f1"><input type="checkbox" value="99">Hurt/Comfort (42)</label></li>
        </ul></dd></dl></form>
        </body></html>
        """
        let freeformPage = try AO3Client.parseSearchPage(
            facetOnlyHTML,
            page: 1,
            requestedURL: requestedFreeform,
            finalURL: canonicalFreeform
        )
        #expect(
            freeformPage.learnedTagAlias == LearnedTagAlias(
                name: "h/c",
                canonicalName: "Hurt/Comfort",
                kind: .freeform
            )
        )
    }

    // MARK: - Persistence & Upsert

    @Test func upsertKeepsOneRowPerNameAndKindAndUpdatesTimestamp() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let t1 = Date(timeIntervalSince1970: 1_750_000_000)
        let t2 = Date(timeIntervalSince1970: 1_750_000_600)
        let t3 = Date(timeIntervalSince1970: 1_750_001_200)

        let first = try #require(TagAliasStore.upsert(
            name: "BNHA",
            canonicalName: "Boku no Hero Academia",
            kind: .fandom,
            in: context,
            now: t1
        ))
        #expect(first.learnedAt == t1)

        // Re-learning updates canonicalName, learnedAt, and merges parentFandoms in one row.
        let updated = try #require(TagAliasStore.upsert(
            name: "  BNHA ",
            canonicalName: "Boku no Hero Academia | My Hero Academia",
            kind: .fandom,
            parentFandoms: ["Anime & Manga"],
            in: context,
            now: t2
        ))
        #expect(updated.id == first.id)
        #expect(updated.learnedAt == t2)
        #expect(updated.lastModifiedAt == t2)
        #expect(updated.canonicalName == "Boku no Hero Academia | My Hero Academia")
        #expect(updated.parentFandoms == ["Anime & Manga"])

        // Re-learning without parentFandoms preserves previously learned parentFandoms.
        _ = TagAliasStore.upsert(
            name: "BNHA",
            canonicalName: "Boku no Hero Academia | My Hero Academia",
            kind: .fandom,
            in: context,
            now: t3
        )
        #expect(updated.learnedAt == t3)
        #expect(updated.parentFandoms == ["Anime & Manga"])

        // Different kind keeps a distinct row even with identical alias text.
        _ = TagAliasStore.upsert(
            name: "BNHA",
            canonicalName: "Boku no Hero Academia Characters",
            kind: .character,
            in: context,
            now: t3
        )
        // Self-alias is ignored.
        #expect(TagAliasStore.upsert(name: "Same", canonicalName: "Same", kind: .fandom, in: context) == nil)

        let all = try context.fetch(FetchDescriptor<TagAlias>())
        #expect(all.count == 2)
    }
}
