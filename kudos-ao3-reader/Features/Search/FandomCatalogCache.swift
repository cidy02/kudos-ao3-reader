import Foundation

/// Local-first, on-disk cache of each media category's full fandom list, so the
/// heavy `/media/<category>/fandoms` pages (thousands of fandoms each) aren't
/// re-scraped every time the user opens Browse. Stored as a single JSON file in the
/// evictable metadata cache directory; each entry carries its fetch date so stale
/// ones can be refreshed in the background while the cached copy shows immediately.
struct FandomCatalogCache {
    struct Entry: Codable {
        var fandoms: [AO3Fandom]
        var fetchedAt: Date
    }

    /// Fandom counts drift slowly; refresh a category at most about once a week.
    static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    private let fileURL: URL

    init(fileURL: URL = FandomCatalogCache.defaultFileURL) {
        self.fileURL = fileURL
    }

    static var defaultFileURL: URL {
        Storage.metadataCacheDirectory.appendingPathComponent("fandom-catalog.json")
    }

    /// Reads the cached entries (keyed by category id). Empty if absent/unreadable.
    /// Safe to call off the main actor — it only touches the filesystem.
    func load() -> [String: Entry] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return decoded
    }

    /// Atomically writes the entries. Best-effort: a failed write just means the
    /// next launch re-scrapes. Safe to call off the main actor.
    func save(_ entries: [String: Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Removes the cache file (the Privacy & Local Data "Clear" action). It rebuilds
    /// the next time the user opens Browse.
    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Whether a category needs (re)fetching: missing, or older than `maxAge`.
    static func isStale(_ entry: Entry?, now: Date = Date()) -> Bool {
        guard let entry else { return true }
        return now.timeIntervalSince(entry.fetchedAt) > maxAge
    }
}
