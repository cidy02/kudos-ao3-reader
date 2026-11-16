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
        let fetch: @Sendable (URL) async -> Data? = { $0.lastPathComponent == "map.png" ? Self.png : nil }
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
        let data = try #require(try await AO3HTMLDownloadConverter.epub(fromHTML: html, fetchImage: { _ in nil }))
        let url = try write(data)
        defer { try? FileManager.default.removeItem(at: url) }
        let extracted = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: extracted) }

        let document = try EPUBDocument.open(epubURL: url, into: extracted)
        #expect(document.chapters.map(\.title) == ["Preface", "One Shot", "Afterword"])
        #expect(try EPUBDocument.metadata(ofEPUBAt: url).author == "Anonymous")
        #expect(try text(MiniZip(data: data), "OEBPS/chapter-2.xhtml").contains("All of it, at once."))
    }

    @Test func anOrdinaryPageIsNotABook() async throws {
        #expect(try await AO3HTMLDownloadConverter.epub(fromHTML: Self.workPage("html"), fetchImage: { _ in nil }) == nil)
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
}

/// AO3 with EPUB withdrawn: an EPUB request gets a page in its place, as
/// `DownloadsController#show` sends when a format cannot be made. No request leaves
/// the process.
private final class HTMLOnlyAO3: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var page = ""
    nonisolated(unsafe) static var html = ""
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var paths: [String] = []

    static func reset(page: String, html: String, status: Int = 200) {
        self.page = page
        self.html = html
        self.status = status
        paths = []
    }

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url, statusCode: Self.status, httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "text/html; charset=utf-8"]
              )
        else {
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
