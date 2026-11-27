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
        <w:p><w:hyperlink r:id="rId2"><w:r><w:t>split</w:t></w:r></w:hyperlink></w:p>
        <w:p><w:hyperlink r:id="rId3"><w:r><w:t>quoted</w:t></w:r></w:hyperlink></w:p>
        """
        let relationships = """
        <Relationship Id="rId1" Type="x/hyperlink" Target="javascript:alert(1)" TargetMode="External"/>\
        <Relationship Id="rId2" Type="x/hyperlink" Target="https://example.com/a&#10;b" TargetMode="External"/>\
        <Relationship Id="rId3" Type="x/hyperlink" \
        Target="https://example.com/a&quot;onclick=&quot;alert(1)" TargetMode="External"/>
        """
        let html = try Self.html(body: body, relationships: relationships)
        #expect(html.contains("<p>click</p>"))
        #expect(html.contains("<p>jump</p>"))
        #expect(html.contains("<p>split</p>"))
        #expect(html.contains(
            "<p><a href=\"https://example.com/a&quot;onclick=&quot;alert(1)\">quoted</a></p>"
        ))
        #expect(!html.contains("javascript:"))
        #expect(!html.contains("onclick=\""))
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

    @Test func oneRunCanCarryEveryMarkAndRepeatedRunsMerge() throws {
        let both = """
        <w:p><w:r><w:rPr><w:b/><w:i/><w:u w:val="single"/><w:strike/></w:rPr><w:t>x</w:t></w:r></w:p>
        """
        #expect(try Self.html(body: both) == "<p><strong><em><u><s>x</s></u></em></strong></p>")

        let runs = String(repeating: "<w:r><w:rPr><w:b/></w:rPr><w:t>a</w:t></w:r>", count: 400)
        let merged = try Self.html(body: "<w:p>\(runs)</w:p>")
        #expect(merged == "<p><strong>\(String(repeating: "a", count: 400))</strong></p>")
    }

    @Test func smartQuotesSurviveAndStraightQuotesAreEscaped() throws {
        let body = """
        <w:p><w:r><w:t>\u{2018}Hi\u{2019} and \u{201C}there\u{201D}</w:t></w:r></w:p>
        <w:p><w:r><w:t>say "hi"</w:t></w:r></w:p>
        """
        let html = try Self.html(body: body)
        #expect(html.contains("\u{2018}Hi\u{2019} and \u{201C}there\u{201D}"))
        #expect(html.contains("say &quot;hi&quot;"))
        #expect(!html.contains("say \"hi\""))
    }

    @Test func tabsBreaksAndOutlineLevel() throws {
        let body = """
        <w:p><w:r><w:t>A</w:t><w:tab/><w:t>B</w:t><w:br/><w:t>C</w:t></w:r></w:p>
        <w:p><w:r><w:t>Hello</w:t></w:r><w:r><w:br w:type="page"/></w:r><w:r><w:t>world</w:t></w:r></w:p>
        <w:p><w:r><w:t>Next</w:t></w:r><w:r><w:br w:type="column"/></w:r></w:p>
        <w:p><w:pPr><w:outlineLvl w:val="1"/></w:pPr><w:r><w:t>Section</w:t></w:r></w:p>
        <w:p><w:pPr><w:outlineLvl w:val="9"/></w:pPr><w:r><w:t>Body</w:t></w:r></w:p>
        <w:p><w:pPr><w:pStyle w:val="Heading3"/><w:outlineLvl w:val="0"/></w:pPr><w:r><w:t>Kept</w:t></w:r></w:p>
        <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Slack</w:t><w:br/><w:t>Water</w:t></w:r></w:p>
        """
        let result = try StudioDocxImport.convertToHTML(
            docxData: Self.docx(body: body),
            fallbackTitle: "   "
        )
        #expect(result.bodyHTML == """
        <p>A B<br>C</p>
        <p>Hello world</p>
        <p>Next</p>
        <h2>Section</h2>
        <p>Body</p>
        <h3>Kept</h3>
        <h1>Slack<br>Water</h1>
        """)
        // The first block is not a heading, and the file name was blank.
        #expect(result.title == "Untitled")

        let brokenHeading = """
        <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>\
        <w:r><w:t>Slack</w:t><w:br/><w:t>Water</w:t></w:r></w:p>
        """
        let titled = try StudioDocxImport.convertToHTML(
            docxData: Self.docx(body: brokenHeading),
            fallbackTitle: "File"
        )
        #expect(titled.title == "Slack Water")
        #expect(titled.bodyHTML == "<h1>Slack<br>Water</h1>")
    }

    @Test func hyperlinkFieldsKeepTheVisibleTextAndTheURL() throws {
        let body = """
        <w:p><w:r><w:t xml:space="preserve">See </w:t></w:r>\
        <w:fldSimple w:instr=" HYPERLINK &quot;https://example.com/chart&quot; \\o &quot;tip&quot; ">\
        <w:r><w:t>the chart</w:t></w:r></w:fldSimple><w:r><w:t xml:space="preserve"> and </w:t></w:r>\
        <w:r><w:fldChar w:fldCharType="begin"/></w:r>\
        <w:r><w:instrText xml:space="preserve"> HYPERLINK "https://example.org/log" </w:instrText></w:r>\
        <w:r><w:fldChar w:fldCharType="separate"/></w:r>\
        <w:r><w:t>the log</w:t></w:r>\
        <w:r><w:fldChar w:fldCharType="end"/></w:r><w:r><w:t>.</w:t></w:r></w:p>
        <w:p><w:r><w:fldChar w:fldCharType="begin"/></w:r>\
        <w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>\
        <w:r><w:fldChar w:fldCharType="separate"/></w:r>\
        <w:r><w:t>12</w:t></w:r>\
        <w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>
        <w:p><w:fldSimple w:instr=" HYPERLINK &quot;javascript:alert(1)&quot; ">\
        <w:r><w:t>nope</w:t></w:r></w:fldSimple></w:p>
        <w:p><w:r><w:t xml:space="preserve">Keep </w:t></w:r>\
        <w:del w:id="1" w:author="Lark"><w:r><w:fldChar w:fldCharType="begin"/></w:r>\
        <w:r><w:delInstrText> HYPERLINK "https://evil.example/secret" </w:delInstrText></w:r>\
        <w:r><w:delText>gone</w:delText></w:r></w:del><w:r><w:t>end</w:t></w:r></w:p>
        """
        let html = try Self.html(body: body)
        #expect(html.contains(
            "<p>See <a href=\"https://example.com/chart\">the chart</a> and <a href=\"https://example.org/log\">the log</a>.</p>"
        ))
        #expect(html.contains("<p>12</p>"))
        #expect(!html.contains("PAGE"))
        #expect(!html.contains("tip"))
        #expect(html.contains("<p>nope</p>"))
        #expect(!html.contains("javascript:"))
        #expect(!html.contains("evil.example"))
        #expect(!html.contains("gone"))
        #expect(html.contains("<p>Keep end</p>"))
    }

    @Test func deletedParagraphMarksJoinAndMovesDoNotDuplicate() throws {
        let body = """
        <w:p><w:pPr><w:pStyle w:val="Heading1"/>\
        <w:rPr><w:del w:id="1" w:author="Lark"/></w:rPr></w:pPr>\
        <w:r><w:t xml:space="preserve">Slack </w:t></w:r></w:p>
        <w:p><w:r><w:t>Water</w:t></w:r></w:p>
        <w:p><w:r><w:t xml:space="preserve">The </w:t></w:r>\
        <w:moveFrom w:id="11" w:author="Lark"><w:r><w:t xml:space="preserve">cold </w:t></w:r></w:moveFrom>\
        <w:r><w:t>wind</w:t></w:r></w:p>
        <w:p><w:r><w:t xml:space="preserve">The </w:t></w:r>\
        <w:moveTo w:id="13" w:author="Lark"><w:r><w:t xml:space="preserve">cold </w:t></w:r></w:moveTo>\
        <w:r><w:t>water</w:t></w:r></w:p>
        <w:tbl><w:tr>\
        <w:tc><w:p><w:pPr><w:rPr><w:del w:id="2" w:author="Lark"/></w:rPr></w:pPr>\
        <w:r><w:t>One</w:t></w:r></w:p></w:tc>\
        <w:tc><w:p><w:r><w:t>Two</w:t></w:r></w:p></w:tc>\
        </w:tr></w:tbl>
        <w:p><w:pPr><w:rPr><w:del w:id="4" w:author="Lark"/></w:rPr></w:pPr>\
        <w:r><w:t xml:space="preserve">Keep </w:t></w:r></w:p>
        <w:p><w:pPr><w:pStyle w:val="Heading2"/></w:pPr><w:r><w:t>style</w:t></w:r></w:p>
        <w:p><w:pPr><w:rPr><w:del w:id="9" w:author="Lark"/></w:rPr></w:pPr>\
        <w:r><w:t>Last</w:t></w:r></w:p>
        """
        let result = try StudioDocxImport.convertToHTML(
            docxData: Self.docx(body: body),
            fallbackTitle: "File"
        )
        #expect(result.title == "Slack Water")
        #expect(result.bodyHTML == """
        <h1>Slack Water</h1>
        <p>The wind</p>
        <p>The cold water</p>
        <p>One</p>
        <p>Two</p>
        <p>Keep style</p>
        <p>Last</p>
        """)
    }

    @Test func scriptsDrawingsAndExternalEntitiesStayOutOfTheChapter() throws {
        let secret = "EXTERNAL_ENTITY_SECRET_9f3c"
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("studio-docx-xxe-\(UUID().uuidString).txt")
        try Data(secret.utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let drawing = """
        <w:p><w:r><w:drawing><w:t>hidden caption</w:t></w:drawing><w:t>Caption</w:t></w:r></w:p>
        <w:p><w:r><w:t>&lt;script&gt;alert(1)&lt;/script&gt;</w:t></w:r></w:p>
        """
        let drawn = try Self.html(body: drawing, relationships: """
        <Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" \
        Target="https://evil.example/pixel.png" TargetMode="External"/>
        """)
        #expect(drawn.contains("<p>Caption</p>"))
        #expect(drawn.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        #expect(!drawn.contains("<script"))
        #expect(!drawn.contains("<img"))
        #expect(!drawn.contains("evil.example"))
        #expect(!drawn.contains("hidden caption"))

        let system = fileURL.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
        let xml = """
        <?xml version="1.0"?>\
        <!DOCTYPE document [<!ENTITY xxe SYSTEM "\(system)">]>\
        <document><p><r><t>before &xxe; after</t></r></p></document>
        """
        let data = try MiniZip.archiveData([("word/document.xml", Data(xml.utf8))])
        do {
            let html = try StudioDocxImport.convertToHTML(docxData: data, fallbackTitle: "T").bodyHTML
            #expect(html.contains("before"))
            // XMLParser stops at an external entity it won't resolve, so text after it in a hostile file is lost;
            // what matters is that the file it names never reaches the chapter
            #expect(!html.contains(secret))
        } catch {
            #expect(!String(describing: error).contains(secret))
        }
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
                <?xml version="1.0"?>\
                <!DOCTYPE document [<!ENTITY a "ENTITY_PAYLOAD_SHOULD_NOT_APPEAR">]>\
                <document><p><r><t>&a;</t></r></p></document>
                """.utf8))])
            )
            let oversized = try write("huge.docx", Data(count: BetaDOCXReader.maxFileBytes + 1))

            for url in [notAZip, truncated, noBody, badXML, entityBomb] {
                do {
                    _ = try await StudioDocumentImporter.importFile(at: url, into: store)
                    Issue.record("\(url.lastPathComponent) should have been refused")
                } catch let error as BetaReadingError {
                    let message = error.errorDescription ?? ""
                    #expect(!message.isEmpty)
                    if url.lastPathComponent == "entities.docx" {
                        #expect(message.localizedCaseInsensitiveContains("entity"))
                        #expect(!message.contains("ENTITY_PAYLOAD_SHOULD_NOT_APPEAR"))
                    }
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
