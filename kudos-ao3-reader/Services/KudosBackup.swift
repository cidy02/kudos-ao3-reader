import Foundation
import OSLog
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// Backup archive schema/restore logic is cohesive; avoid behavior refactors for lint.
// swiftlint:disable file_length

extension UTType {
    /// A directory-backed document package containing a JSON manifest and assets.
    static let kudosBackup = UTType(
        filenameExtension: "kudosbackup",
        conformingTo: .package
    )!
}

struct KudosBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.kudosBackup]
    }

    let contents: KudosBackupContents

    init(contents: KudosBackupContents) {
        self.contents = contents
    }

    init(configuration: ReadConfiguration) throws {
        contents = try KudosBackupContents(fileWrapper: configuration.file)
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        try contents.fileWrapper()
    }
}

struct KudosBackupContents {
    let manifest: KudosBackupManifest
    let epubFiles: [UUID: Data]
    let fontFiles: [String: Data]

    init(
        manifest: KudosBackupManifest,
        epubFiles: [UUID: Data] = [:],
        fontFiles: [String: Data] = [:]
    ) {
        self.manifest = manifest
        self.epubFiles = epubFiles
        self.fontFiles = fontFiles
    }

    init(fileWrapper root: FileWrapper) throws {
        guard root.isDirectory, let rootFiles = root.fileWrappers,
              let manifestData = rootFiles["manifest.json"]?.regularFileContents
        else {
            throw KudosBackupError.invalidPackage
        }

        manifest = try Self.decoder.decode(KudosBackupManifest.self, from: manifestData)
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

    static func read(from url: URL) throws -> Self {
        let wrapper = try FileWrapper(url: url, options: .immediate)
        return try Self(fileWrapper: wrapper)
    }

    func fileWrapper() throws -> FileWrapper {
        let manifestData = try Self.encoder.encode(manifest)
        var rootFiles = [
            "manifest.json": FileWrapper(regularFileWithContents: manifestData)
        ]

        let works = Dictionary(uniqueKeysWithValues: epubFiles.map { id, data in
            ("\(id.uuidString).epub", FileWrapper(regularFileWithContents: data))
        })
        rootFiles["Works"] = FileWrapper(directoryWithFileWrappers: works)

        var fonts: [String: FileWrapper] = [:]
        for (fileName, data) in fontFiles where Self.isSafeFileName(fileName) {
            fonts[fileName] = FileWrapper(regularFileWithContents: data)
        }
        rootFiles["Fonts"] = FileWrapper(directoryWithFileWrappers: fonts)

        return FileWrapper(directoryWithFileWrappers: rootFiles)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static func isSafeFileName(_ fileName: String) -> Bool {
        !fileName.isEmpty
            && URL(fileURLWithPath: fileName).lastPathComponent == fileName
            && !fileName.contains("/")
            && !fileName.contains("\\")
    }
}

struct KudosBackupManifest: Codable, Equatable {
    static let currentVersion = 5
    static let supportedVersions: Set<Int> = [1, 2, 3, 4, currentVersion]

    let version: Int
    let exportedAt: Date
    let works: [KudosBackupWork]
    let bookmarks: [KudosBackupBookmark]
    let fonts: [KudosBackupFont]
    let readingQueues: [KudosBackupReadingQueue]
    let readingQueueMemberships: [KudosBackupReadingQueueMembership]
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
        readingQueues: [KudosBackupReadingQueue] = [],
        readingQueueMemberships: [KudosBackupReadingQueueMembership] = [],
        settings: KudosBackupSettings,
        tombstones: [KudosBackupTombstone] = []
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.works = works
        self.bookmarks = bookmarks
        self.fonts = fonts
        self.readingQueues = readingQueues
        self.readingQueueMemberships = readingQueueMemberships
        self.settings = settings
        self.tombstones = tombstones
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case exportedAt
        case works
        case bookmarks
        case fonts
        case readingQueues
        case readingQueueMemberships
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
        readingQueues = try container.decodeIfPresent(
            [KudosBackupReadingQueue].self,
            forKey: .readingQueues
        ) ?? []
        readingQueueMemberships = try container.decodeIfPresent(
            [KudosBackupReadingQueueMembership].self,
            forKey: .readingQueueMemberships
        ) ?? []
        settings = try container.decode(KudosBackupSettings.self, forKey: .settings)
        tombstones = try container.decodeIfPresent(
            [KudosBackupTombstone].self,
            forKey: .tombstones
        ) ?? []
    }
}

struct KudosBackupTombstone: Codable, Equatable {
    let id: UUID
    let recordID: UUID
    let recordTypeRaw: String
    let createdAt: Date
    let lastModifiedAt: Date
    let sourceURL: String
    let ao3WorkID: Int?
    let deletedOnDeviceID: String
    let deletionReason: String

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
    }
}

struct KudosBackupWork: Codable, Equatable {
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
        isDeleted = work.isDeleted
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

struct KudosBackupBookmark: Codable, Equatable {
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

struct KudosBackupFont: Codable, Equatable {
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

struct KudosBackupReadingQueue: Codable, Equatable {
    let id: UUID
    let name: String
    let kindRaw: String
    let sortOrder: Int
    let dateCreated: Date
    let dateUpdated: Date
    let lastMembershipChangedAt: Date?

    @MainActor
    init(queue: ReadingQueue) {
        id = queue.id
        name = queue.name
        kindRaw = queue.kindRaw
        sortOrder = queue.sortOrder
        dateCreated = queue.dateCreated
        dateUpdated = queue.dateUpdated
        lastMembershipChangedAt = queue.lastMembershipChangedAt
    }

    func effectiveModifiedAt(memberships: [KudosBackupReadingQueueMembership]) -> Date? {
        SyncMerge.effectiveQueueModifiedAt(
            queueUpdatedAt: dateUpdated,
            lastMembershipChangedAt: lastMembershipChangedAt,
            membershipModifiedAts: memberships.map { $0.lastModifiedAt ?? $0.queuedAt }
        )
    }
}

struct KudosBackupReadingQueueMembership: Codable, Equatable {
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

struct KudosBackupSettings: Codable, Equatable {
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
                ?? ReaderTextStyle.defaultFontSizePt,
            readerLineHeight: container.decodeIfPresent(Double.self, forKey: .readerLineHeight)
                ?? ReaderTextStyle.defaultLineHeight,
            readerLetterSpacing: container.decodeIfPresent(Double.self, forKey: .readerLetterSpacing) ?? 0,
            readerWordSpacing: container.decodeIfPresent(Double.self, forKey: .readerWordSpacing) ?? 0,
            readerMargin: container.decodeIfPresent(Double.self, forKey: .readerMargin)
                ?? ReaderTextStyle.defaultMargin,
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
                ?? ThemeManager.ao3Red,
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
                fallback: ReaderTextStyle.defaultFontSizePt
            ),
            readerLineHeight: number(
                defaults,
                "readerLineHeight",
                fallback: ReaderTextStyle.defaultLineHeight
            ),
            readerLetterSpacing: number(defaults, "readerLetterSpacing", fallback: 0),
            readerWordSpacing: number(defaults, "readerWordSpacing", fallback: 0),
            readerMargin: number(
                defaults,
                "readerMargin",
                fallback: ReaderTextStyle.defaultMargin
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
            accentColorHex: defaults.string(forKey: "accentColorHex") ?? ThemeManager.ao3Red,
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

struct KudosBackupRestoreSummary: Equatable {
    let works: Int
    let bookmarks: Int
    let fonts: Int
    var suppressedQueues: Int = 0
    var suppressedQueueMemberships: Int = 0
    var revivedQueues: Int = 0
    var restoredRevivedQueueMemberships: Int = 0
    var ambiguousQueueConflicts: Int = 0

    var conflictMessage: String {
        var parts: [String] = []
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
        return parts.joined(separator: " ")
    }
}

enum KudosBackupError: LocalizedError {
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

// Backup restore stays intentionally linear so conflict and asset safety rules remain auditable.
@MainActor
// swiftlint:disable:next type_body_length
enum KudosBackupService {
    static func makeDocument(
        works: [SavedWork],
        bookmarks: [Bookmark],
        fonts: [CustomFont],
        readingQueues: [ReadingQueue],
        tombstones: [SyncTombstone] = [],
        defaults: UserDefaults = .standard
    ) throws -> KudosBackupDocument {
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
            readingQueues: readingQueues.map(KudosBackupReadingQueue.init),
            readingQueueMemberships: queueMemberships,
            settings: .capture(defaults: defaults),
            tombstones: tombstones.map(KudosBackupTombstone.init)
        )
        return KudosBackupDocument(contents: KudosBackupContents(
            manifest: manifest,
            epubFiles: epubFiles,
            fontFiles: fontFiles
        ))
    }

    // Restore is transactional and intentionally linear for data-safety review.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func restore(
        _ contents: KudosBackupContents,
        into context: ModelContext,
        defaults: UserDefaults = .standard
    ) throws -> KudosBackupRestoreSummary {
        let existingWorks = try context.fetch(FetchDescriptor<SavedWork>())
        var workIndex = WorkRestoreIndex(existingWorks)
        var restoredWorksByArchivedID: [UUID: SavedWork] = [:]

        // Adopt the source device's deletion history so a fresh install/reinstall
        // restoring this backup inherits the same tombstone protection the source
        // device had, instead of having zero local tombstones to consult.
        var localTombstones = try context.fetch(FetchDescriptor<SyncTombstone>())
        var knownTombstoneKeys = Set(localTombstones.map { "\($0.recordTypeRaw)|\($0.recordID)" })
        for archived in contents.manifest.tombstones {
            let key = "\(archived.recordTypeRaw)|\(archived.recordID)"
            guard !knownTombstoneKeys.contains(key) else { continue }
            let recordType = SyncTombstoneRecordType(rawValue: archived.recordTypeRaw) ?? .savedWork
            let tombstone = SyncTombstone(
                recordID: archived.recordID,
                recordType: recordType,
                sourceURL: archived.sourceURL,
                ao3WorkID: archived.ao3WorkID,
                createdAt: archived.createdAt,
                deletedOnDeviceID: archived.deletedOnDeviceID,
                deletionReason: archived.deletionReason
            )
            tombstone.lastModifiedAt = archived.lastModifiedAt
            context.insert(tombstone)
            localTombstones.append(tombstone)
            knownTombstoneKeys.insert(key)
        }
        let tombstones = TombstoneIndex(localTombstones)

        let existingTags = try context.fetch(FetchDescriptor<Tag>())
        var tagsByName = Dictionary(
            existingTags.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for archived in contents.manifest.works {
            let work: SavedWork
            let isNewRecord: Bool
            if let existing = workIndex.existingWork(for: archived) {
                work = existing
                isNewRecord = false
            } else if tombstones.suppressesResurrection(of: archived) {
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

            var seenTags = Set<String>()
            work.tags = archived.userTags.compactMap { name in
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, seenTags.insert(trimmed).inserted else { return nil }
                if let tag = tagsByName[trimmed] { return tag }
                let tag = Tag(name: trimmed)
                context.insert(tag)
                tagsByName[trimmed] = tag
                return tag
            }

            if let epub = contents.epubFiles[archived.id] {
                try epub.write(to: work.fileURL, options: .atomic)
                work.hasEPUB = true
            } else if !FileManager.default.fileExists(atPath: work.fileURL.path) {
                work.hasEPUB = false
                if work.epubPreservationStatus == .preserved {
                    work.epubPreservationStatus = .missingFile
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
            let incomingWins = SyncMerge.shouldApplyIncoming(
                localModifiedAt: localModifiedAt,
                incomingModifiedAt: incomingModifiedAt
            )
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
                if SyncMerge.shouldApplyIncoming(
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

        try context.save()
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
            ambiguousQueueConflicts: ambiguousQueueConflicts
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
    private struct TombstoneIndex {
        private var savedWorkTombstonesByID: [UUID: SyncTombstone] = [:]
        private var savedWorkTombstonesByAO3WorkID: [Int: SyncTombstone] = [:]
        private var savedWorkTombstonesByCanonicalURL: [String: SyncTombstone] = [:]
        private var queueTombstonesByID: [UUID: SyncTombstone] = [:]
        private var membershipTombstonesByID: [UUID: SyncTombstone] = [:]

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
                    break // Collections aren't part of the .kudosbackup manifest today.
                case .readingQueue:
                    indexNewest(tombstone, byQueueID: tombstone.recordID)
                case .readingQueueMembership:
                    indexNewest(tombstone, byMembershipID: tombstone.recordID)
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

        func queueResolution(id: UUID, incomingModifiedAt: Date?) -> SyncMerge.TombstoneResolution {
            SyncMerge.tombstoneResolution(
                incomingModifiedAt: incomingModifiedAt,
                tombstoneDeletedAt: queueTombstonesByID[id]?.lastModifiedAt
            )
        }

        func membershipResolution(id: UUID, incomingModifiedAt: Date?) -> SyncMerge.TombstoneResolution {
            SyncMerge.tombstoneResolution(
                incomingModifiedAt: incomingModifiedAt,
                tombstoneDeletedAt: membershipTombstonesByID[id]?.lastModifiedAt
            )
        }
    }

    private struct WorkRestoreIndex {
        private var worksByID: [UUID: SavedWork] = [:]
        private var worksByAO3WorkID: [Int: SavedWork] = [:]
        private var worksByCanonicalSourceURL: [String: SavedWork] = [:]

        init(_ works: [SavedWork]) {
            for work in works {
                index(work)
            }
        }

        mutating func index(_ work: SavedWork) {
            worksByID[work.id] = work
            if let id = work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL) {
                worksByAO3WorkID[id] = work
            }
            if let canonicalURL = WorkTags.canonicalAO3WorkURL(from: work.sourceURL) {
                worksByCanonicalSourceURL[canonicalURL] = work
            }
        }

        func existingWork(for archived: KudosBackupWork) -> SavedWork? {
            if let archivedAO3WorkID = archived.ao3WorkID ?? WorkTags.ao3WorkID(from: archived.sourceURL),
               let work = worksByAO3WorkID[archivedAO3WorkID] {
                return work
            }
            if let canonicalURL = WorkTags.canonicalAO3WorkURL(from: archived.sourceURL),
               let work = worksByCanonicalSourceURL[canonicalURL] {
                return work
            }
            return worksByID[archived.id]
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
        work.isDeleted = incomingWins ? (archived.isDeleted ?? false) : work.isDeleted
        work.deletedAt = newest(work.deletedAt, archived.deletedAt)

        work.wordCount = mergedPositive(
            current: work.wordCount,
            incoming: archived.wordCount,
            incomingWins: incomingWins
        )
        work.kudos = mergedPositive(current: work.kudos, incoming: archived.kudos, incomingWins: incomingWins)
        work.comments = mergedPositive(current: work.comments, incoming: archived.comments, incomingWins: incomingWins)
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
