import Foundation
import SwiftData
import Testing
@testable import Kudos

/// Update download replaces the EPUB and advances the chapter watermark.
/// It must not restart a half-read or finished work. No test here talks to AO3:
/// the download is the same closure seam `ReadingQueueService.preserve` uses.
@MainActor
struct WorkReaderPreparationUpdateTests {
    private static let locator = #"{"href":"chapter-4.xhtml"}"#
    private static let readDate = Date(timeIntervalSince1970: 1_700_000_000)
    private static let oldModified = Date(timeIntervalSince1970: 1_600_000_000)

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let work: SavedWork
        let original: Data
    }

    private final class DownloadLog {
        var ids: [Int] = []
        var make: () throws -> URL = { throw StubDownloadError() }
        var temps: [URL] = []

        func stage(_ url: URL) -> URL {
            temps.append(url)
            return url
        }

        func removeTemps() {
            for url in temps {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private struct StubDownloadError: Error {}

    /// `log.make` stores its closure, so a freed-during-download stamp cannot
    /// be a local `var`.
    private final class FreedStamp {
        var modified = Date.distantPast
        var preservedAt: Date?
        var digest = ""
    }

    @Test func updateKeepsReadingPositionAndAdvancesWatermark() async throws {
        let fixture = try makeFixture(queued: true)
        defer { try? FileManager.default.removeItem(at: fixture.work.fileURL) }
        let log = DownloadLog()
        log.make = { try Self.stageSample(into: log) }
        let preservedBefore = fixture.work.preservedAt

        try await update(fixture.work, in: fixture.context, log: log)

        let work = fixture.work
        #expect(log.ids == [476])
        #expect(work.isFinished)
        #expect(work.lastSpineIndex == 4)
        #expect(work.lastScrollFraction == 0.5)
        #expect(work.legacyReaderProgress == 0.75)
        #expect(work.readiumLocator == Self.locator)
        #expect(work.lastReadDate == Self.readDate)
        #expect(work.progressModifiedAt == Self.readDate)
        #expect(work.hasEPUB)
        #expect(work.isFavorite)
        #expect(work.knownChapterCount == 8)
        #expect(!work.hasUpdate)
        #expect(!work.remoteEPUBPending)
        #expect(work.epubDigest == Storage.fileDigest(at: work.fileURL))
        #expect(work.epubDigest != "old-digest")
        #expect(work.epubPreservationStatus == .preserved)
        #expect(work.preservedAt != preservedBefore)
        #expect(work.lastModifiedAt != Self.oldModified)
        #expect(try EPUBDocument.metadata(ofEPUBAt: work.fileURL).title == "A Test Work")
        #expect(try Data(contentsOf: work.fileURL) != fixture.original)

        let stored = try refetch(work.id, in: fixture.container)
        #expect(stored.isFinished)
        #expect(stored.lastSpineIndex == 4)
        #expect(stored.lastScrollFraction == 0.5)
        #expect(stored.legacyReaderProgress == 0.75)
        #expect(stored.readiumLocator == Self.locator)
        #expect(stored.knownChapterCount == 8)
        #expect(stored.epubPreservationStatus == .preserved)
        log.removeTemps()
    }

    @Test func updateOfAnUnqueuedWorkDoesNotStampPreservation() async throws {
        let fixture = try makeFixture(queued: false)
        defer { try? FileManager.default.removeItem(at: fixture.work.fileURL) }
        let log = DownloadLog()
        log.make = { try Self.stageSample(into: log) }

        try await update(fixture.work, in: fixture.context, log: log)

        #expect(fixture.work.epubPreservationStatus == .notPreserved)
        #expect(fixture.work.preservedAt == nil)
        #expect(fixture.work.isFinished)
        #expect(fixture.work.lastSpineIndex == 4)
        #expect(fixture.work.knownChapterCount == 8)
        log.removeTemps()
    }

    @Test func failedDownloadLeavesFileAndFieldsUntouched() async throws {
        let fixture = try makeFixture(queued: true)
        defer { try? FileManager.default.removeItem(at: fixture.work.fileURL) }
        let log = DownloadLog()
        log.make = { throw StubDownloadError() }
        let preservedAt = fixture.work.preservedAt

        await #expect(throws: StubDownloadError.self) {
            try await update(fixture.work, in: fixture.context, log: log)
        }

        #expect(log.ids == [476])
        try expectUntouched(fixture.work, original: fixture.original)
        #expect(fixture.work.epubPreservationStatus == .queued)
        #expect(fixture.work.preservedAt == preservedAt)
        #expect(fixture.work.lastModifiedAt == Self.oldModified)

        let stored = try refetch(fixture.work.id, in: fixture.container)
        #expect(stored.knownChapterCount == 5)
        #expect(stored.lastSpineIndex == 4)
        #expect(stored.isFinished)
        #expect(stored.readiumLocator == Self.locator)
        #expect(try Data(contentsOf: fixture.work.fileURL) == fixture.original)
    }

    @Test func invalidPackageLeavesFileAndFieldsUntouched() async throws {
        let fixture = try makeFixture(queued: false)
        defer { try? FileManager.default.removeItem(at: fixture.work.fileURL) }
        let log = DownloadLog()
        log.make = { try Self.stageInvalid(into: log) }

        await #expect(throws: (any Error).self) {
            try await update(fixture.work, in: fixture.context, log: log)
        }

        #expect(log.ids == [476])
        try expectUntouched(fixture.work, original: fixture.original)
        #expect(fixture.work.epubPreservationStatus == .notPreserved)
        #expect(FileManager.default.fileExists(atPath: fixture.work.fileURL.path))
        log.removeTemps()
    }

    @Test func workWithNoEPUBDoesNotDownload() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.work.fileURL) }
        fixture.work.hasEPUB = false
        let log = DownloadLog()
        log.make = { try Self.stageSample(into: log) }

        try await update(fixture.work, in: fixture.context, log: log)

        #expect(log.ids.isEmpty)
        #expect(log.temps.isEmpty)
        #expect(!fixture.work.hasEPUB)
        #expect(fixture.work.knownChapterCount == 5)
        #expect(fixture.work.hasUpdate)
        #expect(fixture.work.lastSpineIndex == 4)
        #expect(fixture.work.epubDigest == "old-digest")
        #expect(fixture.work.lastModifiedAt == Self.oldModified)
        #expect(try Data(contentsOf: fixture.work.fileURL) == fixture.original)
    }

    /// The file can disappear after the download has started: free space, or
    /// the held-copy sweep. The temp must not become the installed file, and
    /// the watermark stays where the free left it.
    @Test func fileFreedDuringTheDownloadRemovesTheTempAndLeavesFields() async throws {
        let fixture = try makeFixture(queued: true)
        defer { try? FileManager.default.removeItem(at: fixture.work.fileURL) }
        let log = DownloadLog()
        let work = fixture.work
        let stamp = FreedStamp()
        log.make = {
            WorkLifecycle.freeEPUB(work)
            stamp.modified = work.lastModifiedAt
            stamp.preservedAt = work.preservedAt
            stamp.digest = work.epubDigest
            return try Self.stageSample(into: log)
        }

        try await update(work, in: fixture.context, log: log)

        #expect(log.ids == [476])
        #expect(!log.temps.isEmpty)
        #expect(log.temps.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        #expect(!work.hasEPUB)
        #expect(work.knownChapterCount == 5)
        #expect(work.hasUpdate)
        #expect(work.isFinished)
        #expect(work.lastSpineIndex == 4)
        #expect(work.lastScrollFraction == 0.5)
        #expect(work.legacyReaderProgress == 0.75)
        #expect(work.readiumLocator == Self.locator)
        #expect(work.epubDigest == stamp.digest)
        #expect(work.epubPreservationStatus == .missingFile)
        #expect(work.preservedAt == stamp.preservedAt)
        #expect(work.lastModifiedAt == stamp.modified)
        #expect(!work.remoteEPUBPending)
        #expect(!FileManager.default.fileExists(atPath: work.fileURL.path))
    }

    @Test func workWithoutAnUpdateDoesNotDownload() async throws {
        let fixture = try makeFixture(chapters: "8/12", known: 8)
        defer { try? FileManager.default.removeItem(at: fixture.work.fileURL) }
        let log = DownloadLog()

        try await update(fixture.work, in: fixture.context, log: log)

        #expect(log.ids.isEmpty)
        try expectUntouched(fixture.work, original: fixture.original, known: 8)
    }

    @Test func missingAO3IDDoesNotDownload() async throws {
        let fixture = try makeFixture(ao3ID: nil, sourceURL: "https://example.com/library/1")
        defer { try? FileManager.default.removeItem(at: fixture.work.fileURL) }
        let log = DownloadLog()

        do {
            try await update(fixture.work, in: fixture.context, log: log)
            Issue.record("A work with no AO3 id must not update")
        } catch {
            #expect(error.localizedDescription.contains("re-downloaded"))
        }

        #expect(log.ids.isEmpty)
        try expectUntouched(fixture.work, original: fixture.original)
        #expect(fixture.work.lastModifiedAt == Self.oldModified)
    }

    @Test func ao3IDComesFromTheSourceURLWhenTheFieldIsEmpty() async throws {
        let fixture = try makeFixture(
            ao3ID: nil,
            sourceURL: "https://archiveofourown.org/works/99"
        )
        defer { try? FileManager.default.removeItem(at: fixture.work.fileURL) }
        let log = DownloadLog()
        log.make = { try Self.stageSample(into: log) }

        try await update(fixture.work, in: fixture.context, log: log)

        #expect(log.ids == [99])
        #expect(fixture.work.lastSpineIndex == 4)
        #expect(fixture.work.isFinished)
        #expect(fixture.work.knownChapterCount == 8)
        log.removeTemps()
    }

    @Test func restoreReadableEPUBStillResetsTheReadingPosition() async throws {
        let fixture = try makeFixture(queued: true)
        defer { try? FileManager.default.removeItem(at: fixture.work.fileURL) }
        let log = DownloadLog()
        log.make = { try Self.stageSample(into: log) }

        try await WorkReaderPreparation.restoreReadableEPUB(
            for: fixture.work,
            in: fixture.context,
            downloadEPUB: { id in
                log.ids.append(id)
                return try log.make()
            }
        )

        let work = fixture.work
        #expect(log.ids == [476])
        #expect(!work.isFinished)
        #expect(work.lastSpineIndex == 0)
        #expect(work.lastScrollFraction == 0)
        #expect(work.legacyReaderProgress == nil)
        // Restore still does not clear the Readium locator or the watermark.
        #expect(work.readiumLocator == Self.locator)
        #expect(work.knownChapterCount == 5)
        #expect(work.hasUpdate)
        #expect(work.hasEPUB)
        #expect(work.epubPreservationStatus == .preserved)
        #expect(work.preservedAt != nil)
        log.removeTemps()
    }

    @Test func updateDownloadFeedsTheSharedFraction() {
        let queue = DownloadQueue()
        let work = SavedWork(title: "Update", author: "Writer")
        let start = Date(timeIntervalSince1970: 10_000)
        #expect(queue.liveDownloadFraction(for: work, at: start) == nil)

        let token = UUID()
        #expect(queue.beginUpdateDownload(for: work.id, token: token, at: start))
        #expect(queue.isDownloading(work))
        #expect(queue.downloadFraction(for: work, at: start) == 0)
        #expect(queue.liveDownloadFraction(for: work, at: start) == 0)

        queue.noteUpdateDownloadProgress(0.4, for: work.id)
        queue.noteUpdateDownloadProgress(0.2, for: work.id)
        #expect(queue.downloadFraction(for: work, at: start) == 0.4)

        let later = start.addingTimeInterval(100)
        let crept = queue.downloadFraction(for: work, at: later)
        #expect(crept != nil)
        #expect((crept ?? 0) > 0.4)
        #expect((crept ?? 1) < 1)
        #expect(queue.liveDownloadFraction(for: work, at: later) == crept)

        queue.endUpdateDownload(for: work.id, token: token)
        queue.noteUpdateDownloadProgress(1, for: work.id)
        #expect(queue.liveDownloadFraction(for: work, at: later) == nil)
        #expect(!queue.isDownloading(work))
    }

    /// Two detail screens can offer the circle for one work. The second begin
    /// loses, and its end must not clear the entry the first begin created.
    @Test func aSecondUpdateBeginForTheSameWorkReturnsFalse() {
        let queue = DownloadQueue()
        let work = SavedWork(title: "Update", author: "Writer")
        let start = Date(timeIntervalSince1970: 10_000)
        let first = UUID()
        #expect(queue.beginUpdateDownload(for: work.id, token: first, at: start))
        #expect(queue.isDownloading(work))

        let second = UUID()
        #expect(!queue.beginUpdateDownload(for: work.id, token: second, at: start.addingTimeInterval(1)))
        #expect(queue.downloadFraction(for: work, at: start) == 0)

        queue.endUpdateDownload(for: work.id, token: second)
        #expect(queue.isDownloading(work))

        queue.endUpdateDownload(for: work.id, token: first)
        #expect(!queue.isDownloading(work))
        #expect(queue.liveDownloadFraction(for: work, at: start) == nil)
    }

    // MARK: - Fixture

    private func update(
        _ work: SavedWork,
        in context: ModelContext,
        log: DownloadLog
    ) async throws {
        try await WorkReaderPreparation.updateDownloadedEPUB(
            for: work,
            in: context,
            downloadEPUB: { id in
                log.ids.append(id)
                return try log.make()
            }
        )
    }

    private func expectUntouched(
        _ work: SavedWork,
        original: Data,
        known: Int = 5
    ) throws {
        #expect(work.isFinished)
        #expect(work.lastSpineIndex == 4)
        #expect(work.lastScrollFraction == 0.5)
        #expect(work.legacyReaderProgress == 0.75)
        #expect(work.readiumLocator == Self.locator)
        #expect(work.knownChapterCount == known)
        #expect(work.epubDigest == "old-digest")
        #expect(work.remoteEPUBPending)
        #expect(work.hasEPUB)
        #expect(work.isFavorite)
        #expect(work.lastReadDate == Self.readDate)
        #expect(work.progressModifiedAt == Self.readDate)
        #expect(work.lastModifiedAt == Self.oldModified)
        #expect(try Data(contentsOf: work.fileURL) == original)
    }

    private func makeFixture(
        chapters: String = "8/12",
        known: Int = 5,
        ao3ID: Int? = 476,
        sourceURL: String = "",
        queued: Bool = false
    ) throws -> Fixture {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let work = SavedWork(title: "Half Read", author: "Writer", sourceURL: sourceURL)
        work.chapters = chapters
        work.knownChapterCount = known
        work.ao3WorkID = ao3ID
        work.isFinished = true
        work.lastSpineIndex = 4
        work.lastScrollFraction = 0.5
        work.legacyReaderProgress = 0.75
        work.readiumLocator = Self.locator
        work.lastReadDate = Self.readDate
        work.progressModifiedAt = Self.readDate
        work.lastModifiedAt = Self.oldModified
        work.remoteEPUBPending = true
        work.epubDigest = "old-digest"
        work.isFavorite = true
        work.hasEPUB = true
        work.isQueuedForLater = queued
        if queued {
            work.epubPreservationStatus = .queued
        }
        context.insert(work)
        let original = Data("original-epub".utf8)
        try FileManager.default.createDirectory(
            at: work.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try original.write(to: work.fileURL)
        try context.save()
        return Fixture(container: container, context: context, work: work, original: original)
    }

    private func refetch(_ id: UUID, in container: ModelContainer) throws -> SavedWork {
        let context = ModelContext(container)
        let works = try context.fetch(FetchDescriptor<SavedWork>())
        return try #require(works.first { $0.id == id })
    }

    private nonisolated static func stageSample(into log: DownloadLog) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("epub")
        try FileManager.default.copyItem(at: try EPUBTests.sampleEPUB, to: url)
        return log.stage(url)
    }

    private nonisolated static func stageInvalid(into log: DownloadLog) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("epub")
        try Data("not an epub".utf8).write(to: url)
        return log.stage(url)
    }
}
