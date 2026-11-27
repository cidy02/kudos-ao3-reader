import Foundation
import Testing
@testable import Kudos

/// Unit tests for T-576f beta reading `.docx` writing, round-trip reading, Word and
/// Google Docs tracked changes/comments fixtures, untracked diffing, and LCS alignment.
/// Pure logic + MiniZip + XMLParser: no network, no AO3, no WebView.
struct BetaRoundTripTests {
    // MARK: - .docx writer (parts, track revisions, formatting, entities, links)

    @Test func docxWriterProducesValidPartsTrackChangesFormattingEntitiesAndLinks() throws {
        let html = """
        <h1>Chapter Four</h1>
        <p>Ines &amp; Marta saw <em>italic</em>, <strong>bold</strong>, <u>underlined</u>, \
        <s>struck</s>, H<sub>2</sub>O, x<sup>2</sup>, and \
        <a href="https://example.com/tide?a=1&amp;b=2">the chart</a>.</p>
        <p>Unsafe <a href="javascript:alert(1)">script link</a> stays plain text.</p>
        <blockquote><p>If the boat comes back, so does he.</p></blockquote>
        <ul><li>Oars</li><li>Lantern</li></ul>
        <ol><li>First check</li><li>Second check</li></ol>
        <hr />
        <p align="center">⁂</p>
        <p align="right">Signed &mdash; Ines<br />Low tide</p>
        """

        let fixedDate = Date(timeIntervalSince1970: 1_763_650_800)
        let data = try BetaDOCXWriter.writeDOCX(
            html: html,
            title: "Chapter 4 · Slack Water",
            author: "Author Name",
            date: fixedDate
        )
        let zip = try MiniZip(data: data, limits: .epub)
        let names = Set(zip.names)

        #expect(names.contains("[Content_Types].xml"))
        #expect(names.contains("_rels/.rels"))
        #expect(names.contains("word/document.xml"))
        #expect(names.contains("word/styles.xml"))
        #expect(names.contains("word/settings.xml"))
        #expect(names.contains("word/_rels/document.xml.rels"))
        #expect(names.contains("docProps/core.xml"))
        #expect(names.contains("word/numbering.xml"))

        let settingsXML = try utf8Entry("word/settings.xml", in: zip)
        #expect(settingsXML.contains("<w:trackRevisions/>"))

        let documentXML = try utf8Entry("word/document.xml", in: zip)
        #expect(documentXML.contains("<w:pStyle w:val=\"Heading1\"/>"))
        #expect(documentXML.contains("<w:pStyle w:val=\"Quote\"/>"))
        #expect(documentXML.contains("<w:pStyle w:val=\"ListParagraph\"/>"))
        #expect(documentXML.contains("<w:pStyle w:val=\"SceneBreak\"/>"))
        #expect(documentXML.contains("<w:i/>"))
        #expect(documentXML.contains("<w:b/>"))
        #expect(documentXML.contains("<w:u w:val=\"single\"/>"))
        #expect(documentXML.contains("<w:strike/>"))
        #expect(documentXML.contains("<w:vertAlign w:val=\"subscript\"/>"))
        #expect(documentXML.contains("<w:vertAlign w:val=\"superscript\"/>"))
        #expect(documentXML.contains("<w:jc w:val=\"center\"/>"))
        #expect(documentXML.contains("<w:jc w:val=\"right\"/>"))
        #expect(documentXML.contains("<w:br/>"))
        #expect(documentXML.contains("Ines &amp; Marta"))
        #expect(documentXML.contains("<w:hyperlink r:id="))
        #expect(!documentXML.contains("javascript:"))

        let relsXML = try utf8Entry("word/_rels/document.xml.rels", in: zip)
        #expect(relsXML.contains("Target=\"https://example.com/tide?a=1&amp;b=2\""))
        #expect(relsXML.contains("TargetMode=\"External\""))
        #expect(!relsXML.contains("javascript:"))

        let coreXML = try utf8Entry("docProps/core.xml", in: zip)
        #expect(coreXML.contains("<dc:title>Chapter 4 · Slack Water</dc:title>"))
        #expect(coreXML.contains("<dc:creator>Author Name</dc:creator>"))

        // Without lists, numbering.xml is omitted and only the 7 core parts are emitted.
        let plainData = try BetaDOCXWriter.writeDOCX(html: "<p>Just prose.</p>", title: "Ch 1")
        let plainZip = try MiniZip(data: plainData, limits: .epub)
        #expect(Set(plainZip.names) == [
            "[Content_Types].xml",
            "_rels/.rels",
            "word/document.xml",
            "word/styles.xml",
            "word/settings.xml",
            "word/_rels/document.xml.rels",
            "docProps/core.xml",
        ])
    }

    @Test func exportThenReadBackProducesIdenticalParagraphTextsAndZeroDiffs() throws {
        let html = """
        <h2>Slack Water</h2>
        <p>Ines counted the ribs of the hull twice &mdash; and then a third time.</p>
        <blockquote><p>Keep the lantern lit &amp; dry.</p></blockquote>
        <ul><li>Rope</li><li>Bucket</li></ul>
        <hr />
        <p align="center">⁂</p>
        <p>First line<br />Second line with <a href="https://example.org">a link</a>.</p>
        """

        let expectedTexts = BetaHTMLDocument.parse(html).map(\.plainText)
        let docxData = try BetaDOCXWriter.writeDOCX(html: html, title: "Slack Water")
        let parsed = try BetaDOCXReader.read(docxData: docxData)

        let actualTexts = parsed.paragraphs.map(\.finalText)
        #expect(actualTexts == expectedTexts)
        #expect(parsed.paragraphs.map(\.baselineText) == expectedTexts)
        #expect(parsed.comments.isEmpty)

        let comparison = BetaComparisonEngine.compare(
            sentHTML: html,
            returned: parsed,
            betaName: "Lark"
        )
        #expect(comparison.suggestions.isEmpty)
        #expect(comparison.comments.isEmpty)
    }

    // MARK: - Word & Google Docs tracked changes + comments fixtures

    @Test func readerParsesMicrosoftWordTrackedChangesAndCommentsFixture() throws {
        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:pPr><w:rPr><w:ins w:id="99" w:author="Lark" w:date="2026-11-20T14:30:00Z"/></w:rPr></w:pPr>
              <w:r><w:t xml:space="preserve">Ines counted the ribs of the hull twice, </w:t></w:r>
              <w:del w:id="1" w:author="Lark" w:date="2026-11-20T14:32:00Z">
                <w:r><w:delText xml:space="preserve">and then a third time,</w:delText></w:r>
              </w:del>
              <w:ins w:id="2" w:author="Lark" w:date="2026-11-20T14:32:00Z">
                <w:r><w:t xml:space="preserve">then once more,</w:t></w:r>
              </w:ins>
              <w:r><w:t xml:space="preserve"> because </w:t></w:r>
              <w:commentRangeStart w:id="7"/>
              <w:r><w:t>the number would not stay still</w:t></w:r>
              <w:commentRangeEnd w:id="7"/>
              <w:r><w:commentReference w:id="7"/></w:r>
              <w:r><w:t>.</w:t></w:r>
            </w:p>
          </w:body>
        </w:document>
        """
        let commentsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:comments xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:comment w:id="7" w:author="Lark" w:date="2026-11-20T15:00:00Z" w:initials="L">
            <w:p><w:r><w:t>This line got me. Keep it exactly like this.</w:t></w:r></w:p>
          </w:comment>
        </w:comments>
        """

        let parsed = try BetaDOCXReader.parse(
            documentXML: Data(documentXML.utf8),
            commentsXML: Data(commentsXML.utf8)
        )
        #expect(parsed.paragraphs.count == 1)
        let para = try #require(parsed.paragraphs.first)
        let expectedBaseline = "Ines counted the ribs of the hull twice, "
            + "and then a third time, because the number would not stay still."
        let expectedFinal = "Ines counted the ribs of the hull twice, "
            + "then once more, because the number would not stay still."
        #expect(para.baselineText == expectedBaseline)
        #expect(para.finalText == expectedFinal)

        #expect(parsed.comments.count == 1)
        let comment = try #require(parsed.comments.first)
        #expect(comment.id == "7")
        #expect(comment.author == "Lark")
        #expect(comment.initials == "L")
        #expect(comment.date != nil)
        #expect(comment.quote == "the number would not stay still")
        #expect(comment.text == "This line got me. Keep it exactly like this.")

        let sentHTML = "<p>\(para.baselineText)</p>"
        let comparison = BetaComparisonEngine.compare(
            sentHTML: sentHTML,
            returned: parsed,
            betaName: "Lark"
        )
        #expect(comparison.suggestions.count == 1)
        let suggestion = try #require(comparison.suggestions.first)
        #expect(suggestion.author == "Lark")
        #expect(suggestion.isTracked)
        #expect(suggestion.date != nil)
        #expect(suggestion.deletedText == "and then a third time,")
        #expect(suggestion.insertedText == "then once more,")

        #expect(comparison.comments.count == 1)
        let expectedNote = "Lark: This line got me. Keep it exactly like this."
        #expect(comparison.comments.first?.annotationNoteText == expectedNote)
    }

    @Test func readerParsesGoogleDocsShapeTrackedChangesAndMultiParagraphCommentsFixture() throws {
        // Google Docs uses 0-based ids, fractional-second dates, split consecutive w:ins,
        // ins-before-del order, optional missing initials, and multi-paragraph comments.
        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" \
        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006">
          <w:body>
            <w:p>
              <w:r><w:t xml:space="preserve">The harbour was </w:t></w:r>
              <w:ins w:id="0" w:author="nightjar" w:date="2026-11-22T09:15:30.456Z">
                <w:r><w:t xml:space="preserve">dead </w:t></w:r>
              </w:ins>
              <w:ins w:id="1" w:author="nightjar" w:date="2026-11-22T09:15:31.012Z">
                <w:r><w:t xml:space="preserve">quiet</w:t></w:r>
              </w:ins>
              <w:del w:id="2" w:author="nightjar" w:date="2026-11-22T09:15:31.012Z">
                <w:r><w:delText>silent</w:delText></w:r>
              </w:del>
              <w:r><w:t xml:space="preserve"> at </w:t></w:r>
              <w:commentRangeStart w:id="0"/>
              <w:r><w:t>slack water</w:t></w:r>
              <w:commentRangeEnd w:id="0"/>
              <w:r><w:commentReference w:id="0"/></w:r>
              <w:r><w:t>.</w:t></w:r>
              <mc:Fallback><w:r><w:t>IGNORED FALLBACK</w:t></w:r></mc:Fallback>
            </w:p>
          </w:body>
        </w:document>
        """
        let commentsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:comments xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:comment w:id="0" w:author="nightjar" w:date="2026-11-22T09:20:00.789Z">
            <w:p><w:r><w:t>Love this detail.</w:t></w:r></w:p>
            <w:p><w:r><w:t>Matches chapter 1.</w:t></w:r></w:p>
          </w:comment>
        </w:comments>
        """

        let parsed = try BetaDOCXReader.parse(
            documentXML: Data(documentXML.utf8),
            commentsXML: Data(commentsXML.utf8)
        )
        let para = try #require(parsed.paragraphs.first)
        #expect(para.baselineText == "The harbour was silent at slack water.")
        #expect(para.finalText == "The harbour was dead quiet at slack water.")

        let comment = try #require(parsed.comments.first)
        #expect(comment.id == "0")
        #expect(comment.author == "nightjar")
        #expect(comment.initials == nil)
        #expect(comment.date != nil)
        #expect(comment.quote == "slack water")
        #expect(comment.text == "Love this detail.\nMatches chapter 1.")

        let sentHTML = "<p>The harbour was silent at slack water.</p>"
        let comparison = BetaComparisonEngine.compare(
            sentHTML: sentHTML,
            returned: parsed,
            betaName: "nightjar"
        )
        #expect(comparison.suggestions.count == 1)
        let suggestion = try #require(comparison.suggestions.first)
        #expect(suggestion.author == "nightjar")
        #expect(suggestion.isTracked)
        #expect(suggestion.deletedText == "silent")
        #expect(suggestion.insertedText == "dead quiet")
    }

    // MARK: - Untracked edits & paragraph alignment

    @Test func untrackedEditsAreCaughtByWordByWordDiff() throws {
        let sentHTML = "<p>The quick brown fox jumped over the old lazy dog.</p>"
        let returnedXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>The swift red fox jumped over the lazy dog.</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """
        let returned = try BetaDOCXReader.parse(documentXML: Data(returnedXML.utf8))
        let comparison = BetaComparisonEngine.compare(
            sentHTML: sentHTML,
            returned: returned,
            betaName: "Lark"
        )

        #expect(comparison.suggestions.count == 2)
        let first = comparison.suggestions[0]
        let second = comparison.suggestions[1]
        #expect(!first.isTracked)
        #expect(first.author == "Lark")
        #expect(first.deletedText == "quick brown")
        #expect(first.insertedText == "swift red")

        #expect(!second.isTracked)
        #expect(second.author == "Lark")
        #expect(second.deletedText == "old ")
        #expect(second.insertedText.isEmpty)
    }

    @Test func mixedTrackedAndUntrackedEditsInSameParagraphAreBothCaptured() throws {
        let sentHTML = "<p>Marta walked slowly to the old pier.</p>"
        let returnedXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:r><w:t xml:space="preserve">Marta ran slowly to the </w:t></w:r>
              <w:del w:id="1" w:author="Lark"><w:r><w:delText>old</w:delText></w:r></w:del>
              <w:ins w:id="2" w:author="Lark"><w:r><w:t>weathered</w:t></w:r></w:ins>
              <w:r><w:t xml:space="preserve"> pier.</w:t></w:r>
            </w:p>
          </w:body>
        </w:document>
        """
        let returned = try BetaDOCXReader.parse(documentXML: Data(returnedXML.utf8))
        let comparison = BetaComparisonEngine.compare(
            sentHTML: sentHTML,
            returned: returned,
            betaName: "Lark"
        )

        #expect(comparison.suggestions.count == 2)
        #expect(comparison.suggestions[0].deletedText == "walked")
        #expect(comparison.suggestions[0].insertedText == "ran")
        #expect(!comparison.suggestions[0].isTracked)

        #expect(comparison.suggestions[1].deletedText == "old")
        #expect(comparison.suggestions[1].insertedText == "weathered")
        #expect(comparison.suggestions[1].isTracked)
    }

    @Test func lcsParagraphAlignmentDoesNotShiftWhenParagraphIsRemovedOrAdded() throws {
        let sentHTML = """
        <p>Opening paragraph about the harbour.</p>
        <p>Second paragraph that the beta removes.</p>
        <p>Third paragraph with a small typo.</p>
        <p>Closing paragraph at sunset.</p>
        """

        // Case 1: Paragraph 1 removed, tracked edit inside paragraph 2.
        let removedXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>Opening paragraph about the harbour.</w:t></w:r></w:p>
            <w:p>
              <w:r><w:t xml:space="preserve">Third paragraph with a </w:t></w:r>
              <w:del w:id="1" w:author="Lark"><w:r><w:delText>small</w:delText></w:r></w:del>
              <w:ins w:id="2" w:author="Lark"><w:r><w:t>tiny</w:t></w:r></w:ins>
              <w:r><w:t xml:space="preserve"> typo.</w:t></w:r>
            </w:p>
            <w:p><w:r><w:t>Closing paragraph at sunset.</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """
        let removedDoc = try BetaDOCXReader.parse(documentXML: Data(removedXML.utf8))
        let removedCmp = BetaComparisonEngine.compare(sentHTML: sentHTML, returned: removedDoc, betaName: "Lark")

        #expect(removedCmp.suggestions.count == 2)
        // Paragraph 1 deletion.
        #expect(removedCmp.suggestions[0].paragraphIndex == 1)
        #expect(removedCmp.suggestions[0].deletedText == "Second paragraph that the beta removes.")
        #expect(removedCmp.suggestions[0].insertedText.isEmpty)
        // Paragraph 2 edit stays aligned at sent index 2 (not shifted to 1!).
        #expect(removedCmp.suggestions[1].paragraphIndex == 2)
        #expect(removedCmp.suggestions[1].deletedText == "small")
        #expect(removedCmp.suggestions[1].insertedText == "tiny")

        // Case 2: Brand-new paragraph added between paragraph 0 and paragraph 1, comment on paragraph 3.
        let addedXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>Opening paragraph about the harbour.</w:t></w:r></w:p>
            <w:p><w:r><w:t>A brand new bridge paragraph suggested by the beta.</w:t></w:r></w:p>
            <w:p><w:r><w:t>Second paragraph that the beta removes.</w:t></w:r></w:p>
            <w:p><w:r><w:t>Third paragraph with a small typo.</w:t></w:r></w:p>
            <w:p>
              <w:r><w:t xml:space="preserve">Closing paragraph at </w:t></w:r>
              <w:commentRangeStart w:id="3"/>
              <w:r><w:t>sunset</w:t></w:r>
              <w:commentRangeEnd w:id="3"/>
              <w:r><w:commentReference w:id="3"/></w:r>
              <w:r><w:t>.</w:t></w:r>
            </w:p>
          </w:body>
        </w:document>
        """
        let addedCommentsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:comments xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:comment w:id="3" w:author="Lark"><w:p><w:r><w:t>Great ending.</w:t></w:r></w:p></w:comment>
        </w:comments>
        """
        let addedDoc = try BetaDOCXReader.parse(
            documentXML: Data(addedXML.utf8),
            commentsXML: Data(addedCommentsXML.utf8)
        )
        let addedCmp = BetaComparisonEngine.compare(sentHTML: sentHTML, returned: addedDoc, betaName: "Lark")

        #expect(addedCmp.suggestions.count == 1)
        let addedSug = try #require(addedCmp.suggestions.first)
        #expect(addedSug.isWholeParagraphAddition)
        #expect(addedSug.insertedText == "A brand new bridge paragraph suggested by the beta.")
        #expect(addedSug.paragraphIndex == 1)
        // Comment on Closing paragraph stays aligned at sent index 3 (not shifted to 4!).
        #expect(addedCmp.comments.count == 1)
        #expect(addedCmp.comments.first?.paragraphIndex == 3)
        #expect(addedCmp.comments.first?.quote == "sunset")
    }

    // MARK: - Helpers

    private func utf8Entry(_ name: String, in zip: MiniZip) throws -> String {
        let data = try #require(zip.data(named: name))
        return try #require(String(data: data, encoding: .utf8))
    }
}
