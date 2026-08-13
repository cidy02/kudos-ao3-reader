import Foundation
import SwiftData
import Testing
@testable import Kudos

// Nested under PersistenceGateSuites: restore takes PersistenceOperationGate, a process-wide
// static lock, so this must serialize against the other gate-taking suites.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct AnnotationNotePreservationTests {

    private static let locator = "epubcfi(/6/4[chap01]!/4/2/2[p3]/1:0)"

    /// M1f, the attack case. An A4 adversary reads a real annotation UUID out of the sync
    /// folder's own `manifest.json`, so the incoming record collides by **id** — there is no
    /// dedup loser and the pre-existing guard in `dedupeSamePassageAnnotations` never runs.
    /// Before M1f this path did a straight `local.note = archived.note` and the user's text was
    /// gone, unrecoverably, with no interaction beyond having trusted the folder.
    @Test func forgedSameIDRecordCannotDestroyAPreExistingNote() throws {
        let schema = schema()
        let target = try context(schema)
        let workID = UUID()
        let work = SavedWork(id: workID, title: "Annotated Work", author: "Marginalia")
        work.isSaved = true
        target.insert(work)
        let victim = ReadingAnnotation(
            work: work, kind: .highlight, locatorString: Self.locator,
            note: "MY IRREPLACEABLE NOTE", color: .yellow,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        victim.lastModifiedAt = Date(timeIntervalSince1970: 1_500)
        target.insert(victim)
        try target.save()

        let contents = try forgedContents(
            annotationID: victim.id, workID: workID, work: work,
            note: "pwned", isPendingDeletion: false
        )
        _ = try KudosBackupService.restore(contents, into: target, defaults: try testDefaults())

        let all = try target.fetch(FetchDescriptor<ReadingAnnotation>())
        // The live row takes LWW — the attacker can deface what is displayed...
        let liveRow = try #require(all.first { $0.id == victim.id })
        #expect(liveRow.note == "pwned")
        // ...but the user's text is still in the store on a hidden sibling.
        #expect(
            all.contains { $0.id != victim.id && $0.note == "MY IRREPLACEABLE NOTE" && $0.isPendingDeletion },
            "the user's note was destroyed — M1f has regressed"
        )
    }

    /// The half of D8 that Grok rejected: annotation delete between the user's own devices
    /// depends on this LWW, because `annotationResolution(.suppressStaleData)` only skips and
    /// never sets the flag. Refusing incoming deletion flags would mean a highlight deleted on
    /// the phone never disappears on the iPad.
    /// The **dedup-site** half of M1c, which had no coverage at all.
    ///
    /// M1f's `parkDisplacedNote` protects the *id-keyed* path (same id, incoming note
    /// overwrites a pre-existing one) and is covered by
    /// `forgedSameIDRecordCannotDestroyAPreExistingNote`. But an attacker who knows a
    /// locator — an A4 adversary reads it out of the sync folder's own manifest —
    /// collides on `(work, kind, locatorString)` with a *different* UUID, which lands
    /// in `dedupeSamePassageAnnotations` instead. There, a pre-existing loser used to
    /// be `context.delete`d outright; it is now soft-deleted so the row and its text
    /// remain recoverable.
    ///
    /// Disabling that soft-delete flipped **no** test in the suite (verified by
    /// revert-check), which is why this exists. `twoDevicesEditingOneNoteConverge…`
    /// cannot catch it: it asserts on the surviving winner, and a hard-deleted loser
    /// and a soft-deleted loser look identical from there.
    @Test func aDedupCollisionSoftDeletesThePreExistingLoserRatherThanDestroyingIt() throws {
        let schema = schema()
        let target = try context(schema)
        let workID = UUID()
        let work = SavedWork(id: workID, title: "Annotated Work", author: "Marginalia")
        work.isSaved = true
        target.insert(work)

        let mine = ReadingAnnotation(
            work: work, kind: .highlight, locatorString: Self.locator,
            note: "MY IRREPLACEABLE NOTE", color: .yellow,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        mine.lastModifiedAt = Date(timeIntervalSince1970: 1_500)
        target.insert(mine)
        try target.save()
        let mineID = mine.id

        // Different UUID, colliding locator, newer stamp — it wins the dedup ranking.
        let contents = try forgedContents(
            annotationID: UUID(), workID: workID, work: work,
            note: "ATTACKER NOTE", isPendingDeletion: false
        )
        _ = try KudosBackupService.restore(contents, into: target, defaults: try testDefaults())

        let all = try target.fetch(FetchDescriptor<ReadingAnnotation>())
        let survivor = try #require(
            all.first { $0.id == mineID },
            "the pre-existing annotation row was destroyed outright by dedup"
        )
        #expect(survivor.isPendingDeletion || survivor.deletedAt != nil,
                "loser should be soft-deleted, not left live")
        // The text must still exist somewhere recoverable — either on the parked row
        // itself or salvaged onto the winner.
        let textSurvives = all.contains { $0.note.contains("MY IRREPLACEABLE NOTE") }
        #expect(textSurvives, "the user's note text is unrecoverable after a dedup collision")
    }

    @Test func incomingDeleteStillPropagatesToAPreExistingAnnotation() throws {
        let schema = schema()
        let target = try context(schema)
        let workID = UUID()
        let work = SavedWork(id: workID, title: "Annotated Work", author: "Marginalia")
        work.isSaved = true
        target.insert(work)
        let existing = ReadingAnnotation(
            work: work, kind: .highlight, locatorString: Self.locator,
            note: "note", color: .yellow, createdAt: Date(timeIntervalSince1970: 1_000)
        )
        existing.lastModifiedAt = Date(timeIntervalSince1970: 1_500)
        target.insert(existing)
        try target.save()

        // Device B deleted the highlight and synced.
        let contents = try forgedContents(
            annotationID: existing.id, workID: workID, work: work,
            note: "note", isPendingDeletion: true
        )
        _ = try KudosBackupService.restore(contents, into: target, defaults: try testDefaults())

        let applied = try #require(
            try target.fetch(FetchDescriptor<ReadingAnnotation>()).first { $0.id == existing.id }
        )
        #expect(applied.isPendingDeletion, "multi-device annotation delete stopped working")
    }

    /// The convergence case that killed the append rule. Two honest devices editing the same
    /// note must settle, not accumulate text on every sync cycle.
    @Test func twoDevicesEditingOneNoteConvergeInsteadOfAccumulating() throws {
        let schema = schema()
        let target = try context(schema)
        let workID = UUID()
        let work = SavedWork(id: workID, title: "Annotated Work", author: "Marginalia")
        work.isSaved = true
        target.insert(work)
        let annotation = ReadingAnnotation(
            work: work, kind: .highlight, locatorString: Self.locator,
            note: "A", color: .yellow, createdAt: Date(timeIntervalSince1970: 1_000)
        )
        annotation.lastModifiedAt = Date(timeIntervalSince1970: 1_500)
        target.insert(annotation)
        try target.save()

        // Device B's newer "B" arrives, twice (the second sync must be a no-op on the text).
        //
        // The incoming record carries a DIFFERENT UUID that collides only by
        // (work, kind, locatorString). That is the whole premise of ANN-8: two devices
        // creating the same highlight offline mint different ids. The earlier version of
        // this test reused `annotation.id`, so `restore()` matched by id and updated in
        // place — `dedupeSamePassageAnnotations` only acts when `group.count > 1`, so it
        // never ran, and this test proved nothing about the convergence it is named for.
        // Fixed id per iteration so the second sync is genuinely the same remote record.
        let deviceBID = UUID()
        for _ in 0..<2 {
            let contents = try forgedContents(
                annotationID: deviceBID, workID: workID, work: work,
                note: "B", isPendingDeletion: false
            )
            _ = try KudosBackupService.restore(contents, into: target, defaults: try testDefaults())
        }

        let live = try target.fetch(FetchDescriptor<ReadingAnnotation>())
            .filter { !$0.isPendingDeletion && $0.deletedAt == nil }
        #expect(live.count == 1)
        let survivor = try #require(live.first)
        #expect(survivor.note == "B", "expected a clean LWW winner, got an accumulated note")
        #expect(!survivor.note.contains("A\n\nB"), "the append ping-pong has come back")
    }

    private func forgedContents(
        annotationID: UUID,
        workID: UUID,
        work: SavedWork,
        note: String,
        isPendingDeletion: Bool
    ) throws -> KudosBackupContents {
        // Build the archived record from a donor object so the manifest carries exactly the
        // fields an attacker controls, including a winning lastModifiedAt.
        let donorSchema = schema()
        let donor = try context(donorSchema)
        let donorWork = SavedWork(id: workID, title: work.title, author: work.author)
        donorWork.isSaved = true
        // makeContents reads EPUB bytes off disk for any work with hasEPUB (which defaults to
        // true) — the donor has no file, so leaving it set makes the helper throw.
        donorWork.hasEPUB = false
        donor.insert(donorWork)
        let donorAnnotation = ReadingAnnotation(
            id: annotationID, work: donorWork, kind: .highlight,
            locatorString: Self.locator, note: note, color: .yellow,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        donorAnnotation.lastModifiedAt = Date().addingTimeInterval(60 * 60)
        donorAnnotation.isPendingDeletion = isPendingDeletion
        donor.insert(donorAnnotation)
        try donor.save()

        return try KudosBackupService.makeContents(
            works: [donorWork], bookmarks: [], fonts: [], readingQueues: [],
            annotations: [donorAnnotation], defaults: try testDefaults()
        )
    }

    // Matches ReadingAnnotationBackupTests exactly — the known-working shape for this schema.
    // Taking `.mainContext` off a freshly-constructed container instead threw during setup.
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

    private func testDefaults() throws -> UserDefaults {
        let name = "AnnotationNotePreservationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
}
