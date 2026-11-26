import Foundation
import OSLog

/// Hand-off state machine (`source` ↔ `rich`), R1 no-op restore, §6.9 loss
/// confirmation, §7.8 failure handling, and §7.11 switch check.
extension DraftSession {
    /// Switches ownership from HTML (`source`) to Rich Text (`rich`) per §7.3.
    @discardableResult
    func switchToRich() async -> DraftHandoffOutcome {
        guard state == .sourceOwned else { return .ignored }
        if let cooldown = richCooldownUntil, clock.now >= cooldown {
            richCooldownUntil = nil
        }
        guard isRichAvailable else { return .unavailable }
        guard let transport = resolveTransport() else { return .unavailable }

        handoffToken += 1
        let token = handoffToken
        state = .handingOffToRich
        noticeMessage = nil

        // Step 1 (§7.3): freeze source without dropping focus; commit IME composition.
        source.isFrozen = true
        source.commitComposition()

        // Step 2 (§7.3, I4): snapshot and checkpoint before the new owner accepts input.
        let sourceText = source.text
        let caretOffset = source.caretOffsetUTF16
        let currentRevision = revision
        let sequence = scheduler?.consumeSequenceForManualCheckpoint() ?? 0
        await checkpointSourceIfNeeded(sourceText, revision: currentRevision, sequence: sequence)

        guard handoffToken == token, state == .handingOffToRich else { return .aborted }

        // Ensure `configure` succeeded and versions agree (§7.2).
        if !isConfigured {
            let configureOutcome = await configureTransport(transport, token: token)
            if configureOutcome != .switched {
                return configureOutcome
            }
        }

        // Step 3–4 (§7.3): warm reuse or cold `load` + §7.11 switch check.
        let loss: RichEditorLossReport
        if preloadedRichRevision == currentRevision, let cachedLoss = preloadedRichLoss {
            loss = cachedLoss
        } else {
            switch await loadAndVerifyColdRich(
                transport: transport,
                sourceText: sourceText,
                revision: currentRevision,
                token: token
            ) {
            case let .success(report):
                loss = report
            case let .failure(outcome):
                return outcome
            }
        }

        guard handoffToken == token, state == .handingOffToRich else { return .aborted }

        // Step 5 (§6.9, §7.3): confirm non-empty dropped items before activating.
        if loss.hasDropped {
            pendingRichHandoff = PendingRichHandoff(
                token: token,
                caretOffset: caretOffset,
                revision: currentRevision,
                sourceText: sourceText,
                loss: loss
            )
            pendingLossConfirmation = DraftLossConfirmation(loss: loss)
            return .awaitingLossConfirmation(loss)
        }

        return await completeSwitchToRich(
            transport: transport,
            caretOffset: caretOffset,
            revision: currentRevision,
            sourceText: sourceText,
            loss: loss,
            token: token
        )
    }

    /// Writer confirmed the §6.9 loss report; activates Rich Text and commits ownership.
    @discardableResult
    func confirmLossAndCompleteSwitchToRich() async -> DraftHandoffOutcome {
        guard let pending = pendingRichHandoff,
              state == .handingOffToRich,
              pending.token == handoffToken,
              let transport = richTransport
        else { return .ignored }

        pendingRichHandoff = nil
        pendingLossConfirmation = nil
        return await completeSwitchToRich(
            transport: transport,
            caretOffset: pending.caretOffset,
            revision: pending.revision,
            sourceText: pending.sourceText,
            loss: pending.loss,
            token: pending.token
        )
    }

    /// Writer cancelled the §6.9 loss report; unfreezes HTML mode and changes nothing.
    /// Does not count as a failure.
    func cancelPendingRichSwitch() {
        guard state == .handingOffToRich, pendingRichHandoff != nil else { return }
        pendingRichHandoff = nil
        pendingLossConfirmation = nil
        isShowingSwitchTransition = false
        source.isFrozen = false
        state = .sourceOwned
    }

    /// Switches ownership from Rich Text (`rich`) to HTML (`source`) per §7.4.
    /// Pass `overrideCaretOffset` when switching from a §7.10 HTML mirror tap so
    /// the HTML caret lands where the writer tapped.
    @discardableResult
    func switchToSource(overrideCaretOffset: Int? = nil) async -> DraftHandoffOutcome {
        guard state == .richOwned, let transport = richTransport else { return .ignored }

        handoffToken += 1
        let token = handoffToken
        state = .handingOffToSource
        noticeMessage = nil

        // Step 1 (§7.4): freeze rich editor (blur, read-only, wait for IME composition).
        do {
            let freezeResult = try await transport.freeze()
            guard handoffToken == token, state == .handingOffToSource else { return .aborted }
            revision = max(revision, freezeResult.revision)
        } catch {
            return await abortSwitchToSource(transport: transport, token: token, error: error)
        }

        // Step 2 (§7.4): fetch snapshot with caret offset.
        let snapshot: RichEditorSnapshotResult
        do {
            snapshot = try await transport.snapshot(RichEditorSnapshotArgs(caret: true))
            guard handoffToken == token, state == .handingOffToSource else { return .aborted }
            revision = max(revision, snapshot.revision)
        } catch {
            return await abortSwitchToSource(transport: transport, token: token, error: error)
        }

        // Step 3 (§7.4, R1 / I9): no edits in Rich Text → restore source bytes verbatim.
        let wasEditedInRich = snapshot.revision != richEntryRevision
            || lastRichEditedRevision != richEntryRevision
        if !wasEditedInRich {
            return restoreUneditedSourceAfterRich(
                snapshot: snapshot,
                overrideCaretOffset: overrideCaretOffset
            )
        }

        // §7.11 switch check before committing edited Rich Text output.
        if let rejection = await verifyEditedRichSwitch(transport: transport, snapshot: snapshot, token: token) {
            return rejection
        }

        // Step 4 (§7.4, I4, U2): checkpoint HTML, replace source buffer, clear native undo stack.
        let sequence = scheduler?.consumeSequenceForManualCheckpoint() ?? 0
        await commitCheckpointPayload(
            snapshot.html,
            revision: snapshot.revision,
            sequence: sequence,
            knownWordCount: snapshot.words
        )
        source.replaceForModeHandoff(
            snapshot.html,
            caretOffset: overrideCaretOffset ?? snapshot.caretOffset
        )

        // Step 5 (§7.4, W5): unfreeze and focus source; keep rich loaded as warm preload.
        source.isFrozen = false
        source.focus()
        state = .sourceOwned
        notifyRichOwnership(false)
        preloadedRichRevision = snapshot.revision
        preloadedRichLoss = .empty
        lastSwitchChanges = nil
        return .switched
    }

    /// §7.10 two-views tap into the read-only HTML mirror: switches ownership
    /// to HTML and places the caret at the tapped UTF-16 offset.
    @discardableResult
    func switchToSourceFromMirrorTap(atUTF16Offset offset: Int) async -> DraftHandoffOutcome {
        await switchToSource(overrideCaretOffset: max(0, offset))
    }

    func resolveTransport() -> (any RichEditorBridgeTransport)? {
        if let richTransport { return richTransport }
        guard let created = makeRichTransport?() else { return nil }
        richTransport = created
        attachTransportCallbacks(created)
        return created
    }

    func sendRichCommand(name: String, attrs: [String: RichEditorJSONValue] = [:]) {
        guard let transport = richTransport else { return }
        Task { [weak self] in
            do {
                _ = try await transport.command(RichEditorCommandArgs(name: name, attrs: attrs))
            } catch {
                self?.logNonFatal("Rich command '\(name)' failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Private hand-off helpers

    private func restoreUneditedSourceAfterRich(
        snapshot: RichEditorSnapshotResult,
        overrideCaretOffset: Int?
    ) -> DraftHandoffOutcome {
        if let caretOffset = overrideCaretOffset ?? snapshot.caretOffset {
            source.setCaretOffsetUTF16(caretOffset)
        }
        text = richSourceTextAtEntry
        source.isFrozen = false
        source.focus()
        state = .sourceOwned
        notifyRichOwnership(false)
        preloadedRichRevision = snapshot.revision
        preloadedRichLoss = preloadedRichLoss ?? .empty
        return .switched
    }

    private func verifyEditedRichSwitch(
        transport: any RichEditorBridgeTransport,
        snapshot: RichEditorSnapshotResult,
        token: Int
    ) async -> DraftHandoffOutcome? {
        do {
            let check = try await transport.verifySwitch(
                RichEditorSwitchCheckArgs(direction: .richToSource, html: snapshot.html)
            )
            guard handoffToken == token, state == .handingOffToSource else { return .aborted }
            if !check.ok {
                await handleSwitchCheckMismatch(
                    leavingMode: .rich,
                    leavingText: snapshot.html,
                    candidateText: check.candidateHtml,
                    reason: check.reason
                )
                _ = try? await transport.activate(RichEditorActivateArgs(caret: nil, focus: true))
                guard handoffToken == token else { return .aborted }
                transport.focusWebView()
                state = .richOwned
                return .switchCheckFailed
            }
            return nil
        } catch {
            return await abortSwitchToSource(transport: transport, token: token, error: error)
        }
    }

    private func configureTransport(
        _ transport: any RichEditorBridgeTransport,
        token: Int
    ) async -> DraftHandoffOutcome {
        let args = RichEditorConfigureArgs(
            variant: fieldVariant,
            theme: themeProvider(),
            locale: localeIdentifier
        )
        do {
            let reply = try await transport.configure(args)
            guard handoffToken == token, state == .handingOffToRich else { return .aborted }
            guard reply.bridgeVersion == RichEditorBridgeProtocol.bridgeVersion,
                  reply.schemaVersion == RichEditorBridgeProtocol.schemaVersion
            else {
                source.isFrozen = false
                state = .sourceOwned
                failureCount += 1
                isRichPermanentlyDisabled = true
                noticeMessage = Self.richOpenFailedMessage
                writingEditorLog.error(
                    """
                    Rich editor version mismatch: bridge=\(reply.bridgeVersion, privacy: .public) \
                    schema=\(reply.schemaVersion, privacy: .public)
                    """
                )
                return .failed
            }
            isConfigured = true
            return .switched
        } catch {
            return failSwitchToRich(token: token, error: error)
        }
    }

    private enum ColdLoadOutcome {
        case success(RichEditorLossReport)
        case failure(DraftHandoffOutcome)
    }

    private func loadAndVerifyColdRich(
        transport: any RichEditorBridgeTransport,
        sourceText: String,
        revision currentRevision: Int,
        token: Int
    ) async -> ColdLoadOutcome {
        let clock = self.clock
        let transitionTask = Task { [weak self] in
            do {
                try await clock.sleep(for: Self.switchTransitionDelay)
                if let self, self.handoffToken == token, self.state == .handingOffToRich {
                    self.isShowingSwitchTransition = true
                }
            } catch {
                // Cancelled once load finishes under 100 ms.
            }
        }
        defer {
            transitionTask.cancel()
            isShowingSwitchTransition = false
        }

        let loadResult: RichEditorLoadResult
        do {
            loadResult = try await transport.load(
                RichEditorLoadArgs(html: sourceText, revision: currentRevision)
            )
            guard handoffToken == token, state == .handingOffToRich else { return .failure(.aborted) }
        } catch {
            return .failure(failSwitchToRich(token: token, error: error))
        }

        // §7.11 switch check before confirming drops or committing ownership.
        do {
            let check = try await transport.verifySwitch(
                RichEditorSwitchCheckArgs(direction: .sourceToRich, html: sourceText)
            )
            guard handoffToken == token, state == .handingOffToRich else { return .failure(.aborted) }
            if !check.ok {
                preloadedRichRevision = nil
                preloadedRichLoss = nil
                source.isFrozen = false
                state = .sourceOwned
                await handleSwitchCheckMismatch(
                    leavingMode: .source,
                    leavingText: sourceText,
                    candidateText: check.candidateHtml,
                    reason: check.reason
                )
                return .failure(.switchCheckFailed)
            }
        } catch {
            return .failure(failSwitchToRich(token: token, error: error))
        }

        preloadedRichRevision = loadResult.revision
        preloadedRichLoss = loadResult.loss
        return .success(loadResult.loss)
    }

    private func completeSwitchToRich(
        transport: any RichEditorBridgeTransport,
        caretOffset: Int,
        revision currentRevision: Int,
        sourceText: String,
        loss: RichEditorLossReport,
        token: Int
    ) async -> DraftHandoffOutcome {
        do {
            _ = try await transport.activate(
                RichEditorActivateArgs(caret: caretOffset, focus: true)
            )
            guard handoffToken == token, state == .handingOffToRich else { return .aborted }
        } catch {
            return failSwitchToRich(token: token, error: error)
        }

        transport.focusWebView()
        richEntryRevision = currentRevision
        richSourceTextAtEntry = sourceText
        lastRichEditedRevision = currentRevision
        preloadedRichRevision = currentRevision
        preloadedRichLoss = loss
        lastSwitchChanges = loss.hasNonBlockingChanges ? loss : nil
        mirrorDocument = HTMLMirrorDocument.seed(from: sourceText, revision: currentRevision)
        toolbarState = .empty
        state = .richOwned
        notifyRichOwnership(true)
        return .switched
    }

    private func failSwitchToRich(token: Int, error: Error) -> DraftHandoffOutcome {
        guard handoffToken == token, state == .handingOffToRich else { return .aborted }
        if error as? RichEditorBridgeError == .processTerminated {
            handleWebContentProcessTerminated()
            return .aborted
        }
        source.isFrozen = false
        state = .sourceOwned
        recordFailure(message: Self.richOpenFailedMessage)
        return .failed
    }

    private func abortSwitchToSource(
        transport: any RichEditorBridgeTransport,
        token: Int,
        error: Error
    ) async -> DraftHandoffOutcome {
        guard handoffToken == token, state == .handingOffToSource else { return .aborted }
        if error as? RichEditorBridgeError == .processTerminated {
            handleWebContentProcessTerminated()
            return .aborted
        }
        logNonFatal("Switch Rich → HTML failed: \(error.localizedDescription)")
        _ = try? await transport.activate(RichEditorActivateArgs(caret: nil, focus: true))
        guard handoffToken == token else { return .aborted }
        transport.focusWebView()
        state = .richOwned
        recordFailure(message: Self.switchCheckStayedInRichMessage)
        return .failed
    }

    private func handleSwitchCheckMismatch(
        leavingMode: DraftEditorMode,
        leavingText: String,
        candidateText: String,
        reason: String?
    ) async {
        if let recoveryWriter {
            do {
                lastMismatchRecoveryURLs = try await recoveryWriter.writeSwitchCheckMismatch(
                    leavingText: leavingText,
                    candidateText: candidateText
                )
            } catch {
                let message = "Local recovery could not be saved: \(UserFacingError.message(for: error))"
                errorMessage = message
                onRecoveryError?(message)
            }
        }
        let message = leavingMode == .rich
            ? Self.switchCheckStayedInRichMessage
            : Self.switchCheckStayedInHTMLMessage
        recordFailure(message: message)
        writingEditorLog.error(
            """
            Switch check mismatch leaving \(leavingMode.rawValue, privacy: .public) \
            (leavingBytes=\(leavingText.utf8.count, privacy: .public), \
            candidateBytes=\(candidateText.utf8.count, privacy: .public), \
            reason=\(reason ?? "none", privacy: .public))
            """
        )
    }

    private func recordFailure(message: String) {
        failureCount += 1
        if failureCount >= Self.maxFailuresBeforeDisable {
            isRichPermanentlyDisabled = true
        }
        noticeMessage = message
    }
}
