import Foundation
import SwiftData
import Testing
@testable import Kudos

extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct ReadingLogBackupTests {
    private func schema() -> Schema {
        Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self, ReadingAnnotation.self,
            ReadingSession.self, ReadingFavorite.self, FandomReadWatermark.self
        ])
    }

    private func context(_ schema: Schema) throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
    }

    private func testDefaults() throws -> UserDefaults {
        let name = "ReadingLogBackupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func sessionsFavoritesAndWatermarksRoundTrip() throws {
        let schema = schema()
        let source = try context(schema)
        let work = SavedWork(title: "Logged Work", author: "Archivist")
        work.keepInProgressOverride = true
        work.isSaved = true
        source.insert(work)
        let session = ReadingSession(
            workID: work.id,
            ao3WorkID: 42,
            sourceURL: "https://archiveofourown.org/works/42",
            workTitle: "Logged Work",
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 1_200),
            durationSeconds: 200,
            lastSpineIndex: 3,
            chapterTitle: "Chapter 4",
            endingProgress: 0.55,
            wordCount: 80_000,
            chapterCountAtVisit: 10,
            didFinish: true,
            lastModifiedAt: Date(timeIntervalSince1970: 1_200)
        )
        let favorite = ReadingFavorite(
            kind: .fandom,
            targetKey: "The Untamed (TV)",
            displayName: "The Untamed (TV)",
            createdAt: Date(timeIntervalSince1970: 500)
        )
        let watermark = FandomReadWatermark(
            fandomName: "The Untamed (TV)",
            lastVisitedAt: Date(timeIntervalSince1970: 800),
            newestWorkIDSeen: 42,
            newestWorkTitleSeen: "Logged Work",
            lastModifiedAt: Date(timeIntervalSince1970: 800)
        )
        source.insert(session)
        source.insert(favorite)
        source.insert(watermark)
        try source.save()

        let contents = try KudosBackupService.makeContents(
            works: [work],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            readingSessions: [session],
            readingFavorites: [favorite],
            fandomReadWatermarks: [watermark],
            defaults: try testDefaults()
        )
        #expect(contents.manifest.version == 8)
        #expect(contents.manifest.readingSessions.count == 1)
        #expect(contents.manifest.readingFavorites.count == 1)
        #expect(contents.manifest.fandomReadWatermarks.count == 1)
        #expect(contents.manifest.works.first?.keepInProgressOverride == true)

        let target = try context(schema)
        _ = try KudosBackupService.restore(contents, into: target, defaults: try testDefaults())

        let restoredWork = try #require(try target.fetch(FetchDescriptor<SavedWork>()).first)
        #expect(restoredWork.keepInProgressOverride)

        let restoredSession = try #require(try target.fetch(FetchDescriptor<ReadingSession>()).first)
        #expect(restoredSession.id == session.id)
        #expect(restoredSession.workID == work.id)
        #expect(restoredSession.durationSeconds == 200)
        #expect(restoredSession.wordCount == 80_000)
        #expect(restoredSession.didFinish)
        #expect(restoredSession.chapterTitle == "Chapter 4")

        let restoredFavorite = try #require(try target.fetch(FetchDescriptor<ReadingFavorite>()).first)
        #expect(restoredFavorite.kind == .fandom)
        #expect(restoredFavorite.targetKey == "The Untamed (TV)")

        let restoredWatermark = try #require(
            try target.fetch(FetchDescriptor<FandomReadWatermark>()).first
        )
        #expect(restoredWatermark.fandomName == "The Untamed (TV)")
        #expect(restoredWatermark.newestWorkIDSeen == 42)
    }

    @Test func keepInProgressOverrideDecodesFalseWhenAbsent() throws {
        let work = SavedWork(title: "Legacy", author: "A")
        work.keepInProgressOverride = true
        let contents = try KudosBackupService.makeContents(
            works: [work], bookmarks: [], fonts: [], readingQueues: [],
            defaults: try testDefaults()
        )
        var object = try #require(
            JSONSerialization.jsonObject(with: contents.manifestData()) as? [String: Any]
        )
        var works = try #require(object["works"] as? [[String: Any]])
        works[0].removeValue(forKey: "keepInProgressOverride")
        object["works"] = works
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let decoded = try KudosBackupContents.decodeManifest(stripped)
        #expect(decoded.works.first?.keepInProgressOverride == false)
    }

    @Test func v7AndV8ArchivesWithoutNewKeysStillImport() throws {
        let v7 = KudosBackupManifest(
            version: 7, works: [], bookmarks: [], fonts: [],
            settings: .capture(defaults: try testDefaults())
        )
        let v7Data = try KudosBackupContents(manifest: v7).manifestData()
        var v7Object = try #require(
            JSONSerialization.jsonObject(with: v7Data) as? [String: Any]
        )
        v7Object.removeValue(forKey: "readingSessions")
        v7Object.removeValue(forKey: "readingFavorites")
        v7Object.removeValue(forKey: "fandomReadWatermarks")
        let strippedV7 = try JSONSerialization.data(withJSONObject: v7Object)
        let decodedV7 = try KudosBackupContents.decodeManifest(strippedV7)
        #expect(decodedV7.readingSessions.isEmpty)
        #expect(decodedV7.readingFavorites.isEmpty)
        #expect(decodedV7.fandomReadWatermarks.isEmpty)
        #expect(decodedV7.version == 7)

        let v8 = KudosBackupManifest(
            version: 8, works: [], bookmarks: [], fonts: [],
            settings: .capture(defaults: try testDefaults())
        )
        let v8Data = try KudosBackupContents(manifest: v8).manifestData()
        var v8Object = try #require(
            JSONSerialization.jsonObject(with: v8Data) as? [String: Any]
        )
        v8Object.removeValue(forKey: "readingSessions")
        v8Object.removeValue(forKey: "readingFavorites")
        v8Object.removeValue(forKey: "fandomReadWatermarks")
        let strippedV8 = try JSONSerialization.data(withJSONObject: v8Object)
        let decodedV8 = try KudosBackupContents.decodeManifest(strippedV8)
        #expect(decodedV8.readingSessions.isEmpty)
        #expect(decodedV8.readingFavorites.isEmpty)
        #expect(decodedV8.fandomReadWatermarks.isEmpty)
        #expect(KudosBackupManifest.currentVersion == 8)
    }

    @Test func tombstoneSuppressesResurrectionOfAnOlderArchive() throws {
        let schema = schema()
        let source = try context(schema)
        let session = ReadingSession(
            workID: UUID(),
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            durationSeconds: 100,
            lastModifiedAt: Date(timeIntervalSince1970: 200)
        )
        let favorite = ReadingFavorite(
            kind: .tag, targetKey: "Angst", displayName: "Angst",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let watermark = FandomReadWatermark(
            fandomName: "Old Fandom",
            lastVisitedAt: Date(timeIntervalSince1970: 100)
        )
        source.insert(session)
        source.insert(favorite)
        source.insert(watermark)
        try source.save()
        let contents = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [],
            readingSessions: [session],
            readingFavorites: [favorite],
            fandomReadWatermarks: [watermark],
            defaults: try testDefaults()
        )

        let target = try context(schema)
        target.insert(SyncTombstone(
            recordID: session.id, recordType: .readingSession,
            createdAt: Date(timeIntervalSince1970: 5_000)
        ))
        target.insert(SyncTombstone(
            recordID: favorite.id, recordType: .readingFavorite,
            createdAt: Date(timeIntervalSince1970: 5_000)
        ))
        target.insert(SyncTombstone(
            recordID: watermark.id, recordType: .fandomReadWatermark,
            createdAt: Date(timeIntervalSince1970: 5_000)
        ))
        try target.save()

        _ = try KudosBackupService.restore(contents, into: target, defaults: try testDefaults())
        #expect(try target.fetch(FetchDescriptor<ReadingSession>()).isEmpty)
        #expect(try target.fetch(FetchDescriptor<ReadingFavorite>()).isEmpty)
        #expect(try target.fetch(FetchDescriptor<FandomReadWatermark>()).isEmpty)
    }

    @Test func replaceOmissionMintsTombstonesAndALaterMergeDoesNotResurrect() throws {
        let schema = schema()
        let context = try context(schema)
        let keepSession = ReadingSession(
            workID: UUID(),
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            durationSeconds: 100
        )
        let dropSession = ReadingSession(
            workID: UUID(),
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            durationSeconds: 100
        )
        let dropFavorite = ReadingFavorite(kind: .author, targetKey: "route/a", displayName: "A")
        let dropWatermark = FandomReadWatermark(fandomName: "Drop Fandom")
        context.insert(keepSession)
        context.insert(dropSession)
        context.insert(dropFavorite)
        context.insert(dropWatermark)
        try context.save()
        let dropSessionID = dropSession.id
        let dropFavoriteID = dropFavorite.id
        let dropWatermarkID = dropWatermark.id

        let stale = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [],
            readingSessions: [keepSession, dropSession],
            readingFavorites: [dropFavorite],
            fandomReadWatermarks: [dropWatermark],
            defaults: try testDefaults()
        )
        let replaceSnapshot = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [],
            readingSessions: [keepSession],
            readingFavorites: [],
            fandomReadWatermarks: [],
            defaults: try testDefaults()
        )
        _ = try KudosBackupService.restore(
            replaceSnapshot, into: context, defaults: try testDefaults(), mode: .replaceLibrary
        )
        _ = try KudosBackupService.restore(
            stale, into: context, defaults: try testDefaults(), mode: .merge
        )

        let sessions = try context.fetch(FetchDescriptor<ReadingSession>())
        #expect(Set(sessions.map(\.id)) == Set([keepSession.id]))
        #expect(try context.fetch(FetchDescriptor<ReadingFavorite>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FandomReadWatermark>()).isEmpty)
        let tombs = try context.fetch(FetchDescriptor<SyncTombstone>())
        #expect(tombs.contains {
            $0.recordType == .readingSession && $0.recordID == dropSessionID && !$0.signature.isEmpty
        })
        #expect(tombs.contains {
            $0.recordType == .readingFavorite && $0.recordID == dropFavoriteID && !$0.signature.isEmpty
        })
        #expect(tombs.contains {
            $0.recordType == .fandomReadWatermark && $0.recordID == dropWatermarkID
                && !$0.signature.isEmpty
        })
    }

    @Test func addingReadingLogDidNotBumpTheSchemaVersion() {
        #expect(KudosBackupManifest.currentVersion == 8)
        #expect(KudosBackupManifest.supportedVersions.contains(8))
        #expect(!KudosBackupManifest.supportedVersions.contains(9))
    }
}
}
