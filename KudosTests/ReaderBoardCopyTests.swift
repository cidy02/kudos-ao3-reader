import Foundation
import Testing
@testable import Kudos

/// Regression tests for board-matched reader copy produced by pure helpers
/// (`Reader-Menu`, `Reader-Find`, `Reader-Highlight`, `Reader-Pronunciation`,
/// `Read-Aloud-Settings`, `Reader-ChapterEnd`, `Reader-End`, `Reader-CaughtUp`).
/// Depends only on a plain test host: no network, no AO3, no WebView, no launch routes.
struct ReaderBoardCopyTests {
    // MARK: - Reader-Menu

    @Test func menuRowTitlesShowPercentAndBookmarkCountOnlyWhenPresent() {
        #expect(ReaderMenuCopy.contentsRowTitle(percent: 22) == "Contents · 22%")
        #expect(ReaderMenuCopy.contentsRowTitle(percent: 0) == "Contents · 0%")
        #expect(ReaderMenuCopy.contentsRowTitle(percent: nil) == "Contents")

        #expect(ReaderMenuCopy.bookmarksRowTitle(count: 5) == "Bookmarks & Highlights · 5")
        #expect(ReaderMenuCopy.bookmarksRowTitle(count: 1) == "Bookmarks & Highlights · 1")
        #expect(ReaderMenuCopy.bookmarksRowTitle(count: 0) == "Bookmarks & Highlights")
        #expect(ReaderMenuCopy.bookmarksRowTitle(count: -2) == "Bookmarks & Highlights")
    }

    // MARK: - Reader-Find

    @Test func findScopeAndSectionHeadersMatchReaderFindBoard() {
        #expect(ReaderSearchCopy.searchFieldAccessibilityLabel == "Find in this work")
        #expect(ReaderSearchCopy.scopeAccessibilityLabel == "Scope")
        #expect(ReaderSearchCopy.moreButtonAccessibilityLabel == "More: Go, Copy, Bookmark")
        #expect(ReaderSearchCopy.emptyThisChapterTitle == "No Matches in This Chapter")
        #expect(ReaderSearchCopy.showWholeWorkActionTitle == "Show Whole Work")

        #expect(ReaderSearchCopy.scopeTitle(.thisChapter, wholeWorkCount: 9, hasMore: false) == "This Chapter")
        #expect(ReaderSearchCopy.scopeTitle(.wholeWork, wholeWorkCount: 0, hasMore: false) == "Whole Work")
        #expect(ReaderSearchCopy.scopeTitle(.wholeWork, wholeWorkCount: 9, hasMore: false) == "Whole Work · 9")
        #expect(ReaderSearchCopy.scopeTitle(.wholeWork, wholeWorkCount: 9, hasMore: true) == "Whole Work · 9+")

        #expect(
            ReaderSearchCopy.sectionHeaderTitle(baseTitle: "Chapter 1", matchCount: 3)
                == "Chapter 1 · 3"
        )
        #expect(
            ReaderSearchCopy.sectionHeaderTitle(baseTitle: "This Chapter (Ch. 7)", matchCount: 4)
                == "This Chapter (Ch. 7) · 4"
        )

        #expect(ReaderSearchCopy.emptyThisChapterMessage(wholeWorkCount: 1) == "1 match in another chapter.")
        #expect(ReaderSearchCopy.emptyThisChapterMessage(wholeWorkCount: 5) == "5 matches in other chapters.")
    }

    // MARK: - Reader-Highlight

    @Test func highlightNoteCopyAndFooterMatchReaderHighlightBoard() {
        #expect(ReaderNoteCopy.sheetTitle == "Note")
        #expect(ReaderNoteCopy.closeAccessibilityLabel == "Close")
        #expect(ReaderNoteCopy.noteFieldAccessibilityLabel == "Note text")
        #expect(ReaderNoteCopy.toolbarAccessibilityLabel == "Highlight colours")
        #expect(ReaderNoteCopy.moreColoursAccessibilityLabel == "More colours")
        #expect(ReaderNoteCopy.deleteHighlightAccessibilityLabel == "Delete highlight")

        #expect(
            ReaderNoteCopy.footerText(isBookmark: false, chapterTitle: "Chapter 8")
                == "Highlighted · Chapter 8 · saved on this device"
        )
        #expect(
            ReaderNoteCopy.footerText(isBookmark: false, chapterTitle: "   ")
                == "Highlighted · saved on this device"
        )
        #expect(
            ReaderNoteCopy.footerText(isBookmark: true, chapterTitle: "Chapter 3")
                == "Bookmarked · Chapter 3 · saved on this device"
        )
        #expect(
            ReaderNoteCopy.footerText(isBookmark: true, chapterTitle: "")
                == "Bookmarked · saved on this device"
        )
    }

    // MARK: - Reader-Pronunciation

    @Test func pronunciationCopyAndWorkBannerMatchReaderPronunciationBoard() {
        #expect(ReaderPronunciationCopy.allWorksSectionTitle == "All works")
        #expect(ReaderPronunciationCopy.guessedWordsSectionTitle == "Words it guessed at")
        #expect(ReaderPronunciationCopy.addButtonTitle == "Add a Pronunciation…")
        #expect(ReaderPronunciationCopy.emptyTitle == "No Corrections Yet")
        #expect(ReaderPronunciationCopy.saidAsSubtitle(for: "WENT-wurth") == "Said as “WENT-wurth”")
        #expect(
            ReaderPronunciationCopy.rowAccessibilityLabel(word: "Wentworth", ipa: "WENT-wurth")
                == "Wentworth, Said as WENT-wurth"
        )

        let formattedWords = NumberFormatter.localizedString(from: NSNumber(value: 21_880), number: .decimal)
        let context = ReaderPronunciationCopy.WorkContext(
            title: "Letters Never Sent",
            author: "marginalia",
            primaryFandom: "Persuasion",
            wordCount: 21_880,
            tintHue: 0.9
        )
        #expect(context.kicker == "Read Aloud · Persuasion")
        #expect(context.meta == "marginalia · \(formattedWords) words")

        let noFandom = ReaderPronunciationCopy.WorkContext(
            title: "Untitled",
            author: "  ",
            primaryFandom: " ",
            wordCount: 0,
            tintHue: 0.1
        )
        #expect(noFandom.kicker == "Read Aloud")
        #expect(noFandom.meta.isEmpty)
    }

    // MARK: - Read-Aloud-Settings

    @Test func readAloudSettingsFormattersMatchBoard() {
        #expect(ReaderSpeechSettingsCopy.currentVoiceAccessibilityLabel == "Current voice")
        #expect(ReaderSpeechSettingsCopy.speedMinLabel == "½×")
        #expect(ReaderSpeechSettingsCopy.speedMaxLabel == "1.5×")
        #expect(ReaderSpeechSettingsCopy.pitchMinLabel == "Low")
        #expect(ReaderSpeechSettingsCopy.pitchMaxLabel == "High")
        #expect(ReaderSpeechSettingsCopy.correctionsRowTitle == "Corrections")
        #expect(ReaderSpeechSettingsCopy.guessedWordsRowTitle == "Words it guessed at")
        #expect(ReaderSpeechSettingsCopy.scanChapterRowTitle == "Scan this chapter")
        #expect(ReaderSpeechSettingsCopy.downloadProgressAccessibilityLabel == "Voice pack download")

        #expect(ReaderSpeechSettingsCopy.speedValueLabel(rate: 1.0) == "1.0×")
        #expect(ReaderSpeechSettingsCopy.speedValueLabel(rate: 1.1) == "1.1×")
        #expect(ReaderSpeechSettingsCopy.speedValueLabel(rate: 0.5) == "0.5×")
        #expect(ReaderSpeechSettingsCopy.speedValueLabel(rate: 1.05) == "1.05×")

        #expect(ReaderSpeechSettingsCopy.pitchValueLabel(pitch: 1.0) == "Normal")
        #expect(ReaderSpeechSettingsCopy.pitchValueLabel(pitch: 0.95) == "0.95×")
        #expect(ReaderSpeechSettingsCopy.pitchValueLabel(pitch: 1.1) == "1.10×")

        #expect(ReaderSpeechSettingsCopy.voiceRowValue(activeVoiceName: "Bella", voiceID: "af_bella") == "Bella")
        #expect(ReaderSpeechSettingsCopy.voiceRowValue(activeVoiceName: "Bella", voiceID: "") == "Automatic")
        #expect(ReaderSpeechSettingsCopy.voiceRowValue(activeVoiceName: nil, voiceID: "af_bella") == "Automatic")

        #expect(ReaderSpeechSettingsCopy.countLabel(12) == "12")
        #expect(ReaderSpeechSettingsCopy.countLabel(0) == "0")
        #expect(ReaderSpeechSettingsCopy.countLabel(-3) == "0")

        #expect(ReaderSpeechSettingsCopy.downloadingStatusLabel(progress: 0.64) == "Downloading · 64%")
        #expect(ReaderSpeechSettingsCopy.downloadingStatusLabel(progress: 0) == "Downloading · 0%")
        #expect(ReaderSpeechSettingsCopy.downloadingStatusLabel(progress: 1.4) == "Downloading · 100%")
    }

    // MARK: - Reader-ChapterEnd, Reader-End, Reader-CaughtUp

    @Test func endCardCopyAndChapterEndStylesheetMatchBoards() {
        #expect(ReaderEndCopy.authorNoteHeading == "Author’s note")
        #expect(ReaderEndCopy.kudosButtonTitle(given: false) == "Give Kudos")
        #expect(ReaderEndCopy.kudosButtonTitle(given: true) == "Kudos Given")

        let css = ReaderChapterEndStylesheet.stylesheet(style: .default, noteMatch: nil)
        #expect(css.contains("padding: 0 0.875rem !important;"))
        #expect(css.contains("font-size: 0.75rem !important;"))
        #expect(css.contains("font-size: 0.8125rem !important;"))
        #expect(css.contains("font-size: 0.9375rem !important;"))
        #expect(css.contains("font-size: 1.0625rem !important;"))
        #expect(css.contains("font-size: 1rem !important;"))
        #expect(!css.contains("<"))
        #expect(!css.contains(">"))
        #expect(!css.contains("&"))
    }
}
