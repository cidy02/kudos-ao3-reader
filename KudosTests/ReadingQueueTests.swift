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

    @Test func queueOnlyWorkStaysOutOfNormalLibrarySections() throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self
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
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self
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

    @Test func queuedWorkKeepsEPUBWhenMarkedFinished() throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self
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

    @Test func removingLastQueueDeletesQueueOnlyWork() throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self
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

        ReadingQueueService.remove(work, from: queue, in: context)

        #expect(try context.fetch(FetchDescriptor<SavedWork>()).isEmpty)
        #expect(queue.memberships.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func removingQueueFromSavedWorkKeepsRecordAndFile() throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self
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

        ReadingQueueService.remove(work, from: queue, in: context)

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
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self
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
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self
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
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self
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
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self
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
}
