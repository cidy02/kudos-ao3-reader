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

    #if DEBUG
    /// Test-only override for the user-imported-font directory.
    ///
    /// The production default remains Application Support/Fonts. The override lets
    /// restore tests exercise a mounted case-sensitive filesystem without changing
    /// any production restore path.
    ///
    /// **Compiled out of release builds on purpose.** This is a mutable global that
    /// redirects where restore writes untrusted font bytes — precisely the sink M21
    /// exists to control. It has no production setter today, but a write-redirect
    /// primitive should not exist at all in a shipping binary, so the seam is
    /// `#if DEBUG` rather than merely unused.
    static var fontsDirectoryOverride: URL?
    #endif

    /// Permanent home for user-imported fonts.
    static var fontsDirectory: URL {
        #if DEBUG
        if let fontsDirectoryOverride { return fontsDirectoryOverride }
        #endif
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
        // Alphanumerics, not letters only: stripping digits turned "azw3" into "azw"
        // and "7z" into "z", so two unrelated originals could land on one name.
        let cleaned = fileExtension.lowercased().filter { $0.isLetter || $0.isNumber }
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
        return contents?.first {
            // The conversion record sidecar shares this prefix and is *not* the
            // original; returning it would make re-conversion try to convert its own
            // bookkeeping.
            $0.lastPathComponent.hasPrefix(prefix)
                && !$0.lastPathComponent.hasSuffix(conversionRecordSuffix)
        }
    }

    /// Suffix of the per-work conversion record written next to a preserved original.
    /// Lives here so the "which file is the original?" rule above and the record's own
    /// filename can never drift apart.
    static let conversionRecordSuffix = ".conversion.json"

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
        
        let candidate = URL(fileURLWithPath: suggestedName).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: "\0", with: "")
            
        var safeName = candidate.components(separatedBy: .controlCharacters).joined()
        if safeName == "." || safeName == ".." { safeName = "" }
        if safeName.count > 255 { safeName = String(safeName.prefix(255)) }
        
        let name = safeName.isEmpty ? "\(UUID().uuidString).epub" : safeName
        return dir.appendingPathComponent(name)
    }
}
