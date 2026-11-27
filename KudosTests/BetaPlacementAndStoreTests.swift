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

@MainActor
private final class FakeBetaSourceBridge: DraftSourceBridge {
    var text: String
    var isFrozen = false
    var caretOffsetUTF16 = 0
    var canUndo = false
    var canRedo = false
    var onEdit: (@MainActor () -> Void)?
    var replaceCallCount = 0

    init(text: String) {
        self.text = text
    }

    func commitComposition() {}
    func setCaretOffsetUTF16(_ offset: Int) { caretOffsetUTF16 = offset }
    func replaceForModeHandoff(_ value: String, caretOffset: Int?) {
        text = value
        if let caretOffset { caretOffsetUTF16 = caretOffset }
    }
    func restore(_ value: String) { text = value }

    @discardableResult
    func replaceText(in range: NSRange, with value: String) -> Bool {
        replaceCallCount += 1
        guard !isFrozen else { return false }
        let nsText = text as NSString
        guard range.location >= 0, range.location + range.length <= nsText.length else {
            return false
        }
        text = nsText.replacingCharacters(in: range, with: value)
        caretOffsetUTF16 = range.location + (value as NSString).length
        return true
    }

    func focus() {}
    func undo() {}
    func redo() {}
}

@MainActor
private final class FakeBetaRichTransport: RichEditorBridgeTransport {
    var onEvent: (@MainActor (RichEditorEvent) -> Void)?
    var onProcessTerminated: (@MainActor () -> Void)?
    var html: String
    var commands: [RichEditorCommandArgs] = []
    var commandApplied = true

    init(html: String) {
        self.html = html
    }

    func configure(_ args: RichEditorConfigureArgs) async throws -> RichEditorConfigureResult {
        RichEditorConfigureResult(bridgeVersion: 1, schemaVersion: 1, bundleVersion: "test")
    }
    func load(_ args: RichEditorLoadArgs) async throws -> RichEditorLoadResult {
        html = args.html
        return RichEditorLoadResult(revision: args.revision, loss: .empty, timing: .zero)
    }
    func activate(_ args: RichEditorActivateArgs) async throws -> RichEditorActivateResult {
        RichEditorActivateResult(caretFound: true)
    }
    func freeze() async throws -> RichEditorFreezeResult { RichEditorFreezeResult(revision: 0) }
    func snapshot(_ args: RichEditorSnapshotArgs) async throws -> RichEditorSnapshotResult {
        RichEditorSnapshotResult(revision: 0, html: html, caretOffset: nil, words: 0, selection: nil)
    }
    func command(_ args: RichEditorCommandArgs) async throws -> RichEditorCommandResult {
        commands.append(args)
        return RichEditorCommandResult(applied: commandApplied)
    }
    func lint(_ args: RichEditorLintArgs) async throws -> RichEditorLintResult {
        RichEditorLintResult(loss: .empty)
    }
    func setTheme(_ theme: RichEditorTheme) async throws {}
    func setAppearance(_ appearance: RichEditorAppearance) async throws {}
    func dispose() async throws {}
    func verifySwitch(_ args: RichEditorSwitchCheckArgs) async throws -> RichEditorSwitchCheckResult {
        RichEditorSwitchCheckResult(ok: true, candidateHtml: args.html, reason: nil)
    }
    func focusWebView() {}
    func resetAfterTermination() {}
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

        // 3. Whole-paragraph addition is copy-and-paste only (excluded from auto-accept).
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
        #expect(addedSuggestion.isWholeParagraphAddition)
        #expect(addedSuggestion.state == .pending)
        #expect(addedSuggestion.copyableText == "Brand new paragraph from Lark.")
        let copyRecord = BetaCopyRecord(
            id: UUID(),
            betaName: "Lark",
            format: .docx,
            sentAt: Date(timeIntervalSince1970: 1_763_650_800),
            sentHTML: sentPlain,
            returnedAt: Date(timeIntervalSince1970: 1_763_650_900),
            status: .cameBack,
            hasSnapshottedBeforeAccept: false,
            suggestions: [addedSuggestion],
            comments: [],
            updatedAt: Date(timeIntervalSince1970: 1_763_650_900),
            updatedBy: "test"
        )
        #expect(copyRecord.acceptablePendingSuggestions.isEmpty)
        #expect(copyRecord.pasteOnlyPendingSuggestions.map(\.id) == [addedSuggestion.id])

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

        // VoiceOver summary includes the surrounding sentence around the edit (and added-paragraph label).
        let inlineSuggestion = BetaSuggestionItem(
            author: "Lark",
            isTracked: true,
            paragraphIndex: 0,
            paragraphText: "The harbour was silent at slack water.",
            paragraphPrefix: "",
            paragraphSuffix: "",
            paragraphUTF16Offset: 0,
            editStartUTF16: 16,
            editEndUTF16: 22,
            deletedText: "silent",
            insertedText: "dead quiet",
            localPrefix: "The harbour was ",
            localSuffix: " at slack water."
        )
        let spoken = BetaSuggestionCardView.accessibilityText(for: inlineSuggestion)
        #expect(spoken.contains("The harbour was"))
        #expect(spoken.contains("Delete: silent"))
        #expect(spoken.contains("Insert: dead quiet"))
        #expect(spoken.contains("at slack water."))

        let addedParagraph = BetaSuggestionItem(
            author: "Lark",
            isTracked: false,
            paragraphIndex: 0,
            paragraphText: "",
            paragraphPrefix: "",
            paragraphSuffix: "",
            paragraphUTF16Offset: 0,
            editStartUTF16: 0,
            editEndUTF16: 0,
            deletedText: "",
            insertedText: "A fresh paragraph.",
            localPrefix: "",
            localSuffix: "",
            isWholeParagraphAddition: true
        )
        #expect(BetaSuggestionCardView.accessibilityText(for: addedParagraph) == "Added paragraph: A fresh paragraph.")
    }

    // MARK: - Accept / Accept All, Finding 10 range verification, and Import ordering/dedup

    @MainActor
    @Test func wholeParagraphAdditionNeverMarksUnplaceableAndAcceptAllSkipsIt() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("beta-accept-all-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let clock = BetaTestClock(Date(timeIntervalSince1970: 1_763_650_800))
        let store = WritingDocumentStore(root: root, deviceID: "test-device", now: { clock.now })
        let work = try await store.createWork(title: "Harbour")
        let chapter = try await store.addChapter(workID: work.id, title: "Ch 1")
        let sentHTML = "<p>The old harbour wall stood above the water.</p>"
        _ = try await store.saveChapter(workID: work.id, chapter: chapter, bodyHTML: sentHTML)

        var copy = try await store.recordBetaCopy(
            workID: work.id,
            chapterID: chapter.id,
            betaName: "Lark",
            format: .docx,
            sentHTML: sentHTML
        )
        let returnedXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:r><w:t xml:space="preserve">The </w:t></w:r>
              <w:del w:id="1" w:author="Lark"><w:r><w:delText>old</w:delText></w:r></w:del>
              <w:ins w:id="2" w:author="Lark"><w:r><w:t>stone</w:t></w:r></w:ins>
              <w:r><w:t xml:space="preserve"> harbour wall stood above the water.</w:t></w:r>
            </w:p>
            <w:p><w:r><w:t>Brand new paragraph from Lark.</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """
        let cmp = BetaComparisonEngine.compare(
            sentHTML: sentHTML,
            returned: try BetaDOCXReader.parse(documentXML: Data(returnedXML.utf8)),
            betaName: "Lark"
        )
        #expect(cmp.suggestions.count == 2)
        copy.returnedAt = clock.now
        copy.suggestions = cmp.suggestions
        copy.refreshStatusFromItems()
        copy = try await store.updateBetaCopy(workID: work.id, chapterID: chapter.id, copy: copy)

        let source = FakeBetaSourceBridge(text: sentHTML)
        let session = DraftSession(initialText: sentHTML, fieldVariant: .content, source: source)

        let addedID = try #require(copy.suggestions.first(where: \.isWholeParagraphAddition)?.id)
        let directOutcome = await BetaReviewActions.acceptSuggestion(
            suggestionID: addedID,
            in: &copy,
            workID: work.id,
            chapterID: chapter.id,
            store: store,
            session: session
        )
        #expect(directOutcome == .skippedManualPaste)
        #expect(copy.suggestions.first { $0.id == addedID }?.state == .pending)
        #expect(source.text == sentHTML)
        #expect(source.replaceCallCount == 0)

        let bulk = await BetaReviewActions.acceptAll(
            in: &copy,
            workID: work.id,
            chapterID: chapter.id,
            store: store,
            session: session
        )
        #expect(bulk.appliedCount == 1)
        #expect(bulk.skippedManualPasteCount == 1)
        #expect(bulk.unplaceableCount == 0)
        #expect(bulk.manualPasteNotice == "1 added paragraph was skipped — copy and paste it where it goes.")
        #expect(source.text == "<p>The stone harbour wall stood above the water.</p>")
        #expect(copy.suggestions.first { !$0.isWholeParagraphAddition }?.state == .accepted)
        #expect(copy.suggestions.first { $0.id == addedID }?.state == .pending)
        #expect(try await store.listVersions(workID: work.id, chapterID: chapter.id).count == 1)
    }

    @MainActor
    @Test func verifiedReplaceTextRequiresDecodedSliceToEqualDeletedTextInHTMLAndRichModes() async throws {
        let html = "<p>Ines &amp; Marta saw old ribs.</p>"
        let ampStart = try utf16Range(of: "Ines &amp; Marta", in: html)
        let ampRange = RichEditorTextRange(from: ampStart.lowerBound, to: ampStart.upperBound)
        #expect(BetaComparisonEngine.rangeMatchesDeletedText("Ines & Marta", at: ampRange, in: html))
        #expect(!BetaComparisonEngine.rangeMatchesDeletedText("wrong words", at: ampRange, in: html))

        // Leading-space deletions (e.g. " old") must preserve leading whitespace when decoding.
        let leadingSpace = try utf16Range(of: " old", in: html)
        let leadingRange = RichEditorTextRange(from: leadingSpace.lowerBound, to: leadingSpace.upperBound)
        #expect(BetaComparisonEngine.rangeMatchesDeletedText(" old", at: leadingRange, in: html))

        // HTML (source) mode: mismatch refuses without touching source; match applies cleanly.
        let source = FakeBetaSourceBridge(text: html)
        let htmlSession = DraftSession(initialText: html, fieldVariant: .content, source: source)

        let badHTMLApplied = await BetaReviewActions.verifiedReplaceText(
            in: ampRange,
            expectingDeletedText: "something else",
            with: "replacement",
            in: htmlSession
        )
        #expect(!badHTMLApplied)
        #expect(source.replaceCallCount == 0)
        #expect(source.text == html)

        let goodHTMLApplied = await BetaReviewActions.verifiedReplaceText(
            in: ampRange,
            expectingDeletedText: "Ines & Marta",
            with: "Ines and Marta",
            in: htmlSession
        )
        #expect(goodHTMLApplied)
        #expect(source.replaceCallCount == 1)
        #expect(source.text == "<p>Ines and Marta saw old ribs.</p>")

        // Rich Text mode: mismatch refuses before sending replaceText; match sends command.
        let richSource = FakeBetaSourceBridge(text: html)
        let transport = FakeBetaRichTransport(html: html)
        let richSession = DraftSession(
            initialText: html,
            fieldVariant: .content,
            source: richSource,
            richTransport: transport
        )
        richSession.state = .richOwned

        let badRichApplied = await BetaReviewActions.verifiedReplaceText(
            in: ampRange,
            expectingDeletedText: "stale text",
            with: "replacement",
            in: richSession
        )
        #expect(!badRichApplied)
        #expect(transport.commands.isEmpty)

        let goodRichApplied = await BetaReviewActions.verifiedReplaceText(
            in: ampRange,
            expectingDeletedText: "Ines & Marta",
            with: "Ines and Marta",
            in: richSession
        )
        #expect(goodRichApplied)
        #expect(transport.commands.count == 1)
        #expect(transport.commands.first?.name == "replaceText")
    }

    @MainActor
    @Test func importWritesBetaRecordBeforeNotesAndSkipsLinkedCommentsOnRetry() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("beta-import-order-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let clock = BetaTestClock(Date(timeIntervalSince1970: 1_763_650_800))
        let store = WritingDocumentStore(root: root, deviceID: "test-device", now: { clock.now })
        let bridge = ChapterEditorDocumentBridge(store: store)
        let sentHTML = "<p>Ines counted the ribs because the number would not stay still.</p>"
        let snapshot = try #require(await bridge.open(
            target: .local(workID: nil, chapterID: nil),
            initialPayload: ChapterEditorChapterPayload(
                workTitle: "What the Tide Keeps",
                chapterTitle: "Slack Water",
                summary: "",
                notesBefore: "",
                notesAfter: "",
                bodyHTML: sentHTML,
                ao3ChapterID: nil,
                status: .local
            )
        ))
        let workID = snapshot.work.id
        let chapterID = snapshot.activeChapter.id

        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:r><w:t xml:space="preserve">Ines counted the ribs because </w:t></w:r>
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
          <w:comment w:id="7" w:author="Lark">
            <w:p><w:r><w:t>Keep this line.</w:t></w:r></w:p>
          </w:comment>
        </w:comments>
        """
        let docxData = try MiniZip.archiveData([
            (name: "word/document.xml", data: Data(documentXML.utf8)),
            (name: "word/comments.xml", data: Data(commentsXML.utf8)),
        ])

        // If betas.json persistence throws (unknown copy id), zero notes may be written.
        let unrecordedCopy = BetaCopyRecord(
            id: UUID(),
            betaName: "Lark",
            format: .docx,
            sentAt: clock.now,
            sentHTML: sentHTML,
            returnedAt: nil,
            status: .waiting,
            hasSnapshottedBeforeAccept: false,
            suggestions: [],
            comments: [],
            updatedAt: clock.now,
            updatedBy: "test-device"
        )
        await #expect(throws: WritingDocumentError.self) {
            _ = try await BetaReviewActions.importReturnedDOCX(
                docxData: docxData,
                into: unrecordedCopy,
                workID: workID,
                chapterID: chapterID,
                documentBridge: bridge,
                liveHTML: sentHTML,
                now: clock.now
            )
        }
        #expect(try await store.listAnnotations(workID: workID, chapterID: chapterID).isEmpty)

        // Normal import writes betas.json first, then links one note.
        let recorded = try await store.recordBetaCopy(
            workID: workID,
            chapterID: chapterID,
            betaName: "Lark",
            format: .docx,
            sentHTML: sentHTML
        )
        let firstImport = try await BetaReviewActions.importReturnedDOCX(
            docxData: docxData,
            into: recorded,
            workID: workID,
            chapterID: chapterID,
            documentBridge: bridge,
            liveHTML: sentHTML,
            now: clock.now
        )
        #expect(firstImport.addedAnnotations)
        #expect(firstImport.copy.status == .cameBack)
        let notesAfterFirst = try await store.listAnnotations(workID: workID, chapterID: chapterID)
        #expect(notesAfterFirst.count == 1)
        let firstNoteID = try #require(notesAfterFirst.first?.id)
        #expect(firstImport.copy.comments.first?.annotationID == firstNoteID)

        // Retrying import for the same copy skips sourceCommentIDs already linked to a note.
        let retryImport = try await BetaReviewActions.importReturnedDOCX(
            docxData: docxData,
            into: firstImport.copy,
            workID: workID,
            chapterID: chapterID,
            documentBridge: bridge,
            liveHTML: sentHTML,
            now: clock.now
        )
        #expect(!retryImport.addedAnnotations)
        let notesAfterRetry = try await store.listAnnotations(workID: workID, chapterID: chapterID)
        #expect(notesAfterRetry.count == 1)
        #expect(retryImport.copy.comments.first?.annotationID == firstNoteID)
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
