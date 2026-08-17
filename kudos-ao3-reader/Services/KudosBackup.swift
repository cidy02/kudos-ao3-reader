import CoreGraphics
import Foundation
import OSLog
import SwiftData
import UniformTypeIdentifiers

// Backup archive schema/restore logic is cohesive; avoid behavior refactors for lint.
// swiftlint:disable file_length

extension UTType {
    /// A single ZIP archive (with the `.kudosbackup` extension) containing a
    /// JSON manifest and assets.
    ///
    /// Resolved by the identifier the app *declares* in its Info.plist (see the
    /// `UTExportedTypeDeclarations` injection in the "Inject Info.plist keys"
    /// build phase), not derived from the extension at runtime. That matters:
    /// `UTType(filenameExtension:conformingTo:)` on an undeclared extension
    /// mints a synthetic `dyn.…` identifier encoding the conformance you asked
    /// for, while the system independently types a real file on disk from the
    /// extension alone — a *different* synthetic identifier. The two never
    /// compare or conform equal, which greyed out every backup in the import
    /// picker. A declared type gives both sides one stable identifier.
    ///
    /// The lookup is deliberately non-trapping (unlike `UTType(exportedAs:)`,
    /// which requires the declaration and aborts without it): if the injection
    /// phase is ever skipped, falling back to the extension-derived type keeps
    /// the app running with the old behaviour instead of crashing on launch.
    static let kudosBackup = UTType("com.cidy02.Kudos.backup")
        ?? UTType(filenameExtension: "kudosbackup")!
}

nonisolated struct KudosBackupContents {
    static let maxFontEntryBytes = 4 * 1024 * 1024
    static let maxTotalFontBytes = 32 * 1024 * 1024

    let manifest: KudosBackupManifest
    let epubFiles: [UUID: Data]
    let fontFiles: [String: Data]
    let zip: MiniZip?
    /// Set on the Settings directory-import path so `epubData`/`fontData`
    /// can pull one file at a time. Nil for ZIP and in-memory contents.
    let directoryURL: URL?

    /// Counts ZIP entry names this contents object has actually extracted.
    /// `manifest.json` is pulled at decode; `Works/` and `Fonts/` names appear
    /// only when the matching accessor runs. Empty for directory / in-memory.
    var extractedZipEntryNames: [String] { zipSource?.extractedNames ?? [] }

    private let zipSource: ZipSource?

    /// File identity captured at pre-confirm so execute can refuse a swap.
    ///
    /// Residual (accepted): a replacement with the same size and the same
    /// `contentModificationDate` is indistinguishable. Directory imports
    /// additionally snapshot listed asset sizes, not bytes, so an equal-size
    /// swap of one EPUB still lands. Closing that fully would mean hashing
    /// every payload at confirm time, which is the M4 bomb again.
    struct SourceIdentity: Equatable, Sendable {
        let isDirectory: Bool
        let rootFileSize: Int?
        let rootModificationDate: Date?
        let listedAssetSizes: [String: Int]
    }

    private final class ZipSource: @unchecked Sendable {
        let zip: MiniZip
        private let lock = NSLock()
        private var names: [String] = []

        init(_ zip: MiniZip) {
            self.zip = zip
        }

        var extractedNames: [String] {
            lock.lock()
            defer { lock.unlock() }
            return names
        }

        func data(named name: String) -> Data? {
            lock.lock()
            names.append(name)
            lock.unlock()
            return zip.data(named: name)
        }
    }

    nonisolated init(
        manifest: KudosBackupManifest,
        epubFiles: [UUID: Data] = [:],
        fontFiles: [String: Data] = [:],
        zip: MiniZip? = nil,
        directoryURL: URL? = nil
    ) {
        self.manifest = manifest
        self.epubFiles = epubFiles
        self.fontFiles = fontFiles
        self.zip = zip
        self.directoryURL = directoryURL
        self.zipSource = zip.map(ZipSource.init)
    }

    /// Legacy read path for the pre-archive directory-package format. Kept so
    /// old exported backups and not-yet-migrated sync folders stay readable;
    /// nothing writes this format anymore.
    nonisolated init(fileWrapper root: FileWrapper) throws {
        guard root.isDirectory, let rootFiles = root.fileWrappers,
              let manifestData = rootFiles["manifest.json"]?.regularFileContents
        else {
            throw KudosBackupError.invalidPackage
        }

        manifest = try Self.makeDecoder().decode(KudosBackupManifest.self, from: manifestData)
        guard KudosBackupManifest.supportedVersions.contains(manifest.version) else {
            throw KudosBackupError.unsupportedVersion(manifest.version)
        }

        let workWrappers = rootFiles["Works"]?.fileWrappers ?? [:]
        var epubs: [UUID: Data] = [:]
        for work in manifest.works {
            guard let data = workWrappers["\(work.id.uuidString).epub"]?.regularFileContents else {
                continue
            }
            epubs[work.id] = data
        }
        epubFiles = epubs

        let fontWrappers = rootFiles["Fonts"]?.fileWrappers ?? [:]
        var fonts: [String: Data] = [:]
        var aggregateFontBytes = 0
        for font in manifest.fonts {
            guard Self.isSafeFileName(font.fileName),
                  let data = fontWrappers[font.fileName]?.regularFileContents
            else { continue }
            guard data.count <= Self.maxFontEntryBytes,
                  aggregateFontBytes <= Self.maxTotalFontBytes - data.count
            else {
                throw KudosBackupError.invalidPackage
            }
            aggregateFontBytes += data.count
            fonts[font.fileName] = data
        }
        fontFiles = fonts
        zip = nil
        directoryURL = nil
        zipSource = nil
    }

    /// Reads a backup from either physical format: a single `.kudosbackup` ZIP
    /// archive (current) or a legacy directory package (read-only support).
    nonisolated static func read(from url: URL) throws -> Self {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if isDirectory {
            return try readLegacyDirectory(from: url)
        }
        // M17 RESIDUAL: .mappedIfSafe can cause SIGBUS if the underlying file is truncated by another process while mapped.
        return try Self(zipData: Data(contentsOf: url, options: .mappedIfSafe))
    }

    /// Reads the legacy directory package without materializing EPUBs or fonts.
    /// Font limits are checked from metadata (or a discarded bounded read when
    /// size is unavailable) so a hostile tree still fails before confirm/restore
    /// holds the bytes. `epubData`/`fontData` pull one file later.
    nonisolated static func readLegacyDirectory(from rootURL: URL) throws -> Self {
        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        let manifest = try decodeManifest(Data(contentsOf: manifestURL, options: .mappedIfSafe))

        let fontsDirectory = rootURL.appendingPathComponent("Fonts", isDirectory: true)
        var aggregateFontBytes = 0
        for font in manifest.fonts where isSafeFileName(font.fileName) {
            let url = fontsDirectory.appendingPathComponent(font.fileName)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let remainingBytes = maxTotalFontBytes - aggregateFontBytes
            guard remainingBytes > 0 else { throw KudosBackupError.invalidPackage }
            let cap = min(maxFontEntryBytes, remainingBytes)
            if let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                guard fileSize <= cap else { throw KudosBackupError.invalidPackage }
                aggregateFontBytes += fileSize
                continue
            }
            // No size metadata: bound-read and discard so the cap still holds.
            let data = try readBoundedData(from: url, maxBytes: cap)
            aggregateFontBytes += data.count
        }
        return Self(
            manifest: manifest,
            epubFiles: [:],
            fontFiles: [:],
            directoryURL: rootURL
        )
    }

    nonisolated private static func readBoundedData(from url: URL, maxBytes: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maxBytes + 1) ?? Data()
        guard data.count <= maxBytes else { throw KudosBackupError.invalidPackage }
        return data
    }

    /// Snapshot used between Settings pre-confirm and execute. Stats only —
    /// does not read EPUB or font payloads. Uses `attributesOfItem` rather
    /// than `URL.resourceValues`, which can return a cached size after the
    /// file has already been replaced.
    nonisolated static func sourceIdentity(
        of url: URL,
        manifest: KudosBackupManifest? = nil
    ) throws -> SourceIdentity {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw KudosBackupError.sourceChanged
        }
        let root = fileAttributes(at: url)
        var listed: [String: Int] = [:]
        if isDirectory.boolValue, let manifest {
            let manifestURL = url.appendingPathComponent("manifest.json")
            if let size = fileAttributes(at: manifestURL).size {
                listed["manifest.json"] = size
            }
            let worksDirectory = url.appendingPathComponent("Works", isDirectory: true)
            for work in manifest.works {
                let name = "Works/\(work.id.uuidString).epub"
                let file = worksDirectory.appendingPathComponent("\(work.id.uuidString).epub")
                if let size = fileAttributes(at: file).size {
                    listed[name] = size
                }
            }
            let fontsDirectory = url.appendingPathComponent("Fonts", isDirectory: true)
            for font in manifest.fonts where isSafeFileName(font.fileName) {
                let name = "Fonts/\(font.fileName)"
                let file = fontsDirectory.appendingPathComponent(font.fileName)
                if let size = fileAttributes(at: file).size {
                    listed[name] = size
                }
            }
        }
        return SourceIdentity(
            isDirectory: isDirectory.boolValue,
            rootFileSize: root.size,
            rootModificationDate: root.modified,
            listedAssetSizes: listed
        )
    }

    nonisolated private static func fileAttributes(
        at url: URL
    ) -> (size: Int?, modified: Date?) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.intValue
        let modified = attrs?[.modificationDate] as? Date
        return (size, modified)
    }

    nonisolated static func assertSourceUnchanged(
        _ url: URL,
        since expected: SourceIdentity,
        manifest: KudosBackupManifest? = nil
    ) throws {
        let current = try sourceIdentity(of: url, manifest: manifest)
        guard current == expected else { throw KudosBackupError.sourceChanged }
    }

    /// Settings execute path: refuse a swapped file, then read lazily.
    nonisolated static func readForConfirmedImport(
        from url: URL,
        expectedIdentity: SourceIdentity,
        manifest: KudosBackupManifest? = nil
    ) throws -> Self {
        try assertSourceUnchanged(url, since: expectedIdentity, manifest: manifest)
        return try read(from: url)
    }

    /// Reads just the manifest for the pre-confirmation UI without materializing
    /// EPUBs or fonts into memory.
    nonisolated static func preConfirmManifest(from url: URL) throws -> KudosBackupManifest {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if isDirectory {
            // M4: Defer reading EPUBs into memory. We only read manifest.json.
            let manifestURL = url.appendingPathComponent("manifest.json")
            // M17 RESIDUAL: .mappedIfSafe can cause SIGBUS if the underlying file is truncated by another process while mapped.
            let manifestData = try Data(contentsOf: manifestURL, options: .mappedIfSafe)
            return try decodeManifest(manifestData)
        } else {
            // M17 RESIDUAL: .mappedIfSafe can cause SIGBUS if the underlying file is truncated by another process while mapped.
            let zipData = try Data(contentsOf: url, options: .mappedIfSafe)
            let zip = try MiniZip(data: zipData, limits: .backup)
            guard let manifestData = zip.data(named: "manifest.json") else {
                throw KudosBackupError.invalidPackage
            }
            return try decodeManifest(manifestData)
        }
    }

    nonisolated init(zipData: Data) throws {
        let parsed: MiniZip
        do {
            parsed = try MiniZip(data: zipData, limits: .backup)
        } catch {
            throw KudosBackupError.invalidPackage
        }
        // Extract only through ZipSource so unread-until-access stays observable.
        let source = ZipSource(parsed)
        guard let manifestData = source.data(named: "manifest.json") else {
            throw KudosBackupError.invalidPackage
        }

        manifest = try Self.makeDecoder().decode(KudosBackupManifest.self, from: manifestData)
        guard KudosBackupManifest.supportedVersions.contains(manifest.version) else {
            throw KudosBackupError.unsupportedVersion(manifest.version)
        }

        // M4: Defer EPUBs *and* fonts. Size-check fonts from the central
        // directory so a decompression bomb still fails here, but do not
        // inflate the payloads until `fontData(for:)` / restore asks.
        epubFiles = [:]
        fontFiles = [:]
        zip = parsed
        zipSource = source
        directoryURL = nil

        var aggregateFontBytes = 0
        for font in manifest.fonts {
            guard Self.isSafeFileName(font.fileName) else { continue }
            let entryName = "Fonts/\(font.fileName)"
            guard let size = parsed.uncompressedSize(named: entryName) else { continue }
            guard size <= Self.maxFontEntryBytes,
                  aggregateFontBytes <= Self.maxTotalFontBytes - size
            else {
                throw KudosBackupError.invalidPackage
            }
            aggregateFontBytes += size
        }
    }

    nonisolated func epubData(for id: UUID) -> Data? {
        if let data = epubFiles[id] { return data }
        if let data = zipSource?.data(named: "Works/\(id.uuidString).epub") {
            return data
        }
        if let dir = directoryURL {
            let file = dir.appendingPathComponent("Works/\(id.uuidString).epub")
            return try? Data(contentsOf: file, options: .mappedIfSafe)
        }
        return nil
    }

    nonisolated func fontData(for fileName: String) -> Data? {
        guard Self.isSafeFileName(fileName) else { return nil }
        if let data = fontFiles[fileName] { return data }
        if let data = zipSource?.data(named: "Fonts/\(fileName)") {
            return data
        }
        if let dir = directoryURL {
            let file = dir.appendingPathComponent("Fonts/\(fileName)")
            return try? Self.readBoundedData(from: file, maxBytes: Self.maxFontEntryBytes)
        }
        return nil
    }

    /// Encodes just the manifest — the sync directory's `manifest.json` and
    /// the archive's first entry share the same bytes.
    nonisolated func manifestData() throws -> Data {
        try Self.makeEncoder().encode(manifest)
    }

    /// Decodes and version-checks a bare manifest (e.g. the sync directory's
    /// `manifest.json`).
    nonisolated static func decodeManifest(_ data: Data) throws -> KudosBackupManifest {
        let manifest = try makeDecoder().decode(KudosBackupManifest.self, from: data)
        guard KudosBackupManifest.supportedVersions.contains(manifest.version) else {
            throw KudosBackupError.unsupportedVersion(manifest.version)
        }
        return manifest
    }

    /// The complete backup as a single stored-entry ZIP archive — the bytes of
    /// a `.kudosbackup` file. Entry order is deterministic (manifest first,
    /// then assets sorted by name) so identical contents produce identical
    /// archives.
    nonisolated func zipData() throws -> Data {
        let encodedManifest = try manifestData()
        var entries: [(name: String, data: Data)] = [(name: "manifest.json", data: encodedManifest)]
        for (id, data) in epubFiles.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            entries.append((name: "Works/\(id.uuidString).epub", data: data))
        }
        for (fileName, data) in fontFiles.sorted(by: { $0.key < $1.key })
            where Self.isSafeFileName(fileName) {
            entries.append((name: "Fonts/\(fileName)", data: data))
        }
        return try MiniZip.archiveData(entries)
    }

    /// Plain `.iso8601` has no fractional-second support (whole-seconds only), which
    /// silently truncates every timestamp on export. Two edits from different devices
    /// landing in the same wall-clock second — a real possibility with auto-sync —
    /// would then be unorderable by every lastModifiedAt-based merge decision in this
    /// file. A custom formatter with fractional seconds fixes that; the decoder falls
    /// back to the plain formatter so older `.kudosbackup` files (encoded without
    /// fractional seconds) still decode correctly.
    /// ISO8601DateFormatter is not Sendable; formatters are configured once and
    /// only read afterwards (thread-safe for that usage). nonisolated(unsafe)
    /// keeps encode/decode helpers callable from nonisolated backup paths.
    private nonisolated(unsafe) static let fractionalSecondsISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated(unsafe) static let wholeSecondISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private nonisolated static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractionalSecondsISO8601Formatter.string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    /// How far ahead of "now" a timestamp in an untrusted archive may legitimately
    /// sit. Real backups never carry future dates; the allowance exists only for
    /// clock skew between two of the user's own devices.
    ///
    /// **This is a security boundary, not a tidiness rule.** Every merge decision in
    /// this file ranks records by `lastModifiedAt` — `SyncMerge.shouldApplyIncoming`,
    /// the annotation same-passage dedup, tombstone suppression, and the
    /// `incomingWins` flag that can lower `epubPreservationStatus`. All of those read
    /// their input from a `.kudosbackup` the user was sent, or from a `manifest.json`
    /// in the Library Sync Folder that a cloud-account adversary can write. Without a
    /// bound, a record dated year 3000 wins every comparison forever: it overwrites
    /// newer local metadata, wins the annotation dedup (which then *hard-deletes* the
    /// user's own note), and makes a forged tombstone suppress every future genuine
    /// restore. Clamping at the decode boundary fixes all of those at once, because
    /// this is the single funnel every manifest date passes through.
    nonisolated static let maxFutureTimestampSkew: TimeInterval = 24 * 60 * 60

    /// Clamps a decoded archive timestamp to at most `now + maxFutureTimestampSkew`.
    /// Pure and internal so the boundary itself is unit-testable without a manifest.
    nonisolated static func clampedArchiveDate(_ date: Date, now: Date = Date()) -> Date {
        min(date, now.addingTimeInterval(maxFutureTimestampSkew))
    }

    private nonisolated static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = fractionalSecondsISO8601Formatter.date(from: string) {
                return clampedArchiveDate(date)
            }
            if let date = wholeSecondISO8601Formatter.date(from: string) {
                return clampedArchiveDate(date)
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(string)"
            )
        }
        return decoder
    }

    /// Internal (not private): the folder-sync asset writer/reader applies the
    /// same rule when mapping font file names to sync-directory entries.
    nonisolated static func isSafeFileName(_ fileName: String) -> Bool {
        !fileName.isEmpty
            && URL(fileURLWithPath: fileName).lastPathComponent == fileName
            && !fileName.contains("/")
            && !fileName.contains("\\")
    }
}

nonisolated struct KudosBackupManifest: Codable, Equatable {
    // v7 adds permanentDeletionScheduledAt (Recently Deleted / 90-day recovery) to
    // works, collections, and reading queues, plus isDeleted/deletedAt for reading
    // queues (previously never carried in the manifest at all).
    static let currentVersion = 8
    static let supportedVersions: Set<Int> = [1, 2, 3, 4, 5, 6, 7, currentVersion]

    let version: Int
    let exportedAt: Date
    let works: [KudosBackupWork]
    let bookmarks: [KudosBackupBookmark]
    let fonts: [KudosBackupFont]
    let collections: [KudosBackupCollection]
    let readingQueues: [KudosBackupReadingQueue]
    let readingQueueMemberships: [KudosBackupReadingQueueMembership]
    /// In-book bookmarks / highlights / notes (manifest v8+). Decoded as empty
    /// for v1-v7 archives, which predate the feature.
    let annotations: [KudosBackupAnnotation]
    /// Named AO3 searches. Android has written this array for a while; iOS
    /// historically dropped it on both export and import. Additive optional —
    /// archives without the key still decode as `[]`. No version bump: Android
    /// `BackupVersion.isSupported` only accepts 1…8.
    let savedSearches: [KudosBackupSavedSearch]
    let settings: KudosBackupSettings
    /// Carrying tombstones with the backup means a fresh install/reinstall restoring
    /// this file inherits the source device's deletion history, instead of having zero
    /// tombstone knowledge and silently resurrecting anything deleted after export.
    let tombstones: [KudosBackupTombstone]

    init(
        version: Int = currentVersion,
        exportedAt: Date = Date(),
        works: [KudosBackupWork],
        bookmarks: [KudosBackupBookmark],
        fonts: [KudosBackupFont],
        collections: [KudosBackupCollection] = [],
        readingQueues: [KudosBackupReadingQueue] = [],
        readingQueueMemberships: [KudosBackupReadingQueueMembership] = [],
        annotations: [KudosBackupAnnotation] = [],
        savedSearches: [KudosBackupSavedSearch] = [],
        settings: KudosBackupSettings,
        tombstones: [KudosBackupTombstone] = []
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.works = works
        self.bookmarks = bookmarks
        self.fonts = fonts
        self.collections = collections
        self.readingQueues = readingQueues
        self.readingQueueMemberships = readingQueueMemberships
        self.annotations = annotations
        self.savedSearches = savedSearches
        self.settings = settings
        self.tombstones = tombstones
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case exportedAt
        case works
        case bookmarks
        case fonts
        case collections
        case readingQueues
        case readingQueueMemberships
        case annotations
        case savedSearches
        case settings
        case tombstones
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        works = try container.decode([KudosBackupWork].self, forKey: .works)
        bookmarks = try container.decode([KudosBackupBookmark].self, forKey: .bookmarks)
        fonts = try container.decode([KudosBackupFont].self, forKey: .fonts)
        collections = try container.decodeIfPresent(
            [KudosBackupCollection].self,
            forKey: .collections
        ) ?? []
        readingQueues = try container.decodeIfPresent(
            [KudosBackupReadingQueue].self,
            forKey: .readingQueues
        ) ?? []
        readingQueueMemberships = try container.decodeIfPresent(
            [KudosBackupReadingQueueMembership].self,
            forKey: .readingQueueMemberships
        ) ?? []
        annotations = try container.decodeIfPresent(
            [KudosBackupAnnotation].self,
            forKey: .annotations
        ) ?? []
        savedSearches = try container.decodeIfPresent(
            [KudosBackupSavedSearch].self,
            forKey: .savedSearches
        ) ?? []
        settings = try container.decode(KudosBackupSettings.self, forKey: .settings)
        tombstones = try container.decodeIfPresent(
            [KudosBackupTombstone].self,
            forKey: .tombstones
        ) ?? []
    }
}

nonisolated struct KudosBackupTombstone: Codable, Equatable {
    let id: UUID
    let recordID: UUID
    let recordTypeRaw: String
    let createdAt: Date
    let lastModifiedAt: Date
    let sourceURL: String
    let ao3WorkID: Int?
    let deletedOnDeviceID: String
    let deletionReason: String
    let signerPublicKey: String
    let signature: String

    init(tombstone: SyncTombstone) {
        id = tombstone.id
        recordID = tombstone.recordID
        recordTypeRaw = tombstone.recordTypeRaw
        createdAt = tombstone.createdAt
        lastModifiedAt = tombstone.lastModifiedAt
        sourceURL = tombstone.sourceURL
        ao3WorkID = tombstone.ao3WorkID
        deletedOnDeviceID = tombstone.deletedOnDeviceID
        deletionReason = tombstone.deletionReason
        signerPublicKey = tombstone.signerPublicKey
        signature = tombstone.signature
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case recordID
        case recordTypeRaw
        case createdAt
        case lastModifiedAt
        case sourceURL
        case ao3WorkID
        case deletedOnDeviceID
        case deletionReason
        case signerPublicKey
        case signature
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        recordID = try container.decode(UUID.self, forKey: .recordID)
        recordTypeRaw = try container.decode(String.self, forKey: .recordTypeRaw)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastModifiedAt = try container.decode(Date.self, forKey: .lastModifiedAt)
        sourceURL = try container.decode(String.self, forKey: .sourceURL)
        ao3WorkID = try container.decodeIfPresent(Int.self, forKey: .ao3WorkID)
        deletedOnDeviceID = try container.decode(String.self, forKey: .deletedOnDeviceID)
        deletionReason = try container.decode(String.self, forKey: .deletionReason)
        signerPublicKey = try container.decodeIfPresent(String.self, forKey: .signerPublicKey) ?? ""
        signature = try container.decodeIfPresent(String.self, forKey: .signature) ?? ""
    }
}

nonisolated struct KudosBackupWork: Codable, Equatable {
    let id: UUID
    let title: String
    let author: String
    let summary: String
    let sourceURL: String
    let dateAdded: Date
    let createdAt: Date?
    let lastModifiedAt: Date?
    let deletedAt: Date?
    let isDeleted: Bool?
    let permanentDeletionScheduledAt: Date?
    let assetIdentifier: String?
    let isFavorite: Bool
    let isSaved: Bool
    let isFinished: Bool
    let hasEPUB: Bool
    let isComplete: Bool
    let rating: String
    let language: String
    let wordCount: Int
    let datePublished: String?
    let dateUpdated: String?
    let chapters: String
    let kudos: Int
    let comments: Int
    let bookmarks: Int
    let hits: Int
    let workWarnings: [String]
    let workCategories: [String]
    let seriesTitle: String
    let seriesPosition: Int
    let seriesURL: String
    let ao3SeriesID: Int?
    let lastSpineIndex: Int
    let lastScrollFraction: Double
    let lastReadDate: Date?
    let progressModifiedAt: Date?
    let workTags: [String]
    let workFandoms: [String]
    let workCharacters: [String]
    let workRelationships: [String]
    let workFreeforms: [String]
    let workTagsFetched: Bool
    let ao3Unavailable: Bool
    let isQueuedForLater: Bool
    let epubPreservationStatusRaw: String
    let metadataSyncStatusRaw: String
    let preservedAt: Date?
    let lastPreservationAttemptAt: Date?
    let lastAvailabilityCheck: Date?
    let ao3WorkID: Int?
    let userTags: [String]
    let readiumLocator: String?

    @MainActor
    init(work: SavedWork) {
        id = work.id
        title = work.title
        author = work.author
        summary = work.summary
        sourceURL = work.sourceURL
        dateAdded = work.dateAdded
        createdAt = work.createdAt
        lastModifiedAt = work.lastModifiedAt
        deletedAt = work.deletedAt
        isDeleted = work.isPendingDeletion
        permanentDeletionScheduledAt = work.permanentDeletionScheduledAt
        assetIdentifier = work.effectiveAssetIdentifier
        isFavorite = work.isFavorite
        isSaved = work.isSaved
        isFinished = work.isFinished
        hasEPUB = work.hasEPUB
        isComplete = work.isComplete
        rating = work.rating
        language = work.language
        wordCount = work.wordCount
        datePublished = work.datePublished
        dateUpdated = work.dateUpdated
        chapters = work.chapters
        kudos = work.kudos
        comments = work.comments
        bookmarks = work.bookmarks
        hits = work.hits
        workWarnings = work.workWarnings
        workCategories = work.workCategories
        seriesTitle = work.seriesTitle
        seriesPosition = work.seriesPosition
        seriesURL = work.seriesURL
        ao3SeriesID = work.ao3SeriesID
        lastSpineIndex = work.lastSpineIndex
        lastScrollFraction = work.lastScrollFraction
        lastReadDate = work.lastReadDate
        progressModifiedAt = work.progressModifiedAt
        workTags = work.workTags
        workFandoms = work.workFandoms
        workCharacters = work.workCharacters
        workRelationships = work.workRelationships
        workFreeforms = work.workFreeforms
        workTagsFetched = work.workTagsFetched
        ao3Unavailable = work.ao3Unavailable
        isQueuedForLater = work.isQueuedForLater
        epubPreservationStatusRaw = work.epubPreservationStatusRaw
        metadataSyncStatusRaw = work.metadataSyncStatusRaw
        preservedAt = work.preservedAt
        lastPreservationAttemptAt = work.lastPreservationAttemptAt
        lastAvailabilityCheck = work.lastAvailabilityCheck
        ao3WorkID = work.ao3WorkID
        userTags = work.tags.map(\.name).sorted()
        #if canImport(ReadiumShared)
        readiumLocator = work.readiumLocator
        #else
        readiumLocator = nil
        #endif
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case author
        case summary
        case sourceURL
        case dateAdded
        case createdAt
        case lastModifiedAt
        case deletedAt
        case isDeleted
        case permanentDeletionScheduledAt
        case assetIdentifier
        case isFavorite
        case isSaved
        case isFinished
        case hasEPUB
        case isComplete
        case rating
        case language
        case wordCount
        case datePublished
        case dateUpdated
        case chapters
        case kudos
        case comments
        case bookmarks
        case hits
        case workWarnings
        case workCategories
        case seriesTitle
        case seriesPosition
        case seriesURL
        case ao3SeriesID
        case lastSpineIndex
        case lastScrollFraction
        case lastReadDate
        case progressModifiedAt
        case workTags
        case workFandoms
        case workCharacters
        case workRelationships
        case workFreeforms
        case workTagsFetched
        case ao3Unavailable
        case isQueuedForLater
        case epubPreservationStatusRaw
        case metadataSyncStatusRaw
        case preservedAt
        case lastPreservationAttemptAt
        case lastAvailabilityCheck
        case ao3WorkID
        case userTags
        case readiumLocator
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? ""
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL) ?? ""
        dateAdded = try container.decodeIfPresent(Date.self, forKey: .dateAdded) ?? Date()
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        lastModifiedAt = try container.decodeIfPresent(Date.self, forKey: .lastModifiedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted)
        permanentDeletionScheduledAt = try container.decodeIfPresent(
            Date.self,
            forKey: .permanentDeletionScheduledAt
        )
        assetIdentifier = try container.decodeIfPresent(String.self, forKey: .assetIdentifier)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isSaved = try container.decodeIfPresent(Bool.self, forKey: .isSaved) ?? false
        isFinished = try container.decodeIfPresent(Bool.self, forKey: .isFinished) ?? false
        hasEPUB = try container.decodeIfPresent(Bool.self, forKey: .hasEPUB) ?? false
        isComplete = try container.decodeIfPresent(Bool.self, forKey: .isComplete) ?? false
        rating = try container.decodeIfPresent(String.self, forKey: .rating) ?? ""
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? ""
        wordCount = try container.decodeIfPresent(Int.self, forKey: .wordCount) ?? 0
        datePublished = try container.decodeIfPresent(String.self, forKey: .datePublished)
        dateUpdated = try container.decodeIfPresent(String.self, forKey: .dateUpdated)
        chapters = try container.decodeIfPresent(String.self, forKey: .chapters) ?? ""
        kudos = try container.decodeIfPresent(Int.self, forKey: .kudos) ?? 0
        comments = try container.decodeIfPresent(Int.self, forKey: .comments) ?? 0
        bookmarks = try container.decodeIfPresent(Int.self, forKey: .bookmarks) ?? 0
        hits = try container.decodeIfPresent(Int.self, forKey: .hits) ?? 0
        workWarnings = try container.decodeIfPresent([String].self, forKey: .workWarnings) ?? []
        workCategories = try container.decodeIfPresent([String].self, forKey: .workCategories) ?? []
        seriesTitle = try container.decodeIfPresent(String.self, forKey: .seriesTitle) ?? ""
        seriesPosition = try container.decodeIfPresent(Int.self, forKey: .seriesPosition) ?? 0
        seriesURL = try container.decodeIfPresent(String.self, forKey: .seriesURL) ?? ""
        ao3SeriesID = try container.decodeIfPresent(Int.self, forKey: .ao3SeriesID)
        lastSpineIndex = try container.decodeIfPresent(Int.self, forKey: .lastSpineIndex) ?? 0
        lastScrollFraction = try container.decodeIfPresent(Double.self, forKey: .lastScrollFraction) ?? 0
        lastReadDate = try container.decodeIfPresent(Date.self, forKey: .lastReadDate)
        progressModifiedAt = try container.decodeIfPresent(Date.self, forKey: .progressModifiedAt)
        workTags = try container.decodeIfPresent([String].self, forKey: .workTags) ?? []
        workFandoms = try container.decodeIfPresent([String].self, forKey: .workFandoms) ?? []
        workCharacters = try container.decodeIfPresent([String].self, forKey: .workCharacters) ?? []
        workRelationships = try container.decodeIfPresent([String].self, forKey: .workRelationships) ?? []
        workFreeforms = try container.decodeIfPresent([String].self, forKey: .workFreeforms) ?? []
        workTagsFetched = try container.decodeIfPresent(Bool.self, forKey: .workTagsFetched) ?? false
        ao3Unavailable = try container.decodeIfPresent(Bool.self, forKey: .ao3Unavailable) ?? false
        isQueuedForLater = try container.decodeIfPresent(Bool.self, forKey: .isQueuedForLater) ?? false
        epubPreservationStatusRaw = try container.decodeIfPresent(
            String.self,
            forKey: .epubPreservationStatusRaw
        ) ?? EPUBPreservationStatus.notPreserved.rawValue
        metadataSyncStatusRaw = try container.decodeIfPresent(
            String.self,
            forKey: .metadataSyncStatusRaw
        ) ?? MetadataSyncStatus.unknown.rawValue
        preservedAt = try container.decodeIfPresent(Date.self, forKey: .preservedAt)
        lastPreservationAttemptAt = try container.decodeIfPresent(
            Date.self,
            forKey: .lastPreservationAttemptAt
        )
        lastAvailabilityCheck = try container.decodeIfPresent(Date.self, forKey: .lastAvailabilityCheck)
        ao3WorkID = try container.decodeIfPresent(Int.self, forKey: .ao3WorkID)
        userTags = try container.decodeIfPresent([String].self, forKey: .userTags) ?? []
        readiumLocator = try container.decodeIfPresent(String.self, forKey: .readiumLocator)
    }
}

nonisolated struct KudosBackupBookmark: Codable, Equatable {
    let id: UUID
    let title: String
    let urlString: String
    let dateAdded: Date

    private enum CodingKeys: String, CodingKey {
        case id, title, urlString, dateAdded
    }

    @MainActor
    init(bookmark: Bookmark) {
        id = bookmark.id
        title = bookmark.title
        urlString = bookmark.urlString
        dateAdded = bookmark.dateAdded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Pre-G6 archives have no bookmark id. A fresh UUID cannot match a
        // local tombstone, so those older snapshots still cannot be
        // suppressed by id — only archives written after this field exist.
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        urlString = try container.decode(String.self, forKey: .urlString)
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
    }
}

nonisolated struct KudosBackupFont: Codable, Equatable {
    let name: String
    let fileName: String
    let dateAdded: Date

    @MainActor
    init(font: CustomFont) {
        name = font.name
        fileName = font.fileName
        dateAdded = font.dateAdded
    }
}

/// Transport form of a named AO3 search. Mirrors Android's `BackupSavedSearch`
/// (`id`, `name`, `dateAdded`, `filters` as a nested JSON object).
///
/// `filters` is `AO3SearchFilters` (Codable) so it encodes as a nested object,
/// not a string — Android declares the field `JsonObject` and rejects anything
/// else. Dates ride the same fractional-seconds ISO-8601 strategy as every other
/// manifest date (`Instant.parse` / `OffsetDateTime.parse` compatible).
nonisolated struct KudosBackupSavedSearch: Codable, Equatable {
    let id: UUID
    let name: String
    let dateAdded: Date
    let filters: AO3SearchFilters

    @MainActor
    init(savedSearch: SavedSearch) {
        id = savedSearch.id
        name = savedSearch.name
        dateAdded = savedSearch.dateAdded
        filters = savedSearch.filters
    }

    init(id: UUID, name: String, dateAdded: Date, filters: AO3SearchFilters) {
        self.id = id
        self.name = name
        self.dateAdded = dateAdded
        self.filters = filters
    }
}

/// Matches Android `BackupCollection` (`backup/BackupManifest.kt`):
/// `id`, `name`, `dateAdded`, `workIDs`, optional `description`/`sortOrder`
/// (`String?` / `Int?`), plus the Apple sync tombstone fields.
///
/// `description` and `sortOrder` are passthrough for Android. iOS does not edit
/// them in UI — they exist so a restore does not destroy the other platform's
/// data. Decoded with optional synthesis (`decodeIfPresent`); nil encodes as
/// *absent* (Swift `encodeIfPresent`), matching Android `BackupJson`
/// (`explicitNulls = false`) so null stays null rather than becoming `""`.
nonisolated struct KudosBackupCollection: Codable, Equatable {
    let id: UUID
    let name: String
    let dateAdded: Date
    let createdAt: Date?
    let lastModifiedAt: Date?
    let deletedAt: Date?
    let isDeleted: Bool?
    let permanentDeletionScheduledAt: Date?
    let syncStatusRaw: String?
    let workIDs: [UUID]
    /// Android `BackupCollection.description: String?` — wire key `description`.
    let description: String?
    /// Android `BackupCollection.sortOrder: Int?` — wire key `sortOrder`.
    let sortOrder: Int?

    @MainActor
    init(collection: WorkCollection) {
        id = collection.id
        name = collection.name
        dateAdded = collection.dateAdded
        createdAt = collection.createdAt
        lastModifiedAt = collection.lastModifiedAt
        deletedAt = collection.deletedAt
        isDeleted = collection.isPendingDeletion
        permanentDeletionScheduledAt = collection.permanentDeletionScheduledAt
        syncStatusRaw = collection.syncStatusRaw
        workIDs = collection.works.map(\.id).sorted { $0.uuidString < $1.uuidString }
        description = collection.collectionDescription
        sortOrder = collection.sortOrder
    }
}

nonisolated struct KudosBackupReadingQueue: Codable, Equatable {
    let id: UUID
    let name: String
    let kindRaw: String
    let sortOrder: Int
    let dateCreated: Date
    let dateUpdated: Date
    let lastMembershipChangedAt: Date?
    let deletedAt: Date?
    let isDeleted: Bool?
    let permanentDeletionScheduledAt: Date?

    @MainActor
    init(queue: ReadingQueue) {
        id = queue.id
        name = queue.name
        kindRaw = queue.kindRaw
        sortOrder = queue.sortOrder
        dateCreated = queue.dateCreated
        dateUpdated = queue.dateUpdated
        lastMembershipChangedAt = queue.lastMembershipChangedAt
        deletedAt = queue.deletedAt
        isDeleted = queue.isPendingDeletion
        permanentDeletionScheduledAt = queue.permanentDeletionScheduledAt
    }

    func effectiveModifiedAt(memberships: [KudosBackupReadingQueueMembership]) -> Date? {
        SyncMerge.effectiveQueueModifiedAt(
            queueUpdatedAt: dateUpdated,
            lastMembershipChangedAt: lastMembershipChangedAt,
            membershipModifiedAts: memberships.map { $0.lastModifiedAt ?? $0.queuedAt }
        )
    }
}

nonisolated struct KudosBackupReadingQueueMembership: Codable, Equatable {
    let id: UUID
    let queueID: UUID
    let workID: UUID
    let queuedAt: Date
    let lastModifiedAt: Date?
    let sortOrderInQueue: Int
    let note: String

    @MainActor
    init?(membership: ReadingQueueMembership) {
        guard let queueID = membership.queue?.id,
              let workID = membership.work?.id
        else { return nil }
        id = membership.id
        self.queueID = queueID
        self.workID = workID
        queuedAt = membership.queuedAt
        lastModifiedAt = membership.lastModifiedAt
        sortOrderInQueue = membership.sortOrderInQueue
        note = membership.note
    }
}

/// One in-book bookmark / highlight / note in transport form.
///
/// The anchor is the Readium `Locator` string — the same encoding used for
/// reading progress (`SavedWork.readiumLocator`), so a restored annotation
/// resolves through exactly one locator path. `selectedText` travels with it
/// because a locator can dangle if the EPUB is re-downloaded or the author
/// edits a posted chapter; the snapshot keeps the annotation meaningful (and
/// listable) even then.
nonisolated struct KudosBackupAnnotation: Codable, Equatable {
    let id: UUID
    let workID: UUID
    let kindRaw: String
    let colorRaw: String
    let locatorString: String
    let selectedText: String
    let note: String
    let progression: Double
    let spineIndex: Int
    let chapterTitle: String
    let createdAt: Date
    let lastModifiedAt: Date?
    let deletedAt: Date?
    let isPendingDeletion: Bool

    @MainActor
    init?(annotation: ReadingAnnotation) {
        guard let workID = annotation.work?.id else { return nil }
        id = annotation.id
        self.workID = workID
        kindRaw = annotation.kindRaw
        colorRaw = annotation.colorRaw
        locatorString = annotation.locatorString
        selectedText = annotation.selectedText
        note = annotation.note
        progression = annotation.progression
        spineIndex = annotation.spineIndex
        chapterTitle = annotation.chapterTitle
        createdAt = annotation.createdAt
        lastModifiedAt = annotation.lastModifiedAt
        deletedAt = annotation.deletedAt
        isPendingDeletion = annotation.isPendingDeletion
    }
}

nonisolated struct KudosBackupSettings: Codable, Equatable {
    private static let defaultReaderFontSizePt: Double = 18
    private static let defaultReaderLineHeight: Double = 1.65
    private static let defaultReaderMargin: Double = 28
    private static let defaultAccentColorHex = "#990000"

    var readerFontID: String
    var readerMode: String
    var readerTwoPage: Bool
    var readerCustomize: Bool
    var readerBoldText: Bool
    var readerFontPt: Double
    var readerLineHeight: Double
    var readerLetterSpacing: Double
    var readerWordSpacing: Double
    var readerMargin: Double
    var readerJustify: Bool
    var confirmBeforeDelete: Bool
    var hideMatureContent: Bool
    var matureContentMode: String
    var requireBiometricToReveal: Bool
    var appTheme: String
    var readerTheme: String
    var matchAppReaderTheme: Bool
    var accentColorHex: String
    var autoPreserveSmallSeriesOnSaveForLater: Bool
    var autoPreserveSeriesWorkThreshold: Int

    init(
        readerFontID: String,
        readerMode: String,
        readerTwoPage: Bool,
        readerCustomize: Bool,
        readerBoldText: Bool,
        readerFontPt: Double,
        readerLineHeight: Double,
        readerLetterSpacing: Double,
        readerWordSpacing: Double,
        readerMargin: Double,
        readerJustify: Bool,
        confirmBeforeDelete: Bool,
        hideMatureContent: Bool,
        matureContentMode: String,
        requireBiometricToReveal: Bool,
        appTheme: String,
        readerTheme: String,
        matchAppReaderTheme: Bool,
        accentColorHex: String,
        autoPreserveSmallSeriesOnSaveForLater: Bool,
        autoPreserveSeriesWorkThreshold: Int
    ) {
        self.readerFontID = readerFontID
        self.readerMode = readerMode
        self.readerTwoPage = readerTwoPage
        self.readerCustomize = readerCustomize
        self.readerBoldText = readerBoldText
        self.readerFontPt = readerFontPt
        self.readerLineHeight = readerLineHeight
        self.readerLetterSpacing = readerLetterSpacing
        self.readerWordSpacing = readerWordSpacing
        self.readerMargin = readerMargin
        self.readerJustify = readerJustify
        self.confirmBeforeDelete = confirmBeforeDelete
        self.hideMatureContent = hideMatureContent
        self.matureContentMode = matureContentMode
        self.requireBiometricToReveal = requireBiometricToReveal
        self.appTheme = appTheme
        self.readerTheme = readerTheme
        self.matchAppReaderTheme = matchAppReaderTheme
        self.accentColorHex = accentColorHex
        self.autoPreserveSmallSeriesOnSaveForLater = autoPreserveSmallSeriesOnSaveForLater
        self.autoPreserveSeriesWorkThreshold = autoPreserveSeriesWorkThreshold
    }

    private enum CodingKeys: String, CodingKey {
        case readerFontID
        case readerMode
        case readerTwoPage
        case readerCustomize
        case readerBoldText
        case readerFontPt
        case readerLineHeight
        case readerLetterSpacing
        case readerWordSpacing
        case readerMargin
        case readerJustify
        case confirmBeforeDelete
        case hideMatureContent
        case matureContentMode
        case requireBiometricToReveal
        case appTheme
        case readerTheme
        case matchAppReaderTheme
        case accentColorHex
        case autoPreserveSmallSeriesOnSaveForLater
        case autoPreserveSeriesWorkThreshold
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            readerFontID: container.decodeIfPresent(String.self, forKey: .readerFontID) ?? "system",
            readerMode: container.decodeIfPresent(String.self, forKey: .readerMode)
                ?? ReadingMode.scroll.rawValue,
            readerTwoPage: container.decodeIfPresent(Bool.self, forKey: .readerTwoPage) ?? false,
            readerCustomize: container.decodeIfPresent(Bool.self, forKey: .readerCustomize) ?? false,
            readerBoldText: container.decodeIfPresent(Bool.self, forKey: .readerBoldText) ?? false,
            readerFontPt: container.decodeIfPresent(Double.self, forKey: .readerFontPt)
                ?? Self.defaultReaderFontSizePt,
            readerLineHeight: container.decodeIfPresent(Double.self, forKey: .readerLineHeight)
                ?? Self.defaultReaderLineHeight,
            readerLetterSpacing: container.decodeIfPresent(Double.self, forKey: .readerLetterSpacing) ?? 0,
            readerWordSpacing: container.decodeIfPresent(Double.self, forKey: .readerWordSpacing) ?? 0,
            readerMargin: container.decodeIfPresent(Double.self, forKey: .readerMargin)
                ?? Self.defaultReaderMargin,
            readerJustify: container.decodeIfPresent(Bool.self, forKey: .readerJustify) ?? false,
            confirmBeforeDelete: container.decodeIfPresent(Bool.self, forKey: .confirmBeforeDelete) ?? true,
            hideMatureContent: container.decodeIfPresent(Bool.self, forKey: .hideMatureContent) ?? true,
            matureContentMode: container.decodeIfPresent(String.self, forKey: .matureContentMode)
                ?? MaturePrivacyMode.obscure.rawValue,
            requireBiometricToReveal: container.decodeIfPresent(
                Bool.self,
                forKey: .requireBiometricToReveal
            ) ?? false,
            appTheme: container.decodeIfPresent(String.self, forKey: .appTheme)
                ?? ReaderTheme.light.rawValue,
            readerTheme: container.decodeIfPresent(String.self, forKey: .readerTheme)
                ?? ReaderTheme.light.rawValue,
            matchAppReaderTheme: container.decodeIfPresent(Bool.self, forKey: .matchAppReaderTheme) ?? true,
            accentColorHex: container.decodeIfPresent(String.self, forKey: .accentColorHex)
                ?? Self.defaultAccentColorHex,
            autoPreserveSmallSeriesOnSaveForLater: container.decodeIfPresent(
                Bool.self,
                forKey: .autoPreserveSmallSeriesOnSaveForLater
            ) ?? false,
            autoPreserveSeriesWorkThreshold: container.decodeIfPresent(
                Int.self,
                forKey: .autoPreserveSeriesWorkThreshold
            ) ?? 5
        )
    }

    static func capture(defaults: UserDefaults = .standard) -> Self {
        Self(
            readerFontID: defaults.string(forKey: "readerFontID") ?? "system",
            readerMode: defaults.string(forKey: "readerMode") ?? ReadingMode.scroll.rawValue,
            readerTwoPage: bool(defaults, "readerTwoPage", fallback: false),
            readerCustomize: bool(defaults, "readerCustomize", fallback: false),
            readerBoldText: bool(defaults, "readerBoldText", fallback: false),
            readerFontPt: number(
                defaults,
                "readerFontPt",
                fallback: defaultReaderFontSizePt
            ),
            readerLineHeight: number(
                defaults,
                "readerLineHeight",
                fallback: defaultReaderLineHeight
            ),
            readerLetterSpacing: number(defaults, "readerLetterSpacing", fallback: 0),
            readerWordSpacing: number(defaults, "readerWordSpacing", fallback: 0),
            readerMargin: number(
                defaults,
                "readerMargin",
                fallback: defaultReaderMargin
            ),
            readerJustify: bool(defaults, "readerJustify", fallback: false),
            confirmBeforeDelete: bool(defaults, "confirmBeforeDelete", fallback: true),
            hideMatureContent: bool(defaults, "hideMatureContent", fallback: true),
            matureContentMode: defaults.string(forKey: "matureContentMode")
                ?? MaturePrivacyMode.obscure.rawValue,
            requireBiometricToReveal: bool(
                defaults,
                "requireBiometricToReveal",
                fallback: false
            ),
            appTheme: defaults.string(forKey: "appTheme") ?? ReaderTheme.light.rawValue,
            readerTheme: defaults.string(forKey: "readerTheme") ?? ReaderTheme.light.rawValue,
            matchAppReaderTheme: bool(defaults, "matchAppReaderTheme", fallback: true),
            accentColorHex: defaults.string(forKey: "accentColorHex") ?? defaultAccentColorHex,
            autoPreserveSmallSeriesOnSaveForLater: bool(
                defaults,
                "autoPreserveSmallSeriesOnSaveForLater",
                fallback: false
            ),
            autoPreserveSeriesWorkThreshold: Int(number(
                defaults,
                "autoPreserveSeriesWorkThreshold",
                fallback: 5
            ))
        )
    }

    func apply(to defaults: UserDefaults = .standard) {
        // M21. Never assign the archive's readerFontID — the font selection is local-only.
        // A custom font refers to a file name that may not exist on this device (the
        // archive might carry a font the user never installed here, or folder-sync
        // might push one that hasn't been validated yet). Silently switching the reader
        // to a missing font breaks rendering until the user notices and resets it in
        // Settings. The user picks their font on each device; sync carries the *files*,
        // not the selection.
        defaults.set(readerMode, forKey: "readerMode")
        defaults.set(readerTwoPage, forKey: "readerTwoPage")
        defaults.set(readerCustomize, forKey: "readerCustomize")
        defaults.set(readerBoldText, forKey: "readerBoldText")
        defaults.set(readerFontPt, forKey: "readerFontPt")
        defaults.set(readerLineHeight, forKey: "readerLineHeight")
        defaults.set(readerLetterSpacing, forKey: "readerLetterSpacing")
        defaults.set(readerWordSpacing, forKey: "readerWordSpacing")
        defaults.set(readerMargin, forKey: "readerMargin")
        defaults.set(readerJustify, forKey: "readerJustify")
        // M3. These four are safety gates, and until the 2026-08 audit an archive could
        // *relax* every one of them by blind assignment. That is not only an import-time
        // problem: `KudosBackupService.restore` always ends here (it is the last thing it
        // does), and `FolderSyncService` calls `restore` from four separate places
        // — foldConflictContents, syncDown, the legacy package fold and foldConflictVersions
        // — none of which shows any UI. Auto Sync is on by default and syncDown runs at
        // launch and on every foreground, so a `manifest.json` in the Library Sync Folder
        // could silently turn off mature-content hiding and the biometric reveal prompt.
        //
        // A confirmation prompt on the Settings import path would have covered none of those
        // four. So the rule lives here, at the single funnel every restore passes through:
        // **a restore may tighten a privacy gate, never loosen one.** The user relaxes them
        // in Settings, on the device in their hand.
        //
        // Consequence worth knowing: a relaxation cannot propagate between the user's own
        // devices either — once a gate is on anywhere it stays on until it is turned off on
        // each device. That is the intended direction of the trade.
        defaults.set(defaults.bool(forKey: "confirmBeforeDelete") || confirmBeforeDelete, forKey: "confirmBeforeDelete")
        defaults.set(defaults.bool(forKey: "hideMatureContent") || hideMatureContent, forKey: "hideMatureContent")
        defaults.set(
            defaults.bool(forKey: "requireBiometricToReveal") || requireBiometricToReveal,
            forKey: "requireBiometricToReveal"
        )
        // `.hide` is stricter than `.obscure`. An unrecognised incoming string keeps the local
        // value rather than being coerced — the same fail-closed shape as M2's tombstone types.
        if let incomingMode = MaturePrivacyMode(rawValue: matureContentMode) {
            let localMode = MaturePrivacyMode(rawValue: defaults.string(forKey: "matureContentMode") ?? "")
            let stricter = (localMode == .hide || incomingMode == .hide) ? MaturePrivacyMode.hide : incomingMode
            defaults.set(stricter.rawValue, forKey: "matureContentMode")
        }
        defaults.set(appTheme, forKey: "appTheme")
        defaults.set(readerTheme, forKey: "readerTheme")
        defaults.set(matchAppReaderTheme, forKey: "matchAppReaderTheme")
        defaults.set(accentColorHex, forKey: "accentColorHex")
        defaults.set(autoPreserveSmallSeriesOnSaveForLater, forKey: "autoPreserveSmallSeriesOnSaveForLater")
        defaults.set(autoPreserveSeriesWorkThreshold, forKey: "autoPreserveSeriesWorkThreshold")
    }

    private static func bool(
        _ defaults: UserDefaults,
        _ key: String,
        fallback: Bool
    ) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    private static func number(
        _ defaults: UserDefaults,
        _ key: String,
        fallback: Double
    ) -> Double {
        defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
    }
}

nonisolated struct KudosBackupRestoreSummary: Equatable {
    let works: Int
    let bookmarks: Int
    let fonts: Int
    var suppressedQueues: Int = 0
    var suppressedQueueMemberships: Int = 0
    var revivedQueues: Int = 0
    var restoredRevivedQueueMemberships: Int = 0
    var ambiguousQueueConflicts: Int = 0
    var suppressedCollections: Int = 0
    var revivedCollections: Int = 0
    var ambiguousCollectionConflicts: Int = 0
    var skippedInvalidEPUBs: Int = 0
    var suppressedAnnotations: Int = 0
    var removedWorks: Int = 0
    var removedCollections: Int = 0
    var removedQueues: Int = 0

    /// Everything the merge actually changed, one item per line, for the
    /// post-import confirmation. Separate from `conflictMessage`, which reports
    /// only the caveats — this is the "what landed" half, and it deliberately
    /// lists zero counts too so the reader can tell "nothing of this kind was in
    /// the backup" apart from "this kind was skipped".
    var changeMessage: String {
        func line(_ count: Int, _ singular: String, _ plural: String) -> String {
            "• \(count) \(count == 1 ? singular : plural)"
        }
        var parts = [
            line(works, "Library record", "Library records"),
            line(bookmarks, "saved link", "saved links"),
            line(fonts, "custom font", "custom fonts")
        ]
        if revivedQueues > 0 {
            parts.append(line(revivedQueues, "restored Reading Queue", "restored Reading Queues"))
        }
        if restoredRevivedQueueMemberships > 0 {
            parts.append(
                line(restoredRevivedQueueMemberships, "queue membership", "queue memberships")
            )
        }
        if revivedCollections > 0 {
            parts.append(line(revivedCollections, "restored Collection", "restored Collections"))
        }
        if removedWorks > 0 {
            parts.append(line(removedWorks, "work removed", "works removed"))
        }
        if removedCollections > 0 {
            parts.append(line(removedCollections, "collection removed", "collections removed"))
        }
        if removedQueues > 0 {
            parts.append(line(removedQueues, "queue removed", "queues removed"))
        }
        return parts.joined(separator: "\n")
    }

    var conflictMessage: String {
        var parts: [String] = []
        if skippedInvalidEPUBs > 0 {
            parts.append("Skipped \(skippedInvalidEPUBs) invalid EPUB file"
                + "\(skippedInvalidEPUBs == 1 ? "" : "s") to protect your existing copy.")
        }
        if revivedQueues > 0 {
            parts.append("Restored \(revivedQueues) queue\(revivedQueues == 1 ? "" : "s") "
                + "with newer changes than a previous deletion.")
        }
        if suppressedQueues > 0 {
            parts.append("Skipped \(suppressedQueues) previously deleted queue"
                + "\(suppressedQueues == 1 ? "" : "s") and "
                + "\(suppressedQueueMemberships) membership"
                + "\(suppressedQueueMemberships == 1 ? "" : "s").")
        }
        if ambiguousQueueConflicts > 0 {
            parts.append("Preserved \(ambiguousQueueConflicts) queue conflict"
                + "\(ambiguousQueueConflicts == 1 ? "" : "s") because the state was ambiguous.")
        }
        if revivedCollections > 0 {
            parts.append("Restored \(revivedCollections) collection\(revivedCollections == 1 ? "" : "s") "
                + "with newer changes than a previous deletion.")
        }
        if suppressedCollections > 0 {
            parts.append("Skipped \(suppressedCollections) previously deleted collection"
                + "\(suppressedCollections == 1 ? "" : "s").")
        }
        if ambiguousCollectionConflicts > 0 {
            parts.append("Preserved \(ambiguousCollectionConflicts) collection conflict"
                + "\(ambiguousCollectionConflicts == 1 ? "" : "s") because the state was ambiguous.")
        }
        return parts.joined(separator: " ")
    }
}

nonisolated enum KudosBackupError: LocalizedError, Equatable {
    case invalidPackage
    case unsupportedVersion(Int)
    /// The file Settings confirmed is not the file it is about to restore.
    case sourceChanged

    var errorDescription: String? {
        switch self {
        case .invalidPackage:
            "This file is not a valid Kudos backup."
        case let .unsupportedVersion(version):
            "This backup uses unsupported format version \(version)."
        case .sourceChanged:
            "This backup file changed after you reviewed it. Choose the file again."
        }
    }
}

/// Controls how a backup import interacts with the existing library.
///
/// - `reconcile`: Folder-sync / default. Existing LWW `apply` on overlap.
///   Incoming tombstones are still dropped (Phase 1). This is **not**
///   Replace — it never deletes local works that the snapshot omitted.
/// - `merge`: File-import Merge. Add works not already present. Existing
///   works are left untouched. Nothing is deleted.
/// - `replaceLibrary`: This device's works, progress, collections, queues,
///   and annotations become the snapshot. Works absent from the backup are
///   soft-deleted (without creating tombstones) so a later merge can still
///   re-add them. Omitted bookmarks and saved searches are hard-deleted
///   and get an immediate-delete tombstone (annotation pattern).
nonisolated enum BackupImportMode {
    case reconcile
    case merge
    case replaceLibrary
}

// Backup restore stays intentionally linear so conflict and asset safety rules remain auditable.
@MainActor
// swiftlint:disable:next type_body_length
enum KudosBackupService {
    static func makeContents(
        works: [SavedWork],
        bookmarks: [Bookmark],
        fonts: [CustomFont],
        collections: [WorkCollection] = [],
        readingQueues: [ReadingQueue],
        annotations: [ReadingAnnotation] = [],
        savedSearches: [SavedSearch] = [],
        tombstones: [SyncTombstone] = [],
        defaults: UserDefaults = .standard
    ) throws -> KudosBackupContents {
        var epubFiles: [UUID: Data] = [:]
        for work in works where work.hasEPUB {
            // M17 RESIDUAL: .mappedIfSafe can cause SIGBUS if the underlying file is truncated by another process while mapped.
            if let data = try? Data(contentsOf: work.fileURL, options: .mappedIfSafe) {
                epubFiles[work.id] = data
            }
        }

        var fontFiles: [String: Data] = [:]
        for font in fonts {
            // M17 RESIDUAL: .mappedIfSafe can cause SIGBUS if the underlying file is truncated by another process while mapped.
            if let data = try? Data(contentsOf: font.fileURL, options: .mappedIfSafe) {
                fontFiles[font.fileName] = data
            }
        }

        let queueMemberships = readingQueues.flatMap(\.memberships)
            .compactMap(KudosBackupReadingQueueMembership.init)
        let manifest = KudosBackupManifest(
            works: works.map(KudosBackupWork.init),
            bookmarks: bookmarks.map(KudosBackupBookmark.init),
            fonts: fonts.map(KudosBackupFont.init),
            collections: collections.map(KudosBackupCollection.init),
            readingQueues: readingQueues.map(KudosBackupReadingQueue.init),
            readingQueueMemberships: queueMemberships,
            annotations: annotations.compactMap(KudosBackupAnnotation.init),
            savedSearches: savedSearches.map(KudosBackupSavedSearch.init),
            settings: .capture(defaults: defaults),
            tombstones: tombstones.map(KudosBackupTombstone.init)
        )
        return KudosBackupContents(
            manifest: manifest,
            epubFiles: epubFiles,
            fontFiles: fontFiles
        )
    }

    /// Restores with an explicit commit boundary: **nothing reaches the store unless the
    /// whole merge succeeds** (M15a/M20). A hostile archive that is rejected part-way must
    /// leave no trace, and before this the caller's `@Environment` context autosaved, so a
    /// throw left partial merge state to be committed by the next autosave tick.
    ///
    /// **Why the caller's own context and not an isolated one.** The ratified design said
    /// to run on a separate `ModelContext` over the same container. Implemented and
    /// measured, that failed twice over: intermediate `saveBestEffort` calls inside
    /// `ReadingQueueService` still committed mid-merge (now guarded at the helper), and —
    /// decisively — SwiftData exposes no parent/child contexts, so an already-live sibling
    /// context does **not** observe what the isolated one saved.
    /// `FolderSyncService.performSyncDown` reads back through the context it passed in, and
    /// `syncDownRetriesManifestReferencedEPUBOnceItAppears` went red on exactly that.
    ///
    /// So: run on the caller's context, and make `rollback()` safe rather than avoiding it.
    /// The design rejected rollback because the shared context may hold unsaved work
    /// belonging to the rest of the app — true, and answered by flushing that work first.
    /// After the pre-flush, the only uncommitted changes are restore's own, so rolling back
    /// discards exactly them and nothing else.
    static func restore(
        _ contents: KudosBackupContents,
        into context: ModelContext,
        defaults: UserDefaults = .standard,
        mode: BackupImportMode = .reconcile
    ) throws -> KudosBackupRestoreSummary {
        // Flush anything the caller had pending, so the rollback below can only ever
        // discard changes this restore made.
        if context.hasChanges {
            try context.save()
        }

        // Suppress autosave AND `saveBestEffort` (which honours this same flag) for the
        // duration, so the merge has exactly one commit point: the save on success.
        let callerAutosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = callerAutosave }

        do {
            return try restoreIsolatedContents(contents, into: context, defaults: defaults, mode: mode)
        } catch {
            context.rollback()
            throw error
        }
    }

    // Intentionally linear for data-safety review.
    //
    // RC merge (G5): WP-A's M15 split `restore` into this inner implementation
    // plus an outer wrapper that owns the isolated-context / discard-on-throw
    // contract, while the tombstone tree added `mode` to a single-function
    // `restore`. Both are required, so `mode` is threaded through to the inner
    // body that actually branches on it.
    //
    // The disable directive must stay glued to the declaration: `disable:next`
    // covers exactly one following line, so any comment inserted between the
    // two silently un-suppresses the function (and reports the directive itself
    // as superfluous).
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func restoreIsolatedContents(
        _ contents: KudosBackupContents,
        into context: ModelContext,
        defaults: UserDefaults,
        mode: BackupImportMode
    ) throws -> KudosBackupRestoreSummary {
        let existingWorks = try context.fetch(FetchDescriptor<SavedWork>())
        var workIndex = WorkRestoreIndex(existingWorks)
        var restoredWorksByArchivedID: [UUID: SavedWork] = [:]
        var skippedInvalidEPUBs = 0

        // Phase 1: unsigned incoming tombstones still drop.
        // Phase 2: adopt only if the signature verifies over the incoming
        // fields and signerPublicKey is already in the local trust store.
        // A .kudosbackup never writes the trust store.
        TombstoneSigning.resignLocalUnsignedIfNeeded(in: context, defaults: defaults)
        let localTombstones = try context.fetch(FetchDescriptor<SyncTombstone>())
        var batchTombstones = localTombstones
        var seenTombstoneKeys = Set(
            localTombstones.map { "\($0.recordTypeRaw)|\($0.recordID.uuidString.lowercased())" }
        )
        for archived in contents.manifest.tombstones {
            guard TombstoneSigning.shouldAdopt(archived, defaults: defaults) else { continue }
            let key = "\(archived.recordTypeRaw)|\(archived.recordID.uuidString.lowercased())"
            guard seenTombstoneKeys.insert(key).inserted else { continue }
            guard let adopted = makeTombstone(from: archived) else { continue }
            // RC merge (G5) + TOMB-1: `makeTombstone` pins lastModifiedAt to the
            // signed createdAt (lastModifiedAt is unsigned and is the
            // suppression key). Keep WP-A's exportedAt clamp as defence in
            // depth — a tombstone cannot legitimately be newer than the
            // snapshot that carries it.
            adopted.lastModifiedAt = min(adopted.lastModifiedAt, contents.manifest.exportedAt)
            context.insert(adopted)
            batchTombstones.append(adopted)
        }
        let tombstones = TombstoneIndex(batchTombstones)

        let existingTags = try context.fetch(FetchDescriptor<Tag>())
        var tagsByName = Dictionary(
            existingTags.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Asset writes are deliberately monotonic, not atomic with the database
        // save below. A crash can still leave the filesystem ahead of SwiftData
        // for a non-preserved work. That trade-off is intentional: re-running the
        // restore safely converges, while staging/journaling cleanup is defeated
        // by an uncatchable signal. Existing hasEPUB/.missingFile reconciliation
        // already models and repairs the opposite, database-ahead-of-disk state.
        for archived in contents.manifest.works {
            let work: SavedWork
            let isNewRecord: Bool
            if let existing = workIndex.existingWork(for: archived) {
                if mode == .merge {
                    if existing.isPendingDeletion {
                        // Not in the active library (Recently Deleted). Merge
                        // adds it back without planting a tombstone.
                        existing.isPendingDeletion = false
                        existing.deletedAt = nil
                        existing.permanentDeletionScheduledAt = nil
                        PreservedWorkService.retractTombstone(
                            recordID: existing.id,
                            type: .savedWork,
                            ao3WorkID: existing.ao3WorkID
                                ?? archived.ao3WorkID
                                ?? WorkTags.ao3WorkID(from: existing.sourceURL),
                            sourceURL: existing.sourceURL.isEmpty ? archived.sourceURL : existing.sourceURL,
                            in: context
                        )
                        work = existing
                        isNewRecord = false
                    } else {
                        // Active overlap: leave local state entirely.
                        restoredWorksByArchivedID[archived.id] = existing
                        continue
                    }
                } else {
                    work = existing
                    // Replace is a snapshot, not LWW: the file wins even when
                    // the local overlap is newer.
                    isNewRecord = mode == .replaceLibrary
                }
            } else if mode != .replaceLibrary, tombstones.suppressesResurrection(of: archived) {
                // The user explicitly deleted this work on this device and this backup
                // predates that deletion — do not resurrect it.
                continue
            } else {
                work = SavedWork(
                    id: archived.id,
                    title: archived.title,
                    author: archived.author
                )
                context.insert(work)
                isNewRecord = true
            }
            apply(archived, to: work, isNewRecord: isNewRecord)
            restoredWorksByArchivedID[archived.id] = work
            workIndex.index(work)

            // Union-only: a stale archive must never remove a tag the user added locally
            // after the snapshot was taken (A2-F1). There is no per-tag tombstone, so the
            // only safe removal policy is "never infer deletion from absence" — this only
            // ever adds a missing archived tag, matching exact `Tag.name` identity (the
            // model's `@Attribute(.unique)` constraint is case-sensitive), never drops one.
            var existingTagNames = Set(work.tags.map(\.name))
            for name in archived.userTags {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, existingTagNames.insert(trimmed).inserted else { continue }
                let tag: Tag
                if let existingTag = tagsByName[trimmed] {
                    tag = existingTag
                } else {
                    tag = Tag(name: trimmed)
                    context.insert(tag)
                    tagsByName[trimmed] = tag
                }
                work.tags.append(tag)
            }
            // Merged/created from source-of-truth archive fields — the derived search
            // text (never carried in the backup itself) is rebuilt here so restored
            // works are searchable immediately, not only after the next launch sweep.
            // Deliberately after the user-tag union above: tag names are part of the
            // index (v2), so reindexing before linking them would drop them until the
            // next unrelated reindex.
            WorkSearchIndex.reindex(work)

            // D6: gate BEFORE materialising. `epubData(for:)` inflates the entry (WP-C
            // made extraction lazy precisely so a restore holds one EPUB at a time), so
            // running the cheap preservation check first means a work we are going to
            // skip never costs an inflation at all. Order matters for M4's memory win,
            // not just for readability.
            //
            // D7: no `archivedID` parameter — a matching record id is not evidence of
            // provenance, because an A4 adversary reads record UUIDs straight out of the
            // sync folder's own manifest.
            if Self.mayReplaceEPUB(local: work, isNewRecord: isNewRecord),
               let epub = contents.epubData(for: archived.id) {
                // A5-F3: never let corrupt/untrusted bytes overwrite a valid local EPUB.
                // Stage to a scratch file and preflight through the same hardened
                // validator (`EPUBDocument.inspectPackage`, backed by the hardened
                // MiniZip) that `ReadingQueueService.replaceEPUB` already uses for
                // AO3-download/user-import replacement, then reuse that exact
                // validate-then-atomic-replace helper so backup/folder-sync restore
                // shares the one safe path. An invalid asset is skipped — recorded and
                // logged — without touching the existing file, hasEPUB, or preservation
                // state; the rest of the restore transaction still completes.
                let staged = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(UUID().uuidString).epub")
                do {
                    try epub.write(to: staged, options: .atomic)
                    try ReadingQueueService.replaceEPUB(for: work, with: staged)
                    work.hasEPUB = true
                } catch {
                    try? FileManager.default.removeItem(at: staged)
                    skippedInvalidEPUBs += 1
                    Log.library.notice(
                        "Skipped an invalid backup EPUB: \(error.localizedDescription, privacy: .public)"
                    )
                }
            } else if !FileManager.default.fileExists(atPath: work.fileURL.path) {
                work.hasEPUB = false
                if work.epubPreservationStatus == .preserved {
                    work.epubPreservationStatus = .missingFile
                }
            }
        }

        let existingCollections = try context.fetch(FetchDescriptor<WorkCollection>())
        var collectionsByID = Dictionary(
            existingCollections.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var suppressedCollections = 0
        var revivedCollections = 0
        var ambiguousCollectionConflicts = 0
        for archived in contents.manifest.collections {
            let incomingModifiedAt = archived.lastModifiedAt ?? archived.dateAdded
            let collection: WorkCollection
            let isNewCollection: Bool
            if let existing = collectionsByID[archived.id] {
                // Mirror the work path: Merge must be able to undo a prior
                // Replace that parked this collection in Recently Deleted.
                if mode == .merge, existing.isPendingDeletion {
                    existing.isPendingDeletion = false
                    existing.deletedAt = nil
                    existing.permanentDeletionScheduledAt = nil
                }
                collection = existing
                isNewCollection = false
            } else {
                switch tombstones.collectionResolution(
                    id: archived.id,
                    incomingModifiedAt: incomingModifiedAt
                ) {
                case .suppressStaleData:
                    suppressedCollections += 1
                    continue
                case .preserveAmbiguous:
                    ambiguousCollectionConflicts += 1
                    Log.library.notice(
                        "Preserving ambiguous collection \(archived.id.uuidString, privacy: .public)"
                    )
                case .reviveNewerData:
                    revivedCollections += 1
                case .noTombstone:
                    break
                }
                collection = WorkCollection(name: archived.name)
                collection.id = archived.id
                context.insert(collection)
                collectionsByID[archived.id] = collection
                isNewCollection = true
            }

            // File Merge is add-only: keep the local collection name/fields.
            let incomingWins = if mode == .merge {
                isNewCollection
            } else {
                isNewCollection || SyncMerge.shouldApplyIncoming(
                    localModifiedAt: collection.lastModifiedAt,
                    incomingModifiedAt: incomingModifiedAt
                )
            }
            if incomingWins || collection.name.isEmpty {
                collection.name = archived.name
                collection.syncStatusRaw = archived.syncStatusRaw ?? collection.syncStatusRaw
            }
            collection.dateAdded = min(collection.dateAdded, archived.dateAdded)
            if let archivedCreatedAt = archived.createdAt {
                collection.createdAt = min(collection.createdAt, archivedCreatedAt)
            }
            collection.lastModifiedAt = max(collection.lastModifiedAt, incomingModifiedAt)
            collection.deletedAt = collection.deletedAt ?? archived.deletedAt
            // Gated the same way as SavedWork's isFavorite/isSaved/isFinished/isComplete
            // fix: an unconditional merge here would let an older, non-deleted snapshot
            // permanently flip a soft-deleted collection back to not-deleted the moment
            // it syncs in, the same bug class fixed for those boolean flags.
            if incomingWins {
                let deletion = Self.archivedDeletionState(
                    incomingIsDeleted: archived.isDeleted ?? false,
                    localIsPendingDeletion: collection.isPendingDeletion,
                    localScheduledAt: collection.permanentDeletionScheduledAt
                )
                collection.isPendingDeletion = deletion.isPendingDeletion
                collection.permanentDeletionScheduledAt = deletion.scheduledAt
            }
            // Android merge: `archived.description ?: existing.description` (and the
            // same for sortOrder) — non-null archive wins; null/absent never wipes a
            // local value. On a brand-new collection the local defaults are already
            // nil, so this is a straight assign of whatever the archive carried.
            if isNewCollection || incomingWins {
                collection.collectionDescription =
                    archived.description ?? collection.collectionDescription
                collection.sortOrder = archived.sortOrder ?? collection.sortOrder
            }

            for workID in archived.workIDs {
                guard let work = restoredWorksByArchivedID[workID] else { continue }
                // A stale manifest can still list a work the user explicitly removed
                // from this collection since — don't let the union-merge below silently
                // re-add it unless the archive is demonstrably newer than that removal.
                if tombstones.suppressesCollectionMembership(
                    collectionID: collection.id,
                    workID: work.id,
                    incomingModifiedAt: incomingModifiedAt
                ) {
                    continue
                }
                if !collection.works.contains(where: { $0.id == work.id }) {
                    collection.works.append(work)
                }
                if !work.collections.contains(where: { $0.id == collection.id }) {
                    work.collections.append(collection)
                }
            }
        }

        let savedForLaterQueue = ReadingQueueService.ensureSavedForLaterQueue(in: context)
        let existingQueues = try context.fetch(FetchDescriptor<ReadingQueue>())
        var queuesByID = Dictionary(
            existingQueues.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let archivedMembershipsByQueueID = Dictionary(
            grouping: contents.manifest.readingQueueMemberships,
            by: \.queueID
        )
        var queueIDMap: [UUID: ReadingQueue] = [:]
        var suppressedQueueIDs: Set<UUID> = []
        var revivedQueueIDs: Set<UUID> = []
        var suppressedQueues = 0
        var suppressedQueueMemberships = 0
        var suppressedAnnotations = 0
        var revivedQueues = 0
        var restoredRevivedQueueMemberships = 0
        var ambiguousQueueConflicts = 0
        for archived in contents.manifest.readingQueues {
            let queue: ReadingQueue
            let kind = ReadingQueueKind(rawValue: archived.kindRaw) ?? .custom
            let archivedMemberships = archivedMembershipsByQueueID[archived.id] ?? []
            let incomingModifiedAt = archived.effectiveModifiedAt(memberships: archivedMemberships)
            let hadExistingQueue = queuesByID[archived.id] != nil
            let resolution = kind == .savedForLater ? .noTombstone : tombstones.queueResolution(
                id: archived.id,
                incomingModifiedAt: incomingModifiedAt
            )
            if kind == .savedForLater {
                queue = savedForLaterQueue
            } else if let existing = queuesByID[archived.id] {
                // Mirror the work path: Merge must be able to undo a prior
                // Replace that parked this queue in Recently Deleted.
                if mode == .merge, existing.isPendingDeletion {
                    existing.isPendingDeletion = false
                    existing.deletedAt = nil
                    existing.permanentDeletionScheduledAt = nil
                }
                queue = existing
            } else {
                let archivedQueueID = archived.id.uuidString
                switch resolution {
                case .suppressStaleData:
                    // This queue snapshot is older than a local explicit delete.
                    // Drop its memberships with it; never re-home them elsewhere.
                    suppressedQueueIDs.insert(archived.id)
                    suppressedQueues += 1
                    suppressedQueueMemberships += archivedMemberships.count
                    continue
                case .reviveNewerData:
                    revivedQueueIDs.insert(archived.id)
                    revivedQueues += 1
                    Log.library.notice(
                        "Reviving queue \(archivedQueueID, privacy: .public) because backup is newer than tombstone"
                    )
                case .preserveAmbiguous:
                    ambiguousQueueConflicts += 1
                    Log.library.notice(
                        "Preserving queue \(archivedQueueID, privacy: .public) because tombstone conflict is ambiguous"
                    )
                case .noTombstone:
                    break
                }
                queue = ReadingQueue(
                    id: archived.id,
                    name: archived.name,
                    kind: kind,
                    sortOrder: archived.sortOrder,
                    dateCreated: archived.dateCreated,
                    dateUpdated: archived.dateUpdated
                )
                context.insert(queue)
                queuesByID[archived.id] = queue
            }

            if hadExistingQueue, resolution != .noTombstone,
               !revivedQueueIDs.contains(archived.id) {
                ambiguousQueueConflicts += 1
                Log.library.notice(
                    "Preserving existing queue \(archived.id.uuidString, privacy: .public) despite tombstone conflict"
                )
            }
            let localModifiedAt = SyncMerge.effectiveQueueModifiedAt(queue)
            let incomingWins = if mode == .merge {
                false
            } else {
                SyncMerge.shouldApplyIncoming(
                    localModifiedAt: localModifiedAt,
                    incomingModifiedAt: incomingModifiedAt
                )
            }
            if kind == .savedForLater {
                queue.name = ReadingQueueService.savedForLaterName
                queue.kind = .savedForLater
            } else if incomingWins || queue.name.isEmpty {
                queue.name = archived.name
                queue.kind = kind
                queue.sortOrder = archived.sortOrder
            }
            queue.dateCreated = min(queue.dateCreated, archived.dateCreated)
            queue.dateUpdated = max(queue.dateUpdated, archived.dateUpdated)
            if let archivedChangedAt = archived.lastMembershipChangedAt {
                queue.lastMembershipChangedAt = max(queue.lastMembershipChangedAt, archivedChangedAt)
            }
            queue.deletedAt = newest(queue.deletedAt, archived.deletedAt)
            // Same incomingWins gating as SavedWork/WorkCollection's isDeleted merge —
            // a device that already restored a queue must win over a stale device that
            // hasn't synced the restore yet.
            if incomingWins {
                let deletion = Self.archivedDeletionState(
                    incomingIsDeleted: archived.isDeleted ?? false,
                    localIsPendingDeletion: queue.isPendingDeletion,
                    localScheduledAt: queue.permanentDeletionScheduledAt
                )
                queue.isPendingDeletion = deletion.isPendingDeletion
                queue.permanentDeletionScheduledAt = deletion.scheduledAt
            }
            queueIDMap[archived.id] = queue
        }

        for archived in contents.manifest.readingQueueMemberships {
            guard let work = restoredWorksByArchivedID[archived.workID] else { continue }
            switch tombstones.membershipResolution(
                id: archived.id,
                incomingModifiedAt: archived.lastModifiedAt ?? archived.queuedAt
            ) {
            case .suppressStaleData:
                // The user explicitly removed this queue membership on this device —
                // don't resurrect it from an older backup.
                suppressedQueueMemberships += 1
                continue
            case .preserveAmbiguous:
                ambiguousQueueConflicts += 1
            case .reviveNewerData, .noTombstone:
                break
            }
            if suppressedQueueIDs.contains(archived.queueID) {
                // Its whole queue was deleted here; dropping the membership with it is
                // the user's intent — never re-home it into Saved for Later.
                continue
            }
            let queue: ReadingQueue
            if let mapped = queueIDMap[archived.queueID] {
                queue = mapped
            } else {
                // A malformed/older backup can contain a membership without the queue
                // metadata. Preserve it in a clearly-restored custom queue instead of
                // silently dumping it into Saved for Later.
                let date = archived.lastModifiedAt ?? archived.queuedAt
                let restoredQueue = ReadingQueue(
                    id: archived.queueID,
                    name: "Restored Queue",
                    kind: .custom,
                    sortOrder: queuesByID.count,
                    dateCreated: archived.queuedAt,
                    dateUpdated: date
                )
                restoredQueue.lastMembershipChangedAt = date
                context.insert(restoredQueue)
                queuesByID[archived.queueID] = restoredQueue
                queueIDMap[archived.queueID] = restoredQueue
                ambiguousQueueConflicts += 1
                queue = restoredQueue
            }
            if let existing = work.queueMemberships.first(where: { $0.queue?.id == queue.id }) {
                let incomingModifiedAt = archived.lastModifiedAt ?? archived.queuedAt
                if mode != .merge, SyncMerge.shouldApplyIncoming(
                    localModifiedAt: existing.lastModifiedAt,
                    incomingModifiedAt: incomingModifiedAt
                ) {
                    existing.sortOrderInQueue = archived.sortOrderInQueue
                    existing.note = archived.note
                    existing.lastModifiedAt = incomingModifiedAt
                    queue.lastMembershipChangedAt = max(queue.lastMembershipChangedAt, incomingModifiedAt)
                }
                work.isQueuedForLater = true
                continue
            }
            let membership = ReadingQueueMembership(
                id: archived.id,
                queue: queue,
                work: work,
                queuedAt: archived.queuedAt,
                sortOrderInQueue: archived.sortOrderInQueue,
                note: archived.note
            )
            membership.lastModifiedAt = archived.lastModifiedAt ?? archived.queuedAt
            context.insert(membership)
            queue.memberships.append(membership)
            work.queueMemberships.append(membership)
            queue.lastMembershipChangedAt = max(queue.lastMembershipChangedAt, membership.lastModifiedAt)
            work.isQueuedForLater = true
            if revivedQueueIDs.contains(queue.id) {
                restoredRevivedQueueMemberships += 1
            }
        }
        ReadingQueueService.normalizeAllQueuedWorks(in: context)

        restoreAnnotations(
            contents: contents,
            context: context,
            tombstones: tombstones,
            restoredWorksByArchivedID: restoredWorksByArchivedID,
            mode: mode,
            suppressed: &suppressedAnnotations
        )

        // Saved searches: match by id, update in place if present, insert if not.
        // Name collisions keep the incoming name (no uniqueName inventing on iOS;
        // Android de-dupes names only on *insert* of a new id — we keep parity
        // with the rest of this restore function's "incoming name wins" style).
        let existingSavedSearches = try context.fetch(FetchDescriptor<SavedSearch>())
        var savedSearchesByID = Dictionary(
            existingSavedSearches.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for archived in contents.manifest.savedSearches {
            if mode != .replaceLibrary {
                switch tombstones.savedSearchResolution(
                    id: archived.id,
                    incomingModifiedAt: archived.dateAdded
                ) {
                case .suppressStaleData:
                    continue
                case .reviveNewerData, .preserveAmbiguous, .noTombstone:
                    break
                }
            }
            if let existing = savedSearchesByID[archived.id] {
                existing.name = archived.name
                existing.dateAdded = archived.dateAdded
                existing.filters = archived.filters
            } else {
                let search = SavedSearch(name: archived.name, filters: archived.filters)
                search.id = archived.id
                search.dateAdded = archived.dateAdded
                context.insert(search)
                savedSearchesByID[archived.id] = search
            }
        }
        if mode == .replaceLibrary {
            let snapshotSearchIDs = Set(contents.manifest.savedSearches.map(\.id))
            for search in existingSavedSearches where !snapshotSearchIDs.contains(search.id) {
                SyncTombstones.recordDeletion(of: search, in: context)
                context.delete(search)
            }
        }

        let existingBookmarks = try context.fetch(FetchDescriptor<Bookmark>())
        var bookmarksByURL = Dictionary(
            existingBookmarks.map { ($0.urlString, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for archived in contents.manifest.bookmarks {
            if mode != .replaceLibrary {
                switch tombstones.bookmarkResolution(
                    id: archived.id,
                    incomingModifiedAt: archived.dateAdded
                ) {
                case .suppressStaleData:
                    continue
                case .reviveNewerData, .preserveAmbiguous, .noTombstone:
                    break
                }
            }
            let bookmark: Bookmark
            if let existing = bookmarksByURL[archived.urlString] {
                bookmark = existing
            } else {
                bookmark = Bookmark(title: archived.title, urlString: archived.urlString)
                bookmark.id = archived.id
                context.insert(bookmark)
                bookmarksByURL[archived.urlString] = bookmark
            }
            bookmark.title = archived.title
            bookmark.dateAdded = archived.dateAdded
        }
        if mode == .replaceLibrary {
            // Immediate-delete class, same as ReadingAnnotation: mint a
            // signed tombstone then hard-delete. No Recently Deleted UI.
            let snapshotURLs = Set(contents.manifest.bookmarks.map(\.urlString))
            for bookmark in existingBookmarks where !snapshotURLs.contains(bookmark.urlString) {
                SyncTombstones.recordDeletion(of: bookmark, in: context)
                context.delete(bookmark)
            }
        }

        let existingFonts = try context.fetch(FetchDescriptor<CustomFont>())
        let fontsByFoldedFileName = Dictionary(
            grouping: existingFonts,
            by: { $0.fileName.lowercased() }
        )

        // M21: validate the entire applicable font set *before* writing any file.
        // One bad font rejects the whole batch — no partial font state on disk.
        let maxSingleFontBytes = KudosBackupContents.maxFontEntryBytes
        let maxAggregateFontBytes = KudosBackupContents.maxTotalFontBytes
        let allowedExtensions: Set<String> = ["ttf", "otf"]

        // Collect only fonts that have incoming bytes (the ones that would be written).
        var validatedFonts: [(archived: KudosBackupFont, data: Data)] = []
        var validatedFileNames = Set<String>()
        var aggregateBytes = 0
        for archived in contents.manifest.fonts {
            guard let data = contents.fontData(for: archived.fileName) else { continue }

            // Basename-only: no path separators, no traversal.
            let fileName = archived.fileName
            guard KudosBackupContents.isSafeFileName(fileName),
                  URL(fileURLWithPath: fileName).lastPathComponent == fileName
            else {
                throw KudosBackupError.invalidPackage
            }
            guard validatedFileNames.insert(fileName.lowercased()).inserted else {
                throw KudosBackupError.invalidPackage
            }

            // Extension must be .ttf or .otf (case-insensitive).
            let ext = (fileName as NSString).pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else {
                throw KudosBackupError.invalidPackage
            }

            // Per-font size limit.
            guard data.count <= maxSingleFontBytes else {
                throw KudosBackupError.invalidPackage
            }

            aggregateBytes += data.count
            guard aggregateBytes <= maxAggregateFontBytes else {
                throw KudosBackupError.invalidPackage
            }

            // Font must be loadable by the system font stack.
            guard let provider = CGDataProvider(data: data as CFData),
                  CGFont(provider) != nil
            else {
                throw KudosBackupError.invalidPackage
            }

            validatedFonts.append((archived: archived, data: data))
        }

        // All fonts validated — now write.
        let fileManager = FileManager.default
        let localFontURLs = (try? fileManager.contentsOfDirectory(
            at: Storage.fontsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ).filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true
        }) ?? []
        let localFontURLsByFoldedName = Dictionary(
            grouping: localFontURLs,
            by: { $0.lastPathComponent.lowercased() }
        )
        var takenFileNames = Set(
            (
                existingFonts.map(\.fileName) + localFontURLs.map(\.lastPathComponent) +
                    validatedFonts.map { $0.archived.fileName }
            ).map { $0.lowercased() }
        )

        func uniqueRestoredFileName(for fileName: String) -> String {
            let name = fileName as NSString
            let ext = name.pathExtension
            let base = name.deletingPathExtension
            var index = 1
            while true {
                let candidate = ext.isEmpty
                    ? "\(base)-restored-\(index)"
                    : "\(base)-restored-\(index).\(ext)"
                if !takenFileNames.contains(candidate.lowercased()) {
                    takenFileNames.insert(candidate.lowercased())
                    return candidate
                }
                index += 1
            }
        }

        var restoredFonts = 0
        for (archived, data) in validatedFonts {
            let foldedName = archived.fileName.lowercased()
            let existingMatches = fontsByFoldedFileName[foldedName] ?? []
            let localMatches = localFontURLsByFoldedName[foldedName] ?? []
            var finalFileName = archived.fileName
            var matchedFont: CustomFont?
            var shouldWrite = true

            if existingMatches.count > 1 || localMatches.count > 1 {
                finalFileName = uniqueRestoredFileName(for: archived.fileName)
            } else if let existing = existingMatches.first {
                let exactLocalURL = localMatches.first {
                    $0.lastPathComponent == existing.fileName
                }
                if let exactLocalURL,
                   let size = try? exactLocalURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   size <= maxSingleFontBytes,
                   let localData = try? Data(contentsOf: exactLocalURL, options: .mappedIfSafe),
                   localData == data {
                    finalFileName = existing.fileName
                    matchedFont = existing
                    shouldWrite = false
                } else if localMatches.isEmpty,
                          !fileManager.fileExists(atPath: existing.fileURL.path) {
                    // The row still names this exact path and no case-variant occupies it.
                    // Heal the missing bytes without ever repointing the row.
                    finalFileName = existing.fileName
                    matchedFont = existing
                } else {
                    finalFileName = uniqueRestoredFileName(for: archived.fileName)
                }
            } else if let localURL = localMatches.first,
                      let size = try? localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      size <= maxSingleFontBytes,
                      let localData = try? Data(contentsOf: localURL, options: .mappedIfSafe),
                      localData == data {
                // A sole byte-identical folded match is an orphan worth adopting.
                finalFileName = localURL.lastPathComponent
                shouldWrite = false
            } else if !localMatches.isEmpty
                        || fileManager.fileExists(
                            atPath: Storage.fontsDirectory
                                .appendingPathComponent(archived.fileName).path
                        ) {
                finalFileName = uniqueRestoredFileName(for: archived.fileName)
            }

            let resolvedFont: CustomFont
            if let matchedFont {
                resolvedFont = matchedFont
            } else {
                resolvedFont = CustomFont(name: archived.name, fileName: finalFileName)
                context.insert(resolvedFont)
            }
            let font = resolvedFont
            font.name = archived.name
            font.dateAdded = archived.dateAdded
            if shouldWrite {
                try data.write(to: font.fileURL, options: .atomic)
            }
            restoredFonts += 1
        }

        var removedWorks = 0
        var removedCollections = 0
        var removedQueues = 0
        if mode == .replaceLibrary {
            // Soft-delete works not present in the snapshot, without minting
            // tombstones — absence in the snapshot is sufficient for this load,
            // and standing unsigned tombstones would block a later merge of the
            // user's real backup. Works land in Recently Deleted (90-day
            // recovery) the same way user-initiated deletes do, just without
            // the SyncTombstone.
            let snapshotWorkIDs = Set(restoredWorksByArchivedID.values.map(\.id))
            let now = Date()
            let recoveryDeadline = now.addingTimeInterval(PreservedWorkService.recoveryWindow)
            for work in existingWorks where !snapshotWorkIDs.contains(work.id) {
                guard !work.isPendingDeletion else { continue }
                work.isPendingDeletion = true
                work.deletedAt = now
                work.permanentDeletionScheduledAt = recoveryDeadline
                removedWorks += 1
            }

            let snapshotCollectionIDs = Set(contents.manifest.collections.map(\.id))
            for collection in existingCollections where !snapshotCollectionIDs.contains(collection.id) {
                guard !collection.isPendingDeletion else { continue }
                collection.isPendingDeletion = true
                collection.deletedAt = now
                collection.permanentDeletionScheduledAt = recoveryDeadline
                removedCollections += 1
            }

            let snapshotQueueIDs = Set(contents.manifest.readingQueues.map(\.id))
            for queue in existingQueues {
                guard queue.kind != .savedForLater else { continue }
                guard !snapshotQueueIDs.contains(queue.id) else { continue }
                guard !queue.isPendingDeletion else { continue }
                queue.isPendingDeletion = true
                queue.deletedAt = now
                queue.permanentDeletionScheduledAt = recoveryDeadline
                removedQueues += 1
            }

            let snapshotAnnotationIDs = Set(contents.manifest.annotations.map(\.id))
            let allAnnotations = (try? context.fetch(FetchDescriptor<ReadingAnnotation>())) ?? []
            for annotation in allAnnotations where !snapshotAnnotationIDs.contains(annotation.id) {
                guard !annotation.isPendingDeletion else { continue }
                annotation.isPendingDeletion = true
                annotation.deletedAt = now
            }
        }

        try context.save()
        if mode != .replaceLibrary {
            var settings = contents.manifest.settings
            if settings.readerFontID.hasPrefix("custom:") {
                let fileName = String(settings.readerFontID.dropFirst("custom:".count))
                if !FileManager.default.fileExists(
                    atPath: Storage.fontsDirectory.appendingPathComponent(fileName).path
                ) {
                    settings.readerFontID = "system"
                }
            }
            settings.apply(to: defaults)
        }
        return KudosBackupRestoreSummary(
            // Count what was actually applied — tombstone-suppressed works are skipped
            // and must not inflate the user-facing "N works restored" confirmation.
            works: restoredWorksByArchivedID.count,
            bookmarks: contents.manifest.bookmarks.count,
            fonts: restoredFonts,
            suppressedQueues: suppressedQueues,
            suppressedQueueMemberships: suppressedQueueMemberships,
            revivedQueues: revivedQueues,
            restoredRevivedQueueMemberships: restoredRevivedQueueMemberships,
            ambiguousQueueConflicts: ambiguousQueueConflicts,
            suppressedCollections: suppressedCollections,
            revivedCollections: revivedCollections,
            ambiguousCollectionConflicts: ambiguousCollectionConflicts,
            skippedInvalidEPUBs: skippedInvalidEPUBs,
            suppressedAnnotations: suppressedAnnotations,
            removedWorks: removedWorks,
            removedCollections: removedCollections,
            removedQueues: removedQueues
        )
    }

    /// Prevents backup import from resurrecting a record the user explicitly deleted on
    /// this device. A work tombstone only suppresses recreation when it is at least as
    /// new as the archived snapshot — an archived work with a strictly newer modification
    /// time (the user re-saved it after deleting it, then took a fresh backup) is let
    /// through normally rather than blocked forever by a stale tombstone. Queue and
    /// membership tombstones use the same timestamp-aware policy: newer queue or
    /// membership activity revives older tombstones, while older stale snapshots stay
    /// suppressed.
    /// Merges archived in-book bookmarks / highlights / notes into the store.
    ///
    /// Same rules the rest of restore follows (`DATA_AND_PERSISTENCE_INVARIANTS`):
    /// an explicit local delete wins over an older archive via the annotation
    /// tombstone; an existing record only takes archive values when the archive
    /// is newer (`SyncMerge.shouldApplyIncoming`); a new record adopts them
    /// wholesale. Annotations whose work isn't in this restore are skipped
    /// rather than orphaned — the anchor is meaningless without its book.
    private static func restoreAnnotations(
        contents: KudosBackupContents,
        context: ModelContext,
        tombstones: TombstoneIndex,
        restoredWorksByArchivedID: [UUID: SavedWork],
        mode: BackupImportMode,
        suppressed: inout Int
    ) {
        guard !contents.manifest.annotations.isEmpty else { return }
        let existing = (try? context.fetch(FetchDescriptor<ReadingAnnotation>())) ?? []
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Everything that already belonged to this device before the archive was
        // applied. `dedupeSamePassageAnnotations` must never hard-delete one of these
        // (see its doc comment); it needs the set to tell them from records this
        // restore has just inserted.
        let preexistingIDs = Set(existing.map(\.id))

        for archived in contents.manifest.annotations {
            guard let work = restoredWorksByArchivedID[archived.workID] else { continue }
            let incomingModifiedAt = archived.lastModifiedAt ?? archived.createdAt

            switch tombstones.annotationResolution(id: archived.id, incomingModifiedAt: incomingModifiedAt) {
            case .suppressStaleData:
                // Deleted here on purpose — an older archive must not revive it.
                suppressed += 1
                continue
            case .reviveNewerData, .preserveAmbiguous, .noTombstone:
                break
            }

            if let local = byID[archived.id] {
                // File Merge is add-only by annotation id: never overwrite a
                // highlight/note this device already has. New ids still insert.
                if mode == .merge { continue }
                guard SyncMerge.shouldApplyIncoming(
                    localModifiedAt: local.lastModifiedAt,
                    incomingModifiedAt: incomingModifiedAt
                ) else { continue }
                // M1f. This id-keyed path — not the dedup path below — is where a forged
                // annotation actually lands: an A4 adversary reads the real UUID out of the
                // sync folder's own `manifest.json`, so there is no dedup loser and the
                // pre-existing guard in `dedupeSamePassageAnnotations` never runs. Straight
                // LWW here would overwrite the user's note text in place, unrecoverably, with
                // no interaction beyond having trusted the folder.
                //
                // The live row still takes LWW (deletion flags included — annotation delete
                // between the user's own devices depends on it, because
                // `annotationResolution(.suppressStaleData)` only skips and never sets the
                // flag). Only the displaced *text* is preserved, on a hidden sibling.
                if preexistingIDs.contains(local.id), !local.note.isEmpty, archived.note != local.note {
                    parkDisplacedNote(local.note, from: local, work: work, in: context)
                }
                local.kindRaw = archived.kindRaw
                local.colorRaw = archived.colorRaw
                local.locatorString = archived.locatorString
                local.selectedText = archived.selectedText
                local.note = archived.note
                local.progression = archived.progression
                local.spineIndex = archived.spineIndex
                local.chapterTitle = archived.chapterTitle
                local.createdAt = min(local.createdAt, archived.createdAt)
                local.lastModifiedAt = incomingModifiedAt
                local.deletedAt = archived.deletedAt
                local.isPendingDeletion = archived.isPendingDeletion
                // Re-home onto the work this restore just resolved — usually a
                // no-op (stable UUIDs), but a dedup-by-canonical-URL match can
                // land archived.workID on a *different* local SavedWork record
                // than `local.work` still points to, silently orphaning the mark.
                local.work = work
                continue
            }

            let restored = ReadingAnnotation(
                id: archived.id,
                work: work,
                kind: ReadingAnnotationKind(rawValue: archived.kindRaw) ?? .bookmark,
                locatorString: archived.locatorString,
                selectedText: archived.selectedText,
                note: archived.note,
                color: ReadingAnnotationColor(rawValue: archived.colorRaw) ?? .yellow,
                progression: archived.progression,
                spineIndex: archived.spineIndex,
                chapterTitle: archived.chapterTitle,
                createdAt: archived.createdAt
            )
            restored.lastModifiedAt = incomingModifiedAt
            restored.deletedAt = archived.deletedAt
            restored.isPendingDeletion = archived.isPendingDeletion
            context.insert(restored)
            byID[archived.id] = restored
        }

        dedupeSamePassageAnnotations(context: context, preexistingIDs: preexistingIDs)
    }

    /// Parks note text that a merge is about to overwrite onto a hidden, already-soft-deleted
    /// copy of the row it came from, so the live row can take a clean last-write-wins update
    /// without the user's typing being destroyed.
    ///
    /// **Why a sibling row rather than appending onto the live note.** Appending was the first
    /// design and it fails twice. It injects the other side's text into what the user actually
    /// sees — an attacker-supplied note ends up *in* the user's note rather than merely
    /// replacing it. And because `SyncMerge.shouldApplyIncoming` is `incoming >= local`
    /// (`PersistenceSync.swift`) while modified annotations re-export on every snapshot, two of
    /// the user's own devices that legitimately disagree ping-pong the concatenation and it
    /// grows without bound on every sync cycle. Parking keeps the live row a clean LWW winner,
    /// converges, and still never loses a byte the user typed.
    ///
    /// **Honest limitation.** There is no Recently Deleted surface for annotations
    /// (`RecentlyDeletedView` lists works, collections and queues only). "Recoverable" here
    /// means the text survives in the store and round-trips through backup — *not* that the
    /// user can tap to restore it. Do not describe this as a recovery flow.
    ///
    /// **Known consequence, flagged rather than optimised away.** Restore cannot tell a forged
    /// same-id record from the user's own honest edit arriving from another device — that
    /// asymmetry is the premise of the whole rule — so a parked row is created on *every*
    /// divergent note update a device receives, not only on an attack. In effect the store
    /// keeps a version history of every note that has ever been edited on two devices, and
    /// those rows are exported in every backup. Bounding it is tempting and the obvious bounds
    /// are unsafe: keeping only the most recent parked row lets an attacker overwrite twice,
    /// the second write displacing the user's real text out of the single slot. Left unbounded
    /// deliberately; if the row count ever becomes a real problem the fix is a pruning policy
    /// with an explicit retention rule, not a smaller buffer.
    @discardableResult
    private static func parkDisplacedNote(
        _ note: String,
        from original: ReadingAnnotation,
        work: SavedWork,
        in context: ModelContext,
        now: Date = Date()
    ) -> ReadingAnnotation? {
        guard !note.isEmpty else { return nil }
        let parked = ReadingAnnotation(
            work: work,
            kind: original.kind,
            locatorString: original.locatorString,
            selectedText: original.selectedText,
            note: note,
            color: original.color,
            progression: original.progression,
            spineIndex: original.spineIndex,
            chapterTitle: original.chapterTitle,
            createdAt: original.createdAt
        )
        // Born hidden: it is a salvage record, not a second live highlight. Dedup skips
        // pending-deletion rows, so it never competes with the live one it was split from.
        parked.isPendingDeletion = true
        parked.deletedAt = now
        parked.lastModifiedAt = now
        context.insert(parked)
        return parked
    }

    /// ANN-8: two devices creating the "same" highlight/bookmark offline
    /// produce two different UUIDs, so id-keyed merging above never notices.
    /// After the restore merge, collapse any still-live annotations that
    /// share (work, kind, **exact** locator string) — same-kind only, never a
    /// fuzzy text match. The most recently modified one wins.
    ///
    /// **Security rule added after the 2026-08 audit:** a record that existed on this
    /// device *before* the archive was applied is never `context.delete`d here. The
    /// ranking key is `lastModifiedAt`, which for an incoming record comes straight
    /// from an untrusted manifest — so an attacker who knows a locator (an A4 adversary
    /// reads it out of the sync folder's own manifest) could otherwise post a colliding,
    /// newer-dated annotation and have the user's note row hard-deleted, note text and
    /// all, with no user interaction. Pre-existing losers are soft-deleted instead, so the
    /// row and its text survive; a losing note that would otherwise be dropped is filled
    /// onto an empty winner, or parked on a hidden sibling when both notes are non-empty
    /// (see `parkDisplacedNote` for why this is not a concatenation).
    private static func dedupeSamePassageAnnotations(
        context: ModelContext,
        preexistingIDs: Set<UUID>
    ) {
        let live = ((try? context.fetch(FetchDescriptor<ReadingAnnotation>())) ?? [])
            .filter { !$0.isPendingDeletion && $0.deletedAt == nil }

        var groups: [String: [ReadingAnnotation]] = [:]
        for annotation in live {
            guard let workID = annotation.work?.id else { continue }
            let key = "\(workID.uuidString)|\(annotation.kindRaw)|\(annotation.locatorString)"
            groups[key, default: []].append(annotation)
        }

        for group in groups.values where group.count > 1 {
            let ranked = group.sorted {
                if $0.lastModifiedAt != $1.lastModifiedAt { return $0.lastModifiedAt > $1.lastModifiedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            guard let winner = ranked.first else { continue }
            for loser in ranked.dropFirst() {
                if !loser.note.isEmpty, winner.note != loser.note {
                    if winner.note.isEmpty {
                        // Empty-winner fill, as before the audit: no text is in contention,
                        // so the rescued note simply becomes the winner's.
                        winner.note = loser.note
                        // Salvaging is a real content edit: without stamping it, the winner
                        // keeps its old `lastModifiedAt`, and the very next merge would see a
                        // "newer" remote copy of the winner (which still has an empty note)
                        // and overwrite the rescued note — silently undoing this salvage.
                        winner.markModified()
                    } else if let work = loser.work {
                        // Both notes are non-empty and different. Concatenating them onto the
                        // winner was the first fix and it ping-pongs without bound between two
                        // honest devices (see `parkDisplacedNote`). Park instead: the winner
                        // stays a clean LWW result and the loser's text is still not lost.
                        parkDisplacedNote(loser.note, from: loser, work: work, in: context)
                    }
                }
                SyncTombstones.recordDeletion(of: loser, in: context, reason: "samePassageDeduped")
                if preexistingIDs.contains(loser.id) {
                    // Soft-delete: the row and its text survive and can be recovered.
                    loser.isPendingDeletion = true
                    loser.deletedAt = Date()
                    loser.markModified()
                } else {
                    context.delete(loser)
                }
            }
        }
    }

    private struct TombstoneIndex {
        private var savedWorkTombstonesByID: [UUID: SyncTombstone] = [:]
        private var savedWorkTombstonesByAO3WorkID: [Int: SyncTombstone] = [:]
        private var savedWorkTombstonesByCanonicalURL: [String: SyncTombstone] = [:]
        private var collectionTombstonesByID: [UUID: SyncTombstone] = [:]
        private var queueTombstonesByID: [UUID: SyncTombstone] = [:]
        private var membershipTombstonesByID: [UUID: SyncTombstone] = [:]
        private var collectionMembershipTombstonesByID: [UUID: SyncTombstone] = [:]
        private var annotationTombstonesByID: [UUID: SyncTombstone] = [:]
        private var bookmarkTombstonesByID: [UUID: SyncTombstone] = [:]
        private var savedSearchTombstonesByID: [UUID: SyncTombstone] = [:]

        init(_ tombstones: [SyncTombstone]) {
            for tombstone in tombstones {
                switch tombstone.recordType {
                case .savedWork:
                    // Delete → re-download → delete leaves several tombstones sharing an
                    // AO3 identity, and the fetch order is unspecified — always keep the
                    // newest so a stale tombstone can't wrongly re-admit an old snapshot.
                    indexNewest(tombstone, byID: tombstone.recordID)
                    if let ao3WorkID = tombstone.ao3WorkID {
                        indexNewest(tombstone, byAO3WorkID: ao3WorkID)
                    }
                    if let canonicalURL = WorkTags.canonicalAO3WorkURL(from: tombstone.sourceURL) {
                        indexNewest(tombstone, byCanonicalURL: canonicalURL)
                    }
                case .workCollection:
                    indexNewest(tombstone, byCollectionID: tombstone.recordID)
                case .readingQueue:
                    indexNewest(tombstone, byQueueID: tombstone.recordID)
                case .readingQueueMembership:
                    indexNewest(tombstone, byMembershipID: tombstone.recordID)
                case .workCollectionMembership:
                    indexNewest(tombstone, byCollectionMembershipID: tombstone.recordID)
                case .readingAnnotation:
                    indexNewest(tombstone, byAnnotationID: tombstone.recordID)
                case .bookmark:
                    indexNewest(tombstone, byBookmarkID: tombstone.recordID)
                case .savedSearch:
                    indexNewest(tombstone, bySavedSearchID: tombstone.recordID)
                }
            }
        }

        private mutating func indexNewest(_ tombstone: SyncTombstone, byID id: UUID) {
            if let existing = savedWorkTombstonesByID[id], existing.lastModifiedAt >= tombstone.lastModifiedAt {
                return
            }
            savedWorkTombstonesByID[id] = tombstone
        }

        private mutating func indexNewest(_ tombstone: SyncTombstone, byAO3WorkID id: Int) {
            if let existing = savedWorkTombstonesByAO3WorkID[id],
               existing.lastModifiedAt >= tombstone.lastModifiedAt {
                return
            }
            savedWorkTombstonesByAO3WorkID[id] = tombstone
        }

        private mutating func indexNewest(_ tombstone: SyncTombstone, byCanonicalURL url: String) {
            if let existing = savedWorkTombstonesByCanonicalURL[url],
               existing.lastModifiedAt >= tombstone.lastModifiedAt {
                return
            }
            savedWorkTombstonesByCanonicalURL[url] = tombstone
        }

        private mutating func indexNewest(_ tombstone: SyncTombstone, byCollectionID id: UUID) {
            if let existing = collectionTombstonesByID[id], existing.lastModifiedAt >= tombstone.lastModifiedAt {
                return
            }
            collectionTombstonesByID[id] = tombstone
        }

        private mutating func indexNewest(_ tombstone: SyncTombstone, byQueueID id: UUID) {
            if let existing = queueTombstonesByID[id], existing.lastModifiedAt >= tombstone.lastModifiedAt {
                return
            }
            queueTombstonesByID[id] = tombstone
        }

        private mutating func indexNewest(_ tombstone: SyncTombstone, byMembershipID id: UUID) {
            if let existing = membershipTombstonesByID[id],
               existing.lastModifiedAt >= tombstone.lastModifiedAt {
                return
            }
            membershipTombstonesByID[id] = tombstone
        }

        private mutating func indexNewest(_ tombstone: SyncTombstone, byAnnotationID id: UUID) {
            if let existing = annotationTombstonesByID[id],
               existing.lastModifiedAt >= tombstone.lastModifiedAt {
                return
            }
            annotationTombstonesByID[id] = tombstone
        }

        private mutating func indexNewest(_ tombstone: SyncTombstone, byCollectionMembershipID id: UUID) {
            if let existing = collectionMembershipTombstonesByID[id],
               existing.lastModifiedAt >= tombstone.lastModifiedAt {
                return
            }
            collectionMembershipTombstonesByID[id] = tombstone
        }

        private mutating func indexNewest(_ tombstone: SyncTombstone, byBookmarkID id: UUID) {
            if let existing = bookmarkTombstonesByID[id],
               existing.lastModifiedAt >= tombstone.lastModifiedAt {
                return
            }
            bookmarkTombstonesByID[id] = tombstone
        }

        private mutating func indexNewest(_ tombstone: SyncTombstone, bySavedSearchID id: UUID) {
            if let existing = savedSearchTombstonesByID[id],
               existing.lastModifiedAt >= tombstone.lastModifiedAt {
                return
            }
            savedSearchTombstonesByID[id] = tombstone
        }

        /// Whether importing this archived work would resurrect an explicit local delete.
        func suppressesResurrection(of archived: KudosBackupWork) -> Bool {
            let tombstone: SyncTombstone? = if let archivedAO3WorkID = archived.ao3WorkID ?? WorkTags.ao3WorkID(from: archived.sourceURL),
                                               let match = savedWorkTombstonesByAO3WorkID[archivedAO3WorkID] {
                match
            } else if let canonicalURL = WorkTags.canonicalAO3WorkURL(from: archived.sourceURL),
                      let match = savedWorkTombstonesByCanonicalURL[canonicalURL] {
                match
            } else {
                savedWorkTombstonesByID[archived.id]
            }
            guard let tombstone else { return false }
            let archivedModifiedAt = archived.lastModifiedAt ?? archived.dateAdded
            return tombstone.lastModifiedAt >= archivedModifiedAt
        }

        func collectionResolution(id: UUID, incomingModifiedAt: Date?) -> SyncMerge.TombstoneResolution {
            SyncMerge.tombstoneResolution(
                incomingModifiedAt: incomingModifiedAt,
                tombstoneDeletedAt: collectionTombstonesByID[id]?.lastModifiedAt
            )
        }

        func queueResolution(id: UUID, incomingModifiedAt: Date?) -> SyncMerge.TombstoneResolution {
            SyncMerge.tombstoneResolution(
                incomingModifiedAt: incomingModifiedAt,
                tombstoneDeletedAt: queueTombstonesByID[id]?.lastModifiedAt
            )
        }

        func annotationResolution(id: UUID, incomingModifiedAt: Date?) -> SyncMerge.TombstoneResolution {
            SyncMerge.tombstoneResolution(
                incomingModifiedAt: incomingModifiedAt,
                tombstoneDeletedAt: annotationTombstonesByID[id]?.lastModifiedAt
            )
        }

        func bookmarkResolution(id: UUID, incomingModifiedAt: Date?) -> SyncMerge.TombstoneResolution {
            SyncMerge.tombstoneResolution(
                incomingModifiedAt: incomingModifiedAt,
                tombstoneDeletedAt: bookmarkTombstonesByID[id]?.lastModifiedAt
            )
        }

        func savedSearchResolution(id: UUID, incomingModifiedAt: Date?) -> SyncMerge.TombstoneResolution {
            SyncMerge.tombstoneResolution(
                incomingModifiedAt: incomingModifiedAt,
                tombstoneDeletedAt: savedSearchTombstonesByID[id]?.lastModifiedAt
            )
        }

        func membershipResolution(id: UUID, incomingModifiedAt: Date?) -> SyncMerge.TombstoneResolution {
            SyncMerge.tombstoneResolution(
                incomingModifiedAt: incomingModifiedAt,
                tombstoneDeletedAt: membershipTombstonesByID[id]?.lastModifiedAt
            )
        }

        /// Whether a work explicitly removed from this collection should stay removed
        /// rather than being re-added by an archived manifest that still lists it.
        func suppressesCollectionMembership(
            collectionID: UUID,
            workID: UUID,
            incomingModifiedAt: Date?
        ) -> Bool {
            let id = SyncTombstone.collectionMembershipID(collectionID: collectionID, workID: workID)
            guard let tombstone = collectionMembershipTombstonesByID[id] else { return false }
            guard let incomingModifiedAt else { return true }
            return tombstone.lastModifiedAt >= incomingModifiedAt
        }
    }

    private static func makeTombstone(from archived: KudosBackupTombstone) -> SyncTombstone? {
        guard let recordType = SyncTombstoneRecordType(rawValue: archived.recordTypeRaw) else {
            return nil
        }
        let tombstone = SyncTombstone(
            recordID: archived.recordID,
            recordType: recordType,
            sourceURL: archived.sourceURL,
            ao3WorkID: archived.ao3WorkID,
            createdAt: archived.createdAt,
            deletedOnDeviceID: archived.deletedOnDeviceID,
            deletionReason: archived.deletionReason,
            signerPublicKey: archived.signerPublicKey,
            signature: archived.signature
        )
        tombstone.id = archived.id
        // Only createdAt is inside the signed payload. lastModifiedAt decides
        // suppression, so never let an unsigned wire field set it.
        tombstone.lastModifiedAt = archived.createdAt
        return tombstone
    }

    /// Thin adapter over the shared `WorkIdentityIndex` for archived backup records
    /// (which carry the originating record's UUID as a last-resort identity tier).
    private struct WorkRestoreIndex {
        private var identity: WorkIdentityIndex

        init(_ works: [SavedWork]) {
            identity = WorkIdentityIndex(works)
        }

        mutating func index(_ work: SavedWork) {
            identity.index(work)
        }

        func existingWork(for archived: KudosBackupWork) -> SavedWork? {
            identity.existingWork(
                ao3WorkID: archived.ao3WorkID,
                sourceURL: archived.sourceURL,
                recordID: archived.id
            )
        }
    }

    /// Whether a restore may overwrite `local`'s EPUB bytes with an archived asset.
    ///
    /// The old code replaced whenever `contents.epubFiles[archived.id]` existed — no
    /// timestamp check, no preservation check, nothing. That is a *separate* hole from
    /// the merge-priority one: `WorkRestoreIndex.existingWork` binds an archived record
    /// to a local work by **`ao3WorkID` first**, and AO3 work ids are public, so any
    /// archive naming a work id the victim happens to own could replace that work's
    /// file with attacker bytes. Clamping timestamps does not touch this path.
    ///
    /// The rule: **a `.preserved` work that still has its file is never byte-replaced by a
    /// restore.** Preservation is the app's promise that this exact copy is being kept — often
    /// of a fic that no longer exists upstream — so a merge must not silently swap it. A work
    /// with no local file can always be filled in, and a brand-new record has nothing to lose.
    ///
    /// An earlier draft also allowed replacement when `local.id == archivedID`, reasoning that
    /// a record round-tripping through the user's own backup should be able to restore itself.
    /// That hatch is attacker-reachable: an A4 adversary reads record UUIDs straight out of the
    /// sync folder's `manifest.json` (the same read that yields annotation locators), and
    /// `FolderSyncService.readChangedRemoteAssets` treats a size difference as a change signal
    /// and hands the remote bytes to `restore` under that very id. Same-id was therefore no
    /// evidence of provenance at all. Dropped — a preserved file that is still on disk does not
    /// need restoring over the top of itself.
    ///
    /// **Must ship with M1d.** `apply(_:to:isNewRecord:)` runs earlier in the same loop
    /// iteration than the EPUB branch, so without the monotonic-preservation rule a single
    /// restore can flip `.preserved` to `.notPreserved` and then satisfy this gate on the very
    /// next line.
    ///
    /// Pure and internal so the policy is unit-testable without a `ModelContext`.
    nonisolated static func mayReplaceEPUB(
        local: SavedWork,
        isNewRecord: Bool
    ) -> Bool {
        if isNewRecord { return true }
        if !local.hasEPUB { return true }
        return local.epubPreservationStatus != .preserved
    }

    /// The `(isPendingDeletion, permanentDeletionScheduledAt)` a soft-deletable record should
    /// carry once an archive-supplied `isDeleted` flag has been applied to it.
    ///
    /// **`permanentDeletionScheduledAt` is never copied from the archive.** It was, at every one
    /// of the three merge sites (works, collections, queues), and that is a whole-library
    /// destruction bug: `PreservedWorkService.sweepExpired` hard-deletes anything with
    /// `isPendingDeletion && scheduledAt <= now` (`PreservedWorkService.swift:150-176`) and runs
    /// on **every launch** from `ContentView.swift:94`, deliberately independent of folder sync.
    /// So one `manifest.json` in the Library Sync Folder carrying `isDeleted: true` plus a
    /// past `permanentDeletionScheduledAt` — with a `lastModifiedAt` high enough to win
    /// `incomingWins` — permanently destroys every work, collection and queue on the next
    /// launch, straight through the 90-day Recently Deleted window that
    /// `DATA_AND_PERSISTENCE_INVARIANTS.md` promises. No user interaction beyond having
    /// trusted the folder.
    ///
    /// The countdown is therefore always this device's own: `now + recoveryWindow` when a
    /// record enters Recently Deleted, `nil` when it leaves. Soft-delete still syncs in both
    /// directions — only the *schedule* is refused.
    ///
    /// Pure and internal so the policy is unit-testable without a `ModelContext`.
    nonisolated static func archivedDeletionState(
        incomingIsDeleted: Bool,
        localIsPendingDeletion: Bool,
        localScheduledAt: Date?,
        now: Date = Date()
    ) -> (isPendingDeletion: Bool, scheduledAt: Date?) {
        guard incomingIsDeleted else { return (false, nil) }
        // Already counting down on this device: keep that countdown. Restarting it every time
        // the flag round-trips through sync would push the sweep date out forever and the
        // record would never actually be swept.
        if localIsPendingDeletion, let localScheduledAt { return (true, localScheduledAt) }
        return (true, now.addingTimeInterval(PreservedWorkService.recoveryWindow))
    }

    private static func apply(_ archived: KudosBackupWork, to work: SavedWork, isNewRecord: Bool) {
        let incomingModifiedAt = archived.lastModifiedAt ?? archived.dateAdded
        // A freshly-created placeholder's lastModifiedAt is "now" (restore time), which is
        // always at least as new as any real archived snapshot — so incomingWins alone would
        // never let a brand-new record adopt the archive's flags. Treat "no prior local state
        // to protect" the same way mergedText/mergedPositive already treat an empty/zero
        // current value: always accept the incoming value.
        let incomingWins = isNewRecord || SyncMerge.shouldApplyIncoming(
            localModifiedAt: work.lastModifiedAt,
            incomingModifiedAt: incomingModifiedAt
        )

        work.createdAt = min(work.createdAt, archived.createdAt ?? archived.dateAdded)
        work.dateAdded = min(work.dateAdded, archived.dateAdded)
        if let assetIdentifier = archived.assetIdentifier, !assetIdentifier.isEmpty {
            work.assetIdentifier = work.assetIdentifier.isEmpty ? assetIdentifier : work.assetIdentifier
        }

        work.title = mergedText(current: work.title, incoming: archived.title, incomingWins: incomingWins)
        work.author = mergedText(current: work.author, incoming: archived.author, incomingWins: incomingWins)
        work.summary = mergedText(current: work.summary, incoming: archived.summary, incomingWins: incomingWins)
        work.sourceURL = mergedText(current: work.sourceURL, incoming: archived.sourceURL, incomingWins: incomingWins)
        work.rating = mergedText(current: work.rating, incoming: archived.rating, incomingWins: incomingWins)
        work.language = mergedText(current: work.language, incoming: archived.language, incomingWins: incomingWins)
        work.datePublished = mergedText(
            current: work.datePublished,
            incoming: archived.datePublished ?? "",
            incomingWins: incomingWins
        )
        work.dateUpdated = mergedText(
            current: work.dateUpdated,
            incoming: archived.dateUpdated ?? "",
            incomingWins: incomingWins
        )
        work.chapters = mergedText(current: work.chapters, incoming: archived.chapters, incomingWins: incomingWins)
        work.seriesTitle = mergedText(
            current: work.seriesTitle,
            incoming: archived.seriesTitle,
            incomingWins: incomingWins
        )
        work.seriesURL = mergedText(current: work.seriesURL, incoming: archived.seriesURL, incomingWins: incomingWins)

        work.isFavorite = incomingWins ? archived.isFavorite : work.isFavorite
        work.isSaved = incomingWins ? archived.isSaved : work.isSaved
        work.isFinished = incomingWins ? archived.isFinished : work.isFinished
        work.isComplete = incomingWins ? archived.isComplete : work.isComplete
        work.deletedAt = newest(work.deletedAt, archived.deletedAt)
        // incomingWins-gated like the flags above — a device that already called restore()
        // must win over a stale device that hasn't synced the restore yet. The *schedule*
        // is this device's own and is never taken from the archive: see
        // `archivedDeletionState`.
        if incomingWins {
            let deletion = archivedDeletionState(
                incomingIsDeleted: archived.isDeleted ?? false,
                localIsPendingDeletion: work.isPendingDeletion,
                localScheduledAt: work.permanentDeletionScheduledAt
            )
            work.isPendingDeletion = deletion.isPendingDeletion
            work.permanentDeletionScheduledAt = deletion.scheduledAt
        }

        work.wordCount = mergedPositive(
            current: work.wordCount,
            incoming: archived.wordCount,
            incomingWins: incomingWins
        )
        work.kudos = mergedPositive(current: work.kudos, incoming: archived.kudos, incomingWins: incomingWins)
        work.comments = mergedPositive(current: work.comments, incoming: archived.comments, incomingWins: incomingWins)
        work.bookmarks = mergedPositive(
            current: work.bookmarks,
            incoming: archived.bookmarks,
            incomingWins: incomingWins
        )
        work.hits = mergedPositive(current: work.hits, incoming: archived.hits, incomingWins: incomingWins)
        if incomingWins || work.seriesPosition == 0 {
            work.seriesPosition = max(work.seriesPosition, archived.seriesPosition)
        }
        work.ao3SeriesID = work.ao3SeriesID ?? archived.ao3SeriesID
        work.ao3WorkID = work.ao3WorkID ?? archived.ao3WorkID ?? WorkTags.ao3WorkID(from: archived.sourceURL)

        work.workWarnings = TagMerge.merged(work.workWarnings, archived.workWarnings)
        work.workCategories = TagMerge.merged(work.workCategories, archived.workCategories)
        work.workTags = TagMerge.merged(work.workTags, archived.workTags)
        work.workFandoms = TagMerge.merged(work.workFandoms, archived.workFandoms)
        work.workCharacters = TagMerge.merged(work.workCharacters, archived.workCharacters)
        work.workRelationships = TagMerge.merged(work.workRelationships, archived.workRelationships)
        work.workFreeforms = TagMerge.merged(work.workFreeforms, archived.workFreeforms)
        work.workTagsFetched = work.workTagsFetched || archived.workTagsFetched
        work.ao3Unavailable = work.ao3Unavailable || archived.ao3Unavailable
        work.isQueuedForLater = work.isQueuedForLater || archived.isQueuedForLater

        // Preservation is monotonic under merge: an archive may promote a work to
        // `.preserved`, never demote one. A future-dated record used to win
        // `incomingWins` and flip a preserved work back to `.notPreserved`, which both
        // loses the user's explicit intent and re-opens the byte-replacement path that
        // `mayReplaceEPUB` closes. Local `.preserved` is the floor; only the user
        // un-preserves, through the UI.
        if work.epubPreservationStatus != .preserved,
           incomingWins || work.epubPreservationStatus == .notPreserved {
            work.epubPreservationStatusRaw = archived.epubPreservationStatusRaw
        }
        if incomingWins || work.metadataSyncStatus == .unknown {
            work.metadataSyncStatusRaw = archived.metadataSyncStatusRaw
        }
        work.preservedAt = newest(work.preservedAt, archived.preservedAt)
        work.lastPreservationAttemptAt = newest(
            work.lastPreservationAttemptAt,
            archived.lastPreservationAttemptAt
        )
        work.lastAvailabilityCheck = newest(work.lastAvailabilityCheck, archived.lastAvailabilityCheck)

        SyncMerge.applyProgress(
            SyncMerge.ProgressSnapshot(
                lastSpineIndex: archived.lastSpineIndex,
                lastScrollFraction: archived.lastScrollFraction,
                readiumLocator: archived.readiumLocator ?? "",
                lastReadDate: archived.lastReadDate,
                modifiedAt: archived.progressModifiedAt
            ),
            to: work
        )
        work.lastModifiedAt = max(work.lastModifiedAt, incomingModifiedAt)
    }

    private static func mergedText(current: String, incoming: String, incomingWins: Bool) -> String {
        let trimmed = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return current }
        return current.isEmpty || incomingWins ? incoming : current
    }

    private static func mergedPositive(current: Int, incoming: Int, incomingWins: Bool) -> Int {
        guard incoming > 0 else { return current }
        return current == 0 || incomingWins ? incoming : current
    }

    private static func newest(_ first: Date?, _ second: Date?) -> Date? {
        switch (first, second) {
        case let (first?, second?): max(first, second)
        case let (first?, nil): first
        case let (nil, second?): second
        case (nil, nil): nil
        }
    }
}
