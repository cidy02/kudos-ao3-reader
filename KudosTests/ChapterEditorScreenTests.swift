import Foundation
import Testing
@testable import Kudos

/// Unit tests for `ChapterEditorScreen` wiring, flag-off entry points, paste report
/// sequence tracking, AO3 notes counters, and device-local `WritingDocumentStore` glue.
/// Depends only on a plain test host: no network, no AO3, no WebView.
@MainActor
struct ChapterEditorScreenTests {
    // MARK: - ••• menu wiring with fakes (implemented shown, unimplemented hidden)

    @Test func draftAO3ChapterMoreMenuWiresVisibleActionsAndHidesUnimplementedItems() {
        var fired: [String] = []
        let capabilities = ChapterEditorMenuCapabilities(
            isPosted: false,
            hasUnpostedChanges: true,
            canPostOrUpdate: true,
            canSaveAsAO3Draft: true,
            canPreview: true,
            canFind: true,
            canFormat: true,
            canEditChapterMetadata: true,
            canOpenWorkDetails: true,
            canEditTags: true,
            canCopyAsAO3HTML: true,
            availableExportFormats: [],
            canDeleteChapter: true
        )
        let wiring = ChapterEditorMoreMenuWiring(
            capabilities: capabilities,
            handlers: makeRecordingHandlers { fired.append($0) }
        )

        let model = wiring.model(deviceName: "iPhone")
        let actions = wiring.actions()

        // Implemented items are present with the right draft titles.
        #expect(model.topRow.map(\.id) == [.postOrUpdate, .preview, .find])
        #expect(model.topRow.first?.title == "Post")
        #expect(model.ao3Items.map(\.id) == [.saveAsAO3Draft, .chapterMetadata, .workDetails, .editTags])
        #expect(model.exportFormats.isEmpty)
        #expect(model.exportItems.map(\.id) == [.copyAsAO3HTML])
        #expect(model.documentItems.map(\.id) == [.format])
        #expect(model.showsDeleteItem)
        #expect(!model.showsUnpostedDot)

        // Unimplemented items are hidden (never shown disabled).
        let visibleIDs = model.allVisibleActionIDs
        #expect(!visibleIDs.contains(.share))
        #expect(!visibleIDs.contains(.compareWithPosted))
        #expect(!visibleIDs.contains(.discardChanges))
        #expect(!visibleIDs.contains(.sendToBeta))
        #expect(!visibleIDs.contains(.print))
        #expect(!visibleIDs.contains(.versionHistory))
        #expect(!visibleIDs.contains(.writingTools))
        for format in EditorExportFormat.allCases {
            #expect(!visibleIDs.contains(.exportFormat(format)))
        }

        // Every visible action calls its matching fake handler.
        actions.dispatch(.postOrUpdate)
        actions.dispatch(.preview)
        actions.dispatch(.find)
        actions.dispatch(.saveAsAO3Draft)
        actions.dispatch(.chapterMetadata)
        actions.dispatch(.workDetails)
        actions.dispatch(.editTags)
        actions.dispatch(.copyAsAO3HTML)
        actions.dispatch(.format)
        actions.dispatch(.deleteChapter)

        // Hidden actions are inert even if dispatched directly.
        actions.dispatch(.share)
        actions.dispatch(.exportFormat(.epub))
        actions.dispatch(.sendToBeta)
        actions.dispatch(.print)
        actions.dispatch(.versionHistory)
        actions.dispatch(.writingTools)

        #expect(fired == [
            "postOrUpdate",
            "preview",
            "find",
            "saveAsAO3Draft",
            "chapterMetadata",
            "workDetails",
            "editTags",
            "copyAsAO3HTML",
            "format",
            "deleteChapter"
        ])
    }

    @Test func postedAO3ChapterMenuUsesUpdateTitleHidesDraftSaveAndShowsDot() {
        var fired: [String] = []
        let capabilities = ChapterEditorMenuCapabilities(
            isPosted: true,
            hasUnpostedChanges: true,
            canPostOrUpdate: true,
            canSaveAsAO3Draft: true, // Ignored because chapter is already posted.
            canPreview: true,
            canFind: false,
            canFormat: true,
            canEditChapterMetadata: true,
            canOpenWorkDetails: true,
            canEditTags: true,
            canCopyAsAO3HTML: true,
            availableExportFormats: [],
            canDeleteChapter: false
        )
        let wiring = ChapterEditorMoreMenuWiring(
            capabilities: capabilities,
            handlers: makeRecordingHandlers { fired.append($0) }
        )

        let model = wiring.model(deviceName: "Mac")
        let actions = wiring.actions()

        #expect(model.topRow.map(\.id) == [.postOrUpdate, .preview])
        #expect(model.topRow.first?.title == "Update on AO3")
        #expect(model.showsUnpostedDot)
        #expect(!model.allVisibleActionIDs.contains(.saveAsAO3Draft))
        #expect(!model.allVisibleActionIDs.contains(.find))
        #expect(!model.allVisibleActionIDs.contains(.compareWithPosted))
        #expect(!model.allVisibleActionIDs.contains(.discardChanges))
        #expect(!model.showsDeleteItem)
        #expect(!model.allVisibleActionIDs.contains(.deleteChapter))

        actions.dispatch(.postOrUpdate)
        actions.dispatch(.saveAsAO3Draft)
        actions.dispatch(.deleteChapter)
        #expect(fired == ["postOrUpdate"])
    }

    @Test func workEditChapter1AndLocalOnlyMenusHideUnavailableActions() {
        // WorkEditView Chapter 1 (draft work): no Edit Tags and no Delete Chapter.
        let workEditCaps = ChapterEditorMenuCapabilities(
            isPosted: false,
            hasUnpostedChanges: false,
            canPostOrUpdate: true,
            canSaveAsAO3Draft: true,
            canPreview: true,
            canFind: true,
            canFormat: true,
            canEditChapterMetadata: true,
            canOpenWorkDetails: true,
            canEditTags: false,
            canCopyAsAO3HTML: true,
            availableExportFormats: [],
            canDeleteChapter: false
        )
        let workEditModel = workEditCaps.menuModel()
        #expect(!workEditModel.allVisibleActionIDs.contains(.editTags))
        #expect(!workEditModel.allVisibleActionIDs.contains(.deleteChapter))
        #expect(workEditModel.allVisibleActionIDs.contains(.workDetails))
        #expect(workEditModel.allVisibleActionIDs.contains(.saveAsAO3Draft))

        // Local-only chapter (no AO3 account): all AO3 actions hidden.
        var fired: [String] = []
        let localCaps = ChapterEditorMenuCapabilities(
            isPosted: false,
            hasUnpostedChanges: false,
            canPostOrUpdate: false,
            canSaveAsAO3Draft: false,
            canPreview: false,
            canFind: true,
            canFormat: true,
            canEditChapterMetadata: true,
            canOpenWorkDetails: false,
            canEditTags: false,
            canCopyAsAO3HTML: true,
            availableExportFormats: [],
            canDeleteChapter: true
        )
        let localWiring = ChapterEditorMoreMenuWiring(
            capabilities: localCaps,
            handlers: makeRecordingHandlers { fired.append($0) }
        )
        let localModel = localWiring.model()
        let localActions = localWiring.actions()

        #expect(localModel.topRow.map(\.id) == [.find])
        #expect(localModel.ao3Items.map(\.id) == [.chapterMetadata])
        #expect(!localModel.allVisibleActionIDs.contains(.postOrUpdate))
        #expect(!localModel.allVisibleActionIDs.contains(.preview))
        #expect(!localModel.allVisibleActionIDs.contains(.saveAsAO3Draft))
        #expect(!localModel.allVisibleActionIDs.contains(.workDetails))
        #expect(!localModel.allVisibleActionIDs.contains(.editTags))
        #expect(localModel.showsDeleteItem)

        localActions.dispatch(.postOrUpdate)
        localActions.dispatch(.preview)
        localActions.dispatch(.workDetails)
        localActions.dispatch(.find)
        localActions.dispatch(.format)
        localActions.dispatch(.deleteChapter)
        #expect(fired == ["find", "format", "deleteChapter"])
    }

    @Test func exportAsSubmenuShowsOnlyFormatsWithAnAvailableExporter() {
        var fired: [String] = []
        let capabilities = ChapterEditorMenuCapabilities(
            availableExportFormats: [.html, .plainText]
        )
        let wiring = ChapterEditorMoreMenuWiring(
            capabilities: capabilities,
            handlers: makeRecordingHandlers { fired.append($0) }
        )
        let model = wiring.model()
        let actions = wiring.actions()

        #expect(model.exportFormats == [.html, .plainText])
        #expect(model.allVisibleActionIDs.contains(.exportFormat(.html)))
        #expect(model.allVisibleActionIDs.contains(.exportFormat(.plainText)))
        #expect(!model.allVisibleActionIDs.contains(.exportFormat(.pdf)))
        #expect(!model.allVisibleActionIDs.contains(.exportFormat(.epub)))
        #expect(!model.allVisibleActionIDs.contains(.exportFormat(.word)))
        #expect(!model.allVisibleActionIDs.contains(.exportFormat(.markdown)))

        actions.dispatch(.exportFormat(.html))
        actions.dispatch(.exportFormat(.pdf))
        #expect(fired == ["export:html"])
    }

    // MARK: - Flag-off entry point gating

    @Test func flagOffEntryPointsChooseLegacyEditorForAddChapterAndWorkEdit() throws {
        let suiteName = "ChapterEditorScreenTests.flag.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Feature flag defaults to off.
        #expect(!RichEditorFeatureFlag.isEnabled(in: defaults))

        let flagOff = RichEditorFeatureFlag.isEnabled(in: defaults)
        #expect(ChapterEditorEntryPolicy.addChapterDestination(flagEnabled: flagOff) == .legacyFieldEditor)
        #expect(!AddChapterView.usesRichChapterEditor(flagEnabled: flagOff))
        #expect(
            ChapterEditorEntryPolicy.workEditChapter1Destination(flagEnabled: flagOff, contentServed: true)
                == .legacyFieldEditor
        )
        #expect(!WorkEditView.usesRichChapter1Editor(flagEnabled: flagOff, contentServed: true))

        // Enabling the flag opens ChapterEditorScreen from both entry points (when content is served).
        RichEditorFeatureFlag.setEnabled(true, in: defaults)
        let flagOn = RichEditorFeatureFlag.isEnabled(in: defaults)
        #expect(flagOn)
        #expect(ChapterEditorEntryPolicy.addChapterDestination(flagEnabled: flagOn) == .richChapterEditor)
        #expect(AddChapterView.usesRichChapterEditor(flagEnabled: flagOn))
        #expect(
            ChapterEditorEntryPolicy.workEditChapter1Destination(flagEnabled: flagOn, contentServed: true)
                == .richChapterEditor
        )
        #expect(WorkEditView.usesRichChapter1Editor(flagEnabled: flagOn, contentServed: true))

        // Multi-chapter drafts whose chapter 1 content AO3 didn't serve never open the chapter editor.
        #expect(!WorkEditView.usesRichChapter1Editor(flagEnabled: flagOn, contentServed: false))

        // Turning the flag back off restores the legacy editor cleanly.
        RichEditorFeatureFlag.setEnabled(false, in: defaults)
        #expect(!AddChapterView.usesRichChapterEditor(flagEnabled: RichEditorFeatureFlag.isEnabled(in: defaults)))
        #expect(
            !WorkEditView.usesRichChapter1Editor(
                flagEnabled: RichEditorFeatureFlag.isEnabled(in: defaults),
                contentServed: true
            )
        )
    }

    // MARK: - Paste report sequence tracking & DraftSession undo

    @Test func pasteReportAppearsForNewSequenceAndStaysHiddenForSameSequence() throws {
        var tracker = ChapterEditorPasteTracker()
        #expect(tracker.activeReport == nil)
        let received1 = tracker.receive(nil)
        #expect(!received1)

        let firstEvent = RichEditorPasteEvent(
            loss: RichEditorLossReport(
                dropped: RichEditorLossReport.Dropped(elements: ["script": 1], attributes: ["style": 3]),
                unwrapped: ["span": 2],
                normalized: 4,
                preserved: 1
            ),
            words: 420,
            kind: "html"
        )
        let firstPaste = DraftPasteReport(sequence: 1, event: firstEvent)

        // Sequence 1 appears and maps all loss fields without inventing a source app name.
        let received2 = tracker.receive(firstPaste)
        #expect(received2)
        let report = try #require(tracker.activeReport)
        #expect(tracker.activeSequence == 1)
        #expect(report.wordCount == 420)
        #expect(report.sourceName == nil)
        #expect(report.headline == "Pasted 420 words")
        #expect(report.removed.map(\.label) == ["<script> tag", "style attributes"])
        #expect(report.removed.map(\.count) == [1, 3])
        #expect(report.normalized.map(\.label) == ["<span> wrappers", "markup details"])
        #expect(report.normalized.map(\.count) == [2, 4])
        #expect(report.kept.map(\.label) == ["preserved HTML block"])

        // Re-delivering sequence 1 while visible is a no-op.
        let received3 = tracker.receive(firstPaste)
        #expect(!received3)

        // Dismissing hides the card; re-delivering sequence 1 does NOT re-show it.
        tracker.dismiss()
        #expect(tracker.activeReport == nil)
        let received4 = tracker.receive(firstPaste)
        #expect(!received4)
        #expect(tracker.activeReport == nil)

        // A new paste with sequence 2 appears immediately.
        let secondPaste = DraftPasteReport(
            sequence: 2,
            event: RichEditorPasteEvent(loss: .empty, words: 12, kind: "text")
        )
        let received5 = tracker.receive(secondPaste)
        #expect(received5)
        #expect(tracker.activeSequence == 2)
        #expect(tracker.activeReport?.headline == "Pasted 12 words")
        #expect(tracker.activeReport?.summaryText == "Ready for AO3.")
    }

    @Test func draftSessionPasteSequenceDrivesTrackerAndUndoPasteDispatchesUndo() async {
        let source = FakeSourceEditor(text: "<p>Hello</p>")
        let transport = FakeRichTransport()
        let session = DraftSession(
            initialText: "<p>Hello</p>",
            fieldVariant: .content,
            source: source,
            clock: TestWritingClock(),
            richTransport: transport
        )
        let outcome = await session.switchToRich()
        #expect(outcome == .switched)

        var tracker = ChapterEditorPasteTracker()
        transport.emit(.paste(RichEditorPasteEvent(
            loss: RichEditorLossReport(
                dropped: RichEditorLossReport.Dropped(attributes: ["style": 2])
            ),
            words: 85,
            kind: "html"
        )))
        #expect(session.lastPaste?.sequence == 1)
        let received6 = tracker.receive(session.lastPaste)
        #expect(received6)
        #expect(tracker.activeReport?.wordCount == 85)

        // Undo Paste calls `session.apply(.undo)` and dismisses the card.
        session.apply(.undo)
        tracker.dismiss()
        await Task.yield()
        await Task.yield()

        #expect(transport.commandCalls.contains { $0.name == "undo" })
        let received7 = tracker.receive(session.lastPaste)
        #expect(!received7)

        // A subsequent paste bumps `lastPaste.sequence` to 2 and shows a fresh card.
        transport.emit(.paste(RichEditorPasteEvent(loss: .empty, words: 10, kind: "text")))
        #expect(session.lastPaste?.sequence == 2)
        let received8 = tracker.receive(session.lastPaste)
        #expect(received8)
        #expect(tracker.activeReport?.wordCount == 10)

        session.teardown()
    }

    // MARK: - Notes counters at AO3's limits

    @Test func chapterNotesCountersEnforceAO3LimitsIncludingUnicodeScalars() {
        // Summary: AO3 SUMMARY_MAX = 1,250 (warning starts at 1,125 = 90%).
        let summaryBelowWarn = CharacterLimitStatus.evaluate(
            text: String(repeating: "a", count: 1_124),
            field: .summary
        )
        #expect(summaryBelowWarn.severity == .normal)
        #expect(summaryBelowWarn.counterText == "1,124 / 1,250")
        #expect(summaryBelowWarn.overLimitMessage == nil)

        let summaryAtWarn = CharacterLimitStatus.evaluate(
            text: String(repeating: "a", count: 1_125),
            field: .summary
        )
        #expect(summaryAtWarn.severity == .warning)

        let summaryAtExactLimit = CharacterLimitStatus.evaluate(
            text: String(repeating: "a", count: 1_250),
            field: .summary
        )
        #expect(summaryAtExactLimit.severity == .warning)
        #expect(summaryAtExactLimit.remaining == 0)
        #expect(summaryAtExactLimit.overLimitMessage == nil)

        let summaryOverLimit = CharacterLimitStatus.evaluate(
            text: String(repeating: "a", count: 1_251),
            field: .summary
        )
        #expect(summaryOverLimit.severity == .exceeded)
        #expect(summaryOverLimit.remaining == -1)
        #expect(summaryOverLimit.overLimitMessage == "AO3 won't accept more than 1,250 characters")

        // Beginning & End Notes: AO3 NOTES_MAX = 5,000 (warning starts at 4,500 = 90%).
        #expect(ChapterNoteField.notesBefore.limit == .notes)
        #expect(ChapterNoteField.notesAfter.limit == .notes)
        #expect(
            CharacterLimitStatus.evaluate(text: String(repeating: "n", count: 4_499), field: .notes).severity
                == .normal
        )
        #expect(
            CharacterLimitStatus.evaluate(text: String(repeating: "n", count: 4_500), field: .notes).severity
                == .warning
        )
        #expect(
            CharacterLimitStatus.evaluate(text: String(repeating: "n", count: 5_000), field: .notes).severity
                == .warning
        )
        let notesOverLimit = CharacterLimitStatus.evaluate(
            text: String(repeating: "n", count: 5_001),
            field: .notes
        )
        #expect(notesOverLimit.severity == .exceeded)
        #expect(notesOverLimit.counterText == "5,001 / 5,000")
        #expect(notesOverLimit.overLimitMessage == "AO3 won't accept more than 5,000 characters")

        // Multi-scalar emoji counts by Unicode scalars to match AO3's Ruby `String#length`.
        // "👩‍💻" is 3 Unicode scalars (U+1F469, U+200D, U+1F4BB).
        let emojiStatus = CharacterLimitStatus.evaluate(text: "👩‍💻", field: .summary)
        #expect(emojiStatus.count == 3)
    }

    // MARK: - WritingDocumentStore device-local copy & account-free flow

    @Test func documentBridgeMirrorsAO3ChapterAndSupportsAccountFreeManuscripts() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(
            "chapter-editor-bridge-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WritingDocumentStore(root: root, deviceID: "test-device")

        // 1. Mirror an AO3 chapter onto this device and verify reopening updates the same copy.
        let ao3Bridge = ChapterEditorDocumentBridge(store: store)
        let initialAO3 = ChapterEditorChapterPayload(
            workTitle: "What the Tide Keeps",
            chapterTitle: "Slack Water",
            summary: "A brief summary.",
            notesBefore: "Opening note.",
            notesAfter: "Closing note.",
            bodyHTML: "<p>The tide had turned.</p>",
            ao3ChapterID: 901,
            status: .ao3Draft
        )
        let opened = try #require(
            await ao3Bridge.open(
                target: .ao3Mirror(ao3WorkID: 42, ao3ChapterID: 901, isChapterOne: false),
                initialPayload: initialAO3
            )
        )
        #expect(opened.work.ao3WorkID == 42)
        #expect(opened.activeChapter.ao3ChapterID == 901)
        #expect(opened.activeBodyHTML == "<p>The tide had turned.</p>")
        #expect(ao3Bridge.syncState == .localOnly)

        var editedAO3 = initialAO3
        editedAO3.bodyHTML = "<p>The tide had turned and the boat sat still.</p>"
        await ao3Bridge.save(editedAO3, kind: .destructive)

        // Destructive save (e.g. Undo Paste) keeps the previous body as a version snapshot.
        let versions = try await store.listVersions(
            workID: opened.work.id,
            chapterID: opened.activeChapter.id
        )
        #expect(versions.count == 1)
        #expect(versions.first?.cause == .destructive)

        // Reopening the same AO3 work/chapter reuses the existing local folder without duplicating.
        let secondBridge = ChapterEditorDocumentBridge(store: store)
        let reopened = try #require(
            await secondBridge.open(
                target: .ao3Mirror(ao3WorkID: 42, ao3ChapterID: 901, isChapterOne: false),
                initialPayload: editedAO3
            )
        )
        #expect(reopened.work.id == opened.work.id)
        #expect(reopened.activeChapter.id == opened.activeChapter.id)
        #expect(try await store.listChapters(workID: opened.work.id).count == 1)

        // 2. Account-free local work: create, add chapter, story notes, and soft-delete a chapter.
        let localBridge = ChapterEditorDocumentBridge(store: store)
        let localPayload = ChapterEditorChapterPayload(
            workTitle: "Harbour Notes",
            chapterTitle: "One",
            summary: "",
            notesBefore: "",
            notesAfter: "",
            bodyHTML: "<p>First chapter.</p>",
            ao3ChapterID: nil,
            status: .local
        )
        let localOpened = try #require(
            await localBridge.open(target: .local(workID: nil, chapterID: nil), initialPayload: localPayload)
        )
        #expect(localOpened.work.ao3WorkID == nil)

        await localBridge.addStoryNote(
            kind: .character,
            name: "Ines",
            detail: "Hasn't swum since the accident",
            pinned: true
        )
        #expect(localBridge.storyNotes.count == 1)
        #expect(localBridge.storyNotes.first?.pinned == true)

        let secondChapter = try #require(
            await localBridge.addChapter(savingCurrent: localPayload, title: "Two")
        )
        #expect(localBridge.chapters.count == 2)
        #expect(localBridge.chapterID == secondChapter.chapter.id)

        let afterDelete = try #require(await localBridge.deleteActiveChapter())
        #expect(localBridge.chapters.count == 1)
        #expect(afterDelete.chapter.id == localOpened.activeChapter.id)
        #expect(try await store.listRecentlyDeleted().count == 1)
    }

    // MARK: - Helpers

    private func makeRecordingHandlers(
        record: @escaping (String) -> Void
    ) -> ChapterEditorMoreMenuHandlers {
        ChapterEditorMoreMenuHandlers(
            postOrUpdate: { record("postOrUpdate") },
            preview: { record("preview") },
            find: { record("find") },
            saveAsAO3Draft: { record("saveAsAO3Draft") },
            chapterMetadata: { record("chapterMetadata") },
            workDetails: { record("workDetails") },
            editTags: { record("editTags") },
            exportFormat: { format in record("export:\(format.rawValue)") },
            copyAsAO3HTML: { record("copyAsAO3HTML") },
            format: { record("format") },
            deleteChapter: { record("deleteChapter") }
        )
    }
}
