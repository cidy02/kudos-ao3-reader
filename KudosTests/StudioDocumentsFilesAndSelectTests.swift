import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Kudos

private final class StudioTestClock: @unchecked Sendable {
    var date: Date
    init(_ date: Date) { self.date = date }
    func advance(days: Double) { date.addTimeInterval(days * 24 * 60 * 60) }
}

private func withTempStudioStore(
    _ body: (WritingDocumentStore, StudioTestClock, URL) async throws -> Void
) async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("studio-s2-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let clock = StudioTestClock(Date(timeIntervalSince1970: 1_760_000_000))
    let store = WritingDocumentStore(root: root, deviceID: "test-device", now: { clock.date })
    try await body(store, clock, root)
}

private func makeSelectWork(
    title: String,
    postedID: Int? = nil,
    draftID: Int? = nil,
    hasLocal: Bool = false
) -> StudioWorkItem {
    let now = Date(timeIntervalSince1970: 1_760_000_000)
    let localWork: WritingWork? = if hasLocal {
        WritingWork(
            id: UUID(),
            title: title,
            ao3WorkID: postedID ?? draftID,
            createdAt: now,
            updatedAt: now,
            updatedBy: "test-device",
            chapterOrder: []
        )
    } else {
        nil
    }

    func summary(_ id: Int) -> AO3WorkSummary {
        AO3WorkSummary(
            id: id,
            title: title,
            authors: ["saltwindow"],
            fandoms: ["Original Work"],
            rating: "General Audiences",
            warnings: ["No Archive Warnings Apply"],
            categories: ["Gen"],
            isComplete: true,
            dateUpdated: "2026-10-20",
            tags: [],
            summary: "",
            language: "English",
            words: 1500,
            chapters: "1/1",
            comments: nil,
            kudos: nil,
            hits: nil,
            seriesTitle: nil,
            seriesURL: nil,
            seriesPosition: nil
        )
    }

    let id = if let localWork {
        "local:\(localWork.id.uuidString)"
    } else if let remoteID = postedID ?? draftID {
        "ao3:\(remoteID)"
    } else {
        "local:\(UUID().uuidString)"
    }
    return StudioWorkItem(
        id: id,
        localWork: localWork,
        localChapters: [],
        storyNotes: [],
        chapterExcerpts: [:],
        ao3PostedWork: postedID.map(summary),
        ao3DraftWork: draftID.map(summary),
        ao3DraftDaysLeft: draftID != nil ? 12 : nil
    )
}

struct StudioDocumentsImportTests {
    @Test func importsPlainTextMarkdownAndHTMLIntoStore() async throws {
        try await withTempStudioStore { store, _, root in
            let fixtureDir = root.appendingPathComponent("imports", isDirectory: true)
            try FileManager.default.createDirectory(at: fixtureDir, withIntermediateDirectories: true)

            let txtURL = fixtureDir.appendingPathComponent("Salt_Air.txt")
            try "First line & <tag>\nSecond line\n\nSecond paragraph.".write(
                to: txtURL,
                atomically: true,
                encoding: .utf8
            )
            let importedTxt = try await StudioDocumentImporter.importFile(at: txtURL, into: store)
            #expect(importedTxt.format == .plainText)
            #expect(importedTxt.work.title == "Salt Air")
            #expect(importedTxt.work.ao3WorkID == nil)
            let loadedTxt = try await store.loadChapter(
                workID: importedTxt.work.id,
                chapterID: importedTxt.chapter.id
            )
            #expect(loadedTxt.bodyHTML.contains("&amp; &lt;tag&gt;"))
            #expect(loadedTxt.bodyHTML.contains("<br>"))
            #expect(loadedTxt.chapter.wordCount > 0)

            let mdURL = fixtureDir.appendingPathComponent("draft.md")
            let markdown = """
            # Slack Water

            The tide had **turned** an *hour* ago.

            > "Wait for the bell."

            - One
            - Two
            """
            try markdown.write(to: mdURL, atomically: true, encoding: .utf8)
            let importedMD = try await StudioDocumentImporter.importFile(at: mdURL, into: store)
            #expect(importedMD.format == .markdown)
            #expect(importedMD.work.title == "Slack Water")
            let loadedMD = try await store.loadChapter(
                workID: importedMD.work.id,
                chapterID: importedMD.chapter.id
            )
            #expect(loadedMD.bodyHTML.contains("<strong>turned</strong>"))
            #expect(loadedMD.bodyHTML.contains("<em>hour</em>"))
            #expect(loadedMD.bodyHTML.contains("<blockquote>"))
            #expect(loadedMD.bodyHTML.contains("<ul>"))

            let htmlURL = fixtureDir.appendingPathComponent("chapter.html")
            let html = """
            <html><head><title>Spring Tide</title><script>alert(1)</script></head>
            <body><p onclick="evil()">Everyone in the village watched.</p>
            <img src="https://evil.example/pixel.png"><a href="javascript:alert(1)">bad</a></body></html>
            """
            try html.write(to: htmlURL, atomically: true, encoding: .utf8)
            let importedHTML = try await StudioDocumentImporter.importFile(at: htmlURL, into: store)
            #expect(importedHTML.format == .html)
            #expect(importedHTML.work.title == "Spring Tide")
            let loadedHTML = try await store.loadChapter(
                workID: importedHTML.work.id,
                chapterID: importedHTML.chapter.id
            )
            #expect(loadedHTML.bodyHTML.contains("Everyone in the village watched."))
            #expect(!loadedHTML.bodyHTML.contains("<script"))
            #expect(!loadedHTML.bodyHTML.contains("<img"))
            #expect(!loadedHTML.bodyHTML.contains("onclick"))
            #expect(!loadedHTML.bodyHTML.contains("javascript:"))

            let allWorks = try await store.listWorks()
            #expect(allWorks.count == 3)
        }
    }

    @Test func rejectsUnsupportedFormatsAndBinaryDisguisedAsText() async throws {
        try await withTempStudioStore { store, _, root in
            let dir = root.appendingPathComponent("bad-imports", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let zipMagic = Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00])
            let pdfMagic = Data("%PDF-1.7\n1 0 obj".utf8)
            let rtfMagic = Data("{\\rtf1\\ansi Hello}".utf8)

            let rejectedCases: [(String, Data)] = [
                ("book.epub", zipMagic),
                ("archive.zip", zipMagic),
                ("story.pdf", pdfMagic),
                ("notes.rtf", rtfMagic),
                ("data.json", Data("{\"hello\":\"world\"}".utf8)),
                ("noextension", Data("Just plain text without an extension".utf8)),
                ("disguised.txt", zipMagic),
                ("binary.md", Data([0x48, 0x65, 0x00, 0x6C, 0x6F]))
            ]

            for (filename, data) in rejectedCases {
                let url = dir.appendingPathComponent(filename)
                try data.write(to: url)
                await #expect(throws: StudioDocumentImportError.self) {
                    _ = try await StudioDocumentImporter.importFile(at: url, into: store)
                }
            }

            let emptyURL = dir.appendingPathComponent("empty.txt")
            try Data("   \n\n  ".utf8).write(to: emptyURL)
            await #expect(throws: StudioDocumentImportError.emptyDocument) {
                _ = try await StudioDocumentImporter.importFile(at: emptyURL, into: store)
            }

            let scriptOnlyURL = dir.appendingPathComponent("scripts.html")
            try Data("<script>alert('x')</script>".utf8).write(to: scriptOnlyURL)
            await #expect(throws: StudioDocumentImportError.emptyDocument) {
                _ = try await StudioDocumentImporter.importFile(at: scriptOnlyURL, into: store)
            }

            let remainingWorks = try await store.listWorks()
            #expect(remainingWorks.isEmpty)

            let allowed = StudioDocumentImporter.allowedContentTypes
            #expect(allowed.contains(.plainText))
            #expect(allowed.contains(.html))
            #expect(!allowed.contains(.pdf))
            if let docx = UTType("org.openxmlformats.wordprocessingml.document") {
                #expect(allowed.contains(docx))
            }
        }
    }

    @Test func windows1252SmartQuotesDecodeAndRemoteImagesStayOut() throws {
        let quotes = Data([0x93, 0x48, 0x69, 0x94])
        let text = try StudioDocumentImporter.decodeText(quotes)
        #expect(text.contains("\u{201C}"))
        #expect(text.contains("Hi"))
        #expect(text.contains("\u{201D}"))
        #expect(!text.contains("\u{0093}"))

        let html = """
        <html><head><title>T</title></head><body><p>Hello</p>\
        <div style="background-image:url(https://evil.example/a.png)">x</div>\
        <img src="https://evil.example/b.png" alt="pic"></body></html>
        """
        let converted = try StudioDocumentImporter.convertToHTML(
            text: html,
            format: .html,
            fallbackTitle: "T"
        )
        #expect(converted.bodyHTML.contains("Hello"))
        #expect(!converted.bodyHTML.localizedCaseInsensitiveContains("evil.example"))

        let markdown = "See ![cover](https://evil.example/a.png) please."
        let rendered = try StudioDocumentImporter.convertToHTML(
            text: markdown,
            format: .markdown,
            fallbackTitle: "Note"
        )
        #expect(rendered.bodyHTML.contains("cover"))
        #expect(!rendered.bodyHTML.localizedCaseInsensitiveContains("evil.example"))
    }
}

struct StudioRecentlyDeletedAndWorkFilesTests {
    @Test func recentlyDeletedSupportsRestoreDeleteNowAnd30DayPurge() async throws {
        try await withTempStudioStore { store, clock, _ in
            let workA = try await store.createWork(title: "Keep Me")
            let chapterA = try await store.addChapter(workID: workA.id, title: "Chapter One")
            _ = try await store.saveChapter(workID: workA.id, chapter: chapterA, bodyHTML: "<p>Hello</p>")

            let workB = try await store.createWork(title: "Delete Immediately")
            let workC = try await store.createWork(title: "Expire After Thirty Days")

            try await store.deleteWork(workA.id)
            try await store.deleteWork(workB.id)
            try await store.deleteWork(workC.id)

            let deletedList = try await store.listRecentlyDeleted()
            #expect(deletedList.count == 3)

            let deletedAt = clock.date
            #expect(StudioRecentlyDeletedHelper.daysRemaining(deletedAt: deletedAt, now: deletedAt) == 30)
            #expect(!StudioRecentlyDeletedHelper.isUrgent(deletedAt: deletedAt, now: deletedAt))

            // Restore workA
            let restored = try await store.restoreWork(workA.id)
            #expect(restored.title == "Keep Me")
            let liveAfterRestore = try await store.listWorks()
            #expect(liveAfterRestore.map(\.id) == [workA.id])

            // Permanently delete workB now
            try await store.deleteNow(workB.id)
            let deletedAfterNow = try await store.listRecentlyDeleted()
            #expect(deletedAfterNow.map(\.id) == [workC.id])

            // Day 29: still kept, marked urgent (1 day left)
            clock.advance(days: 29)
            let daysLeft29 = StudioRecentlyDeletedHelper.daysRemaining(deletedAt: deletedAt, now: clock.date)
            #expect(daysLeft29 == 1)
            #expect(StudioRecentlyDeletedHelper.isUrgent(deletedAt: deletedAt, now: clock.date))
            let countdown29 = StudioRecentlyDeletedHelper.countdownText(deletedAt: deletedAt, now: clock.date)
            #expect(countdown29 == "1 day left")

            let purgedAt29 = try await store.emptyRecentlyDeleted()
            #expect(purgedAt29.isEmpty)

            // Past 30 days: purged by emptyRecentlyDeleted
            clock.advance(days: 2)
            let purgedAt31 = try await store.emptyRecentlyDeleted()
            #expect(purgedAt31.map(\.id) == [workC.id])

            let finalTrash = try await store.listRecentlyDeleted()
            #expect(finalTrash.isEmpty)
        }
    }

    @Test func workFilesChapterRenameDuplicateMoveAndDelete() async throws {
        try await withTempStudioStore { store, _, _ in
            let work = try await store.createWork(title: "Tide")
            let ch1 = try await store.addChapter(workID: work.id, title: "Low Water")
            let ch2 = try await store.addChapter(workID: work.id, title: "The Bar")
            _ = try await store.saveChapter(workID: work.id, chapter: ch1, bodyHTML: "<p>First chapter body</p>")

            let renamed = try await StudioWorkFilesLogic.renameChapter(
                in: store,
                workID: work.id,
                chapterID: ch2.id,
                title: "Spring Tide"
            )
            #expect(renamed.title == "Spring Tide")

            let duplicated = try await StudioWorkFilesLogic.duplicateChapter(
                in: store,
                workID: work.id,
                chapterID: ch1.id
            )
            #expect(duplicated.title == "Low Water Copy")
            #expect(duplicated.status == .local)
            #expect(duplicated.ao3ChapterID == nil)

            let orderAfterDuplicate = try await store.listChapters(workID: work.id).map(\.id)
            #expect(orderAfterDuplicate == [ch1.id, duplicated.id, ch2.id])

            _ = try await StudioWorkFilesLogic.moveChapter(
                in: store,
                workID: work.id,
                chapterID: ch2.id,
                direction: .up
            )
            let orderAfterMoveUp = try await store.listChapters(workID: work.id).map(\.id)
            #expect(orderAfterMoveUp == [ch1.id, ch2.id, duplicated.id])

            try await StudioWorkFilesLogic.deleteChapter(
                in: store,
                workID: work.id,
                chapterID: duplicated.id
            )
            let chaptersAfterDelete = try await store.listChapters(workID: work.id).map(\.id)
            #expect(chaptersAfterDelete == [ch1.id, ch2.id])

            let deletedItems = try await store.listRecentlyDeleted()
            #expect(deletedItems.map(\.id) == [duplicated.id])

            // Merging AO3 chapters + unlinked local planned chapter
            let merged = StudioWorkFilesLogic.mergeChapters(
                localWorkID: work.id,
                localChapters: try await store.listChapters(workID: work.id),
                ao3WorkID: 777,
                ao3Chapters: [AO3ChapterRef(id: 90, position: 1, title: "Chapter 1", dateText: "2026-09-03")],
                isAO3DraftWork: false
            )
            #expect(merged.count == 3)
            #expect(merged[0].badge == .posted)
            #expect(merged[1].badge == .onDevice)
            #expect(merged[2].badge == .planned)
        }
    }
}

struct StudioSelectPolicyTests {
    @Test func emptySelectionDisablesAllActions() {
        let caps = StudioSelectPolicy.evaluate(selected: [], isSignedIn: true)
        #expect(!caps.canEditTogether)
        #expect(!caps.canExport)
        #expect(!caps.canOrphan)
        #expect(!caps.canDelete)
    }

    @Test func postedOnlySelectionAllowsEditTogetherOrphanAndDelete() {
        let posted1 = makeSelectWork(title: "Work 1", postedID: 1, hasLocal: false)
        let posted2 = makeSelectWork(title: "Work 2", postedID: 2, hasLocal: true)

        let caps = StudioSelectPolicy.evaluate(selected: [posted1, posted2], isSignedIn: true)
        #expect(caps.canEditTogether)
        #expect(caps.editTogetherWorkIDs == [1, 2])
        #expect(caps.canOrphan)
        #expect(caps.orphanWorkIDs == [1, 2])
        #expect(caps.canExport)
        #expect(caps.exportableLocalWorkIDs.count == 1)
        #expect(caps.canDelete)
        #expect(caps.deleteAO3WorkIDs == [1, 2])
        #expect(caps.deleteLocalWorkIDs.count == 1)
    }

    @Test func postedAndAO3DraftAllowsEditTogetherAndDeleteButBlocksOrphan() {
        let posted = makeSelectWork(title: "Posted", postedID: 10)
        let draft = makeSelectWork(title: "Draft", draftID: 20)

        let caps = StudioSelectPolicy.evaluate(selected: [posted, draft], isSignedIn: true)
        #expect(caps.canEditTogether)
        #expect(caps.editTogetherWorkIDs == [10, 20])
        #expect(!caps.canOrphan)
        #expect(caps.orphanWorkIDs.isEmpty)
        #expect(!caps.canExport)
        #expect(caps.canDelete)
        #expect(caps.deleteAO3WorkIDs == [10, 20])
    }

    @Test func mixedPostedDraftAndLocalBlocksAO3OnlyBulkActions() throws {
        let posted = makeSelectWork(title: "Posted", postedID: 10)
        let draft = makeSelectWork(title: "Draft", draftID: 20)
        let local = makeSelectWork(title: "Local", hasLocal: true)
        let localID = try #require(local.localWork?.id)

        let caps = StudioSelectPolicy.evaluate(selected: [posted, draft, local], isSignedIn: true)
        #expect(!caps.canEditTogether)
        #expect(caps.editTogetherWorkIDs.isEmpty)
        #expect(!caps.canOrphan)
        #expect(caps.orphanWorkIDs.isEmpty)
        #expect(caps.canExport)
        #expect(caps.exportableLocalWorkIDs == [localID])
        #expect(caps.canDelete)
        #expect(caps.deleteAO3WorkIDs == [10, 20])
        #expect(caps.deleteLocalWorkIDs == [localID])
    }

    @Test func localOnlyWorksSignedInAndSignedOut() {
        let local1 = makeSelectWork(title: "Local 1", hasLocal: true)
        let local2 = makeSelectWork(title: "Local 2", hasLocal: true)

        for signedIn in [true, false] {
            let caps = StudioSelectPolicy.evaluate(selected: [local1, local2], isSignedIn: signedIn)
            #expect(!caps.canEditTogether)
            #expect(!caps.canOrphan)
            #expect(caps.canExport)
            #expect(caps.canDelete)
            #expect(caps.deleteAO3WorkIDs.isEmpty)
            #expect(caps.deleteLocalWorkIDs.count == 2)
        }
    }

    @Test func signedOutCanTrashLocalCopyButNotTheAO3Work() throws {
        let posted = makeSelectWork(title: "Posted", postedID: 10, hasLocal: true)
        let localID = try #require(posted.localWork?.id)

        let caps = StudioSelectPolicy.evaluate(selected: [posted], isSignedIn: false)
        #expect(!caps.canEditTogether)
        #expect(!caps.canOrphan)
        #expect(caps.canDelete)
        #expect(caps.canExport)
        #expect(caps.deleteAO3WorkIDs.isEmpty)
        #expect(caps.deleteLocalWorkIDs == [localID])
        #expect(caps.deleteTitles == ["Posted"])
    }

    @Test func signedOutAO3OnlySelectionCannotDelete() {
        let remote = makeSelectWork(title: "Remote Only", postedID: 3, hasLocal: false)
        let caps = StudioSelectPolicy.evaluate(selected: [remote], isSignedIn: false)
        #expect(!caps.canEditTogether)
        #expect(!caps.canOrphan)
        #expect(!caps.canDelete)
        #expect(caps.deleteAO3WorkIDs.isEmpty)
        #expect(caps.deleteLocalWorkIDs.isEmpty)
        #expect(caps.deleteTitles.isEmpty)
    }

    @Test func signedOutMixedSelectionDeletesOnlyTheLocalCopy() throws {
        let onDevice = makeSelectWork(title: "On Device", postedID: 10, hasLocal: true)
        let remote = makeSelectWork(title: "AO3 Only", postedID: 11, hasLocal: false)
        let localID = try #require(onDevice.localWork?.id)

        let caps = StudioSelectPolicy.evaluate(selected: [onDevice, remote], isSignedIn: false)
        #expect(caps.canDelete)
        #expect(caps.deleteAO3WorkIDs.isEmpty)
        #expect(caps.deleteLocalWorkIDs == [localID])
        #expect(caps.deleteTitles == ["On Device"])
        let pending = StudioPendingDelete(
            ao3WorkIDs: caps.deleteAO3WorkIDs,
            localWorkIDs: caps.deleteLocalWorkIDs,
            titles: caps.deleteTitles,
            generation: 4
        )
        #expect(pending.titleText == "Move 1 work to Recently Deleted?")
        let message = pending.message(deviceName: "iPhone")
        #expect(message.contains("On Device"))
        #expect(!message.contains("AO3 Only"))
        #expect(message.contains("Recently Deleted"))
    }

    @Test func deleteIgnoresUnselectedWorksAndDuplicateAO3IDs() throws {
        let first = makeSelectWork(title: "First", postedID: 9, hasLocal: true)
        let second = makeSelectWork(title: "Second", postedID: 9, hasLocal: true)
        let unselected = makeSelectWork(title: "Leave Me", postedID: 8, hasLocal: true)
        let firstID = try #require(first.localWork?.id)
        let secondID = try #require(second.localWork?.id)
        let unselectedID = try #require(unselected.localWork?.id)

        let caps = StudioSelectPolicy.evaluate(selected: [first, second], isSignedIn: true)
        #expect(caps.deleteAO3WorkIDs == [9])
        #expect(caps.editTogetherWorkIDs == [9])
        #expect(caps.deleteLocalWorkIDs == [firstID, secondID])
        #expect(!caps.deleteLocalWorkIDs.contains(unselectedID))
        #expect(caps.deleteTitles == ["First", "Second"])
        #expect(first.id != second.id)
    }

    @Test func orphanDisablesAbove100PostedWorks() {
        let works = (1...101).map { makeSelectWork(title: "Work \($0)", postedID: $0) }
        let caps = StudioSelectPolicy.evaluate(selected: works, isSignedIn: true)
        #expect(caps.canEditTogether)
        #expect(!caps.canOrphan)
        #expect(caps.isOverOrphanCap)
    }

    @Test func exporterRendersCleanHTMLWithoutPrivateNotes() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let work = WritingWork(
            id: UUID(),
            title: "Salt & Light",
            ao3WorkID: nil,
            createdAt: now,
            updatedAt: now,
            updatedBy: "test-device",
            chapterOrder: []
        )
        let chapter = WritingChapter(
            id: UUID(),
            title: "Chapter One",
            summary: "",
            notesBefore: "",
            notesAfter: "",
            ao3ChapterID: nil,
            status: .local,
            wordCount: 3,
            bodySavedAt: now,
            updatedAt: now,
            updatedBy: "test-device"
        )
        let html = StudioWorkExporter.renderHTML(works: [
            .init(work: work, chapters: [WritingChapterDocument(chapter: chapter, bodyHTML: "<p>Hello world</p>")])
        ])
        #expect(html.contains("<title>Salt &amp; Light</title>"))
        #expect(html.contains("<h1>Salt &amp; Light</h1>"))
        #expect(html.contains("<h2>1. Chapter One</h2>"))
        #expect(html.contains("<p>Hello world</p>"))
        #expect(StudioWorkExporter.defaultFilename(for: [work]) == "Salt & Light.html")
    }
}

struct StudioAddChapterPlannerTests {
    @Test func postedWithoutLocalOpensAO3WhenSignedIn() {
        let item = makeSelectWork(title: "Posted", postedID: 4, hasLocal: false)
        let target = StudioAddChapterPlanner.target(
            work: item,
            isSignedIn: true,
            existingLocalWorkID: nil
        )
        #expect(target == .ao3NewChapter(workID: 4))
    }

    @Test func signedOutPostedCreatesALocalCopy() {
        let item = makeSelectWork(title: "Posted", postedID: 4, hasLocal: false)
        let target = StudioAddChapterPlanner.target(
            work: item,
            isSignedIn: false,
            existingLocalWorkID: nil
        )
        #expect(target == .createLocal(ao3WorkID: 4, title: "Posted"))
    }

    @Test func existingLocalLinkWinsOverANewFolder() {
        let existing = UUID()
        let item = makeSelectWork(title: "Draft", draftID: 4, hasLocal: false)
        let target = StudioAddChapterPlanner.target(
            work: item,
            isSignedIn: true,
            existingLocalWorkID: existing
        )
        #expect(target == .localChapter(workID: existing))
    }

    @Test func localOnTheItemWinsOverAnotherFolder() throws {
        let item = makeSelectWork(title: "Both", postedID: 4, hasLocal: true)
        let localID = try #require(item.localWork?.id)
        let target = StudioAddChapterPlanner.target(
            work: item,
            isSignedIn: true,
            existingLocalWorkID: UUID()
        )
        #expect(target == .localChapter(workID: localID))
    }

    @Test func performReusesTheNewestLocalWorkWithTheSameAO3ID() async throws {
        try await withTempStudioStore { store, clock, _ in
            _ = try await store.createWork(title: "Older", ao3WorkID: 42)
            clock.advance(days: 1)
            let newer = try await store.createWork(title: "Newer", ao3WorkID: 42)
            let item = makeSelectWork(title: "AO3 Draft", draftID: 42, hasLocal: false)
            let outcome = try await StudioAddChapterPlanner.perform(
                work: item,
                isSignedIn: true,
                store: store,
                ao3ChapterCount: nil
            )
            let openedID: UUID?
            if case let .openedLocal(workID, _, _) = outcome {
                openedID = workID
            } else {
                openedID = nil
            }
            let works = try await store.listWorks()
            let count = works.count
            #expect(openedID == newer.id)
            #expect(count == 2)
        }
    }

    @Test func performDoesNotCreateALocalWorkForASignedInPostedWork() async throws {
        try await withTempStudioStore { store, _, _ in
            let item = makeSelectWork(title: "Posted", postedID: 7, hasLocal: false)
            let outcome = try await StudioAddChapterPlanner.perform(
                work: item,
                isSignedIn: true,
                store: store,
                ao3ChapterCount: 3
            )
            let openedAO3: Int?
            if case let .openAO3(workID, _, _) = outcome {
                openedAO3 = workID
            } else {
                openedAO3 = nil
            }
            let works = try await store.listWorks()
            let count = works.count
            #expect(openedAO3 == 7)
            #expect(count == 0)
        }
    }
}
