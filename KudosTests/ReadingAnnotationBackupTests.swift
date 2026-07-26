import Foundation
import SwiftData
import Testing
@testable import Kudos

// Nested under PersistenceGateSuites (see its doc comment): restore drives
// PersistenceOperationGate, a process-wide static gate, so these must serialize
// against the other persistence suites too.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct ReadingAnnotationBackupTests {
    private func schema() -> Schema {
        Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SyncTombstone.self, ReadingAnnotation.self
        ])
    }

    private func context(_ schema: Schema) throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
    }

    /// A Readium locator is stored verbatim as its `persistenceString`, the same
    /// encoding reading progress uses, so it must survive the archive byte-for-byte
    /// — a mangled anchor silently points the annotation at the wrong passage.
    private static let locator = """
    {"href":"/OEBPS/ch3.xhtml","type":"application/xhtml+xml",\
    "locations":{"progression":0.42,"totalProgression":0.17,"position":88},\
    "text":{"highlight":"the lantern guttered"}}
    """

    private func makeWork() -> SavedWork {
        let work = SavedWork(title: "Annotated Work", author: "Marginalia")
        work.isSaved = true
        return work
    }

    @Test func annotationsRoundTripThroughTheArchive() throws {
        let schema = schema()
        let source = try context(schema)
        let work = makeWork()
        source.insert(work)

        let highlight = ReadingAnnotation(
            work: work, kind: .highlight, locatorString: Self.locator,
            selectedText: "the lantern guttered", note: "echoes the opening line",
            color: .green, progression: 0.17, spineIndex: 4,
            chapterTitle: "Chapter 3", createdAt: Date(timeIntervalSince1970: 1000)
        )
        let bookmark = ReadingAnnotation(
            work: work, kind: .bookmark, locatorString: Self.locator,
            progression: 0.17, spineIndex: 4, chapterTitle: "Chapter 3",
            createdAt: Date(timeIntervalSince1970: 2000)
        )
        source.insert(highlight)
        source.insert(bookmark)
        try source.save()

        let contents = try KudosBackupService.makeContents(
            works: [work], bookmarks: [], fonts: [], readingQueues: [],
            annotations: [highlight, bookmark], defaults: try testDefaults()
        )
        #expect(contents.manifest.version == 8)
        #expect(contents.manifest.annotations.count == 2)

        let target = try context(schema)
        _ = try KudosBackupService.restore(contents, into: target, defaults: try testDefaults())

        let restored = try target.fetch(FetchDescriptor<ReadingAnnotation>())
            .sorted { $0.createdAt < $1.createdAt }
        #expect(restored.count == 2)

        let restoredHighlight = try #require(restored.first)
        // The locator is the anchor — any drift here mis-points the annotation.
        #expect(restoredHighlight.locatorString == Self.locator)
        #expect(restoredHighlight.kind == .highlight)
        #expect(restoredHighlight.color == .green)
        #expect(restoredHighlight.selectedText == "the lantern guttered")
        #expect(restoredHighlight.note == "echoes the opening line")
        #expect(restoredHighlight.spineIndex == 4)
        #expect(restoredHighlight.chapterTitle == "Chapter 3")
        #expect(restoredHighlight.hasNote)
        // Re-homed onto the restored work, not orphaned.
        #expect(restoredHighlight.work?.id == work.id)

        let restoredBookmark = try #require(restored.last)
        #expect(restoredBookmark.kind == .bookmark)
        #expect(restoredBookmark.selectedText.isEmpty)
        #expect(!restoredBookmark.hasNote)
    }

    @Test func olderArchivesWithoutAnnotationsStillDecode() throws {
        // v1-v7 predate the field; they must decode to empty, not fail.
        let manifest = KudosBackupManifest(
            version: 7, works: [], bookmarks: [], fonts: [],
            settings: .capture(defaults: try testDefaults())
        )
        let data = try KudosBackupContents(manifest: manifest).manifestData()
        let decoded = try KudosBackupContents.decodeManifest(data)
        #expect(decoded.annotations.isEmpty)
        #expect(KudosBackupManifest.supportedVersions.contains(7))
    }

    @Test func aDeletedAnnotationIsNotResurrectedByAnOlderArchive() throws {
        let schema = schema()
        let source = try context(schema)
        let work = makeWork()
        source.insert(work)
        let annotation = ReadingAnnotation(
            work: work, kind: .bookmark, locatorString: Self.locator,
            createdAt: Date(timeIntervalSince1970: 1000)
        )
        source.insert(annotation)
        try source.save()

        let contents = try KudosBackupService.makeContents(
            works: [work], bookmarks: [], fonts: [], readingQueues: [],
            annotations: [annotation], defaults: try testDefaults()
        )

        // The target deleted it *after* the archive was taken.
        let target = try context(schema)
        target.insert(SyncTombstone(
            recordID: annotation.id,
            recordType: .readingAnnotation,
            createdAt: Date(timeIntervalSince1970: 5000)
        ))
        try target.save()

        let summary = try KudosBackupService.restore(
            contents, into: target, defaults: try testDefaults()
        )
        #expect(try target.fetch(FetchDescriptor<ReadingAnnotation>()).isEmpty)
        #expect(summary.suppressedAnnotations == 1)
    }

    @Test func aNewerArchivedEditWinsOverAnOlderLocalCopy() throws {
        let schema = schema()
        let source = try context(schema)
        let work = makeWork()
        source.insert(work)
        let shared = UUID()
        let archived = ReadingAnnotation(
            id: shared, work: work, kind: .highlight, locatorString: Self.locator,
            selectedText: "new snapshot", note: "edited later", color: .blue,
            createdAt: Date(timeIntervalSince1970: 1000)
        )
        archived.lastModifiedAt = Date(timeIntervalSince1970: 9000)
        source.insert(archived)
        try source.save()

        let contents = try KudosBackupService.makeContents(
            works: [work], bookmarks: [], fonts: [], readingQueues: [],
            annotations: [archived], defaults: try testDefaults()
        )

        let target = try context(schema)
        let localWork = SavedWork(title: "Annotated Work", author: "Marginalia")
        localWork.isSaved = true
        target.insert(localWork)
        let local = ReadingAnnotation(
            id: shared, work: localWork, kind: .highlight, locatorString: Self.locator,
            selectedText: "old snapshot", note: "stale", color: .yellow,
            createdAt: Date(timeIntervalSince1970: 1000)
        )
        local.lastModifiedAt = Date(timeIntervalSince1970: 2000)
        target.insert(local)
        try target.save()

        _ = try KudosBackupService.restore(contents, into: target, defaults: try testDefaults())

        let all = try target.fetch(FetchDescriptor<ReadingAnnotation>())
        // Merged in place by id, not duplicated.
        #expect(all.count == 1)
        let merged = try #require(all.first)
        #expect(merged.note == "edited later")
        #expect(merged.color == .blue)
        #expect(merged.selectedText == "new snapshot")
    }

    private func testDefaults() throws -> UserDefaults {
        let name = "ReadingAnnotationBackupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
}
