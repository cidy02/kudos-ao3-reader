import Foundation
import SwiftData
import Testing
@testable import Kudos

extension PersistenceGateSuites {
    @MainActor
    struct LibraryScaleQueueNormalizationParityTests {
        private struct WorkState: Equatable {
            let queued: Bool
            let hasEPUB: Bool
            let preservation: EPUBPreservationStatus
            let metadata: MetadataSyncStatus
            let preservedAt: Date?
            let workID: Int?
            let seriesID: Int?

            init(_ work: SavedWork) {
                queued = work.isQueuedForLater
                hasEPUB = work.hasEPUB
                preservation = work.epubPreservationStatus
                metadata = work.metadataSyncStatus
                preservedAt = work.preservedAt
                workID = work.ao3WorkID
                seriesID = work.ao3SeriesID
            }
        }

        @Test func targetedLaunchRepairMatchesTheOldMembershipSweep() throws {
            let reference = try normalizeFixture(using: legacySweep)
            let optimized = try normalizeFixture(using: ReadingQueueService.normalizeAllQueuedWorks(in:))
            #expect(optimized == reference)
            let missing = try #require(optimized["Missing file"])
            #expect(missing.queued && !missing.hasEPUB)
            #expect(missing.preservation == .missingFile)
            let intact = try #require(optimized["Intact file"])
            #expect(intact.queued && intact.hasEPUB)
            #expect(intact.preservation == .preserved)
            let unflagged = try #require(optimized["Unflagged member"])
            #expect(unflagged.queued && unflagged.preservation == .queued)
            #expect(unflagged.workID == 102 && unflagged.seriesID == 42)
            #expect(optimized["Orphaned flag"]?.queued == false)
            #expect(optimized["Unlinked flag"]?.queued == false)
            #expect(optimized["Outside queues"]?.hasEPUB == true)
        }

        private func normalizeFixture(using repair: (ModelContext) -> Void) throws -> [String: WorkState] {
            let manager = FileManager.default
            let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? manager.removeItem(at: directory) }
            let schema = Schema([
                SavedWork.self, Tag.self, Bookmark.self, CustomFont.self, WorkCollection.self,
                ReadingQueue.self, ReadingQueueMembership.self, SavedSearch.self,
                QueueSavedSearchLink.self, SyncTombstone.self
            ])
            let configuration = ModelConfiguration(
                schema: schema, url: directory.appendingPathComponent("Library.store"), cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let setup = ModelContext(container)
            let queue = ReadingQueue(name: "Archive", kind: .custom, sortOrder: 0)
            setup.insert(queue)

            let missing = SavedWork(title: "Missing file", author: "Author")
            let intact = SavedWork(title: "Intact file", author: "Author")
            let unflagged = SavedWork(title: "Unflagged member", author: "Author", sourceURL: "https://ao3.org/works/102")
            let orphan = SavedWork(title: "Orphaned flag", author: "Author")
            let unlinked = SavedWork(title: "Unlinked flag", author: "Author")
            let unqueued = SavedWork(title: "Outside queues", author: "Author")
            for work in [missing, intact, unflagged, orphan, unlinked, unqueued] { setup.insert(work) }
            for work in [missing, intact, unflagged] {
                setup.insert(ReadingQueueMembership(queue: queue, work: work))
            }
            setup.insert(ReadingQueueMembership(queue: nil, work: orphan))
            setup.insert(ReadingQueueMembership(queue: queue, work: nil))
            for work in [missing, intact, orphan] {
                work.isQueuedForLater = true
                work.epubPreservationStatus = .preserved
                work.preservedAt = Date(timeIntervalSince1970: 1_000)
            }
            unflagged.hasEPUB = false
            unflagged.seriesURL = "/series/42"
            unlinked.hasEPUB = false
            unlinked.isQueuedForLater = true
            unlinked.epubPreservationStatus = .queued
            unlinked.metadataSyncStatus = .pending

            let missingURL = missing.fileURL
            let intactURL = intact.fileURL
            try Data("epub".utf8).write(to: intactURL)
            defer {
                try? manager.removeItem(at: intactURL)
                try? manager.removeItem(at: missingURL)
            }
            try Data("epub".utf8).write(to: missingURL)
            try setup.save()
            try manager.removeItem(at: missingURL)

            let context = ModelContext(container)
            context.autosaveEnabled = true
            repair(context)
            #expect(!context.hasChanges)
            let reloaded = ModelContext(container)
            let memberships = try reloaded.fetch(FetchDescriptor<ReadingQueueMembership>())
            #expect(memberships.count == 3)
            #expect(memberships.allSatisfy { $0.queue != nil && $0.work != nil })
            let works = try reloaded.fetch(FetchDescriptor<SavedWork>())
            let states = Dictionary(uniqueKeysWithValues: works.map { ($0.title, WorkState($0)) })

            reloaded.autosaveEnabled = true
            let budget = SaveBestEffortTesting.SaveBudget(1)
            SaveBestEffortTesting.$budget.withValue(budget) {
                ReadingQueueService.normalizeAllQueuedWorks(in: reloaded)
            }
            #expect(budget.remaining == 1)
            return states
        }

        private func legacySweep(_ context: ModelContext) {
            let memberships = (try? context.fetch(FetchDescriptor<ReadingQueueMembership>())) ?? []
            for membership in memberships where membership.queue == nil || membership.work == nil {
                membership.queue?.memberships.removeAll { $0.id == membership.id }
                membership.work?.queueMemberships.removeAll { $0.id == membership.id }
                context.delete(membership)
            }
            let flagged = (try? context.fetch(FetchDescriptor<SavedWork>(
                predicate: #Predicate { $0.isQueuedForLater }
            ))) ?? []
            var seen = Set<UUID>()
            for work in memberships.compactMap(\.work) + flagged where seen.insert(work.id).inserted {
                legacyNormalize(work)
            }
            context.saveBestEffort(reason: "Saving legacy queue normalization failed")
        }

        private func legacyNormalize(_ work: SavedWork) {
            if work.ao3WorkID == nil { work.ao3WorkID = WorkTags.ao3WorkID(from: work.sourceURL) }
            if work.ao3SeriesID == nil { work.ao3SeriesID = ReadingQueueService.ao3SeriesID(from: work.seriesURL) }
            let hasMembership = work.queueMemberships.contains { $0.queue != nil }
            work.isQueuedForLater = hasMembership
            let hasFile = FileManager.default.fileExists(atPath: work.fileURL.path)
            if !hasFile {
                work.hasEPUB = false
                if work.epubPreservationStatus == .preserved { work.epubPreservationStatus = .missingFile }
            }
            if hasMembership {
                if work.hasEPUB, hasFile {
                    if work.epubPreservationStatus != .preserving { work.epubPreservationStatus = .preserved }
                    if work.preservedAt == nil { work.preservedAt = Date() }
                } else if work.epubPreservationStatus == .notPreserved {
                    work.epubPreservationStatus = .queued
                }
                if work.metadataSyncStatus == .unknown, work.needsAO3Refresh { work.metadataSyncStatus = .pending }
            } else if work.epubPreservationStatus != .notPreserved {
                work.epubPreservationStatus = .notPreserved
                work.preservedAt = nil
            }
        }
    }
}
