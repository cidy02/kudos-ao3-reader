import Foundation
import SwiftData
import Testing
@testable import Kudos

/// A backup that could not carry everything it promised must say so.
///
/// Both halves used to be silent. `writeArchive` skips an asset it cannot open
/// — right, because one evicted file should not fail a whole export — but
/// returned nothing, while the manifest went on claiming that work has an
/// EPUB. Restore then met a work whose promised bytes never arrived, set
/// `hasEPUB = false` and moved on, counting the record in the "N Library
/// records" total exactly like a healthy one. The reader was told the backup
/// succeeded and found the hole when they opened the work on the new phone.
///
/// This matters more since the restore began checking entry CRCs: bytes that
/// fail their checksum are refused, which surfaces as the same absence.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct IncompleteBackupReportingTests {
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
        let name = "IncompleteBackupReportingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// A work that claims a file it does not have on disk — an evicted iCloud
    /// asset, a lost file `hasEPUB` outlived, or bytes a CRC check refused.
    private func workPromisingAnEPUB(in context: ModelContext) throws -> SavedWork {
        let work = SavedWork(id: UUID(), title: "Promised Book", author: "Author")
        work.hasEPUB = true
        context.insert(work)
        try context.save()
        return work
    }

    @Test func aWorkWhosePromisedEPUBNeverArrivesIsCounted() throws {
        let schema = schema()
        let source = try context(schema)
        let work = try workPromisingAnEPUB(in: source)

        let contents = try KudosBackupService.makeContents(
            works: [work], bookmarks: [], fonts: [], readingQueues: [],
            defaults: try testDefaults()
        )
        // The promise is in the manifest; the bytes are not in the archive.
        #expect(contents.manifest.works.first?.hasEPUB == true)
        #expect(contents.epubData(for: work.id) == nil)

        let target = try context(schema)
        let summary = try KudosBackupService.restore(
            contents, into: target, defaults: try testDefaults(), mode: .merge
        )

        #expect(summary.worksMissingPromisedEPUB == 1)
        #expect(summary.conflictMessage.contains("EPUB"))
    }

    /// The other side of the same coin: a work that never had an EPUB is not a
    /// gap, and counting it would cry wolf over every ordinary metadata-only
    /// record — which is most of a library synced from AO3 without downloads.
    @Test func aWorkThatNeverHadAnEPUBIsNotCounted() throws {
        let schema = schema()
        let source = try context(schema)
        let work = SavedWork(id: UUID(), title: "Metadata Only", author: "Author")
        work.hasEPUB = false
        source.insert(work)
        try source.save()

        let contents = try KudosBackupService.makeContents(
            works: [work], bookmarks: [], fonts: [], readingQueues: [],
            defaults: try testDefaults()
        )
        let target = try context(schema)
        let summary = try KudosBackupService.restore(
            contents, into: target, defaults: try testDefaults(), mode: .merge
        )

        #expect(summary.worksMissingPromisedEPUB == 0)
    }

    /// The export half. Before this, `writeArchive` returned `Void` — there was
    /// no value to assert on, which is the whole defect.
    @Test func theStreamingExporterNamesWhatItCouldNotInclude() throws {
        let schema = schema()
        let source = try context(schema)
        let work = try workPromisingAnEPUB(in: source)

        let plan = try KudosBackupService.makeExportPlan(
            works: [work], bookmarks: [], fonts: [], readingQueues: [],
            defaults: try testDefaults()
        )
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).kudosbackup")
        defer { try? FileManager.default.removeItem(at: destination) }

        let skipped = try KudosBackupService.writeArchive(plan, to: destination)

        #expect(skipped == ["Works/\(work.id.uuidString).epub"])
        // The export still succeeds — skipping is the right call, reporting is
        // the part that was missing.
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }
}
}
