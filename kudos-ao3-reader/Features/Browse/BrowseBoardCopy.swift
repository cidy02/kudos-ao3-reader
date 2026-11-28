import Foundation

/// Wording shared by the Browse sweep's presentation-only views.
nonisolated enum BrowseBoardCopy {
    static let restrictedWorkMessage = "This work may be available only to logged-in AO3 readers."
    static let unsavedCopy = "You haven’t saved anything on this device yet"
    static let emptyCollections = "No collections yet"

    static func fandomCount(_ count: Int) -> String {
        let number = count.formatted(.number.notation(.compactName))
        return "\(number) \(count == 1 ? "fandom" : "fandoms")"
    }

    static func categoryStats(fandomCount count: Int, workCount: Int?, approximate: Bool) -> String {
        let fandoms = fandomCount(count)
        guard let workCount else { return fandoms }
        let number = workCount.formatted(.number.notation(.compactName))
        return "\(fandoms) · \(approximate ? "~" : "")\(number) \(workCount == 1 ? "work" : "works")"
    }

    static func allFandomsLabel(category: String, count: Int?) -> String {
        guard let count else { return "All fandoms in \(category)" }
        return "All \(count.formatted()) \(count == 1 ? "fandom" : "fandoms") in \(category)"
    }

    static func selectionFact(selectedCount: Int, sort: String?, filters: [String]) -> String {
        var parts = ["\(selectedCount.formatted()) selected"]
        if let sort { parts.append("sorted by \(sort)") }
        if !filters.isEmpty { parts.append("filters: " + filters.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    static func tagCoverage(tagged: Int, selected: Int) -> String {
        if tagged == 0 { return "none" }
        if tagged == selected { return "all \(selected.formatted())" }
        return "\(tagged.formatted()) of \(selected.formatted())"
    }

    static func workCount(_ count: Int) -> String {
        "\(count.formatted()) \(count == 1 ? "work" : "works")"
    }

    static func availabilityProgress(completed: Int, total: Int) -> String {
        "\(completed.formatted()) of \(total.formatted()) · stops if you leave"
    }

    static func deleteWorkTitle(_ title: String) -> String {
        "Delete “\(title)”?"
    }

    static func deletedRecovery(days: Int) -> String {
        "Works stay here for \(days) days, then they're gone for good. "
            + "Restoring brings back the EPUB, your progress and your tags."
    }

    static func irreplaceableCount(_ count: Int) -> String? {
        switch count {
        case ...0: nil
        case 1: "1 of these can't be downloaded again once it's gone."
        default: "\(count.formatted()) of these can't be downloaded again once they're gone."
        }
    }

    static func bookmarkMeta(author: String, words: Int?, chapters: String) -> String {
        var parts: [String] = []
        if !author.isEmpty { parts.append(author) }
        if let words, words > 0 { parts.append(wordCount(words)) }
        if !chapters.isEmpty { parts.append(chapters) }
        return parts.joined(separator: " · ")
    }

    private static func wordCount(_ words: Int) -> String {
        "\(words.formatted()) \(words == 1 ? "word" : "words")"
    }

    static func deletedWorkDetail(words: Int, chapters: String, readingState: String) -> String {
        var parts: [String] = []
        if words > 0 { parts.append(wordCount(words)) }
        if !chapters.isEmpty { parts.append(chapters) }
        parts.append(readingState)
        return parts.joined(separator: " · ")
    }

    static func collectionRow(workCount: Int, showsOnHome: Bool, updatedLabel: String) -> String {
        var parts = [Self.workCount(workCount)]
        if showsOnHome { parts.append("on Home") }
        parts.append(updatedLabel)
        return parts.joined(separator: " · ")
    }

    static func historyHeader(pageFacts: String) -> String {
        "On AO3 · \(pageFacts) · last visited first"
    }
}
