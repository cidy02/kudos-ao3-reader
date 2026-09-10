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

}
