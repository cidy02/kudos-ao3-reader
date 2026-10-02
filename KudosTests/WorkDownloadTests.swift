import Foundation
import SwiftData
import Testing
@testable import Kudos

/// Owner, 2026-10-01 (reversing 2026-09-28): Download / Remove Download follow
/// what the reader chose to keep. A copy fetched only to read is not a download.
@MainActor
@Suite(.serialized)
struct WorkDownloadTests {
    private func context() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self, ReadingAnnotation.self,
            ReadingSession.self, ReadingFavorite.self, FandomReadWatermark.self
        ])
        return ModelContext(try ModelContainer(
            for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
    }

    private func work(onDevice: Bool, in context: ModelContext) -> SavedWork {
        let work = SavedWork(title: "W", author: "A")
        work.ao3WorkID = Int.random(in: 1 ... 9_000_000)
        context.insert(work)
        if onDevice {
            try? FileManager.default.createDirectory(
                at: work.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try? Data([0]).write(to: work.fileURL)
        } else {
            work.hasEPUB = false
        }
        return work
    }

    @Test func onlyAKeptCopyOffersRemove() throws {
        let context = try context()
        let readingCopy = work(onDevice: true, in: context)
        readingCopy.isSaved = false
        #expect(WorkDownload.action(for: readingCopy) == .download)
        #expect(!readingCopy.isDownloaded)
        readingCopy.isSaved = true
        #expect(WorkDownload.action(for: readingCopy) == .removeDownload)
        #expect(readingCopy.isDownloaded)
        let missing = work(onDevice: false, in: context)
        missing.isSaved = true
        #expect(WorkDownload.action(for: missing) == .download)
        try? FileManager.default.removeItem(at: readingCopy.fileURL)
    }

    /// Download on a copy fetched to read keeps it at once, fetching nothing.
    @Test func downloadKeepsAReadingCopyWithoutFetching() async throws {
        let context = try context()
        let readingCopy = work(onDevice: true, in: context)
        try await WorkDownload.perform(.download, on: readingCopy, in: context)
        #expect(readingCopy.isSaved && readingCopy.isDownloaded)
        try? FileManager.default.removeItem(at: readingCopy.fileURL)
    }

    @Test func aKeepOfflineQueueNamesItselfInsteadOfRemove() throws {
        let context = try context()
        let kept = work(onDevice: true, in: context)
        let queue = ReadingQueue(name: "Neon reread")
        context.insert(queue)
        _ = ReadingQueueService.add(kept, to: queue, in: context)
        #expect(WorkDownload.action(for: kept) == .keptBy("Neon reread"))
        try? FileManager.default.removeItem(at: kept.fileURL)
    }

    @Test func removeDownloadDeletesTheFileAndKeepsTheRecord() async throws {
        let context = try context()
        let downloaded = work(onDevice: true, in: context)
        downloaded.isSaved = true
        try await WorkDownload.perform(.removeDownload, on: downloaded, in: context)
        #expect(!FileManager.default.fileExists(atPath: downloaded.fileURL.path))
        #expect(!downloaded.hasEPUB)
        #expect(!downloaded.isSaved)
        #expect(WorkDownload.action(for: downloaded) == .download)
    }

    @Test func bulkRemoveOnlyWhenEverythingIsOnTheDevice() throws {
        let context = try context()
        let onDevice = work(onDevice: true, in: context)
        onDevice.isSaved = true
        let missing = work(onDevice: false, in: context)
        #expect(WorkDownload.bulkAction(for: [onDevice]) == .removeDownload)
        #expect(WorkDownload.bulkAction(for: [onDevice, missing]) == .download)
        #expect(WorkDownload.bulkLabel(.removeDownload).title == "Remove Downloads")
        try? FileManager.default.removeItem(at: onDevice.fileURL)
    }
}
