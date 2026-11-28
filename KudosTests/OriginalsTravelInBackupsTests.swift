import Foundation
import SwiftData
import Testing
@testable import Kudos

/// The document a converted work was made from now travels with the backup.
///
/// `UserDocumentImport.preserveOriginal` keeps the exact file the reader handed
/// over and calls that copy "insurance". Both exporters enumerated works and
/// fonts only, so the insurance was the one thing that did not survive the
/// event it exists for: migrating to a new phone and erasing the old one.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct OriginalsTravelInBackupsTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, QueueSavedSearchLink.self, SyncTombstone.self, ReadingAnnotation.self
        ])
        return ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
    }

    private func testDefaults() throws -> UserDefaults {
        let name = "OriginalsTravelInBackupsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private static let originalBytes = Data("%PDF-1.7 the document they imported".utf8)

    /// A work whose original PDF and conversion record are on disk, exactly as
    /// a real document import leaves them.
    private func workWithOriginal(in context: ModelContext) throws -> SavedWork {
        let work = SavedWork(id: UUID(), title: "Converted", author: "Writer")
        context.insert(work)
        try context.save()
        let original = Storage.originalDocumentURL(for: work.id, fileExtension: "pdf")
        try FileManager.default.createDirectory(
            at: original.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Self.originalBytes.write(to: original, options: .atomic)
        WorkConversionRecord(format: "pdf", originalFileName: "thesis.pdf").write(for: work.id)
        return work
    }

    private func cleanUp(_ workIDs: [UUID]) {
        for id in workIDs {
            if let url = Storage.existingOriginalDocumentURL(for: id) {
                try? FileManager.default.removeItem(at: url)
            }
            try? FileManager.default.removeItem(at: WorkConversionRecord.url(for: id))
        }
    }

    @Test func exportPlanMatchesPerWorkOriginalLookup() throws {
        let first = SavedWork(title: "PDF", author: "Writer")
        let second = SavedWork(title: "Legacy name", author: "Writer")
        let sidecarOnly = SavedWork(title: "Sidecar only", author: "Writer")
        let missing = SavedWork(title: "Missing", author: "Writer")
        first.hasEPUB = false
        second.hasEPUB = true
        sidecarOnly.hasEPUB = false
        missing.hasEPUB = false

        let firstOriginal = Storage.originalDocumentURL(for: first.id, fileExtension: "pdf")
        let alternate = Storage.originalDocumentURL(for: first.id, fileExtension: "html")
        let legacyName = Storage.originalsDirectory.appendingPathComponent("\(second.id.uuidString)-legacy.txt")
        let firstRecord = WorkConversionRecord.url(for: first.id)
        let orphanRecord = WorkConversionRecord.url(for: sidecarOnly.id)
        let paths = [firstOriginal, alternate, legacyName, firstRecord, orphanRecord]
        defer {
            for url in paths { try? FileManager.default.removeItem(at: url) }
        }
        for url in [firstOriginal, alternate, legacyName] {
            try Self.originalBytes.write(to: url)
        }
        let record = WorkConversionRecord(format: "pdf", originalFileName: "thesis.pdf")
        let recordBytes = try JSONEncoder().encode(record)
        try recordBytes.write(to: firstRecord)
        try recordBytes.write(to: orphanRecord)

        let orderedWorks = [first, second, sidecarOnly, missing].sorted { $0.id.uuidString < $1.id.uuidString }
        var expectedOriginals: [URL] = []
        for work in orderedWorks {
            guard let original = Storage.existingOriginalDocumentURL(for: work.id) else { continue }
            expectedOriginals.append(original)
            let sidecar = WorkConversionRecord.url(for: work.id)
            if FileManager.default.fileExists(atPath: sidecar.path) { expectedOriginals.append(sidecar) }
        }
        #expect(expectedOriginals.count == 3)

        let plan = try KudosBackupService.makeExportPlan(
            works: Array(orderedWorks.reversed()) + [first],
            bookmarks: [], fonts: [], readingQueues: [], defaults: try testDefaults()
        )
        let expectedNames = ["Works/\(second.id.uuidString).epub"]
            + expectedOriginals.map { "Originals/\($0.lastPathComponent)" }
        #expect(plan.assets.map(\.entryName) == expectedNames)
        #expect(plan.assets.map(\.fileURL) == [second.fileURL] + expectedOriginals)
    }

    @Test func anOriginalSurvivesAZipRoundTrip() throws {
        let source = try makeContext()
        let work = try workWithOriginal(in: source)
        let target = try makeContext()
        defer { cleanUp([work.id]) }

        let contents = try KudosBackupService.makeContents(
            works: [work], bookmarks: [], fonts: [], readingQueues: [],
            defaults: try testDefaults()
        )
        // Both the document and the record naming its converter.
        #expect(contents.originalFileNames.count == 2)

        // Through a real archive, not just the in-memory object.
        let reread = try KudosBackupContents(zipData: try contents.zipData())
        #expect(reread.originalFileNames.count == 2)

        // Erase this device's copies, then restore.
        cleanUp([work.id])
        #expect(Storage.existingOriginalDocumentURL(for: work.id) == nil)

        let summary = try KudosBackupService.restore(
            reread, into: target, defaults: try testDefaults(), mode: .merge
        )

        #expect(summary.restoredOriginals == 1)
        let restored = try #require(Storage.existingOriginalDocumentURL(for: work.id))
        #expect(try Data(contentsOf: restored) == Self.originalBytes)
        #expect(WorkConversionRecord.read(for: work.id)?.originalFileName == "thesis.pdf")
    }

    @Test func exportReportsAnUnreadableOriginalAndKeepsEveryReadableOne() async throws {
        let context = try makeContext()
        let readable = try [workWithOriginal(in: context), workWithOriginal(in: context)]
        let unreadable = SavedWork(title: "Unreadable Original", author: "Writer")
        context.insert(unreadable)
        try context.save()
        let works = readable + [unreadable]
        defer { cleanUp(works.map(\.id)) }
        let blocked = Storage.originalDocumentURL(for: unreadable.id, fileExtension: "pdf")
        // A non-file where the original should be is unreadable on either OS,
        // independent of the test host's permissions.
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        WorkConversionRecord(format: "pdf", originalFileName: "missing.pdf").write(for: unreadable.id)

        let defaults = try testDefaults()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("OriginalExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let plan = try KudosBackupService.makeExportPlan(
            works: works, bookmarks: [], fonts: [], readingQueues: [], defaults: defaults
        )
        let archive = folder.appendingPathComponent("Export.kudosbackup")
        let report = try KudosBackupService.writeArchive(plan, to: archive)
        let fromArchive = try KudosBackupContents.read(from: archive)
        let inMemory = try KudosBackupService.makeContents(
            works: works, bookmarks: [], fonts: [], readingQueues: [], defaults: defaults
        )
        #expect(report.omittedOriginalTitles == [unreadable.title])
        #expect(inMemory.omittedOriginalTitles == [unreadable.title])
        #expect(fromArchive.originalFileNames.count == 4)
        #expect(inMemory.originalFileNames == fromArchive.originalFileNames)
        for work in readable {
            let name = "\(work.id.uuidString).pdf"
            #expect(fromArchive.originalData(named: name) == Self.originalBytes)
            #expect(inMemory.originalData(named: name) == Self.originalBytes)
        }

        try FolderSyncService.connect(to: folder, defaults: defaults)
        defer { FolderSyncService.disconnect(defaults: defaults) }
        let synced = try await FolderSyncService.syncUp(in: context, defaults: defaults)
        let status = FolderSyncService.snapshot(defaults: defaults)
        #expect(synced.omittedOriginalTitles == [unreadable.title])
        #expect(status.lastError.contains("1 original file couldn't be included"))
        #expect(status.lastError.contains(unreadable.title))
        let shared = try KudosBackupContents.read(
            from: folder.appendingPathComponent(FolderSyncService.syncDirectoryName)
        )
        #expect(shared.originalFileNames == inMemory.originalFileNames)
    }

    /// A sync folder is a backup too, so it carries them as well — and a
    /// directory-form read of that folder finds them.
    @Test func aSyncFolderCarriesOriginals() async throws {
        let source = try makeContext()
        let work = try workWithOriginal(in: source)
        defer { cleanUp([work.id]) }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("OriginalsSync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let defaults = try testDefaults()
        defer { FolderSyncService.disconnect(defaults: defaults) }
        try FolderSyncService.connect(to: folder, defaults: defaults)
        _ = try await FolderSyncService.syncUp(in: source, defaults: defaults)

        let syncDirectory = folder.appendingPathComponent(FolderSyncService.syncDirectoryName)
        let originals = syncDirectory
            .appendingPathComponent(FolderSyncService.originalsSubdirectoryName)
        let uploaded = try FileManager.default.contentsOfDirectory(atPath: originals.path)
            .filter { !$0.hasPrefix(".") }
        // The document and the record naming its converter.
        #expect(uploaded.count == 2)

        // The folder read back as a backup exposes them.
        let contents = try KudosBackupContents.read(from: syncDirectory)
        #expect(contents.originalFileNames.count == 2)
        let name = try #require(contents.originalFileNames.first { $0.hasSuffix(".pdf") })
        #expect(contents.originalData(named: name) == Self.originalBytes)
    }

    /// Guard: a local original is the file the reader imported on this device.
    /// The archive's copy is at best the same bytes and at worst older, and
    /// re-conversion reads whichever is on disk — so restore must not clobber.
    @Test func restoreDoesNotOverwriteAnOriginalAlreadyHere() throws {
        let source = try makeContext()
        let work = try workWithOriginal(in: source)
        defer { cleanUp([work.id]) }

        let contents = try KudosBackupService.makeContents(
            works: [work], bookmarks: [], fonts: [], readingQueues: [],
            defaults: try testDefaults()
        )

        // The device's own copy differs from the archived one.
        let mine = Data("%PDF-1.7 the copy already on this device".utf8)
        let original = try #require(Storage.existingOriginalDocumentURL(for: work.id))
        try mine.write(to: original, options: .atomic)

        let target = try makeContext()
        let summary = try KudosBackupService.restore(
            contents, into: target, defaults: try testDefaults(), mode: .merge
        )

        #expect(summary.restoredOriginals == 0)
        #expect(try Data(contentsOf: original) == mine)
    }

    /// The same guard, when the two copies are not named alike.
    ///
    /// The destination took its name from the LOCAL work and its extension from
    /// the ARCHIVED file, so a local `.html` and an archived `.pdf` produced a
    /// path that did not exist — the "already here?" test passed, and both
    /// landed. Nothing downstream can choose between two originals for one
    /// work: `existingOriginalDocumentURL` returns whichever the directory
    /// listing yields first, and that is what re-conversion reads, what
    /// permanent deletion removes, and what the next export carries. They need
    /// not be the same file.
    @Test func restoreDoesNotLeaveASecondOriginalBesideTheFirst() throws {
        let source = try makeContext()
        let work = try workWithOriginal(in: source)
        defer { cleanUp([work.id]) }

        // The archive carries the PDF.
        let contents = try KudosBackupService.makeContents(
            works: [work], bookmarks: [], fonts: [], readingQueues: [],
            defaults: try testDefaults()
        )

        // This device's copy of the same work was converted from HTML instead,
        // so it sits under a different name.
        let pdf = try #require(Storage.existingOriginalDocumentURL(for: work.id))
        try FileManager.default.removeItem(at: pdf)
        let html = Storage.originalDocumentURL(for: work.id, fileExtension: "html")
        let mine = Data("<html>the copy already on this device</html>".utf8)
        try mine.write(to: html, options: .atomic)

        let target = try makeContext()
        let summary = try KudosBackupService.restore(
            contents, into: target, defaults: try testDefaults(), mode: .merge
        )

        #expect(summary.restoredOriginals == 0)
        #expect(originalsOnDisk(for: work.id) == 1)
        #expect(try Data(contentsOf: html) == mine)
    }

    /// Every preserved original for `id`, sidecars excluded — the invariant is
    /// that this is never more than one.
    private func originalsOnDisk(for id: UUID) -> Int {
        let names = (try? FileManager.default.contentsOfDirectory(
            atPath: Storage.originalsDirectory.path
        )) ?? []
        return names.filter {
            $0.hasPrefix(id.uuidString) && !$0.hasSuffix(Storage.conversionRecordSuffix)
        }.count
    }
}
}
