import Foundation
import SwiftUI
import Testing
@testable import Kudos

/// Unit tests for T-576d UI logic: story-note name matching, annotation list grouping and
/// `"Paragraph N"` computation, new-note anchor construction from `(html, range)`, TK marker
/// creation from a range, open/resolved counts, and bridge / session integration.
/// Depends only on a plain test host: no network, no AO3, no WebView.
@MainActor
struct ChapterEditorAnnotationTests {
    // MARK: - Story-note name matching (`Editor-Names.dc.html`)

    @Test func nameMatchingHandlesPrefixCaseDiacriticsWholeWordAndThreeCap() {
        let names = ["Ines", "Marta", "Marlowe", "Maren", "Marcus", "Aodhán", "The harbour wall"]

        // Case-insensitive prefix in story-note order, capped at 3.
        #expect(
            ChapterEditorNameMatcher.suggestions(for: "Ma", names: names)
                == ["Marta", "Marlowe", "Maren"]
        )
        #expect(
            ChapterEditorNameMatcher.suggestions(for: "ma", names: names)
                == ["Marta", "Marlowe", "Maren"]
        )
        #expect(
            ChapterEditorNameMatcher.suggestions(for: "MAR", names: names)
                == ["Marta", "Marlowe", "Maren"]
        )

        // Exact whole-word (case-insensitive) suppresses that name.
        #expect(ChapterEditorNameMatcher.suggestions(for: "Marta", names: names).isEmpty)
        #expect(ChapterEditorNameMatcher.suggestions(for: "marta", names: names).isEmpty)

        // When one name is typed whole and a longer name shares the prefix, only the longer matches.
        #expect(
            ChapterEditorNameMatcher.suggestions(for: "Mar", names: ["Mar", "Marta"])
                == ["Marta"]
        )

        // Diacritic-insensitive typing still offers the accented spelling until typed verbatim.
        #expect(ChapterEditorNameMatcher.suggestions(for: "aodh", names: names) == ["Aodhán"])
        #expect(ChapterEditorNameMatcher.suggestions(for: "Aodhan", names: names) == ["Aodhán"])
        #expect(ChapterEditorNameMatcher.suggestions(for: "Aodhán", names: names).isEmpty)

        // Multi-word place names match from their leading prefix.
        #expect(
            ChapterEditorNameMatcher.suggestions(for: "The", names: names)
                == ["The harbour wall"]
        )

        // Empty / nil / single-character prefix or empty work names produce no chips.
        #expect(ChapterEditorNameMatcher.suggestions(for: nil, names: names).isEmpty)
        #expect(ChapterEditorNameMatcher.suggestions(for: "", names: names).isEmpty)
        #expect(ChapterEditorNameMatcher.suggestions(for: "M", names: names).isEmpty)
        #expect(ChapterEditorNameMatcher.suggestions(for: "Ma", names: []).isEmpty)
    }

    @Test func nameMatchingOffersPossessivesWhenTypedPrefixEndsInApostrophe() {
        let names = ["Marta", "Ines", "Ines’s father", "O'Brien", "Aodhán"]

        // Both straight and curly trailing apostrophes offer the typographic possessive.
        #expect(ChapterEditorNameMatcher.suggestions(for: "Marta'", names: names) == ["Marta’s"])
        #expect(ChapterEditorNameMatcher.suggestions(for: "Marta’", names: names) == ["Marta’s"])
        #expect(ChapterEditorNameMatcher.suggestions(for: "marta'", names: names) == ["Marta’s"])
        #expect(ChapterEditorNameMatcher.suggestions(for: "aodhan'", names: names) == ["Aodhán’s"])

        // Matches both the generated possessive and a story note that already starts with it.
        #expect(
            ChapterEditorNameMatcher.suggestions(for: "Ines'", names: names)
                == ["Ines’s", "Ines’s father"]
        )

        // Apostrophe inside a name matches the name without fabricating a possessive prematurely.
        #expect(ChapterEditorNameMatcher.suggestions(for: "O'", names: names) == ["O'Brien"])
        #expect(ChapterEditorNameMatcher.suggestions(for: "O'Brien'", names: names) == ["O'Brien’s"])

        // Already-typed possessive or non-apostrophe prefix does not show possessive chips.
        #expect(ChapterEditorNameMatcher.suggestions(for: "Marta’s", names: names).isEmpty)
        #expect(ChapterEditorNameMatcher.suggestions(for: "Ma", names: ["Marta"]) == ["Marta"])
    }

    // MARK: - Paragraph numbering from HTML offsets

    @Test func paragraphNumberFromHTMLOffsetHandlesBlocksQuotesInlineTagsEmojiAndPlainText() throws {
        // Matches Studio-Editor.dc.html / Editor-Annotations.dc.html structure:
        // P1 = tide, P2 = Marta, P3 = blockquote, P4 = scene break, P5 = TK.
        let html = """
        <p>The tide had turned.</p>
        <p>Marta said <em>something</em>. She always knew.</p>
        <blockquote><p>If the boat comes back, so does he.</p></blockquote>
        <p align="center">⁂</p>
        <p>The boat’s name, TK, was painted over.</p>
        """

        let p1Offset = try utf16Start(of: "tide", in: html)
        let p2InlineOffset = try utf16Start(of: "She always knew.", in: html)
        let p3QuoteOffset = try utf16Start(of: "If the boat", in: html)
        let p4BreakOffset = try utf16Start(of: "⁂", in: html)
        let p5TKOffset = try utf16Start(of: "TK", in: html)

        #expect(ChapterEditorAnnotationAnchoring.paragraphNumber(atUTF16Offset: p1Offset, in: html) == 1)
        #expect(ChapterEditorAnnotationAnchoring.paragraphNumber(atUTF16Offset: p2InlineOffset, in: html) == 2)
        #expect(ChapterEditorAnnotationAnchoring.paragraphNumber(atUTF16Offset: p3QuoteOffset, in: html) == 3)
        #expect(ChapterEditorAnnotationAnchoring.paragraphNumber(atUTF16Offset: p4BreakOffset, in: html) == 4)
        #expect(ChapterEditorAnnotationAnchoring.paragraphNumber(atUTF16Offset: p5TKOffset, in: html) == 5)

        // Bare blockquote (no inner <p>) and <hr> divider (ignored as a paragraph).
        let bareQuoteHTML = "<p>One</p><hr><blockquote>Direct quote</blockquote><p>Three</p>"
        let bareStart = try utf16Start(of: "Direct quote", in: bareQuoteHTML)
        let afterBare = try utf16Start(of: "Three", in: bareQuoteHTML)
        #expect(ChapterEditorAnnotationAnchoring.paragraphNumber(atUTF16Offset: bareStart, in: bareQuoteHTML) == 2)
        #expect(ChapterEditorAnnotationAnchoring.paragraphNumber(atUTF16Offset: afterBare, in: bareQuoteHTML) == 3)

        // Multi-byte UTF-16 emoji before the target paragraph.
        let emojiHTML = "<p>Hello 👩‍💻 world</p><p>Second paragraph</p>"
        let secondOffset = try utf16Start(of: "Second", in: emojiHTML)
        #expect(ChapterEditorAnnotationAnchoring.paragraphNumber(atUTF16Offset: secondOffset, in: emojiHTML) == 2)

        // Plain text separated by blank lines.
        let plain = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph."
        let plainFirst = try utf16Start(of: "First", in: plain)
        let plainSecond = try utf16Start(of: "Second", in: plain)
        let plainThird = try utf16Start(of: "Third", in: plain)
        #expect(ChapterEditorAnnotationAnchoring.paragraphNumber(atUTF16Offset: plainFirst, in: plain) == 1)
        #expect(ChapterEditorAnnotationAnchoring.paragraphNumber(atUTF16Offset: plainSecond, in: plain) == 2)
        #expect(ChapterEditorAnnotationAnchoring.paragraphNumber(atUTF16Offset: plainThird, in: plain) == 3)

        // Empty HTML or negative offset returns nil.
        #expect(ChapterEditorAnnotationAnchoring.paragraphNumber(atUTF16Offset: 0, in: "") == nil)
        #expect(ChapterEditorAnnotationAnchoring.paragraphNumber(atUTF16Offset: -1, in: html) == nil)
    }

    // MARK: - Annotation list grouping & counts

    @Test func annotationListGroupsIntoNoteTKAndResolvedWithParagraphLocations() throws {
        let html = """
        <p>Fix the tide times here.</p>
        <p>She always knew more than she said.</p>
        <p>The boat’s name, TK, was painted over.</p>
        """
        let p1Offset = try utf16Start(of: "tide times", in: html)
        let p2Offset = try utf16Start(of: "She always knew", in: html)
        let p3Offset = try utf16Start(of: "TK", in: html)

        let chapterID = UUID()
        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let t2 = Date(timeIntervalSince1970: 1_700_100_000)

        let openNote = makeAnnotation(
            chapterID: chapterID, quote: "She always knew", utf16Offset: p2Offset,
            text: "Does Marta already know about the boat?", kind: .note, createdAt: t1
        )
        let openTK = makeAnnotation(
            chapterID: chapterID, quote: "TK", utf16Offset: p3Offset,
            text: "the boat’s name", kind: .tk, createdAt: t1
        )
        let emptyTK = makeAnnotation(
            chapterID: chapterID, quote: "TK", utf16Offset: p3Offset + 2,
            text: "   ", kind: .tk, createdAt: t2
        )
        let resolvedNote = makeAnnotation(
            chapterID: chapterID, quote: "tide times", utf16Offset: p1Offset,
            text: "Fix the tide times (high water 6:40)", kind: .note, createdAt: t1, resolvedAt: t1
        )
        let resolvedTK = makeAnnotation(
            chapterID: chapterID, quote: "TK", utf16Offset: p3Offset,
            text: "harbour depth", kind: .tk, createdAt: t1, resolvedAt: t2
        )

        let all = [resolvedNote, emptyTK, openNote, resolvedTK, openTK]
        let counts = ChapterEditorAnnotationCounts.count(all)
        #expect(counts.openNoteCount == 1)
        #expect(counts.openTKCount == 2)
        #expect(counts.resolvedCount == 2)
        #expect(counts.openTotal == 3)

        let groups = ChapterEditorAnnotationListBuilder.groups(
            from: all,
            in: html,
            lostIDs: [emptyTK.id],
            formatDate: { date in date == t2 ? "Nov 24" : "Nov 22" }
        )

        #expect(groups.map(\.kind) == [.note, .tk, .resolved])

        // Note section.
        let noteRows = groups[0].rows
        #expect(noteRows.map(\.id) == [openNote.id])
        #expect(noteRows[0].paragraphNumber == 2)
        #expect(noteRows[0].locationText == "Paragraph 2")

        // TK section: ordered by utf16Offset; empty text falls back; lost anchor omits paragraph.
        let tkRows = groups[1].rows
        #expect(tkRows.map(\.id) == [openTK.id, emptyTK.id])
        #expect(tkRows[0].displayText == "the boat’s name")
        #expect(tkRows[0].locationText == "Paragraph 3")
        #expect(tkRows[1].displayText == "To come")
        #expect(tkRows[1].isAnchorLost)
        #expect(tkRows[1].paragraphNumber == nil)
        #expect(tkRows[1].locationText == "Anchor not found")

        // Resolved section: most recently resolved first, includes both resolved notes and TKs.
        let resolvedRows = groups[2].rows
        #expect(resolvedRows.map(\.id) == [resolvedTK.id, resolvedNote.id])
        #expect(resolvedRows[0].locationText == "Paragraph 3 · Nov 24")
        #expect(resolvedRows[1].locationText == "Paragraph 1 · Nov 22")
    }

    // MARK: - New note anchor from (html, range)

    @Test func newNoteAnchorBuildsFromHTMLAndUTF16RangeIncludingTagsAndEmoji() throws {
        let html = "<p>Hello 👩‍💻 and <em>She always knew</em> more than she said.</p>"
        let quote = "<em>She always knew</em>"
        let start = try utf16Start(of: quote, in: html)
        let range = RichEditorTextRange(from: start, to: start + quote.utf16.count)

        let anchor = try #require(
            ChapterEditorAnnotationAnchoring.anchorForSelection(html: html, range: range)
        )
        #expect(anchor.quote == quote)
        #expect(anchor.utf16Offset == start)
        #expect(anchor.prefix.hasSuffix(" and "))
        #expect(anchor.suffix.hasPrefix(" more than she said."))
        #expect(anchor.prefix.count <= WritingAnnotationReanchor.contextLimit)
        #expect(anchor.suffix.count <= WritingAnnotationReanchor.contextLimit)

        // Plain preview strips markup for display while leaving stored HTML quote intact.
        #expect(ChapterEditorAnnotationAnchoring.plainQuotePreview(from: anchor.quote) == "She always knew")

        // Round-trips cleanly through the store's re-anchor logic.
        #expect(WritingAnnotationReanchor.reanchor(anchor, in: html) == .placed(anchor))

        // Empty, reversed, negative, and out-of-bounds ranges return nil.
        #expect(
            ChapterEditorAnnotationAnchoring.anchorForSelection(
                html: html,
                range: RichEditorTextRange(from: start, to: start)
            ) == nil
        )
        #expect(
            ChapterEditorAnnotationAnchoring.anchorForSelection(
                html: html,
                range: RichEditorTextRange(from: start + 2, to: start)
            ) == nil
        )
        #expect(
            ChapterEditorAnnotationAnchoring.anchorForSelection(
                html: html,
                range: RichEditorTextRange(from: -1, to: 4)
            ) == nil
        )
        #expect(
            ChapterEditorAnnotationAnchoring.anchorForSelection(
                html: html,
                range: RichEditorTextRange(from: 0, to: html.utf16.count + 5)
            ) == nil
        )
    }

    // MARK: - TK creation from a range

    @Test func tkAnchorUsesDirectRangeAndFallsBackToNearestTKAtOrAfterRange() throws {
        // Direct hit: html[range] is "TK".
        let directHTML = "<p>The boat’s name, TK, was painted over.</p>"
        let tkStart = try utf16Start(of: "TK", in: directHTML)
        let directAnchor = try #require(
            ChapterEditorAnnotationAnchoring.anchorForTK(
                html: directHTML,
                range: RichEditorTextRange(from: tkStart, to: tkStart + 2)
            )
        )
        #expect(directAnchor.quote == "TK")
        #expect(directAnchor.utf16Offset == tkStart)
        #expect(directAnchor.prefix.hasSuffix("name, "))
        #expect(directAnchor.suffix.hasPrefix(", was painted over."))

        // Writer typed on before the TK so it shifted forward; skips TK in href and non-word ATTK.
        let shiftedHTML = "<p>Added <a href=\"https://example.com/TK\">link</a> ATTK then TK here.</p>"
        let realTKStart = try utf16Start(of: "TK here", in: shiftedHTML)
        let shiftedAnchor = try #require(
            ChapterEditorAnnotationAnchoring.anchorForTK(
                html: shiftedHTML,
                range: RichEditorTextRange(from: 3, to: 5)
            )
        )
        #expect(shiftedAnchor.quote == "TK")
        #expect(shiftedAnchor.utf16Offset == realTKStart)
        #expect(shiftedAnchor.prefix.hasSuffix("then "))
        #expect(shiftedAnchor.suffix.hasPrefix(" here."))

        // No TK at or after range.from returns nil.
        let missingHTML = "<p>TK was earlier, nothing later.</p>"
        let laterStart = try utf16Start(of: "nothing", in: missingHTML)
        #expect(
            ChapterEditorAnnotationAnchoring.anchorForTK(
                html: missingHTML,
                range: RichEditorTextRange(from: laterStart, to: laterStart + 2)
            ) == nil
        )
    }

    // MARK: - Store bridge, status counts, menu wiring, and DraftSession integration

    @Test func bridgePersistsAnnotationsUpdatesCountsAndKeepsChapterHTMLClean() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(
            "chapter-editor-annotations-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WritingDocumentStore(root: root, deviceID: "test-device")
        let bridge = ChapterEditorDocumentBridge(store: store)

        // Before opening a local work, no story names or annotations exist.
        #expect(bridge.workID == nil)
        #expect(bridge.storyNoteNames.isEmpty)
        #expect(ChapterEditorNameMatcher.suggestions(for: "Ma", names: bridge.storyNoteNames).isEmpty)

        let bodyHTML = "<p>Marta waited on the wall.</p><p>The boat, TK, sat in the mud.</p>"
        let payload = ChapterEditorChapterPayload(
            workTitle: "What the Tide Keeps",
            chapterTitle: "Slack Water",
            summary: "",
            notesBefore: "",
            notesAfter: "",
            bodyHTML: bodyHTML,
            ao3ChapterID: nil,
            status: .local
        )
        let opened = try #require(
            await bridge.open(target: .local(workID: nil, chapterID: nil), initialPayload: payload)
        )
        #expect(bridge.annotationCount == 0)
        #expect(bridge.tkCount == 0)

        await bridge.addStoryNote(kind: .character, name: "Marta", detail: "Carries shoes", pinned: false)
        await bridge.addStoryNote(kind: .place, name: "Harbour Wall", detail: "Faces west", pinned: false)
        #expect(bridge.storyNoteNames == ["Marta", "Harbour Wall"])
        #expect(ChapterEditorNameMatcher.suggestions(for: "Ma", names: bridge.storyNoteNames) == ["Marta"])

        let noteStart = try utf16Start(of: "Marta waited", in: bodyHTML)
        let noteAnchor = try #require(
            ChapterEditorAnnotationAnchoring.anchorForSelection(
                html: bodyHTML,
                range: RichEditorTextRange(from: noteStart, to: noteStart + "Marta waited".utf16.count)
            )
        )
        let createdNote = try #require(
            await bridge.addAnnotation(anchor: noteAnchor, text: "Check timeline", kind: .note)
        )

        let tkStart = try utf16Start(of: "TK", in: bodyHTML)
        let tkAnchor = try #require(
            ChapterEditorAnnotationAnchoring.anchorForTK(
                html: bodyHTML,
                range: RichEditorTextRange(from: tkStart, to: tkStart + 2)
            )
        )
        let createdTK = try #require(
            await bridge.addAnnotation(anchor: tkAnchor, text: "the boat’s name", kind: .tk)
        )

        #expect(bridge.annotationCount == 1)
        #expect(bridge.tkCount == 1)
        let status = EditorStatusSummary(
            wordsToday: 120,
            noteCount: bridge.annotationCount,
            tkCount: bridge.tkCount,
            syncState: .saved
        )
        #expect(status.trailingStatusText == "1 note · 1 TK · Saved")

        // Annotations never leak into body.html.
        let loadedChapter = try await store.loadChapter(
            workID: opened.work.id,
            chapterID: opened.activeChapter.id
        )
        let containsNote = loadedChapter.bodyHTML.contains("Check timeline")
        let containsTKDesc = loadedChapter.bodyHTML.contains("the boat’s name")
        #expect(!containsNote)
        #expect(!containsTKDesc)

        // Resolving and deleting update open counts immediately.
        _ = try #require(await bridge.setAnnotationResolved(createdNote, resolved: true))
        #expect(bridge.annotationCount == 0)
        #expect(bridge.tkCount == 1)

        let deleted = await bridge.deleteAnnotation(createdTK.id)
        #expect(deleted)
        #expect(bridge.annotationCount == 0)
        #expect(bridge.tkCount == 0)
    }

    @Test func sessionSyncsUnresolvedHighlightsAndCompletesWords() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(
            "chapter-editor-session-ann-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WritingDocumentStore(root: root, deviceID: "test-device")
        let bridge = ChapterEditorDocumentBridge(store: store)

        let bodyHTML = "<p>Marta waited on the wall.</p><p>The boat, TK, sat in the mud.</p>"
        let payload = ChapterEditorChapterPayload(
            workTitle: "What the Tide Keeps",
            chapterTitle: "Slack Water",
            summary: "",
            notesBefore: "",
            notesAfter: "",
            bodyHTML: bodyHTML,
            ao3ChapterID: nil,
            status: .local
        )
        _ = try #require(
            await bridge.open(target: .local(workID: nil, chapterID: nil), initialPayload: payload)
        )

        let noteStart = try utf16Start(of: "Marta waited", in: bodyHTML)
        let noteAnchor = try #require(
            ChapterEditorAnnotationAnchoring.anchorForSelection(
                html: bodyHTML,
                range: RichEditorTextRange(from: noteStart, to: noteStart + "Marta waited".utf16.count)
            )
        )
        let createdNote = try #require(
            await bridge.addAnnotation(anchor: noteAnchor, text: "Check timeline", kind: .note)
        )
        let tkStart = try utf16Start(of: "TK", in: bodyHTML)
        let tkAnchor = try #require(
            ChapterEditorAnnotationAnchoring.anchorForTK(
                html: bodyHTML,
                range: RichEditorTextRange(from: tkStart, to: tkStart + 2)
            )
        )
        let createdTK = try #require(
            await bridge.addAnnotation(anchor: tkAnchor, text: "the boat’s name", kind: .tk)
        )

        let source = FakeSourceEditor(text: bodyHTML)
        let transport = RecordingAnnotationTransport(html: bodyHTML)
        let session = DraftSession(
            initialText: bodyHTML,
            fieldVariant: .content,
            source: source,
            clock: TestWritingClock(),
            richTransport: transport
        )
        defer { session.teardown() }

        let switchOutcome = await session.switchToRich()
        #expect(switchOutcome == .switched)

        let report = try #require(await bridge.reanchorAnnotations(in: session.text))
        let items = ChapterEditorAnnotationAnchoring.bridgeItems(from: report.placed)
        #expect(items.count == 2)
        #expect(items.contains { $0.id == createdNote.id.uuidString && $0.kind == "note" })
        #expect(items.contains { $0.id == createdTK.id.uuidString && $0.kind == "tk" })

        _ = await session.setAnnotations(items)
        #expect(transport.setAnnotationBatches.last == items)

        // Resolving excludes the resolved note from drawn highlights.
        _ = try #require(await bridge.setAnnotationResolved(createdNote, resolved: true))
        let afterResolve = try #require(await bridge.reanchorAnnotations(in: session.text))
        let remainingItems = ChapterEditorAnnotationAnchoring.bridgeItems(from: afterResolve.placed)
        #expect(remainingItems.map(\.id) == [createdTK.id.uuidString])
        _ = await session.setAnnotations(remainingItems)
        #expect(transport.setAnnotationBatches.last?.map(\.id) == [createdTK.id.uuidString])

        // Deleting clears all drawn highlights.
        _ = await bridge.deleteAnnotation(createdTK.id)
        let afterDelete = try #require(await bridge.reanchorAnnotations(in: session.text))
        let emptyItems = ChapterEditorAnnotationAnchoring.bridgeItems(from: afterDelete.placed)
        #expect(emptyItems.isEmpty)
        _ = await session.setAnnotations(emptyItems)
        #expect(transport.setAnnotationBatches.last?.isEmpty == true)

        // Tapping a name chip invokes `completeWord`.
        session.completeWord("Marta’s")
        await Task.yield()
        await Task.yield()
        #expect(
            transport.commandCalls.contains {
                $0.name == "completeWord" && $0.attrs["text"] == .string("Marta’s")
            }
        )
    }

    #if os(iOS)
    @Test func keysAccessoryViewUpdatesAndClearsLeadingSlotInPlace() {
        let accessory = WritingKeysInputAccessoryView(onAction: { _ in })
        #expect(!accessory.hasLeadingContent)

        accessory.updateLeadingSlot(hasContent: true) {
            WritingNameSuggestionChips(suggestions: ["Marta", "Marta’s"], onSelect: { _ in })
        }
        #expect(accessory.hasLeadingContent)

        accessory.clearLeadingSlot()
        #expect(!accessory.hasLeadingContent)
    }
    #endif

    @Test func tkAndAnnotationTapSequenceTrackersAndMoreMenuAddNoteWiring() {
        var tkTracker = ChapterEditorTKTracker()
        let firstTK = DraftTypedTK(sequence: 1, range: RichEditorTextRange(from: 10, to: 12))
        let acceptedFirst = tkTracker.receive(firstTK)
        #expect(acceptedFirst)
        #expect(tkTracker.activeTK == firstTK)

        let duplicateFirst = tkTracker.receive(firstTK)
        #expect(!duplicateFirst)

        tkTracker.dismiss()
        #expect(tkTracker.activeTK == nil)
        let redeliveredFirst = tkTracker.receive(firstTK)
        #expect(!redeliveredFirst)

        let secondTK = DraftTypedTK(sequence: 2, range: RichEditorTextRange(from: 24, to: 26))
        let acceptedSecond = tkTracker.receive(secondTK)
        #expect(acceptedSecond)
        #expect(tkTracker.activeTK == secondTK)

        var tapTracker = ChapterEditorAnnotationTapTracker()
        let tap1 = DraftAnnotationTap(sequence: 1, id: "abc")
        let firstTapID = tapTracker.receive(tap1)
        #expect(firstTapID == "abc")
        let duplicateTapID = tapTracker.receive(tap1)
        #expect(duplicateTapID == nil)
        let tap2 = DraftAnnotationTap(sequence: 2, id: "abc")
        let secondTapID = tapTracker.receive(tap2)
        #expect(secondTapID == "abc")

        // ••• menu exposes Add Note when `canAddNote` is true and hides it when false.
        var fired: [String] = []
        let richCaps = ChapterEditorMenuCapabilities(canAddNote: true, canFormat: true)
        let wiring = ChapterEditorMoreMenuWiring(
            capabilities: richCaps,
            handlers: ChapterEditorMoreMenuHandlers(
                addNote: { fired.append("addNote") },
                format: { fired.append("format") }
            )
        )
        let model = wiring.model()
        #expect(model.documentItems.map(\.id) == [.addNote, .format])
        wiring.actions().dispatch(.addNote)
        #expect(fired == ["addNote"])

        let htmlCaps = ChapterEditorMenuCapabilities(canAddNote: false, canFormat: false)
        let htmlModel = htmlCaps.menuModel()
        #expect(!htmlModel.allVisibleActionIDs.contains(.addNote))
    }

    // MARK: - Helpers

    private func utf16Start(of needle: String, in haystack: String) throws -> Int {
        let range = try #require(haystack.range(of: needle))
        return haystack.utf16.distance(from: haystack.utf16.startIndex, to: range.lowerBound)
    }

    private func makeAnnotation(
        chapterID: UUID,
        quote: String,
        utf16Offset: Int,
        text: String,
        kind: WritingAnnotationKind,
        createdAt: Date,
        resolvedAt: Date? = nil
    ) -> WritingAnnotation {
        WritingAnnotation(
            id: UUID(),
            chapterID: chapterID,
            quote: quote,
            prefix: "",
            suffix: "",
            utf16Offset: utf16Offset,
            text: text,
            createdAt: createdAt,
            resolvedAt: resolvedAt,
            kind: kind,
            updatedAt: resolvedAt ?? createdAt,
            updatedBy: "test-device"
        )
    }
}

/// Minimal `RichEditorBridgeTransport` double that records `setAnnotations` batches and commands.
@MainActor
private final class RecordingAnnotationTransport: RichEditorBridgeTransport {
    var onEvent: (@MainActor (RichEditorEvent) -> Void)?
    var onProcessTerminated: (@MainActor () -> Void)?

    var storedHTML: String
    private(set) var setAnnotationBatches: [[RichEditorAnnotationItem]] = []
    private(set) var commandCalls: [RichEditorCommandArgs] = []

    init(html: String) {
        self.storedHTML = html
    }

    func configure(_ args: RichEditorConfigureArgs) async throws -> RichEditorConfigureResult {
        RichEditorConfigureResult(
            bridgeVersion: RichEditorBridgeProtocol.bridgeVersion,
            schemaVersion: RichEditorBridgeProtocol.schemaVersion,
            bundleVersion: "test"
        )
    }

    func load(_ args: RichEditorLoadArgs) async throws -> RichEditorLoadResult {
        storedHTML = args.html
        return RichEditorLoadResult(revision: args.revision, loss: .empty, timing: .zero)
    }

    func activate(_ args: RichEditorActivateArgs) async throws -> RichEditorActivateResult {
        RichEditorActivateResult(caretFound: args.caret != nil)
    }

    func freeze() async throws -> RichEditorFreezeResult {
        RichEditorFreezeResult(revision: 0)
    }

    func snapshot(_ args: RichEditorSnapshotArgs) async throws -> RichEditorSnapshotResult {
        RichEditorSnapshotResult(revision: 0, html: storedHTML, caretOffset: nil, words: 0)
    }

    func command(_ args: RichEditorCommandArgs) async throws -> RichEditorCommandResult {
        commandCalls.append(args)
        return RichEditorCommandResult(applied: true)
    }

    func lint(_ args: RichEditorLintArgs) async throws -> RichEditorLintResult {
        RichEditorLintResult(loss: .empty)
    }

    func setTheme(_ theme: RichEditorTheme) async throws {}
    func setAppearance(_ appearance: RichEditorAppearance) async throws {}

    func setAnnotations(_ args: RichEditorAnnotationsArgs) async throws -> RichEditorAnnotationsResult {
        setAnnotationBatches.append(args.items)
        return RichEditorAnnotationsResult(
            placed: args.items.map {
                RichEditorAnnotationsResult.Placed(id: $0.id, found: $0.to > $0.from)
            }
        )
    }

    func dispose() async throws {}

    func verifySwitch(_ args: RichEditorSwitchCheckArgs) async throws -> RichEditorSwitchCheckResult {
        RichEditorSwitchCheckResult(ok: true, candidateHtml: args.html, reason: nil)
    }

    func focusWebView() {}
    func resetAfterTermination() {}
}
