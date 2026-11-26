import Foundation
import OSLog
#if os(iOS)
import UIKit
#endif

/// Checkpoints, off-main-thread recovery writes, lifecycle triggers, and word counting (§8).
extension DraftSession {
    /// Explicit commit for Save / Post / Done (§8.7). Commits IME composition first.
    @discardableResult
    func commit() async -> String {
        await checkpointNow(commitComposition: true)
        return text
    }

    /// Synchronous commit when HTML owns the buffer (preserves E1's instant Done path).
    func commitSynchronouslyIfSource() {
        guard state == .sourceOwned else { return }
        source.commitComposition()
        scheduler?.fireNow()
    }

    /// Runs an immediate checkpoint for the current owner.
    func checkpointNow(commitComposition: Bool) async {
        switch state {
        case .sourceOwned:
            if commitComposition { source.commitComposition() }
            let sequence = scheduler?.consumeSequenceForManualCheckpoint() ?? 0
            await checkpointSourceIfNeeded(source.text, revision: revision, sequence: sequence)
        case .richOwned:
            let sequence = scheduler?.consumeSequenceForManualCheckpoint() ?? 0
            await checkpointRich(commitComposition: commitComposition, sequence: sequence)
        case .handingOffToRich, .handingOffToSource:
            break
        }
    }

    /// Awaits any background recovery write queued by a synchronous source checkpoint.
    func waitForPendingRecoveryWrites() async {
        while let pending = pendingRecoveryWrite {
            await pending.task.value
            if pendingRecoveryWrite?.id == pending.id {
                pendingRecoveryWrite = nil
            }
        }
    }

    /// App going inactive or background (§8.1): checkpoints without committing composition.
    func handleSceneInactiveOrBackground() {
        scheduler?.fireNow()
    }

    /// Memory warning (§8.1, §9.3 W4): checkpoints without committing composition and
    /// drops any idle preload in the hidden WebView.
    func handleMemoryWarning() {
        scheduler?.fireNow()
        if state == .sourceOwned, preloadedRichRevision != nil, let transport = richTransport {
            preloadedRichRevision = nil
            preloadedRichLoss = nil
            Task { _ = try? await transport.dispose() }
        }
    }

    /// Restores a local recovery copy in HTML mode as one undoable edit, followed
    /// by an immediate checkpoint (D7, §8.5).
    func restoreRecoveryCopy(_ recoveredText: String) {
        if state != .sourceOwned {
            handoffToken += 1
            pendingRichHandoff = nil
            pendingLossConfirmation = nil
            isShowingSwitchTransition = false
            source.isFrozen = false
            state = .sourceOwned
        }
        preloadedRichRevision = nil
        preloadedRichLoss = nil
        source.restore(recoveredText)
        scheduler?.fireNow()
    }

    // MARK: Internal checkpoint mechanics (§8.2)

    func handleScheduledCheckpoint() {
        let sequence = scheduler?.checkpointCount ?? 0
        switch state {
        case .sourceOwned:
            // Synchronous main-actor snapshot + off-main recovery write & word count.
            guard revision != lastCheckpointedRevision else { return }
            let value = source.text
            lastCheckpointedRevision = revision
            guard value != lastCheckpointedText else { return }
            lastCheckpointedText = value
            text = value
            onCheckpointText?(value)
            queueRecoveryWrite(value, sequence: sequence)
            recountOffMain(value, checkpoint: sequence)

        case .richOwned:
            // Tracked like a source write, so rich and source checkpoints reach disk in order and
            // `waitForPendingRecoveryWrites()` covers this one too.
            recoveryWriteSequence += 1
            let id = recoveryWriteSequence
            let previous = pendingRecoveryWrite?.task
            let task = Task { [weak self] in
                await previous?.value
                await self?.checkpointRich(commitComposition: false, sequence: sequence)
            }
            pendingRecoveryWrite = (id, task)

        case .handingOffToRich, .handingOffToSource:
            break
        }
    }

    func checkpointSourceIfNeeded(
        _ value: String,
        revision currentRevision: Int,
        sequence: Int
    ) async {
        guard currentRevision != lastCheckpointedRevision else { return }
        lastCheckpointedRevision = currentRevision
        guard value != lastCheckpointedText else { return }
        await commitCheckpointPayload(
            value,
            revision: currentRevision,
            sequence: sequence,
            knownWordCount: nil
        )
    }

    func commitCheckpointPayload(
        _ value: String,
        revision currentRevision: Int,
        sequence: Int,
        knownWordCount: Int?
    ) async {
        lastCheckpointedRevision = max(lastCheckpointedRevision, currentRevision)
        lastCheckpointedText = value
        text = value
        onCheckpointText?(value)
        if let knownWordCount {
            countedCheckpoint = sequence
            wordCount = knownWordCount
        } else {
            recountOffMain(value, checkpoint: sequence)
        }
        await writeRecoveryAndWait(value, sequence: sequence)
    }

    func recountOffMain(_ value: String, checkpoint: Int) {
        countedCheckpoint = checkpoint
        wordCountTask?.cancel()
        wordCountTask = Task { [weak self] in
            let count = await Task.detached(priority: .userInitiated) {
                WritingWordCount.count(value)
            }.value
            guard !Task.isCancelled, let self, self.countedCheckpoint == checkpoint else { return }
            self.wordCount = count
        }
    }

    func logNonFatal(_ message: String) {
        writingEditorLog.notice("\(message, privacy: .public)")
    }

    private func checkpointRich(commitComposition: Bool, sequence: Int) async {
        guard state == .richOwned, let transport = richTransport else { return }
        if !commitComposition, revision == lastCheckpointedRevision { return }
        do {
            if commitComposition {
                let freezeResult = try await transport.freeze()
                revision = max(revision, freezeResult.revision)
            }
            let snap = try await transport.snapshot(RichEditorSnapshotArgs(caret: false))
            if commitComposition, state == .richOwned {
                _ = try? await transport.activate(RichEditorActivateArgs(caret: nil, focus: false))
            }
            guard state == .richOwned else { return }
            revision = max(revision, snap.revision)
            if snap.html == lastCheckpointedText {
                lastCheckpointedRevision = max(lastCheckpointedRevision, snap.revision)
                return
            }
            await commitCheckpointPayload(
                snap.html,
                revision: snap.revision,
                sequence: sequence,
                knownWordCount: snap.words
            )
        } catch {
            if commitComposition, state == .richOwned {
                _ = try? await transport.activate(RichEditorActivateArgs(caret: nil, focus: false))
            }
            logNonFatal("Rich checkpoint failed: \(error.localizedDescription)")
        }
    }

    private func queueRecoveryWrite(_ value: String, sequence: Int) {
        guard recoveryWriter != nil else { return }
        recoveryWriteSequence += 1
        let id = recoveryWriteSequence
        let previous = pendingRecoveryWrite?.task
        let task = Task { [weak self] in
            await previous?.value
            await self?.writeRecoveryAndWait(value, sequence: sequence)
        }
        pendingRecoveryWrite = (id, task)
    }

    private func writeRecoveryAndWait(_ value: String, sequence: Int) async {
        guard let recoveryWriter else { return }
        #if os(iOS)
        var assertion = UIBackgroundTaskIdentifier.invalid
        assertion = UIApplication.shared.beginBackgroundTask(withName: "Writing recovery") {
            UIApplication.shared.endBackgroundTask(assertion)
            assertion = .invalid
        }
        defer {
            if assertion != .invalid { UIApplication.shared.endBackgroundTask(assertion) }
            assertion = .invalid
        }
        #endif
        do {
            try await recoveryWriter.write(value, sequence: sequence)
        } catch {
            let message = "Local recovery could not be saved: \(UserFacingError.message(for: error))"
            errorMessage = message
            onRecoveryError?(message)
        }
    }
}
