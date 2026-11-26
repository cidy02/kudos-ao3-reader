import Foundation
import Testing
@testable import Kudos

/// `DraftSession` checkpoint scheduling and off-main-thread recovery writes
/// driven deterministically by `TestWritingClock` (§8.1, §8.2, §7.6).
@MainActor
struct DraftSessionCheckpointTests {
    private func makeRecoveryStore() -> (WritingTextRecovery, URL, WritingRecoveryWriter) {
        let dir = URL.temporaryDirectory
            .appendingPathComponent("draft-checkpoint-\(UUID().uuidString)", isDirectory: true)
        let store = WritingTextRecovery(directory: dir)
        let key = store.fileURL(account: "writer", target: "work:42", field: "content")
        let sessionURL = key.deletingPathExtension()
            .appendingPathExtension(UUID().uuidString)
            .appendingPathExtension("json")
        let writer = WritingRecoveryWriter(store: store, url: sessionURL, original: "start")
        return (store, key, writer)
    }

    @Test func sourceIdleCheckpointFiresAt1500msWithoutCommittingComposition() async throws {
        let (store, key, writer) = makeRecoveryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let clock = TestWritingClock()
        let source = FakeSourceEditor(text: "start")
        var formValues: [String] = []

        let session = DraftSession(
            initialText: "start",
            fieldVariant: .content,
            source: source,
            recoveryWriter: writer,
            clock: clock,
            onCheckpointText: { formValues.append($0) }
        )

        source.simulateUserEdit("start plus typing")
        await clock.advance(by: .milliseconds(1499))
        #expect(formValues.isEmpty)
        #expect(session.text == "start")

        await clock.advance(by: .milliseconds(1))
        #expect(formValues == ["start plus typing"])
        #expect(session.text == "start plus typing")
        #expect(source.commitCompositionCount == 0)

        // Wait deterministically for the off-main-thread actor write.
        await session.waitForPendingRecoveryWrites()
        #expect(try store.copies(for: key).first?.entry.text == "start plus typing")
    }

    @Test func continuousTypingStillCheckpointsAtThe20SecondCeiling() async {
        let clock = TestWritingClock()
        let source = FakeSourceEditor(text: "base")
        var formValues: [String] = []

        let session = DraftSession(
            initialText: "base",
            fieldVariant: .content,
            source: source,
            clock: clock,
            onCheckpointText: { formValues.append($0) }
        )

        // One edit every 1 s keeps pushing the 1.5 s idle delay out.
        for step in 1...19 {
            source.simulateUserEdit("edit \(step)")
            await clock.advance(by: .seconds(1))
        }
        #expect(formValues.isEmpty)

        source.simulateUserEdit("edit 20")
        await clock.advance(by: .seconds(1))
        #expect(formValues == ["edit 20"])
        #expect(session.text == "edit 20")
        #expect(source.commitCompositionCount == 0)
    }

    @Test func typingAndRevertingWithinOneWindowWritesNothing() async throws {
        let (store, key, writer) = makeRecoveryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let clock = TestWritingClock()
        let source = FakeSourceEditor(text: "same")
        var formValues: [String] = []

        let session = DraftSession(
            initialText: "same",
            fieldVariant: .content,
            source: source,
            recoveryWriter: writer,
            clock: clock,
            onCheckpointText: { formValues.append($0) }
        )

        source.simulateUserEdit("same typo")
        source.simulateUserEdit("same")
        await clock.advance(by: .milliseconds(1500))

        #expect(formValues.isEmpty)
        #expect(session.lastCheckpointedRevision == session.revision)
        await session.waitForPendingRecoveryWrites()
        #expect(try store.copies(for: key).isEmpty)
    }

    @Test func explicitCommitCommitsCompositionAndFlushesToDisk() async throws {
        let (store, key, writer) = makeRecoveryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let clock = TestWritingClock()
        let source = FakeSourceEditor(text: "draft")
        var formValues: [String] = []

        let session = DraftSession(
            initialText: "draft",
            fieldVariant: .content,
            source: source,
            recoveryWriter: writer,
            clock: clock,
            onCheckpointText: { formValues.append($0) }
        )

        source.simulateUserEdit("draft final")
        let committed = await session.commit()

        #expect(committed == "draft final")
        #expect(source.commitCompositionCount == 1)
        #expect(formValues == ["draft final"])
        #expect(try store.copies(for: key).first?.entry.text == "draft final")

        // Pending timer was cleared, so advancing past idleDelay does not double-fire.
        await clock.advance(by: .seconds(2))
        #expect(formValues.count == 1)
    }

    @Test func sceneBackgroundAndMemoryWarningCheckpointWithoutCommittingAndDisposePreload() async {
        let clock = TestWritingClock()
        let source = FakeSourceEditor(text: "<p>One</p>")
        let transport = FakeRichTransport()
        var formValues: [String] = []

        let session = DraftSession(
            initialText: "<p>One</p>",
            fieldVariant: .content,
            source: source,
            clock: clock,
            richTransport: transport,
            onCheckpointText: { formValues.append($0) }
        )

        // Create a warm preload by visiting Rich Text and returning without edits.
        #expect(await session.switchToRich() == .switched)
        #expect(await session.switchToSource() == .switched)

        session.handleMemoryWarning()
        for _ in 0..<4 { await Task.yield() }
        #expect(transport.disposeCount == 1)

        source.simulateUserEdit("<p>Two</p>")
        let commitsBefore = source.commitCompositionCount
        session.handleSceneInactiveOrBackground()
        #expect(formValues == ["<p>Two</p>"])
        #expect(source.commitCompositionCount == commitsBefore)
    }

    @Test func richModeIdleCheckpointSnapshotsWithoutFreezingAndUsesReportedWordCount() async throws {
        let (store, key, writer) = makeRecoveryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let clock = TestWritingClock()
        let source = FakeSourceEditor(text: "<p>One</p>")
        let transport = FakeRichTransport()

        let session = DraftSession(
            initialText: "<p>One</p>",
            fieldVariant: .content,
            source: source,
            recoveryWriter: writer,
            clock: clock,
            richTransport: transport
        )

        #expect(await session.switchToRich() == .switched)
        let freezesBefore = transport.recordedCalls.filter { $0 == "freeze" }.count

        transport.storedRevision = 1
        transport.storedHTML = "<p>One two three four</p>"
        transport.storedWords = 4
        transport.emit(.edited(revision: 1))

        await clock.advance(by: .milliseconds(1500))

        #expect(transport.recordedCalls.filter { $0 == "freeze" }.count == freezesBefore)
        #expect(session.text == "<p>One two three four</p>")
        #expect(session.wordCount == 4)
        await session.waitForPendingRecoveryWrites()
        #expect(try store.copies(for: key).first?.entry.text == "<p>One two three four</p>")
    }

    @Test func richModeExplicitCommitFreezesSnapshotsAndReEnablesEditing() async {
        let clock = TestWritingClock()
        let source = FakeSourceEditor(text: "<p>One</p>")
        let transport = FakeRichTransport()

        let session = DraftSession(
            initialText: "<p>One</p>",
            fieldVariant: .content,
            source: source,
            clock: clock,
            richTransport: transport
        )

        #expect(await session.switchToRich() == .switched)
        let activatesBefore = transport.activateCalls.count
        transport.storedRevision = 1
        transport.storedHTML = "<p>Committed rich</p>"
        transport.storedWords = 2
        transport.emit(.edited(revision: 1))

        let committed = await session.commit()
        #expect(committed == "<p>Committed rich</p>")
        #expect(transport.recordedCalls.contains("freeze"))
        #expect(transport.activateCalls.count == activatesBefore + 1)
        #expect(transport.activateCalls.last == RichEditorActivateArgs(caret: nil, focus: false))
    }
}
