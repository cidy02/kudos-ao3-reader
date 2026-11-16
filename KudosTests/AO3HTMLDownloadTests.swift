import Foundation
@testable import Kudos
import SwiftSoup
import Testing

/// AO3 serving HTML only (November 2026). The fixtures are written out from
/// otwarchive 452391b648f2's own templates — `downloads/show` with its three
/// partials under the `barebones` layout, and `works/_work_header_navigation` for
/// the menu — not from a saved page. Android runs the same fixtures
/// (`AO3HtmlDownloadTest.kt`).
@Suite(.serialized)
struct AO3HTMLDownloadTests {
    private final class BundleAnchor {}

    private static func fixture(_ name: String) throws -> String {
        let url = try #require(Bundle(for: BundleAnchor.self).url(forResource: name, withExtension: "html"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// `works/_work_header_navigation.html.erb`: the li, noscript and button share a line.
    private static func workPage(_ formats: String...) -> String {
        let links = formats
            .map { "<li><a href=\"/downloads/7/One_Shot.\($0)?updated_at=1763000000\">\($0.uppercased())</a></li>" }
            .joined(separator: "\n")
        return """
        <html><body><ul class="work navigation actions">
          <li class="comments"><a href="/works/7?show_comments=true">Comments</a></li>
          <li class="download"><noscript><h4 class="heading">Download</h4></noscript>\
        <button class="hidden">Download</button>
            <ul class="expandable secondary">
        \(links)
            </ul>
          </li>
        </ul></body></html>
        """
    }

    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0])

    private func write(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("epub")
        try data.write(to: url)
        return url
    }

    private func text(_ zip: MiniZip, _ name: String) throws -> String {
        String(decoding: try #require(zip.data(named: name)), as: UTF8.self)
    }

    // MARK: - Detection

    @Test func theMenuSaysWhichFormatsAreOffered() {
        #expect(AO3Client.parseDownloadFormats(from: Self.workPage("html")) == ["html"])
        #expect(
            AO3Client.parseDownloadFormats(from: Self.workPage("azw3", "epub", "mobi", "pdf", "html"))
                == ["azw3", "epub", "mobi", "pdf", "html"]
        )
        // A guest's view of a restricted work, or downloads switched off: no menu at all.
        #expect(AO3Client.parseDownloadFormats(from: "<html><body><ul class=\"work navigation actions\"></ul></body></html>") == nil)
    }

    // MARK: - Conversion

    @Test func anHTMLDownloadBecomesTheEPUBAO3WouldHaveMade() async throws {
        let html = try Self.fixture("ao3_download_multi_chapter")
        let fetch: @Sendable (URL, Int) async -> Data? = { $0.lastPathComponent == "map.png" ? Self.png : nil }
        let data = try #require(try await AO3HTMLDownloadConverter.epub(fromHTML: html, fetchImage: fetch))
        let url = try write(data)
        defer { try? FileManager.default.removeItem(at: url) }

        // calibre's split, as the app's own EPUB reader sees it.
        let extracted = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: extracted) }
        let document = try EPUBDocument.open(epubURL: url, into: extracted)
        #expect(document.spineURLs.count == 4)
        #expect(document.chapters.map(\.title) == ["Preface", "Chapter 1: Setting Out", "Chapter 2", "Afterword"])

        // What `importEPUB` reads for a download: the OPF, as calibre would have filled it.
        let metadata = try EPUBDocument.metadata(ofEPUBAt: url)
        #expect(metadata.title == "The Long Road & Back")
        #expect(metadata.author == "ink_and_oak, second_author (their_pseud)")
        #expect(metadata.summary == "Two friends walk to the sea.")
        #expect(metadata.sourceURL == "https://archiveofourown.org/works/4242")
        #expect(metadata.language == "fr")
        #expect(metadata.rating == "Teen And Up Audiences")
        #expect(metadata.seriesTitle == "Roads")
        #expect(metadata.seriesIndex == 2)
        #expect(metadata.publishedDate == "2026-03-09")
        #expect(metadata.subjects == [
            "Teen And Up Audiences", "No Archive Warnings Apply", "Gen", "Original Work", "Fluff"
        ])

        let zip = try MiniZip(data: data)
        let preface = try text(zip, "OEBPS/chapter-1.xhtml")
        let chapterOne = try text(zip, "OEBPS/chapter-2.xhtml")
        let chapterTwo = try text(zip, "OEBPS/chapter-3.xhtml")
        let afterword = try text(zip, "OEBPS/chapter-4.xhtml")
        #expect(chapterOne.contains("The road began at the door."))
        #expect(!chapterOne.contains("It ended at the sea."))
        #expect(chapterTwo.contains("It ended at the sea."))
        #expect(chapterTwo.contains("Thanks for reading chapter two."))
        #expect(afterword.contains("drop by the Archive and comment"))

        // AO3's own headings are the only ones: nothing is printed twice, and the
        // Preface and Afterword stay unlabelled, as in AO3's EPUB.
        #expect(!preface.contains("<h1>Preface</h1>"))
        #expect(!preface.contains("toc-heading"))
        #expect(chapterOne.components(separatedBy: "Chapter 1: Setting Out").count == 3) // <title> + AO3's h2
        // The preface keeps the structure the importer reads an AO3 EPUB's preface by.
        #expect(preface.contains("<dl class=\"tags\">"))
        // "See the end of the work for notes" now names the file the notes are in.
        #expect(preface.contains("href=\"chapter-4.xhtml#endnotes\""))
        #expect(afterword.contains("id=\"endnotes\""))

        // The image that could be fetched is in the book; the one that could not is
        // gone, and nothing is left pointing at a host. Scripts never make it in.
        #expect(zip.data(named: "OEBPS/images/image-1.png") == Self.png)
        #expect(chapterOne.contains("src=\"images/image-1.png\""))
        for name in zip.names where name.hasSuffix(".xhtml") || name.hasSuffix(".opf") {
            let entry = try text(zip, name)
            #expect(!entry.contains("img.example"))
            #expect(!entry.contains("alert(1)"))
        }

        // The same download always makes the same file, so two devices agree on its digest.
        let again = try #require(try await AO3HTMLDownloadConverter.epub(fromHTML: html, fetchImage: fetch))
        #expect(again == data)
    }

    @Test func aSingleChapterWorkHasOneSectionNamedForTheWork() async throws {
        let html = try Self.fixture("ao3_download_single_chapter")
        let data = try #require(try await AO3HTMLDownloadConverter.epub(fromHTML: html, fetchImage: { _, _ in nil }))
        let url = try write(data)
        defer { try? FileManager.default.removeItem(at: url) }
        let extracted = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: extracted) }

        let document = try EPUBDocument.open(epubURL: url, into: extracted)
        #expect(document.chapters.map(\.title) == ["Preface", "One Shot", "Afterword"])
        #expect(try EPUBDocument.metadata(ofEPUBAt: url).author == "Anonymous")

        let zip = try MiniZip(data: data)
        let chapterTwo = try text(zip, "OEBPS/chapter-2.xhtml")
        #expect(chapterTwo.contains("All of it, at once."))
        #expect(!chapterTwo.contains("toc-heading"))
        #expect(chapterTwo.components(separatedBy: "One Shot").count == 2) // <title> only
        #expect(try text(zip, "OEBPS/style.css").contains(".toc-heading { display: none; }"))
    }

    @Test func aWindows1252ByteInTheFileConverts() async throws {
        var bytes = Data(try Self.fixture("ao3_download_single_chapter").utf8)
        let target = Data("All of it, at once.".utf8)
        let replacement = Data("All".utf8) + Data([0x93]) + Data("it.".utf8)
        let range = try #require(bytes.range(of: target))
        bytes.replaceSubrange(range, with: replacement)

        let htmlFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("html")
        try bytes.write(to: htmlFile)
        defer { try? FileManager.default.removeItem(at: htmlFile) }

        let epubURL = try await AO3HTMLDownloadConverter.epubFile(fromHTMLFile: htmlFile, named: "win1252.epub")
        defer { try? FileManager.default.removeItem(at: epubURL) }
        #expect(try EPUBDocument.metadata(ofEPUBAt: epubURL).title == "One Shot")
        let zip = try MiniZip(data: try Data(contentsOf: epubURL))
        let chapterTwo = try text(zip, "OEBPS/chapter-2.xhtml")
        #expect(chapterTwo.contains("All\u{FFFD}it."))
    }

    @Test func rtlDirectionSurvivesSanitizationOnBlocksAndBody() async throws {
        let html = try Self.fixture("ao3_download_single_chapter")
            .replacingOccurrences(of: "<body>", with: "<body dir=\"rtl\">")
            .replacingOccurrences(
                of: "<div class=\"userstuff\">\n      <p>All of it, at once.</p>",
                with: """
                <div class="userstuff" dir="rtl">
                      <p dir="auto">All of it, at once.</p>
                      <p dir="ltr">Left to right.</p>
                      <p dir="bogus">Invalid dir stripped.</p>
                """
            )
        let data = try #require(try await AO3HTMLDownloadConverter.epub(fromHTML: html, fetchImage: { _, _ in nil }))
        let zip = try MiniZip(data: data)
        let opf = try text(zip, "OEBPS/content.opf")
        let chapterTwo = try text(zip, "OEBPS/chapter-2.xhtml")
        #expect(opf.contains("page-progression-direction=\"rtl\""))
        #expect(chapterTwo.contains("<body dir=\"rtl\">"))
        #expect(chapterTwo.contains("<div class=\"userstuff\" dir=\"rtl\">"))
        #expect(chapterTwo.contains("<p dir=\"auto\">"))
        #expect(chapterTwo.contains("<p dir=\"ltr\">"))
        #expect(!chapterTwo.contains("bogus"))
    }

    @Test func anOrdinaryPageIsNotABook() async throws {
        #expect(try await AO3HTMLDownloadConverter.epub(fromHTML: Self.workPage("html"), fetchImage: { _, _ in nil }) == nil)
    }

    @Test func aDownloadedHTMLFileImportedByHandIsReadTheSameWay() throws {
        // Settings → Import, with the file AO3's own "HTML" link saves.
        let result = try HTMLWorkConverter.convert(
            html: Self.fixture("ao3_download_multi_chapter"), fallbackTitle: "The_Long_Road"
        )
        #expect(result.metadata.title == "The Long Road & Back")
        #expect(result.chapters.map(\.title) == ["Preface", "Chapter 1: Setting Out", "Chapter 2", "Afterword"])
        // No fetching on this path: a file from disk never reaches for the network.
        #expect(!result.chapters.contains { $0.bodyXHTML.contains("<img") })
    }

    // MARK: - Download

    private func client() -> AO3Client {
        let configuration = AO3Client.makeAnonymousSessionConfiguration()
        configuration.protocolClasses = [HTMLOnlyAO3.self]
        return AO3Client(session: URLSession(configuration: configuration), paceSleep: { _ in })
    }

    @Test func whenAO3OffersOnlyHTMLTheDownloadIsStillAnEPUBAndTheNextOneGoesStraightToHTML() async throws {
        HTMLOnlyAO3.reset(page: Self.workPage("html"), html: try Self.fixture("ao3_download_single_chapter"))
        let client = client()

        let first = try await client.downloadEPUB(workID: 7)
        defer { try? FileManager.default.removeItem(at: first) }
        #expect(first.pathExtension == "epub")
        #expect(try EPUBDocument.metadata(ofEPUBAt: first).title == "One Shot")
        #expect(HTMLOnlyAO3.paths == ["/downloads/7/work.epub", "/works/7", "/downloads/7/work.html"])

        HTMLOnlyAO3.paths = []
        let second = try await client.downloadEPUB(workID: 8)
        defer { try? FileManager.default.removeItem(at: second) }
        #expect(HTMLOnlyAO3.paths == ["/downloads/8/work.html"])
    }

    @Test func failedHTMLDoesNotSkipTheNextEPUBProbe() async throws {
        HTMLOnlyAO3.reset(page: Self.workPage("html"), html: "")
        HTMLOnlyAO3.routeStatus = ["/downloads/7/work.epub": 404, "/downloads/7/work.html": 403]
        let client = client()
        await #expect(throws: AO3Error.forbidden) { _ = try await client.downloadEPUB(workID: 7) }
        HTMLOnlyAO3.paths = []
        HTMLOnlyAO3.routeStatus = ["/downloads/8/work.epub": 404]
        HTMLOnlyAO3.html = try Self.fixture("ao3_download_single_chapter")
        let file = try await client.downloadEPUB(workID: 8)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(HTMLOnlyAO3.paths == ["/downloads/8/work.epub", "/works/8", "/downloads/8/work.html"])
    }

    @Test func anEPUBThatFailsWhileStillOnTheMenuIsAFailureAndHTMLIsNotAsked() async throws {
        HTMLOnlyAO3.reset(page: Self.workPage("epub", "html"), html: try Self.fixture("ao3_download_single_chapter"))
        await #expect(throws: AO3Error.parse) { _ = try await client().downloadEPUB(workID: 7) }
        #expect(HTMLOnlyAO3.paths == ["/downloads/7/work.epub", "/works/7"])
    }

    @Test func withNoMenuToReadHTMLIsTriedAndTheFirstAnswerStandsIfItFailsToo() async throws {
        let noMenu = "<html><body><p>This work is only available to registered users.</p></body></html>"
        HTMLOnlyAO3.reset(page: noMenu, html: try Self.fixture("ao3_download_single_chapter"))
        let file = try await client().downloadEPUB(workID: 7)
        try? FileManager.default.removeItem(at: file)

        HTMLOnlyAO3.reset(page: noMenu, html: noMenu)
        await #expect(throws: AO3Error.parse) { _ = try await client().downloadEPUB(workID: 7) }
    }

    @Test func aWorkThatIsGoneIsStillReportedAsGone() async throws {
        HTMLOnlyAO3.reset(page: "", html: "", status: 404)
        await #expect(throws: AO3Error.notFound) { _ = try await client().downloadEPUB(workID: 7) }
        #expect(HTMLOnlyAO3.paths == ["/downloads/7/work.epub", "/works/7"])
    }

    @Test func beingBlockedAsksForNothingMore() async throws {
        HTMLOnlyAO3.reset(page: Self.workPage("html"), html: "", status: 403)
        await #expect(throws: AO3Error.forbidden) { _ = try await client().downloadEPUB(workID: 7) }
        #expect(HTMLOnlyAO3.paths == ["/downloads/7/work.epub"])
    }

    @Test func followUpErrorsOnWorkPageOrHTMLSurfaceAsThemselves() async throws {
        let maintenanceBody = try Self.fixture("ao3_maintenance")
        let cases: [(status: Int, body: String, headers: [String: String], expected: AO3Error)] = [
            (403, "", [:], .forbidden),
            (429, "", ["Retry-After": "0"], .rateLimited(retryAfter: 0)),
            (503, "", [:], .server(status: 503)),
            (503, maintenanceBody, [:], .maintenance),
        ]

        // 1) `.epub` 404 → work page fails with 403 / 429 / 503 / maintenance.
        for item in cases {
            HTMLOnlyAO3.reset(page: item.body, html: "")
            HTMLOnlyAO3.routeStatus = ["/downloads/7/work.epub": 404, "/works/7": item.status]
            HTMLOnlyAO3.routeHeaders = ["/works/7": item.headers]
            await #expect(throws: item.expected) { _ = try await client().downloadEPUB(workID: 7) }
            #expect(!HTMLOnlyAO3.paths.contains("/downloads/7/work.html"))
        }

        // 2) `.epub` 404 → work page has no menu → `.html` fails with 403 / 429 / 503 / maintenance.
        let noMenu = "<html><body><p>Restricted.</p></body></html>"
        for item in cases {
            HTMLOnlyAO3.reset(page: noMenu, html: item.body)
            HTMLOnlyAO3.routeStatus = [
                "/downloads/7/work.epub": 404,
                "/works/7": 200,
                "/downloads/7/work.html": item.status,
            ]
            HTMLOnlyAO3.routeHeaders = ["/downloads/7/work.html": item.headers]
            await #expect(throws: item.expected) { _ = try await client().downloadEPUB(workID: 7) }
        }

        // 3) `.epub` 404 → work page offers HTML → `.html` succeeds.
        HTMLOnlyAO3.reset(page: Self.workPage("html"), html: try Self.fixture("ao3_download_single_chapter"))
        HTMLOnlyAO3.routeStatus = ["/downloads/7/work.epub": 404]
        let file = try await client().downloadEPUB(workID: 7)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(try EPUBDocument.metadata(ofEPUBAt: file).title == "One Shot")

        // 4) Cancelled task during follow-up still throws CancellationError, not refusal.
        HTMLOnlyAO3.reset(page: Self.workPage("html"), html: "")
        HTMLOnlyAO3.routeStatus = ["/downloads/7/work.epub": 404]
        let cancelledClient = client()
        let task = Task {
            try await Task.sleep(nanoseconds: 0)
            return try await cancelledClient.downloadEPUB(workID: 7)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    // MARK: - Image isolation & caps

    @Test func imageSessionKeepsNoCookiesOrCredentials() {
        for config in [
            AO3HTMLDownloadConverter.makeImageSessionConfiguration(),
            AO3HTMLDownloadConverter.imageSession.configuration,
        ] {
            #expect(!config.httpShouldSetCookies)
            #expect(config.httpCookieStorage == nil)
            #expect(config.urlCredentialStorage == nil)
        }
    }

    @Test func ao3HostImagesAndRedirectsGoThroughAO3ClientNeverBareSession() async throws {
        ImageStubProtocol.reset()
        ImageStubProtocol.responses[URL(string: "https://img.example/redirect.png")!] = .redirect(
            to: URL(string: "https://archiveofourown.org/images/from-redirect.png")!
        )
        let bareConfig = AO3HTMLDownloadConverter.makeImageSessionConfiguration()
        bareConfig.protocolClasses = [ImageStubProtocol.self]
        let bareSession = URLSession(configuration: bareConfig)

        AO3ImageStubProtocol.reset(data: Self.png)
        let ao3Config = AO3Client.makeAnonymousSessionConfiguration()
        ao3Config.protocolClasses = [AO3ImageStubProtocol.self]
        let ao3Client = AO3Client(session: URLSession(configuration: ao3Config), paceSleep: { _ in })

        // Direct AO3 URL: fetched via AO3Client (with its User-Agent), never bare session.
        let directURL = URL(string: "https://archiveofourown.org/images/direct.png")!
        let directData = await AO3HTMLDownloadConverter.fetchRemoteImage(
            directURL, session: bareSession, ao3Client: ao3Client
        )
        #expect(directData == Self.png)
        #expect(ImageStubProtocol.requestedURLs.isEmpty)
        #expect(AO3ImageStubProtocol.requestedURLs == [directURL])
        #expect(AO3ImageStubProtocol.userAgents.first == AO3RequestDefaults.userAgent)

        // Non-HTTPS AO3 host URL: skipped, never touches bare session.
        let insecureAO3 = URL(string: "http://archiveofourown.org/images/insecure.png")!
        #expect(
            await AO3HTMLDownloadConverter.fetchRemoteImage(
                insecureAO3, session: bareSession, ao3Client: ao3Client
            ) == nil
        )
        #expect(ImageStubProtocol.requestedURLs.isEmpty)

        // Redirect from non-AO3 host to AO3 host: bare session stops at 302; target goes through AO3Client.
        let redirectOrigin = URL(string: "https://img.example/redirect.png")!
        let redirectTarget = URL(string: "https://archiveofourown.org/images/from-redirect.png")!
        let redirectedData = await AO3HTMLDownloadConverter.fetchRemoteImage(
            redirectOrigin, session: bareSession, ao3Client: ao3Client
        )
        #expect(redirectedData == Self.png)
        #expect(ImageStubProtocol.requestedURLs == [redirectOrigin])
        #expect(AO3ImageStubProtocol.requestedURLs == [directURL, redirectTarget])
    }

    @Test func perImageAndTotalImageCapsAreEnforced() async throws {
        ImageStubProtocol.reset()
        let bareConfig = AO3HTMLDownloadConverter.makeImageSessionConfiguration()
        bareConfig.protocolClasses = [ImageStubProtocol.self]
        let bareSession = URLSession(configuration: bareConfig)
        let ao3Client = client()

        // Content-Length above cap aborts before reading body.
        let headerOverCap = URL(string: "https://img.example/header-over.png")!
        ImageStubProtocol.responses[headerOverCap] = .chunks(
            [Self.png, Data(repeating: 0, count: 64)], contentLength: 100
        )
        #expect(
            await AO3HTMLDownloadConverter.fetchRemoteImage(
                headerOverCap, session: bareSession, ao3Client: ao3Client, maxBytes: 16
            ) == nil
        )
        #expect(!ImageStubProtocol.finishedURLs.contains(headerOverCap))

        // Chunked response without Content-Length aborts as soon as bytes exceed cap.
        let streamOverCap = URL(string: "https://img.example/stream-over.png")!
        ImageStubProtocol.responses[streamOverCap] = .chunks(
            [Data(repeating: 1, count: 10), Data(repeating: 2, count: 10)], contentLength: nil
        )
        #expect(
            await AO3HTMLDownloadConverter.fetchRemoteImage(
                streamOverCap, session: bareSession, ao3Client: ao3Client, maxBytes: 16
            ) == nil
        )
        #expect(!ImageStubProtocol.finishedURLs.contains(streamOverCap))

        // The AO3 route must stop the same stream without retrying it.
        let ao3OverCap = URL(string: "https://archiveofourown.org/images/over.png")!
        ImageStubProtocol.responses[ao3OverCap] = .chunks(
            [Data(repeating: 1, count: 10), Data(repeating: 2, count: 10), Data(repeating: 3, count: 10)],
            contentLength: nil
        )
        let ao3Config = AO3Client.makeAnonymousSessionConfiguration()
        ao3Config.protocolClasses = [ImageStubProtocol.self]
        let cappedAO3Client = AO3Client(session: URLSession(configuration: ao3Config), paceSleep: { _ in })
        #expect(await AO3HTMLDownloadConverter.fetchRemoteImage(
            ao3OverCap, session: bareSession, ao3Client: cappedAO3Client, maxBytes: 16
        ) == nil)
        #expect(ImageStubProtocol.requestedURLs.filter { $0 == ao3OverCap }.count == 1)
        #expect(!ImageStubProtocol.finishedURLs.contains(ao3OverCap))

        // Total cap checks `total + size <= max` before appending.
        let html = try Self.fixture("ao3_download_single_chapter").replacingOccurrences(
            of: "<p>All of it, at once.</p>",
            with: """
            <p><img src="https://img.example/a.png" alt="a"></p>
            <p><img src="https://img.example/b.png" alt="b"></p>
            <p><img src="https://img.example/c.png" alt="c"></p>
            """
        )
        let epubData = try #require(
            try await AO3HTMLDownloadConverter.epub(
                fromHTML: html,
                fetchImage: { url, limit in
                    if url.lastPathComponent == "c.png" { #expect(limit == 1) }
                    return Self.png
                }, // 12 bytes each
                maxTotalImageBytes: 25
            )
        )
        let zip = try MiniZip(data: epubData)
        #expect(zip.data(named: "OEBPS/images/image-1.png") == Self.png)
        #expect(zip.data(named: "OEBPS/images/image-2.png") == Self.png)
        #expect(zip.data(named: "OEBPS/images/image-3.png") == nil)
    }

    @Test func undecodableWebPIsDroppedInsteadOfPackaged() async throws {
        let html = try Self.fixture("ao3_download_single_chapter").replacingOccurrences(
            of: "<p>All of it, at once.</p>",
            with: "<p><img src=\"https://img.example/bad.webp\"></p>"
        )
        let badWebP = Data("RIFFxxxxWEBPbad".utf8)
        let data = try #require(try await AO3HTMLDownloadConverter.epub(
            fromHTML: html, fetchImage: { _, _ in badWebP }
        ))
        let zip = try MiniZip(data: data)
        #expect(!zip.names.contains { $0.hasSuffix(".webp") })
        #expect(!zip.names.contains { $0.hasPrefix("OEBPS/images/") })
        #expect(try text(zip, "OEBPS/chapter-2.xhtml").contains("<img") == false)
    }

    @Test func webPIsConvertedBeforePackaging() async throws {
        let html = try Self.fixture("ao3_download_single_chapter").replacingOccurrences(
            of: "<p>All of it, at once.</p>",
            with: "<p><img src=\"https://img.example/tiny.webp\"></p>"
        )
        let webP = try #require(Data(base64Encoded:
            "UklGRjwAAABXRUJQVlA4IDAAAADQAQCdASoBAAEAAUAmJaACdLoB+AADsAD+8ut//NgVzXPv9//S4P0uD9Lg/9KQAAA="
        ))
        let data = try #require(try await AO3HTMLDownloadConverter.epub(
            fromHTML: html, fetchImage: { _, _ in webP }
        ))
        let zip = try MiniZip(data: data)
        #expect(zip.data(named: "OEBPS/images/image-1.png")?.starts(with: [0x89, 0x50, 0x4E, 0x47]) == true)
        #expect(!zip.names.contains { $0.hasSuffix(".webp") })
        #expect(try text(zip, "OEBPS/chapter-2.xhtml").contains("src=\"images/image-1.png\""))
    }
}

/// AO3 with EPUB withdrawn: an EPUB request gets a page in its place, as
/// `DownloadsController#show` sends when a format cannot be made. No request leaves
/// the process.
private final class HTMLOnlyAO3: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var page = ""
    nonisolated(unsafe) static var html = ""
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var routeStatus: [String: Int] = [:]
    nonisolated(unsafe) static var routeHeaders: [String: [String: String]] = [:]
    nonisolated(unsafe) static var paths: [String] = []

    static func reset(page: String, html: String, status: Int = 200) {
        self.page = page
        self.html = html
        self.status = status
        routeStatus = [:]
        routeHeaders = [:]
        paths = []
    }

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let code = Self.routeStatus[url.path] ?? Self.status
        var headers = ["Content-Type": "text/html; charset=utf-8"]
        for (key, value) in Self.routeHeaders[url.path] ?? [:] { headers[key] = value }
        guard let response = HTTPURLResponse(
            url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.paths.append(url.path)
        let body = switch url.pathExtension {
        case "html": Self.html
        case "epub": "<!DOCTYPE html><html><body>We were not able to render this work.</body></html>"
        default: Self.page
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class ImageStubProtocol: URLProtocol, @unchecked Sendable {
    enum StubResponse {
        case chunks([Data], contentLength: Int?)
        case redirect(to: URL)
    }

    nonisolated(unsafe) static var responses: [URL: StubResponse] = [:]
    nonisolated(unsafe) static var requestedURLs: [URL] = []
    nonisolated(unsafe) static var finishedURLs: [URL] = []
    private var cancelled = false

    static func reset() {
        responses = [:]
        requestedURLs = []
        finishedURLs = []
    }

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let stub = Self.responses[url] else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }
        Self.requestedURLs.append(url)
        switch stub {
        case let .redirect(to: target):
            guard let response = HTTPURLResponse(
                url: url, statusCode: 302, httpVersion: "HTTP/1.1",
                headerFields: ["Location": target.absoluteString]
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            client?.urlProtocolDidFinishLoading(self)
        case let .chunks(chunks, contentLength: contentLength):
            var headers: [String: String] = [:]
            if let contentLength { headers["Content-Length"] = "\(contentLength)" }
            guard let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            // A real server sends a body over time: deliver it a chunk at a time, so a client
            // that cancels on the response or mid-body is seen to stop the transfer. Delivered
            // all at once inside `startLoading`, the load finished before any cancel arrived.
            deliver(chunks, from: 0, url: url)
        }
    }

    private func deliver(_ chunks: [Data], from index: Int, url: URL) {
        Self.queue.asyncAfter(deadline: .now() + 0.05) { [self] in
            guard !isCancelled else { return }
            if index < chunks.count {
                client?.urlProtocol(self, didLoad: chunks[index])
                deliver(chunks, from: index + 1, url: url)
            } else {
                Self.finishedURLs.append(url)
                client?.urlProtocolDidFinishLoading(self)
            }
        }
    }

    private static let queue = DispatchQueue(label: "ImageStubProtocol")
    private let lock = NSLock()
    private var isCancelled: Bool { lock.withLock { cancelled } }

    override func stopLoading() {
        lock.withLock { cancelled = true }
    }
}

private final class AO3ImageStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var data = Data()
    nonisolated(unsafe) static var requestedURLs: [URL] = []
    nonisolated(unsafe) static var userAgents: [String] = []

    static func reset(data: Data) {
        self.data = data
        requestedURLs = []
        userAgents = []
    }

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "image/png"]
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.requestedURLs.append(url)
        if let userAgent = request.value(forHTTPHeaderField: "User-Agent") {
            Self.userAgents.append(userAgent)
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
