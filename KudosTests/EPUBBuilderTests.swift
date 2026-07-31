import Foundation
import Testing
@testable import Kudos

/// Tests that `EPUBBuilder` produces archives the app's *own* EPUB stack accepts.
///
/// The real contract is not "looks like an EPUB" but "round-trips through the
/// same readers a downloaded AO3 EPUB does", so these assertions deliberately go
/// through `MiniZip`, `EPUBDocument.metadata` and `EPUBDocument.inspectPackage`
/// rather than inspecting the generated strings.
struct EPUBBuilderTests {
    private func write(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("epub")
        try data.write(to: url)
        return url
    }

    private func sampleArchive(
        title: String = "Converted Work",
        author: String = "Some Author",
        summary: String = "A summary.",
        sourceURL: String = "",
        subjects: [String] = [],
        chapters: [EPUBBuilder.Chapter] = [
            .init(title: "Chapter 1", bodyXHTML: "<p>First.</p>"),
            .init(title: "Chapter 2", bodyXHTML: "<p>Second.</p>")
        ]
    ) throws -> Data {
        try EPUBBuilder.archive(
            metadata: .init(
                title: title,
                author: author,
                summary: summary,
                sourceURL: sourceURL,
                subjects: subjects,
                identifier: "pinned-identifier"
            ),
            chapters: chapters,
            modified: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func mimetypeIsTheFirstEntryAndStoredUncompressed() throws {
        // EPUB requires `mimetype` first and uncompressed. Assert on the raw
        // bytes rather than via MiniZip, because a reader that tolerates a
        // misplaced entry would hide exactly the defect this guards. A ZIP local
        // file header is a fixed 30 bytes, then the name, then the payload.
        let bytes = Array(try sampleArchive().prefix(58))
        #expect(Array(bytes[0..<4]) == [0x50, 0x4B, 0x03, 0x04]) // "PK\u{03}\u{04}"
        #expect(bytes[8] == 0 && bytes[9] == 0) // compression method: stored
        #expect(String(bytes: bytes[30..<38], encoding: .utf8) == "mimetype")
        #expect(String(bytes: bytes[38..<58], encoding: .utf8) == "application/epub+zip")
    }

    @Test func archiveCarriesEveryExpectedEntry() throws {
        let zip = try MiniZip(data: try sampleArchive())
        #expect(zip.names.contains("mimetype"))
        #expect(zip.names.contains("META-INF/container.xml"))
        #expect(zip.names.contains("OEBPS/content.opf"))
        #expect(zip.names.contains("OEBPS/nav.xhtml"))
        #expect(zip.names.contains("OEBPS/chapter-1.xhtml"))
        #expect(zip.names.contains("OEBPS/chapter-2.xhtml"))
    }

    @Test func metadataRoundTripsThroughTheAppsOwnParser() throws {
        let url = try write(try sampleArchive(
            sourceURL: "https://archiveofourown.org/works/12345",
            subjects: ["Fluff", "Angst"]
        ))
        defer { try? FileManager.default.removeItem(at: url) }

        let meta = try EPUBDocument.metadata(ofEPUBAt: url)
        #expect(meta.title == "Converted Work")
        #expect(meta.author == "Some Author")
        #expect(meta.summary == "A summary.")
        #expect(meta.language == "en")
        #expect(meta.subjects.contains("Fluff"))
        #expect(meta.subjects.contains("Angst"))
        // dc:source is how a converted file keeps its AO3 identity, so that the
        // importer can still resolve an ao3WorkID and refresh tags later.
        #expect(meta.sourceURL == "https://archiveofourown.org/works/12345")
    }

    @Test func spineIsReadableAndInOrder() throws {
        let url = try write(try sampleArchive())
        defer { try? FileManager.default.removeItem(at: url) }

        let package = try EPUBDocument.inspectPackage(ofEPUBAt: url)
        #expect(package.readableItemCount == 2)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let document = try EPUBDocument.open(epubURL: url, into: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(document.spineURLs.count == 2)
        #expect(document.spineURLs[0].lastPathComponent == "chapter-1.xhtml")
        #expect(document.spineURLs[1].lastPathComponent == "chapter-2.xhtml")
        // The nav document drives the TOC for both readers.
        #expect(document.chapters.map(\.title) == ["Chapter 1", "Chapter 2"])
    }

    @Test func metadataNeedingEscapesStaysWellFormedXML() throws {
        let url = try write(try sampleArchive(
            title: "Fish & <Chips> \"Quoted\"",
            author: "A & B",
            summary: "5 < 6 & 7 > 3",
            subjects: ["Tag <with> markup"],
            chapters: [.init(title: "Ch & 1", bodyXHTML: "<p>Body.</p>")]
        ))
        defer { try? FileManager.default.removeItem(at: url) }

        // Unescaped metadata would make XMLParser fail outright, so a successful
        // parse plus exact values is the assertion.
        let meta = try EPUBDocument.metadata(ofEPUBAt: url)
        #expect(meta.title == "Fish & <Chips> \"Quoted\"")
        #expect(meta.author == "A & B")
        #expect(meta.summary == "5 < 6 & 7 > 3")
        #expect(meta.subjects.contains("Tag <with> markup"))
    }

    @Test func chapterTitlesNeedingEscapesSurviveInTheTOC() throws {
        let url = try write(try sampleArchive(
            chapters: [.init(title: "Ch 1: A & B <c>", bodyXHTML: "<p>Body.</p>")]
        ))
        defer { try? FileManager.default.removeItem(at: url) }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let document = try EPUBDocument.open(epubURL: url, into: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(document.chapters.map(\.title) == ["Ch 1: A & B <c>"])
    }

    @Test func theArchiveStatesItsOwnWordCount() throws {
        // Nothing downstream can otherwise know an imported work's length: word count
        // normally comes from AO3's stats page, which a non-AO3 work never has, so it
        // stayed 0 and the card omitted it.
        let url = try write(try sampleArchive(chapters: [
            .init(title: "One", bodyXHTML: "<p>One two three four five.</p>"),
            .init(title: "Two", bodyXHTML: "<p>Six seven</p><p>eight nine ten.</p>")
        ]))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try EPUBDocument.metadata(ofEPUBAt: url).wordCount == 10)
    }

    @Test func markupDoesNotInflateTheWordCount() throws {
        // Tags are stripped first, so a heavily marked-up paragraph is not counted as
        // longer than it reads.
        let url = try write(try sampleArchive(chapters: [
            .init(title: "One", bodyXHTML: "<p><em>Two</em> <strong>words</strong></p>")
        ]))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try EPUBDocument.metadata(ofEPUBAt: url).wordCount == 2)
    }

    @Test func emptyChapterListIsRejected() {
        #expect(throws: EPUBBuilder.BuildError.noChapters) {
            _ = try EPUBBuilder.archive(metadata: .init(title: "Empty"), chapters: [])
        }
    }

    @Test func pinnedInputsProduceIdenticalBytes() throws {
        // Reproducibility matters for dedup: re-converting the same source file
        // must not look like a different work. MiniZip already writes a fixed DOS
        // timestamp, so only the identifier and `dcterms:modified` could vary.
        let first = try sampleArchive()
        let second = try sampleArchive()
        #expect(first == second)
    }

    @Test func missingLanguageFallsBackToEnglish() throws {
        let data = try EPUBBuilder.archive(
            metadata: .init(title: "No Language", language: "", identifier: "pinned"),
            chapters: [.init(title: "One", bodyXHTML: "<p>x</p>")],
            modified: Date(timeIntervalSince1970: 0)
        )
        let url = try write(data)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try EPUBDocument.metadata(ofEPUBAt: url).language == "en")
    }
}
