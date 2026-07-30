import Foundation

/// Filesystem locations used by the app. `nonisolated` so the off-main
/// `AO3Client` actor can build download paths without crossing actors.
nonisolated enum Storage {
    static func defaultEPUBAssetIdentifier(for id: UUID) -> String {
        "\(id.uuidString).epub"
    }

    static func workAssetURL(identifier: String, fallbackID: UUID) -> URL {
        worksDirectory.appendingPathComponent(safeEPUBAssetIdentifier(identifier, fallbackID: fallbackID))
    }

    static func safeEPUBAssetIdentifier(_ identifier: String, fallbackID: UUID) -> String {
        let fallback = defaultEPUBAssetIdentifier(for: fallbackID)
        let candidate = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty,
              URL(fileURLWithPath: candidate).lastPathComponent == candidate,
              !candidate.contains("/"),
              !candidate.contains("\\"),
              URL(fileURLWithPath: candidate).pathExtension.localizedCaseInsensitiveCompare("epub")
                  == .orderedSame
        else { return fallback }
        return candidate
    }

    /// Permanent home for user-imported fonts.
    static var fontsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Fonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Permanent home for downloaded EPUBs.
    static var worksDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Works", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Permanent home for the *original* file a converted import came from.
    ///
    /// A work redistributed by the community is often the last copy in existence,
    /// and conversion to EPUB is lossy, so the bytes we were handed are kept
    /// verbatim next to the EPUB the reader actually opens. Deliberately a
    /// separate directory from `worksDirectory`: everything there is expected to
    /// be a readable `.epub` (see `safeEPUBAssetIdentifier`), and originals are
    /// not.
    static var originalsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Originals", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Where a work's preserved original lives, keyed by the work's id so it is
    /// found without a database lookup. `fileExtension` is sanitized: only
    /// alphanumerics survive, so an attacker-supplied name cannot escape the
    /// directory or add path components.
    static func originalDocumentURL(for id: UUID, fileExtension: String) -> URL {
        let cleaned = fileExtension.lowercased().filter(\.isLetter)
        let suffix = cleaned.isEmpty ? "bin" : String(cleaned.prefix(12))
        return originalsDirectory.appendingPathComponent("\(id.uuidString).\(suffix)")
    }

    /// Any preserved original for this work, whatever its extension. Used by
    /// deletion (to avoid orphans) and, later, by the provenance UI.
    static func existingOriginalDocumentURL(for id: UUID) -> URL? {
        let prefix = id.uuidString
        let contents = try? FileManager.default.contentsOfDirectory(
            at: originalsDirectory,
            includingPropertiesForKeys: nil
        )
        return contents?.first { $0.lastPathComponent.hasPrefix(prefix) }
    }

    /// Scratch space where EPUBs are unzipped for reading.
    static func readerDirectory(for id: UUID) -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Reader/\(id.uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Evictable cache for scraped AO3 metadata (e.g. the fandom catalog), so the
    /// app can show data instantly on relaunch instead of re-scraping. Under
    /// `.cachesDirectory` so the OS may purge it under disk pressure.
    static var metadataCacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Metadata", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Temporary destination for an in-flight download.
    static func tempDownloadURL(suggestedName: String) -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = suggestedName.isEmpty ? "\(UUID().uuidString).epub" : suggestedName
        return dir.appendingPathComponent(name)
    }
}
