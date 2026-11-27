import Foundation

/// Pure, platform-agnostic copy and formatting helpers shared by the reader's
/// sheets and cards (T-507 detail sweep against the `.design-ref/Reader-*` and
/// `Read-Aloud-Settings` boards). Kept UIKit-free so macOS builds cleanly and
/// `ReaderBoardCopyTests` can pin every string on a plain test host.
nonisolated enum ReaderMenuCopy {
    /// "Contents · 22%" when progress is known, otherwise "Contents".
    static func contentsRowTitle(percent: Int?) -> String {
        guard let percent else { return "Contents" }
        return "Contents · \(percent)%"
    }

    /// "Bookmarks & Highlights · 5" when any mark exists, otherwise "Bookmarks & Highlights".
    static func bookmarksRowTitle(count: Int) -> String {
        count > 0 ? "Bookmarks & Highlights · \(count)" : "Bookmarks & Highlights"
    }
}

/// Copy and scope labels for Find in Work (`Reader-Find`).
nonisolated enum ReaderSearchCopy {
    enum Scope: String, CaseIterable, Identifiable, Sendable {
        case thisChapter
        case wholeWork

        var id: String { rawValue }
    }

    static let searchFieldAccessibilityLabel = "Find in this work"
    static let scopeAccessibilityLabel = "Scope"
    static let moreButtonAccessibilityLabel = "More: Go, Copy, Bookmark"
    static let emptyThisChapterTitle = "No Matches in This Chapter"
    static let showWholeWorkActionTitle = "Show Whole Work"

    /// "This Chapter" or "Whole Work · 9" (with "+" while additional pages remain).
    static func scopeTitle(_ scope: Scope, wholeWorkCount: Int, hasMore: Bool) -> String {
        switch scope {
        case .thisChapter:
            return "This Chapter"
        case .wholeWork:
            guard wholeWorkCount > 0 else { return "Whole Work" }
            let suffix = hasMore ? "+" : ""
            return "Whole Work · \(wholeWorkCount)\(suffix)"
        }
    }

    /// Appends the chapter match count to a `ReaderSearchGrouping.Group` title:
    /// "Chapter 1 · 3" / "This Chapter (Ch. 7) · 4".
    static func sectionHeaderTitle(baseTitle: String, matchCount: Int) -> String {
        "\(baseTitle) · \(matchCount)"
    }

    /// Secondary text under the empty "This Chapter" view when other chapters matched.
    static func emptyThisChapterMessage(wholeWorkCount: Int) -> String {
        if wholeWorkCount == 1 {
            return "1 match in another chapter."
        }
        return "\(wholeWorkCount) matches in other chapters."
    }
}

/// Copy for the highlight note sheet (`Reader-Highlight`).
nonisolated enum ReaderNoteCopy {
    static let sheetTitle = "Note"
    static let closeAccessibilityLabel = "Close"
    static let noteFieldAccessibilityLabel = "Note text"
    static let toolbarAccessibilityLabel = "Highlight colours"
    static let moreColoursAccessibilityLabel = "More colours"
    static let deleteHighlightAccessibilityLabel = "Delete highlight"

    /// "Highlighted · Chapter 8 · saved on this device" (omits chapter when absent).
    static func footerText(isBookmark: Bool, chapterTitle: String) -> String {
        let prefix = isBookmark ? "Bookmarked" : "Highlighted"
        let trimmed = chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "\(prefix) · saved on this device"
        }
        return "\(prefix) · \(trimmed) · saved on this device"
    }
}

/// Copy and work context banner formatting for Pronunciations (`Reader-Pronunciation`).
nonisolated enum ReaderPronunciationCopy {
    struct WorkContext: Equatable, Sendable {
        let title: String
        let author: String
        let primaryFandom: String?
        let wordCount: Int
        let tintHue: Double

        /// "Read Aloud · Persuasion", or "Read Aloud" when the work carries no fandom tag.
        var kicker: String {
            let trimmed = primaryFandom?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "Read Aloud" : "Read Aloud · \(trimmed)"
        }

        /// "marginalia · 21,880 words" — omits empty author or zero word count.
        var meta: String {
            var parts: [String] = []
            let trimmedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedAuthor.isEmpty {
                parts.append(trimmedAuthor)
            }
            if wordCount > 0 {
                let formatted = NumberFormatter.localizedString(
                    from: NSNumber(value: wordCount),
                    number: .decimal
                )
                parts.append("\(formatted) words")
            }
            return parts.joined(separator: " · ")
        }
    }

    static let allWorksSectionTitle = "All works"
    static let guessedWordsSectionTitle = "Words it guessed at"
    static let addButtonTitle = "Add a Pronunciation…"
    static let emptyTitle = "No Corrections Yet"

    /// "Said as “WENT-wurth”"
    static func saidAsSubtitle(for ipa: String) -> String {
        "Said as “\(ipa)”"
    }

    static func rowAccessibilityLabel(word: String, ipa: String) -> String {
        "\(word), Said as \(ipa)"
    }
}

/// Copy and value formatters for Read Aloud settings (`Read-Aloud-Settings`).
nonisolated enum ReaderSpeechSettingsCopy {
    static let currentVoiceAccessibilityLabel = "Current voice"
    static let speedMinLabel = "½×"
    static let speedMaxLabel = "1.5×"
    static let pitchMinLabel = "Low"
    static let pitchMaxLabel = "High"
    static let correctionsRowTitle = "Corrections"
    static let guessedWordsRowTitle = "Words it guessed at"
    static let scanChapterRowTitle = "Scan this chapter"
    static let downloadProgressAccessibilityLabel = "Voice pack download"

    /// Multiplier label with multiplication sign: "1.0×", "1.1×", "1.05×".
    static func speedValueLabel(rate: Double) -> String {
        let hundredths = Int((rate * 100).rounded())
        if hundredths.isMultiple(of: 10) {
            return String(format: "%.1f×", Double(hundredths) / 100.0)
        }
        return String(format: "%.2f×", Double(hundredths) / 100.0)
    }

    /// "Normal" at 1.0, otherwise "0.95×" / "1.10×".
    static func pitchValueLabel(pitch: Double) -> String {
        if abs(pitch - 1.0) < 0.001 {
            return "Normal"
        }
        return String(format: "%.2f×", pitch)
    }

    /// Short value for the Voice row: the chosen voice's name alone ("Bella"), or "Automatic".
    static func voiceRowValue(activeVoiceName: String?, voiceID: String) -> String {
        guard !voiceID.isEmpty, let activeVoiceName, !activeVoiceName.isEmpty else {
            return "Automatic"
        }
        return activeVoiceName
    }

    static func countLabel(_ count: Int) -> String {
        "\(max(0, count))"
    }

    static func downloadingStatusLabel(progress: Double) -> String {
        let clamped = min(1, max(0, progress))
        return "Downloading · \(Int((clamped * 100).rounded()))%"
    }
}

/// Shared copy for end-of-chapter and end-of-work cards (`Reader-ChapterEnd`,
/// `Reader-End`, `Reader-CaughtUp`).
nonisolated enum ReaderEndCopy {
    static let authorNoteHeading = "Author’s note"

    static func kudosButtonTitle(given: Bool) -> String {
        given ? "Kudos Given" : "Give Kudos"
    }
}
