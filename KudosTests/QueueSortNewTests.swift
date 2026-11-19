import Foundation
import SwiftData
import Testing
@testable import Kudos

/// T-529 Sort New: Keep / Later / Drop on a queue's New works, and Undo back to
/// the start of the session restoring state, order, origin and Recently Deleted.
@MainActor
@Suite(.serialized)
struct QueueSortNewTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self, WorkCollection.self,
            ReadingQueue.self, ReadingQueueMembership.self, SavedSearch.self,
            QueueSavedSearchLink.self, SyncTombstone.self, ReadingAnnotation.self,
            ReadingSession.self, ReadingFavorite.self, FandomReadWatermark.self
        ])
        return ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
    }

    private struct Fixture {
        let context: ModelContext
        let queue: ReadingQueue
        let lined: SavedWork
        let library: SavedWork
        let queueOnly: SavedWork
        let third: SavedWork
        let mLined: ReadingQueueMembership
        let mLibrary: ReadingQueueMembership
        let mQueueOnly: ReadingQueueMembership
        let mThird: ReadingQueueMembership
    }

    /// One In line work, then three New works: a Library work, a queue-only work
    /// and another queue-only work, each with a recorded origin.
    private func makeFixture() throws -> Fixture {
        let context = try makeContext()
        let queue = ReadingQueue(name: "Summer Reading")
        context.insert(queue)
        func work(_ title: String, saved: Bool) -> SavedWork {
            let work = SavedWork(title: title, author: "Author")
            work.chapters = "1/1"
            work.isComplete = true
            work.isSaved = saved
            work.wordCount = 9_000
            context.insert(work)
            return work
        }
        let lined = work("Lined", saved: true)
        let library = work("Library", saved: true)
        let queueOnly = work("Queue only", saved: false)
        let third = work("Third", saved: false)
        let origin = ReadingQueueMembershipOrigin(kind: .search, searchID: UUID(), label: "Holmes casefic")
        let mLined = ReadingQueueService.add(lined, to: queue, state: .inLine, in: context)
        let mLibrary = ReadingQueueService.add(library, to: queue, state: .new, origin: origin, in: context)
        let mQueueOnly = ReadingQueueService.add(queueOnly, to: queue, state: .new, origin: origin, in: context)
        let mThird = ReadingQueueService.add(third, to: queue, state: .new, in: context)
        mLibrary.note = "from the train"
        return Fixture(
            context: context, queue: queue, lined: lined, library: library, queueOnly: queueOnly, third: third,
            mLined: mLined, mLibrary: mLibrary, mQueueOnly: mQueueOnly, mThird: mThird
        )
    }

    private func newSession(_ fixture: Fixture) -> QueueSortSession {
        let new = ReadingQueueFacts.partition(
            memberships: ReadingQueueService.orderedMemberships(in: fixture.queue)
        ).new
        return QueueSortSession(queueID: fixture.queue.id, membershipIDs: new.map(\.membership.id))
    }

    private func membershipTombstones(_ context: ModelContext, id: UUID) throws -> Int {
        try context.fetch(FetchDescriptor<SyncTombstone>())
            .filter { $0.recordType == .readingQueueMembership && $0.recordID == id }
            .count
    }

    private func titlesInOrder(_ queue: ReadingQueue) -> [String] {
        ReadingQueueService.orderedMemberships(in: queue).compactMap { $0.work?.title }
    }

    // MARK: - Session

    @Test func sessionCountsProgressSegmentsAndSubtitle() {
        let ids = (0..<4).map { _ in UUID() }
        var session = QueueSortSession(queueID: UUID(), membershipIDs: ids + [ids[0]])
        #expect(session.total == 4)
        #expect(session.subtitle(queueName: "Summer Reading") == "1 of 4 · Summer Reading")
        #expect(session.segments == [.current, .upcoming, .upcoming, .upcoming])
        #expect(!session.canUndo)

        let keep = QueueSortRecord(
            membershipID: ids[0], workID: UUID(), action: .keep, before: nil,
            sentWorkToRecentlyDeleted: false, preservationStatusRaw: nil, preservedAt: nil
        )
        session.record(keep)
        // Only the current membership can be recorded.
        session.record(keep)
        session.record(.skip(membershipID: ids[1]))
        #expect(session.sortedCount == 2)
        #expect(session.currentMembershipID == ids[2])
        #expect(session.nextMembershipID == ids[3])
        #expect(session.segments == [.sorted, .sorted, .current, .upcoming])
        #expect(session.progressAccessibilityLabel == "2 of 4 sorted")
        #expect(session.count(of: .keep) == 1)
        #expect(session.count(of: .later) == 0)

        // Undo steps back over the skip to the last real decision.
        #expect(session.popLast() == keep)
        #expect(session.currentMembershipID == ids[0])
        #expect(session.popLast() == nil)
    }

    @Test func footerLineFollowsBoardCopy() {
        #expect(QueueSortSession.footerLine(minutes: 37, originLabel: "Holmes casefic under 20k")
            == "About 35 min to read · found by Holmes casefic under 20k")
        #expect(QueueSortSession.footerLine(minutes: nil, originLabel: "  ") == nil)
        #expect(QueueSortSession.footerLine(minutes: 90, originLabel: nil) == "About 1 h 30 min to read")
    }

    // MARK: - Keep

    @Test func keepMovesToEndOfInLineAndUndoRestoresStateOrderAndOrigin() throws {
        let fixture = try makeFixture()
        var session = newSession(fixture)
        #expect(session.membershipIDs == [fixture.mLibrary.id, fixture.mQueueOnly.id, fixture.mThird.id])
        let before = QueueSortMembershipSnapshot(fixture.mLibrary)

        #expect(QueueSortNew.apply(.keep, session: &session, queue: fixture.queue, context: fixture.context))
        #expect(fixture.mLibrary.state == .inLine)
        let after = ReadingQueueFacts.partition(memberships: ReadingQueueService.orderedMemberships(in: fixture.queue))
        #expect(after.inLineAll.map(\.work.title) == ["Lined", "Library"])
        #expect(session.currentMembershipID == fixture.mQueueOnly.id)

        let undone = QueueSortNew.undo(session: &session, queue: fixture.queue, context: fixture.context)
        #expect(undone?.action == .keep)
        #expect(QueueSortMembershipSnapshot(fixture.mLibrary) == before)
        #expect(fixture.mLibrary.state == .new)
        #expect(fixture.mLibrary.origin?.label == "Holmes casefic")
        #expect(titlesInOrder(fixture.queue) == ["Lined", "Library", "Queue only", "Third"])
        #expect(session.currentMembershipID == fixture.mLibrary.id)
    }

    // MARK: - Later

    @Test func laterLeavesWorkInNewAndUndoStepsBack() throws {
        let fixture = try makeFixture()
        var session = newSession(fixture)
        let before = QueueSortMembershipSnapshot(fixture.mLibrary)

        #expect(QueueSortNew.apply(.later, session: &session, queue: fixture.queue, context: fixture.context))
        #expect(QueueSortMembershipSnapshot(fixture.mLibrary) == before)
        #expect(fixture.mLibrary.state == .new)
        #expect(session.currentMembershipID == fixture.mQueueOnly.id)

        #expect(QueueSortNew.undo(session: &session, queue: fixture.queue, context: fixture.context)?.action == .later)
        #expect(QueueSortMembershipSnapshot(fixture.mLibrary) == before)
        #expect(session.currentMembershipID == fixture.mLibrary.id)
    }

    // MARK: - Drop

    @Test func dropOfALibraryWorkKeepsItInTheLibraryAndUndoRestoresTheMembership() throws {
        let fixture = try makeFixture()
        var session = newSession(fixture)
        let before = QueueSortMembershipSnapshot(fixture.mLibrary)

        #expect(QueueSortNew.apply(.drop, session: &session, queue: fixture.queue, context: fixture.context))
        // The Library work survives Drop.
        #expect(!fixture.library.isPendingDeletion)
        #expect(fixture.library.deletedAt == nil)
        #expect(fixture.library.isSaved)
        #expect(try fixture.context.fetch(FetchDescriptor<SavedWork>()).contains { $0.id == fixture.library.id })
        #expect(!fixture.library.queueMemberships.contains { $0.queue?.id == fixture.queue.id })
        #expect(session.history.last?.sentWorkToRecentlyDeleted == false)
        #expect(try membershipTombstones(fixture.context, id: before.id) == 1)

        #expect(QueueSortNew.undo(session: &session, queue: fixture.queue, context: fixture.context)?.action == .drop)
        let restored = try #require(QueueSortNew.membership(before.id, in: fixture.queue))
        #expect(QueueSortMembershipSnapshot(restored) == before)
        #expect(restored.state == .new)
        #expect(restored.origin?.label == "Holmes casefic")
        #expect(restored.note == "from the train")
        #expect(restored.work?.id == fixture.library.id)
        #expect(fixture.library.isQueuedForLater)
        #expect(titlesInOrder(fixture.queue) == ["Lined", "Library", "Queue only", "Third"])
        #expect(try membershipTombstones(fixture.context, id: before.id) == 0)
        #expect(session.currentMembershipID == before.id)
    }

    @Test func dropOfAQueueOnlyWorkSendsItToRecentlyDeletedAndUndoBringsItBack() throws {
        let fixture = try makeFixture()
        var session = newSession(fixture)
        #expect(QueueSortNew.apply(.later, session: &session, queue: fixture.queue, context: fixture.context))
        let before = QueueSortMembershipSnapshot(fixture.mQueueOnly)
        let workID = fixture.queueOnly.id

        #expect(QueueSortNew.apply(.drop, session: &session, queue: fixture.queue, context: fixture.context))
        // Soft-deleted, never hard-deleted.
        let dropped = try #require(try fixture.context.fetch(FetchDescriptor<SavedWork>()).first { $0.id == workID })
        #expect(dropped.isPendingDeletion)
        #expect(dropped.permanentDeletionScheduledAt != nil)
        #expect(session.history.last?.sentWorkToRecentlyDeleted == true)
        let workTombstones = try fixture.context.fetch(FetchDescriptor<SyncTombstone>())
            .filter { $0.recordType == .savedWork && $0.recordID == workID }
        #expect(workTombstones.count == 1)

        #expect(QueueSortNew.undo(session: &session, queue: fixture.queue, context: fixture.context)?.action == .drop)
        #expect(!dropped.isPendingDeletion)
        #expect(dropped.deletedAt == nil)
        #expect(dropped.permanentDeletionScheduledAt == nil)
        #expect(dropped.isQueuedForLater)
        let restored = try #require(QueueSortNew.membership(before.id, in: fixture.queue))
        #expect(QueueSortMembershipSnapshot(restored) == before)
        #expect(try fixture.context.fetch(FetchDescriptor<SyncTombstone>())
            .filter { $0.recordID == workID || $0.recordID == before.id }.isEmpty)
        #expect(titlesInOrder(fixture.queue) == ["Lined", "Library", "Queue only", "Third"])
        #expect(session.currentMembershipID == before.id)
    }

    // MARK: - Whole session

    @Test func undoEveryDecisionBackToTheStartRestoresTheQueueExactly() throws {
        let fixture = try makeFixture()
        var session = newSession(fixture)
        let snapshots = [fixture.mLibrary, fixture.mQueueOnly, fixture.mThird].map(QueueSortMembershipSnapshot.init)
        let order = titlesInOrder(fixture.queue)

        #expect(QueueSortNew.apply(.keep, session: &session, queue: fixture.queue, context: fixture.context))
        #expect(QueueSortNew.apply(.drop, session: &session, queue: fixture.queue, context: fixture.context))
        #expect(QueueSortNew.apply(.drop, session: &session, queue: fixture.queue, context: fixture.context))
        #expect(session.isFinished)
        #expect(session.count(of: .keep) == 1)
        #expect(session.count(of: .drop) == 2)
        #expect(fixture.queueOnly.isPendingDeletion)
        #expect(fixture.third.isPendingDeletion)
        // Nothing left to decide.
        #expect(!QueueSortNew.apply(.keep, session: &session, queue: fixture.queue, context: fixture.context))

        while QueueSortNew.undo(session: &session, queue: fixture.queue, context: fixture.context) != nil {}

        #expect(!session.canUndo)
        #expect(session.currentMembershipID == snapshots[0].id)
        #expect(titlesInOrder(fixture.queue) == order)
        for snapshot in snapshots {
            let membership = try #require(QueueSortNew.membership(snapshot.id, in: fixture.queue))
            #expect(QueueSortMembershipSnapshot(membership) == snapshot)
        }
        #expect(!fixture.queueOnly.isPendingDeletion)
        #expect(!fixture.third.isPendingDeletion)
        #expect(fixture.mLined.state == .inLine)
        let partition = ReadingQueueFacts.partition(memberships: ReadingQueueService.orderedMemberships(in: fixture.queue))
        #expect(partition.new.map(\.work.title) == ["Library", "Queue only", "Third"])
    }

    @Test func aWorkThatLeftTheQueueMidSessionIsSkipped() throws {
        let fixture = try makeFixture()
        var session = newSession(fixture)
        ReadingQueueService.removeFromQueue(fixture.library, from: fixture.queue, in: fixture.context)

        QueueSortNew.skipMissing(session: &session, queue: fixture.queue)
        #expect(session.currentMembershipID == fixture.mQueueOnly.id)
        #expect(!session.canUndo)
        #expect(session.count(of: .later) == 0)
    }
}
