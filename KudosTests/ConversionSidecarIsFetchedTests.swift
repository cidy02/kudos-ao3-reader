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

    @Test(arguments: [false, true])
    func aPendingOriginalStillAllowsOtherChangesToUpload(remapsWorkID: Bool) async throws {
        let work = SavedWork(title: "Converted on another device", author: "Writer")
        if remapsWorkID { work.ao3WorkID = 12345 }
        let defaults = try testDefaults("placeholder")
        let remote = try makeRemoteFolder(for: work, defaults: defaults)
        defer { try? FileManager.default.removeItem(at: remote.folder) }
        defer { FolderSyncService.disconnect(defaults: defaults) }
        let shared = remote.originals.appendingPathComponent("\(work.id.uuidString.lowercased()).pdf")
        let placeholder = remote.originals.appendingPathComponent(".\(shared.lastPathComponent).icloud")
        let placeholderBytes = Data("placeholder metadata".utf8)
        try placeholderBytes.write(to: placeholder)
        let oldRecord = WorkConversionRecord(
            format: "pdf", originalFileName: "source.pdf", convertedAt: Date(timeIntervalSince1970: 1_000)
        )
        var newRecord = oldRecord
        newRecord.convertedAt = Date(timeIntervalSince1970: 2_000)
        let sharedRecord = WorkConversionRecord.url(for: work.id, in: remote.originals)
        let sharedRecordBytes = try JSONEncoder().encode(newRecord)
        try sharedRecordBytes.write(to: sharedRecord)
        let orphanID = UUID()
        let orphan = Storage.originalDocumentURL(for: orphanID, fileExtension: "pdf", in: remote.originals)
        let orphanRecord = WorkConversionRecord.url(for: orphanID, in: remote.originals)
        try Data("%PDF-1.7 deleted work's source".utf8).write(to: orphan)
        try sharedRecordBytes.write(to: orphanRecord)

        let localContainer = try container()
        let context = localContainer.mainContext
        let localWork = SavedWork(id: remapsWorkID ? UUID() : work.id, title: work.title, author: work.author)
        localWork.ao3WorkID = work.ao3WorkID
        let newWork = SavedWork(title: "New local work", author: "Writer")
        newWork.lastSpineIndex = 3
        newWork.markProgressModified()
        context.insert(localWork)
        context.insert(newWork)
        try context.save()

        let local = Storage.originalDocumentURL(for: localWork.id, fileExtension: "pdf")
        let newLocal = Storage.originalDocumentURL(for: newWork.id, fileExtension: "pdf")
        defer {
            try? FileManager.default.removeItem(at: local)
            try? FileManager.default.removeItem(at: newLocal)
            WorkConversionRecord.delete(for: localWork.id)
            WorkConversionRecord.delete(for: newWork.id)
        }
        let oldBytes = Data("%PDF-1.7 previous source".utf8)
        let newLocalBytes = Data("%PDF-1.7 source for the new work".utf8)
        try oldBytes.write(to: local)
        try newLocalBytes.write(to: newLocal)
        try JSONEncoder().encode(oldRecord).write(to: WorkConversionRecord.url(for: localWork.id))
        try JSONEncoder().encode(oldRecord).write(to: WorkConversionRecord.url(for: newWork.id))

        let first = try await FolderSyncService.syncUp(in: context, defaults: defaults)
        #expect(first.pendingOriginalIDs == Set([work.id]))
        #expect(first.didWriteRemoteFile)
        #expect(first.omittedOriginalTitles.isEmpty)
        let manifest = try KudosBackupContents.decodeManifest(Data(contentsOf: remote.manifest))
        #expect(manifest.works.contains { $0.id == newWork.id && $0.lastSpineIndex == 3 })
        #expect(manifest.works.contains { $0.id == work.id })
        let newShared = remote.originals.appendingPathComponent(newLocal.lastPathComponent)
        #expect(try Data(contentsOf: newShared) == newLocalBytes)
        let newSharedRecord = WorkConversionRecord.url(for: newWork.id, in: remote.originals)
        let newSharedRecordBytes = try Data(contentsOf: newSharedRecord)
        #expect(try JSONDecoder().decode(WorkConversionRecord.self, from: newSharedRecordBytes) == oldRecord)
        #expect(try Data(contentsOf: placeholder) == placeholderBytes)
        #expect(try Data(contentsOf: sharedRecord) == sharedRecordBytes)
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
        #expect(!FileManager.default.fileExists(atPath: orphanRecord.path))
        #expect(!FileManager.default.fileExists(atPath: shared.path))
        let remappedShared = remote.originals.appendingPathComponent(local.lastPathComponent)
        if remapsWorkID {
            #expect(!FileManager.default.fileExists(atPath: remappedShared.path))
        }

        // Simulate iCloud materializing the original without rewriting the manifest.
        let bytes = Data("%PDF-1.7 the newer original file".utf8)
        try bytes.write(to: shared)
        try FileManager.default.removeItem(at: placeholder)
        let second = try await FolderSyncService.syncDown(in: context, defaults: defaults)
        #expect(!second.skippedUnchanged)
        #expect(second.pendingOriginalIDs.isEmpty)
        #expect(second.failedOriginalIDs.isEmpty)
        #expect(try Data(contentsOf: local) == bytes)
        #expect(WorkConversionRecord.read(for: localWork.id) == newRecord)

        let third = try await FolderSyncService.syncUp(in: context, defaults: defaults)
        #expect(third.skippedUnchanged)
        if remapsWorkID {
            #expect(try Data(contentsOf: remappedShared) == bytes)
            #expect(!FileManager.default.fileExists(atPath: shared.path))
        }
    }

    @Test func aFailedOriginalWriteIsReportedAndRetriedAfterUploading() async throws {
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
        #expect(first.didWriteRemoteFile)
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

    @Test func anUploadLeavesTheFoldersNewerOriginalAndRecordInPlace() async throws {
        let work = SavedWork(title: "Corrected on another device", author: "Writer")
        let defaults = try testDefaults("newer-in-folder")
        let remote = try makeRemoteFolder(for: work, defaults: defaults)
        defer { try? FileManager.default.removeItem(at: remote.folder) }
        defer { FolderSyncService.disconnect(defaults: defaults) }
        let local = Storage.originalDocumentURL(for: work.id, fileExtension: "pdf")
        defer {
            try? FileManager.default.removeItem(at: local)
            WorkConversionRecord.delete(for: work.id)
        }
        let oldBytes = Data("%PDF-1.7 previous source".utf8)
        let shared = remote.originals.appendingPathComponent(local.lastPathComponent)
        let sharedRecord = WorkConversionRecord.url(for: work.id, in: remote.originals)
        let oldRecord = WorkConversionRecord(
            format: "pdf", originalFileName: "source.pdf", convertedAt: Date(timeIntervalSince1970: 1_000)
        )
        let oldRecordBytes = try JSONEncoder().encode(oldRecord)
        try oldBytes.write(to: local)
        try oldBytes.write(to: shared)
        try oldRecordBytes.write(to: WorkConversionRecord.url(for: work.id))
        try oldRecordBytes.write(to: sharedRecord)
        let localContainer = try container()
        let context = localContainer.mainContext
        _ = try await FolderSyncService.syncDown(in: context, defaults: defaults)

        // The folder's assets can advance before the manifest arrives. The
        // unchanged manifest keeps the local pair older when the upload starts.
        let newBytes = Data("%PDF-1.7 newer source".utf8)
        var newRecord = oldRecord
        newRecord.convertedAt = Date(timeIntervalSince1970: 2_000)
        let newRecordBytes = try JSONEncoder().encode(newRecord)
        try newBytes.write(to: shared)
        try newRecordBytes.write(to: sharedRecord)
        let modified = Date(timeIntervalSince1970: 10_000)
        for url in [shared, sharedRecord] {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }

        let result = try await FolderSyncService.syncUp(in: context, defaults: defaults)
        #expect(result.skippedUnchanged)
        #expect(result.didWriteRemoteFile)
        #expect(result.omittedOriginalTitles.isEmpty)
        #expect(try Data(contentsOf: local) == oldBytes)
        #expect(WorkConversionRecord.read(for: work.id) == oldRecord)
        #expect(try Data(contentsOf: shared) == newBytes)
        #expect(try Data(contentsOf: sharedRecord) == newRecordBytes)
        for url in [shared, sharedRecord] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            #expect(attributes[.modificationDate] as? Date == modified)
        }
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
