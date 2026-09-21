import Foundation
import SwiftData
import Testing
@testable import Kudos

/// `epubDigest` describes the bytes on this disk. Four ways it came to describe
/// something else, each of which made sync skip a book it should have fetched.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct EPUBDigestHonestyTests {
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
        let name = "EPUBDigestHonestyTests.\(label).\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private static let sourceURL = "https://archiveofourown.org/works/12345"

    private func book(_ body: String, source: String = "") throws -> Data {
        try EPUBBuilder.archive(
            metadata: .init(title: "Same Length", sourceURL: source, identifier: "pinned"),
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

    /// The manifest is metadata; the EPUB is bytes, and they travel separately.
    /// Adopting the manifest's digest when the bytes did not arrive made the
    /// local file claim to be the remote one — after which the two digests
    /// agreed, sync skipped the download, and nothing ever disagreed again. The
    /// correction was lost permanently, by a comparison that was sure it had it.
    ///
    /// The second half is what makes the first half matter: once the bytes do
    /// arrive, they must still be fetched. A digest adopted early would have
    /// matched the remote one by then, and the fetch would have been skipped as
    /// unnecessary — so this asserts the correction actually lands.
    @Test func aPromisedBookIsNotAssumedToHaveArrived() async throws {
        let mine = try book("<p>AAAAAAAA</p>")
        let corrected = try book("<p>BBBBBBBB</p>")
        #expect(mine.count == corrected.count)
        #expect(mine != corrected)

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("DigestHonesty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        // The other device published the corrected book and its digest...
        let remoteContainer = try container()
        let remoteWork = SavedWork(id: UUID(), title: "Same Length", author: "Writer")
        remoteWork.hasEPUB = true
        remoteWork.epubDigest = try digest(of: corrected)
        remoteWork.markModified(Date(timeIntervalSince1970: 9_000))
        remoteContainer.mainContext.insert(remoteWork)
        try remoteContainer.mainContext.save()
        let remoteContents = try KudosBackupService.makeContents(
            works: [remoteWork], bookmarks: [], fonts: [], readingQueues: [],
            defaults: try testDefaults("remote")
        )

        let syncDirectory = folder.appendingPathComponent(FolderSyncService.syncDirectoryName)
        let worksDirectory = syncDirectory
            .appendingPathComponent(FolderSyncService.worksSubdirectoryName)
        try FileManager.default.createDirectory(
            at: worksDirectory, withIntermediateDirectories: true
        )
        // ...but the bytes are still an undownloaded iCloud placeholder. This
        // is what a half-arrived sync actually looks like: the record is
        // readable, the book is not.
        try remoteContents.manifestData().write(
            to: syncDirectory.appendingPathComponent(FolderSyncService.manifestFileName),
            options: .atomic
        )
        let placeholderURL = worksDirectory
            .appendingPathComponent(".\(remoteWork.id.uuidString).epub.icloud")
        try Data().write(to: placeholderURL)

        let localContainer = try container()
        let localContext = localContainer.mainContext
        let localWork = SavedWork(id: remoteWork.id, title: "Same Length", author: "Writer")
        localWork.hasEPUB = true
        let mineDigest = try digest(of: mine)
        localWork.epubDigest = mineDigest
        localWork.markModified(Date(timeIntervalSince1970: 1_000))
        localContext.insert(localWork)
        try localContext.save()
        try FileManager.default.createDirectory(
            at: localWork.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try mine.write(to: localWork.fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: localWork.fileURL) }

        let defaults = try testDefaults("local")
        defer { FolderSyncService.disconnect(defaults: defaults) }
        try FolderSyncService.connect(to: folder, defaults: defaults)
        _ = try await FolderSyncService.syncDown(in: localContext, defaults: defaults)

        // The bytes did not arrive, so the identity of the bytes did not either.
        #expect(localWork.epubDigest == mineDigest)
        #expect(try Data(contentsOf: localWork.fileURL) == mine)

        // The download finishes, with no manifest change at all. The unread
        // placeholder counted as outstanding, so the skip stamp was withheld
        // and this sync comes back to look.
        try corrected.write(
            to: worksDirectory.appendingPathComponent("\(remoteWork.id.uuidString).epub"),
            options: .atomic
        )
        try FileManager.default.removeItem(at: placeholderURL)
        _ = try await FolderSyncService.syncDown(in: localContext, defaults: defaults)

        #expect(try Data(contentsOf: localWork.fileURL) == corrected)
        #expect(localWork.epubDigest == (try digest(of: corrected)))
    }

    /// `epubDigest` shipped after migration did, so every library that has
    /// anything to hash is already `.completed` — the one state the backfill
    /// used to refuse to run in. Left there, the field would have stayed empty
    /// on every existing install forever, and the size-only comparison it
    /// exists to replace would have gone on being the only thing sync had.
    @Test func aLibraryThatAlreadyMigratedStillGetsDigests() async throws {
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

        // The state an upgrading installation is already in.
        let defaults = try testDefaults("migrated")
        PersistenceStatusStore.setState(.completed, defaults: defaults)

        _ = await PersistenceMigrationService.runIfNeeded(in: context, defaults: defaults)

        #expect(work.epubDigest == Storage.fileDigest(at: work.fileURL))
    }

    /// Importing is a byte write like any other, and owes the same honesty.
    /// A book freed to save space keeps its digest; importing a corrected copy
    /// of the same length over it left that stale digest in place, and the
    /// peer still holding the old copy read "same digest, same size" and
    /// skipped the file it was being sent.
    @Test func reImportingOverAFreedBookRefreshesItsDigest() async throws {
        let container = try container()
        let context = container.mainContext
        let mine = try book("<p>AAAAAAAA</p>", source: Self.sourceURL)
        let corrected = try book("<p>BBBBBBBB</p>", source: Self.sourceURL)
        #expect(mine.count == corrected.count)

        // Freed, so there is no file left to recognise it by — an AO3 identity
        // is the only thing that can still match it, and is what makes this the
        // "same book, corrected copy" case rather than a second import.
        let work = SavedWork(
            title: "Same Length", author: "Writer", sourceURL: Self.sourceURL
        )
        work.hasEPUB = false
        work.epubDigest = try digest(of: mine)
        context.insert(work)
        try context.save()
        defer { try? FileManager.default.removeItem(at: work.fileURL) }

        let incoming = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).epub")
        try corrected.write(to: incoming, options: .atomic)
        defer { try? FileManager.default.removeItem(at: incoming) }

        let outcome = try await importUserEPUB(incoming, into: context)
        // The premise: it found the freed record rather than making a new one.
        guard case .restored = outcome else {
            Issue.record("Expected the freed work to be restored, got \(outcome)")
            return
        }

        #expect(work.hasEPUB)
        #expect(work.epubDigest == (try digest(of: corrected)))
    }

    /// Freeing an EPUB is the reader saying they do not want the bytes. A
    /// promise of a remote copy, made by a manifest that arrived before the
    /// file did, has to end there — otherwise the next export advertises an
    /// EPUB the reader deleted on purpose, and peers skip sending the real one.
    @Test func freeingAnEPUBCancelsAPromisedRemoteCopy() throws {
        let container = try container()
        let context = container.mainContext
        let work = SavedWork(id: UUID(), title: "Promised", author: "Writer")
        work.hasEPUB = false
        work.remoteEPUBPending = true
        context.insert(work)
        try context.save()

        WorkLifecycle.freeEPUB(work)

        #expect(!work.remoteEPUBPending)
        let contents = try KudosBackupService.makeContents(
            works: [work], bookmarks: [], fonts: [], readingQueues: [],
            defaults: try testDefaults("freed")
        )
        #expect(contents.manifest.works.first?.hasEPUB == false)
    }
}
}
