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
        #expect(controller.toastTarget?.priorWorkState == .existing)
        controller.undo()
        #expect(!existing.isPendingDeletion)
        #expect(existing.activeQueueMemberships.isEmpty)
        #expect(existing.lastReadDate != nil)
        #expect(existing.hasEPUB)
        #expect(try Data(contentsOf: existing.fileURL) == epub)

        controller.quickAdd(summary(512), in: context, defaults: settings) { _, _, _ in }
        let created = try #require(controller.toastTarget?.work)
        #expect(controller.toastTarget?.priorWorkState == .inserted)
        controller.undo()
        #expect(created.isPendingDeletion)
        #expect(created.activeQueueMemberships.isEmpty)
    }

    private func copySampleEPUB() throws -> URL {
        let sample = try #require(Bundle(for: BundleAnchor.self).url(forResource: "sample", withExtension: "epub"))
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
        try FileManager.default.copyItem(at: sample, to: temp)
        return temp
    }

    private func waitUntilFinished(_ queue: DownloadQueue) async {
        for _ in 0..<500 where queue.isRunning {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(!queue.isRunning)
    }

    @Test func undoReturnsRevivedWorkToRecentlyDeletedWithRemainingWindow() throws {
        let context = try context()
        let queue = ReadingQueue(name: "List")
        let otherQueue = ReadingQueue(name: "Other")
        context.insert(queue)
        context.insert(otherQueue)

        let savedWork = SavedWork(
            title: "Restorable Saved", author: "Writer", sourceURL: summary(515).workURL.absoluteString
        )
        savedWork.ao3WorkID = 515
        savedWork.isSaved = true
        context.insert(savedWork)
        let epub = Data("preserved epub".utf8)
        try epub.write(to: savedWork.fileURL)
        defer { try? FileManager.default.removeItem(at: savedWork.fileURL) }
        let originalDeletedAt = Date(timeIntervalSinceNow: -60 * 86_400)
        let originalScheduledAt = Date(timeIntervalSinceNow: 30 * 86_400)
        PreservedWorkService.softDelete(
            savedWork,
            priorDates: (originalDeletedAt, originalScheduledAt),
            in: context
        )

        let controller = RemoteWorkSelectionController()
        controller.sourceQueueID = queue.id
        let settings = try defaults()
        controller.quickAdd(summary(515), in: context, defaults: settings) { _, _, _ in }
        #expect(!savedWork.isPendingDeletion)
        #expect(
            controller.toastTarget?.priorWorkState
                == .revived(deletedAt: originalDeletedAt, scheduledAt: originalScheduledAt)
        )
        let restoredTombstones = try context.fetch(FetchDescriptor<SyncTombstone>())
        #expect(!restoredTombstones.contains {
            $0.recordType == .savedWork && $0.recordID == savedWork.id
        })
        controller.undo()
        #expect(savedWork.isPendingDeletion)
        #expect(savedWork.deletedAt == originalDeletedAt)
        #expect(savedWork.permanentDeletionScheduledAt == originalScheduledAt)
        #expect(savedWork.activeQueueMemberships.isEmpty)
        #expect(savedWork.hasEPUB)
        #expect(try Data(contentsOf: savedWork.fileURL) == epub)
        let undoneTombstones = try context.fetch(FetchDescriptor<SyncTombstone>())
        #expect(undoneTombstones.contains {
            $0.recordType == .savedWork && $0.recordID == savedWork.id
        })

        savedWork.deletedAt = nil // a legacy pending work may lack the recovery dates
        savedWork.permanentDeletionScheduledAt = nil
        try context.save()
        controller.quickAdd(summary(515), in: context, defaults: settings) { _, _, _ in }
        controller.undo()
        #expect(savedWork.isPendingDeletion)
        #expect(savedWork.deletedAt == nil)
        #expect(savedWork.permanentDeletionScheduledAt == nil)

        let queueOnlyWork = SavedWork(
            title: "Restorable Queue Only", author: "Writer", sourceURL: summary(518).workURL.absoluteString
        )
        queueOnlyWork.ao3WorkID = 518
        queueOnlyWork.hasEPUB = false
        context.insert(queueOnlyWork)
        let queueOnlyDeletedAt = Date(timeIntervalSinceNow: -10 * 86_400)
        let queueOnlyScheduledAt = Date(timeIntervalSinceNow: 80 * 86_400)
        PreservedWorkService.softDelete(
            queueOnlyWork,
            priorDates: (queueOnlyDeletedAt, queueOnlyScheduledAt),
            in: context
        )
        controller.quickAdd(summary(518), in: context, defaults: settings) { _, _, _ in }
        controller.undo()
        #expect(queueOnlyWork.isPendingDeletion)
        #expect(queueOnlyWork.deletedAt == queueOnlyDeletedAt)
        #expect(queueOnlyWork.permanentDeletionScheduledAt == queueOnlyScheduledAt)
        #expect(queueOnlyWork.activeQueueMemberships.isEmpty)

        // If another live queue adopted the revived work before Undo, Undo leaves it live there.
        controller.quickAdd(summary(518), in: context, defaults: settings) { _, _, _ in }
        ReadingQueueService.add(queueOnlyWork, to: otherQueue, in: context)
        controller.undo()
        #expect(!queueOnlyWork.isPendingDeletion)
        #expect(queueOnlyWork.activeQueueMemberships.map { $0.queue?.id } == [otherQueue.id])
        #expect(try context.fetchCount(FetchDescriptor<SavedWork>()) == 2)
    }

    @Test func finishedDownloadsCanBeQueuedAgainAndExplicitDownloadUpgradesActiveItems() async throws {
        var incoming = DownloadQueue.Item(
            id: 513, title: "Retry", sourceURL: summary(513).workURL, isComplete: true, seriesURL: ""
        )
        incoming.requiresOfflineQueue = true
        var other = DownloadQueue.Item(
            id: 999, title: "Active", sourceURL: summary(999).workURL, isComplete: true, seriesURL: ""
        )
        other.status = .downloading
        for status in [DownloadQueue.Status.skipped, .done, .failed] {
            var previous = DownloadQueue.Item(
                id: 513, title: "Old", sourceURL: summary(513).workURL, isComplete: true, seriesURL: ""
            )
            previous.requiresOfflineQueue = true
            previous.status = status
            var items = [previous, other]
            DownloadQueue.merge([incoming], into: &items)
            #expect(items.map(\.id) == [other.id, incoming.id])
            #expect(items[1] == incoming)
        }

        let context = try context()
        let queue = ReadingQueue(name: "Offline")
        context.insert(queue)
        let work513 = try ReadingQueueService.ensureLocalMetadata(for: summary(513), in: context)
        let work519 = try ReadingQueueService.ensureLocalMetadata(for: summary(519), in: context)
        defer {
            try? FileManager.default.removeItem(at: work513.fileURL)
            try? FileManager.default.removeItem(at: work519.fileURL)
        }

        var started519: CheckedContinuation<Void, Never>?
        var finish519: CheckedContinuation<URL, Error>?
        var downloads: [Int] = []
        let downloadQueue = DownloadQueue(
            downloadEPUB: { id, _ in
                downloads.append(id)
                if id == 519 {
                    return try await withCheckedThrowingContinuation { continuation in
                        finish519 = continuation
                        started519?.resume()
                        started519 = nil
                    }
                }
                return try self.copySampleEPUB()
            },
            verifyAvailability: { _, _ in }
        )

        // First run skips 513 because it isn't in an offline queue yet; second run re-queues and imports it.
        downloadQueue.enqueue([incoming], into: context)
        await waitUntilFinished(downloadQueue)
        #expect(downloadQueue.items.map(\.status) == [.skipped])
        #expect(downloads.isEmpty)

        ReadingQueueService.add(work513, to: queue, in: context)
        downloadQueue.enqueue([incoming], into: context)
        await waitUntilFinished(downloadQueue)
        #expect(work513.hasEPUB)
        #expect(downloadQueue.items.map(\.status) == [.done])
        #expect(downloads == [513])

        // While 519 is mid-download for an offline queue, remove it from the queue and upgrade via Download.
        ReadingQueueService.add(work519, to: queue, in: context)
        var offline519 = DownloadQueue.Item(
            id: 519, title: "Active", sourceURL: summary(519).workURL, isComplete: true, seriesURL: ""
        )
        offline519.requiresOfflineQueue = true
        await withCheckedContinuation { continuation in
            started519 = continuation
            downloadQueue.enqueue([offline519], into: context)
        }
        ReadingQueueService.removeFromQueue(work519, from: queue, in: context)
        var explicit519 = offline519
        explicit519.requiresOfflineQueue = false
        downloadQueue.enqueue([explicit519], into: context)
        #expect(downloadQueue.items.count == 1)
        #expect(downloadQueue.items[0].status == .downloading)
        #expect(!downloadQueue.items[0].requiresOfflineQueue)
        finish519?.resume(with: Result { try copySampleEPUB() })
        finish519 = nil
        await waitUntilFinished(downloadQueue)
        #expect(work519.hasEPUB)
        #expect(downloadQueue.items.map(\.status) == [.done])
        #expect(downloads == [513, 519])
    }

    @Test func cancelAfterRequeueDoesNotCrashActiveDownload() async throws {
        let context = try context()
        let work516 = try ReadingQueueService.ensureLocalMetadata(for: summary(516), in: context)
        let work517 = try ReadingQueueService.ensureLocalMetadata(for: summary(517), in: context)
        defer {
            try? FileManager.default.removeItem(at: work516.fileURL)
            try? FileManager.default.removeItem(at: work517.fileURL)
        }

        var started517: CheckedContinuation<Void, Never>?
        var finish517: CheckedContinuation<URL, Error>?
        let downloadQueue = DownloadQueue(
            downloadEPUB: { id, _ in
                if id == 516 {
                    throw URLError(.notConnectedToInternet)
                }
                return try await withCheckedThrowingContinuation { continuation in
                    finish517 = continuation
                    started517?.resume()
                    started517 = nil
                }
            },
            verifyAvailability: { _, _ in }
        )

        let item516 = DownloadQueue.Item(
            id: 516, title: "Fail First", sourceURL: summary(516).workURL, isComplete: true, seriesURL: ""
        )
        let item517 = DownloadQueue.Item(
            id: 517, title: "In Flight", sourceURL: summary(517).workURL, isComplete: true, seriesURL: ""
        )
        await withCheckedContinuation { continuation in
            started517 = continuation
            downloadQueue.enqueue([item516, item517], into: context)
        }
        #expect(downloadQueue.items.map(\.status) == [.failed, .downloading])

        // Re-queueing 516 moves it to the back (FIFO); cancel drops queued items while 517 finishes.
        downloadQueue.enqueue([item516], into: context)
        #expect(downloadQueue.items.map(\.id) == [517, 516])
        downloadQueue.cancel()
        #expect(downloadQueue.items.map(\.id) == [517])
        finish517?.resume(with: Result { try copySampleEPUB() })
        finish517 = nil
        await waitUntilFinished(downloadQueue)
        #expect(work517.hasEPUB)
        #expect(downloadQueue.items.map(\.status) == [.done])
    }

    @Test func queuedImportReconcilesPreservationAndMetadataWithoutRelaunch() async throws {
        let context = try context()
        let queue = ReadingQueue(name: "Offline")
        context.insert(queue)
        let remote514 = summary(514)
        let work514 = try ReadingQueueService.ensureLocalMetadata(for: remote514, in: context)
        ReadingQueueService.add(work514, to: queue, in: context)
        let remote520 = summary(520)
        let work520 = try ReadingQueueService.ensureLocalMetadata(for: remote520, in: context)
        ReadingQueueService.add(work520, to: queue, in: context)
        defer {
            try? FileManager.default.removeItem(at: work514.fileURL)
            try? FileManager.default.removeItem(at: work520.fileURL)
        }
        #expect(work514.epubPreservationStatus == .queued)
        #expect(work514.metadataSyncStatus == .pending)

        let downloadQueue = DownloadQueue(
            downloadEPUB: { _, _ in try self.copySampleEPUB() },
            verifyAvailability: { work, _ in
                if work.ao3WorkID == 514 {
                    work.lastTagRefreshAttemptAt = Date() // failed verification on cooldown stays incomplete
                } else {
                    work.workTagsFetched = true
                    work.workFandoms = ["Fandom"]
                    work.workWarnings = ["No Archive Warnings Apply"]
                    work.chapters = "1/1"
                    if let identity = AO3AuthorIdentity(displayName: "Writer", href: "/users/writer") {
                        work.verifiedAuthorIdentities = [identity]
                    }
                }
            }
        )
        var item514 = DownloadQueue.Item(
            id: 514, title: work514.title, sourceURL: remote514.workURL, isComplete: true, seriesURL: ""
        )
        item514.requiresOfflineQueue = true
        var item520 = DownloadQueue.Item(
            id: 520, title: work520.title, sourceURL: remote520.workURL, isComplete: true, seriesURL: ""
        )
        item520.requiresOfflineQueue = true
        downloadQueue.enqueue([item514, item520], into: context)
        await waitUntilFinished(downloadQueue)

        #expect(work514.hasEPUB)
        #expect(work514.epubPreservationStatus == .preserved)
        #expect(work514.preservedAt != nil)
        #expect(work514.metadataSyncStatus == .incomplete)
        #expect(work520.hasEPUB)
        #expect(work520.epubPreservationStatus == .preserved)
        #expect(work520.metadataSyncStatus == .complete)
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
        let largeActions = UIHostingController(rootView: toast.actions.dynamicTypeSize(.large))
            .sizeThatFits(in: CGSize(width: 400, height: 200))
        let ax5Actions = UIHostingController(rootView: toast.actions.dynamicTypeSize(.accessibility5))
            .sizeThatFits(in: CGSize(width: 240, height: 500))
        let ax5Toast = UIHostingController(
            rootView: toast.environment(ThemeManager()).dynamicTypeSize(.accessibility5)
        ).sizeThatFits(in: CGSize(width: 600, height: 600))
        #expect(largeActions.height >= 44)
        #expect(ax5Actions.height >= max(94, largeActions.height * 2.2))
        #expect(ax5Toast.height >= ax5Actions.height + 44)
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
