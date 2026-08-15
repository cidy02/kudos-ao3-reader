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
    let manifest: KudosBackupManifest
    let epubFiles: [UUID: Data]
    let fontFiles: [String: Data]

    nonisolated init(
        manifest: KudosBackupManifest,
        epubFiles: [UUID: Data] = [:],
        fontFiles: [String: Data] = [:]
    ) {
        self.manifest = manifest
        self.epubFiles = epubFiles
        self.fontFiles = fontFiles
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
        for font in manifest.fonts {
            guard Self.isSafeFileName(font.fileName),
                  let data = fontWrappers[font.fileName]?.regularFileContents
            else { continue }
            fonts[font.fileName] = data
        }
        fontFiles = fonts
    }

    /// Reads a backup from either physical format: a single `.kudosbackup` ZIP
    /// archive (current) or a legacy directory package (read-only support).
    nonisolated static func read(from url: URL) throws -> Self {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if isDirectory {
            let wrapper = try FileWrapper(url: url, options: .immediate)
            return try Self(fileWrapper: wrapper)
        }
        return try Self(zipData: Data(contentsOf: url, options: .mappedIfSafe))
    }

    nonisolated init(zipData: Data) throws {
        let zip: MiniZip
        do {
            zip = try MiniZip(data: zipData, limits: .backup)
        } catch {
            throw KudosBackupError.invalidPackage
        }
        guard let manifestData = zip.data(named: "manifest.json") else {
            throw KudosBackupError.invalidPackage
        }

        manifest = try Self.makeDecoder().decode(KudosBackupManifest.self, from: manifestData)
        guard KudosBackupManifest.supportedVersions.contains(manifest.version) else {
            throw KudosBackupError.unsupportedVersion(manifest.version)
        }

        var epubs: [UUID: Data] = [:]
        for work in manifest.works {
            guard let data = zip.data(named: "Works/\(work.id.uuidString).epub") else { continue }
            epubs[work.id] = data
        }
        epubFiles = epubs

        var fonts: [String: Data] = [:]
        for font in manifest.fonts {
            guard Self.isSafeFileName(font.fileName),
                  let data = zip.data(named: "Fonts/\(font.fileName)")
            else { continue }
            fonts[font.fileName] = data
        }
        fontFiles = fonts
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

    // Plain `.iso8601` has no fractional-second support (whole-seconds only), which
    // silently truncates every timestamp on export. Two edits from different devices
    // landing in the same wall-clock second — a real possibility with auto-sync —
    // would then be unorderable by every lastModifiedAt-based merge decision in this
    // file. A custom formatter with fractional seconds fixes that; the decoder falls
    // back to the plain formatter so older `.kudosbackup` files (encoded without
    // fractional seconds) still decode correctly.
    // ISO8601DateFormatter is not Sendable; formatters are configured once and
    // only read afterwards (thread-safe for that usage). nonisolated(unsafe)
    // keeps encode/decode helpers callable from nonisolated backup paths.
    nonisolated(unsafe) private static let fractionalSecondsISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let wholeSecondISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    nonisolated private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractionalSecondsISO8601Formatter.string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    nonisolated private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = fractionalSecondsISO8601Formatter.date(from: string) {
                return date
            }
            if let date = wholeSecondISO8601Formatter.date(from: string) {
                return date
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
    // Carrying tombstones with the backup means a fresh install/reinstall restoring
    // this file inherits the source device's deletion history, instead of having zero
    // tombstone knowledge and silently resurrecting anything deleted after export.
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
    let title: String
    let urlString: String
    let dateAdded: Date

    @MainActor
    init(bookmark: Bookmark) {
        title = bookmark.title
        urlString = bookmark.urlString
        dateAdded = bookmark.dateAdded
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
                fallback: Self.defaultReaderFontSizePt
            ),
            readerLineHeight: number(
                defaults,
                "readerLineHeight",
                fallback: Self.defaultReaderLineHeight
            ),
            readerLetterSpacing: number(defaults, "readerLetterSpacing", fallback: 0),
            readerWordSpacing: number(defaults, "readerWordSpacing", fallback: 0),
            readerMargin: number(
                defaults,
                "readerMargin",
                fallback: Self.defaultReaderMargin
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
            accentColorHex: defaults.string(forKey: "accentColorHex") ?? Self.defaultAccentColorHex,
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
        defaults.set(readerFontID, forKey: "readerFontID")
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
        defaults.set(confirmBeforeDelete, forKey: "confirmBeforeDelete")
        defaults.set(hideMatureContent, forKey: "hideMatureContent")
        defaults.set(matureContentMode, forKey: "matureContentMode")
        defaults.set(requireBiometricToReveal, forKey: "requireBiometricToReveal")
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

nonisolated enum KudosBackupError: LocalizedError {
    case invalidPackage
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .invalidPackage:
            "This file is not a valid Kudos backup."
        case let .unsupportedVersion(version):
            "This backup uses unsupported format version \(version)."
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
///   re-add them.
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
            if let data = try? Data(contentsOf: work.fileURL, options: .mappedIfSafe) {
                epubFiles[work.id] = data
            }
        }

        var fontFiles: [String: Data] = [:]
        for font in fonts {
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

    // Restore is transactional and intentionally linear for data-safety review.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func restore(
        _ contents: KudosBackupContents,
        into context: ModelContext,
        defaults: UserDefaults = .standard,
        mode: BackupImportMode = .reconcile
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
            context.insert(adopted)
            batchTombstones.append(adopted)
        }
        let tombstones = TombstoneIndex(batchTombstones)

        let existingTags = try context.fetch(FetchDescriptor<Tag>())
        var tagsByName = Dictionary(
            existingTags.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )

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

            if let epub = contents.epubFiles[archived.id] {
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
            collection.isPendingDeletion = incomingWins ? (archived.isDeleted ?? false) : collection.isPendingDeletion
            collection.permanentDeletionScheduledAt = incomingWins
                ? archived.permanentDeletionScheduledAt
                : collection.permanentDeletionScheduledAt
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
            queue.isPendingDeletion = incomingWins ? (archived.isDeleted ?? false) : queue.isPendingDeletion
            queue.permanentDeletionScheduledAt = incomingWins
                ? archived.permanentDeletionScheduledAt
                : queue.permanentDeletionScheduledAt
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
                context.delete(search)
            }
        }

        let existingBookmarks = try context.fetch(FetchDescriptor<Bookmark>())
        var bookmarksByURL = Dictionary(
            existingBookmarks.map { ($0.urlString, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for archived in contents.manifest.bookmarks {
            let bookmark: Bookmark
            if let existing = bookmarksByURL[archived.urlString] {
                bookmark = existing
            } else {
                bookmark = Bookmark(title: archived.title, urlString: archived.urlString)
                context.insert(bookmark)
                bookmarksByURL[archived.urlString] = bookmark
            }
            bookmark.title = archived.title
            bookmark.dateAdded = archived.dateAdded
        }
        if mode == .replaceLibrary {
            // Bookmarks have no Recently Deleted UI. Drop omissions without a
            // tombstone so a later Merge can insert them again.
            let snapshotURLs = Set(contents.manifest.bookmarks.map(\.urlString))
            for bookmark in existingBookmarks where !snapshotURLs.contains(bookmark.urlString) {
                context.delete(bookmark)
            }
        }

        let existingFonts = try context.fetch(FetchDescriptor<CustomFont>())
        var fontsByFileName = Dictionary(
            existingFonts.map { ($0.fileName, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var restoredFonts = 0
        for archived in contents.manifest.fonts {
            guard let data = contents.fontFiles[archived.fileName] else { continue }
            let font: CustomFont
            if let existing = fontsByFileName[archived.fileName] {
                font = existing
            } else {
                font = CustomFont(name: archived.name, fileName: archived.fileName)
                context.insert(font)
                fontsByFileName[archived.fileName] = font
            }
            font.name = archived.name
            font.dateAdded = archived.dateAdded
            try data.write(to: font.fileURL, options: .atomic)
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

        dedupeSamePassageAnnotations(context: context)
    }

    /// ANN-8: two devices creating the "same" highlight/bookmark offline
    /// produce two different UUIDs, so id-keyed merging above never notices.
    /// After the restore merge, collapse any still-live annotations that
    /// share (work, kind, **exact** locator string) — same-kind only, never a
    /// fuzzy text match. The most recently modified one wins; a non-empty
    /// note on the loser is salvaged onto the winner if the winner has none.
    private static func dedupeSamePassageAnnotations(context: ModelContext) {
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
                if winner.note.isEmpty, !loser.note.isEmpty {
                    winner.note = loser.note
                    // Salvaging is a real content edit: without stamping it, the
                    // winner keeps its old `lastModifiedAt`, and the very next
                    // merge would see a "newer" remote copy of the winner (which
                    // still has an empty note) and overwrite the rescued note —
                    // silently undoing the salvage this dedup just performed.
                    winner.markModified()
                }
                SyncTombstones.recordDeletion(of: loser, in: context, reason: "samePassageDeduped")
                context.delete(loser)
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

        /// Whether importing this archived work would resurrect an explicit local delete.
        func suppressesResurrection(of archived: KudosBackupWork) -> Bool {
            let tombstone: SyncTombstone?
            if let archivedAO3WorkID = archived.ao3WorkID ?? WorkTags.ao3WorkID(from: archived.sourceURL),
               let match = savedWorkTombstonesByAO3WorkID[archivedAO3WorkID] {
                tombstone = match
            } else if let canonicalURL = WorkTags.canonicalAO3WorkURL(from: archived.sourceURL),
                      let match = savedWorkTombstonesByCanonicalURL[canonicalURL] {
                tombstone = match
            } else {
                tombstone = savedWorkTombstonesByID[archived.id]
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
        tombstone.lastModifiedAt = archived.lastModifiedAt
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
        work.isPendingDeletion = incomingWins ? (archived.isDeleted ?? false) : work.isPendingDeletion
        work.deletedAt = newest(work.deletedAt, archived.deletedAt)
        // incomingWins-gated like isDeleted, not a blind "newest wins" — a device that
        // already called restore() (clearing this field) must win over a stale device
        // that hasn't synced the restore yet, the same way an un-set isDeleted does.
        work.permanentDeletionScheduledAt = incomingWins
            ? archived.permanentDeletionScheduledAt
            : work.permanentDeletionScheduledAt

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

        if incomingWins || work.epubPreservationStatus == .notPreserved {
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
