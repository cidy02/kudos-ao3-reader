import CoreGraphics
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

    // MARK: - Session & Swipe

    @Test func sessionCountsProgressSegmentsAndSubtitle() {
        let ids = (0..<4).map { _ in UUID() }
        var session = QueueSortSession(queueID: UUID(), membershipIDs: ids + [ids[0]])
        #expect(session.total == 4)
        #expect(session.subtitle(queueName: "Summer Reading") == "1 of 4 · Summer Reading")
        #expect(session.segments == [.current, .upcoming, .upcoming, .upcoming])
        #expect(!session.canUndo)

        let keep = QueueSortRecord(
            membershipID: ids[0], workID: UUID(), action: .keep,
            before: nil, keepOutcome: nil, dropOutcome: nil
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

    @Test func swipeRequiresClearHorizontalIntent() {
        // Diagonal vertical scroll on a long card must neither tilt nor decide.
        let diagonalScroll = CGSize(width: -115, height: -260)
        #expect(!QueueSortSwipe.isHorizontalIntent(diagonalScroll))
        #expect(QueueSortSwipe.dragOffset(for: diagonalScroll) == 0)
        #expect(QueueSortSwipe.decision(for: diagonalScroll) == nil)

        // Even a shallow diagonal (dx < 1.5 * dy) must not trigger Drop/Keep.
        let shallowDiagonal = CGSize(width: 120, height: 100)
        #expect(!QueueSortSwipe.isHorizontalIntent(shallowDiagonal))
        #expect(QueueSortSwipe.decision(for: shallowDiagonal) == nil)

        // Clear horizontal swipe below threshold tilts without deciding.
        let shortSwipe = CGSize(width: 80, height: 10)
        #expect(QueueSortSwipe.dragOffset(for: shortSwipe) == 80)
        #expect(QueueSortSwipe.decision(for: shortSwipe) == nil)

        // Clear horizontal swipe past threshold keeps right / drops left.
        let keepSwipe = CGSize(width: 120, height: 20)
        #expect(QueueSortSwipe.dragOffset(for: keepSwipe) == 120)
        #expect(QueueSortSwipe.decision(for: keepSwipe) == .keep)

        let dropSwipe = CGSize(width: -120, height: -30)
        #expect(QueueSortSwipe.dragOffset(for: dropSwipe) == -120)
        #expect(QueueSortSwipe.decision(for: dropSwipe) == .drop)
    }

    @Test func voiceOverAnnouncementsDescribeActionAndHideConcealedTitles() {
        let ids = (0..<3).map { _ in UUID() }
        var session = QueueSortSession(queueID: UUID(), membershipIDs: ids)
        session.record(QueueSortRecord(
            membershipID: ids[0], workID: UUID(), action: .keep,
            before: nil, keepOutcome: nil, dropOutcome: nil
        ))
        #expect(session.announcement(after: .keep, nextTitle: "Second Fic", nextIsConcealed: false)
            == "Kept. Next: Second Fic, 2 of 3.")
        #expect(session.announcement(after: .later, nextTitle: "Secret Mature Fic", nextIsConcealed: true)
            == "Left for later. Next: hidden mature work, 2 of 3.")
        #expect(session.announcement(after: .drop, nextTitle: nil, nextIsConcealed: false)
            == "Dropped. All sorted.")
        #expect(session.undoAnnouncement(nextTitle: "First Fic", nextIsConcealed: false)
            == "Undone. First Fic, 2 of 3.")
        #expect(session.undoAnnouncement(nextTitle: "Secret Mature Fic", nextIsConcealed: true)
            == "Undone. Hidden mature work, 2 of 3.")
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
        #expect(undone.undoneRecord?.action == .keep)
        #expect(QueueSortMembershipSnapshot(fixture.mLibrary) == before)
        #expect(fixture.mLibrary.state == .new)
        #expect(fixture.mLibrary.origin?.label == "Holmes casefic")
        #expect(titlesInOrder(fixture.queue) == ["Lined", "Library", "Queue only", "Third"])
        #expect(session.currentMembershipID == fixture.mLibrary.id)
    }

    @Test func undoKeepPreservesInterveningNoteOriginAndQueuedAtEdits() throws {
        let fixture = try makeFixture()
        var session = newSession(fixture)
        let originalOrder = fixture.mLibrary.sortOrderInQueue

        #expect(QueueSortNew.apply(.keep, session: &session, queue: fixture.queue, context: fixture.context))

        let editedOrigin = ReadingQueueMembershipOrigin(kind: .link, label: "Shared rec")
        let editedQueuedAt = Date(timeIntervalSince1970: 1_700_000_000)
        fixture.mLibrary.note = "edited on iPad"
        fixture.mLibrary.origin = editedOrigin
        fixture.mLibrary.queuedAt = editedQueuedAt

        let result = QueueSortNew.undo(session: &session, queue: fixture.queue, context: fixture.context)
        #expect(result.undoneRecord?.action == .keep)
        #expect(fixture.mLibrary.state == .new)
        #expect(fixture.mLibrary.sortOrderInQueue == originalOrder)
        #expect(fixture.mLibrary.note == "edited on iPad")
        #expect(fixture.mLibrary.origin == editedOrigin)
        #expect(fixture.mLibrary.queuedAt == editedQueuedAt)
    }

    @Test func undoKeepRefusesWhenMembershipWasReorderedSinceKeep() throws {
        let fixture = try makeFixture()
        var session = newSession(fixture)

        #expect(QueueSortNew.apply(.keep, session: &session, queue: fixture.queue, context: fixture.context))
        fixture.mLibrary.sortOrderInQueue = 999

        let result = QueueSortNew.undo(session: &session, queue: fixture.queue, context: fixture.context)
        if case .blocked = result {} else { Issue.record("Expected blocked Undo after external reorder") }
        #expect(fixture.mLibrary.state == .inLine)
        #expect(fixture.mLibrary.sortOrderInQueue == 999)
        // Session stays on the next live work, not stranded on "All sorted".
        #expect(session.currentMembershipID == fixture.mQueueOnly.id)
        #expect(!session.isFinished)
        #expect(!session.canUndo)
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

        #expect(QueueSortNew.undo(
            session: &session, queue: fixture.queue, context: fixture.context
        ).undoneRecord?.action == .later)
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

        #expect(QueueSortNew.undo(
            session: &session, queue: fixture.queue, context: fixture.context
        ).undoneRecord?.action == .drop)
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

    @Test func dropOfAQueueOnlyWorkSendsItToRecentlyDeletedAndUndoRestoresWorkAndPreservedAt() throws {
        let fixture = try makeFixture()
        // Real EPUB file on disk with a distinct historical `preservedAt` so the
        // preservation-date restore branch is genuinely exercised (non-nil).
        let epubURL = fixture.queueOnly.fileURL
        try FileManager.default.createDirectory(
            at: epubURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("stub-epub-bytes".utf8).write(to: epubURL)
        defer { try? FileManager.default.removeItem(at: epubURL) }
        let originalPreservedAt = Date(timeIntervalSince1970: 1_710_000_000)
        fixture.queueOnly.hasEPUB = true
        fixture.queueOnly.epubPreservationStatus = .preserved
        fixture.queueOnly.preservedAt = originalPreservedAt

        var session = newSession(fixture)
        #expect(QueueSortNew.apply(.later, session: &session, queue: fixture.queue, context: fixture.context))
        let before = QueueSortMembershipSnapshot(fixture.mQueueOnly)
        let workID = fixture.queueOnly.id

        #expect(QueueSortNew.apply(.drop, session: &session, queue: fixture.queue, context: fixture.context))
        // Soft-deleted, never hard-deleted.
        let dropped = try #require(try fixture.context.fetch(FetchDescriptor<SavedWork>()).first { $0.id == workID })
        #expect(dropped.isPendingDeletion)
        #expect(dropped.permanentDeletionScheduledAt != nil)
        #expect(dropped.epubPreservationStatus == .notPreserved)
        #expect(dropped.preservedAt == nil)
        #expect(session.history.last?.sentWorkToRecentlyDeleted == true)
        let workTombstones = try fixture.context.fetch(FetchDescriptor<SyncTombstone>())
            .filter { $0.recordType == .savedWork && $0.recordID == workID }
        #expect(workTombstones.count == 1)

        #expect(QueueSortNew.undo(
            session: &session, queue: fixture.queue, context: fixture.context
        ).undoneRecord?.action == .drop)
        #expect(!dropped.isPendingDeletion)
        #expect(dropped.deletedAt == nil)
        #expect(dropped.permanentDeletionScheduledAt == nil)
        #expect(dropped.isQueuedForLater)
        #expect(dropped.epubPreservationStatus == .preserved)
        #expect(dropped.preservedAt == originalPreservedAt)
        let restored = try #require(QueueSortNew.membership(before.id, in: fixture.queue))
        #expect(QueueSortMembershipSnapshot(restored) == before)
        #expect(try fixture.context.fetch(FetchDescriptor<SyncTombstone>())
            .filter { $0.recordID == workID || $0.recordID == before.id }.isEmpty)
        #expect(titlesInOrder(fixture.queue) == ["Lined", "Library", "Queue only", "Third"])
        #expect(session.currentMembershipID == before.id)
    }

    @Test func dropOfQueueOnlyWorkInSecondQueueKeepsItAlive() throws {
        let fixture = try makeFixture()
        let secondQueue = ReadingQueue(name: "Weekend")
        fixture.context.insert(secondQueue)
        _ = ReadingQueueService.add(fixture.queueOnly, to: secondQueue, state: .inLine, in: fixture.context)

        var session = newSession(fixture)
        #expect(QueueSortNew.apply(.later, session: &session, queue: fixture.queue, context: fixture.context))
        let before = QueueSortMembershipSnapshot(fixture.mQueueOnly)

        #expect(QueueSortNew.apply(.drop, session: &session, queue: fixture.queue, context: fixture.context))
        #expect(!fixture.queueOnly.isPendingDeletion)
        #expect(fixture.queueOnly.deletedAt == nil)
        #expect(fixture.queueOnly.isQueuedForLater)
        #expect(session.history.last?.sentWorkToRecentlyDeleted == false)
        #expect(fixture.queueOnly.queueMemberships.contains { $0.queue?.id == secondQueue.id })
        #expect(!fixture.queueOnly.queueMemberships.contains { $0.queue?.id == fixture.queue.id })

        #expect(QueueSortNew.undo(
            session: &session, queue: fixture.queue, context: fixture.context
        ).undoneRecord?.action == .drop)
        #expect(QueueSortNew.membership(before.id, in: fixture.queue) != nil)
        #expect(fixture.queueOnly.queueMemberships.contains { $0.queue?.id == secondQueue.id })
    }

    // MARK: - Soft-delete, privacy, fly-out binding & intervening-mutation Undo
}

extension QueueSortNewTests {
    @Test func softDeletedWorkIsExcludedFromMembershipApplyAndSkipMissing() throws {
        let fixture = try makeFixture()
        var session = newSession(fixture)
        let membershipCountBefore = fixture.queue.memberships.count

        PreservedWorkService.softDelete(fixture.library, in: fixture.context)
        // Soft-deleting a work keeps its queue memberships so Restore re-joins.
        #expect(fixture.queue.memberships.count == membershipCountBefore)
        #expect(QueueSortNew.membership(fixture.mLibrary.id, in: fixture.queue) == nil)
        #expect(!QueueSortNew.apply(.keep, session: &session, queue: fixture.queue, context: fixture.context))
        #expect(!QueueSortNew.apply(.drop, session: &session, queue: fixture.queue, context: fixture.context))
        #expect(fixture.mLibrary.state == .new)
        #expect(fixture.library.queueMemberships.contains { $0.id == fixture.mLibrary.id })

        QueueSortNew.skipMissing(session: &session, queue: fixture.queue)
        #expect(session.currentMembershipID == fixture.mQueueOnly.id)
    }

    @Test func hideMatureVisibilitySkipsHiddenWorksAndAllowsUndoOnceRevealed() throws {
        let fixture = try makeFixture()
        fixture.library.rating = "Explicit"
        var session = newSession(fixture)

        QueueSortNew.skipMissing(session: &session, queue: fixture.queue) { !$0.isAdult }
        #expect(session.currentMembershipID == fixture.mQueueOnly.id)

        // Keep then hide -> Undo reports .hidden without permanently blocking the step.
        #expect(QueueSortNew.apply(.keep, session: &session, queue: fixture.queue, context: fixture.context))
        fixture.queueOnly.rating = "Mature"
        try fixture.context.save()
        let hiddenKeep = QueueSortNew.undo(
            session: &session, queue: fixture.queue, context: fixture.context
        ) { !$0.isAdult }
        if case .hidden = hiddenKeep {} else { Issue.record("Expected .hidden Undo for concealed mature work") }
        #expect(fixture.mQueueOnly.state == .inLine)
        #expect(session.canUndo)
        #expect(!session.unrevisitableIDs.contains(fixture.mQueueOnly.id))
        #expect(session.currentMembershipID == fixture.mThird.id)

        // Revealing the work again lets the same Undo succeed.
        let revealedKeep = QueueSortNew.undo(
            session: &session, queue: fixture.queue, context: fixture.context
        ) { _ in true }
        #expect(revealedKeep.undoneRecord?.action == .keep)
        #expect(fixture.mQueueOnly.state == .new)
        #expect(session.currentMembershipID == fixture.mQueueOnly.id)

        // Same for Drop of a queue-only work when its reveal lapses and then returns.
        #expect(QueueSortNew.apply(.drop, session: &session, queue: fixture.queue, context: fixture.context))
        let hiddenDrop = QueueSortNew.undo(
            session: &session, queue: fixture.queue, context: fixture.context
        ) { !$0.isAdult }
        if case .hidden = hiddenDrop {} else { Issue.record("Expected .hidden Undo for dropped mature work") }
        #expect(fixture.queueOnly.isPendingDeletion)
        #expect(session.canUndo)

        let revealedDrop = QueueSortNew.undo(
            session: &session, queue: fixture.queue, context: fixture.context
        ) { _ in true }
        #expect(revealedDrop.undoneRecord?.action == .drop)
        #expect(!fixture.queueOnly.isPendingDeletion)
        #expect(QueueSortNew.membership(fixture.mQueueOnly.id, in: fixture.queue) != nil)
        #expect(session.currentMembershipID == fixture.mQueueOnly.id)
    }

    private static let schema = Schema([
        SavedWork.self, Tag.self, Bookmark.self, CustomFont.self, WorkCollection.self,
        ReadingQueue.self, ReadingQueueMembership.self, SavedSearch.self,
        QueueSavedSearchLink.self, SyncTombstone.self, ReadingAnnotation.self,
        ReadingSession.self, ReadingFavorite.self, FandomReadWatermark.self
    ])

    /// A queue-only work Dropped in a store on disk (writable), then the same store reopened
    /// read-only: SwiftData itself refuses that context's save, with a thrown error.
    @Test func undoQueueOnlyDropRollsBackOnARealThrowingSaveAndCanBeRetried() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sortnew-undo-\(UUID().uuidString).store")
        let writable = ModelContext(try ModelContainer(
            for: Self.schema, configurations: [ModelConfiguration(schema: Self.schema, url: url)]
        ))
        let queue = ReadingQueue(name: "Summer Reading")
        writable.insert(queue)
        let work = SavedWork(title: "Queue only", author: "Author")
        writable.insert(work)
        let membership = ReadingQueueService.add(work, to: queue, state: .new, in: writable)
        try writable.save()
        let queueID = queue.id
        let workID = work.id
        let membershipID = membership.id

        var session = QueueSortSession(queueID: queueID, membershipIDs: [membershipID])
        #expect(QueueSortNew.apply(.drop, session: &session, queue: queue, context: writable))
        try writable.save()
        let syncSuite = "QueueSortNewTests.atomic.\(UUID().uuidString)"
        let syncDefaults = try #require(UserDefaults(suiteName: syncSuite))
        defer { syncDefaults.removePersistentDomain(forName: syncSuite) }

        let readOnly = ModelContext(try ModelContainer(
            for: Self.schema,
            configurations: [ModelConfiguration(schema: Self.schema, url: url, allowsSave: false)]
        ))
        let roQueue = try #require(try readOnly.fetch(FetchDescriptor<ReadingQueue>()).first { $0.id == queueID })
        let roWork = try #require(try readOnly.fetch(FetchDescriptor<SavedWork>()).first { $0.id == workID })
        #expect(roWork.isPendingDeletion)

        let outcome = QueueSortNew.undo(
            session: &session, queue: roQueue, context: readOnly, syncDefaults: syncDefaults
        )
        if case .saveFailed = outcome {} else { Issue.record("Expected .saveFailed, got \(outcome)") }
        #expect(roWork.isPendingDeletion)
        #expect(roWork.queueMemberships.isEmpty)
        #expect(!readOnly.hasChanges)
        #expect(QueueSortNew.membership(membershipID, in: roQueue) == nil)
        let tombstones = try readOnly.fetch(FetchDescriptor<SyncTombstone>())
        #expect(tombstones.contains { $0.recordType == .savedWork && $0.recordID == workID })
        #expect(!FolderSyncService.snapshot(defaults: syncDefaults).isDirty)

        // Not burnt: the step is still undoable, and works once saving does.
        #expect(session.canUndo)
        #expect(session.unrevisitableIDs.isEmpty)
        let retry = QueueSortNew.undo(session: &session, queue: queue, context: writable, syncDefaults: syncDefaults)
        #expect(retry.undoneRecord?.action == .drop)
        #expect(!work.isPendingDeletion)
    }

    @Test func undoNeverCommitsOrDiscardsChangesThatAreNotItsOwn() throws {
        let fixture = try makeFixture()
        var session = newSession(fixture)
        #expect(QueueSortNew.apply(.keep, session: &session, queue: fixture.queue, context: fixture.context))
        try fixture.context.save()

        // Something else left a change pending (say a Recently Deleted restore whose save failed).
        fixture.third.title = "Pending elsewhere"
        let refused = QueueSortNew.undo(session: &session, queue: fixture.queue, context: fixture.context)
        if case .saveFailed = refused {} else { Issue.record("Expected .saveFailed, got \(refused)") }
        #expect(fixture.third.title == "Pending elsewhere")
        #expect(fixture.context.hasChanges)
        #expect(fixture.mLibrary.state == .inLine)
        #expect(session.canUndo)

        // Once that is saved by whoever owns it, the same Undo goes through.
        try fixture.context.save()
        #expect(QueueSortNew.undo(session: &session, queue: fixture.queue, context: fixture.context)
            .undoneRecord?.action == .keep)
        #expect(fixture.mLibrary.state == .new)
    }

    @Test func aHiddenStepPassedOverStaysUndoableOnceRevealedInTheSameSession() throws {
        let fixture = try makeFixture()
        var session = newSession(fixture)
        #expect(QueueSortNew.apply(.keep, session: &session, queue: fixture.queue, context: fixture.context))
        #expect(QueueSortNew.apply(.drop, session: &session, queue: fixture.queue, context: fixture.context))
        #expect(fixture.queueOnly.isPendingDeletion)

        fixture.queueOnly.rating = "Explicit"
        try fixture.context.save()
        let first = QueueSortNew.undo(
            session: &session, queue: fixture.queue, context: fixture.context
        ) { !$0.isAdult }
        guard case .undoneSkippingHidden = first else { Issue.record("got \(first)"); return }
        #expect(fixture.mLibrary.state == .new)
        #expect(fixture.queueOnly.isPendingDeletion)
        #expect(session.canUndo)

        // Revealed again: the Drop that was passed over can now be undone.
        let second = QueueSortNew.undo(session: &session, queue: fixture.queue, context: fixture.context)
        #expect(second.undoneRecord?.action == .drop)
        #expect(!fixture.queueOnly.isPendingDeletion)
        #expect(QueueSortNew.membership(fixture.mQueueOnly.id, in: fixture.queue) != nil)
    }

    @Test func undoPassesOverAHiddenNewestStepToUndoTheEarlierOne() throws {
        let fixture = try makeFixture()
        var session = newSession(fixture)
        #expect(QueueSortNew.apply(.keep, session: &session, queue: fixture.queue, context: fixture.context))
        #expect(QueueSortNew.apply(.keep, session: &session, queue: fixture.queue, context: fixture.context))
        #expect(fixture.mLibrary.state == .inLine)
        #expect(fixture.mQueueOnly.state == .inLine)

        // The newest step is on a work that is now hidden; the earlier one is not.
        fixture.queueOnly.rating = "Explicit"
        try fixture.context.save()
        let result = QueueSortNew.undo(
            session: &session, queue: fixture.queue, context: fixture.context
        ) { !$0.isAdult }
        guard case let .undoneSkippingHidden(record, skipped) = result else {
            Issue.record("Expected Undo to pass over the hidden step, got \(result)")
            return
        }
        #expect(record.membershipID == fixture.mLibrary.id)
        #expect(skipped == 1)
        #expect(result.undoneRecord == record)
        #expect(fixture.mLibrary.state == .new)
        #expect(fixture.mQueueOnly.state == .inLine)
        #expect(session.currentMembershipID == fixture.mLibrary.id)
        #expect(QueueSortSession.skippedHiddenNotice(count: 1).contains("1 newer step was"))

        // Every step hidden: still .hidden, and still undoable once revealed.
        var onlyHidden = newSession(fixture)
        QueueSortNew.skipMissing(session: &onlyHidden, queue: fixture.queue)
        #expect(QueueSortNew.apply(.later, session: &onlyHidden, queue: fixture.queue, context: fixture.context))
        fixture.library.rating = "Explicit"
        try fixture.context.save()
        let allHidden = QueueSortNew.undo(
            session: &onlyHidden, queue: fixture.queue, context: fixture.context
        ) { !$0.isAdult }
        if case .hidden = allHidden {} else { Issue.record("Expected .hidden, got \(allHidden)") }
        #expect(onlyHidden.canUndo)
    }

    @Test(arguments: [true, false])
    func undoDropRefusesAPeerDeleteThatSyncedInAfterTheDropEvenWhenOlder(queueOnly: Bool) throws {
        let fixture = try makeFixture()
        var session = newSession(fixture)
        let target = queueOnly ? fixture.mQueueOnly : fixture.mLibrary
        if queueOnly {
            #expect(QueueSortNew.apply(.later, session: &session, queue: fixture.queue, context: fixture.context))
        }
        let work = try #require(target.work)
        let membershipID = target.id
        #expect(QueueSortNew.apply(.drop, session: &session, queue: fixture.queue, context: fixture.context))
        #expect(work.isPendingDeletion == queueOnly)

        // A peer's delete of the same record arrives after the Drop, stamped BEFORE it.
        let older = Date().addingTimeInterval(-3_600)
        fixture.context.insert(SyncTombstone(
            recordID: queueOnly ? work.id : membershipID,
            recordType: queueOnly ? .savedWork : .readingQueueMembership,
            createdAt: older, deletedOnDeviceID: "peer-device", deletionReason: "test"
        ))
        try fixture.context.save()

        let outcome = QueueSortNew.undo(session: &session, queue: fixture.queue, context: fixture.context)
        if case .blocked = outcome {} else { Issue.record("Expected .blocked, got \(outcome)") }
        #expect(work.isPendingDeletion == queueOnly)
        #expect(QueueSortNew.membership(membershipID, in: fixture.queue) == nil)
    }

    @Test func membershipMovedOutOfNewIsSkippedAndNoOpKeepUndoDoesNotBumpModified() throws {
        let fixture = try makeFixture()
        let syncSuite = "QueueSortNewTests.noop.\(UUID().uuidString)"
        let syncDefaults = try #require(UserDefaults(suiteName: syncSuite))
        syncDefaults.removePersistentDomain(forName: syncSuite)
        defer { syncDefaults.removePersistentDomain(forName: syncSuite) }

        var session = newSession(fixture)
        // External move to In line (e.g. Work Details or sync) before the card is decided.
        ReadingQueueService.sortIntoLine(fixture.mLibrary, in: fixture.queue, context: fixture.context)
        let movedModifiedAt = fixture.mLibrary.lastModifiedAt

        #expect(!QueueSortNew.apply(.keep, session: &session, queue: fixture.queue, context: fixture.context))
        #expect(fixture.mLibrary.lastModifiedAt == movedModifiedAt)
        QueueSortNew.skipMissing(session: &session, queue: fixture.queue)
        #expect(session.currentMembershipID == fixture.mQueueOnly.id)

        // Later followed by external move to In line blocks Undo of Later.
        #expect(QueueSortNew.apply(.later, session: &session, queue: fixture.queue, context: fixture.context))
        ReadingQueueService.sortIntoLine(fixture.mQueueOnly, in: fixture.queue, context: fixture.context)
        let laterUndo = QueueSortNew.undo(session: &session, queue: fixture.queue, context: fixture.context)
        if case .blocked = laterUndo {} else { Issue.record("Expected blocked Undo of Later after move to In line") }

        // A no-op Keep (when requiresNewState == false, e.g. already In line) must not bump timestamps on Undo.
        let pastStamp = Date(timeIntervalSince1970: 1_700_000_000)
        fixture.mLined.lastModifiedAt = pastStamp
        fixture.queue.lastMembershipChangedAt = pastStamp
        try fixture.context.save()

        var nonNewSession = QueueSortSession(
            queueID: fixture.queue.id, membershipIDs: [fixture.mLined.id], requiresNewState: false
        )
        #expect(QueueSortNew.apply(
            .keep, session: &nonNewSession, queue: fixture.queue, context: fixture.context, syncDefaults: syncDefaults
        ))
        #expect(fixture.mLined.lastModifiedAt == pastStamp)
        let undoNoOp = QueueSortNew.undo(
            session: &nonNewSession, queue: fixture.queue, context: fixture.context, syncDefaults: syncDefaults
        )
        #expect(undoNoOp.undoneRecord?.action == .keep)
        #expect(fixture.mLined.lastModifiedAt == pastStamp)
        #expect(fixture.queue.lastMembershipChangedAt == pastStamp)
        #expect(!FolderSyncService.snapshot(defaults: syncDefaults).isDirty)
    }

    @Test func applyRejectsMismatchedExpectedWorkOrMembershipID() throws {
        let fixture = try makeFixture()
        var session = newSession(fixture)

        #expect(!QueueSortNew.apply(
            .drop, session: &session, queue: fixture.queue, context: fixture.context,
            expectedMembershipID: fixture.mLibrary.id, expectedWorkID: fixture.queueOnly.id
        ))
        #expect(QueueSortNew.membership(fixture.mLibrary.id, in: fixture.queue) != nil)

        // Simulate M0 vanishing during fly-out and cursor advancing to M1:
        ReadingQueueService.removeFromQueue(fixture.library, from: fixture.queue, in: fixture.context)
        QueueSortNew.skipMissing(session: &session, queue: fixture.queue)
        #expect(session.currentMembershipID == fixture.mQueueOnly.id)

        #expect(!QueueSortNew.apply(
            .drop, session: &session, queue: fixture.queue, context: fixture.context,
            expectedMembershipID: fixture.mLibrary.id, expectedWorkID: fixture.library.id
        ))
        // M1 was NOT dropped unseen.
        #expect(QueueSortNew.membership(fixture.mQueueOnly.id, in: fixture.queue) != nil)
        #expect(!fixture.queueOnly.isPendingDeletion)
    }

    @Test func undoRefusesWhenLibraryWorkWasSoftDeletedAfterDrop() throws {
        let fixture = try makeFixture()
        var session = newSession(fixture)

        #expect(QueueSortNew.apply(.drop, session: &session, queue: fixture.queue, context: fixture.context))
        PreservedWorkService.softDelete(fixture.library, in: fixture.context)
        let deletedModifiedAt = fixture.library.lastModifiedAt

        let outcome = QueueSortNew.undo(session: &session, queue: fixture.queue, context: fixture.context)
        if case .blocked = outcome {} else { Issue.record("Expected blocked Undo for soft-deleted library work") }
        #expect(fixture.library.isPendingDeletion)
        #expect(fixture.library.lastModifiedAt == deletedModifiedAt)
        #expect(fixture.library.queueMemberships.isEmpty)
        #expect(session.currentMembershipID == fixture.mQueueOnly.id)
        #expect(!session.isFinished)
    }

    @Test func undoRefusesWhenQueueOnlyWorkWasRestoredAndReDeletedLocally() throws {
        let fixture = try makeFixture()
        var session = newSession(fixture)
        #expect(QueueSortNew.apply(.later, session: &session, queue: fixture.queue, context: fixture.context))
        #expect(QueueSortNew.apply(.drop, session: &session, queue: fixture.queue, context: fixture.context))

        PreservedWorkService.restore(fixture.queueOnly, in: fixture.context)
        PreservedWorkService.softDelete(fixture.queueOnly, in: fixture.context)

        let outcome = QueueSortNew.undo(session: &session, queue: fixture.queue, context: fixture.context)
        if case .blocked = outcome {} else { Issue.record("Expected blocked Undo after local restore + re-delete") }
        #expect(fixture.queueOnly.isPendingDeletion)
        #expect(QueueSortNew.membership(fixture.mQueueOnly.id, in: fixture.queue) == nil)
        #expect(session.currentMembershipID == fixture.mThird.id)
    }

    @Test func undoRefusesWhenQueueWasSoftDeletedAfterDrop() throws {
        let fixture = try makeFixture()
        var session = newSession(fixture)
        #expect(QueueSortNew.apply(.later, session: &session, queue: fixture.queue, context: fixture.context))
        #expect(QueueSortNew.apply(.drop, session: &session, queue: fixture.queue, context: fixture.context))

        PreservedWorkService.softDelete(fixture.queue, in: fixture.context)
        let queueUpdatedAt = fixture.queue.dateUpdated

        let outcome = QueueSortNew.undo(session: &session, queue: fixture.queue, context: fixture.context)
        if case .blocked = outcome {} else { Issue.record("Expected blocked Undo on soft-deleted queue") }
        #expect(fixture.queueOnly.isPendingDeletion)
        #expect(fixture.queue.dateUpdated == queueUpdatedAt)
        #expect(fixture.queueOnly.queueMemberships.isEmpty)
    }

    @Test func undoAfterExternalRemovalOrReAddKeepsSessionConsistentWithoutPrematureFinish() throws {
        // Case 1: Keep A, then A leaves the queue; Undo fails without landing on "All sorted".
        let fixture1 = try makeFixture()
        var session1 = newSession(fixture1)
        #expect(QueueSortNew.apply(.keep, session: &session1, queue: fixture1.queue, context: fixture1.context))
        ReadingQueueService.removeFromQueue(fixture1.library, from: fixture1.queue, in: fixture1.context)

        let outcome1 = QueueSortNew.undo(session: &session1, queue: fixture1.queue, context: fixture1.context)
        if case .blocked = outcome1 {} else { Issue.record("Expected blocked Undo when kept work left queue") }
        #expect(session1.currentMembershipID == fixture1.mQueueOnly.id)
        #expect(!session1.isFinished)
        #expect(!session1.canUndo)

        // Case 2: Drop A, then A is re-added under a new membership UUID; Undo refuses and leaves new membership.
        let fixture2 = try makeFixture()
        var session2 = newSession(fixture2)
        let oldID = fixture2.mLibrary.id
        #expect(QueueSortNew.apply(.drop, session: &session2, queue: fixture2.queue, context: fixture2.context))
        let replacement = ReadingQueueService.add(
            fixture2.library, to: fixture2.queue, state: .inLine, in: fixture2.context
        )
        #expect(replacement.id != oldID)

        let outcome2 = QueueSortNew.undo(session: &session2, queue: fixture2.queue, context: fixture2.context)
        if case .blocked = outcome2 {} else { Issue.record("Expected blocked Undo when work was re-added") }
        #expect(fixture2.library.queueMemberships.map(\.id) == [replacement.id])
        #expect(session2.currentMembershipID == fixture2.mQueueOnly.id)
        #expect(!session2.isFinished)

        // Case 3: Keep A, Drop B, permanently delete B -> Undo #1 blocks B (stays on C), Undo #2 undoes A cleanly.
        let fixture3 = try makeFixture()
        var session3 = newSession(fixture3)
        #expect(QueueSortNew.apply(.keep, session: &session3, queue: fixture3.queue, context: fixture3.context))
        #expect(QueueSortNew.apply(.drop, session: &session3, queue: fixture3.queue, context: fixture3.context))
        PreservedWorkService.deletePermanently(fixture3.queueOnly, in: fixture3.context)

        let blockedB = QueueSortNew.undo(session: &session3, queue: fixture3.queue, context: fixture3.context)
        if case .blocked(let rec) = blockedB {
            #expect(rec.membershipID == fixture3.mQueueOnly.id)
        } else {
            Issue.record("Expected blocked Undo for permanently deleted B")
        }
        #expect(session3.currentMembershipID == fixture3.mThird.id)
        #expect(session3.canUndo)

        let undoneA = QueueSortNew.undo(session: &session3, queue: fixture3.queue, context: fixture3.context)
        #expect(undoneA.undoneRecord?.membershipID == fixture3.mLibrary.id)
        #expect(session3.currentMembershipID == fixture3.mLibrary.id)
        #expect(QueueSortNew.apply(.later, session: &session3, queue: fixture3.queue, context: fixture3.context))
        QueueSortNew.skipMissing(session: &session3, queue: fixture3.queue)
        #expect(session3.currentMembershipID == fixture3.mThird.id)
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

        var undoneCount = 0
        while case .undone = QueueSortNew.undo(session: &session, queue: fixture.queue, context: fixture.context) {
            undoneCount += 1
        }
        #expect(undoneCount == 3)

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
        let partition = ReadingQueueFacts.partition(
            memberships: ReadingQueueService.orderedMemberships(in: fixture.queue)
        )
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
