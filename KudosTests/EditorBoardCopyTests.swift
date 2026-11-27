import Foundation
import Testing
@testable import Kudos

/// Regression tests for board-matched editor copy, row meta lines, counts, and empty states
/// across `Studio-Editor`, `Editor-Typing`, `Editor-Format`, `Editor-Notes`, `Editor-Annotations`,
/// `Editor-Names`, and `Editor-Beta` (T-507 editor detail sweep).
/// Depends only on a plain test host: no network, no AO3, no WebView.
@MainActor
struct EditorBoardCopyTests {
    // MARK: - Studio-Editor & Editor-Typing: Sprint pill and chapter notes headers

    @Test func sprintPillCopyFormatsPositiveWordDeltaAndSingularPlural() {
        #expect(EditorSprintCopy.wordsBadgeText(words: 312) == "+312 words")
        #expect(EditorSprintCopy.wordsBadgeText(words: 1) == "+1 word")
        #expect(EditorSprintCopy.wordsBadgeText(words: 0) == "+0 words")
        #expect(EditorSprintCopy.wordsBadgeText(words: -5) == "+0 words")

        #expect(EditorSprintCopy.accessibilityWordsSuffix(words: 312) == "312 words so far")
        #expect(EditorSprintCopy.accessibilityWordsSuffix(words: 1) == "1 word so far")
        #expect(EditorSprintCopy.accessibilityWordsSuffix(words: 0) == "0 words so far")
    }

    @Test func chapterNotesHeaderTrailingMatchesStudioEditorBoard() {
        let normalSummary = CharacterLimitStatus.evaluate(count: 46, limit: 1_250)
        // Collapsed Summary hides its normal counter so the one-line preview has room.
        #expect(
            ChapterNoteField.summary.headerTrailing(
                isExpanded: false,
                showsCollapsedPreview: true,
                status: normalSummary
            ) == .none
        )
        // Expanded Summary shows the live character counter.
        #expect(
            ChapterNoteField.summary.headerTrailing(
                isExpanded: true,
                showsCollapsedPreview: true,
                status: normalSummary
            ) == .counter(normalSummary.counterText)
        )
        // Warning and over-limit counters remain visible even while collapsed.
        let warnSummary = CharacterLimitStatus.evaluate(count: 1_200, limit: 1_250)
        #expect(
            ChapterNoteField.summary.headerTrailing(
                isExpanded: false,
                showsCollapsedPreview: true,
                status: warnSummary
            ) == .counter(warnSummary.counterText)
        )

        let normalBefore = CharacterLimitStatus.evaluate(count: 72, limit: 5_000)
        #expect(
            ChapterNoteField.notesBefore.headerTrailing(
                isExpanded: true,
                showsCollapsedPreview: false,
                status: normalBefore
            ) == .counter(normalBefore.counterText)
        )
        let emptyBefore = CharacterLimitStatus.evaluate(count: 0, limit: 5_000)
        #expect(
            ChapterNoteField.notesBefore.headerTrailing(
                isExpanded: false,
                showsCollapsedPreview: false,
                status: emptyBefore
            ) == .none
        )

        // Notes after shows "Shown at the end on AO3" in its header while normal,
        // and switches to the limit counter once warning/exceeded.
        let normalAfter = CharacterLimitStatus.evaluate(count: 65, limit: 5_000)
        #expect(
            ChapterNoteField.notesAfter.headerTrailing(
                isExpanded: true,
                showsCollapsedPreview: false,
                status: normalAfter
            ) == .helper("Shown at the end on AO3")
        )
        #expect(
            ChapterNoteField.notesAfter.headerTrailing(
                isExpanded: false,
                showsCollapsedPreview: false,
                status: normalAfter
            ) == .helper("Shown at the end on AO3")
        )
        let overAfter = CharacterLimitStatus.evaluate(count: 5_001, limit: 5_000)
        #expect(
            ChapterNoteField.notesAfter.headerTrailing(
                isExpanded: true,
                showsCollapsedPreview: false,
                status: overAfter
            ) == .counter(overAfter.counterText)
        )
    }

    // MARK: - Editor-Typing & Editor-Names: Writing keys bar labels

    @Test func writingKeysBarAccessibilityLabelsMatchTypingAndNamesBoards() {
        #expect(WritingKeyID.cursorLeft.accessibilityLabel == "Move left")
        #expect(WritingKeyID.cursorRight.accessibilityLabel == "Move right")
        #expect(WritingKeyID.barAccessibilityLabel(hasNameSuggestions: false) == "Writing keys")
        #expect(
            WritingKeyID.barAccessibilityLabel(hasNameSuggestions: true)
                == "Writing keys with name suggestions"
        )
    }

    // MARK: - Editor-Format: Paragraph, mark, alignment, and direction copy

    @Test func formatPanelLabelsMatchEditorFormatBoard() {
        #expect(
            FormatBlock.allCases.map(\.title) == [
                "Body", "Heading", "Subheading", "Centred",
                "Quote", "• List", "1. List", "Fold-out",
            ]
        )
        #expect(
            FormatMark.allCases.map(\.buttonGlyph) == [
                "B", "I", "U", "S", "x²", "x₂", "sm", "‹›",
            ]
        )
        #expect(
            FormatMark.allCases.map(\.accessibilityLabel) == [
                "Bold", "Italic", "Underline", "Strikethrough",
                "Superscript", "Subscript", "Smaller text", "Code",
            ]
        )
        #expect(
            FormatAlignment.allCases.map(\.accessibilityLabel) == [
                "Align left", "Centre", "Align right", "Justify",
            ]
        )
        #expect(
            FormatDirection.allCases.map(\.decoratedTitle) == [
                "¶→ Left to right", "Right to left ←¶",
            ]
        )
    }

    // MARK: - Editor-Notes & Editor-Annotations: Unified list, detail header, and empty copy

    @Test func annotationCopyAndFlatRowsMatchEditorAnnotationsBoard() throws {
        #expect(ChapterEditorAnnotationCopy.inThisChapterSectionTitle == "In this chapter")
        #expect(ChapterEditorAnnotationCopy.emptyChapterNotesTitle == "No Notes in This Chapter")
        #expect(ChapterEditorAnnotationCopy.newNoteButtonTitle == "New Note")

        #expect(
            ChapterEditorAnnotationCopy.detailHeaderLabel(
                kind: .note,
                isResolved: false,
                dateText: "Nov 24",
                paragraphNumber: nil
            ) == "Your note · Nov 24"
        )
        #expect(
            ChapterEditorAnnotationCopy.detailHeaderLabel(
                kind: .note,
                isResolved: false,
                dateText: "Nov 24",
                paragraphNumber: 2
            ) == "Your note · Nov 24 · Paragraph 2"
        )
        #expect(
            ChapterEditorAnnotationCopy.detailHeaderLabel(
                kind: .tk,
                isResolved: false,
                dateText: "Nov 24",
                paragraphNumber: 5
            ) == "TK · Nov 24 · Paragraph 5"
        )
        #expect(
            ChapterEditorAnnotationCopy.detailHeaderLabel(
                kind: .note,
                isResolved: true,
                dateText: "Nov 22",
                paragraphNumber: 1
            ) == "Resolved · Nov 22 · Paragraph 1"
        )

        let html = """
        <p>Fix the tide times here.</p>
        <p>She always knew more than she said.</p>
        <blockquote><p>If the boat comes back, so does he.</p></blockquote>
        <p align="center">⁂</p>
        <p>The boat’s name, TK, was painted over.</p>
        """
        let p1 = try utf16Start(of: "tide times", in: html)
        let p2 = try utf16Start(of: "She always knew", in: html)
        let p5 = try utf16Start(of: "TK", in: html)
        let chapterID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let resolved = WritingAnnotation(
            id: UUID(),
            chapterID: chapterID,
            quote: "tide times",
            prefix: "",
            suffix: "",
            utf16Offset: p1,
            text: "Fix the tide times (high water 6:40)",
            createdAt: date,
            resolvedAt: date,
            kind: .note,
            updatedAt: date,
            updatedBy: "test-device"
        )
        let note = WritingAnnotation(
            id: UUID(),
            chapterID: chapterID,
            quote: "She always knew",
            prefix: "",
            suffix: "",
            utf16Offset: p2,
            text: "Does Marta already know about the boat?",
            createdAt: date,
            resolvedAt: nil,
            kind: .note,
            updatedAt: date,
            updatedBy: "test-device"
        )
        let tkMarker = WritingAnnotation(
            id: UUID(),
            chapterID: chapterID,
            quote: "TK",
            prefix: "",
            suffix: "",
            utf16Offset: p5,
            text: "the boat’s name",
            createdAt: date,
            resolvedAt: nil,
            kind: .tk,
            updatedAt: date,
            updatedBy: "test-device"
        )

        let flat = ChapterEditorAnnotationListBuilder.flatRows(
            from: [resolved, tkMarker, note],
            in: html,
            formatDate: { _ in "Nov 22" }
        )
        #expect(flat.map(\.group) == [.note, .tk, .resolved])
        #expect(flat.map(\.group.badgeTitle) == ["Note", "TK", "Resolved"])
        #expect(flat.map(\.locationText) == ["Paragraph 2", "Paragraph 5", "Paragraph 1 · Nov 22"])
    }

    // MARK: - Editor-Beta: Headings, row meta, counts, and empty states

    @Test func betaReadingCopyMatchesEditorBetaBoard() {
        #expect(BetaReadingCopy.screenTitle == "Beta Reading")
        #expect(
            BetaReadingCopy.chapterSubtitle(chapterNumber: 4, chapterTitle: "Slack Water")
                == "Chapter 4 · Slack Water"
        )
        #expect(
            BetaReadingCopy.chapterSubtitle(chapterNumber: 5, chapterTitle: "   ")
                == "Chapter 5 · Untitled"
        )
        #expect(
            BetaReadingCopy.chapterSubtitle(chapterNumber: nil, chapterTitle: "Prologue")
                == "Prologue"
        )
        #expect(BetaReadingCopy.sendSectionTitle == "Send a copy")
        #expect(
            BetaReadingCopy.sendSectionFooter
                == "Each beta gets their own copy, so their notes don’t sway each other."
        )
        #expect(BetaReadingCopy.withYourBetasSectionTitle == "With your betas")
        #expect(
            BetaReadingCopy.sentCopyDetail(format: .docx, dateText: "Nov 20")
                == "Word or Google Docs · sent Nov 20"
        )
        #expect(
            BetaReadingCopy.sentCopyDetail(format: .pdf, dateText: "Nov 22")
                == "PDF · sent Nov 22"
        )
        #expect(BetaReadingCopy.reviewAllButtonTitle(remainingCount: 10) == "Review All 10")
        #expect(BetaReadingCopy.reviewAllButtonTitle(remainingCount: -1) == "Review All 0")
        #expect(
            BetaReadingCopy.emptyComparisonMessage(betaName: "Lark")
                == "Lark’s copy matched what you sent, with no suggestions or comments."
        )
        #expect(
            BetaReadingCopy.footerPromise
                == "Kudos saves a version of the chapter before anything comes in. "
                + "Nothing changes until you accept it."
        )

        let now = Date(timeIntervalSince1970: 1_763_650_800)
        let suggestions = (0 ..< 6).map { index in
            BetaSuggestionItem(
                author: "Lark",
                isTracked: true,
                paragraphIndex: index,
                paragraphText: "Sample paragraph.",
                paragraphPrefix: "",
                paragraphSuffix: "",
                paragraphUTF16Offset: 0,
                editStartUTF16: 0,
                editEndUTF16: 6,
                deletedText: "Sample",
                insertedText: "Edited",
                localPrefix: "",
                localSuffix: " paragraph."
            )
        }
        let comments = (0 ..< 4).map { index in
            BetaCommentItem(
                author: "Lark",
                quote: "Sample",
                text: "Note \(index)",
                paragraphIndex: index,
                characterOffsetUTF16: 0
            )
        }
        let populated = BetaCopyRecord(
            id: UUID(),
            betaName: "Lark",
            format: .docx,
            sentAt: now,
            sentHTML: "<p>Sample paragraph.</p>",
            returnedAt: now,
            status: .cameBack,
            hasSnapshottedBeforeAccept: false,
            suggestions: suggestions,
            comments: comments,
            updatedAt: now,
            updatedBy: "test-device"
        )
        #expect(populated.reviewSectionTitle == "Lark’s edits · 6 suggestions, 4 comments")

        var emptyCopy = populated
        emptyCopy.suggestions = []
        emptyCopy.comments = []
        #expect(emptyCopy.reviewSectionTitle == "Lark’s edits · No changes found")
    }

    // MARK: - Helpers

    private func utf16Start(of needle: String, in haystack: String) throws -> Int {
        let range = try #require(haystack.range(of: needle))
        return haystack.utf16.distance(from: haystack.utf16.startIndex, to: range.lowerBound)
    }
}
