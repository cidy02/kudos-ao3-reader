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

    /// Readium's fraction within the current resource, used by the detail
    /// Resume card. This is distinct from the work-wide `totalProgression`.
    static func chapterProgress(from locatorJSON: String) -> Double? {
        guard let data = locatorJSON.data(using: .utf8),
              let locator = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let locations = locator["locations"] as? [String: Any],
              let progression = locations["progression"] as? Double
        else { return nil }
        return min(max(progression, 0), 1)
    }

    /// The progress label a card or the Activity section prints: the
    /// publication's overall percent (`SavedWork.publicationProgress`, Readium's
    /// or the macOS reader's Readium-equivalent), or nothing. Not
    /// `SavedWork.readingProgressLabel`, whose "Ch N" is `lastSpineIndex + 1` — a
    /// spine position, off by the front matter that the legacy reader itself
    /// walks past before it names a chapter.
    static func cardProgressLabel(progress: Double?) -> String? {
        guard let progress else { return nil }
        return "\(Int((progress * 100).rounded()))%"
    }

    /// Readium 3.9's `totalProgression` for a reflowable EPUB, rebuilt without Readium:
    /// each spine item weighs max(1, ceil(entryLength / 1024)) positions
    /// (EPUBPositionsService `.recommended`); progress inside an item is linear
    /// (ViewportProgressionCalculator). `resourceLengths` = ZIP entry lengths in spine
    /// order, nil for an item outside Readium's reading order (no positions, no progress).
    static func publicationProgress(spineIndex: Int, chapterFraction: Double, resourceLengths: [Int?]) -> Double? {
        guard resourceLengths.indices.contains(spineIndex), resourceLengths[spineIndex] != nil else { return nil }
        let positions = resourceLengths.map { $0.map(Self.positions(forEntryLength:)) ?? 0 }
        let before = positions[..<spineIndex].reduce(0, +)
        let within = min(max(chapterFraction, 0), 1) * Double(positions[spineIndex])
        return (Double(before) + within) / Double(positions.reduce(0, +))
    }

    /// Readium's position weight for one ZIP entry: `max(1, ceil(bytes / 1024))`.
    /// A missing entry is not this — callers pass 0 positions for those.
    static func positions(forEntryLength bytes: Int) -> Int {
        max(1, Int((Double(max(0, bytes)) / 1024).rounded(.up)))
    }
}
