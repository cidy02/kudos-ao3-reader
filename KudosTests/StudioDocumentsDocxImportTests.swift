import Foundation
import Testing
@testable import Kudos

/// Import a Document: Word (`.docx`) → AO3 HTML (T-574). Hand-zipped XML with `MiniZip`, plus
/// one round trip through the beta lane's `BetaDOCXWriter`. No network, no AO3.
struct StudioDocumentsDocxImportTests {
    private static let namespaces = """
    xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" \
    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    """

    private static func documentXML(_ body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
        <w:document \(namespaces)><w:body>\(body)</w:body></w:document>
        """
    }

    private static func docx(
        body: String,
        relationships: String? = nil,
        extra: [(name: String, data: Data)] = []
    ) throws -> Data {
        var entries: [(name: String, data: Data)] = [
            ("word/document.xml", Data(documentXML(body).utf8)),
        ]
        if let relationships {
            let xml = """
            <?xml version="1.0" encoding="UTF-8"?>\
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
            \(relationships)</Relationships>
            """
            entries.append(("word/_rels/document.xml.rels", Data(xml.utf8)))
        }
        return try MiniZip.archiveData(entries + extra)
    }

    private static func html(body: String, relationships: String? = nil) throws -> String {
        try StudioDocxImport.convertToHTML(
            docxData: docx(body: body, relationships: relationships),
            fallbackTitle: "File Name"
        ).bodyHTML
    }

    private static func withTempStore(
        _ work: (WritingDocumentStore, URL) async throws -> Void
    ) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("studio-docx-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = WritingDocumentStore(root: root, deviceID: "test-device", now: { Date() })
        try await work(store, root)
    }

    // MARK: - Content

    @Test func paragraphsHeadingsFormattingLinksAndBreaksBecomeHTML() throws {
        let body = """
        <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Slack Water</w:t></w:r></w:p>
        <w:p><w:pPr><w:pStyle w:val="Heading2"/></w:pPr><w:r><w:t>Part two</w:t></w:r></w:p>
        <w:p><w:r><w:t xml:space="preserve">Ines &amp; </w:t></w:r><w:r><w:t xml:space="preserve">Marta saw </w:t></w:r>\
        <w:r><w:rPr><w:i/></w:rPr><w:t>italic</w:t></w:r><w:r><w:t xml:space="preserve">, </w:t></w:r>\
        <w:r><w:rPr><w:b/></w:rPr><w:t>bold</w:t></w:r><w:r><w:t xml:space="preserve">, </w:t></w:r>\
        <w:r><w:rPr><w:u w:val="single"/></w:rPr><w:t>underlined</w:t></w:r><w:r><w:t xml:space="preserve">, </w:t></w:r>\
        <w:r><w:rPr><w:strike/></w:rPr><w:t>struck</w:t></w:r><w:r><w:t xml:space="preserve"> and </w:t></w:r>\
        <w:hyperlink r:id="rId9"><w:r><w:t>the chart</w:t></w:r></w:hyperlink><w:r><w:t>.</w:t></w:r></w:p>
        <w:p><w:r><w:t>Low</w:t></w:r><w:r><w:br/></w:r><w:r><w:t>tide</w:t></w:r></w:p>
        <w:p><w:r><w:rPr><w:b w:val="0"/></w:rPr><w:t>Not bold.</w:t></w:r></w:p>
        <w:p><w:r><w:t xml:space="preserve">   </w:t></w:r></w:p>
        <w:p/>
        """
        let relationships = """
        <Relationship Id="rId9" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" \
        Target="https://example.com/tide?a=1&amp;b=2" TargetMode="External"/>
        """
        let result = try StudioDocxImport.convertToHTML(
            docxData: Self.docx(body: body, relationships: relationships),
            fallbackTitle: "File Name"
        )

        #expect(result.title == "Slack Water")
        let html = result.bodyHTML
        #expect(html.contains("<h1>Slack Water</h1>"))
        #expect(html.contains("<h2>Part two</h2>"))
        #expect(html.contains("Ines &amp; Marta saw <em>italic</em>, <strong>bold</strong>, "))
        #expect(html.contains("<u>underlined</u>, <s>struck</s> and "))
        #expect(html.contains("<a href=\"https://example.com/tide?a=1&amp;b=2\">the chart</a>."))
        #expect(html.contains("<p>Low<br>tide</p>"))
        #expect(html.contains("<p>Not bold.</p>"))
        // The blank paragraphs are spacing: three `<p>` blocks, none of them empty.
        #expect(html.components(separatedBy: "<p>").count - 1 == 3)
        #expect(!html.contains("<p></p>"))
    }

    @Test func unsafeLinkTargetsStayPlainText() throws {
        let body = """
        <w:p><w:hyperlink r:id="rId1"><w:r><w:t>click</w:t></w:r></w:hyperlink></w:p>
        <w:p><w:hyperlink w:anchor="top"><w:r><w:t>jump</w:t></w:r></w:hyperlink></w:p>
        """
        let relationships = """
        <Relationship Id="rId1" Type="x/hyperlink" Target="javascript:alert(1)" TargetMode="External"/>
        """
        let html = try Self.html(body: body, relationships: relationships)
        #expect(html.contains("click"))
        #expect(html.contains("jump"))
        #expect(!html.contains("<a"))
        #expect(!html.contains("javascript:"))
    }

    @Test func titleFallsBackToTheFileNameWithoutALeadingHeading() throws {
        let data = try Self.docx(body: "<w:p><w:r><w:t>Just prose.</w:t></w:r></w:p>")
        let result = try StudioDocxImport.convertToHTML(docxData: data, fallbackTitle: "File Name")
        #expect(result.title == "File Name")
        #expect(result.bodyHTML == "<p>Just prose.</p>")
    }

    // MARK: - Tracked changes and comments

    @Test func trackedDeletionsAreDroppedInsertionsKeptAndCommentsIgnored() throws {
        let body = """
        <w:p><w:commentRangeStart w:id="0"/><w:r><w:t xml:space="preserve">Keep </w:t></w:r>\
        <w:del w:id="1" w:author="Lark"><w:r><w:delText xml:space="preserve">gone </w:delText></w:r></w:del>\
        <w:ins w:id="2" w:author="Lark"><w:r><w:t xml:space="preserve">added </w:t></w:r></w:ins>\
        <w:r><w:t>end</w:t></w:r><w:commentRangeEnd w:id="0"/>\
        <w:r><w:commentReference w:id="0"/></w:r></w:p>
        <w:p><w:del w:id="3" w:author="Lark"><w:r><w:delText>Whole deleted paragraph</w:delText></w:r></w:del></w:p>
        """
        let comments = """
        <?xml version="1.0" encoding="UTF-8"?>\
        <w:comments \(Self.namespaces)><w:comment w:id="0" w:author="Lark">\
        <w:p><w:r><w:t>Lovely comment text</w:t></w:r></w:p></w:comment></w:comments>
        """
        let data = try Self.docx(body: body, extra: [("word/comments.xml", Data(comments.utf8))])
        let html = try StudioDocxImport.convertToHTML(docxData: data, fallbackTitle: "T").bodyHTML

        #expect(html == "<p>Keep added end</p>")
        #expect(!html.contains("gone"))
        #expect(!html.contains("Whole deleted"))
        #expect(!html.contains("Lovely comment"))
    }

    @Test func formattingChangeRecordsDoNotOverrideTheCurrentFormatting() throws {
        let body = """
        <w:p><w:r><w:rPr><w:b/><w:rPrChange w:id="1" w:author="Lark"><w:rPr><w:i/></w:rPr></w:rPrChange></w:rPr>\
        <w:t>now bold</w:t></w:r></w:p>
        """
        let html = try Self.html(body: body)
        #expect(html == "<p><strong>now bold</strong></p>")
    }

    // MARK: - Beta lane round trip

    @Test func theBetaWritersOwnDocxImportsBack() throws {
        let source = """
        <h1>Chapter Four</h1>\
        <p>Ines saw <em>it</em>, <strong>b</strong>, <u>u</u>, <s>s</s> and \
        <a href="https://example.com/tide">the chart</a>.</p>\
        <p>Low tide<br>again</p>
        """
        let data = try BetaDOCXWriter.writeDOCX(html: source, title: "Ch 4")
        let result = try StudioDocxImport.convertToHTML(docxData: data, fallbackTitle: "File Name")

        #expect(result.bodyHTML.contains("<h1>Chapter Four</h1>"))
        #expect(result.bodyHTML.contains("<em>it</em>"))
        #expect(result.bodyHTML.contains("<strong>b</strong>"))
        #expect(result.bodyHTML.contains("<u>u</u>"))
        #expect(result.bodyHTML.contains("<s>s</s>"))
        #expect(result.bodyHTML.contains("<a href=\"https://example.com/tide\">the chart</a>"))
        #expect(result.bodyHTML.contains("Low tide<br>again"))
    }

    // MARK: - Through the importer

    @Test func importFileCreatesADocumentFromADocx() async throws {
        try await Self.withTempStore { store, root in
            let url = root.appendingPathComponent("Slack_Water.DOCX")
            let body = "<w:p><w:r><w:rPr><w:i/></w:rPr><w:t>Hello</w:t></w:r></w:p>"
            try Self.docx(body: body).write(to: url)

            let imported = try await StudioDocumentImporter.importFile(at: url, into: store)
            #expect(imported.format == .docx)
            #expect(imported.work.title == "Slack Water")
            let loaded = try await store.loadChapter(workID: imported.work.id, chapterID: imported.chapter.id)
            #expect(loaded.bodyHTML.contains("<em>Hello</em>"))
        }
    }

    // MARK: - Refusals

    @Test func brokenOversizedAndEmptyFilesAreRefusedWithAMessageAndNothingIsCreated() async throws {
        try await Self.withTempStore { store, root in
            func write(_ name: String, _ data: Data) throws -> URL {
                let url = root.appendingPathComponent(name)
                try data.write(to: url)
                return url
            }

            let notAZip = try write("garbage.docx", Data("definitely not a zip".utf8))
            let truncated = try write("truncated.docx", Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00]))
            let noBody = try write(
                "nobody.docx",
                MiniZip.archiveData([("word/styles.xml", Data("<w:styles/>".utf8))])
            )
            let badXML = try write(
                "badxml.docx",
                MiniZip.archiveData([("word/document.xml", Data("<w:document><w:body><w:p>".utf8))])
            )
            let entityBomb = try write(
                "entities.docx",
                MiniZip.archiveData([("word/document.xml", Data("""
                <?xml version="1.0"?><!DOCTYPE d [<!ENTITY a "aaaa">]><w:document \(Self.namespaces)>\
                <w:body><w:p><w:r><w:t>&a;</w:t></w:r></w:p></w:body></w:document>
                """.utf8))])
            )
            let oversized = try write("huge.docx", Data(count: BetaDOCXReader.maxFileBytes + 1))

            for url in [notAZip, truncated, noBody, badXML, entityBomb] {
                do {
                    _ = try await StudioDocumentImporter.importFile(at: url, into: store)
                    Issue.record("\(url.lastPathComponent) should have been refused")
                } catch let error as BetaReadingError {
                    #expect(error.errorDescription?.isEmpty == false)
                } catch {
                    Issue.record("\(url.lastPathComponent): unexpected \(error)")
                }
            }

            let oversizedError = await #expect(throws: BetaReadingError.self) {
                _ = try await StudioDocumentImporter.importFile(at: oversized, into: store)
            }
            #expect(oversizedError == BetaReadingError.fileTooLarge(maxBytes: BetaDOCXReader.maxFileBytes))

            let blank = try write("blank.docx", Self.docx(body: "<w:p/><w:p><w:r><w:t> </w:t></w:r></w:p>"))
            await #expect(throws: StudioDocumentImportError.emptyDocument) {
                _ = try await StudioDocumentImporter.importFile(at: blank, into: store)
            }
            let empty = try write("empty.docx", Data())
            await #expect(throws: StudioDocumentImportError.emptyDocument) {
                _ = try await StudioDocumentImporter.importFile(at: empty, into: store)
            }

            let works = try await store.listWorks()
            #expect(works.isEmpty)
        }
    }

    @Test func theOldDocFormatIsStillRefusedWithAMessage() async throws {
        try await Self.withTempStore { store, root in
            let url = root.appendingPathComponent("old.doc")
            try Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0x00]).write(to: url)
            let error = await #expect(throws: StudioDocumentImportError.self) {
                _ = try await StudioDocumentImporter.importFile(at: url, into: store)
            }
            #expect(error?.errorDescription?.contains(".docx") == true)
        }
    }
}
