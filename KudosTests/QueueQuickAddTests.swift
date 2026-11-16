import Foundation
import SwiftData
import SwiftUI
import Testing
#if os(iOS)
import UIKit
#endif
@testable import Kudos

@MainActor
@Suite(.serialized)
struct QueueQuickAddTests {
    final class BundleAnchor {}

    private func summary(_ id: Int) -> AO3WorkSummary {
        AO3WorkSummary(
            id: id, title: "Work \(id)", authors: ["Writer"], fandoms: ["Fandom"],
            rating: "Teen And Up Audiences", warnings: [], categories: [],
            isComplete: true, dateUpdated: "2026-11-16", tags: [], summary: "Summary",
            language: "English", words: 100, chapters: "1/1", comments: nil,
            kudos: nil, hits: nil, seriesTitle: nil, seriesURL: nil, seriesPosition: nil
        )
    }

    private func defaults() throws -> UserDefaults {
        let suite = "QueueQuickAddTests.\(UUID().uuidString)"
        let value = try #require(UserDefaults(suiteName: suite))
        value.removePersistentDomain(forName: suite)
        return value
    }

    private func context() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self
        ])
        return ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
    }

    @Test func resultNamesZeroOneAndManyQueues() {
        func status(_ names: [String]) -> String? {
            AO3WorkRow.statusText(
                readingState: .unread, chapterLabel: nil, isWantToRead: false,
                queueNames: names, isInLibrary: false
            )
        }
        #expect(status([]) == nil)
        #expect(status(["Summer Reading"]) == "In Summer Reading")
        #expect(status(["Summer Reading", "For the Train"]) == "In 2 queues")
        #expect(AO3WorkRow.statusText(
            readingState: .unread, chapterLabel: nil, isWantToRead: true,
            queueNames: ["Want to Read"], isInLibrary: false
        ) == "In Want to Read")
    }

    @Test func currentQueueUsesSourceThenStoredThenWantToRead() throws {
        let fallback = ReadingQueue(name: "Saved for Later", kind: .savedForLater)
        let stored = ReadingQueue(name: "Stored")
        let source = ReadingQueue(name: "Source")
        let queues = [fallback, stored, source]
        #expect(RemoteWorkSelectionController.currentQueue(
            in: queues, sourceID: source.id, storedID: stored.id.uuidString
        )?.id == source.id)
        #expect(RemoteWorkSelectionController.currentQueue(
            in: queues, sourceID: nil, storedID: stored.id.uuidString
        )?.id == stored.id)
        #expect(RemoteWorkSelectionController.currentQueue(
            in: queues, sourceID: nil, storedID: UUID().uuidString
        )?.id == fallback.id)
        stored.isPendingDeletion = true
        #expect(RemoteWorkSelectionController.currentQueue(
            in: queues, sourceID: nil, storedID: stored.id.uuidString
        )?.id == fallback.id)
        fallback.isPendingDeletion = true
        #expect(RemoteWorkSelectionController.currentQueue(
            in: queues, sourceID: nil, storedID: stored.id.uuidString
        ) == nil)
    }

    @Test func swipePublishesMembershipAndToastBeforePreservation() throws {
        let context = try context()
        let queue = ReadingQueue(name: "Want to Read", kind: .savedForLater)
        context.insert(queue)
        let controller = RemoteWorkSelectionController()
        let settings = try defaults()
        var enqueued = 0
        controller.quickAdd(summary(501), in: context, defaults: settings) { work, chosen, _ in
            enqueued += 1
            #expect(work.queueMemberships.contains { $0.queue?.id == chosen.id })
            #expect(controller.toastTarget?.work.id == work.id)
        }
        #expect(enqueued == 1)
        #expect(controller.toastTarget?.queue.id == queue.id)
        #expect(settings.string(forKey: "lastAddedReadingQueueID") == queue.id.uuidString)
        #expect(try context.fetchCount(FetchDescriptor<SavedWork>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<ReadingQueueMembership>()) == 1)
    }

    @Test func repeatSwipeDoesNotOfferUndoForExistingMembership() throws {
        let context = try context()
        let queue = ReadingQueue(name: "List")
        queue.keepsWorksOffline = false
        context.insert(queue)
        let settings = try defaults()
        settings.set(queue.id.uuidString, forKey: "lastAddedReadingQueueID")
        let controller = RemoteWorkSelectionController()
        let remote = summary(502)
        let work = try ReadingQueueService.ensureLocalMetadata(for: remote, in: context)
        ReadingQueueService.add(work, to: queue, in: context)
        var enqueued = 0
        controller.quickAdd(remote, in: context, defaults: settings) { _, _, _ in enqueued += 1 }
        #expect(enqueued == 0)
        #expect(controller.toastTarget == nil)
        #expect(work.queueMemberships.count == 1)
    }

    @Test func secondSwipeUndoAndChangeKeepTheirOwnTargets() throws {
        let context = try context()
        let firstQueue = ReadingQueue(name: "First")
        let secondQueue = ReadingQueue(name: "Second")
        context.insert(firstQueue)
        context.insert(secondQueue)
        let controller = RemoteWorkSelectionController()
        let settings = try defaults()
        controller.sourceQueueID = firstQueue.id
        controller.quickAdd(summary(503), in: context, defaults: settings) { _, _, _ in }
        let firstWork = try #require(controller.toastTarget?.work)
        controller.sourceQueueID = secondQueue.id
        controller.quickAdd(summary(504), in: context, defaults: settings) { _, _, _ in }
        let secondWork = try #require(controller.toastTarget?.work)
        controller.undo()
        #expect(firstWork.activeQueueMemberships.count == 1)
        #expect(secondWork.activeQueueMemberships.isEmpty)
        #expect(secondWork.isPendingDeletion)
        #expect(controller.toastTarget == nil)

        controller.quickAdd(summary(505), in: context, defaults: settings) { _, _, _ in }
        let changeWork = try #require(controller.toastTarget?.work)
        controller.changeQueue()
        #expect(controller.changeTarget?.work.id == changeWork.id)
        controller.quickAdd(summary(506), in: context, defaults: settings) { _, _, _ in }
        #expect(controller.changeTarget?.work.id == changeWork.id)
        #expect(controller.toastTarget?.work.ao3WorkID == 506)
    }

    @Test func undoDoesNotRemoveAReplacementMembership() throws {
        let context = try context()
        let queue = ReadingQueue(name: "List")
        context.insert(queue)
        let controller = RemoteWorkSelectionController()
        controller.sourceQueueID = queue.id
        controller.quickAdd(summary(510), in: context, defaults: try defaults()) { _, _, _ in }
        let work = try #require(controller.toastTarget?.work)
        let originalID = try #require(controller.toastTarget?.membershipID)
        ReadingQueueService.removeFromQueue(work, from: queue, in: context)
        let replacement = ReadingQueueService.add(work, to: queue, in: context)
        #expect(replacement.id != originalID)
        controller.undo()
        #expect(work.activeQueueMemberships.map(\.id) == [replacement.id])
    }

    @Test func undoPreservesReadingHistoryEPUBAndRemovesSwipeCreatedWork() throws {
        let context = try context()
        let queue = ReadingQueue(name: "Offline")
        context.insert(queue)
        let existing = SavedWork(
            title: "Read Before", author: "Writer", sourceURL: summary(511).workURL.absoluteString
        )
        existing.ao3WorkID = 511
        existing.lastReadDate = Date()
        context.insert(existing)
        let epub = Data("reading copy".utf8)
        try epub.write(to: existing.fileURL)
        defer { try? FileManager.default.removeItem(at: existing.fileURL) }

        let controller = RemoteWorkSelectionController()
        controller.sourceQueueID = queue.id
        let settings = try defaults()
        controller.quickAdd(summary(511), in: context, defaults: settings) { _, _, _ in }
        controller.undo()
        #expect(!existing.isPendingDeletion)
        #expect(existing.activeQueueMemberships.isEmpty)
        #expect(existing.lastReadDate != nil)
        #expect(existing.hasEPUB)
        #expect(try Data(contentsOf: existing.fileURL) == epub)

        controller.quickAdd(summary(512), in: context, defaults: settings) { _, _, _ in }
        let created = try #require(controller.toastTarget?.work)
        controller.undo()
        #expect(created.isPendingDeletion)
        #expect(created.activeQueueMemberships.isEmpty)
    }

    @Test func finishedDownloadsCanBeQueuedAgainAndExplicitDownloadUpgradesActiveItems() {
        var incoming = DownloadQueue.Item(
            id: 513, title: "Retry", sourceURL: nil, isComplete: true, seriesURL: ""
        )
        incoming.requiresOfflineQueue = true
        for status in [DownloadQueue.Status.skipped, .done, .failed] {
            var previous = DownloadQueue.Item(
                id: 513, title: "Old", sourceURL: nil, isComplete: true, seriesURL: ""
            )
            previous.requiresOfflineQueue = true
            previous.status = status
            var items = [previous]
            DownloadQueue.merge([incoming], into: &items)
            #expect(items == [incoming])
        }

        for status in [DownloadQueue.Status.queued, .downloading] {
            var previous = incoming
            previous.status = status
            var items = [previous]
            var explicit = incoming
            explicit.requiresOfflineQueue = false
            DownloadQueue.merge([explicit], into: &items)
            #expect(items.count == 1)
            #expect(items[0].status == status)
            #expect(!items[0].requiresOfflineQueue)
        }
    }

    @Test func queuedImportReconcilesPreservationAndMetadataWithoutRelaunch() async throws {
        let context = try context()
        let queue = ReadingQueue(name: "Offline")
        context.insert(queue)
        let remote = summary(514)
        let work = try ReadingQueueService.ensureLocalMetadata(for: remote, in: context)
        ReadingQueueService.add(work, to: queue, in: context)
        let sample = try #require(Bundle(for: BundleAnchor.self).url(forResource: "sample", withExtension: "epub"))
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
        try FileManager.default.copyItem(at: sample, to: temp)
        defer {
            try? FileManager.default.removeItem(at: temp)
            try? FileManager.default.removeItem(at: work.fileURL)
        }
        let saved = try await importEPUB(temp, source: remote.workURL, verifyAvailability: false, into: context)
        #expect(saved.id == work.id)
        #expect(saved.epubPreservationStatus == .queued)
        #expect(saved.metadataSyncStatus == .pending)
        DownloadQueue.finishImportedWork(saved, in: context)
        #expect(saved.epubPreservationStatus == .preserved)
        #expect(saved.preservedAt != nil)
        #expect(saved.metadataSyncStatus == .incomplete)
        try context.save()
    }

    #if os(iOS)
    @Test func updateMarkerKeepsItsWidthUnlessBadgeTitleOptsIntoWrapping() {
        let size = CGSize(width: 80, height: 300)
        let fixed = UIHostingController(rootView: UpdateMarker(text: "In a long queue")
            .dynamicTypeSize(.accessibility5))
        let wrapping = UIHostingController(rootView: UpdateMarker(text: "In a long queue", wraps: true)
            .dynamicTypeSize(.accessibility5))
        #expect(fixed.sizeThatFits(in: size).width > size.width)
        #expect(wrapping.sizeThatFits(in: size).width <= size.width)
        #expect(!UpdateMarker(text: "+1").wraps)
    }

    @Test func toastActionsStackAtAX5WithTwoFullHitTargets() {
        #expect(QueueAddedToast.stacksActions(.accessibility5))
        #expect(!QueueAddedToast.stacksActions(.large))
        let toast = QueueAddedToast(queue: ReadingQueue(name: "Offline"), change: {}, undo: {})
        let host = UIHostingController(rootView: toast.actions.dynamicTypeSize(.accessibility5))
        #expect(host.sizeThatFits(in: CGSize(width: 160, height: 500)).height >= 94)
    }
    #endif

    @Test func downloadPolicySkipsUndoneAndListOnlyWorks() throws {
        let context = try context()
        let queue = ReadingQueue(name: "Offline")
        let work = SavedWork(title: "Work", author: "Writer", sourceURL: "https://archiveofourown.org/works/507")
        context.insert(queue)
        context.insert(work)
        ReadingQueueService.add(work, to: queue, in: context)
        var item = DownloadQueue.Item(
            id: 507, title: work.title, sourceURL: URL(string: work.sourceURL),
            isComplete: true, seriesURL: ""
        )
        item.requiresOfflineQueue = true
        #expect(DownloadQueue.shouldProcess(item, existing: work))
        queue.keepsWorksOffline = false
        #expect(!DownloadQueue.shouldProcess(item, existing: work))
        queue.keepsWorksOffline = true
        PreservedWorkService.softDelete(queue, in: context)
        #expect(!DownloadQueue.shouldProcess(item, existing: work))
        PreservedWorkService.restore(queue, in: context)
        ReadingQueueService.removeFromQueueAndDeleteIfQueueOnly(work, from: queue, in: context)
        #expect(!DownloadQueue.shouldProcess(item, existing: work))
    }

    @Test func cancelledQueuedImportDoesNotReviveOrWriteAWork() async throws {
        let context = try context()
        let sample = try #require(Bundle(for: BundleAnchor.self).url(forResource: "sample", withExtension: "epub"))
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
        try FileManager.default.copyItem(at: sample, to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }
        do {
            _ = try await importEPUB(
                temp, source: URL(string: "https://archiveofourown.org/works/507"),
                verifyAvailability: false, canImport: { false }, into: context
            )
            Issue.record("An undone download imported a work")
        } catch is CancellationError {
            #expect(!FileManager.default.fileExists(atPath: temp.path))
        } catch {
            Issue.record("Unexpected import error: \(error)")
        }
        #expect(try context.fetchCount(FetchDescriptor<SavedWork>()) == 0)
    }

    @Test func recentlyDeletedSavedForLaterIsRestoredBeforeSwipe() throws {
        let context = try context()
        let queue = ReadingQueueService.ensureSavedForLaterQueue(in: context)
        PreservedWorkService.softDelete(queue, in: context)
        let controller = RemoteWorkSelectionController()
        controller.quickAdd(summary(508), in: context, defaults: try defaults()) { _, _, _ in }
        #expect(!queue.isPendingDeletion)
        #expect(controller.toastTarget?.queue.id == queue.id)
        #expect(controller.toastTarget?.work.activeQueueMemberships.count == 1)
    }

    @Test func moveCanBeReversedAndThenUntoggled() throws {
        let context = try context()
        let first = ReadingQueue(name: "First")
        let second = ReadingQueue(name: "Second")
        let work = SavedWork(title: "Work", author: "Writer", sourceURL: "https://archiveofourown.org/works/509")
        context.insert(first)
        context.insert(second)
        context.insert(work)
        ReadingQueueService.add(work, to: first, in: context)
        ReadingQueueService.move([work], from: first, to: second, in: context)
        #expect(work.activeQueueMemberships.map { $0.queue?.id } == [second.id])
        ReadingQueueService.move([work], from: second, to: first, in: context)
        #expect(work.activeQueueMemberships.map { $0.queue?.id } == [first.id])
        ReadingQueueService.removeFromQueueAndDeleteIfQueueOnly(work, from: first, in: context)
        #expect(work.activeQueueMemberships.isEmpty)
    }

    @Test func repeatAddDoesNotDuplicateMembershipOrFetchForListOnlyQueue() async throws {
        let context = try context()
        let queue = ReadingQueue(name: "List")
        queue.keepsWorksOffline = false
        let work = SavedWork(
            title: "Remote", author: "Writer", sourceURL: "https://archiveofourown.org/works/123"
        )
        work.ao3WorkID = 123
        context.insert(queue)
        context.insert(work)
        _ = await ReadingQueueService.addAndPreserve(work, to: queue, in: context)
        _ = await ReadingQueueService.addAndPreserve(work, to: queue, in: context)
        #expect(work.queueMemberships.count == 1)
        #expect(!work.hasEPUB)
    }

    @Test func lastQueuePreferenceRoundTripsAndIsOmittedWhenUnset() throws {
        let empty = KudosBackupSettings.capture(defaults: try defaults())
        let emptyJSON = try #require(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(empty)
        ) as? [String: Any])
        #expect(emptyJSON["lastAddedReadingQueueID"] == nil)

        let source = try defaults()
        let id = UUID()
        source.set(id.uuidString, forKey: "lastAddedReadingQueueID")
        let decoded = try JSONDecoder().decode(
            KudosBackupSettings.self,
            from: JSONEncoder().encode(KudosBackupSettings.capture(defaults: source))
        )
        let destination = try defaults()
        decoded.apply(to: destination)
        #expect(destination.string(forKey: "lastAddedReadingQueueID") == id.uuidString)
        empty.apply(to: destination)
        #expect(destination.string(forKey: "lastAddedReadingQueueID") == id.uuidString)
    }
}
