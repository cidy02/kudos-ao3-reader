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
            SavedSearch.self, QueueSavedSearchLink.self, SyncTombstone.self, ReadingAnnotation.self
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

    @Test func thePlaceholderKeepsTheOriginalPendingUntilItsBytesArrive() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("OriginalPlaceholder-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let remoteContainer = try container()
        let work = SavedWork(title: "Converted on another device", author: "Writer")
        work.hasEPUB = false
        remoteContainer.mainContext.insert(work)
        try remoteContainer.mainContext.save()
        let contents = try KudosBackupService.makeContents(
            works: [work], bookmarks: [], fonts: [], readingQueues: [],
            defaults: try testDefaults("placeholder-remote")
        )
        let syncDirectory = folder.appendingPathComponent(FolderSyncService.syncDirectoryName)
        let originalsDirectory = syncDirectory.appendingPathComponent(FolderSyncService.originalsSubdirectoryName)
        try FileManager.default.createDirectory(at: originalsDirectory, withIntermediateDirectories: true)
        let manifestURL = syncDirectory.appendingPathComponent(FolderSyncService.manifestFileName)
        try contents.manifestData().write(to: manifestURL)
        let name = "\(work.id.uuidString.lowercased()).pdf"
        let placeholder = originalsDirectory.appendingPathComponent(".\(name).icloud")
        try Data("placeholder metadata".utf8).write(to: placeholder)

        let localContainer = try container()
        let context = localContainer.mainContext
        let defaults = try testDefaults("placeholder-local")
        defer { FolderSyncService.disconnect(defaults: defaults) }
        try FolderSyncService.connect(to: folder, defaults: defaults)
        let local = Storage.originalDocumentURL(for: work.id, fileExtension: "pdf")
        defer { try? FileManager.default.removeItem(at: local) }

        let first = try await FolderSyncService.syncDown(in: context, defaults: defaults)
        #expect(first.didReadRemoteFile)
        #expect(!FileManager.default.fileExists(atPath: local.path))

        // Simulate iCloud materializing the original without rewriting the manifest.
        let bytes = Data("%PDF-1.7 the original file".utf8)
        try bytes.write(to: originalsDirectory.appendingPathComponent(name))
        try FileManager.default.removeItem(at: placeholder)
        let second = try await FolderSyncService.syncDown(in: context, defaults: defaults)
        #expect(!second.skippedUnchanged)
        #expect(try Data(contentsOf: local) == bytes)

        let third = try await FolderSyncService.syncDown(in: context, defaults: defaults)
        #expect(third.skippedUnchanged)
    }

    @Test func aFailedOriginalWriteIsReportedAndRetriedWithoutChangingTheRemoteManifest() async throws {
        let work = SavedWork(title: "Original to restore", author: "Writer")
        let defaults = try testDefaults("retry")
        let remote = try makeRemoteFolder(for: work, defaults: defaults)
        defer { try? FileManager.default.removeItem(at: remote.folder) }
        defer { FolderSyncService.disconnect(defaults: defaults) }
        let local = Storage.originalDocumentURL(for: work.id, fileExtension: "pdf")
        defer { try? FileManager.default.removeItem(at: local) }
        defer { WorkConversionRecord.delete(for: work.id) }
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        let bytes = Data("%PDF-1.7 recover this source".utf8)
        let shared = remote.originals.appendingPathComponent(local.lastPathComponent)
        try bytes.write(to: shared)
        let record = WorkConversionRecord(format: "pdf", originalFileName: "source.pdf")
        let recordURL = WorkConversionRecord.url(for: work.id)
        let sharedRecord = remote.originals.appendingPathComponent(recordURL.lastPathComponent)
        try JSONEncoder().encode(record).write(to: sharedRecord)
        let localContainer = try container()
        let context = localContainer.mainContext

        let first = try await FolderSyncService.syncNow(in: context, defaults: defaults)
        #expect(first.failedOriginalIDs == Set([work.id]))
        #expect(!first.didWriteRemoteFile)
        #expect(WorkConversionRecord.read(for: work.id) == nil)
        #expect(FolderSyncService.snapshot(defaults: defaults).lastError.contains("1 original couldn't be restored"))
        #expect(try Data(contentsOf: shared) == bytes)

        try FileManager.default.removeItem(at: local)
        let second = try await FolderSyncService.syncDown(in: context, defaults: defaults)
        #expect(!second.skippedUnchanged)
        #expect(second.failedOriginalIDs.isEmpty)
        #expect(try Data(contentsOf: local) == bytes)
        #expect(WorkConversionRecord.read(for: work.id) == record)
        #expect(FolderSyncService.snapshot(defaults: defaults).lastError.isEmpty)
        let third = try await FolderSyncService.syncDown(in: context, defaults: defaults)
        #expect(third.skippedUnchanged)
    }

    @Test func aNewerOriginalReplacesAnOlderOneAndItsRecordEvenWhenTheExtensionChanges() async throws {
        let work = SavedWork(title: "Corrected original", author: "Writer")
        let defaults = try testDefaults("corrected")
        let remote = try makeRemoteFolder(for: work, defaults: defaults)
        defer { try? FileManager.default.removeItem(at: remote.folder) }
        defer { FolderSyncService.disconnect(defaults: defaults) }
        let previous = Storage.originalDocumentURL(for: work.id, fileExtension: "pdf")
        let corrected = Storage.originalDocumentURL(for: work.id, fileExtension: "html")
        defer {
            for url in [previous, corrected] { try? FileManager.default.removeItem(at: url) }
            WorkConversionRecord.delete(for: work.id)
        }
        let previousBytes = Data("%PDF-1.7 the older source".utf8)
        let correctedBytes = Data("<html>The corrected source</html>".utf8)
        try previousBytes.write(to: previous)
        let oldRecord = WorkConversionRecord(
            format: "pdf", originalFileName: "source.pdf", convertedAt: Date(timeIntervalSince1970: 1_000)
        )
        let newRecord = WorkConversionRecord(
            format: "html", originalFileName: "source.html", convertedAt: Date(timeIntervalSince1970: 2_000)
        )
        try JSONEncoder().encode(oldRecord).write(to: WorkConversionRecord.url(for: work.id))
        let sharedPrevious = remote.originals.appendingPathComponent(previous.lastPathComponent)
        let sharedCorrected = remote.originals.appendingPathComponent(corrected.lastPathComponent)
        let recordURL = WorkConversionRecord.url(for: work.id)
        let sharedRecord = remote.originals.appendingPathComponent(recordURL.lastPathComponent)
        try correctedBytes.write(to: sharedCorrected)
        try JSONEncoder().encode(newRecord).write(to: sharedRecord)
        let localContainer = try container()
        let context = localContainer.mainContext

        // A blocked destination must leave the previous copy and record reachable.
        try FileManager.default.createDirectory(at: corrected, withIntermediateDirectories: true)
        let failed = try await FolderSyncService.syncNow(in: context, defaults: defaults)
        #expect(failed.failedOriginalIDs == Set([work.id]))
        #expect(try Data(contentsOf: previous) == previousBytes)
        #expect(WorkConversionRecord.read(for: work.id) == oldRecord)
        #expect(try Data(contentsOf: sharedCorrected) == correctedBytes)
        try FileManager.default.removeItem(at: corrected)

        _ = try await FolderSyncService.syncDown(in: context, defaults: defaults)
        #expect(try Data(contentsOf: corrected) == correctedBytes)
        #expect(!FileManager.default.fileExists(atPath: previous.path))
        #expect(WorkConversionRecord.read(for: work.id) == newRecord)

        // Model an older client publishing its copy. A full pass must retain
        // the local correction and republish it safely.
        try FileManager.default.removeItem(at: sharedCorrected)
        try previousBytes.write(to: sharedPrevious)
        try JSONEncoder().encode(oldRecord).write(to: sharedRecord, options: .atomic)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 3_000)], ofItemAtPath: remote.manifest.path
        )
        let upload = try await FolderSyncService.syncNow(in: context, defaults: defaults)
        #expect(upload.didWriteRemoteFile)
        #expect(try Data(contentsOf: corrected) == correctedBytes)
        #expect(WorkConversionRecord.read(for: work.id) == newRecord)
        #expect(try Data(contentsOf: sharedCorrected) == correctedBytes)
        #expect(!FileManager.default.fileExists(atPath: sharedPrevious.path))
        #expect(try JSONDecoder().decode(WorkConversionRecord.self, from: Data(contentsOf: sharedRecord)) == newRecord)
    }

    @Test func identicalBytesKeepTheirFileEvenWhenTheRemoteRecordIsNewer() async throws {
        let work = SavedWork(title: "Same source", author: "Writer")
        let defaults = try testDefaults("identical")
        let remote = try makeRemoteFolder(for: work, defaults: defaults)
        defer { try? FileManager.default.removeItem(at: remote.folder) }
        defer { FolderSyncService.disconnect(defaults: defaults) }
        let local = Storage.originalDocumentURL(for: work.id, fileExtension: "pdf")
        let recordURL = WorkConversionRecord.url(for: work.id)
        defer {
            try? FileManager.default.removeItem(at: local)
            WorkConversionRecord.delete(for: work.id)
        }
        let bytes = Data("%PDF-1.7 identical source".utf8)
        try bytes.write(to: local)
        let shared = remote.originals.appendingPathComponent(local.lastPathComponent)
        try bytes.write(to: shared)
        var record = WorkConversionRecord(
            format: "pdf", originalFileName: "source.pdf", convertedAt: Date(timeIntervalSince1970: 1_000)
        )
        try JSONEncoder().encode(record).write(to: recordURL)
        record.convertedAt = Date(timeIntervalSince1970: 2_000)
        try JSONEncoder().encode(record).write(to: remote.originals.appendingPathComponent(recordURL.lastPathComponent))

        let modified = Date(timeIntervalSince1970: 10_000)
        for url in [local, shared] {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
        let localContainer = try container()
        let context = localContainer.mainContext
        _ = try await FolderSyncService.syncNow(in: context, defaults: defaults)

        #expect(WorkConversionRecord.read(for: work.id) == record)
        for url in [local, shared] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            #expect(attributes[.modificationDate] as? Date == modified)
        }
    }

    private func makeRemoteFolder(
        for work: SavedWork, defaults: UserDefaults
    ) throws -> (folder: URL, originals: URL, manifest: URL) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("VersionedOriginal-\(UUID().uuidString)", isDirectory: true)
        let syncDirectory = folder.appendingPathComponent(FolderSyncService.syncDirectoryName)
        let originals = syncDirectory.appendingPathComponent(FolderSyncService.originalsSubdirectoryName)
        let manifest = syncDirectory.appendingPathComponent(FolderSyncService.manifestFileName)
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        let contents = try KudosBackupService.makeContents(
            works: [work], bookmarks: [], fonts: [], readingQueues: [], defaults: defaults
        )
        try contents.manifestData().write(to: manifest)
        try FolderSyncService.connect(to: folder, defaults: defaults)
        return (folder, originals, manifest)
    }
}
}
