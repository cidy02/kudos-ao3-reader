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
        #expect(second.deletedText == " old", "the word with the space before it; \"old \" would be as right")
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

    // MARK: - Review regressions (fields, moves, replies, cross-paragraph comments, CJK, quotes, hostile docx)

    @Test func fldSimpleKeepsVisibleTextWhileComplexFieldInstrTextStaysIgnored() throws {
        let sentHTML = """
        <p>Check <a href="https://example.com">the chart</a> and \
        <a href="https://example.org">the log</a>.</p>
        """
        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:r><w:t xml:space="preserve">Check </w:t></w:r>
              <w:fldSimple w:instr=" HYPERLINK &quot;https://example.com&quot; ">
                <w:r><w:t>the chart</w:t></w:r>
              </w:fldSimple>
              <w:r><w:t xml:space="preserve"> and </w:t></w:r>
              <w:r><w:fldChar w:fldCharType="begin"/></w:r>
              <w:r><w:instrText> HYPERLINK "https://example.org" </w:instrText></w:r>
              <w:r><w:fldChar w:fldCharType="separate"/></w:r>
              <w:r><w:t>the log</w:t></w:r>
              <w:r><w:fldChar w:fldCharType="end"/></w:r>
              <w:r><w:t>.</w:t></w:r>
            </w:p>
          </w:body>
        </w:document>
        """

        let parsed = try BetaDOCXReader.parse(documentXML: Data(documentXML.utf8))
        let para = try #require(parsed.paragraphs.first)
        #expect(para.baselineText == "Check the chart and the log.")
        #expect(para.finalText == "Check the chart and the log.")

        let comparison = BetaComparisonEngine.compare(
            sentHTML: sentHTML,
            returned: parsed,
            betaName: "Lark"
        )
        #expect(comparison.suggestions.isEmpty)
    }

    @Test func wordTrackedMovesEmitTrackedDeletionAndInsertionInsteadOfDuplicating() throws {
        let sentHTML = "<p>The cold wind rose.</p><p>The water darkened.</p>"
        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:r><w:t xml:space="preserve">The </w:t></w:r>
              <w:moveFromRangeStart w:id="10" w:name="move1"/>
              <w:moveFrom w:id="11" w:author="Lark" w:date="2026-11-21T10:00:00Z">
                <w:r><w:t xml:space="preserve">cold </w:t></w:r>
              </w:moveFrom>
              <w:moveFromRangeEnd w:id="10"/>
              <w:r><w:t>wind rose.</w:t></w:r>
            </w:p>
            <w:p>
              <w:r><w:t xml:space="preserve">The </w:t></w:r>
              <w:moveToRangeStart w:id="12" w:name="move1"/>
              <w:moveTo w:id="13" w:author="Lark" w:date="2026-11-21T10:00:00Z">
                <w:r><w:t xml:space="preserve">cold </w:t></w:r>
              </w:moveTo>
              <w:moveToRangeEnd w:id="12"/>
              <w:r><w:t>water darkened.</w:t></w:r>
            </w:p>
          </w:body>
        </w:document>
        """

        let parsed = try BetaDOCXReader.parse(documentXML: Data(documentXML.utf8))
        #expect(parsed.paragraphs.count == 2)
        #expect(parsed.paragraphs[0].baselineText == "The cold wind rose.")
        #expect(parsed.paragraphs[0].finalText == "The wind rose.")
        #expect(parsed.paragraphs[1].baselineText == "The water darkened.")
        #expect(parsed.paragraphs[1].finalText == "The cold water darkened.")

        let comparison = BetaComparisonEngine.compare(
            sentHTML: sentHTML,
            returned: parsed,
            betaName: "Lark"
        )
        #expect(comparison.suggestions.count == 2)
        #expect(comparison.suggestions[0].paragraphIndex == 0)
        #expect(comparison.suggestions[0].isTracked)
        #expect(comparison.suggestions[0].author == "Lark")
        #expect(comparison.suggestions[0].deletedText == "cold ")
        #expect(comparison.suggestions[0].insertedText.isEmpty)

        #expect(comparison.suggestions[1].paragraphIndex == 1)
        #expect(comparison.suggestions[1].isTracked)
        #expect(comparison.suggestions[1].author == "Lark")
        #expect(comparison.suggestions[1].deletedText.isEmpty)
        #expect(comparison.suggestions[1].insertedText == "cold ")
    }

    @Test func commentRepliesViaCommentsExtendedAndUnrangedCommentsArePreserved() throws {
        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:r><w:t xml:space="preserve">The harbour was quiet at </w:t></w:r>
              <w:commentRangeStart w:id="1"/>
              <w:r><w:t>slack water</w:t></w:r>
              <w:commentRangeEnd w:id="1"/>
              <w:r><w:commentReference w:id="1"/></w:r>
              <w:r><w:t>.</w:t></w:r>
            </w:p>
          </w:body>
        </w:document>
        """
        let commentsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:comments xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" \
        xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml">
          <w:comment w:id="1" w:author="Lark" w:date="2026-11-22T09:00:00Z">
            <w:p w14:paraId="1111AAAA"><w:r><w:t>This line lands softly.</w:t></w:r></w:p>
          </w:comment>
          <w:comment w:id="2" w:author="Marta" w:date="2026-11-22T09:05:00Z">
            <w:p w14:paraId="2222BBBB"><w:r><w:t>Agreed, keep it.</w:t></w:r></w:p>
          </w:comment>
          <w:comment w:id="3" w:author="Lark" w:date="2026-11-22T09:10:00Z">
            <w:p w14:paraId="3333CCCC"><w:r><w:t>General pacing note.</w:t></w:r></w:p>
          </w:comment>
        </w:comments>
        """
        let commentsExtendedXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w15:commentsEx xmlns:w15="http://schemas.microsoft.com/office/word/2012/wordml">
          <w15:commentEx w15:paraId="1111AAAA" w15:done="0"/>
          <w15:commentEx w15:paraId="2222BBBB" w15:paraIdParent="1111AAAA" w15:done="0"/>
        </w15:commentsEx>
        """

        let docxData = try MiniZip.archiveData([
            (name: "word/document.xml", data: Data(documentXML.utf8)),
            (name: "word/comments.xml", data: Data(commentsXML.utf8)),
            (name: "word/commentsExtended.xml", data: Data(commentsExtendedXML.utf8)),
        ])
        let parsed = try BetaDOCXReader.read(docxData: docxData)
        #expect(parsed.comments.count == 3)

        let parent = try #require(parsed.comments.first { $0.id == "1" })
        let reply = try #require(parsed.comments.first { $0.id == "2" })
        let unranged = try #require(parsed.comments.first { $0.id == "3" })

        #expect(parent.quote == "slack water")
        #expect(parent.text == "This line lands softly.")
        #expect(reply.author == "Marta")
        #expect(reply.quote == "slack water")
        #expect(reply.paragraphIndex == parent.paragraphIndex)
        #expect(reply.text == "Reply to Lark (“This line lands softly.”): Agreed, keep it.")
        #expect(unranged.text == "General pacing note.")
        #expect(unranged.quote.isEmpty)

        let parentIndex = try #require(parsed.comments.firstIndex { $0.id == "1" })
        let replyIndex = try #require(parsed.comments.firstIndex { $0.id == "2" })
        #expect(parentIndex < replyIndex)
    }

    @Test func crossParagraphCommentRangeAndTrailingNewParagraphCommentAnchorCleanly() throws {
        // Case 1: commentRangeStart sits at the end of para A, words live in para B.
        let sentTwoParas = "<p>First paragraph stays quiet.</p><p>Second paragraph holds the clue.</p>"
        let trailingStartXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:r><w:t>First paragraph stays quiet.</w:t></w:r>
              <w:commentRangeStart w:id="1"/>
            </w:p>
            <w:p>
              <w:r><w:t>Second paragraph holds the clue.</w:t></w:r>
              <w:commentRangeEnd w:id="1"/>
              <w:r><w:commentReference w:id="1"/></w:r>
            </w:p>
          </w:body>
        </w:document>
        """
        let oneCommentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:comments xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:comment w:id="1" w:author="Lark"><w:p><w:r><w:t>Sharp clue.</w:t></w:r></w:p></w:comment>
        </w:comments>
        """
        let parsedTrailing = try BetaDOCXReader.parse(
            documentXML: Data(trailingStartXML.utf8),
            commentsXML: Data(oneCommentXML.utf8)
        )
        let trailingComment = try #require(parsedTrailing.comments.first)
        #expect(trailingComment.paragraphIndex == 1)
        #expect(trailingComment.quote == "Second paragraph holds the clue.")

        let trailingCmp = BetaComparisonEngine.compare(
            sentHTML: sentTwoParas,
            returned: parsedTrailing,
            betaName: "Lark"
        )
        let trailingAnchor = BetaComparisonEngine.anchor(
            for: try #require(trailingCmp.comments.first),
            sentHTML: sentTwoParas,
            in: sentTwoParas
        )
        #expect(trailingAnchor.quote == "Second paragraph holds the clue.")

        // Case 2: commentRange spans text at the end of para A into the start of para B.
        let spanningXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:r><w:t xml:space="preserve">First paragraph </w:t></w:r>
              <w:commentRangeStart w:id="1"/>
              <w:r><w:t>stays quiet.</w:t></w:r>
            </w:p>
            <w:p>
              <w:r><w:t>Second paragraph</w:t></w:r>
              <w:commentRangeEnd w:id="1"/>
              <w:r><w:commentReference w:id="1"/></w:r>
              <w:r><w:t xml:space="preserve"> holds the clue.</w:t></w:r>
            </w:p>
          </w:body>
        </w:document>
        """
        let parsedSpan = try BetaDOCXReader.parse(
            documentXML: Data(spanningXML.utf8),
            commentsXML: Data(oneCommentXML.utf8)
        )
        let spanComment = try #require(parsedSpan.comments.first)
        #expect(spanComment.quote == "stays quiet.\nSecond paragraph")
        let spanCmp = BetaComparisonEngine.compare(
            sentHTML: sentTwoParas,
            returned: parsedSpan,
            betaName: "Lark"
        )
        let spanAnchor = BetaComparisonEngine.anchor(
            for: try #require(spanCmp.comments.first),
            sentHTML: sentTwoParas,
            in: sentTwoParas
        )
        #expect(spanAnchor.quote == "stays quiet.</p><p>Second paragraph")

        // Case 3: comment on a brand-new paragraph added after the last sent paragraph clamps to sentCount - 1.
        let trailingNewParaXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>First paragraph stays quiet.</w:t></w:r></w:p>
            <w:p><w:r><w:t>Second paragraph holds the clue.</w:t></w:r></w:p>
            <w:p>
              <w:commentRangeStart w:id="1"/>
              <w:r><w:t>Brand new coda paragraph.</w:t></w:r>
              <w:commentRangeEnd w:id="1"/>
              <w:r><w:commentReference w:id="1"/></w:r>
            </w:p>
          </w:body>
        </w:document>
        """
        let parsedNewPara = try BetaDOCXReader.parse(
            documentXML: Data(trailingNewParaXML.utf8),
            commentsXML: Data(oneCommentXML.utf8)
        )
        let newParaCmp = BetaComparisonEngine.compare(
            sentHTML: sentTwoParas,
            returned: parsedNewPara,
            betaName: "Lark"
        )
        let newParaComment = try #require(newParaCmp.comments.first)
        #expect(newParaComment.paragraphIndex == 1)
        let newParaAnchor = BetaComparisonEngine.anchor(
            for: newParaComment,
            sentHTML: sentTwoParas,
            in: sentTwoParas
        )
        #expect(newParaAnchor.quote == "Second paragraph holds the clue.")
        #expect(newParaAnchor.utf16Offset > 0)
    }

    @Test func cjkTokenizationAndLongUntrackedParagraphMyersDiffAvoidGiantHunks() throws {
        // CJK ideographs emit one token per character.
        let zhXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body><w:p><w:r><w:t>今天天晴很好</w:t></w:r></w:p></w:body>
        </w:document>
        """
        let zhCmp = BetaComparisonEngine.compare(
            sentHTML: "<p>今天天气很好</p>",
            returned: try BetaDOCXReader.parse(documentXML: Data(zhXML.utf8)),
            betaName: "Lark"
        )
        #expect(zhCmp.suggestions.count == 1)
        #expect(zhCmp.suggestions.first?.deletedText == "气")
        #expect(zhCmp.suggestions.first?.insertedText == "晴")

        // Japanese kana and kanji emit one token per character.
        let jaXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body><w:p><w:r><w:t>今日は悪い天気です</w:t></w:r></w:p></w:body>
        </w:document>
        """
        let jaCmp = BetaComparisonEngine.compare(
            sentHTML: "<p>今日はいい天気です</p>",
            returned: try BetaDOCXReader.parse(documentXML: Data(jaXML.utf8)),
            betaName: "Lark"
        )
        #expect(jaCmp.suggestions.count == 1)
        // one token per kana and ideograph: only the first い changes (accepting it gives the beta's sentence)
        #expect(jaCmp.suggestions.first?.deletedText == "い")
        #expect(jaCmp.suggestions.first?.insertedText == "悪")

        // Long paragraph (> 500 words = > 1,000 tokens -> > 1,000,000 cells, past the 250,000 DP cap).
        var sentWords = (0 ..< 520).map { "word\($0)" }
        sentWords[5] = "alpha"
        sentWords[515] = "omega"
        var returnedWords = sentWords
        returnedWords[5] = "ALPHA"
        returnedWords[515] = "OMEGA"
        let sentLong = "<p>\(sentWords.joined(separator: " "))</p>"
        let longXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body><w:p><w:r><w:t>\(returnedWords.joined(separator: " "))</w:t></w:r></w:p></w:body>
        </w:document>
        """
        let longCmp = BetaComparisonEngine.compare(
            sentHTML: sentLong,
            returned: try BetaDOCXReader.parse(documentXML: Data(longXML.utf8)),
            betaName: "Lark"
        )
        #expect(longCmp.suggestions.count == 2)
        #expect(longCmp.suggestions[0].deletedText == "alpha")
        #expect(longCmp.suggestions[0].insertedText == "ALPHA")
        #expect(longCmp.suggestions[1].deletedText == "omega")
        #expect(longCmp.suggestions[1].insertedText == "OMEGA")
    }

    @Test func smartQuoteCurlingDoesNotManufactureDiffsAndPreservesReturnedQuotesInEdits() throws {
        let sentHTML = "<p>It's \"cold\" and we'll stay.</p>"
        let curledOnlyXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body><w:p><w:r><w:t>It’s “cold” and we’ll stay.</w:t></w:r></w:p></w:body>
        </w:document>
        """
        let curledOnlyCmp = BetaComparisonEngine.compare(
            sentHTML: sentHTML,
            returned: try BetaDOCXReader.parse(documentXML: Data(curledOnlyXML.utf8)),
            betaName: "Lark"
        )
        #expect(curledOnlyCmp.suggestions.isEmpty)

        let editedWithCurledXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body><w:p><w:r><w:t>It’s “warm” and won’t stay.</w:t></w:r></w:p></w:body>
        </w:document>
        """
        let editedCmp = BetaComparisonEngine.compare(
            sentHTML: sentHTML,
            returned: try BetaDOCXReader.parse(documentXML: Data(editedWithCurledXML.utf8)),
            betaName: "Lark"
        )
        #expect(editedCmp.suggestions.count == 2)
        #expect(editedCmp.suggestions[0].deletedText == "cold")
        #expect(editedCmp.suggestions[0].insertedText == "warm")
        #expect(editedCmp.suggestions[1].deletedText == "we'll")
        #expect(editedCmp.suggestions[1].insertedText == "won’t")
    }

    @Test func readerHandlesTabsLineBreaksSmartTagsAndRejectsHostileDOCX() throws {
        // w:tab, w:br, and w:smartTag keep their text intact.
        let richElementsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:r><w:t>A</w:t><w:tab/><w:t>B</w:t><w:br/><w:t>C</w:t></w:r>
              <w:smartTag w:element="place"><w:r><w:t xml:space="preserve"> London</w:t></w:r></w:smartTag>
            </w:p>
          </w:body>
        </w:document>
        """
        let parsed = try BetaDOCXReader.parse(documentXML: Data(richElementsXML.utf8))
        #expect(parsed.paragraphs.first?.finalText == "A\tB\nC London")

        // File larger than 20 MB is refused before reading.
        let oversizedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("beta-oversized-\(UUID().uuidString).docx")
        defer { try? FileManager.default.removeItem(at: oversizedURL) }
        FileManager.default.createFile(atPath: oversizedURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: oversizedURL)
        try handle.truncate(atOffset: UInt64(BetaDOCXReader.maxFileBytes + 1))
        try handle.close()
        #expect(throws: BetaReadingError.fileTooLarge(maxBytes: BetaDOCXReader.maxFileBytes)) {
            _ = try BetaDOCXReader.readFileData(at: oversizedURL)
        }

        // Zip bombs under EPUB's 200 MB / 1100:1 limits are rejected by tighter beta docxLimits (25 MB / 200:1).
        let overEntryLimitArchive = HostileZipFixture.build([
            HostileZipFixture.Entry(
                name: "word/document.xml",
                method: 8,
                payload: Data([0x00, 0x01, 0x02, 0x03]),
                declaredCompressedSize: 400_000,
                declaredUncompressedSize: 40_000_000
            ),
        ])
        _ = try MiniZip(data: overEntryLimitArchive, limits: .epub)
        #expect(throws: BetaReadingError.self) {
            _ = try BetaDOCXReader.read(docxData: overEntryLimitArchive)
        }

        let overRatioLimitArchive = HostileZipFixture.build([
            HostileZipFixture.Entry(
                name: "word/document.xml",
                method: 8,
                payload: Data([0x00, 0x01, 0x02, 0x03]),
                declaredCompressedSize: 100,
                declaredUncompressedSize: 30_000
            ),
        ])
        _ = try MiniZip(data: overRatioLimitArchive, limits: .epub)
        #expect(throws: BetaReadingError.self) {
            _ = try BetaDOCXReader.read(docxData: overRatioLimitArchive)
        }

        // Internal XML entity declarations (billion-laughs defense) are rejected.
        let entityXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE doc [<!ENTITY lol "boom">]>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body><w:p><w:r><w:t>&lol;</w:t></w:r></w:p></w:body>
        </w:document>
        """
        #expect(throws: BetaReadingError.self) {
            _ = try BetaDOCXReader.parse(documentXML: Data(entityXML.utf8))
        }
    }

    // MARK: - Helpers

    private func utf8Entry(_ name: String, in zip: MiniZip) throws -> String {
        let data = try #require(zip.data(named: name))
        return try #require(String(data: data, encoding: .utf8))
    }
}
