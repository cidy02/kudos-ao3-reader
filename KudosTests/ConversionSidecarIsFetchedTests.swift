import Foundation
import SwiftData
import Testing
@testable import Kudos

/// A preserved original and the record of how it was converted are two files,
/// and they sync independently. The skip that decided whether to fetch either
/// one asked the same question about both — "is the original here?" — and
/// `existingOriginalDocumentURL` deliberately ignores the `.conversion.json`
/// sidecar. So once the document itself landed, its conversion record was
/// skipped by that same test, permanently: the sidecar's own absence was never
/// what was being asked about.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct ConversionSidecarIsFetchedTests {
    private func container() throws -> ModelContainer {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self, ReadingAnnotation.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    private func testDefaults(_ label: String) throws -> UserDefaults {
        let name = "ConversionSidecarIsFetchedTests.\(label).\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func theSidecarArrivesEvenWhenTheOriginalIsAlreadyHere() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Sidecar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let remoteContainer = try container()
        let work = SavedWork(id: UUID(), title: "Converted", author: "Writer")
        work.markModified(Date(timeIntervalSince1970: 9_000))
        remoteContainer.mainContext.insert(work)
        try remoteContainer.mainContext.save()
        let contents = try KudosBackupService.makeContents(
            works: [work], bookmarks: [], fonts: [], readingQueues: [],
            defaults: try testDefaults("remote")
        )

        let syncDirectory = folder.appendingPathComponent(FolderSyncService.syncDirectoryName)
        let originalsDirectory = syncDirectory
            .appendingPathComponent(FolderSyncService.originalsSubdirectoryName)
        try FileManager.default.createDirectory(
            at: originalsDirectory, withIntermediateDirectories: true
        )
        try contents.manifestData().write(
            to: syncDirectory.appendingPathComponent(FolderSyncService.manifestFileName),
            options: .atomic
        )
        // Remote holds both halves.
        let originalBytes = Data("%PDF-1.7 the document they imported".utf8)
        try originalBytes.write(
            to: originalsDirectory.appendingPathComponent("\(work.id.uuidString).pdf"),
            options: .atomic
        )
        let record = WorkConversionRecord(format: "pdf", originalFileName: "thesis.pdf")
        try JSONEncoder().encode(record).write(
            to: originalsDirectory
                .appendingPathComponent("\(work.id.uuidString).conversion.json"),
            options: .atomic
        )

        // This device already fetched the document on an earlier pass, but the
        // sidecar was not readable at the time.
        let localContainer = try container()
        let localContext = localContainer.mainContext
        let localOriginal = Storage.originalDocumentURL(for: work.id, fileExtension: "pdf")
        try FileManager.default.createDirectory(
            at: localOriginal.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try originalBytes.write(to: localOriginal, options: .atomic)
        let localRecord = WorkConversionRecord.url(for: work.id)
        try? FileManager.default.removeItem(at: localRecord)
        defer {
            try? FileManager.default.removeItem(at: localOriginal)
            try? FileManager.default.removeItem(at: localRecord)
        }

        let defaults = try testDefaults("local")
        defer { FolderSyncService.disconnect(defaults: defaults) }
        try FolderSyncService.connect(to: folder, defaults: defaults)
        _ = try await FolderSyncService.syncDown(in: localContext, defaults: defaults)

        #expect(FileManager.default.fileExists(atPath: localRecord.path))
    }
}
}
