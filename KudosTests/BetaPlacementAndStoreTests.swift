import Foundation
import Testing
@testable import Kudos

private nonisolated final class BetaTestClock: @unchecked Sendable {
    var now: Date

    init(_ start: Date) {
        now = start
    }

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

/// Unit tests for plain-text ↔ HTML UTF-16 offset mapping (entities, inline tags, emoji),
/// unplaceable suggestion detection, store persistence, destructive snapshots, comments
/// becoming 576d notes, PDF HTML sanitization, and ••• menu wiring.
/// Pure logic + temp disk store: no network, no AO3, no WebView.
struct BetaPlacementAndStoreTests {
    // MARK: - Plain-text to HTML offset mapping (entities & inline tags)

    @Test func htmlTextMapperMapsEntitiesInlineRunsAndSurrogatePairsAccurately() throws {
        let html = "<p>Salt &amp; <em>cold &ldquo;water&rdquo;</em> &#x1F30A; today.</p>"
        let textMap = BetaHTMLTextMapper.build(from: html)
        #expect(textMap.plainText == "Salt & cold “water” 🌊 today.")

        // Entity &amp; maps as one plain character covering all 5 UTF-16 units in HTML.
        let ampPlain = try utf16Range(of: "&", in: textMap.plainText)
        let ampResult = textMap.htmlRange(forPlainUTF16Range: ampPlain, allowInlineTags: false)
        guard case let .placed(ampHTML) = ampResult else {
            Issue.record("Expected &amp; to place cleanly")
            return
        }
        #expect(try sliceUTF16(ampHTML, in: html) == "&amp;")

        // Text inside <em>...</em> (including named quote entities) maps to one run inside <em>.
        let innerPlain = try utf16Range(of: "cold “water”", in: textMap.plainText)
        let innerResult = textMap.htmlRange(forPlainUTF16Range: innerPlain, allowInlineTags: false)
        guard case let .placed(innerHTML) = innerResult else {
            Issue.record("Expected inline-formatted run to place cleanly")
            return
        }
        #expect(try sliceUTF16(innerHTML, in: html) == "cold &ldquo;water&rdquo;")

        // Non-BMP numeric entity &#x1F30A; (2 UTF-16 units) maps cleanly whole, rejects half-split.
        let wavePlain = try utf16Range(of: "🌊", in: textMap.plainText)
        let waveResult = textMap.htmlRange(forPlainUTF16Range: wavePlain, allowInlineTags: false)
        guard case let .placed(waveHTML) = waveResult else {
            Issue.record("Expected surrogate-pair entity to place cleanly")
            return
        }
        #expect(try sliceUTF16(waveHTML, in: html) == "&#x1F30A;")

        let splitWave = wavePlain.lowerBound ..< (wavePlain.lowerBound + 1)
        let splitResult = textMap.htmlRange(forPlainUTF16Range: splitWave, allowInlineTags: false)
        #expect(splitResult == .crossesFormatting)

        // Crossing <em> boundary is rejected for replaceText, but allowed for 576d note anchors.
        let crossingPlain = try utf16Range(of: "& cold", in: textMap.plainText)
        let crossingEdit = textMap.htmlRange(forPlainUTF16Range: crossingPlain, allowInlineTags: false)
        #expect(crossingEdit == .crossesFormatting)

        let crossingComment = textMap.htmlRange(forPlainUTF16Range: crossingPlain, allowInlineTags: true)
        guard case let .placed(commentHTML) = crossingComment else {
            Issue.record("Expected comment anchor to span inline formatting tags")
            return
        }
        #expect(try sliceUTF16(commentHTML, in: html) == "&amp; <em>cold")
    }

    @Test func placementSurvivesShiftedChapterEditsTwoEditsInOneParagraphAndNBSP() throws {
        let sentHTML = """
        <p>First paragraph stays put.</p>
        <p>Ines&nbsp;counted the ribs twice, and then a third time, because the old hull creaked.</p>
        """
        let returnedXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>First paragraph stays put.</w:t></w:r></w:p>
            <w:p>
              <w:r><w:t xml:space="preserve">Ines counted the ribs twice, </w:t></w:r>
              <w:del w:id="1" w:author="Lark"><w:r><w:delText>and then a third time,</w:delText></w:r></w:del>
              <w:ins w:id="2" w:author="Lark"><w:r><w:t>then once more,</w:t></w:r></w:ins>
              <w:r><w:t xml:space="preserve"> because the </w:t></w:r>
              <w:del w:id="3" w:author="Lark"><w:r><w:delText>old</w:delText></w:r></w:del>
              <w:ins w:id="4" w:author="Lark"><w:r><w:t>weathered</w:t></w:r></w:ins>
              <w:r><w:t xml:space="preserve"> hull creaked.</w:t></w:r>
            </w:p>
          </w:body>
        </w:document>
        """
        let returned = try BetaDOCXReader.parse(documentXML: Data(returnedXML.utf8))
        let comparison = BetaComparisonEngine.compare(sentHTML: sentHTML, returned: returned, betaName: "Lark")
        #expect(comparison.suggestions.count == 2)

        // Writer added a brand-new opening paragraph after sending to Lark.
        var liveHTML = "<p>Brand new opening added later.</p>\n" + sentHTML

        // Accept suggestion 1.
        let firstPlacement = BetaComparisonEngine.place(comparison.suggestions[0], in: liveHTML)
        guard case let .placed(firstRange) = firstPlacement else {
            Issue.record("Expected first suggestion to place after intro paragraph was inserted")
            return
        }
        #expect(try sliceUTF16(firstRange, in: liveHTML) == "and then a third time,")
        liveHTML = try replacingUTF16(firstRange, in: liveHTML, with: comparison.suggestions[0].insertedText)

        // Accept suggestion 2 in the SAME already-mutated paragraph (Strategy B fallback).
        let secondPlacement = BetaComparisonEngine.place(comparison.suggestions[1], in: liveHTML)
        guard case let .placed(secondRange) = secondPlacement else {
            Issue.record("Expected second suggestion in same paragraph to place after first was accepted")
            return
        }
        #expect(try sliceUTF16(secondRange, in: liveHTML) == "old")
        liveHTML = try replacingUTF16(secondRange, in: liveHTML, with: comparison.suggestions[1].insertedText)
        #expect(liveHTML.contains("then once more, because the weathered hull creaked."))
    }

    @Test func cantPlaceCasesAreDetectedCleanly() throws {
        // 1. Suggestion crossing an inline <em> tag.
        let formattedHTML = "<p>Ines <em>counted the</em> ribs.</p>"
        let formattedRet = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:del w:id="1" w:author="Lark"><w:r><w:delText>Ines counted</w:delText></w:r></w:del>
              <w:ins w:id="2" w:author="Lark"><w:r><w:t>Marta tallied</w:t></w:r></w:ins>
              <w:r><w:t xml:space="preserve"> the ribs.</w:t></w:r>
            </w:p>
          </w:body>
        </w:document>
        """
        let formattedCmp = BetaComparisonEngine.compare(
            sentHTML: formattedHTML,
            returned: try BetaDOCXReader.parse(documentXML: Data(formattedRet.utf8)),
            betaName: "Lark"
        )
        let crossSuggestion = try #require(formattedCmp.suggestions.first)
        #expect(BetaComparisonEngine.place(crossSuggestion, in: formattedHTML) == .crossesFormatting)

        // 2. Writer rewrote/deleted the sentence since sending.
        let sentPlain = "<p>The old harbour wall stood above the water.</p>"
        let plainRet = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:r><w:t xml:space="preserve">The </w:t></w:r>
              <w:del w:id="1" w:author="Lark"><w:r><w:delText>old harbour</w:delText></w:r></w:del>
              <w:ins w:id="2" w:author="Lark"><w:r><w:t>stone</w:t></w:r></w:ins>
              <w:r><w:t xml:space="preserve"> wall stood above the water.</w:t></w:r>
            </w:p>
          </w:body>
        </w:document>
        """
        let plainCmp = BetaComparisonEngine.compare(
            sentHTML: sentPlain,
            returned: try BetaDOCXReader.parse(documentXML: Data(plainRet.utf8)),
            betaName: "Lark"
        )
        let missingSuggestion = try #require(plainCmp.suggestions.first)
        let rewrittenHTML = "<p>A completely different scene now.</p>"
        #expect(BetaComparisonEngine.place(missingSuggestion, in: rewrittenHTML) == .notFound)

        // 3. Whole-paragraph addition cannot be placed into an existing text run.
        let addedRet = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>The old harbour wall stood above the water.</w:t></w:r></w:p>
            <w:p><w:r><w:t>Brand new paragraph from Lark.</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """
        let addedCmp = BetaComparisonEngine.compare(
            sentHTML: sentPlain,
            returned: try BetaDOCXReader.parse(documentXML: Data(addedRet.utf8)),
            betaName: "Lark"
        )
        let addedSuggestion = try #require(addedCmp.suggestions.first)
        #expect(BetaComparisonEngine.place(addedSuggestion, in: sentPlain) == .wholeParagraphAddition)
        #expect(addedSuggestion.copyableText == "Brand new paragraph from Lark.")

        // 4. Crossing a <br /> line break fails placement.
        let brHTML = "<p>Line one<br />Line two</p>"
        let brSuggestion = BetaSuggestionItem(
            author: "Lark",
            isTracked: true,
            paragraphIndex: 0,
            paragraphText: "Line one\nLine two",
            paragraphPrefix: "",
            paragraphSuffix: "",
            paragraphUTF16Offset: 0,
            editStartUTF16: 5,
            editEndUTF16: 13,
            deletedText: "one\nLine",
            insertedText: "one Line",
            localPrefix: "Line ",
            localSuffix: " two"
        )
        #expect(BetaComparisonEngine.place(brSuggestion, in: brHTML) == .crossesFormatting)
    }

    // MARK: - Store persistence, destructive snapshot, notes, filenames, PDF sanitization & menu

    @Test func storePersistsBetaCopiesSnapshotsUnchangedBodyAndLinksCommentNotes() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("beta-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let clock = BetaTestClock(Date(timeIntervalSince1970: 1_763_650_800))
        let store = WritingDocumentStore(root: root, deviceID: "test-device", now: { clock.now })
        let work = try await store.createWork(title: "What the Tide Keeps")
        let chapter = try await store.addChapter(workID: work.id, title: "Slack Water")
        let bodyHTML = "<p>Ines counted the ribs because the number would not stay still.</p>"
        _ = try await store.saveChapter(workID: work.id, chapter: chapter, bodyHTML: bodyHTML)

        // Recording two copies for two betas populates recentBetaNames in recency order.
        var larkCopy = try await store.recordBetaCopy(
            workID: work.id,
            chapterID: chapter.id,
            betaName: "Lark",
            format: .docx,
            sentHTML: bodyHTML
        )
        clock.advance(by: 120)
        _ = try await store.recordBetaCopy(
            workID: work.id,
            chapterID: chapter.id,
            betaName: "nightjar",
            format: .pdf,
            sentHTML: bodyHTML
        )

        let listed = try await store.listBetaCopies(workID: work.id, chapterID: chapter.id)
        #expect(listed.map(\.betaName) == ["nightjar", "Lark"])
        #expect(listed.map(\.status) == [.waiting, .waiting])

        let recentNames = try await store.recentBetaNames(preferringWorkID: work.id)
        #expect(recentNames == ["nightjar", "Lark"])

        // snapshotChapterVersion saves a .destructive version even when body is unchanged.
        let beforeVersions = try await store.listVersions(workID: work.id, chapterID: chapter.id)
        #expect(beforeVersions.isEmpty)

        let snap = try await store.snapshotChapterVersion(workID: work.id, chapterID: chapter.id)
        #expect(snap.cause == .destructive)
        let afterVersions = try await store.listVersions(workID: work.id, chapterID: chapter.id)
        #expect(afterVersions.count == 1)
        let snapBody = try await store.versionBody(
            workID: work.id,
            chapterID: chapter.id,
            versionID: snap.id
        )
        #expect(snapBody == bodyHTML)

        // Adding a beta comment as a 576d .note annotation and resolving it completes review.
        var commentItem = BetaCommentItem(
            sourceCommentID: "0",
            author: "Lark",
            quote: "the number would not stay still",
            text: "Keep this line.",
            paragraphIndex: 0,
            characterOffsetUTF16: 33
        )
        let anchor = BetaComparisonEngine.anchor(for: commentItem, sentHTML: bodyHTML, in: bodyHTML)
        #expect(anchor.quote == "the number would not stay still")

        let createdNote = try await store.addAnnotation(
            workID: work.id,
            chapterID: chapter.id,
            anchor: anchor,
            text: commentItem.annotationNoteText,
            kind: .note
        )
        #expect(createdNote.text == "Lark: Keep this line.")
        #expect(createdNote.kind == .note)
        commentItem.annotationID = createdNote.id

        larkCopy.returnedAt = clock.now
        larkCopy.comments = [commentItem]
        larkCopy.refreshStatusFromItems()
        #expect(larkCopy.status == .cameBack)
        #expect(larkCopy.reviewSectionTitle == "Lark’s edits · 1 comment")

        var resolvedNote = createdNote
        resolvedNote.resolvedAt = clock.now
        let savedResolved = try await store.updateAnnotation(workID: work.id, annotation: resolvedNote)
        #expect(savedResolved.resolvedAt != nil)

        larkCopy.comments[0].isDone = true
        larkCopy.refreshStatusFromItems()
        #expect(larkCopy.status == .reviewed)
        let persisted = try await store.updateBetaCopy(
            workID: work.id,
            chapterID: chapter.id,
            copy: larkCopy
        )
        #expect(persisted.status == .reviewed)
    }

    @MainActor
    @Test func exportFileNameSanitizationPDFSanitizationAndMoreMenuWiring() {
        #expect(
            BetaExportFileName.make(
                chapterNumber: 4,
                chapterTitle: "Slack Water",
                betaName: "Lark",
                format: .docx
            ) == "Chapter 4 – for Lark.docx"
        )
        #expect(
            BetaExportFileName.make(
                chapterNumber: nil,
                chapterTitle: "../Secret:Chapter/1",
                betaName: "Lark:2",
                format: .pdf
            ) == "Secret Chapter 1 – for Lark 2.pdf"
        )

        #if os(iOS)
        #expect(BetaCopyFormat.availableSendFormats == [.docx, .pdf])
        #else
        #expect(BetaCopyFormat.availableSendFormats == [.docx])
        #endif

        // PDF printable HTML must strip remote images and scripts (no network calls).
        let printable = BetaPDFExporter.printableHTML(
            workTitle: "What the Tide Keeps",
            chapterNumber: 4,
            chapterTitle: "Slack Water",
            bodyHTML: "<p>Safe prose.</p><img src=\"https://tracker.invalid/px.png\"><script>alert(1)</script>"
        )
        #expect(printable.contains("Chapter 4 · Slack Water"))
        #expect(printable.contains("Safe prose."))
        #expect(!printable.contains("tracker.invalid"))
        #expect(!printable.contains("<img"))
        #expect(!printable.contains("<script"))

        // ••• menu wiring exposes and dispatches .sendToBeta when canSendToBeta is true.
        var fired = false
        let caps = ChapterEditorMenuCapabilities(canSendToBeta: true)
        let wiring = ChapterEditorMoreMenuWiring(
            capabilities: caps,
            handlers: ChapterEditorMoreMenuHandlers(sendToBeta: { fired = true })
        )
        let model = wiring.model()
        #expect(model.allVisibleActionIDs.contains(.sendToBeta))
        wiring.actions().dispatch(.sendToBeta)
        #expect(fired)
    }

    // MARK: - Helpers

    private func utf16Range(of needle: String, in haystack: String) throws -> Range<Int> {
        let range = try #require(haystack.range(of: needle))
        let start = haystack.utf16.distance(from: haystack.utf16.startIndex, to: range.lowerBound)
        let end = haystack.utf16.distance(from: haystack.utf16.startIndex, to: range.upperBound)
        return start ..< end
    }

    private func sliceUTF16(_ range: RichEditorTextRange, in text: String) throws -> String {
        let lower = text.utf16.index(text.utf16.startIndex, offsetBy: range.from)
        let upper = text.utf16.index(text.utf16.startIndex, offsetBy: range.to)
        let start = try #require(String.Index(lower, within: text))
        let end = try #require(String.Index(upper, within: text))
        return String(text[start ..< end])
    }

    private func replacingUTF16(
        _ range: RichEditorTextRange,
        in text: String,
        with replacement: String
    ) throws -> String {
        let lower = text.utf16.index(text.utf16.startIndex, offsetBy: range.from)
        let upper = text.utf16.index(text.utf16.startIndex, offsetBy: range.to)
        let start = try #require(String.Index(lower, within: text))
        let end = try #require(String.Index(upper, within: text))
        var copy = text
        copy.replaceSubrange(start ..< end, with: replacement)
        return copy
    }
}
