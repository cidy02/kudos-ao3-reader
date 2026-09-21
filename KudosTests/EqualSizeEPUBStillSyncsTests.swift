import Foundation
import SwiftData
import Testing
@testable import Kudos

/// Equal size is not equal content.
///
/// Sync-down decided an EPUB was unchanged on file size alone, while the font
/// branch of the same function says "equal size is not equal content" and
/// compares bytes. And this is not a contrived collision: the archive writer
/// STORES entries rather than deflating them, so two books whose text differs
/// only in the characters used really do come out the same length. A corrected
/// chapter of the same length was never fetched, and sync reported success
/// while keeping the old words.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct EqualSizeEPUBStillSyncsTests {
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

    private func testDefaults() throws -> UserDefaults {
        let name = "EqualSizeEPUBStillSyncsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func book(_ body: String) throws -> Data {
        try EPUBBuilder.archive(
            metadata: .init(title: "Same Length", identifier: "pinned"),
            chapters: [.init(title: "One", bodyXHTML: body)],
            modified: Date(timeIntervalSince1970: 0)
        )
    }

    private func digest(of data: Data) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).epub")
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }
        return try #require(Storage.fileDigest(at: url))
    }

    @Test func aCorrectedBookOfTheSameLengthIsStillFetched() async throws {
        let mine = try book("<p>AAAAAAAA</p>")
        let corrected = try book("<p>BBBBBBBB</p>")
        // The premise. If these ever differ in length the test proves nothing,
        // because a size comparison alone would already fetch.
        #expect(mine.count == corrected.count)
        #expect(mine != corrected)

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("EqualSizeSync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        // The other device's state: same work, corrected book, newer record.
        let remoteContainer = try container()
        let remoteWork = SavedWork(id: UUID(), title: "Same Length", author: "Writer")
        remoteWork.hasEPUB = true
        remoteWork.epubDigest = try digest(of: corrected)
        remoteWork.markModified(Date(timeIntervalSince1970: 9_000))
        remoteContainer.mainContext.insert(remoteWork)
        try remoteContainer.mainContext.save()
        let remoteContents = try KudosBackupService.makeContents(
            works: [remoteWork], bookmarks: [], fonts: [], readingQueues: [],
            defaults: try testDefaults()
        )

        let syncDirectory = folder.appendingPathComponent(FolderSyncService.syncDirectoryName)
        let worksDirectory = syncDirectory
            .appendingPathComponent(FolderSyncService.worksSubdirectoryName)
        try FileManager.default.createDirectory(
            at: worksDirectory, withIntermediateDirectories: true
        )
        try corrected.write(
            to: worksDirectory.appendingPathComponent("\(remoteWork.id.uuidString).epub"),
            options: .atomic
        )
        try remoteContents.manifestData().write(
            to: syncDirectory.appendingPathComponent(FolderSyncService.manifestFileName),
            options: .atomic
        )

        // This device: same work, the older book, an older record.
        let localContainer = try container()
        let localContext = localContainer.mainContext
        let localWork = SavedWork(id: remoteWork.id, title: "Same Length", author: "Writer")
        localWork.hasEPUB = true
        localWork.epubDigest = try digest(of: mine)
        localWork.markModified(Date(timeIntervalSince1970: 1_000))
        localContext.insert(localWork)
        try localContext.save()
        try FileManager.default.createDirectory(
            at: localWork.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try mine.write(to: localWork.fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: localWork.fileURL) }

        let defaults = try testDefaults()
        defer { FolderSyncService.disconnect(defaults: defaults) }
        try FolderSyncService.connect(to: folder, defaults: defaults)
        _ = try await FolderSyncService.syncDown(in: localContext, defaults: defaults)

        #expect(try Data(contentsOf: localWork.fileURL) == corrected)
    }

    /// The other half of `epubDigest`: a library that predates the field gets
    /// one computed in the background, so those books stop relying on the
    /// weaker size comparison.
    @Test func anExistingBookGetsADigestOnReconcile() async throws {
        let container = try container()
        let context = container.mainContext
        let work = SavedWork(id: UUID(), title: "Older Book", author: "Writer")
        work.hasEPUB = true
        context.insert(work)
        try context.save()
        try FileManager.default.createDirectory(
            at: work.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try book("<p>Existing.</p>").write(to: work.fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: work.fileURL) }
        #expect(work.epubDigest.isEmpty)

        _ = await PersistenceMigrationService.runIfNeeded(
            in: context, defaults: try testDefaults()
        )

        #expect(!work.epubDigest.isEmpty)
        #expect(work.epubDigest == Storage.fileDigest(at: work.fileURL))
    }
}
}
