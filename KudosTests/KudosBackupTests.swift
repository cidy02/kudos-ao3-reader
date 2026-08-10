import Foundation
import SwiftData
import Testing
@testable import Kudos

// Nested under PersistenceGateSuites (see its doc comment): these tests exercise
// PersistenceOperationGate, a process-wide static gate, so they must serialize
// against FolderSyncTests/PersistenceSyncTests/PreservedWorkTests too, not just
// within this suite.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct KudosBackupTests {
    @Test func archiveRoundTripPreservesManifestAndAssets() throws {
        let defaults = try testDefaults()
        defaults.set("sepia", forKey: "appTheme")
        defaults.set(21.0, forKey: "readerFontPt")

        let work = SavedWork(title: "Backup Work", author: "Archivist")
        work.isSaved = true
        work.wordCount = 42_000
        work.workFandoms = ["Archive Test"]
        work.tags = [Tag(name: "Comfort Read")]
        work.kudos = 890
        work.bookmarks = 56
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

        let contents = try KudosBackupService.makeContents(
            works: [work],
            bookmarks: [bookmark],
            fonts: [font],
            readingQueues: [],
            defaults: defaults
        )
        let backupURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("kudosbackup")
        try contents.zipData().write(to: backupURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: backupURL) }
        let decoded = try KudosBackupContents.read(from: backupURL)

        // The `.kudosbackup` on disk is a single regular file — a real ZIP.
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: backupURL.path, isDirectory: &isDirectory))
        #expect(!isDirectory.boolValue)
        #expect(decoded.manifest.version == KudosBackupManifest.currentVersion)
        #expect(decoded.manifest.works.first?.title == "Backup Work")
        #expect(decoded.manifest.works.first?.userTags == ["Comfort Read"])
        // AO3 stat counts survive the archive. `bookmarks` was added to
        // `KudosBackupWork` without a manifest version bump, on the basis that
        // `decodeIfPresent` keeps it compatible both ways — so it needs to
        // actually round-trip, not just decode.
        #expect(decoded.manifest.works.first?.kudos == 890)
        #expect(decoded.manifest.works.first?.bookmarks == 56)
        #expect(decoded.manifest.bookmarks.first?.urlString == bookmark.urlString)
        #expect(decoded.manifest.fonts.first?.fileName == font.fileName)
        #expect(decoded.manifest.settings.appTheme == "sepia")
        #expect(decoded.manifest.settings.readerFontPt == 21)
        #expect(decoded.epubFiles[work.id] == epub)
        #expect(decoded.fontFiles[font.fileName] == fontData)
    }

    @Test func authorIdentityPersistsLocallyWithoutChangingBackupSchema() throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self,
            ReadingAnnotation.self
        ])
        let sourceConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let sourceContainer = try ModelContainer(
            for: schema,
            configurations: [sourceConfiguration]
        )
        let sourceContext = ModelContext(sourceContainer)
        let route = try #require(AO3AuthorRoute(
            username: "Avery_Archive",
            pseud: "Avery Writes"
        ))
        let identity = AO3AuthorIdentity(route: route, displayName: "Avery Writes")
        let work = SavedWork(title: "Identity Work", author: "Avery Writes")
        work.verifiedAuthorIdentities = [identity]
        sourceContext.insert(work)
        try sourceContext.save()

        let persisted = try #require(sourceContext.fetch(FetchDescriptor<SavedWork>()).first)
        #expect(persisted.verifiedAuthorIdentities == [identity])

        let contents = try KudosBackupService.makeContents(
            works: [persisted],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: try testDefaults()
        )
        let targetConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let targetContainer = try ModelContainer(
            for: schema,
            configurations: [targetConfiguration]
        )
        let targetContext = ModelContext(targetContainer)

        _ = try KudosBackupService.restore(
            contents,
            into: targetContext,
            defaults: try testDefaults()
        )

        let restored = try #require(targetContext.fetch(FetchDescriptor<SavedWork>()).first)
        #expect(restored.author == "Avery Writes")
        #expect(restored.verifiedAuthorIdentities.isEmpty)
        #expect(contents.manifest.version == KudosBackupManifest.currentVersion)
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
        let epub = try Data(contentsOf: EPUBTests.sampleEPUB)
        try epub.write(to: archivedWork.fileURL)

        let archivedBookmark = Bookmark(
            title: "Restored Link",
            urlString: "https://archiveofourown.org/works/456"
        )
        defer { try? FileManager.default.removeItem(at: archivedWork.fileURL) }

        let contents = try KudosBackupService.makeContents(
            works: [archivedWork],
            bookmarks: [archivedBookmark],
            fonts: [],
            readingQueues: [],
            defaults: sourceDefaults
        )

        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self,
            ReadingAnnotation.self
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
            contents,
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
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self,
            ReadingAnnotation.self
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
        let queuedEPUB = try Data(contentsOf: EPUBTests.sampleEPUB)
        try queuedEPUB.write(to: work.fileURL)
        let queue = ReadingQueueService.ensureSavedForLaterQueue(in: sourceContext)
        ReadingQueueService.add(work, to: queue, in: sourceContext)
        work.epubPreservationStatus = .preserved
        try sourceContext.save()

        let contents = try KudosBackupService.makeContents(
            works: [work],
            bookmarks: [],
            fonts: [],
            readingQueues: [queue],
            defaults: try testDefaults()
        )

        let targetContainer = try ModelContainer(for: schema, configurations: [configuration])
        let targetContext = ModelContext(targetContainer)
        let summary = try KudosBackupService.restore(
            contents,
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
        #expect(try Data(contentsOf: restored.fileURL) == queuedEPUB)

        try? FileManager.default.removeItem(at: restored.fileURL)
    }

    @Test func restoreMergesByAO3WorkIDBeforeUUID() throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self,
            ReadingAnnotation.self
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
        let contents = try KudosBackupService.makeContents(
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
            contents,
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
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self,
            ReadingAnnotation.self
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
        let contents = try KudosBackupService.makeContents(
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
            contents,
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
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self,
            ReadingAnnotation.self
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

        let contents = try KudosBackupService.makeContents(
            works: [work],
            bookmarks: [],
            fonts: [],
            readingQueues: [queue],
            defaults: try testDefaults()
        )

        let targetContainer = try ModelContainer(for: schema, configurations: [configuration])
        let targetContext = ModelContext(targetContainer)
        _ = try KudosBackupService.restore(
            contents,
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
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self,
            ReadingAnnotation.self
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
          "works": [
            { "id": "\(UUID().uuidString)", "title": "Old Work", "author": "Someone", "kudos": 890 }
          ],
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
        // An archive written before `bookmarks` existed must still decode, with
        // the field absent rather than defaulted-over-a-real-value. This is the
        // half of the no-version-bump argument that the round-trip test can't
        // reach, since the current writer always emits the key.
        #expect(contents.manifest.works.first?.kudos == 890)
        #expect(contents.manifest.works.first?.bookmarks == 0)
    }

    @Test func unsupportedBackupVersionIsRejected() throws {
        let manifest = KudosBackupManifest(
            version: 99,
            works: [],
            bookmarks: [],
            fonts: [],
            settings: .capture(defaults: try testDefaults())
        )
        let zipData = try KudosBackupContents(manifest: manifest).zipData()

        #expect(throws: KudosBackupError.self) {
            _ = try KudosBackupContents(zipData: zipData)
        }
    }

    /// The current writer produces a single ZIP file, but backups exported by
    /// pre-archive versions are directory packages — those must remain
    /// importable forever via the same `read(from:)` entry point.
    @Test func legacyDirectoryPackageBackupRemainsReadable() throws {
        let defaults = try testDefaults()
        let work = SavedWork(title: "Legacy Work", author: "Archivist")
        let epub = Data("legacy-epub-data".utf8)
        try epub.write(to: work.fileURL)
        defer { try? FileManager.default.removeItem(at: work.fileURL) }

        let contents = try KudosBackupService.makeContents(
            works: [work],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: defaults
        )

        // Write the old on-disk shape by hand — production code no longer can.
        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("kudosbackup")
        let wrapper = FileWrapper(directoryWithFileWrappers: [
            "manifest.json": FileWrapper(regularFileWithContents: try contents.manifestData()),
            "Works": FileWrapper(directoryWithFileWrappers: [
                "\(work.id.uuidString).epub": FileWrapper(regularFileWithContents: epub)
            ]),
            "Fonts": FileWrapper(directoryWithFileWrappers: [:])
        ])
        try wrapper.write(to: packageURL, options: .atomic, originalContentsURL: nil)
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let decoded = try KudosBackupContents.read(from: packageURL)
        #expect(decoded.manifest.works.first?.title == "Legacy Work")
        #expect(decoded.epubFiles[work.id] == epub)
    }

    /// A truncated archive — the partially-written state an interrupted copy
    /// or crash could leave behind — must never decode as a valid backup.
    @Test func truncatedArchiveIsRejectedAsInvalid() throws {
        let manifest = KudosBackupManifest(
            works: [],
            bookmarks: [],
            fonts: [],
            settings: .capture(defaults: try testDefaults())
        )
        let zipData = try KudosBackupContents(manifest: manifest).zipData()

        let truncated = zipData.prefix(zipData.count / 2)
        #expect(throws: KudosBackupError.self) {
            _ = try KudosBackupContents(zipData: Data(truncated))
        }
    }

    /// The streaming exporter (makeExportPlan + writeArchive) must produce an
    /// archive equivalent to the in-memory path: same entry names in the same
    /// order, identical asset bytes, and a manifest differing only in its
    /// `exportedAt` timestamp. Also covers the lenient-asset rule — a work
    /// whose EPUB file is missing is skipped without failing the export.
    @Test func streamedExportMatchesTheInMemoryArchive() throws {
        let defaults = try testDefaults()
        let work = SavedWork(title: "Streamed Work", author: "Archivist")
        work.hasEPUB = true
        let epub = Data("streamed-epub-data".utf8)
        try epub.write(to: work.fileURL)
        let ghost = SavedWork(title: "Ghost Work", author: "Archivist")
        ghost.hasEPUB = true // claims an EPUB, but no file exists on disk
        defer { try? FileManager.default.removeItem(at: work.fileURL) }

        let inMemory = try KudosBackupService.makeContents(
            works: [work, ghost],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: defaults
        ).zipData()

        let plan = try KudosBackupService.makeExportPlan(
            works: [work, ghost],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: defaults
        )
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("kudosbackup")
        defer { try? FileManager.default.removeItem(at: destination) }
        try KudosBackupService.writeArchive(plan, to: destination)

        let streamed = try Data(contentsOf: destination)
        let inMemoryZip = try MiniZip(data: inMemory, limits: .backup)
        let streamedZip = try MiniZip(data: streamed, limits: .backup)
        #expect(streamedZip.names == inMemoryZip.names)
        for name in streamedZip.names where name != "manifest.json" {
            #expect(streamedZip.data(named: name) == inMemoryZip.data(named: name))
        }

        // Same decoded manifest contents (the two exports differ only in
        // their independently-captured `exportedAt` timestamps).
        let decoded = try KudosBackupContents.read(from: destination)
        let reference = try KudosBackupContents(zipData: inMemory)
        #expect(decoded.manifest.works == reference.manifest.works)
        #expect(decoded.manifest.settings == reference.manifest.settings)
        #expect(decoded.epubFiles[work.id] == epub)
        #expect(decoded.epubFiles[ghost.id] == nil)
    }

    /// The streaming writer itself has no ceilings (ZIP64), so `writeArchive`
    /// must refuse — before writing anything — any export the reader's
    /// `.backup` limits would reject on import: entry count, per-file size,
    /// and total size all stay symmetric between export and restore.
    @Test func exportRefusesArchivesTheReaderWouldReject() throws {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExportCaps-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let assetURL = staging.appendingPathComponent("asset.epub")
        try Data(count: 100).write(to: assetURL)
        let plan = KudosBackupExportPlan(
            manifestData: Data(#"{"version":7}"#.utf8),
            assets: [.init(entryName: "Works/asset.epub", fileURL: assetURL)]
        )
        let destination = staging.appendingPathComponent("out.kudosbackup")

        func limits(entries: Int = 10, single: Int = 1_000, total: Int = 1_000) -> MiniZip.Limits {
            MiniZip.Limits(
                maxEntryCount: entries,
                maxSingleEntryUncompressedSize: single,
                maxTotalUncompressedSize: total,
                maxCompressionRatio: 1100
            )
        }

        // Manifest + 1 asset = 2 entries > 1; the 100-byte asset > 50; and
        // 13-byte manifest + 100-byte asset > 60.
        #expect(throws: KudosBackupExportError.self) {
            try KudosBackupService.writeArchive(plan, to: destination, limits: limits(entries: 1))
        }
        #expect(throws: KudosBackupExportError.self) {
            try KudosBackupService.writeArchive(plan, to: destination, limits: limits(single: 50))
        }
        #expect(throws: KudosBackupExportError.self) {
            try KudosBackupService.writeArchive(plan, to: destination, limits: limits(total: 60))
        }
        // Preflight failures never create the destination file at all.
        #expect(!FileManager.default.fileExists(atPath: destination.path))

        // The same plan passes under the real `.backup` limits, and the
        // resulting archive parses under the same reader profile.
        try KudosBackupService.writeArchive(plan, to: destination)
        let written = try MiniZip(data: Data(contentsOf: destination), limits: .backup)
        #expect(written.names == ["manifest.json", "Works/asset.epub"])
    }

    // MARK: - A2-F1: stale-archive tag-merge safety

    /// A2-F1 regression: a stale archive (older than the local tag) must never remove
    /// a tag the user added since. There's no per-tag tombstone, so the only safe
    /// policy is to never infer removal from absence.
    @Test func staleArchiveWithoutTagsDoesNotRemoveNewerLocalTag() throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self,
            ReadingAnnotation.self
        ])
        let olderArchiveDate = Date(timeIntervalSince1970: 100)
        let newerLocalDate = Date(timeIntervalSince1970: 200)
        let workID = UUID()

        let sourceConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let sourceContainer = try ModelContainer(for: schema, configurations: [sourceConfiguration])
        let sourceContext = ModelContext(sourceContainer)
        let staleWork = SavedWork(id: workID, title: "Tagged Work", author: "Writer")
        staleWork.markModified(olderArchiveDate)
        sourceContext.insert(staleWork)
        try sourceContext.save()
        let staleContents = try KudosBackupService.makeContents(
            works: [staleWork],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: try testDefaults()
        )

        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let localWork = SavedWork(id: workID, title: "Tagged Work", author: "Writer")
        localWork.tags = [Tag(name: "fluff")]
        localWork.markModified(newerLocalDate)
        context.insert(localWork)
        try context.save()

        _ = try KudosBackupService.restore(
            staleContents,
            into: context,
            defaults: try testDefaults()
        )

        let restored = try #require(try context.fetch(FetchDescriptor<SavedWork>()).first)
        #expect(restored.tags.map(\.name) == ["fluff"])
    }

    /// A2-F1: restoring the same archive twice must not duplicate the tags it adds.
    @Test func repeatedRestoreOfArchiveTagsIsIdempotent() throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self,
            ReadingAnnotation.self
        ])
        let archivedWork = SavedWork(title: "Idempotent Work", author: "Writer")
        archivedWork.tags = [Tag(name: "found family")]
        let contents = try KudosBackupService.makeContents(
            works: [archivedWork],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: try testDefaults()
        )

        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        _ = try KudosBackupService.restore(contents, into: context, defaults: try testDefaults())
        _ = try KudosBackupService.restore(contents, into: context, defaults: try testDefaults())

        let restored = try #require(try context.fetch(FetchDescriptor<SavedWork>()).first)
        #expect(restored.tags.map(\.name) == ["found family"])
        #expect(try context.fetch(FetchDescriptor<Kudos.Tag>()).count == 1)
    }

    // MARK: - A5-F3: backup EPUB validation before replacement

    /// A5-F3 regression: corrupt/untrusted incoming EPUB bytes must be preflighted
    /// through the hardened validator and skipped without touching the existing
    /// valid file, `hasEPUB`, or preservation state.
    @Test func invalidBackupEPUBLeavesValidLocalEPUBUnchanged() throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self,
            ReadingAnnotation.self
        ])
        let workID = UUID()
        let olderArchiveDate = Date(timeIntervalSince1970: 100)
        let newerLocalDate = Date(timeIntervalSince1970: 200)

        let sourceWork = SavedWork(id: workID, title: "Corrupted Restore", author: "Writer")
        sourceWork.markModified(olderArchiveDate)
        let baseContents = try KudosBackupService.makeContents(
            works: [sourceWork],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: try testDefaults()
        )
        let corruptContents = KudosBackupContents(
            manifest: baseContents.manifest,
            epubFiles: [workID: Data("not-an-epub".utf8)],
            fontFiles: [:]
        )

        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let localWork = SavedWork(id: workID, title: "Corrupted Restore", author: "Writer")
        localWork.hasEPUB = true
        localWork.markModified(newerLocalDate)
        context.insert(localWork)
        let validEPUB = try Data(contentsOf: EPUBTests.sampleEPUB)
        try validEPUB.write(to: localWork.fileURL)
        // Preservation status is only meaningful alongside a queue membership
        // (ReadingQueueService.normalize resets un-queued works to .notPreserved,
        // called as part of every restore) — queue it (after the file exists, so
        // normalize's own file check doesn't downgrade it) so this assertion
        // reflects a real, stable state rather than one the app's own
        // normalization pass would immediately correct regardless of the
        // backup-validation fix under test.
        let queue = ReadingQueueService.ensureSavedForLaterQueue(in: context)
        ReadingQueueService.add(localWork, to: queue, in: context)
        localWork.epubPreservationStatus = .preserved
        try context.save()
        defer { try? FileManager.default.removeItem(at: localWork.fileURL) }

        let summary = try KudosBackupService.restore(
            corruptContents,
            into: context,
            defaults: try testDefaults()
        )

        let restored = try #require(try context.fetch(FetchDescriptor<SavedWork>()).first)
        #expect(restored.hasEPUB)
        #expect(restored.epubPreservationStatus == .preserved)
        #expect(try Data(contentsOf: restored.fileURL) == validEPUB)
        #expect(summary.skippedInvalidEPUBs == 1)
    }

    /// Validator/extractor-asymmetry regression: a backup EPUB can be
    /// structurally valid — readable container/OPF/spine — while carrying one
    /// extra entry, unsafely named, that the OPF never references.
    /// `EPUBDocument.inspectPackage` (the A5-F3 preflight) only reads
    /// container/OPF/spine by exact name, so if entry-name safety were only
    /// checked during real extraction/`unzip`, this archive would pass
    /// preflight, overwrite the valid local EPUB, and only fail later when the
    /// reader actually opened it — after the original, possibly
    /// non-redownloadable EPUB was already gone. `MiniZip` now validates every
    /// entry's name while parsing the central directory (not just at `unzip`
    /// time), so this whole archive is rejected at preflight and the local
    /// EPUB is left untouched.
    @Test func backupEPUBWithUnreferencedHostileEntryLeavesValidLocalEPUBUnchanged() throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self,
            ReadingAnnotation.self
        ])
        let workID = UUID()

        let sourceWork = SavedWork(id: workID, title: "Hostile Blob", author: "Writer")
        let baseContents = try KudosBackupService.makeContents(
            works: [sourceWork],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: try testDefaults()
        )
        let hostileEPUB = HostileZipFixture.build(
            HostileZipFixture.minimalValidEPUBEntries + [
                HostileZipFixture.Entry(name: "../evil.txt", payload: Data("hostile".utf8))
            ]
        )
        let hostileContents = KudosBackupContents(
            manifest: baseContents.manifest,
            epubFiles: [workID: hostileEPUB],
            fontFiles: [:]
        )

        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let localWork = SavedWork(id: workID, title: "Hostile Blob", author: "Writer")
        localWork.hasEPUB = true
        context.insert(localWork)
        let validEPUB = try Data(contentsOf: EPUBTests.sampleEPUB)
        try validEPUB.write(to: localWork.fileURL)
        try context.save()
        defer { try? FileManager.default.removeItem(at: localWork.fileURL) }

        let summary = try KudosBackupService.restore(
            hostileContents,
            into: context,
            defaults: try testDefaults()
        )

        let restored = try #require(try context.fetch(FetchDescriptor<SavedWork>()).first)
        #expect(restored.hasEPUB)
        #expect(try Data(contentsOf: restored.fileURL) == validEPUB)
        #expect(summary.skippedInvalidEPUBs == 1)
    }

    /// A5-F3: a tombstone-suppressed (explicitly deleted) work must never write its
    /// archived EPUB blob to disk, even when the archive carries valid bytes.
    @Test func tombstoneSuppressedWorkDoesNotWriteEPUBBlob() throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self,
            ReadingAnnotation.self
        ])
        let workID = UUID()
        let olderArchiveDate = Date(timeIntervalSince1970: 100)
        let deletionDate = Date(timeIntervalSince1970: 200)
        // No real bytes are ever written to `workID`'s on-disk path during setup
        // (the archive's EPUB is injected directly into the manifest below), so
        // the "never written" assertion at the end only reflects what restore()
        // itself did — not test setup.
        let staleWork = SavedWork(id: workID, title: "Deleted Work", author: "Writer")
        staleWork.markModified(olderArchiveDate)
        let baseContents = try KudosBackupService.makeContents(
            works: [staleWork],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: try testDefaults()
        )
        let staleContents = KudosBackupContents(
            manifest: baseContents.manifest,
            epubFiles: [workID: try Data(contentsOf: EPUBTests.sampleEPUB)],
            fontFiles: [:]
        )

        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.insert(SyncTombstone(
            recordID: workID,
            recordType: .savedWork,
            createdAt: deletionDate
        ))
        try context.save()

        _ = try KudosBackupService.restore(
            staleContents,
            into: context,
            defaults: try testDefaults()
        )

        #expect(try context.fetch(FetchDescriptor<SavedWork>()).isEmpty)
        let neverWrittenPath = SavedWork(id: workID, title: "x", author: "y").fileURL.path
        #expect(!FileManager.default.fileExists(atPath: neverWrittenPath))
    }

    @Test func collectionDescriptionAndSortOrderSurviveExportImportRoundTrip() throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self, ReadingAnnotation.self
        ])
        let collectionID = UUID(uuidString: "bbbbbbbb-cccc-4ddd-8eee-ffffffffffff")!
        let dateAdded = Date(timeIntervalSince1970: 1_719_403_200) // 2024-06-26T12:00:00Z

        let sourceConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let sourceContainer = try ModelContainer(for: schema, configurations: [sourceConfiguration])
        let sourceContext = ModelContext(sourceContainer)
        let collection = WorkCollection(name: "Comfort shelf")
        collection.id = collectionID
        collection.dateAdded = dateAdded
        collection.createdAt = dateAdded
        collection.lastModifiedAt = dateAdded
        // Passthrough fields — iOS never edits these in UI, but must keep them.
        collection.collectionDescription = "Android-written shelf notes"
        collection.sortOrder = 7
        sourceContext.insert(collection)
        try sourceContext.save()

        let contents = try KudosBackupService.makeContents(
            works: [],
            bookmarks: [],
            fonts: [],
            collections: [collection],
            readingQueues: [],
            defaults: try testDefaults()
        )
        #expect(contents.manifest.collections.count == 1)
        #expect(contents.manifest.collections.first?.id == collectionID)
        #expect(contents.manifest.collections.first?.description == "Android-written shelf notes")
        #expect(contents.manifest.collections.first?.sortOrder == 7)

        // Wire keys match Android exactly (property names on KudosBackupCollection).
        let manifestJSON = try JSONSerialization.jsonObject(
            with: contents.manifestData()
        ) as? [String: Any]
        let collectionsArray = try #require(manifestJSON?["collections"] as? [[String: Any]])
        let firstJSON = try #require(collectionsArray.first)
        #expect(firstJSON["description"] as? String == "Android-written shelf notes")
        #expect(firstJSON["sortOrder"] as? Int == 7)

        let targetConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let targetContainer = try ModelContainer(for: schema, configurations: [targetConfiguration])
        let targetContext = ModelContext(targetContainer)
        _ = try KudosBackupService.restore(
            contents,
            into: targetContext,
            defaults: try testDefaults()
        )
        let restored = try #require(
            try targetContext.fetch(FetchDescriptor<WorkCollection>()).first
        )
        #expect(restored.id == collectionID)
        #expect(restored.name == "Comfort shelf")
        #expect(restored.collectionDescription == "Android-written shelf notes")
        #expect(restored.sortOrder == 7)

        // Re-export must keep the values (not collapse them to nil/"").
        let reexported = try KudosBackupService.makeContents(
            works: [],
            bookmarks: [],
            fonts: [],
            collections: [restored],
            readingQueues: [],
            defaults: try testDefaults()
        )
        #expect(reexported.manifest.collections.first?.description == "Android-written shelf notes")
        #expect(reexported.manifest.collections.first?.sortOrder == 7)
    }

    @Test func collectionWithoutDescriptionOrSortOrderKeysStillDecodes() throws {
        // Backward compat: pre-passthrough iOS archives and any writer that omits
        // the optional keys must still load. Android BackupJson uses
        // `explicitNulls = false`, so a null description is also absent on the wire.
        let minimal = """
        {
          "version": 8,
          "exportedAt": "2026-06-26T12:00:00Z",
          "works": [],
          "bookmarks": [],
          "fonts": [],
          "collections": [
            {
              "id": "cccccccc-dddd-4eee-8fff-000000000001",
              "name": "No extras",
              "dateAdded": "2026-06-26T12:00:00Z",
              "workIDs": []
            }
          ],
          "settings": {
            "readerFontID": "system",
            "readerMode": "scroll",
            "readerTwoPage": false,
            "readerCustomize": false,
            "readerBoldText": false,
            "readerFontPt": 18,
            "readerLineHeight": 1.65,
            "readerLetterSpacing": 0,
            "readerWordSpacing": 0,
            "readerMargin": 28,
            "readerJustify": false,
            "confirmBeforeDelete": true,
            "hideMatureContent": true,
            "matureContentMode": "obscure",
            "requireBiometricToReveal": false,
            "appTheme": "light",
            "readerTheme": "light",
            "matchAppReaderTheme": true,
            "accentColorHex": "#990000",
            "autoPreserveSmallSeriesOnSaveForLater": false,
            "autoPreserveSeriesWorkThreshold": 5
          }
        }
        """
        let manifest = try decodeManifestJSON(minimal)
        let collection = try #require(manifest.collections.first)
        #expect(collection.name == "No extras")
        #expect(collection.description == nil)
        #expect(collection.sortOrder == nil)

        // Re-export path must not invent "" for a missing description.
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self, ReadingAnnotation.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let wrapper = FileWrapper(directoryWithFileWrappers: [
            "manifest.json": FileWrapper(regularFileWithContents: Data(minimal.utf8))
        ])
        let contents = try KudosBackupContents(fileWrapper: wrapper)
        _ = try KudosBackupService.restore(contents, into: context, defaults: try testDefaults())
        let restored = try #require(try context.fetch(FetchDescriptor<WorkCollection>()).first)
        #expect(restored.collectionDescription == nil)
        #expect(restored.sortOrder == nil)

        let reexported = try KudosBackupService.makeContents(
            works: [],
            bookmarks: [],
            fonts: [],
            collections: [restored],
            readingQueues: [],
            defaults: try testDefaults()
        )
        #expect(reexported.manifest.collections.first?.description == nil)
        #expect(reexported.manifest.collections.first?.sortOrder == nil)
        let reexportJSON = try JSONSerialization.jsonObject(
            with: reexported.manifestData()
        ) as? [String: Any]
        let reexportCollections = try #require(reexportJSON?["collections"] as? [[String: Any]])
        let reexportFirst = try #require(reexportCollections.first)
        // encodeIfPresent + Android explicitNulls=false: absent, not "".
        #expect(reexportFirst["description"] == nil)
        #expect(reexportFirst["sortOrder"] == nil)
        #expect((reexportFirst["description"] as? String) != "")
    }

    @Test func androidCollectionJSONShapeDecodesAndReexportsUnchanged() throws {
        // Hand-written from Kotlin `BackupCollection` — not produced by our own
        // encoder — so this proves cross-platform decode. Contract
        // (BackupManifest.kt ~114-127):
        //   id: String, name: String, dateAdded: String,
        //   workIDs: List<String> = emptyList(),
        //   description: String? = null, sortOrder: Int? = null,
        //   createdAt/lastModifiedAt/deletedAt/isDeleted/
        //   permanentDeletionScheduledAt/syncStatusRaw: optional.
        let androidManifest = """
        {
          "version": 8,
          "exportedAt": "2026-06-26T12:00:00Z",
          "works": [],
          "bookmarks": [],
          "fonts": [],
          "collections": [
            {
              "id": "11111111-2222-4333-8444-555555555555",
              "name": "Android shelf",
              "dateAdded": "2026-06-26T12:00:00Z",
              "workIDs": [],
              "description": "Notes from the Android library",
              "sortOrder": 3,
              "createdAt": "2026-06-26T12:00:00Z",
              "lastModifiedAt": "2026-06-26T13:00:00Z",
              "deletedAt": null,
              "isDeleted": false,
              "permanentDeletionScheduledAt": null,
              "syncStatusRaw": "localOnly"
            },
            {
              "id": "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
              "name": "Null description shelf",
              "dateAdded": "2026-06-26T12:30:00Z",
              "workIDs": [],
              "description": null,
              "sortOrder": null
            }
          ],
          "settings": {
            "readerFontID": "system",
            "readerMode": "scroll",
            "readerTwoPage": false,
            "readerCustomize": false,
            "readerBoldText": false,
            "readerFontPt": 18,
            "readerLineHeight": 1.65,
            "readerLetterSpacing": 0,
            "readerWordSpacing": 0,
            "readerMargin": 28,
            "readerJustify": false,
            "confirmBeforeDelete": true,
            "hideMatureContent": true,
            "matureContentMode": "obscure",
            "requireBiometricToReveal": false,
            "appTheme": "light",
            "readerTheme": "light",
            "matchAppReaderTheme": true,
            "accentColorHex": "#990000",
            "autoPreserveSmallSeriesOnSaveForLater": false,
            "autoPreserveSeriesWorkThreshold": 5
          }
        }
        """
        let manifest = try decodeManifestJSON(androidManifest)
        #expect(manifest.collections.count == 2)

        let first = try #require(manifest.collections.first)
        #expect(first.id == UUID(uuidString: "11111111-2222-4333-8444-555555555555"))
        #expect(first.name == "Android shelf")
        #expect(first.description == "Notes from the Android library")
        #expect(first.sortOrder == 3)

        let second = try #require(manifest.collections.last)
        #expect(second.name == "Null description shelf")
        #expect(second.description == nil)
        #expect(second.sortOrder == nil)

        // Restore into a store, re-export, and confirm values (and nulls) survive.
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self, ReadingAnnotation.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let wrapper = FileWrapper(directoryWithFileWrappers: [
            "manifest.json": FileWrapper(regularFileWithContents: Data(androidManifest.utf8))
        ])
        let contents = try KudosBackupContents(fileWrapper: wrapper)
        _ = try KudosBackupService.restore(contents, into: context, defaults: try testDefaults())

        let restored = try context.fetch(FetchDescriptor<WorkCollection>())
            .sorted { $0.name < $1.name }
        #expect(restored.count == 2)
        let androidShelf = try #require(restored.first { $0.name == "Android shelf" })
        #expect(androidShelf.collectionDescription == "Notes from the Android library")
        #expect(androidShelf.sortOrder == 3)
        let nullShelf = try #require(restored.first { $0.name == "Null description shelf" })
        #expect(nullShelf.collectionDescription == nil)
        #expect(nullShelf.sortOrder == nil)

        let reexported = try KudosBackupService.makeContents(
            works: [],
            bookmarks: [],
            fonts: [],
            collections: restored,
            readingQueues: [],
            defaults: try testDefaults()
        )
        let byName = Dictionary(
            uniqueKeysWithValues: reexported.manifest.collections.map { ($0.name, $0) }
        )
        #expect(byName["Android shelf"]?.description == "Notes from the Android library")
        #expect(byName["Android shelf"]?.sortOrder == 3)
        #expect(byName["Null description shelf"]?.description == nil)
        #expect(byName["Null description shelf"]?.sortOrder == nil)

        let reexportJSON = try JSONSerialization.jsonObject(
            with: reexported.manifestData()
        ) as? [String: Any]
        let reexportCollections = try #require(reexportJSON?["collections"] as? [[String: Any]])
        let nullJSON = try #require(
            reexportCollections.first { ($0["name"] as? String) == "Null description shelf" }
        )
        #expect(nullJSON["description"] == nil)
        #expect(nullJSON["sortOrder"] == nil)
    }

    @Test func savedSearchSurvivesExportImportRoundTrip() throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self, ReadingAnnotation.self
        ])
        let searchID = UUID(uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")!
        let dateAdded = Date(timeIntervalSince1970: 1_719_403_200) // 2024-06-26T12:00:00Z
        var filters = AO3SearchFilters()
        filters.query = "hurt/comfort"
        filters.fandom = "The Untamed"
        filters.rating = .teen
        filters.completion = .complete
        filters.wordsFrom = "1000"
        filters.language = try #require(AO3SearchFilters.Language.allCases.first { $0.id == "en" })
        filters.sort = .kudos

        let sourceConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let sourceContainer = try ModelContainer(for: schema, configurations: [sourceConfiguration])
        let sourceContext = ModelContext(sourceContainer)
        let saved = SavedSearch(name: "Comfort reads", filters: filters)
        saved.id = searchID
        saved.dateAdded = dateAdded
        sourceContext.insert(saved)
        try sourceContext.save()

        let contents = try KudosBackupService.makeContents(
            works: [],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            savedSearches: [saved],
            defaults: try testDefaults()
        )
        #expect(contents.manifest.savedSearches.count == 1)
        #expect(contents.manifest.savedSearches.first?.id == searchID)
        #expect(contents.manifest.savedSearches.first?.name == "Comfort reads")
        #expect(contents.manifest.savedSearches.first?.dateAdded == dateAdded)
        #expect(contents.manifest.savedSearches.first?.filters.query == "hurt/comfort")
        #expect(contents.manifest.savedSearches.first?.filters.fandom == "The Untamed")
        #expect(contents.manifest.savedSearches.first?.filters.rating == .teen)
        #expect(contents.manifest.savedSearches.first?.filters.completion == .complete)
        #expect(contents.manifest.savedSearches.first?.filters.wordsFrom == "1000")
        #expect(contents.manifest.savedSearches.first?.filters.language.id == "en")
        #expect(contents.manifest.savedSearches.first?.filters.sort == .kudos)

        // filters must encode as a nested JSON *object*, not a string (Android
        // `BackupSavedSearch.filters: JsonObject`).
        let manifestJSON = try JSONSerialization.jsonObject(
            with: contents.manifestData()
        ) as? [String: Any]
        let savedArray = try #require(manifestJSON?["savedSearches"] as? [[String: Any]])
        let first = try #require(savedArray.first)
        #expect(first["filters"] is [String: Any])
        #expect(!(first["filters"] is String))

        let targetConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let targetContainer = try ModelContainer(for: schema, configurations: [targetConfiguration])
        let targetContext = ModelContext(targetContainer)
        _ = try KudosBackupService.restore(
            contents,
            into: targetContext,
            defaults: try testDefaults()
        )
        let restored = try #require(
            try targetContext.fetch(FetchDescriptor<SavedSearch>()).first
        )
        #expect(restored.id == searchID)
        #expect(restored.name == "Comfort reads")
        #expect(restored.dateAdded == dateAdded)
        #expect(restored.filters.query == "hurt/comfort")
        #expect(restored.filters.fandom == "The Untamed")
        #expect(restored.filters.rating == .teen)
        #expect(restored.filters.completion == .complete)
        #expect(restored.filters.wordsFrom == "1000")
        #expect(restored.filters.language.id == "en")
        #expect(restored.filters.sort == .kudos)
    }

    @Test func manifestWithoutSavedSearchesKeyStillDecodes() throws {
        // Backward compat: v1–v8 archives that predate (or Android builds that
        // omit) the key must not fail to decode.
        let minimal = """
        {
          "version": 8,
          "exportedAt": "2026-06-26T12:00:00Z",
          "works": [],
          "bookmarks": [],
          "fonts": [],
          "settings": {
            "readerFontID": "system",
            "readerMode": "scroll",
            "readerTwoPage": false,
            "readerCustomize": false,
            "readerBoldText": false,
            "readerFontPt": 18,
            "readerLineHeight": 1.65,
            "readerLetterSpacing": 0,
            "readerWordSpacing": 0,
            "readerMargin": 28,
            "readerJustify": false,
            "confirmBeforeDelete": true,
            "hideMatureContent": true,
            "matureContentMode": "obscure",
            "requireBiometricToReveal": false,
            "appTheme": "light",
            "readerTheme": "light",
            "matchAppReaderTheme": true,
            "accentColorHex": "#990000",
            "autoPreserveSmallSeriesOnSaveForLater": false,
            "autoPreserveSeriesWorkThreshold": 5
          }
        }
        """
        let manifest = try decodeManifestJSON(minimal)
        #expect(manifest.savedSearches.isEmpty)
    }

    @Test func androidSavedSearchJSONShapeDecodes() throws {
        // Hand-written from Kotlin `BackupSavedSearch` — not produced by our
        // own encoder — so this actually proves cross-platform decode.
        // Android: id = UUID string (lowercase), dateAdded = ISO-8601 instant,
        // filters = JsonObject (nested object, may be empty or a partial DTO).
        let androidManifest = """
        {
          "version": 8,
          "exportedAt": "2026-06-26T12:00:00Z",
          "works": [],
          "bookmarks": [],
          "fonts": [],
          "savedSearches": [
            {
              "id": "11111111-2222-4333-8444-555555555555",
              "name": "Android comfort",
              "dateAdded": "2026-06-26T12:00:00Z",
              "filters": {
                "query": "found family",
                "fandom": "Good Omens",
                "characters": "",
                "relationships": "",
                "additionalTags": "",
                "excludedFandoms": "",
                "excludedCharacters": "",
                "excludedRelationships": "",
                "excludedAdditionalTags": "",
                "rating": "teen",
                "ratingMatch": "exact",
                "includeNotRated": true,
                "warnings": [],
                "excludedWarnings": [],
                "categories": ["mm"],
                "excludedCategories": [],
                "crossover": "any",
                "completion": "complete",
                "wordsFrom": "5000",
                "wordsTo": "",
                "updated": "any",
                "language": "en",
                "sort": "kudos"
              }
            },
            {
              "id": "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
              "name": "Empty filters",
              "dateAdded": "2026-06-26T13:30:00.123Z",
              "filters": {}
            }
          ],
          "settings": {
            "readerFontID": "system",
            "readerMode": "scroll",
            "readerTwoPage": false,
            "readerCustomize": false,
            "readerBoldText": false,
            "readerFontPt": 18,
            "readerLineHeight": 1.65,
            "readerLetterSpacing": 0,
            "readerWordSpacing": 0,
            "readerMargin": 28,
            "readerJustify": false,
            "confirmBeforeDelete": true,
            "hideMatureContent": true,
            "matureContentMode": "obscure",
            "requireBiometricToReveal": false,
            "appTheme": "light",
            "readerTheme": "light",
            "matchAppReaderTheme": true,
            "accentColorHex": "#990000",
            "autoPreserveSmallSeriesOnSaveForLater": false,
            "autoPreserveSeriesWorkThreshold": 5
          }
        }
        """
        let manifest = try decodeManifestJSON(androidManifest)
        #expect(manifest.savedSearches.count == 2)

        let first = try #require(manifest.savedSearches.first)
        #expect(first.id == UUID(uuidString: "11111111-2222-4333-8444-555555555555"))
        #expect(first.name == "Android comfort")
        #expect(first.filters.query == "found family")
        #expect(first.filters.fandom == "Good Omens")
        #expect(first.filters.rating == .teen)
        #expect(first.filters.categories == [.mm])
        #expect(first.filters.completion == .complete)
        #expect(first.filters.wordsFrom == "5000")
        #expect(first.filters.language.id == "en")
        #expect(first.filters.sort == .kudos)

        let second = try #require(manifest.savedSearches.last)
        #expect(second.name == "Empty filters")
        #expect(second.filters == AO3SearchFilters())
    }

    /// Decode a hand-written manifest JSON blob with the same date strategy the
    /// real archive path uses (fractional seconds + whole-second fallback).
    private func decodeManifestJSON(_ json: String) throws -> KudosBackupManifest {
        try KudosBackupContents.decodeManifest(Data(json.utf8))
    }

    private func testDefaults() throws -> UserDefaults {
        let name = "KudosBackupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
}
