import Foundation
import SwiftData
import Testing
@testable import Kudos

@MainActor
struct ReadingQueueTests {
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
}
