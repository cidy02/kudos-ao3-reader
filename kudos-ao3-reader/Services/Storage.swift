import CryptoKit
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

    /// SHA-256 of a file, streamed so a large book never becomes resident.
    ///
    /// The content identity a sync can compare. Equal size is not equal
    /// content — the font branch of `readChangedRemoteAssets` says exactly that
    /// and compares bytes, while the EPUB branch beside it settles for the byte
    /// count and therefore never notices a same-length correction.
    static func fileDigest(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
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
    static func originalDocumentURL(for id: UUID, fileExtension: String, in directory: URL? = nil) -> URL {
        // Alphanumerics, not letters only: stripping digits turned "azw3" into "azw"
        // and "7z" into "z", so two unrelated originals could land on one name.
        let cleaned = fileExtension.lowercased().filter { $0.isLetter || $0.isNumber }
        let suffix = cleaned.isEmpty ? "bin" : String(cleaned.prefix(12))
        return (directory ?? originalsDirectory).appendingPathComponent("\(id.uuidString).\(suffix)")
    }

    /// Any preserved original for this work, whatever its extension. Used by
    /// deletion (to avoid orphans) and, later, by the provenance UI.
    static func existingOriginalDocumentURL(for id: UUID, in directory: URL? = nil) -> URL? {
        let directory = directory ?? originalsDirectory
        let candidates = originalDocuments(for: id, in: directory)
        return preferredOriginal(candidates, for: id, in: directory)
    }

    /// An older re-import under a different extension could leave both copies.
    static func originalDocuments(for id: UUID, in directory: URL) -> [URL] {
        originalDirectoryContents(in: directory).filter { isOriginalDocument($0, for: id) }
    }

    private static func isOriginalDocument(_ url: URL, for id: UUID) -> Bool {
        // The conversion record shares the prefix. Return only the source document.
        let name = url.lastPathComponent
        return name.hasPrefix(id.uuidString) && !name.hasSuffix(conversionRecordSuffix)
    }

    /// Snapshot originals for a bulk lookup, including legacy names.
    static func existingOriginalDocumentURLs() -> [UUID: URL] {
        let directory = originalsDirectory
        var originals: [UUID: [URL]] = [:]
        for url in originalDirectoryContents(in: directory) {
            let name = url.lastPathComponent
            let prefix = String(name.prefix(36))
            guard !name.hasSuffix(conversionRecordSuffix),
                  let id = UUID(uuidString: prefix), id.uuidString == prefix
            else { continue }
            originals[id, default: []].append(url)
        }
        return Dictionary(uniqueKeysWithValues: originals.compactMap { id, candidates in
            preferredOriginal(candidates, for: id, in: directory).map { (id, $0) }
        })
    }

    private static func preferredOriginal(_ candidates: [URL], for id: UUID, in directory: URL) -> URL? {
        guard candidates.count > 1 else { return candidates.first }
        // A failed cleanup or interrupted older import may leave a sibling.
        // Prefer the file named by the committed record when it disambiguates.
        let recordURL = WorkConversionRecord.url(for: id, in: directory)
        if let data = try? Data(contentsOf: recordURL),
           let record = try? JSONDecoder().decode(WorkConversionRecord.self, from: data) {
            let expected = originalDocumentURL(for: id, fileExtension: record.originalPathExtension, in: directory)
            if let match = candidates.first(where: { $0.lastPathComponent == expected.lastPathComponent }) {
                return match
            }
        }
        return candidates.first
    }

    private static func originalDirectoryContents(in directory: URL? = nil) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory ?? originalsDirectory, includingPropertiesForKeys: nil
        )) ?? []
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

    /// Temporary destination for an in-flight download. `suggestedName` is a
    /// basename only — a hostile Content-Disposition (`../`, `/`, `\`, `.`,
    /// control characters) cannot escape `Caches/Downloads`. Unsafe names
    /// fall back to a UUID rather than being rewritten into a "safe-looking"
    /// last path component of attacker-controlled input.
    static func tempDownloadURL(suggestedName: String) -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(safeTempDownloadName(suggestedName))
    }

    /// Production sanitizer used by `tempDownloadURL`. Isolated so tests can
    /// assert the fallback without depending on a particular UUID.
    static func safeTempDownloadName(_ suggestedName: String) -> String {
        let fallback = "\(UUID().uuidString).epub"
        let candidate = suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty,
              candidate.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              URL(fileURLWithPath: candidate).lastPathComponent == candidate,
              !candidate.contains("/"),
              !candidate.contains("\\"),
              !candidate.contains(".."),
              candidate != ".",
              candidate != "..",
              candidate.count <= 255
        else { return fallback }
        return candidate
    }
}
