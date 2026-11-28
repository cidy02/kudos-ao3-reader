import Foundation
import SwiftData
import Testing
@testable import Kudos

extension PersistenceGateSuites {
    @MainActor
    struct LibraryScaleBatchParityTests {
        @Test func batchImportMatchesIndividualImports() async throws {
            let individual = try await importFixture(batched: false)
            let batched = try await importFixture(batched: true)
            #expect(batched == individual)
            #expect(batched == ["By ID", "By URL", "Exact source", "New work", "New work"])
        }

        @Test func batchLookupKeepsRecordIDFallbackAndSeesInterveningWrites() throws {
            let container = try makeContainer()
            let context = container.mainContext
            let byRecord = SavedWork(title: "Legacy record", author: "Writer")
            let byID = SavedWork(title: "With AO3 ID", author: "Writer")
            byID.ao3WorkID = 4601
            context.insert(byRecord)
            context.insert(byID)
            try context.save()
            let batch = WorkIdentityBatch(in: context)
            defer { batch.stopTrackingChanges() }

            let original = WorkIdentityIndex(try context.fetch(FetchDescriptor<SavedWork>()))
            let fallback = batch.existingWork(ao3WorkID: nil, sourceURL: nil, recordID: byRecord.id)
            #expect(fallback === original.existingWork(ao3WorkID: nil, sourceURL: nil, recordID: byRecord.id))
            #expect(fallback === byRecord)
            let stronger = batch.existingWork(ao3WorkID: 4601, sourceURL: nil, recordID: byRecord.id)
            #expect(stronger === byID)

            byID.ao3WorkID = 4602
            try context.save()
            let previous = batch.existingWork(ao3WorkID: 4601, sourceURL: nil)
            let changed = batch.existingWork(ao3WorkID: 4602, sourceURL: nil)
            #expect(previous == nil)
            #expect(changed === byID)

            let inserted = SavedWork(title: "Another import", author: "Writer")
            inserted.ao3WorkID = 4601
            context.insert(inserted)
            try context.save()
            let replacement = batch.existingWork(ao3WorkID: 4601, sourceURL: nil)
            #expect(replacement === inserted)
        }

        @Test func remoteBatchMatchesIndividualSavesWithAnInterleavedQueueEdit() async throws {
            let individual = try await remoteFixture(batched: false)
            let batched = try await remoteFixture(batched: true)
            #expect(batched == individual)
            #expect(batched.downloads == [4701, 4702, 4703, 4703])
            #expect(batched.members == ["By ID", "By URL", "New remote work"])
            #expect(batched.orders == [10, 11, 12])
        }

        @Test func expirySweepMatchesPermanentDeletionForWorksAndTheirAssets() throws {
            let individual = try expiryFixture(batched: false)
            let batched = try expiryFixture(batched: true)
            #expect(batched == individual)
            #expect(batched.remainingWorks == ["Future", "Live", "Undated"])
            #expect(batched.collectionWorks == ["Live"])
            #expect(batched.queueWorks == ["Live"])
            #expect(batched.assetsRemain == [false, false, false, false, true, true, true, true])
            #expect(batched.tombstones.contains("converted:workPermanentlyDeleted"))
            #expect(batched.tombstones.contains("annotation:workDeleted"))
            #expect(batched.tombstones.contains("live-queue-membership:queueMembershipRemoved"))
            #expect(batched.tombstones.contains("expired-queue-membership:queueMembershipRemoved"))
            #expect(batched.tombstones.count { $0 == "both-due-membership:queueMembershipRemoved" } == 1)
        }

        @Test func failedSweepSaveKeepsTheWorkAndItsFilesForRetry() throws {
            let container = try makeContainer()
            let context = container.mainContext
            let work = SavedWork(title: "Converted work", author: "Writer")
            let id = work.id
            markDue(work)
            context.insert(work)
            try context.save()
            let paths = try installConvertedAssets(for: work)
            defer { removeFiles(paths) }

            let deleted = SaveBestEffortTesting.$budget.withValue(SaveBestEffortTesting.SaveBudget(0)) {
                PreservedWorkService.sweepExpired(in: context)
            }
            #expect(deleted == 0)
            let afterFailure = ModelContext(container)
            #expect(try afterFailure.fetch(FetchDescriptor<SavedWork>()).map(\.id) == [id])
            #expect(try afterFailure.fetch(FetchDescriptor<SyncTombstone>()).isEmpty)
            #expect(paths.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })

            let retried = PreservedWorkService.sweepExpired(in: context)
            #expect(retried == 1)
            let afterRetry = ModelContext(container)
            #expect(try afterRetry.fetch(FetchDescriptor<SavedWork>()).isEmpty)
            #expect(try afterRetry.fetch(FetchDescriptor<SyncTombstone>()).map(\.recordID) == [id])
            #expect(paths.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        }

        @Test func sweepCommitsAtMost500RowsBeforeTheNextSave() throws {
            let container = try makeContainer()
            let context = container.mainContext
            var seeded = Set<UUID>()
            for number in 0...500 {
                let collection = WorkCollection(name: "Expired \(number)")
                collection.isPendingDeletion = true
                collection.permanentDeletionScheduledAt = .distantPast
                context.insert(collection)
                seeded.insert(collection.id)
            }
            try context.save()

            let deleted = SaveBestEffortTesting.$budget.withValue(SaveBestEffortTesting.SaveBudget(1)) {
                PreservedWorkService.sweepExpired(in: context)
            }
            #expect(deleted == 500)
            let saved = ModelContext(container)
            let remaining = try saved.fetch(FetchDescriptor<WorkCollection>())
            #expect(remaining.count == 1)
            let tombstones = try saved.fetch(FetchDescriptor<SyncTombstone>())
            #expect(tombstones.count == 500)
            #expect(Set(tombstones.map(\.recordID)) == seeded.subtracting(remaining.map(\.id)))
        }

        private func importFixture(batched: Bool) async throws -> [String] {
            let container = try makeContainer()
            let context = container.mainContext
            let idWork = SavedWork(title: "By ID", author: "Writer", sourceURL: "https://example.com/legacy")
            idWork.ao3WorkID = 4501
            let urlWork = SavedWork(
                title: "By URL", author: "Writer", sourceURL: "https://archiveofourown.org/downloads/4502/story.epub"
            )
            let exact = SavedWork(title: "Exact source", author: "Writer", sourceURL: "https://example.com/story")
            for work in [idWork, urlWork, exact] { context.insert(work) }
            try context.save()
            let sources = [
                "https://archiveofourown.org/works/4501", "https://archiveofourown.org/works/4502",
                exact.sourceURL, "https://archiveofourown.org/works/4503", "https://archiveofourown.org/works/4503"
            ]
            let epub = try EPUBBuilder.archive(
                metadata: EPUBBuilder.Metadata(title: "New work", author: "Writer", identifier: "scale-parity"),
                chapters: [EPUBBuilder.Chapter(title: "Chapter", bodyXHTML: "<p>A preserved paragraph.</p>")],
                modified: Date(timeIntervalSince1970: 1_767_225_600)
            )
            let batch = batched ? WorkIdentityBatch(in: context) : nil
            defer { batch?.stopTrackingChanges() }
            var files: [URL] = []
            defer { removeFiles(files) }
            var imported: [SavedWork] = []
            for source in sources {
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).epub")
                files.append(temp)
                try epub.write(to: temp)
                let url = try #require(URL(string: source))
                let work: SavedWork
                if let batch {
                    work = try await importEPUB(
                        temp, source: url, verifyAvailability: false, using: batch, into: context
                    )
                } else {
                    work = try await importEPUB(temp, source: url, verifyAvailability: false, into: context)
                }
                files.append(work.fileURL)
                imported.append(work)
            }
            #expect(try context.fetchCount(FetchDescriptor<SavedWork>()) == 4)
            #expect(Set(imported.map(\.id)).count == 4)
            #expect(imported.allSatisfy { $0.hasEPUB })
            return imported.map(\.title)
        }

        private struct RemoteSnapshot: Equatable {
            let members: [String]
            let states: [ReadingQueueMembershipState]
            let orders: [Int]
            let origins: [ReadingQueueMembershipOrigin?]
            let statuses: [EPUBPreservationStatus]
            let downloads: [Int]
        }

        private func remoteFixture(batched: Bool) async throws -> RemoteSnapshot {
            let container = try makeContainer()
            let context = container.mainContext
            let byID = SavedWork(title: "By ID", author: "Writer")
            byID.ao3WorkID = 4701
            let byURL = SavedWork(
                title: "By URL", author: "Writer", sourceURL: "https://archiveofourown.org/downloads/4702/story.epub"
            )
            context.insert(byID)
            context.insert(byURL)
            try context.save()
            let summaries = [4701, 4702, 4703, 4703].map {
                AO3WorkSummary.subscription(id: $0, title: "New remote work", authors: ["Writer"])
            }
            let origin = ReadingQueueMembershipOrigin(kind: .search, searchID: nil, label: "Scale")
            let queue = ReadingQueueService.ensureSavedForLaterQueue(in: context)
            var downloads: [Int] = []
            let download: (Int) async throws -> URL = { id in
                downloads.append(id)
                if id == 4701 {
                    let membership = try #require(queue.memberships.first)
                    membership.sortOrderInQueue = 10
                    try context.save()
                }
                throw AO3Error.notFound
            }
            if batched {
                let error = await bulkSaveForLaterRemote(summaries, origin: origin, in: context, downloadEPUB: download)
                #expect(error == nil)
            } else {
                for summary in summaries {
                    _ = try await ReadingQueueService.addToSavedForLater(
                        summary, state: .new, origin: origin, in: context, downloadEPUB: download
                    )
                }
            }
            #expect(try context.fetchCount(FetchDescriptor<SavedWork>()) == 3)
            let memberships = queue.memberships.sorted { $0.sortOrderInQueue < $1.sortOrderInQueue }
            return RemoteSnapshot(
                members: memberships.compactMap { $0.work?.title },
                states: memberships.map(\.state),
                orders: memberships.map(\.sortOrderInQueue),
                origins: memberships.map(\.origin),
                statuses: memberships.compactMap { $0.work?.epubPreservationStatus },
                downloads: downloads
            )
        }

        private struct ExpirySnapshot: Equatable {
            let remainingWorks: [String]
            let collectionWorks: [String]
            let queueWorks: [String]
            let tombstones: [String]
            let assetsRemain: [Bool]
        }

        private func expiryFixture(batched: Bool) throws -> ExpirySnapshot {
            let container = try makeContainer()
            let context = container.mainContext
            let converted = SavedWork(title: "Converted", author: "Writer")
            let due = SavedWork(title: "Due", author: "Writer")
            let live = SavedWork(title: "Live", author: "Writer")
            let future = SavedWork(title: "Future", author: "Writer")
            let undated = SavedWork(title: "Undated", author: "Writer")
            for work in [converted, due, live, future, undated] { context.insert(work) }
            markDue(converted)
            markDue(due)
            live.permanentDeletionScheduledAt = .distantPast
            future.isPendingDeletion = true
            future.permanentDeletionScheduledAt = .distantFuture
            undated.isPendingDeletion = true
            let annotation = ReadingAnnotation(work: converted, kind: .bookmark, locatorString: "chapter.xhtml")
            context.insert(annotation)

            let collection = WorkCollection(name: "Collection")
            let queue = ReadingQueue(name: "Queue")
            let expiredQueue = ReadingQueue(name: "Expired Queue")
            context.insert(collection)
            context.insert(queue)
            context.insert(expiredQueue)
            collection.works = [converted, due, live]
            let membership = ReadingQueueService.add(converted, to: queue, in: context)
            ReadingQueueService.add(live, to: queue, in: context)
            let queueToExpire = ReadingQueueService.add(live, to: expiredQueue, in: context)
            let bothDue = ReadingQueueService.add(converted, to: expiredQueue, in: context)
            expiredQueue.isPendingDeletion = true
            expiredQueue.permanentDeletionScheduledAt = .distantPast
            try context.save()
            let roles = [
                converted.id: "converted", due.id: "due", annotation.id: "annotation",
                membership.id: "live-queue-membership", queueToExpire.id: "expired-queue-membership",
                bothDue.id: "both-due-membership", expiredQueue.id: "expired-queue"
            ]
            let files = try installConvertedAssets(for: converted) + installConvertedAssets(for: live)
            defer { removeFiles(files) }

            if batched {
                let deleted = PreservedWorkService.sweepExpired(in: context)
                #expect(deleted == 3)
            } else {
                PreservedWorkService.deletePermanently(converted, in: context)
                PreservedWorkService.deletePermanently(due, in: context)
                PreservedWorkService.deletePermanently(expiredQueue, in: context)
            }
            let saved = ModelContext(container)
            let savedCollection = try #require(try saved.fetch(FetchDescriptor<WorkCollection>()).first)
            let savedQueue = try #require(try saved.fetch(FetchDescriptor<ReadingQueue>()).first)
            #expect(try saved.fetchCount(FetchDescriptor<ReadingQueue>()) == 1)
            #expect(try saved.fetchCount(FetchDescriptor<ReadingAnnotation>()) == 0)
            #expect(savedQueue.memberships.first?.work?.isQueuedForLater == true)
            let tombstones = try saved.fetch(FetchDescriptor<SyncTombstone>())
            return ExpirySnapshot(
                remainingWorks: try saved.fetch(FetchDescriptor<SavedWork>()).map(\.title).sorted(),
                collectionWorks: savedCollection.works.map(\.title).sorted(),
                queueWorks: savedQueue.memberships.compactMap { $0.work?.title }.sorted(),
                tombstones: tombstones.map { "\(roles[$0.recordID] ?? "unexpected"):\($0.deletionReason)" }.sorted(),
                assetsRemain: files.map { FileManager.default.fileExists(atPath: $0.path) }
            )
        }

        private func markDue(_ work: SavedWork) {
            work.isPendingDeletion = true
            work.permanentDeletionScheduledAt = .distantPast
        }

        private func installConvertedAssets(for work: SavedWork) throws -> [URL] {
            let epub = work.fileURL
            let cache = Storage.readerDirectory(for: work.id)
            let original = Storage.originalDocumentURL(for: work.id, fileExtension: "txt")
            try Data("EPUB bytes".utf8).write(to: epub)
            try Data("Reader cache".utf8).write(to: cache.appendingPathComponent("chapter.xhtml"))
            try Data("The original".utf8).write(to: original)
            WorkConversionRecord(format: "txt", originalFileName: "original.txt").write(for: work.id)
            let sidecar = WorkConversionRecord.url(for: work.id)
            try #require(FileManager.default.fileExists(atPath: sidecar.path))
            return [epub, cache, original, sidecar]
        }

        private func removeFiles(_ paths: [URL]) {
            for path in paths { try? FileManager.default.removeItem(at: path) }
        }

        private func makeContainer() throws -> ModelContainer {
            let schema = Schema([
                SavedWork.self, Tag.self, WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
                SavedSearch.self, QueueSavedSearchLink.self, SyncTombstone.self, ReadingAnnotation.self
            ])
            return try ModelContainer(for: schema, configurations: [
                ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            ])
        }
    }
}
