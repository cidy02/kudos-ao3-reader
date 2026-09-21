import Foundation
import SwiftData
import Testing
@testable import Kudos

/// Merging a backup is what a reader does when a download has gone missing.
///
/// It could not help them. On merge, a work that already existed and was active
/// hit "Active overlap: leave local state entirely" and `continue`d — which
/// skipped asset restoration along with the metadata it meant to protect. The
/// work was still counted as restored, so the confirmation said the merge had
/// done something it had not.
///
/// Filling an absent file is pure gain: there is nothing local to protect, and
/// `ReadingQueueService.replaceEPUB` moves rather than replaces when the
/// destination does not exist, so nothing can be displaced. The metadata
/// contract is unchanged, which the second test here exists to prove.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct MergeMissingEPUBRecoveryTests {
    private func schema() -> Schema {
        Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self, ReadingAnnotation.self,
            ReadingSession.self, ReadingFavorite.self, FandomReadWatermark.self
        ])
    }

    private func context(_ schema: Schema) throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
    }

    private func testDefaults() throws -> UserDefaults {
        let name = "MergeMissingEPUBRecoveryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// Real bytes, because `replaceEPUB` validates through
    /// `EPUBDocument.inspectPackage` before installing anything.
    private func validEPUB(title: String) throws -> Data {
        try EPUBBuilder.archive(
            metadata: .init(title: title),
            chapters: [.init(title: "Chapter 1", bodyXHTML: "<p>Text.</p>")],
            modified: Date(timeIntervalSince1970: 0)
        )
    }

    /// A backup that holds the work's EPUB, for a work of the given id.
    private func backup(containing epub: Data, for id: UUID) throws -> KudosBackupContents {
        let staging = try context(schema())
        let archived = SavedWork(id: id, title: "Archived Title", author: "Archived Author")
        archived.hasEPUB = true
        staging.insert(archived)
        try staging.save()
        let manifest = try KudosBackupService.makeContents(
            works: [archived], bookmarks: [], fonts: [], readingQueues: [],
            defaults: try testDefaults()
        ).manifest
        return KudosBackupContents(manifest: manifest, epubFiles: [id: epub])
    }

    @Test func mergeRefillsAnEPUBThatWentMissingLocally() throws {
        let schema = schema()
        let id = UUID()
        let epub = try validEPUB(title: "Recovered")
        let contents = try backup(containing: epub, for: id)

        let target = try context(schema)
        let local = SavedWork(id: id, title: "Local Title", author: "Local Author")
        local.hasEPUB = false
        target.insert(local)
        try target.save()
        defer { try? FileManager.default.removeItem(at: local.fileURL) }

        #expect(!FileManager.default.fileExists(atPath: local.fileURL.path))

        let summary = try KudosBackupService.restore(
            contents, into: target, defaults: try testDefaults(), mode: .merge
        )

        #expect(summary.recoveredMissingEPUBs == 1)
        #expect(FileManager.default.fileExists(atPath: local.fileURL.path))
        #expect(local.hasEPUB)
        // The active-overlap contract is untouched: only the bytes were filled.
        #expect(local.title == "Local Title")
        #expect(local.author == "Local Author")
        #expect(summary.changeMessage.contains("recovered EPUB file"))
    }

    /// The guard. Merge must still refuse to touch a file that is present —
    /// filling a gap must not have become a general replacement path.
    @Test func mergeLeavesAnExistingLocalEPUBAlone() throws {
        let schema = schema()
        let id = UUID()
        let incoming = try validEPUB(title: "From Backup")
        let contents = try backup(containing: incoming, for: id)

        let target = try context(schema)
        let local = SavedWork(id: id, title: "Local Title", author: "Local Author")
        local.hasEPUB = true
        target.insert(local)
        try target.save()
        defer { try? FileManager.default.removeItem(at: local.fileURL) }

        let localBytes = try validEPUB(title: "Local Copy")
        try FileManager.default.createDirectory(
            at: local.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try localBytes.write(to: local.fileURL, options: .atomic)
        #expect(localBytes != incoming)

        let summary = try KudosBackupService.restore(
            contents, into: target, defaults: try testDefaults(), mode: .merge
        )

        #expect(summary.recoveredMissingEPUBs == 0)
        #expect(try Data(contentsOf: local.fileURL) == localBytes)
    }
}
}
