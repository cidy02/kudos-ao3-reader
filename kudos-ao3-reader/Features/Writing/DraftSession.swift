import Foundation
import OSLog

/// Which view currently owns the editable text (docs/WRITING_EDITOR_ARCHITECTURE.md §1, D3).
nonisolated enum DraftEditorMode: String, CaseIterable, Equatable, Hashable, Sendable {
    case source
    case rich

    var title: String {
        switch self {
        case .source: "HTML"
        case .rich: "Rich Text"
        }
    }
}

/// Hand-off state machine states (§7.1).
nonisolated enum DraftSessionState: Equatable, Sendable {
    case sourceOwned
    case handingOffToRich
    case richOwned
    case handingOffToSource
}

/// Outcome returned by `DraftSession.switchToRich()` / `switchToSource()`.
nonisolated enum DraftHandoffOutcome: Equatable, Sendable {
    case switched
    case awaitingLossConfirmation(RichEditorLossReport)
    case switchCheckFailed
    case failed
    case aborted
    case unavailable
    case ignored
}

/// Presented when loading HTML into Rich Text would drop tags or attributes AO3 removes (§6.9).
nonisolated struct DraftLossConfirmation: Equatable, Identifiable, Sendable {
    let id = UUID()
    let loss: RichEditorLossReport

    var message: String { loss.droppedConfirmationMessage }
}

/// Abstraction over the native HTML text view controller so `DraftSession` can be
/// unit-tested without mounting UIKit/AppKit views.
@MainActor
protocol DraftSourceBridge: AnyObject {
    var text: String { get }
    var isFrozen: Bool { get set }
    var caretOffsetUTF16: Int { get }
    var canUndo: Bool { get }
    var canRedo: Bool { get }
    var onEdit: (@MainActor () -> Void)? { get set }

    func commitComposition()
    func setCaretOffsetUTF16(_ offset: Int)
    func replaceForModeHandoff(_ value: String, caretOffset: Int?)
    func restore(_ value: String)
    func focus()
    func undo()
    func redo()
}

extension WritingTextController: DraftSourceBridge {}

/// Per-field native source of truth for the writing editor (§5.1, §7, §8).
///
/// Holds the authoritative HTML string, monotonic revision counter, mode owner,
/// E1 checkpoint scheduler, off-main-thread recovery writer actor, and the
/// source ↔ rich hand-off state machine (including R1, U1–U3, the two-failure
/// rule, process-death fallback, and the §7.11 round-trip switch check).
@MainActor @Observable
final class DraftSession {
    nonisolated static let maxFailuresBeforeDisable = 2
    nonisolated static let processDeathCooldown: Duration = .seconds(60)
    nonisolated static let switchTransitionDelay: Duration = .milliseconds(100)

    nonisolated static let richOpenFailedMessage = "Rich Text couldn't open this text"
    nonisolated static let processDeathLossWarning =
        "The last few seconds in Rich Text couldn't be recovered"
    nonisolated static let processDeathCleanFallbackMessage =
        "Rich Text closed unexpectedly. Switched to HTML mode."
    nonisolated static let switchCheckStayedInRichMessage =
        "Kudos couldn't switch views without changing your text, so it stayed in Rich Text."
    nonisolated static let switchCheckStayedInHTMLMessage =
        "Kudos couldn't switch views without changing your text, so it stayed in HTML."

    // MARK: Observable state (mutated across DraftSession+Handoff & DraftSession+Checkpoints)

    /// Native authoritative text, updated at checkpoints and hand-offs (I2).
    var text: String
    /// Text the form loaded when the editor opened (§5.1).
    let baseText: String
    let fieldVariant: DraftFieldVariant
    /// Monotonic edit counter; loading text into a mode does not increment it (§1).
    var revision = 0
    var state: DraftSessionState = .sourceOwned
    /// Word count as of open or the last checkpoint (off main thread, §8.2).
    var wordCount: Int?
    var toolbarState: RichEditorToolbarState = .empty
    var failureCount = 0
    var isRichPermanentlyDisabled = false
    var richCooldownUntil: Duration?
    /// Non-nil while waiting for the writer to confirm or cancel §6.9 dropped items.
    var pendingLossConfirmation: DraftLossConfirmation?
    /// Non-blocking changes from the last switch into Rich Text ("What changed", §6.9).
    var lastSwitchChanges: RichEditorLossReport?
    /// Shown after 100 ms on a cold HTML → Rich Text `load` (§7.3 step 4).
    var isShowingSwitchTransition = false
    /// Last recovery copy URLs written on a §7.11 switch-check mismatch.
    var lastMismatchRecoveryURLs: (leaving: URL, candidate: URL)?
    /// The last paste into Rich Text and what AO3's cleaning did to it (the paste report, §6.8, §6.9).
    var lastPaste: DraftPasteReport?
    /// The last tap on a note or TK highlight (T-576d).
    var lastAnnotationTap: DraftAnnotationTap?
    /// The last "TK" the writer typed, with its range in the HTML a snapshot would return (T-576d).
    var lastTypedTK: DraftTypedTK?
    /// The letters before the caret in Rich Text, for name suggestions on the keys bar (T-576d).
    var wordAtCaret: String?
    /// Whether the §7.10 HTML mirror is on screen; the page sends `mirrorBlocks` only while it is.
    private(set) var isMirrorVisible = false
    /// Incremental block mirror for §7.10 two-views mode (updated ONLY from `mirrorBlocks`).
    var mirrorDocument = HTMLMirrorDocument()
    /// User-facing notice for switch failures, switch-check mismatches, or process death.
    var noticeMessage: String?
    /// User-facing error for recovery I/O failures.
    var errorMessage: String?

    /// Mode that currently owns the text (I1).
    var owner: DraftEditorMode {
        switch state {
        case .sourceOwned, .handingOffToRich: .source
        case .richOwned, .handingOffToSource: .rich
        }
    }

    var isHandingOff: Bool {
        state == .handingOffToRich || state == .handingOffToSource
    }

    /// Mode reflected in the Rich Text / HTML toggle while idle or transitioning.
    var displayedMode: DraftEditorMode {
        switch state {
        case .sourceOwned, .handingOffToSource: .source
        case .richOwned, .handingOffToRich: .rich
        }
    }

    /// Whether Rich Text can currently be entered (respects version mismatch,
    /// two-failure rule, and the 60 s process-death cooldown).
    var isRichAvailable: Bool {
        guard !isRichPermanentlyDisabled else { return false }
        if let cooldown = richCooldownUntil {
            return clock.now >= cooldown
        }
        return true
    }

    var canUndo: Bool {
        switch state {
        case .sourceOwned: source.canUndo
        case .richOwned: toolbarState.canUndo
        case .handingOffToRich, .handingOffToSource: false
        }
    }

    var canRedo: Bool {
        switch state {
        case .sourceOwned: source.canRedo
        case .richOwned: toolbarState.canRedo
        case .handingOffToRich, .handingOffToSource: false
        }
    }

    // MARK: Dependencies & internal bookkeeping (shared across DraftSession extensions)

    @ObservationIgnored var lastCheckpointedRevision = 0
    @ObservationIgnored var lastCheckpointedText: String

    @ObservationIgnored let source: any DraftSourceBridge
    @ObservationIgnored let recoveryWriter: WritingRecoveryWriter?
    @ObservationIgnored let clock: any WritingClock
    @ObservationIgnored var scheduler: WritingCheckpointScheduler?
    @ObservationIgnored var richTransport: (any RichEditorBridgeTransport)?
    @ObservationIgnored let makeRichTransport: (@MainActor () -> any RichEditorBridgeTransport)?
    @ObservationIgnored var themeProvider: @MainActor () -> RichEditorTheme
    @ObservationIgnored let localeIdentifier: String
    @ObservationIgnored var onCheckpointText: (@MainActor (String) -> Void)?
    @ObservationIgnored var onRecoveryError: (@MainActor (String) -> Void)?
    @ObservationIgnored var onToolbarStateSync: (@MainActor (RichEditorToolbarState) -> Void)?
    @ObservationIgnored var onRichOwnershipChanged: (@MainActor (Bool) -> Void)?

    @ObservationIgnored var isRichPreloadEnabled: Bool
    @ObservationIgnored var isAppInForeground = true
    @ObservationIgnored var lastMemoryWarningAt: Duration?
    @ObservationIgnored var latestPreloadRevision = -1
    @ObservationIgnored var isConfigured = false
    @ObservationIgnored var richEntryRevision = 0
    @ObservationIgnored var richSourceTextAtEntry = ""
    @ObservationIgnored var lastRichEditedRevision = 0
    @ObservationIgnored var preloadedRichRevision: Int?
    @ObservationIgnored var preloadedRichLoss: RichEditorLossReport?
    @ObservationIgnored var pendingRichHandoff: PendingRichHandoff?
    @ObservationIgnored var handoffToken = 0
    @ObservationIgnored var countedCheckpoint = 0
    @ObservationIgnored var wordCountTask: Task<Void, Never>?
    @ObservationIgnored var pendingRecoveryWrite: (id: Int, task: Task<Void, Never>)?
    @ObservationIgnored var recoveryWriteSequence = 0

    struct PendingRichHandoff {
        let token: Int
        let caretOffset: Int
        let revision: Int
        let sourceText: String
        let loss: RichEditorLossReport
    }

    init(
        initialText: String,
        fieldVariant: DraftFieldVariant,
        source: any DraftSourceBridge,
        recoveryWriter: WritingRecoveryWriter? = nil,
        policy: WritingCheckpointPolicy = WritingCheckpointPolicy(),
        clock: any WritingClock = SystemWritingClock(),
        richTransport: (any RichEditorBridgeTransport)? = nil,
        makeRichTransport: (@MainActor () -> any RichEditorBridgeTransport)? = nil,
        themeProvider: @escaping @MainActor () -> RichEditorTheme = {
            RichEditorTheme(
                background: "#FFFFFF",
                text: "#1E1E1E",
                accent: "#821019",
                link: "#0B66C2",
                fontFamily: RichEditorTheme.defaultFontFamily,
                fontSizePx: 15.5,
                lineHeight: RichEditorTheme.defaultLineHeight
            )
        },
        localeIdentifier: String = Locale.current.identifier,
        isRichPreloadEnabled: Bool = false,
        onCheckpointText: (@MainActor (String) -> Void)? = nil,
        onRecoveryError: (@MainActor (String) -> Void)? = nil
    ) {
        self.text = initialText
        self.baseText = initialText
        self.lastCheckpointedText = initialText
        self.fieldVariant = fieldVariant
        self.source = source
        self.recoveryWriter = recoveryWriter
        self.clock = clock
        self.richTransport = richTransport
        self.makeRichTransport = makeRichTransport
        self.themeProvider = themeProvider
        self.localeIdentifier = localeIdentifier
        self.isRichPreloadEnabled = isRichPreloadEnabled
        self.onCheckpointText = onCheckpointText
        self.onRecoveryError = onRecoveryError

        let scheduler = WritingCheckpointScheduler(policy: policy, clock: clock) { [weak self] in
            self?.handleScheduledCheckpoint()
        }
        self.scheduler = scheduler
        source.onEdit = { [weak self] in self?.noteSourceEdit() }

        if let richTransport {
            attachTransportCallbacks(richTransport)
        }
        recountOffMain(initialText, checkpoint: 0)
    }

    // MARK: Keystroke path (O(1), D8 / I3)

    /// Records a source-mode keystroke or edit. O(1): never copies text, writes
    /// to disk, counts words, or touches the bridge.
    func noteSourceEdit() {
        guard state == .sourceOwned else { return }
        revision += 1
        preloadedRichRevision = nil
        preloadedRichLoss = nil
        scheduler?.noteEdit()
    }

    // MARK: Undo / Redo / Formatting / Theme (U1–U3, §7.2)

    /// Routes undo to the current owner (native in HTML, `prosemirror-history` in Rich, U1).
    func undo() {
        switch state {
        case .sourceOwned:
            source.undo()
        case .richOwned:
            sendRichCommand(name: "undo")
        case .handingOffToRich, .handingOffToSource:
            break
        }
    }

    /// Routes redo to the current owner (U1).
    func redo() {
        switch state {
        case .sourceOwned:
            source.redo()
        case .richOwned:
            sendRichCommand(name: "redo")
        case .handingOffToRich, .handingOffToSource:
            break
        }
    }

    /// Sends a formatting command to Rich Text while Rich owns the buffer.
    func applyRichCommand(name: String, attrs: [String: RichEditorJSONValue] = [:]) {
        guard state == .richOwned else { return }
        sendRichCommand(name: name, attrs: attrs)
    }

    /// Pushes an updated theme to the WebView when configured (§7.2 `setTheme`).
    func updateTheme(_ theme: RichEditorTheme) {
        themeProvider = { theme }
        guard isConfigured, let transport = richTransport else { return }
        Task { [weak self] in
            do {
                try await transport.setTheme(theme)
            } catch {
                self?.logNonFatal("setTheme failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Incoming events, process death, teardown (§7.2, §7.8)

    /// Handles incoming informational JS events (§7.2).
    func handleBridgeEvent(_ event: RichEditorEvent) {
        switch event {
        case .ready:
            break
        case let .edited(jsRevision):
            guard state == .richOwned else { return }
            revision = max(revision, jsRevision)
            lastRichEditedRevision = max(lastRichEditedRevision, jsRevision)
            // §7.10 / D8: never update `mirrorDocument` on the keystroke path.
            scheduler?.noteEdit()
        case let .toolbarState(newState):
            guard state == .richOwned else { return }
            toolbarState = newState
            (richTransport as? RichEditorHost)?.syncToolbarState(newState)
            onToolbarStateSync?(newState)
        case .journal:
            // E4 persists the edit journal; part 1 accepts the event without failing.
            break
        case .caretRect:
            // Handled directly by `RichEditorHost` for native scroll-view tracking (N4).
            break
        case let .mirrorBlocks(event):
            // The page's reset can land while the hand-off into Rich Text is completing.
            guard state == .richOwned || state == .handingOffToRich else { return }
            _ = mirrorDocument.apply(event)
            if mirrorDocument.needsReset { pushMirrorVisibility() }
        case let .paste(event):
            guard state == .richOwned else { return }
            lastPaste = DraftPasteReport(sequence: (lastPaste?.sequence ?? 0) + 1, event: event)
        case let .annotationTapped(id):
            guard state == .richOwned else { return }
            lastAnnotationTap = DraftAnnotationTap(sequence: (lastAnnotationTap?.sequence ?? 0) + 1, id: id)
        case let .tkTyped(range):
            guard state == .richOwned else { return }
            lastTypedTK = DraftTypedTK(sequence: (lastTypedTK?.sequence ?? 0) + 1, range: range)
        case let .wordAtCaret(prefix):
            guard state == .richOwned else { return }
            wordAtCaret = prefix
        case let .error(code, message):
            writingEditorLog.error(
                "Rich editor JS error [\(code, privacy: .public)]: \(message, privacy: .public)"
            )
        }
    }

    /// Handles WebView content process termination per §7.8.
    func handleWebContentProcessTerminated() {
        isConfigured = false
        preloadedRichRevision = nil
        preloadedRichLoss = nil
        isShowingSwitchTransition = false

        switch state {
        case .sourceOwned:
            richTransport?.resetAfterTermination()

        case .handingOffToRich:
            // §7.8: process dies during hand-off → abort; source was only frozen, unfreeze it.
            handoffToken += 1
            pendingRichHandoff = nil
            pendingLossConfirmation = nil
            source.isFrozen = false
            state = .sourceOwned
            richTransport?.resetAfterTermination()
            noticeMessage = Self.richOpenFailedMessage

        case .richOwned, .handingOffToSource:
            // §7.8: HTML takes ownership with the last checkpoint; rich off for 60 s.
            handoffToken += 1
            pendingRichHandoff = nil
            pendingLossConfirmation = nil
            let hadUncheckpointedEdits = lastRichEditedRevision > lastCheckpointedRevision
            if source.text != lastCheckpointedText {
                source.replaceForModeHandoff(lastCheckpointedText, caretOffset: nil)
            }
            text = lastCheckpointedText
            source.isFrozen = false
            source.focus()
            state = .sourceOwned
            toolbarState = .empty
            notifyRichOwnership(false)
            richCooldownUntil = clock.now + Self.processDeathCooldown
            richTransport?.resetAfterTermination()
            noticeMessage = hadUncheckpointedEdits
                ? Self.processDeathLossWarning
                : Self.processDeathCleanFallbackMessage
        }
    }

    /// Stops timers and breaks callbacks when the editor screen leaves.
    func teardown() {
        handoffToken += 1
        scheduler?.cancel()
        scheduler = nil
        wordCountTask?.cancel()
        wordCountTask = nil
        pendingRichHandoff = nil
        pendingLossConfirmation = nil
        isShowingSwitchTransition = false
        source.isFrozen = false
        source.onEdit = nil
        richTransport?.onEvent = nil
        richTransport?.onProcessTerminated = nil
        onCheckpointText = nil
        onRecoveryError = nil
        onToolbarStateSync = nil
        onRichOwnershipChanged = nil
        (richTransport as? RichEditorHost)?.setOwnsRichUndo(false)
    }

    func notifyRichOwnership(_ ownsRich: Bool) {
        (richTransport as? RichEditorHost)?.setOwnsRichUndo(ownsRich)
        onRichOwnershipChanged?(ownsRich)
    }

    func attachTransportCallbacks(_ transport: any RichEditorBridgeTransport) {
        transport.onEvent = { [weak self] event in
            self?.handleBridgeEvent(event)
        }
        transport.onProcessTerminated = { [weak self] in
            self?.handleWebContentProcessTerminated()
        }
    }
}

extension DraftSession {
    /// Shows or hides the §7.10 HTML mirror. Showing it makes the page send every block once (a reset).
    func setMirrorVisible(_ visible: Bool) {
        guard visible != isMirrorVisible else { return }
        isMirrorVisible = visible
        pushMirrorVisibility()
    }

    /// Tells the page whether the mirror is shown (again after a reset was needed or the page was configured).
    func pushMirrorVisibility() {
        guard isConfigured, let transport = richTransport else { return }
        let enabled = isMirrorVisible
        Task { [weak self] in
            do {
                try await transport.setMirror(RichEditorMirrorArgs(enabled: enabled))
            } catch {
                self?.logNonFatal("setMirror failed: \(error.localizedDescription)")
            }
        }
    }
}
