import Foundation
import SwiftData
import Testing
@testable import Kudos

/// Replace means "make this library match the file", so a choice the snapshot
/// does not carry is a choice the reader is asking to drop. Three places kept
/// local state anyway, each by reusing a rule written for merge — where keeping
/// it is right, because a stale archive's silence is not a deletion.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct ReplaceIsTheSnapshotTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self, ReadingAnnotation.self
        ])
        return ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
    }

    private func testDefaults() throws -> UserDefaults {
        let name = "ReplaceIsTheSnapshotTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private struct Fixture {
        let context: ModelContext
        let queue: ReadingQueue
        let work: SavedWork
        let membership: ReadingQueueMembership
    }

    /// A queue holding one work, in a context of its own.
    private func fixture(queueID: UUID, workID: UUID, at when: Date) throws -> Fixture {
        let context = try makeContext()
        let work = SavedWork(id: workID, title: "Queued", author: "Writer")
        let queue = ReadingQueue(
            id: queueID, name: "Weekend Reads", dateCreated: when, dateUpdated: when
        )
        let membership = ReadingQueueMembership(
            queue: queue, work: work, queuedAt: when, sortOrderInQueue: 0
        )
        context.insert(work)
        context.insert(queue)
        context.insert(membership)
        try context.save()
        return Fixture(context: context, queue: queue, work: work, membership: membership)
    }

    /// The archive's queue is not pinned. The local one is. Replace must unpin
    /// it — the assignment was `archivedPin || queue.isPinned`, which could only
    /// ever change the answer in the case where the archive had already won.
    @Test func replaceUnpinsAQueueTheSnapshotDoesNotPin() throws {
        let queueID = UUID(), workID = UUID()
        let archive = try fixture(queueID: queueID, workID: workID, at: Date(timeIntervalSince1970: 1_000))
        archive.queue.isPinned = false
        try archive.context.save()
        let contents = try KudosBackupService.makeContents(
            works: [archive.work], bookmarks: [], fonts: [],
            readingQueues: [archive.queue], defaults: try testDefaults()
        )

        let local = try fixture(queueID: queueID, workID: workID, at: Date(timeIntervalSince1970: 9_000))
        local.queue.isPinned = true
        try local.context.save()

        _ = try KudosBackupService.restore(
            contents, into: local.context, defaults: try testDefaults(), mode: .replaceLibrary
        )

        #expect(local.queue.isPinned == false)
    }

    /// Merge must still not read a stale archive's silence as a deletion —
    /// the guard on the fix above.
    @Test func mergeStillDoesNotUnpinAQueueTheArchiveOmits() throws {
        let queueID = UUID(), workID = UUID()
        let archive = try fixture(queueID: queueID, workID: workID, at: Date(timeIntervalSince1970: 1_000))
        archive.queue.isPinned = false
        try archive.context.save()
        let contents = try KudosBackupService.makeContents(
            works: [archive.work], bookmarks: [], fonts: [],
            readingQueues: [archive.queue], defaults: try testDefaults()
        )

        let local = try fixture(queueID: queueID, workID: workID, at: Date(timeIntervalSince1970: 9_000))
        local.queue.isPinned = true
        try local.context.save()

        _ = try KudosBackupService.restore(
            contents, into: local.context, defaults: try testDefaults(), mode: .merge
        )

        #expect(local.queue.isPinned)
    }

    /// A tag only this device has is, under Replace, one the reader asked to be
    /// rid of. The loop was union-only in every mode.
    @Test func replaceDropsAQueueTagTheSnapshotDoesNotCarry() throws {
        let queueID = UUID(), workID = UUID()
        let archive = try fixture(queueID: queueID, workID: workID, at: Date(timeIntervalSince1970: 1_000))
        let kept = Tag(name: "comfort")
        archive.context.insert(kept)
        archive.queue.tags.append(kept)
        try archive.context.save()
        let contents = try KudosBackupService.makeContents(
            works: [archive.work], bookmarks: [], fonts: [],
            readingQueues: [archive.queue], defaults: try testDefaults()
        )

        let local = try fixture(queueID: queueID, workID: workID, at: Date(timeIntervalSince1970: 9_000))
        let localOnly = Tag(name: "abandoned")
        local.context.insert(localOnly)
        local.queue.tags.append(localOnly)
        try local.context.save()

        _ = try KudosBackupService.restore(
            contents, into: local.context, defaults: try testDefaults(), mode: .replaceLibrary
        )

        #expect(Set(local.queue.tags.map(\.name)) == ["comfort"])
    }

    /// The order and the note are what a reading queue IS. A membership the
    /// reader moved after the backup was taken kept its local position, because
    /// the update stayed gated on recency in every mode — so the one edit
    /// Replace was asked to undo was the one it would not touch.
    @Test func replaceRestoresTheArchivedOrderOverANewerLocalEdit() throws {
        let queueID = UUID(), workID = UUID()
        let archive = try fixture(queueID: queueID, workID: workID, at: Date(timeIntervalSince1970: 1_000))
        archive.membership.sortOrderInQueue = 7
        archive.membership.note = "start here"
        archive.membership.lastModifiedAt = Date(timeIntervalSince1970: 1_000)
        try archive.context.save()
        let contents = try KudosBackupService.makeContents(
            works: [archive.work], bookmarks: [], fonts: [],
            readingQueues: [archive.queue], defaults: try testDefaults()
        )

        // Moved here AFTER the backup was taken — newer, and therefore exactly
        // what the old recency gate protected.
        let local = try fixture(queueID: queueID, workID: workID, at: Date(timeIntervalSince1970: 9_000))
        local.membership.sortOrderInQueue = 0
        local.membership.note = "moved since"
        local.membership.lastModifiedAt = Date(timeIntervalSince1970: 9_000)
        try local.context.save()

        _ = try KudosBackupService.restore(
            contents, into: local.context, defaults: try testDefaults(), mode: .replaceLibrary
        )

        #expect(local.membership.sortOrderInQueue == 7)
        #expect(local.membership.note == "start here")
    }
}
}
