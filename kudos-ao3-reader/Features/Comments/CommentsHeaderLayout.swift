import Foundation

/// Pure logic for formatting the Comments header:
/// the compact work row chapter subtitle, the meta line figures, and mature privacy concealment.
enum CommentsHeaderLayout {
    /// The board's chip form: "Chapter 7" -> "Ch 7". Anything that isn't
    /// "Chapter <number>…" (a title-only label) is returned unchanged.
    static func shortChapterLabel(_ label: String) -> String {
        let prefix = "Chapter "
        guard label.hasPrefix(prefix) else { return label }
        let digits = label.dropFirst(prefix.count).prefix(while: \.isNumber)
        return digits.isEmpty ? label : "Ch \(digits)"
    }

    struct MetaLineData: Equatable, Sendable {
        let commentsText: String
        let threadsText: String
        let yoursText: String?
        let isYoursHighlighted: Bool
        let latestText: String?
        let accessibilityLabel: String

        var fullFormattedLine: String {
            var parts = [commentsText, threadsText]
            if let yoursText { parts.append(yoursText) }
            if let latestText { parts.append(latestText) }
            return parts.joined(separator: " · ")
        }
    }

    /// Formats the components of the comments meta line:
    /// e.g. "286 comments · 12 threads · 1 yours · latest 20h ago"
    static func metaLineData(
        totalComments: Int,
        threads: Int,
        mine: Int,
        isLoggedIn: Bool,
        latestRelativeText: String?
    ) -> MetaLineData {
        let commentsText = totalComments == 1 ? "1 comment" : "\(totalComments.formatted()) comments"
        let threadsText = threads == 1 ? "1 thread" : "\(threads.formatted()) threads"

        let yoursText: String?
        let isYoursHighlighted: Bool
        if isLoggedIn {
            yoursText = mine == 1 ? "1 yours" : "\(mine.formatted()) yours"
            isYoursHighlighted = mine > 0
        } else {
            yoursText = nil
            isYoursHighlighted = false
        }

        let latestText: String?
        if let latestRelativeText, !latestRelativeText.isEmpty {
            latestText = "latest \(latestRelativeText)"
        } else {
            latestText = nil
        }

        var accessibilityParts = [commentsText, threadsText]
        if let yoursText {
            accessibilityParts.append(mine == 1 ? "1 of the loaded comments is yours" : "\(mine.formatted()) of the loaded comments are yours")
        }
        if let latestRelativeText, !latestRelativeText.isEmpty {
            accessibilityParts.append("latest comment \(latestRelativeText)")
        }
        let accessibilityLabel = accessibilityParts.joined(separator: ", ")

        return MetaLineData(
            commentsText: commentsText,
            threadsText: threadsText,
            yoursText: yoursText,
            isYoursHighlighted: isYoursHighlighted,
            latestText: latestText,
            accessibilityLabel: accessibilityLabel
        )
    }

    /// Formats the chapter subtitle string, e.g. "Chapter 7 of 20" or "Chapter 7".
    static func chapterSubtitle(
        scope: CommentsModel.Scope,
        selectedChapter: AO3ChapterRef?,
        totalChapters: Int?
    ) -> String? {
        guard scope == .byChapter, let selectedChapter else { return nil }
        if let totalChapters, totalChapters >= selectedChapter.position {
            return "Chapter \(selectedChapter.position) of \(totalChapters)"
        }
        return "Chapter \(selectedChapter.position)"
    }

    /// Determines total chapter count from the raw chapters string (e.g. "7/20" or "20")
    /// or falling back to the loaded chapters list when rawChapters is empty.
    static func totalChaptersCount(
        chapters: [AO3ChapterRef],
        chaptersLoaded: Bool,
        rawChapters: String
    ) -> Int? {
        let trimmed = rawChapters.trimmingCharacters(in: .whitespacesAndNewlines)
        if let slashIndex = trimmed.firstIndex(of: "/") {
            let totalPart = trimmed[trimmed.index(after: slashIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if let total = Int(totalPart) {
                return total
            }
            return nil
        } else if let total = Int(trimmed) {
            return total
        }
        if chaptersLoaded && !chapters.isEmpty {
            return chapters.count
        }
        return nil
    }

    /// Whether a mature/explicit work should be concealed under the content privacy setting.
    static func isWorkConcealed(
        rating: String,
        hideMature: Bool,
        isRevealed: Bool
    ) -> Bool {
        guard hideMature else { return false }
        let isAdult = rating == "Mature" || rating == "Explicit"
        return isAdult && !isRevealed
    }
}
