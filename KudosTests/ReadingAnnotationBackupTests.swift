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
        // Merged in place by id, not duplicated: still exactly one LIVE mark. This used to
        // assert `all.count == 1`. Under M1f the older local note ("stale") is not destroyed
        // by the merge — it is parked on a hidden sibling — because restore cannot tell this
        // honest edit from a forged same-id record, which is the whole point of the rule.
        let live = all.filter { !$0.isPendingDeletion && $0.deletedAt == nil }
        #expect(live.count == 1)
        let merged = try #require(live.first)
        #expect(merged.note == "edited later")
        #expect(merged.color == .blue)
        #expect(merged.selectedText == "new snapshot")

        // The superseded text is still in the store, hidden.
        #expect(all.contains { $0.isPendingDeletion && $0.note == "stale" })
    }

    @Test func sameChapterHighlightFromTwoDevicesCollapsesToOneOnRestore() throws {
        // Two devices, offline, each highlight the exact same passage — same
        // work, same kind, byte-identical locator string — but with different
        // UUIDs since neither knew about the other's mark. A sync/restore must
        // recognize this as one highlight, not stack duplicates forever.
        let schema = schema()
        let sharedWorkID = UUID()

        let source = try context(schema)
        let sourceWork = SavedWork(id: sharedWorkID, title: "Annotated Work", author: "Marginalia")
        sourceWork.isSaved = true
        source.insert(sourceWork)
        let deviceBHighlight = ReadingAnnotation(
            work: sourceWork, kind: .highlight, locatorString: Self.locator,
            selectedText: "the lantern guttered", color: .green,
            createdAt: Date(timeIntervalSince1970: 500)
        )
        deviceBHighlight.lastModifiedAt = Date(timeIntervalSince1970: 9000)
        source.insert(deviceBHighlight)
        try source.save()

        let contents = try KudosBackupService.makeContents(
            works: [sourceWork], bookmarks: [], fonts: [], readingQueues: [],
            annotations: [deviceBHighlight], defaults: try testDefaults()
        )

        let target = try context(schema)
        let targetWork = SavedWork(id: sharedWorkID, title: "Annotated Work", author: "Marginalia")
        targetWork.isSaved = true
        target.insert(targetWork)
        let deviceAHighlight = ReadingAnnotation(
            work: targetWork, kind: .highlight, locatorString: Self.locator,
            note: "device A's note", color: .yellow,
            createdAt: Date(timeIntervalSince1970: 1000)
        )
        deviceAHighlight.lastModifiedAt = Date(timeIntervalSince1970: 1500)
        target.insert(deviceAHighlight)
        try target.save()

        _ = try KudosBackupService.restore(contents, into: target, defaults: try testDefaults())

        let all = try target.fetch(FetchDescriptor<ReadingAnnotation>())
        // The passage collapses to ONE LIVE mark. This used to assert `all.count == 1` —
        // i.e. that the loser row was destroyed. M1c changed that deliberately: device A's
        // highlight existed on this device before the archive was applied, and the audit's
        // A4 case showed a forged, future-dated record can be made to win this ranking, so a
        // pre-existing loser is now soft-deleted rather than `context.delete`d. The row
        // surviving is the fix, not a leak — so the count assertion moves to live rows and
        // the hidden row is asserted explicitly below.
        let live = all.filter { !$0.isPendingDeletion && $0.deletedAt == nil }
        #expect(live.count == 1)
        let survivor = try #require(live.first)
        // Device B's copy is more recently modified, so it wins the passage...
        #expect(survivor.id == deviceBHighlight.id)
        #expect(survivor.color == .green)
        // ...but device A's note is salvaged since the winner had none.
        #expect(survivor.note == "device A's note")

        // Device A's own row is still in the store, hidden — never destroyed by a merge.
        let hidden = try #require(all.first { $0.id == deviceAHighlight.id })
        #expect(hidden.isPendingDeletion)
        #expect(hidden.note == "device A's note")

        // The loser is tombstoned, not silently dropped — an older archive
        // that still lists it must not resurrect a duplicate later.
        let tombstones = try target.fetch(FetchDescriptor<SyncTombstone>())
        #expect(tombstones.contains { $0.recordID == deviceAHighlight.id })
    }

    @Test func differentKindOrLocatorNeverCollapses() throws {
        // A highlight and a bookmark at the same passage are different marks
        // (ANN-8 is same-*kind* only); a highlight one chapter over is a
        // different passage. Neither should ever be treated as a duplicate.
        let schema = schema()
        let target = try context(schema)
        let work = makeWork()
        target.insert(work)
        let highlight = ReadingAnnotation(
            work: work, kind: .highlight, locatorString: Self.locator, createdAt: Date()
        )
        let bookmarkSamePassage = ReadingAnnotation(
            work: work, kind: .bookmark, locatorString: Self.locator, createdAt: Date()
        )
        let otherLocator = Self.locator.replacingOccurrences(of: "0.42", with: "0.55")
        let highlightElsewhere = ReadingAnnotation(
            work: work, kind: .highlight, locatorString: otherLocator, createdAt: Date()
        )
        target.insert(highlight)
        target.insert(bookmarkSamePassage)
        target.insert(highlightElsewhere)
        try target.save()

        // Re-archiving and restoring the work's own state (a self-referential
        // round trip) still runs the dedup pass over all live local
        // annotations — none of these three should be mistaken for a match.
        let contents = try KudosBackupService.makeContents(
            works: [work], bookmarks: [], fonts: [], readingQueues: [],
            annotations: [highlight], defaults: try testDefaults()
        )
        _ = try KudosBackupService.restore(contents, into: target, defaults: try testDefaults())

        #expect(try target.fetch(FetchDescriptor<ReadingAnnotation>()).count == 3)
    }

    /// ANN-9: `ReadingAnnotation.work` is a plain optional with no
    /// `@Relationship` cascade, so SwiftData's default `.nullify` would leave
    /// every mark behind when its book is hard-deleted — orphaned rows that no
    /// list can show (they all filter on `work?.id`) and that no tombstone
    /// protects, so a later restore of an older archive could resurrect them.
    ///
    /// Lives here rather than in `PersistenceSyncTests` deliberately: that
    /// suite's schema omits `ReadingAnnotation`, so `hardDelete`'s fetch throws
    /// there and is swallowed by `try?` — a cascade test written against that
    /// container would pass no matter what the cascade did.
    @Test func hardDeletingAWorkTombstonesAndRemovesItsAnnotations() throws {
        let schema = schema()
        let context = try context(schema)
        let work = makeWork()
        context.insert(work)
        let highlight = ReadingAnnotation(
            work: work, kind: .highlight, locatorString: Self.locator,
            selectedText: "the lantern guttered", note: "keep me honest"
        )
        let bookmark = ReadingAnnotation(
            work: work, kind: .bookmark, locatorString: Self.locator
        )
        context.insert(highlight)
        context.insert(bookmark)
        try context.save()

        WorkLifecycle.hardDelete(work, in: context)

        #expect(try context.fetch(FetchDescriptor<ReadingAnnotation>()).isEmpty)
        let annotationTombstones = try context.fetch(FetchDescriptor<SyncTombstone>())
            .filter { $0.recordType == .readingAnnotation }
        #expect(annotationTombstones.count == 2)
        #expect(Set(annotationTombstones.map(\.recordID)) == Set([highlight.id, bookmark.id]))
    }

    private func testDefaults() throws -> UserDefaults {
        let name = "ReadingAnnotationBackupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
}
