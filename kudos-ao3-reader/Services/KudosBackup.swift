import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// A directory-backed document package containing a JSON manifest and assets.
    static let kudosBackup = UTType(
        filenameExtension: "kudosbackup",
        conformingTo: .package
    )!
}

struct KudosBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.kudosBackup] }

    let contents: KudosBackupContents

    init(contents: KudosBackupContents) {
        self.contents = contents
    }

    init(configuration: ReadConfiguration) throws {
        contents = try KudosBackupContents(fileWrapper: configuration.file)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
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
        guard manifest.version == KudosBackupManifest.currentVersion else {
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
    static let currentVersion = 1

    let version: Int
    let exportedAt: Date
    let works: [KudosBackupWork]
    let bookmarks: [KudosBackupBookmark]
    let fonts: [KudosBackupFont]
    let settings: KudosBackupSettings

    init(
        version: Int = currentVersion,
        exportedAt: Date = Date(),
        works: [KudosBackupWork],
        bookmarks: [KudosBackupBookmark],
        fonts: [KudosBackupFont],
        settings: KudosBackupSettings
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.works = works
        self.bookmarks = bookmarks
        self.fonts = fonts
        self.settings = settings
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
    let workWarnings: [String]
    let workCategories: [String]
    let seriesTitle: String
    let seriesPosition: Int
    let seriesURL: String
    let lastSpineIndex: Int
    let lastScrollFraction: Double
    let lastReadDate: Date?
    let workTags: [String]
    let workFandoms: [String]
    let workCharacters: [String]
    let workRelationships: [String]
    let workFreeforms: [String]
    let workTagsFetched: Bool
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
        workWarnings = work.workWarnings
        workCategories = work.workCategories
        seriesTitle = work.seriesTitle
        seriesPosition = work.seriesPosition
        seriesURL = work.seriesURL
        lastSpineIndex = work.lastSpineIndex
        lastScrollFraction = work.lastScrollFraction
        lastReadDate = work.lastReadDate
        workTags = work.workTags
        workFandoms = work.workFandoms
        workCharacters = work.workCharacters
        workRelationships = work.workRelationships
        workFreeforms = work.workFreeforms
        workTagsFetched = work.workTagsFetched
        userTags = work.tags.map(\.name).sorted()
        #if canImport(ReadiumShared)
        readiumLocator = work.readiumLocator
        #else
        readiumLocator = nil
        #endif
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
            accentColorHex: defaults.string(forKey: "accentColorHex") ?? ThemeManager.ao3Red
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
        case .unsupportedVersion(let version):
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

        let manifest = KudosBackupManifest(
            works: works.map(KudosBackupWork.init),
            bookmarks: bookmarks.map(KudosBackupBookmark.init),
            fonts: fonts.map(KudosBackupFont.init),
            settings: .capture(defaults: defaults)
        )
        return KudosBackupDocument(contents: KudosBackupContents(
            manifest: manifest,
            epubFiles: epubFiles,
            fontFiles: fontFiles
        ))
    }

    static func restore(
        _ contents: KudosBackupContents,
        into context: ModelContext,
        defaults: UserDefaults = .standard
    ) throws -> KudosBackupRestoreSummary {
        let existingWorks = try context.fetch(FetchDescriptor<SavedWork>())
        var worksByID = Dictionary(
            existingWorks.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let existingTags = try context.fetch(FetchDescriptor<Tag>())
        var tagsByName = Dictionary(
            existingTags.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for archived in contents.manifest.works {
            let work: SavedWork
            if let existing = worksByID[archived.id] {
                work = existing
            } else {
                work = SavedWork(
                    id: archived.id,
                    title: archived.title,
                    author: archived.author
                )
                context.insert(work)
                worksByID[archived.id] = work
            }
            apply(archived, to: work)

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
        work.workWarnings = archived.workWarnings
        work.workCategories = archived.workCategories
        work.seriesTitle = archived.seriesTitle
        work.seriesPosition = archived.seriesPosition
        work.seriesURL = archived.seriesURL
        work.lastSpineIndex = archived.lastSpineIndex
        work.lastScrollFraction = archived.lastScrollFraction
        work.lastReadDate = archived.lastReadDate
        work.workTags = archived.workTags
        work.workFandoms = archived.workFandoms
        work.workCharacters = archived.workCharacters
        work.workRelationships = archived.workRelationships
        work.workFreeforms = archived.workFreeforms
        work.workTagsFetched = archived.workTagsFetched
        #if canImport(ReadiumShared)
        work.readiumLocator = archived.readiumLocator ?? ""
        #endif
    }
}
