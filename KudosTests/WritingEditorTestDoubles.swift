import Foundation
@testable import Kudos

/// Deterministic manual clock for testing checkpoint delays, cooldowns, and timeouts
/// without wall-clock sleeps.
nonisolated final class TestWritingClock: WritingClock, @unchecked Sendable {
    private struct Waiter {
        let id: UUID
        let wakeAt: Duration
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var currentTime: Duration = .zero
    private var waiters: [Waiter] = []
    private var cancelledIDs: Set<UUID> = []

    var now: Duration {
        lock.lock()
        defer { lock.unlock() }
        return currentTime
    }

    func sleep(for duration: Duration) async throws {
        if duration <= .zero {
            try Task.checkCancellation()
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                if Task.isCancelled || cancelledIDs.remove(id) != nil {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                let wakeAt = currentTime + duration
                waiters.append(Waiter(id: id, wakeAt: wakeAt, continuation: continuation))
                lock.unlock()
            }
        } onCancel: {
            lock.lock()
            if let index = waiters.firstIndex(where: { $0.id == id }) {
                let waiter = waiters.remove(at: index)
                lock.unlock()
                waiter.continuation.resume(throwing: CancellationError())
            } else {
                cancelledIDs.insert(id)
                lock.unlock()
            }
        }
    }

    func advance(by delta: Duration) async {
        // Let newly spawned tasks register their sleepers before moving time.
        for _ in 0..<2 { await Task.yield() }
        lock.lock()
        currentTime += delta
        let ready = waiters
            .filter { $0.wakeAt <= currentTime }
            .sorted { $0.wakeAt < $1.wakeAt }
        waiters.removeAll { $0.wakeAt <= currentTime }
        lock.unlock()
        for waiter in ready {
            waiter.continuation.resume()
        }
        for _ in 0..<4 { await Task.yield() }
    }
}

@MainActor
final class FakeSourceEditor: DraftSourceBridge {
    var text: String
    var isFrozen = false
    var caretOffsetUTF16 = 0
    var canUndo = false
    var canRedo = false
    var onEdit: (@MainActor () -> Void)?

    private(set) var commitCompositionCount = 0
    private(set) var focusCount = 0
    private(set) var undoCount = 0
    private(set) var redoCount = 0
    private(set) var replaceForHandoffCalls: [(text: String, caret: Int?)] = []
    private(set) var setCaretCalls: [Int] = []
    private(set) var clearedUndoHistoryCount = 0

    init(text: String) {
        self.text = text
    }

    func simulateUserEdit(_ newText: String) {
        guard !isFrozen else { return }
        text = newText
        canUndo = true
        onEdit?()
    }

    func commitComposition() {
        commitCompositionCount += 1
    }

    func setCaretOffsetUTF16(_ offset: Int) {
        caretOffsetUTF16 = offset
        setCaretCalls.append(offset)
    }

    func replaceForModeHandoff(_ value: String, caretOffset: Int?) {
        text = value
        canUndo = false
        canRedo = false
        clearedUndoHistoryCount += 1
        replaceForHandoffCalls.append((value, caretOffset))
        if let caretOffset { caretOffsetUTF16 = caretOffset }
    }

    func restore(_ value: String) {
        guard !isFrozen else { return }
        commitComposition()
        text = value
        canUndo = true
        onEdit?()
    }

    func replaceText(in range: NSRange, with value: String) {
        guard !isFrozen else { return }
        text = (text as NSString).replacingCharacters(in: range, with: value)
        canUndo = true
        onEdit?()
    }

    func focus() {
        focusCount += 1
    }

    func undo() {
        guard !isFrozen else { return }
        undoCount += 1
    }

    func redo() {
        guard !isFrozen else { return }
        redoCount += 1
    }
}

@MainActor
final class FakeRichTransport: RichEditorBridgeTransport {
    var onEvent: (@MainActor (RichEditorEvent) -> Void)?
    var onProcessTerminated: (@MainActor () -> Void)?

    private(set) var recordedCalls: [String] = []
    private(set) var configureCalls: [RichEditorConfigureArgs] = []
    private(set) var loadCalls: [RichEditorLoadArgs] = []
    private(set) var activateCalls: [RichEditorActivateArgs] = []
    private(set) var commandCalls: [RichEditorCommandArgs] = []
    private(set) var verifySwitchCalls: [RichEditorSwitchCheckArgs] = []
    private(set) var setThemeCalls: [RichEditorTheme] = []
    private(set) var setAppearanceCalls: [RichEditorAppearance] = []
    private(set) var disposeCount = 0
    private(set) var focusCount = 0
    private(set) var resetCount = 0

    var configureHandler: (@MainActor (RichEditorConfigureArgs) async throws -> RichEditorConfigureResult)?
    var loadHandler: (@MainActor (RichEditorLoadArgs) async throws -> RichEditorLoadResult)?
    var activateHandler: (@MainActor (RichEditorActivateArgs) async throws -> RichEditorActivateResult)?
    var freezeHandler: (@MainActor () async throws -> RichEditorFreezeResult)?
    var snapshotHandler: (@MainActor (RichEditorSnapshotArgs) async throws -> RichEditorSnapshotResult)?
    var commandHandler: (@MainActor (RichEditorCommandArgs) async throws -> RichEditorCommandResult)?
    var verifySwitchHandler: (@MainActor (RichEditorSwitchCheckArgs) async throws -> RichEditorSwitchCheckResult)?

    var storedHTML = ""
    var storedRevision = 0
    var storedCaretOffset: Int? = 0
    var storedWords = 0

    func configure(_ args: RichEditorConfigureArgs) async throws -> RichEditorConfigureResult {
        recordedCalls.append("configure")
        configureCalls.append(args)
        if let configureHandler { return try await configureHandler(args) }
        return RichEditorConfigureResult(
            bridgeVersion: RichEditorBridgeProtocol.bridgeVersion,
            schemaVersion: RichEditorBridgeProtocol.schemaVersion,
            bundleVersion: "1.0.0-fake"
        )
    }

    func load(_ args: RichEditorLoadArgs) async throws -> RichEditorLoadResult {
        recordedCalls.append("load")
        loadCalls.append(args)
        if let loadHandler { return try await loadHandler(args) }
        storedHTML = args.html
        storedRevision = args.revision
        return RichEditorLoadResult(revision: args.revision, loss: .empty, timing: .zero)
    }

    func activate(_ args: RichEditorActivateArgs) async throws -> RichEditorActivateResult {
        recordedCalls.append("activate")
        activateCalls.append(args)
        if let activateHandler { return try await activateHandler(args) }
        return RichEditorActivateResult(caretFound: args.caret != nil)
    }

    func freeze() async throws -> RichEditorFreezeResult {
        recordedCalls.append("freeze")
        if let freezeHandler { return try await freezeHandler() }
        return RichEditorFreezeResult(revision: storedRevision)
    }

    func snapshot(_ args: RichEditorSnapshotArgs) async throws -> RichEditorSnapshotResult {
        recordedCalls.append("snapshot")
        if let snapshotHandler { return try await snapshotHandler(args) }
        return RichEditorSnapshotResult(
            revision: storedRevision,
            html: storedHTML,
            caretOffset: args.caret ? storedCaretOffset : nil,
            words: storedWords
        )
    }

    func command(_ args: RichEditorCommandArgs) async throws -> RichEditorCommandResult {
        recordedCalls.append("command:\(args.name)")
        commandCalls.append(args)
        if let commandHandler { return try await commandHandler(args) }
        return RichEditorCommandResult(applied: true)
    }

    func lint(_ args: RichEditorLintArgs) async throws -> RichEditorLintResult {
        recordedCalls.append("lint")
        return RichEditorLintResult(loss: .empty)
    }

    func setTheme(_ theme: RichEditorTheme) async throws {
        recordedCalls.append("setTheme")
        setThemeCalls.append(theme)
    }

    func setAppearance(_ appearance: RichEditorAppearance) async throws {
        recordedCalls.append("setAppearance")
        setAppearanceCalls.append(appearance)
    }

    private(set) var setMirrorCalls: [Bool] = []

    func setMirror(_ args: RichEditorMirrorArgs) async throws {
        recordedCalls.append("setMirror")
        setMirrorCalls.append(args.enabled)
    }

    func dispose() async throws {
        recordedCalls.append("dispose")
        disposeCount += 1
    }

    func verifySwitch(_ args: RichEditorSwitchCheckArgs) async throws -> RichEditorSwitchCheckResult {
        recordedCalls.append("verifySwitch:\(args.direction.rawValue)")
        verifySwitchCalls.append(args)
        if let verifySwitchHandler { return try await verifySwitchHandler(args) }
        return RichEditorSwitchCheckResult(ok: true, candidateHtml: args.html, reason: nil)
    }

    func focusWebView() {
        focusCount += 1
    }

    func resetAfterTermination() {
        resetCount += 1
    }

    func emit(_ event: RichEditorEvent) {
        onEvent?(event)
    }

    func simulateProcessDeath() {
        onProcessTerminated?()
    }
}
