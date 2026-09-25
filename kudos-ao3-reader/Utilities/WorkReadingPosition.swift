import Foundation

/// Publication labels already stored in a Readium locator, shared by resume surfaces.
enum WorkReadingPosition {
    /// Readium already persists the publication's own label in its locator.
    /// Keep front matter labels verbatim; never infer a chapter from a spine index.
    static func title(from locatorJSON: String) -> String? {
        guard let data = locatorJSON.data(using: .utf8),
              let locator = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = locator["title"] as? String
        else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The progress label a card or the Activity section prints: Readium's
    /// overall percent, or nothing. Not `SavedWork.readingProgressLabel`, whose
    /// "Ch N" is `lastSpineIndex + 1` — a spine position, off by the front matter
    /// that the legacy reader itself walks past before it names a chapter.
    static func cardProgressLabel(readiumProgress: Double?) -> String? {
        guard let readiumProgress else { return nil }
        return "\(Int((readiumProgress * 100).rounded()))%"
    }
}
