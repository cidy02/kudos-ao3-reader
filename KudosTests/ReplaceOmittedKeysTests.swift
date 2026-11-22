import Foundation
import SwiftData
import Testing
@testable import Kudos

/// T-563. In Replace Library an archive key that is ABSENT says nothing about those rows; a key
/// that is PRESENT (even `[]`) replaces the collection. Needs only an in-memory store.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct ReplaceOmittedKeysTests {
    private func schema() -> Schema {
        Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, QueueSavedSearchLink.self, SyncTombstone.self, ReadingAnnotation.self,
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
        let name = "ReplaceOmittedKeysTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// An empty iOS-style archive, with the named top-level keys removed from its JSON and decoded
    /// again, as an Android re-export or an older build would present it.
    private func archive(
        removing keys: [String], nulling nulled: [String] = [], works: [SavedWork] = []
    ) throws -> KudosBackupContents {
        let manifest = KudosBackupManifest(
            works: works.map(KudosBackupWork.init(work:)), bookmarks: [], fonts: [],
            settings: .capture(defaults: try testDefaults())
        )
        let data = try KudosBackupContents(manifest: manifest).manifestData()
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in keys { object.removeValue(forKey: key) }
        for key in nulled { object[key] = NSNull() }
        let stripped = try JSONSerialization.data(withJSONObject: object)
        return KudosBackupContents(manifest: try KudosBackupContents.decodeManifest(stripped))
    }

    private func seedLog(_ target: ModelContext) throws {
        target.insert(ReadingSession(
            workID: UUID(), startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 1_100), durationSeconds: 100
        ))
        target.insert(ReadingFavorite(kind: .tag, targetKey: "Slow Burn"))
        target.insert(FandomReadWatermark(fandomName: "Naruto"))
        try target.save()
    }

    @Test func anArchiveWithoutTheLogKeysLeavesLocalRowsAndWritesNoTombstones() throws {
        let target = try context(schema())
        try seedLog(target)
        let contents = try archive(
            removing: ["readingSessions", "readingFavorites", "fandomReadWatermarks"]
        )
        #expect(contents.manifest.readingSessions == nil)
        #expect(contents.manifest.readingFavorites == nil)
        #expect(contents.manifest.fandomReadWatermarks == nil)

        _ = try KudosBackupService.restore(
            contents, into: target, defaults: try testDefaults(), mode: .replaceLibrary
        )

        #expect(try target.fetch(FetchDescriptor<ReadingSession>()).count == 1)
        #expect(try target.fetch(FetchDescriptor<ReadingFavorite>()).count == 1)
        #expect(try target.fetch(FetchDescriptor<FandomReadWatermark>()).count == 1)
        #expect(try target.fetch(FetchDescriptor<SyncTombstone>()).isEmpty)
    }

    @Test func anArchiveWithEmptyLogKeysStillReplacesThem() throws {
        let target = try context(schema())
        try seedLog(target)
        let contents = try archive(removing: [])
        #expect(contents.manifest.readingSessions == [])

        _ = try KudosBackupService.restore(
            contents, into: target, defaults: try testDefaults(), mode: .replaceLibrary
        )

        #expect(try target.fetch(FetchDescriptor<ReadingSession>()).isEmpty)
        #expect(try target.fetch(FetchDescriptor<ReadingFavorite>()).isEmpty)
        #expect(try target.fetch(FetchDescriptor<FandomReadWatermark>()).isEmpty)
        #expect(try target.fetch(FetchDescriptor<SyncTombstone>()).count == 3)
    }

    @Test func eachLogKeyIsJudgedOnItsOwn() throws {
        let target = try context(schema())
        try seedLog(target)
        let contents = try archive(removing: ["readingFavorites"])

        _ = try KudosBackupService.restore(
            contents, into: target, defaults: try testDefaults(), mode: .replaceLibrary
        )

        #expect(try target.fetch(FetchDescriptor<ReadingSession>()).isEmpty)
        #expect(try target.fetch(FetchDescriptor<ReadingFavorite>()).count == 1)
        #expect(try target.fetch(FetchDescriptor<FandomReadWatermark>()).isEmpty)
    }

    @Test func omittedCollectionsQueuesAnnotationsAndSearchesAreLeftAlone() throws {
        let target = try context(schema())
        let work = SavedWork(title: "Kept", author: "Writer")
        target.insert(work)
        let collection = WorkCollection(name: "Keep me")
        let queue = ReadingQueue(name: "Keep me too")
        let search = SavedSearch(name: "Comfort", filters: AO3SearchFilters())
        let annotation = ReadingAnnotation(
            work: work, kind: .highlight, locatorString: "{}", note: "n", color: .yellow,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        target.insert(collection)
        target.insert(queue)
        target.insert(search)
        target.insert(annotation)
        try target.save()
        let contents = try archive(
            removing: ["collections", "readingQueues", "annotations", "savedSearches"]
        )

        _ = try KudosBackupService.restore(
            contents, into: target, defaults: try testDefaults(), mode: .replaceLibrary
        )

        #expect(collection.isPendingDeletion == false)
        #expect(queue.isPendingDeletion == false)
        #expect(annotation.isPendingDeletion == false)
        #expect(try target.fetch(FetchDescriptor<SavedSearch>()).count == 1)
        #expect(try target.fetch(FetchDescriptor<SyncTombstone>()).isEmpty)
    }

    @Test func presentEmptyCollectionsQueuesAnnotationsAndSearchesStillReplace() throws {
        let target = try context(schema())
        let work = SavedWork(title: "Gone", author: "Writer")
        target.insert(work)
        let collection = WorkCollection(name: "Replace me")
        let queue = ReadingQueue(name: "Replace me too")
        target.insert(collection)
        target.insert(queue)
        target.insert(SavedSearch(name: "Comfort", filters: AO3SearchFilters()))
        let kept = SavedWork(title: "Kept", author: "Writer")
        target.insert(kept)
        let highlight = ReadingAnnotation(
            work: kept, kind: .highlight, locatorString: "{}", note: "n", color: .yellow,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        target.insert(highlight)
        try target.save()

        // `kept` is in the archive, so only the annotation sweep can remove its highlight.
        _ = try KudosBackupService.restore(
            try archive(removing: [], works: [kept]), into: target,
            defaults: try testDefaults(), mode: .replaceLibrary
        )

        #expect(collection.isPendingDeletion)
        #expect(queue.isPendingDeletion)
        #expect(highlight.isPendingDeletion)
        #expect(try target.fetch(FetchDescriptor<SavedSearch>()).isEmpty)
    }

    @Test func nullCollectionsQueuesAnnotationsAndSearchesAreLeftAlone() throws {
        let target = try context(schema())
        target.insert(SavedSearch(name: "Comfort", filters: AO3SearchFilters()))
        let collection = WorkCollection(name: "Keep me")
        target.insert(collection)
        try target.save()
        let keys = ["collections", "readingQueues", "annotations", "savedSearches"]
        let contents = try archive(removing: [], nulling: keys)
        #expect(contents.manifest.omittedKeys == Set(keys))

        _ = try KudosBackupService.restore(
            contents, into: target, defaults: try testDefaults(), mode: .replaceLibrary
        )

        #expect(collection.isPendingDeletion == false)
        #expect(try target.fetch(FetchDescriptor<SavedSearch>()).count == 1)
        #expect(try target.fetch(FetchDescriptor<SyncTombstone>()).isEmpty)
    }

    @Test func writersAlwaysEmitTheLogKeysEvenWhenEmpty() throws {
        let contents = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [], defaults: try testDefaults()
        )
        let root = try #require(
            JSONSerialization.jsonObject(with: contents.manifestData()) as? [String: Any]
        )
        for key in ["readingSessions", "readingFavorites", "fandomReadWatermarks"] {
            #expect((root[key] as? [Any])?.isEmpty == true)
        }
        let decoded = try KudosBackupContents.decodeManifest(contents.manifestData())
        #expect(decoded.readingSessions == [])
        #expect(decoded.omittedKeys.isEmpty)
    }
}
}
