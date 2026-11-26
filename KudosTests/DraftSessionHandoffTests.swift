import Foundation
import Testing
@testable import Kudos

private func makeDraftRecoveryStore(
    prefix: String = "draft-handoff"
) -> (WritingTextRecovery, URL, WritingRecoveryWriter) {
    let dir = URL.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    let store = WritingTextRecovery(directory: dir)
    let key = store.fileURL(account: "writer", target: "work:99", field: "content")
    let sessionURL = key.deletingPathExtension()
        .appendingPathExtension(UUID().uuidString)
        .appendingPathExtension("json")
    let writer = WritingRecoveryWriter(store: store, url: sessionURL, original: "initial")
    return (store, key, writer)
}

@MainActor
struct DraftSessionHandoffTests {
    @Test func sourceToRichColdPathFreezesCheckpointsLoadsVerifiesActivatesAndFocuses() async throws {
        let (store, key, writer) = makeDraftRecoveryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let source = FakeSourceEditor(text: "<p>Initial</p>")
        source.caretOffsetUTF16 = 6
        let transport = FakeRichTransport()
        var checkpointedToForm: [String] = []

        let session = DraftSession(
            initialText: "<p>Initial</p>",
            fieldVariant: .content,
            source: source,
            recoveryWriter: writer,
            clock: TestWritingClock(),
            richTransport: transport,
            onCheckpointText: { checkpointedToForm.append($0) }
        )

        source.simulateUserEdit("<p>Edited in HTML</p>")
        let outcome = await session.switchToRich()

        #expect(outcome == .switched)
        #expect(session.state == .richOwned)
        #expect(session.owner == .rich)
        #expect(source.isFrozen)
        #expect(source.commitCompositionCount == 1)
        #expect(checkpointedToForm == ["<p>Edited in HTML</p>"])
        #expect(try store.copies(for: key).first?.entry.text == "<p>Edited in HTML</p>")
        #expect(transport.recordedCalls == [
            "configure",
            "load",
            "verifySwitch:sourceToRich",
            "activate",
        ])
        #expect(transport.activateCalls.first == RichEditorActivateArgs(caret: 6, focus: true))
        #expect(transport.focusCount == 1)
        #expect(source.text == "<p>Edited in HTML</p>")
    }

    @Test func sourceToRichShowsSwitchTransitionAfter100msOnSlowColdLoad() async {
        let clock = TestWritingClock()
        let source = FakeSourceEditor(text: "<p>Chapter</p>")
        let transport = FakeRichTransport()
        var loadContinuation: CheckedContinuation<RichEditorLoadResult, Error>?
        transport.loadHandler = { _ in
            try await withCheckedThrowingContinuation { continuation in
                loadContinuation = continuation
            }
        }
        let session = DraftSession(
            initialText: "<p>Chapter</p>",
            fieldVariant: .content,
            source: source,
            clock: clock,
            richTransport: transport
        )

        let switchTask = Task { await session.switchToRich() }
        await clock.advance(by: .milliseconds(99))
        #expect(!session.isShowingSwitchTransition)
        await clock.advance(by: .milliseconds(1))
        #expect(session.isShowingSwitchTransition)

        loadContinuation?.resume(returning: RichEditorLoadResult(revision: 0, loss: .empty, timing: .zero))
        let outcome = await switchTask.value
        #expect(outcome == .switched)
        #expect(!session.isShowingSwitchTransition)
    }

    @Test func droppedItemsRequireConfirmationAndCommitWhenConfirmed() async {
        let source = FakeSourceEditor(text: "<font>hi</font>")
        let transport = FakeRichTransport()
        let report = RichEditorLossReport(
            dropped: RichEditorLossReport.Dropped(elements: ["font": 3], attributes: ["style": 42]),
            unwrapped: ["span": 2],
            normalized: 4,
            preserved: 1
        )
        transport.loadHandler = { args in
            RichEditorLoadResult(revision: args.revision, loss: report, timing: .zero)
        }
        let session = DraftSession(
            initialText: "<font>hi</font>",
            fieldVariant: .content,
            source: source,
            clock: TestWritingClock(),
            richTransport: transport
        )

        let first = await session.switchToRich()
        #expect(first == .awaitingLossConfirmation(report))
        #expect(session.state == .handingOffToRich)
        #expect(session.owner == .source)
        #expect(source.isFrozen)
        #expect(
            session.pendingLossConfirmation?.message
                == "AO3 would remove these when you save: <font> ×3, style ×42"
        )
        #expect(transport.activateCalls.isEmpty)

        let confirmed = await session.confirmLossAndCompleteSwitchToRich()
        #expect(confirmed == .switched)
        #expect(session.state == .richOwned)
        #expect(session.pendingLossConfirmation == nil)
        #expect(session.lastSwitchChanges == report)
        #expect(transport.activateCalls.count == 1)
    }

    @Test func cancellingLossConfirmationUnfreezesSourceAndCountsNoFailure() async {
        let source = FakeSourceEditor(text: "<font>hi</font>")
        let transport = FakeRichTransport()
        let report = RichEditorLossReport(dropped: RichEditorLossReport.Dropped(elements: ["font": 1]))
        transport.loadHandler = { args in
            RichEditorLoadResult(revision: args.revision, loss: report, timing: .zero)
        }
        let session = DraftSession(
            initialText: "<font>hi</font>",
            fieldVariant: .content,
            source: source,
            clock: TestWritingClock(),
            richTransport: transport
        )

        let outcome = await session.switchToRich()
        #expect(outcome == .awaitingLossConfirmation(report))

        session.cancelPendingRichSwitch()
        #expect(session.state == .sourceOwned)
        #expect(session.owner == .source)
        #expect(!source.isFrozen)
        #expect(session.pendingLossConfirmation == nil)
        #expect(session.failureCount == 0)
        #expect(session.isRichAvailable)
        #expect(source.text == "<font>hi</font>")
    }

    /// R1 (§7.1, §7.4 step 3): switching HTML → Rich → HTML with no edits restores
    /// the original source text byte for byte, never using normalized serialization,
    /// and leaves the rich document warm for a switch straight back.
    @Test func noOpRoundTripRestoresOriginalSourceBytesVerbatimAndKeepsWarmPreload() async {
        let rawSource = "<B>Hello</B>\n\n<span >world</span>"
        let source = FakeSourceEditor(text: rawSource)
        let transport = FakeRichTransport()
        transport.loadHandler = { args in
            // Rich mode normalizes internally; if R1 is broken this string would leak back.
            transport.storedHTML = "<p><b>Hello</b></p>\n<p>world</p>"
            transport.storedRevision = args.revision
            return RichEditorLoadResult(revision: args.revision, loss: .empty, timing: .zero)
        }
        transport.storedCaretOffset = 7
        transport.storedWords = 2

        let session = DraftSession(
            initialText: rawSource,
            fieldVariant: .content,
            source: source,
            clock: TestWritingClock(),
            richTransport: transport
        )

        #expect(await session.switchToRich() == .switched)
        #expect(session.state == .richOwned)

        // Return to HTML with NO edit in Rich Text.
        #expect(await session.switchToSource() == .switched)
        #expect(session.state == .sourceOwned)
        #expect(!source.isFrozen)
        #expect(source.text == rawSource)
        #expect(session.text == rawSource)
        #expect(source.replaceForHandoffCalls.isEmpty)
        #expect(source.setCaretCalls == [7])
        #expect(source.focusCount == 1)
        // Rich → HTML switch check is skipped on an unedited round trip.
        #expect(transport.verifySwitchCalls.map(\.direction) == [.sourceToRich])

        // Switching straight back to Rich Text takes the warm path (no cold `load`).
        let loadsBefore = transport.loadCalls.count
        #expect(await session.switchToRich() == .switched)
        #expect(transport.loadCalls.count == loadsBefore)
        #expect(transport.verifySwitchCalls.count == 1)
    }

    @Test func editedRichToSourceVerifiesCheckpointsReplacesBufferAndClearsUndoHistory() async throws {
        let (store, key, writer) = makeDraftRecoveryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let source = FakeSourceEditor(text: "<p>Before</p>")
        let transport = FakeRichTransport()
        let session = DraftSession(
            initialText: "<p>Before</p>",
            fieldVariant: .content,
            source: source,
            recoveryWriter: writer,
            clock: TestWritingClock(),
            richTransport: transport
        )

        #expect(await session.switchToRich() == .switched)
        transport.storedRevision = 1
        transport.storedHTML = "<p>After rich edit</p>"
        transport.storedCaretOffset = 11
        transport.storedWords = 3
        transport.emit(.edited(revision: 1))

        #expect(await session.switchToSource() == .switched)
        #expect(session.state == .sourceOwned)
        #expect(session.text == "<p>After rich edit</p>")
        #expect(session.wordCount == 3)
        #expect(source.text == "<p>After rich edit</p>")
        #expect(source.caretOffsetUTF16 == 11)
        #expect(source.clearedUndoHistoryCount == 1)
        #expect(!source.isFrozen)
        #expect(source.focusCount == 1)
        #expect(transport.verifySwitchCalls.last?.direction == .richToSource)
        #expect(try store.copies(for: key).first?.entry.text == "<p>After rich edit</p>")
    }

    /// U1–U3 (§7.9): undo/redo route to native undo in HTML mode and to
    /// `prosemirror-history` (`command("undo")`/`command("redo")`) in Rich mode.
    @Test func undoAndRedoRouteToOwningModeOnly() async {
        let source = FakeSourceEditor(text: "<p>Start</p>")
        let transport = FakeRichTransport()
        let session = DraftSession(
            initialText: "<p>Start</p>",
            fieldVariant: .content,
            source: source,
            clock: TestWritingClock(),
            richTransport: transport
        )

        session.undo()
        session.redo()
        #expect(source.undoCount == 1)
        #expect(source.redoCount == 1)
        #expect(transport.commandCalls.isEmpty)

        #expect(await session.switchToRich() == .switched)
        transport.emit(.toolbarState(RichEditorToolbarState(
            marks: ["strong"], block: "paragraph", align: nil, dir: nil, canUndo: true, canRedo: true
        )))
        #expect(session.canUndo)
        #expect(session.canRedo)

        session.undo()
        session.redo()
        for _ in 0..<4 { await Task.yield() }
        #expect(source.undoCount == 1)
        #expect(source.redoCount == 1)
        #expect(transport.commandCalls.map(\.name) == ["undo", "redo"])
    }
}

@MainActor
struct DraftSessionFailureAndSwitchCheckTests {
    @Test func loadTimeoutCountsFailureAndTwoFailuresDisableRichUntilReopen() async {
        let source = FakeSourceEditor(text: "<p>Text</p>")
        let transport = FakeRichTransport()
        transport.loadHandler = { _ in
            throw RichEditorBridgeError.timeout(call: "load", duration: .seconds(5))
        }
        let session = DraftSession(
            initialText: "<p>Text</p>",
            fieldVariant: .content,
            source: source,
            clock: TestWritingClock(),
            richTransport: transport
        )

        #expect(await session.switchToRich() == .failed)
        #expect(session.state == .sourceOwned)
        #expect(!source.isFrozen)
        #expect(session.failureCount == 1)
        #expect(session.isRichAvailable)
        #expect(session.noticeMessage == DraftSession.richOpenFailedMessage)

        #expect(await session.switchToRich() == .failed)
        #expect(session.failureCount == 2)
        #expect(session.isRichPermanentlyDisabled)
        #expect(!session.isRichAvailable)

        let loadsAfterSecond = transport.loadCalls.count
        #expect(await session.switchToRich() == .unavailable)
        #expect(transport.loadCalls.count == loadsAfterSecond)
    }

    @Test func configureVersionMismatchDisablesRichForSessionAndKeepsHTMLWorking() async {
        let source = FakeSourceEditor(text: "<p>Safe</p>")
        let transport = FakeRichTransport()
        transport.configureHandler = { _ in
            RichEditorConfigureResult(bridgeVersion: 99, schemaVersion: 1, bundleVersion: "9.9.9")
        }
        let session = DraftSession(
            initialText: "<p>Safe</p>",
            fieldVariant: .content,
            source: source,
            clock: TestWritingClock(),
            richTransport: transport
        )

        #expect(await session.switchToRich() == .failed)
        #expect(session.state == .sourceOwned)
        #expect(!source.isFrozen)
        #expect(session.isRichPermanentlyDisabled)
        #expect(!session.isRichAvailable)

        source.simulateUserEdit("<p>Still editable</p>")
        #expect(source.text == "<p>Still editable</p>")
        #expect(session.revision == 1)
    }

    @Test func processDeathWhileRichOwnedRestoresCheckpointWarnsAndEnforces60sCooldown() async {
        let clock = TestWritingClock()
        let source = FakeSourceEditor(text: "<p>Start</p>")
        let transport = FakeRichTransport()
        let session = DraftSession(
            initialText: "<p>Start</p>",
            fieldVariant: .content,
            source: source,
            clock: clock,
            richTransport: transport
        )

        #expect(await session.switchToRich() == .switched)

        // Checkpoint revision 1, then leave revision 2 uncheckpointed.
        transport.storedRevision = 1
        transport.storedHTML = "<p>Checkpointed</p>"
        transport.storedWords = 1
        transport.emit(.edited(revision: 1))
        await session.checkpointNow(commitComposition: false)
        #expect(session.text == "<p>Checkpointed</p>")

        transport.storedRevision = 2
        transport.storedHTML = "<p>Lost seconds</p>"
        transport.emit(.edited(revision: 2))

        transport.simulateProcessDeath()

        #expect(session.state == .sourceOwned)
        #expect(session.owner == .source)
        #expect(!source.isFrozen)
        #expect(source.text == "<p>Checkpointed</p>")
        #expect(session.text == "<p>Checkpointed</p>")
        #expect(session.noticeMessage == DraftSession.processDeathLossWarning)
        #expect(transport.resetCount == 1)
        #expect(!session.isRichAvailable)

        // Still locked out at 59 s.
        await clock.advance(by: .seconds(59))
        #expect(!session.isRichAvailable)
        #expect(await session.switchToRich() == .unavailable)

        // Re-enabled at 60 s and re-configured on demand.
        await clock.advance(by: .seconds(1))
        #expect(session.isRichAvailable)
        #expect(await session.switchToRich() == .switched)
        #expect(transport.configureCalls.count == 2)
    }

    @Test func processDeathWhileRichOwnedWithoutUncheckpointedEditsSkipsLossWarning() async {
        let source = FakeSourceEditor(text: "<p>Clean</p>")
        let transport = FakeRichTransport()
        let session = DraftSession(
            initialText: "<p>Clean</p>",
            fieldVariant: .content,
            source: source,
            clock: TestWritingClock(),
            richTransport: transport
        )

        #expect(await session.switchToRich() == .switched)
        transport.simulateProcessDeath()

        #expect(session.state == .sourceOwned)
        #expect(session.noticeMessage == DraftSession.processDeathCleanFallbackMessage)
    }

    @Test func processDeathDuringHandoffToRichAbortsAndUnfreezesSource() async {
        let source = FakeSourceEditor(text: "<p>Chapter</p>")
        let transport = FakeRichTransport()
        var loadContinuation: CheckedContinuation<RichEditorLoadResult, Error>?
        transport.loadHandler = { _ in
            try await withCheckedThrowingContinuation { continuation in
                loadContinuation = continuation
            }
        }
        let session = DraftSession(
            initialText: "<p>Chapter</p>",
            fieldVariant: .content,
            source: source,
            clock: TestWritingClock(),
            richTransport: transport
        )

        let task = Task { await session.switchToRich() }
        for _ in 0..<4 { await Task.yield() }
        #expect(session.state == .handingOffToRich)
        #expect(source.isFrozen)

        transport.simulateProcessDeath()
        loadContinuation?.resume(throwing: RichEditorBridgeError.processTerminated)

        #expect(await task.value == .aborted)
        #expect(session.state == .sourceOwned)
        #expect(!source.isFrozen)
        #expect(session.pendingLossConfirmation == nil)
    }

    @Test func processDeathDuringHandoffToSourceRestoresCheckpointAndStartsCooldown() async {
        let source = FakeSourceEditor(text: "<p>Base</p>")
        let transport = FakeRichTransport()
        let session = DraftSession(
            initialText: "<p>Base</p>",
            fieldVariant: .content,
            source: source,
            clock: TestWritingClock(),
            richTransport: transport
        )

        #expect(await session.switchToRich() == .switched)
        transport.storedRevision = 1
        transport.storedHTML = "<p>Uncheckpointed</p>"
        transport.emit(.edited(revision: 1))
        transport.freezeHandler = {
            throw RichEditorBridgeError.processTerminated
        }

        let outcome = await session.switchToSource()
        #expect(outcome == .aborted)
        #expect(session.state == .sourceOwned)
        #expect(source.text == "<p>Base</p>")
        #expect(!source.isFrozen)
        #expect(!session.isRichAvailable)
        #expect(session.noticeMessage == DraftSession.processDeathLossWarning)
    }

    /// §7.11 switch check failure leaving Rich Text: nothing commits, Rich keeps
    /// ownership, both texts go to recovery copies, failure counts toward the
    /// two-failure rule, and the exact §7.11 message is shown.
    @Test func switchCheckFailureLeavingRichKeepsOwnershipSavesBothRecoveryCopiesAndShowsMessage() async throws {
        let (store, key, writer) = makeDraftRecoveryStore(prefix: "draft-mismatch-rich")
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let source = FakeSourceEditor(text: "<p>Original</p>")
        let transport = FakeRichTransport()
        let session = DraftSession(
            initialText: "<p>Original</p>",
            fieldVariant: .content,
            source: source,
            recoveryWriter: writer,
            clock: TestWritingClock(),
            richTransport: transport
        )

        #expect(await session.switchToRich() == .switched)

        transport.storedRevision = 1
        transport.storedHTML = "<p>Rich version</p>"
        transport.emit(.edited(revision: 1))
        transport.verifySwitchHandler = { args in
            #expect(args.direction == .richToSource)
            return RichEditorSwitchCheckResult(
                ok: false,
                candidateHtml: "<p>Round-tripped mismatch</p>",
                reason: "node-mismatch"
            )
        }

        let outcome = await session.switchToSource()
        #expect(outcome == .switchCheckFailed)
        #expect(session.state == .richOwned)
        #expect(session.owner == .rich)
        #expect(source.text == "<p>Original</p>")
        #expect(source.replaceForHandoffCalls.isEmpty)
        #expect(session.failureCount == 1)
        #expect(session.noticeMessage == DraftSession.switchCheckStayedInRichMessage)

        let urls = try #require(session.lastMismatchRecoveryURLs)
        #expect(try store.load(from: urls.leaving)?.text == "<p>Rich version</p>")
        #expect(try store.load(from: urls.candidate)?.text == "<p>Round-tripped mismatch</p>")
        let allTexts = Set(try store.copies(for: key).map(\.entry.text))
        #expect(allTexts.isSuperset(of: ["<p>Rich version</p>", "<p>Round-tripped mismatch</p>"]))
    }

    /// §7.11 switch check failure leaving HTML: nothing commits, HTML keeps
    /// ownership and is unfrozen, both texts are saved as recovery copies,
    /// failure counts toward the two-failure rule, and the exact §7.11 message is shown.
    @Test func switchCheckFailureLeavingHTMLKeepsOwnershipSavesBothRecoveryCopiesAndShowsMessage() async throws {
        let (store, key, writer) = makeDraftRecoveryStore(prefix: "draft-mismatch-html")
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let source = FakeSourceEditor(text: "<p>Before</p>")
        let transport = FakeRichTransport()
        transport.verifySwitchHandler = { args in
            #expect(args.direction == .sourceToRich)
            return RichEditorSwitchCheckResult(
                ok: false,
                candidateHtml: "<p>Changed by parse</p>",
                reason: "unexpected-diff"
            )
        }
        let session = DraftSession(
            initialText: "<p>Before</p>",
            fieldVariant: .content,
            source: source,
            recoveryWriter: writer,
            clock: TestWritingClock(),
            richTransport: transport
        )

        source.simulateUserEdit("<p>Edited HTML</p>")
        let outcome = await session.switchToRich()
        #expect(outcome == .switchCheckFailed)
        #expect(session.state == .sourceOwned)
        #expect(session.owner == .source)
        #expect(!source.isFrozen)
        #expect(session.failureCount == 1)
        #expect(session.noticeMessage == DraftSession.switchCheckStayedInHTMLMessage)

        let urls = try #require(session.lastMismatchRecoveryURLs)
        #expect(try store.load(from: urls.leaving)?.text == "<p>Edited HTML</p>")
        #expect(try store.load(from: urls.candidate)?.text == "<p>Changed by parse</p>")
        let allTexts = Set(try store.copies(for: key).map(\.entry.text))
        #expect(allTexts.isSuperset(of: ["<p>Edited HTML</p>", "<p>Changed by parse</p>"]))
    }
}
