import Foundation
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
    static let currentVersion = 2
    static let supportedVersions: Set<Int> = [1, currentVersion]

    let version: Int
    let exportedAt: Date
    let works: [KudosBackupWork]
    let bookmarks: [KudosBackupBookmark]
    let fonts: [KudosBackupFont]
    let readingQueues: [KudosBackupReadingQueue]
    let readingQueueMemberships: [KudosBackupReadingQueueMembership]
    let settings: KudosBackupSettings

    init(
        version: Int = currentVersion,
        exportedAt: Date = Date(),
        works: [KudosBackupWork],
        bookmarks: [KudosBackupBookmark],
        fonts: [KudosBackupFont],
        readingQueues: [KudosBackupReadingQueue] = [],
        readingQueueMemberships: [KudosBackupReadingQueueMembership] = [],
        settings: KudosBackupSettings
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.works = works
        self.bookmarks = bookmarks
        self.fonts = fonts
        self.readingQueues = readingQueues
        self.readingQueueMemberships = readingQueueMemberships
        self.settings = settings
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
    }
}

struct KudosBackupWork: Codable, Equatable {
    let id: UUID
    let title: String
    let author: String
    let summary: String
    let sourceURL: String
    let dateAdded: Date
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

    @MainActor
    init(queue: ReadingQueue) {
        id = queue.id
        name = queue.name
        kindRaw = queue.kindRaw
        sortOrder = queue.sortOrder
        dateCreated = queue.dateCreated
        dateUpdated = queue.dateUpdated
    }
}

struct KudosBackupReadingQueueMembership: Codable, Equatable {
    let id: UUID
    let queueID: UUID
    let workID: UUID
    let queuedAt: Date
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

@MainActor
enum KudosBackupService {
    static func makeDocument(
        works: [SavedWork],
        bookmarks: [Bookmark],
        fonts: [CustomFont],
        readingQueues: [ReadingQueue],
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
            settings: .capture(defaults: defaults)
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

        let existingTags = try context.fetch(FetchDescriptor<Tag>())
        var tagsByName = Dictionary(
            existingTags.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for archived in contents.manifest.works {
            let work: SavedWork
            if let existing = workIndex.existingWork(for: archived) {
                work = existing
            } else {
                work = SavedWork(
                    id: archived.id,
                    title: archived.title,
                    author: archived.author
                )
                context.insert(work)
            }
            apply(archived, to: work)
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
        var queueIDMap: [UUID: ReadingQueue] = [:]
        for archived in contents.manifest.readingQueues {
            let queue: ReadingQueue
            let kind = ReadingQueueKind(rawValue: archived.kindRaw) ?? .custom
            if kind == .savedForLater {
                queue = savedForLaterQueue
            } else if let existing = queuesByID[archived.id] {
                queue = existing
            } else {
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
            queue.name = kind == .savedForLater ? ReadingQueueService.savedForLaterName : archived.name
            queue.kind = kind
            queue.sortOrder = archived.sortOrder
            queue.dateCreated = archived.dateCreated
            queue.dateUpdated = archived.dateUpdated
            queueIDMap[archived.id] = queue
        }

        for archived in contents.manifest.readingQueueMemberships {
            guard let work = restoredWorksByArchivedID[archived.workID] else { continue }
            let queue = queueIDMap[archived.queueID] ?? savedForLaterQueue
            if work.queueMemberships.contains(where: { $0.queue?.id == queue.id }) {
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
            context.insert(membership)
            queue.memberships.append(membership)
            work.queueMemberships.append(membership)
            work.isQueuedForLater = true
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
            works: contents.manifest.works.count,
            bookmarks: contents.manifest.bookmarks.count,
            fonts: restoredFonts
        )
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

    private static func apply(_ archived: KudosBackupWork, to work: SavedWork) {
        work.title = archived.title
        work.author = archived.author
        work.summary = archived.summary
        work.sourceURL = archived.sourceURL
        work.dateAdded = archived.dateAdded
        work.isFavorite = archived.isFavorite
        work.isSaved = archived.isSaved
        work.isFinished = archived.isFinished
        work.isComplete = archived.isComplete
        work.rating = archived.rating
        work.language = archived.language
        work.wordCount = archived.wordCount
        work.datePublished = archived.datePublished ?? ""
        work.dateUpdated = archived.dateUpdated ?? ""
        work.chapters = archived.chapters
        work.kudos = archived.kudos
        work.comments = archived.comments
        work.hits = archived.hits
        work.workWarnings = archived.workWarnings
        work.workCategories = archived.workCategories
        work.seriesTitle = archived.seriesTitle
        work.seriesPosition = archived.seriesPosition
        work.seriesURL = archived.seriesURL
        work.ao3SeriesID = archived.ao3SeriesID
        work.lastSpineIndex = archived.lastSpineIndex
        work.lastScrollFraction = archived.lastScrollFraction
        work.lastReadDate = archived.lastReadDate
        work.workTags = archived.workTags
        work.workFandoms = archived.workFandoms
        work.workCharacters = archived.workCharacters
        work.workRelationships = archived.workRelationships
        work.workFreeforms = archived.workFreeforms
        work.workTagsFetched = archived.workTagsFetched
        work.ao3Unavailable = archived.ao3Unavailable
        work.isQueuedForLater = archived.isQueuedForLater
        work.epubPreservationStatusRaw = archived.epubPreservationStatusRaw
        work.metadataSyncStatusRaw = archived.metadataSyncStatusRaw
        work.preservedAt = archived.preservedAt
        work.lastPreservationAttemptAt = archived.lastPreservationAttemptAt
        work.lastAvailabilityCheck = archived.lastAvailabilityCheck
        work.ao3WorkID = archived.ao3WorkID ?? WorkTags.ao3WorkID(from: archived.sourceURL)
        #if canImport(ReadiumShared)
        work.readiumLocator = archived.readiumLocator ?? ""
        #endif
    }
}
