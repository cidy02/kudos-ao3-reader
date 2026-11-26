import Foundation
import SwiftUI
import Testing
#if os(iOS)
import UIKit
#endif
@testable import Kudos

@MainActor
struct EditorChromeTests {
    // MARK: - FormatPanel & FormatCommand coverage

    @Test func formatPanelCoversEveryFormatCommandCase() throws {
        var emitted: [FormatCommand] = FormatPanelControl.allDirectControls.map(\.command)

        // Link form: add/edit link and remove link when in a link.
        let linkDraft = FormatLinkDraft(address: " https://archiveofourown.org/works/123 ", isInLink: true)
        emitted.append(try #require(linkDraft.submitCommand()))
        emitted.append(try #require(linkDraft.removeCommand()))

        // Image form: address, description, width, height.
        let imageDraft = FormatImageDraft(
            address: "https://example.com/boat.png",
            description: "Harbour at slack water",
            widthText: "640",
            heightText: "480"
        )
        emitted.append(try #require(imageDraft.submitCommand()))

        let expectedImage = FormatImageSpec(
            address: "https://example.com/boat.png",
            description: "Harbour at slack water",
            width: 640,
            height: 480
        )

        // Verify every mark, block, alignment, direction, scene break, and standalone command.
        for mark in FormatMark.allCases {
            #expect(emitted.contains(.toggleMark(mark)))
        }
        for block in FormatBlock.allCases {
            #expect(emitted.contains(.setBlock(block)))
        }
        for alignment in FormatAlignment.allCases {
            #expect(emitted.contains(.setAlignment(alignment)))
        }
        for direction in FormatDirection.allCases {
            #expect(emitted.contains(.setDirection(direction)))
        }
        for style in SceneBreakStyle.allCases {
            #expect(emitted.contains(.insertSceneBreak(style)))
        }

        #expect(emitted.contains(.setLink(url: "https://archiveofourown.org/works/123")))
        #expect(emitted.contains(.unlink))
        #expect(emitted.contains(.insertImage(expectedImage)))
        #expect(emitted.contains(.insertFootnote))
        #expect(emitted.contains(.openTableInHTML))
        #expect(emitted.contains(.undo))
        #expect(emitted.contains(.redo))
        #expect(emitted.contains(.clearFormatting))

        // Confirm every FormatCommand enum case was produced by at least one FormatPanel control/form.
        let coveredKinds = Set(emitted.map(Self.commandKind))
        #expect(coveredKinds.count == 13)
    }

    private static func commandKind(_ command: FormatCommand) -> String {
        switch command {
        case .toggleMark: "toggleMark"
        case .setBlock: "setBlock"
        case .setAlignment: "setAlignment"
        case .setDirection: "setDirection"
        case .setLink: "setLink"
        case .unlink: "unlink"
        case .insertImage: "insertImage"
        case .insertSceneBreak: "insertSceneBreak"
        case .insertFootnote: "insertFootnote"
        case .openTableInHTML: "openTableInHTML"
        case .undo: "undo"
        case .redo: "redo"
        case .clearFormatting: "clearFormatting"
        }
    }

    @Test func formatPanelFormsValidateLinksAndImagesForAO3() {
        // Link form rejects javascript: and bare text, accepts http/https/mailto.
        let unsafeLink = FormatLinkDraft(address: "javascript:alert(1)", isInLink: false)
        #expect(!unsafeLink.canSubmit)
        #expect(unsafeLink.showsValidationHint)
        #expect(unsafeLink.submitCommand() == nil)
        #expect(unsafeLink.removeCommand() == nil)

        let mailtoLink = FormatLinkDraft(address: "mailto:author@example.com", isInLink: false)
        #expect(mailtoLink.canSubmit)
        #expect(mailtoLink.submitCommand() == .setLink(url: "mailto:author@example.com"))

        // Image form allows only http/https and optional positive pixel dimensions.
        let mailtoImage = FormatImageDraft(address: "mailto:author@example.com")
        #expect(!mailtoImage.canSubmit)
        #expect(mailtoImage.submitCommand() == nil)

        let badSizeImage = FormatImageDraft(address: "https://example.com/a.jpg", widthText: "-10")
        #expect(!badSizeImage.canSubmit)
        #expect(!badSizeImage.areDimensionsValid)

        let noSizeImage = FormatImageDraft(address: "http://example.com/a.jpg", description: "  Boat  ")
        #expect(noSizeImage.canSubmit)
        #expect(
            noSizeImage.submitCommand()
                == .insertImage(FormatImageSpec(address: "http://example.com/a.jpg", description: "Boat"))
        )
    }

    @Test func formatStateReportsActiveMarks() {
        let state = FormatState(activeMarks: [.italic, .code], block: .quote, canUndo: true)
        #expect(state.isActive(.italic))
        #expect(state.isActive(.code))
        #expect(!state.isActive(.bold))
        #expect(state.block == .quote)
    }

    // MARK: - ChapterNotesBlocks counters and thresholds

    @Test func summaryCounterThresholdsFollowAO3Limit() {
        #expect(AO3ChapterFieldLimit.summary.characterLimit == 1_250)
        #expect(ChapterNoteField.summary.limit == .summary)

        let empty = CharacterLimitStatus.evaluate(count: 0, limit: 1_250)
        #expect(empty.severity == .normal)
        #expect(empty.counterText == "0 / 1,250")
        #expect(empty.overLimitMessage == nil)

        // Just below 10% threshold (126 remaining > 125).
        let stillNormal = CharacterLimitStatus.evaluate(count: 1_124, limit: 1_250)
        #expect(stillNormal.severity == .normal)

        // Exactly 10% remaining (125 left = 1,125 typed) turns amber.
        let atWarningStart = CharacterLimitStatus.evaluate(count: 1_125, limit: 1_250)
        #expect(atWarningStart.severity == .warning)
        #expect(atWarningStart.overLimitMessage == nil)

        // At exact limit stays amber (still accepted by AO3).
        let atLimit = CharacterLimitStatus.evaluate(count: 1_250, limit: 1_250)
        #expect(atLimit.severity == .warning)
        #expect(atLimit.overLimitMessage == nil)

        // Over limit turns red with the AO3 rejection message.
        let overLimit = CharacterLimitStatus.evaluate(count: 1_251, limit: 1_250)
        #expect(overLimit.severity == .exceeded)
        #expect(overLimit.overLimitMessage == "AO3 won't accept more than 1,250 characters")
    }

    @Test func chapterNotesCounterThresholdsFollowAO3Limit() {
        #expect(AO3ChapterFieldLimit.notes.characterLimit == 5_000)
        #expect(ChapterNoteField.notesBefore.limit == .notes)
        #expect(ChapterNoteField.notesAfter.limit == .notes)

        #expect(CharacterLimitStatus.evaluate(count: 4_499, limit: 5_000).severity == .normal)
        #expect(CharacterLimitStatus.evaluate(count: 4_500, limit: 5_000).severity == .warning)
        #expect(CharacterLimitStatus.evaluate(count: 5_000, limit: 5_000).severity == .warning)

        let over = CharacterLimitStatus.evaluate(
            text: String(repeating: "x", count: 5_001),
            field: .notes
        )
        #expect(over.severity == .exceeded)
        #expect(over.counterText == "5,001 / 5,000")
        #expect(over.overLimitMessage == "AO3 won't accept more than 5,000 characters")
    }

    // MARK: - EditorStatusLine text & progress

    @Test func editorStatusLineFormatsGoalNotesSyncAndDraftChip() {
        let summary = EditorStatusSummary(
            wordsToday: 640,
            dailyGoal: 1_000,
            noteCount: 1,
            tkCount: 1,
            syncState: .saved,
            ao3DraftDaysLeft: 22,
            chapterWordCount: 2_060
        )

        #expect(summary.goalProgress == 0.64)
        #expect(summary.goalLineText == "640 today · 360 to your goal")
        #expect(summary.goalAccessibilityLabel == "640 words today, 360 to your goal")
        #expect(summary.trailingStatusText == "1 note · 1 TK · Saved")
        #expect(summary.trailingAccessibilityLabel == "1 note, 1 TK marker, Saved")
        #expect(summary.ao3DraftChipText == "AO3 draft · 22 days left")
        #expect(summary.chapterWordCountText == "2,060 words")
    }

    @Test func editorStatusLineHandlesGoalReachedZeroCountsAndLastDay() {
        let reached = EditorStatusSummary(
            wordsToday: 1_250,
            dailyGoal: 1_000,
            noteCount: 0,
            tkCount: 0,
            syncState: .synced(device: "Mac"),
            ao3DraftDaysLeft: 0
        )
        #expect(reached.goalProgress == 1.0)
        #expect(reached.goalLineText == "1,250 today · Goal reached")
        #expect(reached.trailingStatusText == "Synced with your Mac")
        #expect(reached.ao3DraftChipText == "AO3 draft · Last day")

        let noGoal = EditorStatusSummary(
            wordsToday: 1,
            dailyGoal: nil,
            noteCount: 2,
            tkCount: 3,
            syncState: .saving,
            ao3DraftDaysLeft: 1
        )
        #expect(noGoal.goalLineText == "1 today")
        #expect(noGoal.goalAccessibilityLabel == "1 word today")
        #expect(noGoal.trailingStatusText == "2 notes · 3 TK · Saving…")
        #expect(noGoal.trailingAccessibilityLabel == "2 notes, 3 TK markers, Saving…")
        #expect(noGoal.ao3DraftChipText == "AO3 draft · 1 day left")
    }

    // MARK: - EditorMoreMenu draft vs posted-chapter variant

    @Test func editorMoreMenuDraftVariantMatchesDesignOrderAndSections() {
        let model = EditorMoreMenuModel.build(
            isPosted: false,
            hasUnpostedChanges: true,
            savedVersionCount: 14,
            deviceName: "iPhone"
        )

        #expect(model.topRow.map(\.title) == ["Post", "Preview", "Share", "Find"])
        #expect(
            model.ao3Items.map(\.title)
                == ["Save as AO3 Draft", "Chapter Title, Summary and Notes", "Work Details", "Edit Tags"]
        )
        #expect(model.ao3Items.first?.subtitle == "AO3 keeps drafts for 29 days")
        #expect(model.exportFormats.map(\.title) == ["EPUB", "PDF", "Word", "HTML", "Markdown", "Plain Text"])
        #expect(model.exportItems.map(\.title) == ["Copy as AO3 HTML", "Send to a Beta", "Print"])
        #expect(model.documentItems.map(\.title) == ["Version History", "Writing Tools"])
        #expect(model.documentItems.first?.subtitle == "14 saved versions on this iPhone")
        #expect(model.deleteItem.title == "Delete Chapter")
        #expect(model.deleteItem.isDestructive)
        #expect(!model.showsUnpostedDot)
    }

    @Test func editorMoreMenuPostedVariantSwapsPostAddsDiffAndShowsDot() {
        let dirtyPosted = EditorMoreMenuModel.build(
            isPosted: true,
            hasUnpostedChanges: true,
            savedVersionCount: 1,
            deviceName: "Mac"
        )

        #expect(dirtyPosted.topRow.first?.title == "Update on AO3")
        #expect(dirtyPosted.showsUnpostedDot)
        #expect(dirtyPosted.triggerAccessibilityLabel.contains("Changes not yet on AO3"))
        #expect(
            dirtyPosted.ao3Items.map(\.title) == [
                "Compare with Posted",
                "Discard Changes",
                "Chapter Title, Summary and Notes",
                "Work Details",
                "Edit Tags"
            ]
        )
        #expect(dirtyPosted.ao3Items.first(where: { $0.id == .compareWithPosted })?.isEnabled == true)
        let discard = dirtyPosted.ao3Items.first(where: { $0.id == .discardChanges })
        #expect(discard?.isDestructive == true)
        #expect(discard?.isEnabled == true)
        #expect(dirtyPosted.documentItems.first?.subtitle == "1 saved version on this Mac")

        let cleanPosted = EditorMoreMenuModel.build(isPosted: true, hasUnpostedChanges: false)
        #expect(!cleanPosted.showsUnpostedDot)
        #expect(cleanPosted.ao3Items.first(where: { $0.id == .compareWithPosted })?.isEnabled == false)
        #expect(cleanPosted.ao3Items.first(where: { $0.id == .discardChanges })?.isEnabled == false)
    }

    @Test func editorMoreMenuDispatchesCallbacks() {
        var fired: [String] = []
        var actions = EditorMoreMenuActions()
        actions.onPostOrUpdate = { fired.append("post") }
        actions.onCompareWithPosted = { fired.append("compare") }
        actions.onDiscardChanges = { fired.append("discard") }
        actions.onExport = { format in fired.append("export:\(format.rawValue)") }
        actions.onDeleteChapter = { fired.append("delete") }

        actions.dispatch(.postOrUpdate)
        actions.dispatch(.compareWithPosted)
        actions.dispatch(.discardChanges)
        actions.dispatch(.exportFormat(.epub))
        actions.dispatch(.deleteChapter)

        #expect(fired == ["post", "compare", "discard", "export:epub", "delete"])
    }

    // MARK: - ChapterSwitcherMenu & PasteReportCard

    @Test func chapterSummaryFormatsAllFourStatusesAndUntitled() {
        let posted = EditorChapterSummary(
            id: "1", number: 1, title: "The Turning", wordCount: 2_410, status: .posted, detailText: "Oct 6"
        )
        let draft = EditorChapterSummary(
            id: "4", number: 4, title: "Slack Water", wordCount: 2_060, status: .ao3Draft
        )
        let writing = EditorChapterSummary(
            id: "5", number: 5, title: "", wordCount: 0, status: .writing
        )
        let planned = EditorChapterSummary(
            id: "6", number: 6, title: "", wordCount: 0, status: .planned, detailText: "2 scenes planned"
        )

        #expect(posted.menuTitle == "1 · The Turning")
        #expect(posted.menuSubtitle == "2,410 words · Oct 6 · Posted")
        #expect(draft.headerTitle == "Ch. 4 · Slack Water")
        #expect(draft.menuSubtitle == "2,060 words · AO3 draft")
        #expect(writing.menuTitle == "5 · Untitled")
        #expect(writing.menuSubtitle == "0 words · Writing")
        #expect(planned.menuSubtitle == "2 scenes planned · Planned")
    }

    @Test func pasteLossReportFormatsHeadlineAndSummary() {
        let report = PasteLossReport(
            wordCount: 2_140,
            sourceName: "Google Docs",
            kept: [
                PasteChangeItem(label: "italics", count: 12),
                PasteChangeItem(label: "bold", count: 3),
                PasteChangeItem(label: "centred lines", count: 2)
            ],
            removed: [
                PasteChangeItem(label: "indents", count: 3, examples: ["style=\"margin-left: 36pt\""])
            ]
        )

        #expect(report.headline == "Pasted 2,140 words from Google Docs")
        #expect(report.summaryText == "Kept italics, bold and centred lines. Removed 3 indents AO3 can’t show.")
        #expect(report.hasChangeDetails)

        let normalizedOnly = PasteLossReport(
            wordCount: 1,
            normalized: [PasteChangeItem(label: "wrapper spans", count: 2)]
        )
        #expect(normalizedOnly.headline == "Pasted 1 word")
        #expect(normalizedOnly.summaryText == "Normalized 2 markup details for AO3.")
    }

    // MARK: - WritingKeysBar actions & iOS UIInputView wrapper

    @Test func writingKeysBarOrderActionsAndUndoLongPress() {
        #expect(
            WritingKeyID.allCases == [
                .italic, .bold, .sceneBreak, .emDash, .quotationMarks,
                .cursorLeft, .cursorRight, .undo, .format
            ]
        )

        let activeState = FormatState(activeMarks: [.italic], canUndo: true, canRedo: true)
        #expect(WritingKeyID.italic.isHighlighted(in: activeState))
        #expect(!WritingKeyID.bold.isHighlighted(in: activeState))
        #expect(WritingKeyID.italic.tapAction(in: activeState) == .toggleItalic)
        #expect(WritingKeyID.bold.tapAction(in: activeState) == .toggleBold)
        #expect(WritingKeyID.sceneBreak.tapAction(in: activeState) == .insertSceneBreak)
        #expect(WritingKeyID.emDash.tapAction(in: activeState) == .insertEmDash)
        #expect(WritingKeyID.quotationMarks.tapAction(in: activeState) == .insertQuotationMarks)
        #expect(WritingKeyID.cursorLeft.tapAction(in: activeState) == .moveCursorLeft)
        #expect(WritingKeyID.cursorRight.tapAction(in: activeState) == .moveCursorRight)
        #expect(WritingKeyID.undo.tapAction(in: activeState) == .undo)
        #expect(WritingKeyID.undo.longPressAction(in: activeState) == .redo)
        #expect(WritingKeyID.format.tapAction(in: activeState) == .openFormat)
        #expect(WritingKeyID.undo.accessibilityHint(for: activeState) == "Press and hold for redo")

        // Every key carries a non-empty VoiceOver label.
        for key in WritingKeyID.allCases {
            #expect(!key.accessibilityLabel.isEmpty)
        }

        // Undo/redo gating when history is empty or one-sided.
        let emptyHistory = FormatState(canUndo: false, canRedo: false)
        #expect(!WritingKeyID.undo.isEnabled(in: emptyHistory))
        #expect(WritingKeyID.undo.tapAction(in: emptyHistory) == nil)
        #expect(WritingKeyID.undo.longPressAction(in: emptyHistory) == nil)

        let redoOnly = FormatState(canUndo: false, canRedo: true)
        #expect(WritingKeyID.undo.isEnabled(in: redoOnly))
        #expect(WritingKeyID.undo.tapAction(in: redoOnly) == nil)
        #expect(WritingKeyID.undo.longPressAction(in: redoOnly) == .redo)

        // FormatCommand bridge mapping.
        #expect(WritingKeyAction.toggleItalic.formatCommand == .toggleMark(.italic))
        #expect(WritingKeyAction.toggleBold.formatCommand == .toggleMark(.bold))
        #expect(WritingKeyAction.insertSceneBreak.formatCommand == .insertSceneBreak(.asterism))
        #expect(WritingKeyAction.undo.formatCommand == .undo)
        #expect(WritingKeyAction.redo.formatCommand == .redo)
        #expect(WritingKeyAction.insertEmDash.formatCommand == nil)
    }

    #if os(iOS)
    @Test func writingKeysInputAccessoryViewInstallsAndUpdatesState() {
        let initial = FormatState(activeMarks: [.bold], canUndo: true, canRedo: false)
        let accessory = WritingKeysInputAccessoryView(
            formatState: initial,
            themeManager: ThemeManager(),
            onAction: { _ in }
        )

        #expect(accessory.allowsSelfSizing)
        #expect(accessory.enableInputClicksWhenVisible)
        #expect(accessory.formatState == initial)

        let updated = FormatState(activeMarks: [.italic], canUndo: true, canRedo: true)
        accessory.update(formatState: updated)
        #expect(accessory.formatState == updated)

        // Confirm it can be installed directly as a UITextView's inputAccessoryView.
        let textView = UITextView()
        textView.inputAccessoryView = accessory
        #expect(textView.inputAccessoryView === accessory)
    }
    #endif
}
