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

    /// Pure W2 preload gate (§9.3): preloads HTML into the hidden rich view after
    /// an HTML checkpoint only when every W2 condition holds.
    nonisolated static func shouldPreload(
        isRichEnabled: Bool,
        isRichAvailable: Bool,
        isInForeground: Bool,
        now: Duration,
        lastMemoryWarningAt: Duration?,
        revision: Int,
        lastPreloadedRevision: Int?,
        characterCount: Int,
        maxCharacters: Int
    ) -> Bool {
        guard isRichEnabled, isRichAvailable, isInForeground else { return false }
        if let warning = lastMemoryWarningAt, now < warning + processDeathCooldown {
            return false
        }
        guard lastPreloadedRevision != revision else { return false }
        return characterCount <= maxCharacters
    }

    /// App returned to foreground (§9.3 W2).
    func handleSceneActive() {
        isAppInForeground = true
    }

    /// App going inactive or background (§8.1, §9.3 W4): checkpoints without
    /// committing composition and disposes any idle preload in the hidden WebView.
    func handleSceneInactiveOrBackground() {
        isAppInForeground = false
        scheduler?.fireNow()
        disposeIdlePreloadIfNeeded()
    }

    /// Memory warning (§8.1, §9.3 W4): checkpoints without committing composition,
    /// starts the 60 s preload cooldown, and drops any idle preload in the hidden WebView.
    func handleMemoryWarning() {
        lastMemoryWarningAt = clock.now
        scheduler?.fireNow()
        disposeIdlePreloadIfNeeded()
    }

    private func disposeIdlePreloadIfNeeded() {
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
            scheduleBackgroundPreloadIfEligible(html: value, revision: revision)

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

    /// §9.3 W2–W3 background preload into the hidden rich view after an HTML checkpoint.
    /// A newer revision supersedes any in-flight preload; stale results are discarded.
    func scheduleBackgroundPreloadIfEligible(html: String, revision targetRevision: Int) {
        guard state == .sourceOwned else { return }
        guard Self.shouldPreload(
            isRichEnabled: isRichPreloadEnabled,
            isRichAvailable: isRichAvailable,
            isInForeground: isAppInForeground,
            now: clock.now,
            lastMemoryWarningAt: lastMemoryWarningAt,
            revision: targetRevision,
            lastPreloadedRevision: preloadedRichRevision,
            characterCount: html.count,
            maxCharacters: fieldVariant.maxCharacters
        ) else {
            return
        }
        guard let transport = resolveTransport() else { return }

        latestPreloadRevision = targetRevision
        Task { [weak self] in
            guard let self else { return }
            do {
                if !self.isConfigured {
                    let reply = try await transport.configure(RichEditorConfigureArgs(
                        variant: self.fieldVariant,
                        theme: self.themeProvider(),
                        locale: self.localeIdentifier
                    ))
                    guard reply.bridgeVersion == RichEditorBridgeProtocol.bridgeVersion,
                          reply.schemaVersion == RichEditorBridgeProtocol.schemaVersion
                    else { return }
                    self.isConfigured = true
                    if self.isMirrorVisible { self.pushMirrorVisibility() }
                }
                let result = try await transport.load(
                    RichEditorLoadArgs(html: html, revision: targetRevision)
                )
                // W3: discard superseded results or results arriving after a mode switch.
                guard self.state == .sourceOwned,
                      self.latestPreloadRevision == targetRevision,
                      self.revision == targetRevision,
                      result.revision == targetRevision
                else { return }
                self.preloadedRichRevision = result.revision
                self.preloadedRichLoss = result.loss
            } catch {
                self.logNonFatal("Background preload skipped: \(error.localizedDescription)")
            }
        }
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
