import Foundation
import SwiftData
import Testing
@testable import Kudos

@MainActor
struct ReadingQueueTests {
    final class BundleAnchor {}

    private var sampleEPUB: URL {
        get throws {
            try #require(Bundle(for: BundleAnchor.self).url(forResource: "sample", withExtension: "epub"))
        }
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func summary(_ id: Int, seriesURL: String? = nil) -> AO3WorkSummary {
        AO3WorkSummary(
            id: id,
            title: "Series Work \(id)",
            authors: ["Writer"],
            fandoms: ["Fandom"],
            rating: "Teen And Up Audiences",
            warnings: ["No Archive Warnings Apply"],
            categories: [],
            isComplete: true,
            dateUpdated: "2026-06-30",
            tags: ["Freeform"],
            summary: "Summary \(id)",
            language: "English",
            words: 1_000,
            chapters: "1/1",
            comments: nil,
            kudos: nil,
            hits: nil,
            seriesTitle: "Series",
            seriesURL: seriesURL,
            seriesPosition: id
        )
    }

    @Test func queueOnlyWorkStaysOutOfNormalLibrarySections() throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let work = SavedWork(
            title: "Queue Only",
            author: "Writer",
            sourceURL: "https://archiveofourown.org/works/123"
        )
        work.hasEPUB = true
        work.lastReadDate = Date()
        work.lastScrollFraction = 0.4
        work.isFinished = true
        context.insert(work)
        try Data("queue-only".utf8).write(to: work.fileURL)
        defer { try? FileManager.default.removeItem(at: work.fileURL) }
        let queue = ReadingQueueService.ensureSavedForLaterQueue(in: context)
        ReadingQueueService.add(work, to: queue, in: context)

        let works = [work]
        let visible: (SavedWork) -> Bool = { _ in true }

        #expect(LibrarySectionKind.savedForLater.works(from: works, visible: visible).map(\.id) == [work.id])
        #expect(LibrarySectionKind.readingNow.works(from: works, visible: visible).isEmpty)
        #expect(LibrarySectionKind.finished.works(from: works, visible: visible).isEmpty)
        #expect(LibrarySectionKind.downloaded.works(from: works, visible: visible).isEmpty)

        work.isSaved = true
        #expect(LibrarySectionKind.downloaded.works(from: works, visible: visible).map(\.id) == [work.id])
    }

    @Test func duplicateMembershipsAreNotCreated() throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let work = SavedWork(title: "One Queue Entry", author: "Writer")
        context.insert(work)
        let queue = ReadingQueueService.ensureSavedForLaterQueue(in: context)

        let first = ReadingQueueService.add(work, to: queue, in: context)
        let second = ReadingQueueService.add(work, to: queue, in: context)

        #expect(first.id == second.id)
        #expect(work.queueMemberships.count == 1)
        #expect(queue.memberships.count == 1)
    }

    @Test func reorderRewritesSortOrderAndMarksMembershipsPending() throws {
        let context = try makeContext()
        let queue = ReadingQueueService.createQueue(named: "Reorder Test", in: context)
        let works = (1 ... 3).map { SavedWork(title: "Work \($0)", author: "Writer") }
        for work in works {
            context.insert(work)
            ReadingQueueService.add(work, to: queue, in: context)
        }
        // Insertion order: Work 1, 2, 3 (sortOrderInQueue 0, 1, 2).
        #expect(queue.memberships.sorted { $0.sortOrderInQueue < $1.sortOrderInQueue }.compactMap(\.work?.title)
            == ["Work 1", "Work 2", "Work 3"])
        for membership in queue.memberships {
            membership.syncStatusRaw = SyncRecordStatus.synced.rawValue
        }

        // Drag Work 3 to the front.
        let newOrder = [works[2].id, works[0].id, works[1].id]
        ReadingQueueService.reorder(newOrder, in: queue, context: context)

        #expect(queue.memberships.sorted { $0.sortOrderInQueue < $1.sortOrderInQueue }.compactMap(\.work?.title)
            == ["Work 3", "Work 1", "Work 2"])
        // A user-dragged reorder is a real local change — it must be visible to sync,
        // not silently dropped because nothing else about the membership changed.
        #expect(queue.memberships.allSatisfy { $0.syncStatus == .pending })
    }

    @Test func reorderIgnoresUnknownWorkIDs() throws {
        let context = try makeContext()
        let queue = ReadingQueueService.createQueue(named: "Reorder Test", in: context)
        let work = SavedWork(title: "Solo Work", author: "Writer")
        context.insert(work)
        ReadingQueueService.add(work, to: queue, in: context)

        // A stale/unrelated UUID in the dragged order (e.g. a work removed mid-drag)
        // must not crash or corrupt the real membership's order.
        ReadingQueueService.reorder([UUID(), work.id], in: queue, context: context)

        #expect(queue.memberships.first?.sortOrderInQueue == 1)
    }

    // MARK: - moveOffsets (compact-grid VoiceOver Move Up/Down/to Top/to Bottom actions)

    @Test func moveOffsetsForwardAddsOneToToOffset() {
        // Matches WorkReorderDropDelegate.dropEntered's own convention: moving an
        // item later in the array needs toOffset past the gap the removal leaves.
        let result = ReadingQueueService.moveOffsets(currentIndex: 0, requestedIndex: 2, count: 4)
        #expect(result?.from == IndexSet(integer: 0))
        #expect(result?.to == 3)
    }

    @Test func moveOffsetsBackwardUsesRequestedIndexDirectly() {
        let result = ReadingQueueService.moveOffsets(currentIndex: 3, requestedIndex: 1, count: 4)
        #expect(result?.from == IndexSet(integer: 3))
        #expect(result?.to == 1)
    }

    @Test func moveOffsetsClampsPastTheEndToTheLastIndex() {
        // "Move to Bottom" from anywhere requests count-1; also covers a Move Down
        // that overshoots the array (should land on the last index, not go out of bounds).
        let result = ReadingQueueService.moveOffsets(currentIndex: 1, requestedIndex: 99, count: 4)
        #expect(result?.from == IndexSet(integer: 1))
        #expect(result?.to == 4) // last index (3) + 1, since it's a forward move
    }

    @Test func moveOffsetsClampsBeforeTheStartToZero() {
        let result = ReadingQueueService.moveOffsets(currentIndex: 2, requestedIndex: -99, count: 4)
        #expect(result?.from == IndexSet(integer: 2))
        #expect(result?.to == 0)
    }

    @Test func moveOffsetsIsANoOpAlreadyAtTheRequestedIndex() {
        #expect(ReadingQueueService.moveOffsets(currentIndex: 2, requestedIndex: 2, count: 4) == nil)
    }

    @Test func moveOffsetsIsANoOpMovingUpFromTheTop() {
        // The Move Up action at index 0 requests index -1, which clamps back to 0 —
        // the same index it's already at, so this must be a safe no-op, not a crash.
        #expect(ReadingQueueService.moveOffsets(currentIndex: 0, requestedIndex: -1, count: 4) == nil)
    }

    @Test func moveOffsetsIsANoOpMovingDownFromTheBottom() {
        #expect(ReadingQueueService.moveOffsets(currentIndex: 3, requestedIndex: 4, count: 4) == nil)
    }

    @Test func moveOffsetsIsANoOpOnAnEmptyQueue() {
        #expect(ReadingQueueService.moveOffsets(currentIndex: 0, requestedIndex: 0, count: 0) == nil)
    }

    @Test func queuedWorkKeepsEPUBWhenMarkedFinished() throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let work = SavedWork(
            title: "Protected Queue Work",
            author: "Writer",
            sourceURL: "https://archiveofourown.org/works/456"
        )
        work.hasEPUB = true
        context.insert(work)
        try Data("queued-finished".utf8).write(to: work.fileURL)
        defer { try? FileManager.default.removeItem(at: work.fileURL) }

        let queue = ReadingQueueService.ensureSavedForLaterQueue(in: context)
        ReadingQueueService.add(work, to: queue, in: context)

        WorkLifecycle.markFinished(work, in: context)

        #expect(work.isFinished)
        #expect(work.hasEPUB)
        #expect(FileManager.default.fileExists(atPath: work.fileURL.path))
        #expect(work.epubPreservationStatus == .preserved)
    }

    @Test func removeLastQueueMembershipDoesNotDeleteWorkByDefault() throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let work = SavedWork(
            title: "Queue Only Removal",
            author: "Writer",
            sourceURL: "https://archiveofourown.org/works/654"
        )
        work.hasEPUB = true
        context.insert(work)
        try Data("queue-only-removal".utf8).write(to: work.fileURL)
        let fileURL = work.fileURL

        let queue = ReadingQueueService.ensureSavedForLaterQueue(in: context)
        ReadingQueueService.add(work, to: queue, in: context)

        ReadingQueueService.removeFromQueue(work, from: queue, in: context)

        let restored = try #require(try context.fetch(FetchDescriptor<SavedWork>()).first)
        #expect(restored.id == work.id)
        #expect(!restored.isQueuedForLater)
        #expect(restored.queueMemberships.isEmpty)
        #expect(queue.memberships.isEmpty)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func removeLastQueueMembershipDestructiveVariantDeletesQueueOnlyWork() throws {
        let context = try makeContext()

        let work = SavedWork(
            title: "Queue Only Destructive Removal",
            author: "Writer",
            sourceURL: "https://archiveofourown.org/works/655"
        )
        work.hasEPUB = true
        context.insert(work)
        try Data("queue-only-destruction".utf8).write(to: work.fileURL)
        let fileURL = work.fileURL

        let queue = ReadingQueueService.ensureSavedForLaterQueue(in: context)
        ReadingQueueService.add(work, to: queue, in: context)

        ReadingQueueService.removeFromQueueAndDeleteIfQueueOnly(work, from: queue, in: context)

        // Deletion now moves the work to Recently Deleted (PreservedWorkService.softDelete)
        // rather than an instant, unrecoverable removal — the record and its EPUB both
        // survive the 90-day recovery window.
        let remaining = try context.fetch(FetchDescriptor<SavedWork>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.isPendingDeletion == true)
        #expect(queue.memberships.isEmpty)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func detailRemovalPathRevivesQueueOnlyWorkBeforeMutation() throws {
        // Work Details' "Remove from Later" can soft-delete a queue-only work
        // while the detail screen stays bound to it. Any later mutation from
        // that screen must revive the record first (restore + act), never
        // mutate it while hidden — docs/DATA_AND_PERSISTENCE_INVARIANTS.md.
        let context = try makeContext()

        let work = SavedWork(
            title: "Detail Removal Revive",
            author: "Writer",
            sourceURL: "https://archiveofourown.org/works/656"
        )
        work.hasEPUB = true
        context.insert(work)

        let queue = ReadingQueueService.ensureSavedForLaterQueue(in: context)
        ReadingQueueService.add(work, to: queue, in: context)
        ReadingQueueService.removeFromQueueAndDeleteIfQueueOnly(work, from: queue, in: context)

        #expect(work.isPendingDeletion)
        #expect(try context.fetch(FetchDescriptor<SyncTombstone>()).contains { $0.recordID == work.id })

        // The view's withLocalWork guard: revive, then run the action (Save).
        PreservedWorkService.restore(work, in: context)
        WorkLifecycle.setSaved(work, true, in: context)

        #expect(!work.isPendingDeletion)
        #expect(work.deletedAt == nil)
        #expect(work.isSaved)
        #expect(!(try context.fetch(FetchDescriptor<SyncTombstone>()).contains { $0.recordID == work.id }))
    }

    @Test func orderedWorksProjectionSortsAndSkipsSoftDeleted() throws {
        let context = try makeContext()
        let queue = ReadingQueueService.createQueue(named: "Projection", in: context)

        let first = SavedWork(title: "First", author: "A",
                              sourceURL: "https://archiveofourown.org/works/661")
        let second = SavedWork(title: "Second", author: "B",
                               sourceURL: "https://archiveofourown.org/works/662")
        let hidden = SavedWork(title: "Hidden", author: "C",
                               sourceURL: "https://archiveofourown.org/works/663")
        for work in [first, second, hidden] {
            context.insert(work)
            ReadingQueueService.add(work, to: queue, in: context)
        }
        // Reverse the assigned order so the sort is actually exercised.
        ReadingQueueService.reorder([second.id, first.id, hidden.id], in: queue, context: context)
        PreservedWorkService.softDelete(hidden, in: context)

        let ordered = ReadingQueueService.orderedWorks(in: queue)
        #expect(ordered.map(\.title) == ["Second", "First"])
    }

    @Test func removeOneQueueMembershipKeepsWorkIfOtherMembershipExists() throws {
        let context = try makeContext()
        let work = SavedWork(
            title: "Two Queue Work",
            author: "Writer",
            sourceURL: "https://archiveofourown.org/works/656"
        )
        context.insert(work)
        let firstQueue = ReadingQueueService.ensureSavedForLaterQueue(in: context)
        let secondQueue = ReadingQueueService.createQueue(named: "Weekend", in: context)
        ReadingQueueService.add(work, to: firstQueue, in: context)
        ReadingQueueService.add(work, to: secondQueue, in: context)

        ReadingQueueService.removeFromQueue(work, from: firstQueue, in: context)

        #expect(work.isQueuedForLater)
        #expect(work.queueMemberships.count == 1)
        #expect(work.queueMemberships.first?.queue?.id == secondQueue.id)
        #expect(try context.fetch(FetchDescriptor<SavedWork>()).first?.id == work.id)
    }

    @Test func removeLastQueueMembershipRecomputesQueueFlag() throws {
        let context = try makeContext()
        let work = SavedWork(
            title: "Queue Flag Work",
            author: "Writer",
            sourceURL: "https://archiveofourown.org/works/657"
        )
        context.insert(work)
        let queue = ReadingQueueService.ensureSavedForLaterQueue(in: context)
        ReadingQueueService.add(work, to: queue, in: context)
        #expect(work.isQueuedForLater)

        ReadingQueueService.removeFromQueue(work, from: queue, in: context)

        #expect(!work.isQueuedForLater)
        #expect(work.epubPreservationStatus == .notPreserved)
    }

    @Test func removingQueueFromSavedWorkKeepsRecordAndFile() throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let work = SavedWork(
            title: "Saved Queue Removal",
            author: "Writer",
            sourceURL: "https://archiveofourown.org/works/987"
        )
        work.isSaved = true
        work.hasEPUB = true
        context.insert(work)
        try Data("saved-queue-removal".utf8).write(to: work.fileURL)
        defer { try? FileManager.default.removeItem(at: work.fileURL) }

        let queue = ReadingQueueService.ensureSavedForLaterQueue(in: context)
        ReadingQueueService.add(work, to: queue, in: context)

        ReadingQueueService.removeFromQueue(work, from: queue, in: context)

        let restored = try #require(try context.fetch(FetchDescriptor<SavedWork>()).first)
        #expect(restored.id == work.id)
        #expect(restored.isSaved)
        #expect(!restored.isQueuedForLater)
        #expect(restored.queueMemberships.isEmpty)
        #expect(restored.hasEPUB)
        #expect(FileManager.default.fileExists(atPath: restored.fileURL.path))
    }

    @Test func normalizeClearsStaleQueueFlagWithoutMembership() throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let work = SavedWork(title: "Stale Queue Flag", author: "Writer")
        work.isQueuedForLater = true
        work.epubPreservationStatus = .preserved
        context.insert(work)

        ReadingQueueService.normalizeAllQueuedWorks(in: context)

        #expect(!work.isQueuedForLater)
        #expect(work.queueMemberships.isEmpty)
        #expect(work.epubPreservationStatus == .notPreserved)
        #expect(try context.fetch(FetchDescriptor<ReadingQueueMembership>()).isEmpty)
    }

    @Test func existingWorkMatchesCanonicalAO3URLVariants() throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let work = SavedWork(
            title: "Canonical Match",
            author: "Writer",
            sourceURL: "https://archiveofourown.org/downloads/2468/work.epub"
        )
        context.insert(work)

        let summary = AO3WorkSummary(
            id: 2468,
            title: "Canonical Match",
            authors: ["Writer"],
            fandoms: [],
            rating: "",
            warnings: [],
            categories: [],
            isComplete: nil,
            dateUpdated: "",
            tags: [],
            summary: "",
            language: "",
            words: nil,
            chapters: "",
            comments: nil,
            kudos: nil,
            hits: nil,
            seriesTitle: nil,
            seriesURL: nil,
            seriesPosition: nil
        )

        #expect(ReadingQueueService.existingWork(for: summary, in: context)?.id == work.id)
    }

    @Test func atomicEPUBReplaceFailureKeepsExistingFile() throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let work = SavedWork(title: "Atomic Failure", author: "Writer")
        context.insert(work)
        let original = Data("original-epub".utf8)
        try original.write(to: work.fileURL)
        defer { try? FileManager.default.removeItem(at: work.fileURL) }

        let invalid = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("epub")
        try Data("not an epub".utf8).write(to: invalid)
        defer { try? FileManager.default.removeItem(at: invalid) }

        #expect(throws: (any Error).self) {
            try ReadingQueueService.replaceEPUB(for: work, with: invalid)
        }
        #expect(try Data(contentsOf: work.fileURL) == original)
    }

    @Test func atomicEPUBReplaceSuccessUpdatesFile() throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let work = SavedWork(title: "Atomic Success", author: "Writer")
        context.insert(work)
        try Data("old".utf8).write(to: work.fileURL)
        defer { try? FileManager.default.removeItem(at: work.fileURL) }

        let replacement = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("epub")
        try FileManager.default.copyItem(at: try sampleEPUB, to: replacement)

        try ReadingQueueService.replaceEPUB(for: work, with: replacement)

        #expect(try EPUBDocument.metadata(ofEPUBAt: work.fileURL).title == "A Test Work")
        #expect(!FileManager.default.fileExists(atPath: replacement.path))
    }

    @Test func seriesManualConfirmationShowsSizeOrUnknownWarning() {
        let preview = AO3SeriesPreview(
            works: [summary(1), summary(2)],
            currentPage: 1,
            totalPages: 1
        )
        let exact = ReadingQueueService.seriesPrompt(for: preview, threshold: 5)
        #expect(exact.message.contains("2 works"))
        #expect(!exact.message.contains("at least"))

        let partial = ReadingQueueService.seriesPrompt(
            for: AO3SeriesPreview(works: [summary(1)], currentPage: 1, totalPages: 3),
            threshold: 5
        )
        #expect(partial.message.contains("at least 1 work"))
        #expect(partial.message.contains("multiple pages"))

        let unknown = ReadingQueueService.seriesPrompt(for: nil, threshold: 5, previewFailed: true)
        #expect(unknown.message.contains("couldn't confirm"))
    }

    @Test func autoPreserveSettingDefaultOffThresholdFiveRules() {
        let smallPreview = AO3SeriesPreview(
            works: [summary(1), summary(2), summary(3), summary(4), summary(5)],
            currentPage: 1,
            totalPages: 1
        )
        let defaultPrompt = ReadingQueueService.seriesPrompt(for: smallPreview, threshold: 5)
        #expect(defaultPrompt.canAutoPreserve)
        #expect(defaultPrompt.autoPreserveLabel == "Always auto-preserve series under 5 works")

        let lowerThreshold = ReadingQueueService.seriesPrompt(for: smallPreview, threshold: 4)
        #expect(!lowerThreshold.canAutoPreserve)

        let multiPage = ReadingQueueService.seriesPrompt(
            for: AO3SeriesPreview(works: [summary(1)], currentPage: 1, totalPages: 2),
            threshold: 5
        )
        #expect(!multiPage.canAutoPreserve)
    }

    @Test func seriesPreviewUsedForThresholdDecision() {
        let exactSmall = ReadingQueueService.seriesPrompt(
            for: AO3SeriesPreview(works: [summary(1), summary(2)], currentPage: 1, totalPages: 1),
            threshold: 2
        )
        #expect(exactSmall.canAutoPreserve)
        #expect(exactSmall.canUsePreviewForPreservation)

        let exactTooLarge = ReadingQueueService.seriesPrompt(
            for: AO3SeriesPreview(
                works: [summary(1), summary(2), summary(3)],
                currentPage: 1,
                totalPages: 1
            ),
            threshold: 2
        )
        #expect(!exactTooLarge.canAutoPreserve)
        #expect(exactTooLarge.canUsePreviewForPreservation)

        let partial = ReadingQueueService.seriesPrompt(
            for: AO3SeriesPreview(works: [summary(1), summary(2)], currentPage: 1, totalPages: 2),
            threshold: 5
        )
        #expect(!partial.canAutoPreserve)
        #expect(!partial.canUsePreviewForPreservation)
    }

    @Test func seriesResultCountsAlreadyPreservedSeparately() async throws {
        let context = try makeContext()
        let queue = ReadingQueueService.ensureSavedForLaterQueue(in: context)
        let work = SavedWork(
            title: "Series Work 10",
            author: "Writer",
            sourceURL: "https://archiveofourown.org/works/10"
        )
        work.ao3WorkID = 10
        context.insert(work)
        ReadingQueueService.add(work, to: queue, in: context)
        work.hasEPUB = true
        work.epubPreservationStatus = .preserved
        try context.save()

        let result = await ReadingQueueService.preserveSeries(
            [summary(10)],
            to: [queue],
            in: context,
            preserveWork: { _, _, _ in
                throw AO3Error.network("Preserver should not be called.")
            },
            pauseNanos: 0
        )

        #expect(result.total == 1)
        #expect(result.alreadyPreserved == 1)
        #expect(result.preserved == 0)
        #expect(result.failed == 0)
    }

    @Test func seriesResultCountsUnavailableSeparately() async throws {
        let context = try makeContext()
        let queue = ReadingQueueService.ensureSavedForLaterQueue(in: context)
        let work = SavedWork(
            title: "Unavailable Series Work",
            author: "Writer",
            sourceURL: "https://archiveofourown.org/works/11"
        )
        work.ao3WorkID = 11
        work.ao3Unavailable = true
        context.insert(work)
        ReadingQueueService.add(work, to: queue, in: context)

        let result = await ReadingQueueService.preserveSeries(
            [summary(11)],
            to: [queue],
            in: context,
            preserveWork: { _, _, _ in
                throw AO3Error.network("Preserver should not be called.")
            },
            pauseNanos: 0
        )

        #expect(result.unavailable == 1)
        #expect(result.failed == 0)
    }

    @Test func seriesResultPartialFailureDoesNotFailEntireSeries() async throws {
        let context = try makeContext()
        let queue = ReadingQueueService.ensureSavedForLaterQueue(in: context)
        let summaries = [summary(20), summary(21), summary(22)]

        let result = await ReadingQueueService.preserveSeries(
            summaries,
            to: [queue],
            in: context,
            preserveWork: { summary, queues, context in
                if summary.id == 21 { throw AO3Error.notFound }
                if summary.id == 22 { throw AO3Error.network("offline") }
                let work = SavedWork(
                    title: summary.title,
                    author: summary.authorText,
                    sourceURL: summary.workURL.absoluteString
                )
                work.ao3WorkID = summary.id
                context.insert(work)
                for queue in queues {
                    ReadingQueueService.add(work, to: queue, in: context)
                }
                work.hasEPUB = true
                work.epubPreservationStatus = .preserved
                try context.save()
                return work
            },
            pauseNanos: 0
        )

        #expect(result.preserved == 1)
        #expect(result.unavailable == 1)
        #expect(result.failed == 1)
        #expect(result.completed == 3)
    }

    @Test func customQueueSeriesOptionAddsSeriesWhenEnabled() async throws {
        let context = try makeContext()
        let firstQueue = ReadingQueueService.createQueue(named: "Weeknight", in: context)
        let secondQueue = ReadingQueueService.createQueue(named: "Longfic", in: context)

        let result = await ReadingQueueService.preserveSeries(
            [summary(30), summary(31)],
            to: [firstQueue, secondQueue],
            in: context,
            preserveWork: { summary, queues, context in
                let work = SavedWork(
                    title: summary.title,
                    author: summary.authorText,
                    sourceURL: summary.workURL.absoluteString
                )
                work.ao3WorkID = summary.id
                context.insert(work)
                for queue in queues {
                    ReadingQueueService.add(work, to: queue, in: context)
                }
                work.hasEPUB = true
                work.epubPreservationStatus = .preserved
                try context.save()
                return work
            },
            pauseNanos: 0
        )

        let works = try context.fetch(FetchDescriptor<SavedWork>())
        #expect(result.preserved == 2)
        #expect(works.count == 2)
        #expect(works.allSatisfy { $0.queueMemberships.count == 2 })
        #expect(firstQueue.memberships.count == 2)
        #expect(secondQueue.memberships.count == 2)
    }

    @Test func customQueueSeriesOptionPreventsDuplicateMemberships() async throws {
        let context = try makeContext()
        let queue = ReadingQueueService.createQueue(named: "No Duplicates", in: context)
        let work = SavedWork(
            title: "Series Work 40",
            author: "Writer",
            sourceURL: "https://archiveofourown.org/works/40"
        )
        work.ao3WorkID = 40
        context.insert(work)
        ReadingQueueService.add(work, to: queue, in: context)
        work.hasEPUB = true
        work.epubPreservationStatus = .preserved
        try context.save()

        let result = await ReadingQueueService.preserveSeries(
            [summary(40)],
            to: [queue],
            in: context,
            preserveWork: { _, _, _ in
                throw AO3Error.network("Preserver should not be called.")
            },
            pauseNanos: 0
        )

        #expect(result.alreadyPreserved == 1)
        #expect(work.queueMemberships.count == 1)
        #expect(queue.memberships.count == 1)
    }

    @Test func saveForLaterRemoteDownloadFailureKeepsMetadata() async throws {
        let context = try makeContext()
        let summary = summary(50, seriesURL: "https://archiveofourown.org/series/5")

        let work = try await ReadingQueueService.addToSavedForLater(
            summary,
            in: context,
            downloadEPUB: { _ in throw AO3Error.network("offline") }
        )

        #expect(work.title == summary.title)
        #expect(work.author == summary.authorText)
        #expect(work.summary == summary.summary)
        #expect(work.sourceURL == summary.workURL.absoluteString)
        #expect(work.ao3WorkID == summary.id)
        #expect(work.isInSavedForLaterQueue)
        #expect(work.epubPreservationStatus == .failed)
        #expect(work.workFandoms == summary.fandoms)
        #expect(work.workFreeforms == summary.tags)
    }
}
