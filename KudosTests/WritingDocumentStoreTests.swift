import Foundation
import Testing
@testable import Kudos

private final class WritingDocumentClock: @unchecked Sendable {
    var date: Date
    init(_ date: Date) { self.date = date }
    func advance(_ seconds: TimeInterval) { date.addTimeInterval(seconds) }
}

private func withWritingStore(
    deviceID: String? = "device-test",
    _ body: (WritingDocumentStore, WritingDocumentClock, URL) async throws -> Void
) async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("writing-docs-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let clock = WritingDocumentClock(Date(timeIntervalSince1970: 1_700_000_000))
    let store = WritingDocumentStore(root: root, deviceID: deviceID, now: { clock.date })
    try await body(store, clock, root)
}

private func utf16Range(of needle: String, in body: String) -> Range<Int> {
    let found = (body as NSString).range(of: needle)
    return found.location..<(found.location + found.length)
}

struct WritingDocumentStoreTests {
    @Test func recordsRoundTrip() async throws {
        try await withWritingStore { store, _, _ in
            let work = try await store.createWork(title: "A Story", ao3WorkID: 42)
            #expect(try await store.openWork(work.id) == work)
            #expect(try await store.listWorks().map(\.id) == [work.id])
            let renamed = try await store.renameWork(work.id, title: "Renamed")
            #expect(renamed.title == "Renamed")
            #expect(renamed.createdAt == work.createdAt)
            #expect(renamed.ao3WorkID == 42)
            #expect(renamed.updatedBy == "device-test")

            var chapter = try await store.addChapter(workID: work.id, title: "One")
            let second = try await store.addChapter(workID: work.id, title: "Two")
            let reordered = try await store.reorderChapters(workID: work.id, order: [second.id, chapter.id])
            #expect(reordered.chapterOrder == [second.id, chapter.id])
            await #expect(throws: WritingDocumentError.chapterOrderMismatch) {
                try await store.reorderChapters(workID: work.id, order: [chapter.id])
            }

            chapter.summary = "Sum"
            chapter.notesBefore = "Before"
            chapter.notesAfter = "After & 世界"
            chapter.ao3ChapterID = 7
            chapter.status = .ao3Draft
            let document = try await store.saveChapter(
                workID: work.id,
                chapter: chapter,
                bodyHTML: "<p>Hello <strong>brave</strong> world</p>"
            )
            #expect(document.chapter.wordCount == 3)
            #expect(document.chapter.summary == "Sum")
            #expect(document.chapter.notesBefore == "Before")
            #expect(document.chapter.notesAfter == "After & 世界")
            #expect(document.chapter.ao3ChapterID == 7)
            #expect(document.chapter.status == .ao3Draft)
            #expect(try await store.loadChapter(workID: work.id, chapterID: chapter.id) == document)
            #expect(try await store.listVersions(workID: work.id, chapterID: chapter.id).isEmpty)

            var posted = document.chapter
            posted.status = .posted
            let postedDocument = try await store.saveChapter(
                workID: work.id,
                chapter: posted,
                bodyHTML: document.bodyHTML
            )
            #expect(postedDocument.chapter.status == .posted)
            #expect(postedDocument.chapter.bodySavedAt == document.chapter.bodySavedAt)
        }
    }

    @Test func worksWithNoAO3Ids() async throws {
        try await withWritingStore { store, _, _ in
            let work = try await store.createWork(title: "Offline")
            #expect(work.ao3WorkID == nil)
            let chapter = try await store.addChapter(workID: work.id, title: "Local")
            let document = try await store.saveChapter(
                workID: work.id,
                chapter: chapter,
                bodyHTML: "<p>Only on this device</p>"
            )
            #expect(document.chapter.ao3ChapterID == nil)
            #expect(document.chapter.status == .local)
            let listed = try await store.listChapters(workID: work.id)
            #expect(listed.map(\.status) == [.local])
        }
    }

    @Test func storyNotesRoundTripAndSupplyNames() async throws {
        try await withWritingStore { store, _, _ in
            let work = try await store.createWork(title: "Notes")
            for kind in [WritingStoryNoteKind.character, .place, .canon, .timeline, .other] {
                _ = try await store.addStoryNote(
                    workID: work.id, kind: kind, name: kind.rawValue, detail: "d", pinned: false
                )
            }
            let kinds = try await store.listStoryNotes(workID: work.id).map(\.kind)
            #expect(kinds == [.character, .place, .canon, .timeline, .other])
            _ = try await store.addStoryNote(
                workID: work.id, kind: .character, name: "Alice", detail: "brave", pinned: true
            )
            _ = try await store.addStoryNote(
                workID: work.id, kind: .place, name: "  Baker Street ", detail: "221B", pinned: false
            )
            let again = try await store.addStoryNote(
                workID: work.id, kind: .character, name: "Alice", detail: "again", pinned: false
            )
            _ = try await store.addStoryNote(
                workID: work.id, kind: .other, name: "   ", detail: "blank", pinned: false
            )
            #expect(try await store.storyNoteNames(workID: work.id) == [
                "character", "place", "canon", "timeline", "other", "Alice", "Baker Street",
            ])
            let alice = try #require(
                try await store.listStoryNotes(workID: work.id).first { $0.name == "Alice" }
            )
            #expect(alice.pinned)
            var edited = alice
            edited.detail = "changed"
            edited.pinned = false
            let saved = try await store.updateStoryNote(workID: work.id, note: edited)
            #expect(saved.detail == "changed")
            #expect(!saved.pinned)
            #expect(saved.updatedBy == "device-test")
            try await store.deleteStoryNote(workID: work.id, noteID: alice.id)
            #expect(try await store.storyNoteNames(workID: work.id).contains("Alice"))
            try await store.deleteStoryNote(workID: work.id, noteID: again.id)
            let namesAfterDelete = try await store.storyNoteNames(workID: work.id)
            #expect(!namesAfterDelete.contains("Alice"))
        }
    }

    @Test func annotationsRoundTrip() async throws {
        try await withWritingStore { store, _, _ in
            let work = try await store.createWork(title: "Margin")
            let chapter = try await store.addChapter(workID: work.id)
            let body = "The quick brown fox jumps."
            _ = try await store.saveChapter(workID: work.id, chapter: chapter, bodyHTML: body)
            let anchor = try #require(WritingAnnotationReanchor.capture(
                in: body,
                utf16Range: utf16Range(of: "brown fox", in: body)
            ))
            var note = try await store.addAnnotation(
                workID: work.id, chapterID: chapter.id, anchor: anchor, text: "check this", kind: .note
            )
            let marker = try await store.addAnnotation(
                workID: work.id,
                chapterID: chapter.id,
                anchor: WritingAnnotationAnchor(quote: "quick", prefix: "The ", suffix: " brown", utf16Offset: 4),
                text: "to come",
                kind: .tk
            )
            let longPrefix = String(repeating: "a", count: 40)
            let clamped = try await store.addAnnotation(
                workID: work.id,
                chapterID: chapter.id,
                anchor: WritingAnnotationAnchor(quote: "fox", prefix: longPrefix, suffix: longPrefix, utf16Offset: 1),
                text: "edges",
                kind: .note
            )
            #expect(clamped.prefix.count == WritingAnnotationReanchor.contextLimit)
            #expect(clamped.suffix.count == WritingAnnotationReanchor.contextLimit)
            note.resolvedAt = Date(timeIntervalSince1970: 1_700_000_100)
            note.text = "checked"
            let resolved = try await store.updateAnnotation(workID: work.id, annotation: note)
            #expect(resolved.resolvedAt == note.resolvedAt)
            #expect(resolved.text == "checked")
            #expect(resolved.kind == .note)
            #expect(marker.kind == .tk)
            #expect(try await store.listAnnotations(workID: work.id, chapterID: chapter.id).map(\.id) == [
                resolved.id, marker.id, clamped.id,
            ])
            let loaded = try await store.loadChapter(workID: work.id, chapterID: chapter.id)
            #expect(!loaded.bodyHTML.contains("checked"))
            #expect(!loaded.bodyHTML.contains("to come"))
            try await store.deleteAnnotation(workID: work.id, annotationID: marker.id)
            #expect(try await store.listAnnotations(workID: work.id).map(\.id) == [resolved.id, clamped.id])
        }
    }

    @Test func anInterruptedWriteNeverReplacesGoodData() async throws {
        try await withWritingStore { store, _, root in
            let work = try await store.createWork(title: "Good")
            let chapter = try await store.addChapter(workID: work.id, title: "Ch")
            let saved = try await store.saveChapter(
                workID: work.id, chapter: chapter, bodyHTML: "<p>Good body</p>"
            )
            let workDirectory = WritingDocumentPaths.workDirectory(root: root, id: work.id)
            let workFile = WritingDocumentPaths.workFile(workDirectory)
            let bodyFile = WritingDocumentPaths.bodyFile(
                WritingDocumentPaths.chapterDirectory(workDirectory, id: chapter.id)
            )
            try Data(#"{"title":"Bad"}"#.utf8).write(
                to: WritingDocumentPaths.temporaryFile(for: workFile)
            )
            try Data("bad body".utf8).write(to: WritingDocumentPaths.temporaryFile(for: bodyFile))
            #expect(try await store.openWork(work.id).title == "Good")
            let loaded = try await store.loadChapter(workID: work.id, chapterID: chapter.id)
            #expect(loaded.bodyHTML == saved.bodyHTML)

            try FileManager.default.removeItem(at: workFile)
            await #expect(throws: WritingDocumentError.workNotFound(work.id)) {
                try await store.openWork(work.id)
            }
            #expect(!FileManager.default.fileExists(atPath: workFile.path))
        }
    }

    @Test func aMissingOrderEntryDoesNotDropTheChapter() async throws {
        try await withWritingStore { store, _, root in
            let work = try await store.createWork(title: "Heal")
            let chapter = try await store.addChapter(workID: work.id, title: "Kept")
            let file = WritingDocumentPaths.workFile(
                WritingDocumentPaths.workDirectory(root: root, id: work.id)
            )
            var stored = try WritingDocumentIO.readJSON(WritingWork.self, from: file)
            stored.chapterOrder = []
            try WritingDocumentIO.writeJSON(stored, to: file)
            #expect(try await store.listChapters(workID: work.id).map(\.id) == [chapter.id])
        }
    }

    @Test func recentlyDeletedRetainsAndRestores() async throws {
        try await withWritingStore { store, clock, _ in
            let work = try await store.createWork(title: "Bin")
            let first = try await store.addChapter(workID: work.id, title: "A")
            let middle = try await store.addChapter(workID: work.id, title: "B")
            let last = try await store.addChapter(workID: work.id, title: "C")
            let note = try await store.addStoryNote(
                workID: work.id, kind: .place, name: "Baker Street", detail: "221B", pinned: true
            )

            try await store.deleteChapter(workID: work.id, chapterID: middle.id)
            #expect(try await store.listChapters(workID: work.id).map(\.id) == [first.id, last.id])
            #expect(try await store.listRecentlyDeleted().map(\.id) == [middle.id])
            #expect(try await store.restoreChapter(middle.id).title == "B")
            #expect(try await store.listChapters(workID: work.id).map(\.title) == ["A", "B", "C"])

            try await store.deleteWork(work.id)
            #expect(try await store.listWorks().isEmpty)
            await #expect(throws: WritingDocumentError.workNotFound(work.id)) {
                try await store.openWork(work.id)
            }
            #expect(try await store.restoreWork(work.id).title == "Bin")
            #expect(try await store.listChapters(workID: work.id).map(\.title) == ["A", "B", "C"])
            #expect(try await store.listStoryNotes(workID: work.id) == [note])

            try await store.deleteChapter(workID: work.id, chapterID: middle.id)
            clock.advance(WritingDocumentStore.retention)
            #expect(try await store.emptyRecentlyDeleted().isEmpty)
            clock.advance(1)
            #expect(try await store.emptyRecentlyDeleted().map(\.id) == [middle.id])
            #expect(try await store.listWorks().map(\.id) == [work.id])
            await #expect(throws: WritingDocumentError.notInRecentlyDeleted(middle.id)) {
                try await store.restoreChapter(middle.id)
            }

            try await store.deleteWork(work.id)
            try await store.deleteNow(work.id)
            #expect(try await store.listRecentlyDeleted().isEmpty)
            await #expect(throws: WritingDocumentError.notInRecentlyDeleted(work.id)) {
                try await store.deleteNow(work.id)
            }
        }
    }

    @Test func versionsFollowTheTenMinuteRule() async throws {
        try await withWritingStore { store, clock, _ in
            let work = try await store.createWork(title: "Versions")
            var document = try await store.saveChapter(
                workID: work.id,
                chapter: try await store.addChapter(workID: work.id, title: "Ch"),
                bodyHTML: "one"
            )
            let chapterID = document.chapter.id
            clock.advance(5 * 60)
            document = try await store.saveChapter(
                workID: work.id, chapter: document.chapter, bodyHTML: "two"
            )
            #expect(try await store.listVersions(workID: work.id, chapterID: chapterID).isEmpty)

            clock.advance(WritingDocumentStore.automaticVersionGap)
            var retitle = document.chapter
            retitle.title = "Retitled"
            let retitled = try await store.saveChapter(
                workID: work.id, chapter: retitle, bodyHTML: "two"
            )
            #expect(try await store.listVersions(workID: work.id, chapterID: chapterID).isEmpty)
            #expect(retitled.chapter.bodySavedAt == document.chapter.bodySavedAt)

            clock.advance(1)
            document = try await store.saveChapter(
                workID: work.id, chapter: retitled.chapter, bodyHTML: "three"
            )
            let versions = try await store.listVersions(workID: work.id, chapterID: chapterID)
            #expect(versions.map(\.cause) == [.automatic])
            let body = try await store.versionBody(
                workID: work.id, chapterID: chapterID, versionID: versions[0].id
            )
            #expect(body == "two")
            #expect(document.bodyHTML == "three")
        }
    }

}

struct WritingDocumentPolicyTests {
    @Test func destructiveSnapshotsStayOutsideTheAutomaticCap() async throws {
        try await withWritingStore { store, clock, _ in
            let work = try await store.createWork(title: "Cap")
            var document = try await store.saveChapter(
                workID: work.id,
                chapter: try await store.addChapter(workID: work.id),
                bodyHTML: "v0"
            )
            let chapterID = document.chapter.id
            for index in 1...21 {
                clock.advance(WritingDocumentStore.automaticVersionGap)
                document = try await store.saveChapter(
                    workID: work.id, chapter: document.chapter, bodyHTML: "v\(index)"
                )
            }
            let beforeDestructive = document.bodyHTML
            let replaced = try await store.saveChapter(
                workID: work.id,
                chapter: document.chapter,
                bodyHTML: "replaced",
                kind: .destructive
            )
            clock.advance(WritingDocumentStore.automaticVersionGap)
            var latest = replaced
            for index in 1...3 {
                latest = try await store.saveChapter(
                    workID: work.id, chapter: latest.chapter, bodyHTML: "after-\(index)"
                )
                clock.advance(WritingDocumentStore.automaticVersionGap)
            }
            #expect(latest.bodyHTML == "after-3")
            let versions = try await store.listVersions(workID: work.id, chapterID: chapterID)
            let automatic = versions.filter { $0.cause == .automatic }
            let destructive = versions.filter { $0.cause == .destructive }
            #expect(automatic.count == WritingDocumentStore.retainedAutomaticVersions)
            #expect(destructive.count == 1)
            let kept = try await store.versionBody(
                workID: work.id, chapterID: chapterID, versionID: destructive[0].id
            )
            #expect(kept == beforeDestructive)
        }
    }

    @Test func restoringAVersionKeepsTheTextItReplaces() async throws {
        try await withWritingStore { store, clock, _ in
            let work = try await store.createWork(title: "Restore")
            var document = try await store.saveChapter(
                workID: work.id,
                chapter: try await store.addChapter(workID: work.id),
                bodyHTML: "first"
            )
            clock.advance(WritingDocumentStore.automaticVersionGap)
            document = try await store.saveChapter(
                workID: work.id, chapter: document.chapter, bodyHTML: "second"
            )
            let previous = try #require(
                try await store.listVersions(workID: work.id, chapterID: document.chapter.id).first
            )
            let restored = try await store.restoreVersion(
                workID: work.id, chapterID: document.chapter.id, versionID: previous.id
            )
            #expect(restored.bodyHTML == "first")
            let destructive = try #require(
                try await store.listVersions(workID: work.id, chapterID: document.chapter.id)
                    .first { $0.cause == .destructive }
            )
            let kept = try await store.versionBody(
                workID: work.id, chapterID: document.chapter.id, versionID: destructive.id
            )
            #expect(kept == "second")
        }
    }

    @Test func destructiveSnapshotsExpireAndAutomaticOnesDoNot() async throws {
        try await withWritingStore { store, clock, _ in
            let work = try await store.createWork(title: "Age")
            var document = try await store.saveChapter(
                workID: work.id,
                chapter: try await store.addChapter(workID: work.id),
                bodyHTML: "body"
            )
            document = try await store.saveChapter(
                workID: work.id, chapter: document.chapter, bodyHTML: "mid", kind: .destructive
            )
            clock.advance(WritingDocumentStore.automaticVersionGap)
            let automaticAt = clock.date
            document = try await store.saveChapter(
                workID: work.id, chapter: document.chapter, bodyHTML: "later"
            )
            clock.date = automaticAt.addingTimeInterval(WritingDocumentStore.retention + 1)
            _ = try await store.emptyRecentlyDeleted()
            let versions = try await store.listVersions(workID: work.id, chapterID: document.chapter.id)
            #expect(versions.map(\.cause) == [.automatic])
            let body = try await store.versionBody(
                workID: work.id, chapterID: document.chapter.id, versionID: versions[0].id
            )
            #expect(body == "mid")
        }
    }

    @Test func reanchoringReportsWhatItCanPlace() async throws {
        let body = "The quick brown fox jumps over the lazy dog."
        let anchor = try #require(WritingAnnotationReanchor.capture(
            in: body, utf16Range: utf16Range(of: "brown fox", in: body)
        ))
        #expect(WritingAnnotationReanchor.reanchor(anchor, in: body) == .placed(anchor))

        let moved = "INTRO " + body
        guard case .placed(let movedAnchor) = WritingAnnotationReanchor.reanchor(anchor, in: moved) else {
            Issue.record("A moved quote should still place")
            return
        }
        #expect(movedAnchor.quote == "brown fox")
        #expect(movedAnchor.utf16Offset != anchor.utf16Offset)

        let edited = body.replacingOccurrences(of: "brown fox", with: "brwn fox")
        guard case .placed(let editedAnchor) = WritingAnnotationReanchor.reanchor(anchor, in: edited) else {
            Issue.record("A one-character edit should still place")
            return
        }
        #expect(editedAnchor.quote == "brwn fox")

        let contextEdited = body.replacingOccurrences(of: "quick", with: "quik")
        guard case .placed(let contextAnchor) = WritingAnnotationReanchor.reanchor(anchor, in: contextEdited) else {
            Issue.record("An edit beside the quote should still place")
            return
        }
        #expect(contextAnchor.quote == "brown fox")

        let doubled = body + "\n" + body
        #expect(WritingAnnotationReanchor.reanchor(anchor, in: doubled) == .placed(anchor))

        let deleted = body.replacingOccurrences(of: "brown fox", with: "cat")
        #expect(WritingAnnotationReanchor.reanchor(anchor, in: deleted) == .lost)

        let lead = String(repeating: "a", count: 50) + "QUOTE" + String(repeating: "b", count: 50)
        let captured = try #require(WritingAnnotationReanchor.capture(
            in: lead, utf16Range: utf16Range(of: "QUOTE", in: lead)
        ))
        #expect(captured.prefix.count == 32)
        #expect(captured.suffix.count == 32)
        let emoji = "Hello 👩‍💻 world"
        let emojiAnchor = try #require(WritingAnnotationReanchor.capture(
            in: emoji, utf16Range: utf16Range(of: "world", in: emoji)
        ))
        let world = try #require(emoji.range(of: "world")?.lowerBound)
        let characterOffset = emoji.distance(from: emoji.startIndex, to: world)
        #expect(emojiAnchor.utf16Offset > characterOffset)
        #expect(WritingAnnotationReanchor.reanchor(emojiAnchor, in: emoji) == .placed(emojiAnchor))
    }

    @Test func theStoreSavesAReanchoredNoteAndLeavesALostOne() async throws {
        try await withWritingStore { store, _, _ in
            let work = try await store.createWork(title: "Anchor")
            let chapter = try await store.addChapter(workID: work.id)
            let body = "The quick brown fox jumps over the lazy dog."
            _ = try await store.saveChapter(workID: work.id, chapter: chapter, bodyHTML: body)
            let anchor = try #require(WritingAnnotationReanchor.capture(
                in: body, utf16Range: utf16Range(of: "brown fox", in: body)
            ))
            let note = try await store.addAnnotation(
                workID: work.id, chapterID: chapter.id, anchor: anchor, text: "private", kind: .note
            )
            let other = try await store.addChapter(workID: work.id, title: "Other")
            let otherNote = try await store.addAnnotation(
                workID: work.id,
                chapterID: other.id,
                anchor: WritingAnnotationAnchor(quote: "other", prefix: "", suffix: "", utf16Offset: 0),
                text: "stays",
                kind: .note
            )
            let moved = "INTRO " + body
            let placed = try await store.reanchorAnnotations(
                workID: work.id, chapterID: chapter.id, bodyHTML: moved
            )
            #expect(placed.lost.isEmpty)
            #expect(placed.placed.map(\.id) == [note.id])
            #expect(placed.placed[0].utf16Offset != note.utf16Offset)
            let stored = try await store.listAnnotations(workID: work.id, chapterID: chapter.id)
            #expect(stored.first?.utf16Offset == placed.placed[0].utf16Offset)

            let lost = try await store.reanchorAnnotations(
                workID: work.id, chapterID: chapter.id, bodyHTML: "The quick cat jumps over the lazy dog."
            )
            #expect(lost.placed.isEmpty)
            #expect(lost.lost.map(\.id) == [note.id])
            let unchanged = try await store.listAnnotations(workID: work.id, chapterID: chapter.id)
            #expect(unchanged.first?.quote == placed.placed[0].quote)
            let others = try await store.listAnnotations(workID: work.id, chapterID: other.id)
            #expect(others == [otherNote])
        }
    }

    @Test func concurrentCallsStayConsistent() async throws {
        try await withWritingStore { store, _, root in
            let count = 24
            let workIDs = try await withThrowingTaskGroup(of: UUID.self) { group in
                for index in 0..<count {
                    group.addTask { try await store.createWork(title: "Work \(index)").id }
                }
                var collected: [UUID] = []
                for try await id in group { collected.append(id) }
                return collected
            }
            #expect(Set(workIDs).count == count)
            #expect(try await store.listWorks().count == count)

            let work = try await store.createWork(title: "Chapters")
            let chapterIDs = try await withThrowingTaskGroup(of: UUID.self) { group in
                for index in 0..<count {
                    group.addTask { try await store.addChapter(workID: work.id, title: "C\(index)").id }
                }
                var collected: [UUID] = []
                for try await id in group { collected.append(id) }
                return collected
            }
            let opened = try await store.openWork(work.id)
            #expect(opened.chapterOrder.count == count)
            #expect(Set(opened.chapterOrder) == Set(chapterIDs))

            let bodies = (0..<12).map { "complete-body-\($0)" }
            let target = chapterIDs[0]
            try await withThrowingTaskGroup(of: Void.self) { group in
                for body in bodies {
                    group.addTask {
                        let current = try await store.loadChapter(workID: work.id, chapterID: target)
                        _ = try await store.saveChapter(
                            workID: work.id, chapter: current.chapter, bodyHTML: body
                        )
                    }
                }
                try await group.waitForAll()
            }
            let loaded = try await store.loadChapter(workID: work.id, chapterID: target)
            #expect(bodies.contains(loaded.bodyHTML))
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil
            ) else {
                Issue.record("The store directory could not be listed")
                return
            }
            var temporary = false
            while let url = enumerator.nextObject() as? URL {
                if url.lastPathComponent.hasSuffix(".tmp") { temporary = true }
            }
            #expect(!temporary)
        }
    }

    @Test func theInstallDeviceIdIsReused() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("writing-docs-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = Date(timeIntervalSince1970: 1_700_000_000)
        let first = WritingDocumentStore(root: root, now: { clock })
        let created = try await first.createWork(title: "One")
        let second = WritingDocumentStore(root: root, now: { clock })
        let again = try await second.createWork(title: "Two")
        #expect(created.updatedBy == again.updatedBy)
        #expect(!created.updatedBy.isEmpty)
        let stored = try String(contentsOf: WritingDocumentPaths.deviceID(root), encoding: .utf8)
        #expect(stored == created.updatedBy)
    }
}
