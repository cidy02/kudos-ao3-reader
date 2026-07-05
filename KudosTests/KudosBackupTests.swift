import Foundation
import SwiftData
import Testing
@testable import Kudos

// Serialized: several tests here and in FolderSyncTests/PersistenceSyncTests exercise
// PersistenceOperationGate, a process-wide static gate that's meaningfully global in
// the real app (only one instance ever runs) but can spuriously contend across
// concurrently-running test suites otherwise.
@MainActor
@Suite(.serialized)
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
            readingQueues: [],
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

        #expect(decoded.manifest.version == KudosBackupManifest.currentVersion)
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
        let olderLocalDate = Date(timeIntervalSince1970: 100)
        let newerArchiveDate = Date(timeIntervalSince1970: 200)

        let archivedWork = SavedWork(title: "Restored Work", author: "Writer")
        archivedWork.isFavorite = true
        archivedWork.isFinished = true
        archivedWork.wordCount = 99_001
        archivedWork.lastSpineIndex = 4
        archivedWork.tags = [Tag(name: "Re-read")]
        archivedWork.markProgressModified(newerArchiveDate)
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
            readingQueues: [],
            defaults: sourceDefaults
        )

        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let existing = SavedWork(
            id: archivedWork.id,
            title: "Old Title",
            author: "Old Author"
        )
        existing.markModified(olderLocalDate)
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

    @Test func backupRestoresReadingQueuesAndPreservedEPUBs() throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let sourceContainer = try ModelContainer(for: schema, configurations: [configuration])
        let sourceContext = ModelContext(sourceContainer)

        let work = SavedWork(
            title: "Queued Work",
            author: "Queue Writer",
            sourceURL: "https://archiveofourown.org/works/789"
        )
        work.hasEPUB = true
        work.ao3WorkID = 789
        sourceContext.insert(work)
        try Data("queued-epub".utf8).write(to: work.fileURL)
        let queue = ReadingQueueService.ensureSavedForLaterQueue(in: sourceContext)
        ReadingQueueService.add(work, to: queue, in: sourceContext)
        work.epubPreservationStatus = .preserved
        try sourceContext.save()

        let document = try KudosBackupService.makeDocument(
            works: [work],
            bookmarks: [],
            fonts: [],
            readingQueues: [queue],
            defaults: try testDefaults()
        )

        let targetContainer = try ModelContainer(for: schema, configurations: [configuration])
        let targetContext = ModelContext(targetContainer)
        let summary = try KudosBackupService.restore(
            document.contents,
            into: targetContext,
            defaults: try testDefaults()
        )

        let restored = try #require(try targetContext.fetch(FetchDescriptor<SavedWork>()).first)
        let restoredQueues = try targetContext.fetch(FetchDescriptor<ReadingQueue>())
        let restoredQueue = try #require(restoredQueues.first { $0.kind == .savedForLater })

        #expect(summary.works == 1)
        #expect(restored.ao3WorkID == 789)
        #expect(restored.isQueuedForLater)
        #expect(restored.isInSavedForLaterQueue)
        #expect(restored.epubPreservationStatus == .preserved)
        #expect(restoredQueue.memberships.count == 1)
        #expect(try Data(contentsOf: restored.fileURL) == Data("queued-epub".utf8))

        try? FileManager.default.removeItem(at: restored.fileURL)
    }

    @Test func restoreMergesByAO3WorkIDBeforeUUID() throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let olderLocalDate = Date(timeIntervalSince1970: 100)
        let newerArchiveDate = Date(timeIntervalSince1970: 200)

        let archivedWork = SavedWork(
            title: "Archived AO3 Work",
            author: "Writer",
            sourceURL: "https://archiveofourown.org/works/13579"
        )
        archivedWork.ao3WorkID = 13_579
        archivedWork.markModified(newerArchiveDate)
        let document = try KudosBackupService.makeDocument(
            works: [archivedWork],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: try testDefaults()
        )

        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let existing = SavedWork(
            title: "Existing AO3 Work",
            author: "Writer",
            sourceURL: "https://archiveofourown.org/works/13579?view_full_work=true"
        )
        existing.ao3WorkID = 13_579
        existing.markModified(olderLocalDate)
        context.insert(existing)

        _ = try KudosBackupService.restore(
            document.contents,
            into: context,
            defaults: try testDefaults()
        )

        let works = try context.fetch(FetchDescriptor<SavedWork>())
        let restored = try #require(works.first)
        #expect(works.count == 1)
        #expect(restored.id == existing.id)
        #expect(restored.title == "Archived AO3 Work")
    }

    @Test func restoreMergesByCanonicalAO3URLBeforeUUID() throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let olderLocalDate = Date(timeIntervalSince1970: 100)
        let newerArchiveDate = Date(timeIntervalSince1970: 200)

        let archivedWork = SavedWork(
            title: "Archived URL Work",
            author: "Writer",
            sourceURL: "https://archiveofourown.org/downloads/24680/work.epub"
        )
        archivedWork.markModified(newerArchiveDate)
        let document = try KudosBackupService.makeDocument(
            works: [archivedWork],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: try testDefaults()
        )

        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let existing = SavedWork(
            title: "Existing URL Work",
            author: "Writer",
            sourceURL: "https://archiveofourown.org/works/24680?view_full_work=true#main"
        )
        existing.markModified(olderLocalDate)
        context.insert(existing)

        _ = try KudosBackupService.restore(
            document.contents,
            into: context,
            defaults: try testDefaults()
        )

        let works = try context.fetch(FetchDescriptor<SavedWork>())
        let restored = try #require(works.first)
        #expect(works.count == 1)
        #expect(restored.id == existing.id)
        #expect(restored.title == "Archived URL Work")
    }

    @Test func restorePreservedStatusWithMissingEPUBBecomesMissingFile() throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let sourceContainer = try ModelContainer(for: schema, configurations: [configuration])
        let sourceContext = ModelContext(sourceContainer)

        let work = SavedWork(
            title: "Missing Preserved EPUB",
            author: "Writer",
            sourceURL: "https://archiveofourown.org/works/8642"
        )
        work.hasEPUB = true
        work.ao3WorkID = 8_642
        sourceContext.insert(work)
        let queue = ReadingQueueService.ensureSavedForLaterQueue(in: sourceContext)
        ReadingQueueService.add(work, to: queue, in: sourceContext)
        work.epubPreservationStatus = .preserved
        try? FileManager.default.removeItem(at: work.fileURL)
        try sourceContext.save()

        let document = try KudosBackupService.makeDocument(
            works: [work],
            bookmarks: [],
            fonts: [],
            readingQueues: [queue],
            defaults: try testDefaults()
        )

        let targetContainer = try ModelContainer(for: schema, configurations: [configuration])
        let targetContext = ModelContext(targetContainer)
        _ = try KudosBackupService.restore(
            document.contents,
            into: targetContext,
            defaults: try testDefaults()
        )

        let restored = try #require(try targetContext.fetch(FetchDescriptor<SavedWork>()).first)
        #expect(restored.isQueuedForLater)
        #expect(!restored.hasEPUB)
        #expect(restored.epubPreservationStatus == .missingFile)
    }

    @Test func restoreSkipsMembershipReferencingMissingWork() throws {
        let queueID = UUID()
        let missingWorkID = UUID()
        let membershipID = UUID()
        let manifest = """
        {
          "version": 2,
          "exportedAt": "2026-06-30T00:00:00Z",
          "works": [],
          "bookmarks": [],
          "fonts": [],
          "readingQueues": [
            {
              "id": "\(queueID.uuidString)",
              "name": "Broken Queue",
              "kindRaw": "custom",
              "sortOrder": 3,
              "dateCreated": "2026-06-30T00:00:00Z",
              "dateUpdated": "2026-06-30T00:00:00Z"
            }
          ],
          "readingQueueMemberships": [
            {
              "id": "\(membershipID.uuidString)",
              "queueID": "\(queueID.uuidString)",
              "workID": "\(missingWorkID.uuidString)",
              "queuedAt": "2026-06-30T00:00:00Z",
              "sortOrderInQueue": 0,
              "note": ""
            }
          ],
          "settings": {}
        }
        """
        let wrapper = FileWrapper(directoryWithFileWrappers: [
            "manifest.json": FileWrapper(regularFileWithContents: Data(manifest.utf8))
        ])
        let contents = try KudosBackupContents(fileWrapper: wrapper)
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        _ = try KudosBackupService.restore(contents, into: context, defaults: try testDefaults())

        #expect(try context.fetch(FetchDescriptor<SavedWork>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ReadingQueueMembership>()).isEmpty)
    }

    @Test func versionOneBackupDefaultsQueueFields() throws {
        let manifest = """
        {
          "version": 1,
          "exportedAt": "2026-06-30T00:00:00Z",
          "works": [],
          "bookmarks": [],
          "fonts": [],
          "settings": {}
        }
        """
        let wrapper = FileWrapper(directoryWithFileWrappers: [
            "manifest.json": FileWrapper(regularFileWithContents: Data(manifest.utf8))
        ])

        let contents = try KudosBackupContents(fileWrapper: wrapper)

        #expect(contents.manifest.version == 1)
        #expect(contents.manifest.readingQueues.isEmpty)
        #expect(contents.manifest.readingQueueMemberships.isEmpty)
        #expect(contents.manifest.settings.autoPreserveSmallSeriesOnSaveForLater == false)
        #expect(contents.manifest.settings.autoPreserveSeriesWorkThreshold == 5)
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
