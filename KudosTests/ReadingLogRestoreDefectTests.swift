import Foundation
import SwiftData
import Testing
@testable import Kudos

/// Three review findings against the reading log's backup integration. Each test
/// is written to fail on the code as it was, so a revert cannot pass quietly.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct ReadingLogRestoreDefectTests {
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
        let name = "ReadingLogRestoreDefectTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func session(
        workID: UUID, at seconds: TimeInterval = 1_000
    ) -> ReadingSession {
        ReadingSession(
            workID: workID,
            startedAt: Date(timeIntervalSince1970: seconds),
            endedAt: Date(timeIntervalSince1970: seconds + 200),
            durationSeconds: 200,
            lastModifiedAt: Date(timeIntervalSince1970: seconds + 200)
        )
    }

    // MARK: Replace Library must not delete what it just matched

    @Test func replaceLibraryKeepsFavoritesAndWatermarksMatchedByTarget() throws {
        let schema = schema()

        // Two devices that independently starred the same fandom and visited it:
        // same target, different UUIDs. This is the ordinary case, not a corner.
        let source = try context(schema)
        let archivedFavorite = ReadingFavorite(
            kind: .fandom, targetKey: "The Untamed (TV)", displayName: "The Untamed (TV)",
            createdAt: Date(timeIntervalSince1970: 500)
        )
        let archivedWatermark = FandomReadWatermark(
            fandomName: "The Untamed (TV)",
            lastVisitedAt: Date(timeIntervalSince1970: 900),
            lastModifiedAt: Date(timeIntervalSince1970: 900)
        )
        source.insert(archivedFavorite)
        source.insert(archivedWatermark)
        try source.save()

        let contents = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [],
            readingSessions: [],
            readingFavorites: [archivedFavorite],
            fandomReadWatermarks: [archivedWatermark],
            defaults: try testDefaults()
        )

        let target = try context(schema)
        let localFavorite = ReadingFavorite(
            kind: .fandom, targetKey: "The Untamed (TV)", displayName: "The Untamed (TV)",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let localWatermark = FandomReadWatermark(
            fandomName: "The Untamed (TV)",
            lastVisitedAt: Date(timeIntervalSince1970: 200),
            lastModifiedAt: Date(timeIntervalSince1970: 200)
        )
        target.insert(localFavorite)
        target.insert(localWatermark)
        try target.save()

        _ = try KudosBackupService.restore(
            contents, into: target, defaults: try testDefaults(), mode: .replaceLibrary
        )

        // The record is matched by target, so it keeps its local UUID — which the
        // archive has never heard of. Deleting on id-absence wiped the record that
        // had just been matched and updated: one of each in, zero of each out.
        #expect(try target.fetch(FetchDescriptor<ReadingFavorite>()).count == 1)
        #expect(try target.fetch(FetchDescriptor<FandomReadWatermark>()).count == 1)
    }

    @Test func replaceLibraryStillDropsRecordsTheArchiveDoesNotHave() throws {
        let schema = schema()
        let contents = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [],
            defaults: try testDefaults()
        )

        let target = try context(schema)
        target.insert(ReadingFavorite(kind: .tag, targetKey: "Slow Burn"))
        target.insert(FandomReadWatermark(fandomName: "Naruto"))
        try target.save()

        _ = try KudosBackupService.restore(
            contents, into: target, defaults: try testDefaults(), mode: .replaceLibrary
        )

        // The other half of the rule: Replace Library still replaces.
        #expect(try target.fetch(FetchDescriptor<ReadingFavorite>()).isEmpty)
        #expect(try target.fetch(FetchDescriptor<FandomReadWatermark>()).isEmpty)
    }

    @Test func repeatingAnIdenticalReplaceLibraryIsNotDestructive() throws {
        let schema = schema()

        // The archive holds the records *and* the tombstones from when they were
        // deleted on the source device — which is the ordinary shape of a backup
        // taken after a delete-and-recreate.
        let source = try context(schema)
        let favorite = ReadingFavorite(
            kind: .tag, targetKey: "Fix-It", displayName: "Fix-It",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let watermark = FandomReadWatermark(
            fandomName: "Naruto", lastModifiedAt: Date(timeIntervalSince1970: 100)
        )
        source.insert(favorite)
        source.insert(watermark)
        try source.save()
        SyncTombstones.recordDeletion(of: favorite, in: source)
        SyncTombstones.recordDeletion(of: watermark, in: source)
        try source.save()
        let tombstones = try source.fetch(FetchDescriptor<SyncTombstone>())

        let contents = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [],
            readingSessions: [],
            readingFavorites: [favorite],
            fandomReadWatermarks: [watermark],
            tombstones: tombstones,
            defaults: try testDefaults()
        )

        let target = try context(schema)
        _ = try KudosBackupService.restore(
            contents, into: target, defaults: try testDefaults(), mode: .replaceLibrary
        )
        #expect(try target.fetch(FetchDescriptor<ReadingFavorite>()).count == 1)
        #expect(try target.fetch(FetchDescriptor<FandomReadWatermark>()).count == 1)

        // Replace Library is "make this device look like the archive", and the
        // archive wins even over a local delete — so running it twice must be
        // idempotent. A tombstone pass that ignored the mode turned the second
        // run into a deletion of what the first had just restored.
        _ = try KudosBackupService.restore(
            contents, into: target, defaults: try testDefaults(), mode: .replaceLibrary
        )
        #expect(try target.fetch(FetchDescriptor<ReadingFavorite>()).count == 1)
        #expect(try target.fetch(FetchDescriptor<FandomReadWatermark>()).count == 1)
    }

    // MARK: History must follow the work it belongs to

    @Test func historyAndStarsFollowAWorkMergedIntoAnExistingCopy() throws {
        let schema = schema()

        let source = try context(schema)
        let archivedWork = SavedWork(title: "Shared Work", author: "A")
        archivedWork.ao3WorkID = 5150
        source.insert(archivedWork)
        let archivedSession = session(workID: archivedWork.id)
        let archivedStar = ReadingFavorite(
            kind: .work,
            targetKey: ReadingFavorite.workTargetKey(archivedWork),
            displayName: "Shared Work"
        )
        source.insert(archivedSession)
        source.insert(archivedStar)
        try source.save()

        let contents = try KudosBackupService.makeContents(
            works: [archivedWork], bookmarks: [], fonts: [], readingQueues: [],
            readingSessions: [archivedSession],
            readingFavorites: [archivedStar],
            fandomReadWatermarks: [],
            defaults: try testDefaults()
        )

        // The same work already here under a different UUID — restore merges into
        // it and keeps the local id.
        let target = try context(schema)
        let localWork = SavedWork(title: "Shared Work", author: "A")
        localWork.ao3WorkID = 5150
        target.insert(localWork)
        try target.save()

        _ = try KudosBackupService.restore(contents, into: target, defaults: try testDefaults())

        let works = try target.fetch(FetchDescriptor<SavedWork>())
        #expect(works.count == 1)
        let survivor = try #require(works.first)

        // Imported history pointing at the archived UUID would disappear from every
        // query for the work that actually survived.
        let restoredSession = try #require(
            try target.fetch(FetchDescriptor<ReadingSession>()).first
        )
        #expect(restoredSession.workID == survivor.id)

        let restoredStar = try #require(
            try target.fetch(FetchDescriptor<ReadingFavorite>()).first
        )
        #expect(restoredStar.targetKey == survivor.id.uuidString)
    }

    @Test func historyForAWorkThatIsNotHereStaysDetachedRatherThanBeingDropped() throws {
        let schema = schema()
        let source = try context(schema)
        let missingWorkID = UUID()
        let orphan = session(workID: missingWorkID)
        source.insert(orphan)
        try source.save()

        let contents = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [],
            readingSessions: [orphan], readingFavorites: [], fandomReadWatermarks: [],
            defaults: try testDefaults()
        )

        let target = try context(schema)
        _ = try KudosBackupService.restore(contents, into: target, defaults: try testDefaults())

        // The log is deliberately not tied to a live row — hours read are still
        // hours read when the work is gone.
        let restored = try #require(try target.fetch(FetchDescriptor<ReadingSession>()).first)
        #expect(restored.workID == missingWorkID)
    }

    // MARK: Deletions have to reach records already here

    @Test func aDeletionOnAnotherDeviceRemovesTheLocalCopy() throws {
        let schema = schema()

        // The archive carries the tombstone and *not* the record — which is what a
        // deletion looks like. Checking tombstones only while iterating incoming
        // records therefore never examined the local copy at all.
        let source = try context(schema)
        let doomed = ReadingFavorite(
            kind: .tag, targetKey: "Fix-It", displayName: "Fix-It",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        source.insert(doomed)
        try source.save()
        SyncTombstones.recordDeletion(of: doomed, in: source)
        source.delete(doomed)
        try source.save()
        let tombstones = try source.fetch(FetchDescriptor<SyncTombstone>())
        #expect(!tombstones.isEmpty)

        let contents = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [],
            readingSessions: [], readingFavorites: [], fandomReadWatermarks: [],
            tombstones: tombstones,
            defaults: try testDefaults()
        )
        #expect(contents.manifest.readingFavorites.isEmpty)

        let target = try context(schema)
        let localCopy = ReadingFavorite(
            id: doomed.id, kind: .tag, targetKey: "Fix-It", displayName: "Fix-It",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        localCopy.lastModifiedAt = Date(timeIntervalSince1970: 100)
        target.insert(localCopy)
        try target.save()

        _ = try KudosBackupService.restore(contents, into: target, defaults: try testDefaults())

        #expect(try target.fetch(FetchDescriptor<ReadingFavorite>()).isEmpty)
    }
}
}
