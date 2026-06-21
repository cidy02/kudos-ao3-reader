import Foundation
import SwiftData
import Testing
@testable import Kudos

@MainActor
struct KudosBackupTests {
    @Test func packageRoundTripPreservesManifestAndAssets() throws {
        let defaults = try testDefaults()
        defaults.set("sepia", forKey: "appTheme")
        defaults.set(21.0, forKey: "readerFontPt")

        let work = SavedWork(title: "Backup Work", author: "Archivist")
        work.isSaved = true
        work.wordCount = 42_000
        work.workFandoms = ["Archive Test"]
        work.tags = [Tag(name: "Comfort Read")]
        let epub = Data("epub-data".utf8)
        try epub.write(to: work.fileURL)

        let bookmark = Bookmark(
            title: "AO3",
            urlString: "https://archiveofourown.org/works/123"
        )
        let font = CustomFont(
            name: "Backup Font",
            fileName: "\(UUID().uuidString).ttf"
        )
        let fontData = Data("font-data".utf8)
        try fontData.write(to: font.fileURL)
        defer {
            try? FileManager.default.removeItem(at: work.fileURL)
            try? FileManager.default.removeItem(at: font.fileURL)
        }

        let document = try KudosBackupService.makeDocument(
            works: [work],
            bookmarks: [bookmark],
            fonts: [font],
            defaults: defaults
        )
        let backupURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("kudosbackup")
        try document.contents.fileWrapper().write(
            to: backupURL,
            options: .atomic,
            originalContentsURL: nil
        )
        defer { try? FileManager.default.removeItem(at: backupURL) }
        let decoded = try KudosBackupContents.read(from: backupURL)

        #expect(decoded.manifest.version == 1)
        #expect(decoded.manifest.works.first?.title == "Backup Work")
        #expect(decoded.manifest.works.first?.userTags == ["Comfort Read"])
        #expect(decoded.manifest.bookmarks.first?.urlString == bookmark.urlString)
        #expect(decoded.manifest.fonts.first?.fileName == font.fileName)
        #expect(decoded.manifest.settings.appTheme == "sepia")
        #expect(decoded.manifest.settings.readerFontPt == 21)
        #expect(decoded.epubFiles[work.id] == epub)
        #expect(decoded.fontFiles[font.fileName] == fontData)
    }

    @Test func restoreMergesRecordsTagsAssetsAndSettings() throws {
        let sourceDefaults = try testDefaults()
        sourceDefaults.set(false, forKey: "hideMatureContent")
        sourceDefaults.set("dark", forKey: "appTheme")

        let archivedWork = SavedWork(title: "Restored Work", author: "Writer")
        archivedWork.isFavorite = true
        archivedWork.isFinished = true
        archivedWork.wordCount = 99_001
        archivedWork.lastSpineIndex = 4
        archivedWork.tags = [Tag(name: "Re-read")]
        let epub = Data("restored-epub".utf8)
        try epub.write(to: archivedWork.fileURL)

        let archivedBookmark = Bookmark(
            title: "Restored Link",
            urlString: "https://archiveofourown.org/works/456"
        )
        defer { try? FileManager.default.removeItem(at: archivedWork.fileURL) }

        let document = try KudosBackupService.makeDocument(
            works: [archivedWork],
            bookmarks: [archivedBookmark],
            fonts: [],
            defaults: sourceDefaults
        )

        let schema = Schema([SavedWork.self, Tag.self, Bookmark.self, CustomFont.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let existing = SavedWork(
            id: archivedWork.id,
            title: "Old Title",
            author: "Old Author"
        )
        context.insert(existing)
        let targetDefaults = try testDefaults()

        let summary = try KudosBackupService.restore(
            document.contents,
            into: context,
            defaults: targetDefaults
        )

        let restoredWorks = try context.fetch(FetchDescriptor<SavedWork>())
        let restored = try #require(restoredWorks.first)
        let restoredBookmarks = try context.fetch(FetchDescriptor<Bookmark>())
        let restoredTags = try context.fetch(FetchDescriptor<Kudos.Tag>())

        #expect(summary == .init(works: 1, bookmarks: 1, fonts: 0))
        #expect(restoredWorks.count == 1)
        #expect(restored.title == "Restored Work")
        #expect(restored.author == "Writer")
        #expect(restored.isFavorite)
        #expect(restored.isFinished)
        #expect(restored.wordCount == 99_001)
        #expect(restored.lastSpineIndex == 4)
        #expect(restored.tags.map(\.name) == ["Re-read"])
        #expect(restored.hasEPUB)
        #expect(try Data(contentsOf: restored.fileURL) == epub)
        #expect(restoredBookmarks.first?.title == "Restored Link")
        #expect(restoredTags.map { $0.name } == ["Re-read"])
        #expect(targetDefaults.bool(forKey: "hideMatureContent") == false)
        #expect(targetDefaults.string(forKey: "appTheme") == "dark")

        try? FileManager.default.removeItem(at: restored.fileURL)
    }

    @Test func unsupportedBackupVersionIsRejected() throws {
        let manifest = KudosBackupManifest(
            version: 99,
            works: [],
            bookmarks: [],
            fonts: [],
            settings: .capture(defaults: try testDefaults())
        )
        let wrapper = try KudosBackupContents(manifest: manifest).fileWrapper()

        #expect(throws: KudosBackupError.self) {
            _ = try KudosBackupContents(fileWrapper: wrapper)
        }
    }

    private func testDefaults() throws -> UserDefaults {
        let name = "KudosBackupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
