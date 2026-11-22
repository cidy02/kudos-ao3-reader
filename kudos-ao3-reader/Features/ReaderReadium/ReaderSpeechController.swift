#if os(iOS)
import AVFoundation
import MediaPlayer
import OSLog
import ReadiumNavigator
import ReadiumShared
import SwiftUI
import UIKit

/// Read-aloud for the reader. The controller is the seam the fan-menu waveform
/// and mini player call; it extracts the current chapter's text from Readium's
/// `Publication.content(from:)` and hands it to a `TTSService`.
///
/// **Engine ladder:** `CoreMLKokoroTTSService` (FluidAudio staged Core ML
/// graphs on the Neural Engine) → `SherpaKokoroTTSService` (sherpa-onnx) →
/// `SystemTTSService` (Apple `AVSpeechSynthesizer`).
///
/// Core ML is used on **iOS 27+** only, where its pack is installed and
/// `KokoroAneHealth` has not recorded repeated synthesis crashes on this
/// device. On **iOS 26.x** the libBNNS `SIGSEGV` (FluidAudio #817/#844) makes
/// it unsafe, so Kokoro means Sherpa/ONNX there — which is why the Sherpa
/// engine and its voice-pack download are not dead weight. Selection is
/// re-checked each time speech starts.
///
/// **Audio session:** owned by the active `TTSService` (`.playback` /
/// `.spokenAudio` / long-form).
///
/// **Now Playing / Dynamic Island:** while a session is playing or paused, we
/// publish system Now Playing info + remote commands so Lock Screen / Control
/// Center / Dynamic Island can control transport. The app owns one controller;
/// leaving the reader detaches its navigator callbacks while an active session
/// keeps the publication and transport alive (requires `UIBackgroundModes=audio`).
/// Anything that can be told to stop speaking (the controller; a stub in tests).
@MainActor
protocol SpeechStoppable: AnyObject { func stop() }

/// Process-wide single speech owner: Now Playing / remote commands are global,
/// so a second reader (iPad window) starting speech stops the first.
@MainActor
final class SpeechOwnerRegistry {
    static let shared = SpeechOwnerRegistry()
    private(set) weak var owner: (any SpeechStoppable)?

    func claim(_ new: any SpeechStoppable) {
        let previous = owner
        owner = new
        if let previous, previous !== new { previous.stop() }
    }

    /// No-op unless `old` is the current owner.
    func release(_ old: any SpeechStoppable) {
        if owner === old { owner = nil }
    }
}

/// One-shot "start read aloud once the first location has settled" gate.
struct ReadAloudAutoStart {
    private(set) var fired = false

    /// True exactly once: requested, reader ready, and a location has settled.
    mutating func shouldStart(requested: Bool, isReady: Bool, settledCount: Int) -> Bool {
        guard requested, !fired, isReady, settledCount > 0 else { return false }
        fired = true
        return true
    }
}

extension ReaderSpeechController: SpeechStoppable {}

@MainActor
@Observable
final class ReaderSpeechController {
    enum Status: Equatable {
        case unavailable
        case stopped
        case playing
        case paused
    }

    private(set) var status: Status = .unavailable {
        didSet {
            guard !isAuditioning, status != oldValue, let workID = sessionWorkID else { return }
            onStatusTransition?(workID, status, isReaderOpen)
        }
    }
    /// The sentence currently being spoken, for the mini player's caption.
    private(set) var spokenText: String = ""
    /// 0…1 **smoothed** envelope for the mini-player equalizer (attack/release).
    /// Target spikes on spoken-range callbacks; this value is one-pole filtered
    /// so bars undulate like DI metering instead of staircase jumps.
    private(set) var speechEnergy: Double = 0
    /// 0…1 seed from the latest spoken fragment — varies per-bar phase.
    private(set) var speechEnergySeed: Double = 0
    /// Smoothed per-band levels for the equalizer, one entry per bar.
    /// Kokoro measures these from its own PCM; Apple infers them from the word
    /// being spoken. See `SpeechSpectrum`.
    private(set) var speechSpectrum: [Double] =
        Array(repeating: 0, count: SpeechSpectrum.bandCount)

    /// Called with each utterance's locator so the reader can page along with
    /// the voice.
    var onAdvance: ((Locator) -> Void)?
    /// Called with the exact audible word/phrase locator when an engine can
    /// provide one, or its current sentence locator otherwise.
    var onSpokenRange: ((Locator) -> Void)?
    /// Called when the active service has no current audible source range.
    var onSessionEnded: (() -> Void)?
    /// Called only when a user-initiated chapter skip (⏮/⏭) commits a replacement
    /// chapter, so manual chapter haptics never fire for failed or automatic scans.
    var onChapterSkipCommitted: (() -> Void)?
    /// Now Playing / Lock Screen previous-track — chapter skip (same as mini player).
    var onSkipPrevious: (() -> Void)?
    /// Now Playing / Lock Screen next-track — chapter skip (returns `true` if a next chapter started).
    var onSkipNext: (() -> Bool)?

    /// App-owned persistence sink. Unlike the callbacks above, this never captures
    /// a reader/navigator and stays installed while the reader is detached.
    var onSavePosition: ((
        _ workID: UUID,
        _ locatorString: String,
        _ sections: [ReaderSection],
        _ event: ReaderSpeechPositionSaveThrottle.Event,
        _ date: Date,
        _ sessionProgressStamp: Date
    ) -> ReaderSpeechPositionSaveResult)?
    /// Lets the app resume normal finished-copy cleanup after the detached
    /// controller has released the Publication that still read from that EPUB,
    /// and closes any detached reading-log sitting cleanly.
    var onReleaseDetachedWork: ((_ workID: UUID) -> Void)?
    /// Notifies the reading log when Read Aloud transitions between playing,
    /// paused, and stopped (including detached transport).
    var onStatusTransition: ((_ workID: UUID, _ status: Status, _ isReaderOpen: Bool) -> Void)?
    /// Keeps listening `activeSeconds` advancing during spoken utterances even
    /// when locked or detached (`ReadingLogService.activeGap`).
    var onPlaybackActivity: ((_ workID: UUID, _ date: Date) -> Void)?

    private var publication: Publication?
    private(set) var sessionWorkID: UUID?
    private(set) var isReaderOpen = false
    private(set) var openReaderWorkID: UUID?
    private var isAuditioning = false
    private var sections: [ReaderSection] = []
    private var chapterStartLocators: [Locator?] = []
    private var positionSaveThrottle = ReaderSpeechPositionSaveThrottle()
    private var detachedProgressStamp: Date?
    private var detachedWritesSuspended = false
    private var workEPUBChangeObserver: NSObjectProtocol?
    private var ttsService: TTSService?
    private var ttsServiceKind: ReaderTTSEngineKind?
    private var ttsServiceRuntimeConfiguration: KokoroRuntimeConfiguration?
    private let downloadManager = TTSDownloadManager.shared
    private var stoppedManually = false
    /// Whether the currently bound engine actually holds live/resumable playback
    /// (`.playing` or `.paused`), tracked separately from `status` (which stays
    /// `.playing` across chapter handoffs so Now Playing and the reading log do
    /// not flicker).
    private var enginePlaybackActive = false

    /// Which way Read Aloud looks for a speakable chapter when the one it was sent
    /// to has nothing to speak: onward for ⏭, Play and a finished chapter; back
    /// for ⏮, so skipping back never bounces forward to the chapter just left.
    enum ScanDirection: Equatable {
        case forward
        case backward
    }

    private enum DesiredPlaybackState: Equatable {
        case playing
        case paused
    }

    private struct CandidateChapter {
        let chapterStart: Locator?
        let firstLocator: Locator?
        let chapterIndex: Int?
    }

    private enum RequestStage {
        /// Scanning chapters; old engine (if any) has not been replaced yet.
        case scanning
        /// Handed a speakable candidate to the engine; waiting for its first
        /// playable utterance (or refusal / silent finish). Old playback is gone.
        case awaitingFirstOutput(CandidateChapter)
    }

    /// Single serial owner of the in-flight speech request (checked by `token`
    /// after every await). Replaces scattered pending-pause / start flags so
    /// transport changes, skips, and engine finishes cannot cross wires.
    private struct SpeechRequest {
        let token: UInt64
        let direction: ScanDirection
        let isUserInitiated: Bool
        let isManualSkip: Bool
        var desiredState: DesiredPlaybackState
        var stage: RequestStage
    }

    private var nextRequestToken: UInt64 = 0
    private var activeRequest: SpeechRequest?
    /// Token of the request the engine ended with `.unavailable`, so a throw from
    /// the same `speak` can still attach its detail to the error shown.
    private var unavailableRequestToken: UInt64?
    private var currentAuditionToken: UInt64 = 0
    /// In-flight chapter extract + `speak` so a second tap can cancel it.
    private var startTask: Task<Void, Never>?
    /// Instantaneous target (0…1); `speechEnergy` lerps toward this at ~60 fps.
    private var speechEnergyTarget: Double = 0
    /// Runs the attack/release smoother while energy is live or speaking.
    private var speechEnergySmoothTask: Task<Void, Never>?
    private var speechSpectrumTarget: [Double] =
        Array(repeating: 0, count: SpeechSpectrum.bandCount)
    /// When the last spectrum frame arrived. A *measured* source (Kokoro)
    /// streams frames continuously, so decaying between them would fight the
    /// measurement and flatten real detail; a *pulsed* source (Apple, one
    /// callback per word) needs the decay or the bars would hang at the last
    /// word's level. Rather than branch on engine identity, infer it: recent
    /// frames mean continuous, and the release takes over once they stop.
    private var lastSpectrumAt: Date?

    /// Work metadata for the system Now Playing card (title + author byline).
    private var nowPlayingTitle: String = ""
    private var nowPlayingArtist: String?
    private var concealsNowPlayingMetadata = false
    /// Total Readium positions in the open publication — drives Now Playing
    /// duration/elapsed via `ReaderTimeEstimate` (same model as the position card).
    private var totalPositionCount: Int = 0
    /// Last locator spoken or requested — remote Play after pause/stop uses this
    /// when the in-reader `toggle(from:)` call has no locator, and in-reader
    /// auto-advance uses it so skipping an unspeakable chapter never stalls on a
    /// stale navigator locator.
    private(set) var resumeLocator: Locator?
    private var remoteCommandsInstalled = false
    #if DEBUG
    private var testUnitProvider: ((Locator?) async -> [TTSSpeechUnit])?
    private var skipsEngineReplacementForTests = false
    #endif

    var isAvailable: Bool { status != .unavailable }
    /// A fresh Read Aloud start is in flight: the chapter is being found or the engine
    /// is preparing its first output, but nothing is audible yet (`status` is still
    /// `.stopped`). The fan shows Stop for it so the start can be cancelled.
    var isStartPending: Bool { status == .stopped && activeRequest != nil }
    var isPlaying: Bool { status == .playing }
    /// Mini player / fan "session on" — playing or paused, not fully stopped.
    var isSessionActive: Bool { status == .playing || status == .paused }
    /// Whether a chapter skip counts from the speech position (playing) rather than
    /// the page on screen (paused). See `ReaderSpeechSkip.origin`.
    var skipFollowsSpeechPosition: Bool { isPlaying }
    /// Set when Play, ⏭ or ⏮ in an open reader found no chapter Read Aloud can speak
    /// in that direction; the open reader of `openReaderWorkID` shows an alert saying
    /// why and clears it. Cleared on reader open/close and teardown, so it never
    /// surfaces in a later reader.
    var showsNothingToSpeakAlert = false
    private(set) var nothingToSpeakDirection: ScanDirection = .forward
    var nothingToSpeakMessage: String {
        switch nothingToSpeakDirection {
        case .forward:
            "From here to the end of this work there is no text Read Aloud can speak, "
                + "only images, symbols or scene breaks."
        case .backward:
            "From here to the start of this work there is no text Read Aloud can speak, "
                + "only images, symbols or scene breaks."
        }
    }
    /// Surfaced in the open reader when user-initiated Play / skip fails to start
    /// audio (e.g. audio session activation throws), so Play is never a dead button.
    var speechErrorMessage: String?
    var sessionTitle: String { nowPlayingTitle }

    isolated deinit {
        if let workEPUBChangeObserver {
            NotificationCenter.default.removeObserver(workEPUBChangeObserver)
        }
    }

    /// Voices the settings UI can offer (already filtered for long-form reading).
    var availableVoices: [TTSVoice] {
        ttsService?.availableVoices ?? ReaderSpeechPreferences.catalogVoices()
    }

    /// Which engine the ladder actually resolved to, for the audition harness.
    /// Nil before an engine is installed, which reads as Apple because that is
    /// what an un-prepared controller falls back to.
    var activeEngineName: String {
        ttsServiceKind?.displayName ?? ReaderTTSEngineKind.system.displayName
    }

    /// Builds the synthesizer for a publication. Returns quietly when the
    /// publication has no extractable content — the control is then disabled
    /// rather than offering playback that would do nothing.
    ///
    /// If `publication` is the same instance already prepared, this is a no-op
    /// (aside from refreshing the delegate owner) so a second `.ready` does not
    /// kill mid-chapter speech.
    ///
    /// `title` / `author` feed the system Now Playing card while a session runs.
    /// `totalPositions` is the publication's Readium position count (same source
    /// as the position card's time-left estimates) so the Island can show
    /// elapsed / remaining instead of `--:--`.
    func prepare(
        publication: Publication?,
        workID: UUID,
        title: String,
        author: String,
        totalPositions: Int,
        sections: [ReaderSection],
        chapterStartLocators: [Locator?]
    ) {
        installWorkEPUBChangeObserverIfNeeded()
        let action = ReaderSpeechSessionPolicy.openReader(
            sessionActive: isSessionActive,
            sessionWorkID: sessionWorkID,
            openingWorkID: workID
        )
        if action == .endPreviousSession {
            tearDown()
        }

        nowPlayingTitle = title
        nowPlayingArtist = author.isEmpty ? nil : author
        totalPositionCount = max(0, totalPositions)
        self.sections = sections
        self.chapterStartLocators = chapterStartLocators

        if action == .reattach {
            // The reopened reader has a new Publication instance. Keep the old
            // one and its synthesizer so the current utterance is uninterrupted;
            // compatible locators are handed to the new navigator on attach.
            return
        }

        guard let publication, publication.content() != nil else {
            tearDown()
            return
        }

        let id = ObjectIdentifier(publication)
        if self.publication.map({ ObjectIdentifier($0) }) == id, ttsService != nil {
            // Same open — keep the engine and any in-flight playback; still
            // refresh metadata in case the view re-bound.
            return
        }

        tearDown()
        // tearDown clears totalPositionCount — restore after.
        nowPlayingTitle = title
        nowPlayingArtist = author.isEmpty ? nil : author
        totalPositionCount = max(0, totalPositions)
        self.sections = sections
        self.chapterStartLocators = chapterStartLocators
        self.publication = publication
        sessionWorkID = workID

        installTTSService(for: preferredEngineKind())
        self.status = .stopped
    }

    /// Marks reader presentation immediately, before its publication finishes
    /// opening, so the app mini player cannot remain under an open reader.
    func readerDidOpen(workID: UUID) {
        let action = ReaderSpeechSessionPolicy.openReader(
            sessionActive: isSessionActive,
            sessionWorkID: sessionWorkID,
            openingWorkID: workID
        )
        if action == .endPreviousSession {
            tearDown()
        }
        openReaderWorkID = workID
        isReaderOpen = true
        showsNothingToSpeakAlert = false
        speechErrorMessage = nil
    }

    /// Installs only callbacks owned by the live navigator. A same-work reopen
    /// immediately catches the page and audible decoration up to the voice.
    func attachReader(
        workID: UUID,
        onAdvance: @escaping (Locator) -> Void,
        onSpokenRange: @escaping (Locator) -> Void,
        onSessionEnded: @escaping () -> Void,
        onChapterSkipCommitted: (() -> Void)? = nil,
        onSkipPrevious: @escaping () -> Void,
        onSkipNext: @escaping () -> Bool
    ) {
        guard openReaderWorkID == workID, sessionWorkID == workID else { return }
        resetDetachedPositionSaving()
        self.onAdvance = onAdvance
        self.onSpokenRange = onSpokenRange
        self.onSessionEnded = onSessionEnded
        self.onChapterSkipCommitted = onChapterSkipCommitted
        self.onSkipPrevious = onSkipPrevious
        self.onSkipNext = onSkipNext
        if isSessionActive, let resumeLocator {
            onAdvance(resumeLocator)
            onSpokenRange(resumeLocator)
        }
    }

    /// Active speech keeps its publication; an idle prepared controller releases it.
    @discardableResult
    func readerDidClose(workID: UUID) -> ReaderSpeechSessionPolicy.LeaveReaderAction {
        guard openReaderWorkID == workID else {
            return ReaderSpeechSessionPolicy.leaveReader(sessionActive: isSessionActive)
        }
        openReaderWorkID = nil
        isReaderOpen = false
        showsNothingToSpeakAlert = false
        speechErrorMessage = nil
        let action = ReaderSpeechSessionPolicy.leaveReader(sessionActive: isSessionActive)
        switch action {
        case .detach:
            detachedProgressStamp = Date()
            detachedWritesSuspended = false
            positionSaveThrottle.reset()
            detachReaderCallbacks()
        case .tearDown:
            tearDown()
        }
        return action
    }

    /// Root scene-phase checkpoint. Attached readers save through their existing
    /// flush path; only a detached session needs the app-owned saver.
    func saveDetachedPositionForBackground() {
        guard !isReaderOpen else { return }
        persistPosition(for: .appBackground)
    }

    func setConcealsNowPlayingMetadata(_ concealed: Bool) {
        guard concealsNowPlayingMetadata != concealed else { return }
        concealsNowPlayingMetadata = concealed
        if isSessionActive {
            reconcileTransport()
        }
    }

    /// Pushes the latest UserDefaults preferences into the live synthesizer.
    /// Rate/pitch apply on the next utterance via the engine bridge; voice
    /// changes take effect on the next utterance through `config`.
    func applyPreferences() {
        guard let ttsService else { return }
        let language = publication?.metadata.language ?? Language(code: .bcp47(Locale.current.identifier))
        let voiceID = ReaderSpeechPreferences.resolvedVoiceIdentifier(
            language: language,
            voices: ttsService.availableVoices
        )
        ttsService.setVoice(id: voiceID ?? "")
        ttsService.setRate(Float(ReaderSpeechPreferences.rateMultiplier))
        ttsService.setPitch(Float(ReaderSpeechPreferences.pitchMultiplier))
    }

    /// Applies the manual request when present; otherwise automatically uses
    /// Kokoro once its pack is on disk. Re-checked at every new playback.
    private func preferredEngineKind() -> ReaderTTSEngineKind {
        ReaderTTSEngineKind.effective(
            requestedRawValue: ReaderSpeechPreferences.engineIdentifier,
            modelDownloaded: coreMLKokoroIsUsable || resolvedKokoroRuntimeConfiguration() != nil
        )
    }

    /// Core ML Kokoro is eligible: the OS line is one where it is safe at
    /// all (iOS 27+ — see `KokoroAnePlayback`), its pack is installed, and
    /// synthesis has not repeatedly died on this device.
    private var coreMLKokoroIsUsable: Bool {
        KokoroAnePlayback.supportsCoreML()
            && KokoroAneAvailability.isUsableForPlayback
            && !KokoroAneHealth.hasAbandonedCoreML
    }

    /// Falls back to the installed Int8 pack when a requested FP32 benchmark
    /// pack has not been developer-installed yet. The user's FP32 preference
    /// remains intact, so it becomes active automatically once present.
    private func resolvedKokoroRuntimeConfiguration() -> KokoroRuntimeConfiguration? {
        KokoroRuntimeConfiguration.resolved(
            requested: ReaderSpeechPreferences.kokoroRuntimeConfiguration,
            isModelDownloaded: { [downloadManager] pack in
                downloadManager.isModelDownloaded(for: pack)
            }
        )
    }

    /// Kokoro degrades **Core ML → Sherpa/ONNX → Apple**, never Core ML →
    /// Apple. The libBNNS fault the Core ML path can hit (FluidAudio #817) is
    /// a SIGSEGV, so Sherpa is the only thing standing between a repeatedly
    /// crashing device and losing neural TTS altogether.
    private func makeTTSService(
        for kind: ReaderTTSEngineKind,
        runtimeConfiguration: KokoroRuntimeConfiguration?
    ) -> TTSService {
        switch kind {
        case .kokoro:
            if coreMLKokoroIsUsable {
                return CoreMLKokoroTTSService()
            }
            guard let runtimeConfiguration else {
                return SystemTTSService()
            }
            Log.tts.info("Kokoro falling back to Sherpa/ONNX (Core ML unavailable)")
            return SherpaKokoroTTSService(
                modelDirectory: downloadManager.modelDirectory(for: runtimeConfiguration.modelPack),
                modelPack: runtimeConfiguration.modelPack,
                executionProvider: runtimeConfiguration.executionProvider
            )
        case .system:
            return SystemTTSService()
        }
    }

    private func installTTSService(for kind: ReaderTTSEngineKind) {
        let runtimeConfiguration = kind == .kokoro && !coreMLKokoroIsUsable
            ? resolvedKokoroRuntimeConfiguration()
            : nil
        let hasAnyKokoro = coreMLKokoroIsUsable || runtimeConfiguration != nil
        let effectiveKind: ReaderTTSEngineKind = kind == .kokoro && !hasAnyKokoro
            ? .system
            : kind
        installTTSService(
            makeTTSService(for: effectiveKind, runtimeConfiguration: runtimeConfiguration),
            kind: effectiveKind,
            runtimeConfiguration: runtimeConfiguration
        )
    }

    /// Swap the bound engine if the download state changed since last start.
    /// Unbinds callbacks before `stop()` so a swap cannot auto-skip a chapter.
    private func ensureEngineForPlayback() {
        let kind = preferredEngineKind()
        let runtimeConfiguration = kind == .kokoro && !coreMLKokoroIsUsable
            ? resolvedKokoroRuntimeConfiguration()
            : nil
        guard KokoroRuntimeConfiguration.needsEngineReplacement(
            currentKind: ttsServiceKind,
            currentConfiguration: ttsServiceRuntimeConfiguration,
            requestedKind: kind,
            requestedConfiguration: runtimeConfiguration
        ) else {
            return
        }
        installTTSService(for: kind)
    }

    private func unbindTTSService(_ service: TTSService?, stop: Bool) {
        guard let service else { return }
        service.onStatusChange = nil
        service.onSpokenTextChange = nil
        service.onSpeechEnergyPulse = nil
        service.onSpeechSpectrum = nil
        service.onAudible = nil
        service.onSpokenRange = nil
        if stop {
            service.stop()
        }
    }

    private func installTTSService(
        _ service: TTSService,
        kind: ReaderTTSEngineKind,
        runtimeConfiguration: KokoroRuntimeConfiguration?
    ) {
        unbindTTSService(ttsService, stop: true)
        enginePlaybackActive = false

        service.onStatusChange = { [weak self, weak service] newStatus in
            guard let self, let service, self.ttsService === service else { return }
            self.handleEngineStatusChange(newStatus)
        }

        service.onSpokenTextChange = { [weak self, weak service] text in
            guard let self, let service, self.ttsService === service else { return }
            self.spokenText = ReaderSpeechPreferences.cleanUtteranceText(text)
        }

        service.onSpeechEnergyPulse = { [weak self, weak service] energy, seed in
            guard let self, let service, self.ttsService === service else { return }
            self.speechEnergyTarget = energy
            self.speechEnergySeed = seed
            self.startSpeechEnergySmoothingIfNeeded()
        }

        service.onSpeechSpectrum = { [weak self, weak service] spectrum in
            guard let self, let service, self.ttsService === service else { return }
            self.speechSpectrumTarget = spectrum.bands
            self.lastSpectrumAt = Date()
            // Keep the single-value envelope in step so anything still reading
            // `speechEnergy` stays correct.
            self.speechEnergyTarget = max(self.speechEnergyTarget, spectrum.level)
            self.startSpeechEnergySmoothingIfNeeded()
        }

        service.onAudible = { [weak self, weak service] locator in
            guard let self, let service, self.ttsService === service else { return }
            self.handleAudible(locator)
        }

        service.onSpokenRange = { [weak self, weak service] locator in
            guard let self, let service, self.ttsService === service else { return }
            if self.activeRequest != nil, !self.enginePlaybackActive { return }
            guard self.isSessionActive else { return }
            self.persistPosition(for: .spokenRange, locator: locator)
            self.onSpokenRange?(locator)
        }

        ttsService = service
        ttsServiceKind = kind
        ttsServiceRuntimeConfiguration = runtimeConfiguration
    }

    /// Finds the words this chapter would be guessed at, without speaking it.
    ///
    /// The pronunciation list is otherwise retrospective — a name has to be
    /// mangled once before it can be corrected. This runs the same frontend
    /// over the same chapter text and records the same fallbacks, so the list
    /// is populated before the first tap.
    ///
    /// - Returns: what the scan found, or the reason it could not run.
    ///
    /// A `Result` rather than an optional because the causes are genuinely
    /// different and the reader can act on some of them — stopping Read Aloud
    /// is a fix, a pack that will not compile is not. Collapsing them into
    /// `nil` produced one unactionable "Could not scan this chapter".
    func scanChapterForPronunciation(
        from locator: Locator?
    ) async -> Result<KokoroCastPreflight.ScanResult, Error> {
        guard let publication else {
            Log.tts.error("Pre-flight found no prepared publication")
            return .failure(KokoroCastPreflight.ScanError.unavailable)
        }
        guard KokoroCastPreflight.isAvailable else {
            return .failure(KokoroCastPreflight.ScanError.unavailable)
        }
        let units = await Self.chapterUnits(
            from: locator ?? resumeLocator, in: publication
        )
        guard !units.isEmpty else {
            Log.tts.error("Pre-flight found no extractable text in the current chapter")
            return .failure(KokoroCastPreflight.ScanError.noText)
        }
        do {
            // `.paused` counts: playback installed the observer at `speak()`
            // and still owns it, so a scan would clear it and the rest of the
            // session would record nothing. Only a stopped session has no
            // claim on it.
            return .success(try await KokoroCastPreflight.scan(
                texts: units.map(\.text),
                isPlaying: status == .playing || status == .paused
            ))
        } catch {
            return .failure(error)
        }
    }

    /// The current chapter's text, as speech units.
    ///
    /// Uses a single-resource `HTMLResourceContentIterator` when possible so an
    /// empty XHTML chapter yields `[]` immediately instead of letting Readium's
    /// `PublicationContentIterator` walk forward into later resources (which broke
    /// Skip Back and re-parsed empty runs quadratically). Shared by playback and
    /// the pronunciation pre-flight so the two cannot disagree about boundaries.
    private static func chapterUnits(
        from startLoc: Locator?,
        in publication: Publication
    ) async -> [TTSSpeechUnit] {
        if let iterator = await resourceScopedIterator(from: startLoc, in: publication) {
            return await extractUnits(from: iterator, expectedHREF: nil)
        }
        guard let content = publication.content(from: startLoc) else {
            Log.tts.error("Publication has no ContentService — cannot extract read-aloud text")
            return []
        }
        return await extractUnits(from: content.iterator(), expectedHREF: startLoc?.href)
    }

    private static func resourceScopedIterator(
        from startLoc: Locator?,
        in publication: Publication
    ) async -> ContentIterator? {
        guard !publication.readingOrder.isEmpty else { return nil }
        let index: Int? = if let startLoc {
            readingOrderIndex(for: startLoc.href, in: publication)
        } else {
            0
        }
        guard let index, publication.readingOrder.indices.contains(index) else { return nil }
        let link = publication.readingOrder[index]
        guard let resource = publication.get(link) else { return nil }

        let locator: Locator?
        if let startLoc {
            if startLoc.mediaType.isHTML {
                locator = startLoc
            } else if let linkType = link.mediaType, linkType.isHTML {
                locator = Locator(
                    href: startLoc.href,
                    mediaType: linkType,
                    title: startLoc.title,
                    locations: startLoc.locations,
                    text: startLoc.text
                )
            } else {
                locator = startLoc
            }
        } else {
            locator = await publication.locate(link)
        }
        guard let locator else { return nil }
        return HTMLResourceContentIterator.Factory().make(
            publication: publication,
            readingOrderIndex: index,
            resource: resource,
            locator: locator
        )
    }

    private static func readingOrderIndex(for href: AnyURL, in publication: Publication) -> Int? {
        let stripped = href.removingQuery().removingFragment()
        if let direct = publication.readingOrder.firstIndexWithHREF(stripped) {
            return direct
        }
        if let direct = publication.readingOrder.firstIndexWithHREF(href) {
            return direct
        }
        let key = ReaderSectionBuilder.hrefKey(href.string)
        return publication.readingOrder.firstIndex {
            ReaderSectionBuilder.hrefKey($0.href) == key
        }
    }

    private static func hrefsMatch(_ lhs: AnyURL, _ rhs: AnyURL) -> Bool {
        let left = lhs.removingQuery().removingFragment()
        let right = rhs.removingQuery().removingFragment()
        if left.isEquivalentTo(right) { return true }
        return ReaderSectionBuilder.hrefKey(left.string) == ReaderSectionBuilder.hrefKey(right.string)
    }

    private static func extractUnits(
        from iterator: ContentIterator,
        expectedHREF: AnyURL?
    ) async -> [TTSSpeechUnit] {
        var chapterHref: AnyURL? = expectedHREF
        var units: [TTSSpeechUnit] = []
        while !Task.isCancelled {
            let element: ContentElement?
            do {
                element = try await iterator.next()
            } catch {
                break
            }
            guard let element else { break }
            if let chapterHref {
                if !hrefsMatch(element.locator.href, chapterHref) { break }
            } else {
                chapterHref = element.locator.href
            }
            guard let textElement = element as? TextualContentElement else { continue }

            // Use Readium's normalized text for synthesis. The locator
            // quote preserves raw XHTML whitespace, which must stay out
            // of the sentence chunker or pretty-printed markup can
            // create a false paragraph boundary mid-sentence.
            guard let text = textElement.text,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }

            units.append(TTSSpeechUnit(text: text, locator: textElement.locator))
        }
        return Task.isCancelled ? [] : units
    }

    /// Starts at `locator` (normally the reader's current position) or resumes
    /// where it left off. Walks only one spine resource at a time in `direction`
    /// until it finds speakable text, and only moves the reader (`onAdvance`) and
    /// updates `resumeLocator` once the engine confirms its first playable output.
    private func startSpeechRequest(
        from locator: Locator?,
        direction: ScanDirection = .forward,
        desiredState: DesiredPlaybackState = .playing,
        isUserInitiated: Bool = true,
        isManualSkip: Bool = false
    ) {
        #if DEBUG
        let hasContentSource = publication != nil || testUnitProvider != nil
        #else
        let hasContentSource = publication != nil
        #endif
        guard hasContentSource else { return }
        isAuditioning = false
        if isUserInitiated {
            showsNothingToSpeakAlert = false
            speechErrorMessage = nil
        }
        // The request being replaced already handed its chapter to the engine, which
        // is still preparing its first output. That engine belongs to no request any
        // more: left running it would speak, move the page and save the position
        // behind the new request's back (and survive a failed scan). A request that
        // already committed is audible playback, not this, and is left to carry on
        // until the replacement commits.
        if let previous = activeRequest, case .awaitingFirstOutput = previous.stage {
            stopEngineSilently()
        }
        SpeechOwnerRegistry.shared.claim(self)
        let startLoc = locator ?? resumeLocator
        #if DEBUG
        if !skipsEngineReplacementForTests { ensureEngineForPlayback() }
        #else
        ensureEngineForPlayback()
        #endif
        applyPreferences()

        nextRequestToken &+= 1
        let token = nextRequestToken
        let request = SpeechRequest(
            token: token,
            direction: direction,
            isUserInitiated: isUserInitiated,
            isManualSkip: isManualSkip,
            desiredState: desiredState,
            stage: .scanning
        )
        launchSpeechRequest(request, from: startLoc)
    }

    private func launchSpeechRequest(_ request: SpeechRequest, from startLoc: Locator?) {
        activeRequest = request
        reconcileTransport() // starting: remote targets live so Pause/Play reach it
        startTask?.cancel()
        let token = request.token
        startTask = Task {
            do {
                guard let found = await speakableChapter(from: startLoc, direction: request.direction) else {
                    Log.tts.error("No speakable text in requested direction")
                    guard !Task.isCancelled, let current = activeRequest, current.token == token else { return }
                    handleNothingToSpeak(current)
                    return
                }
                guard !Task.isCancelled, var current = activeRequest, current.token == token else { return }

                stoppedManually = false
                // Re-check after chapter extract so a download that finished
                // while we were walking the spine is used for this tap.
                #if DEBUG
                if !skipsEngineReplacementForTests { ensureEngineForPlayback() }
                #else
                ensureEngineForPlayback()
                #endif
                applyPreferences()

                let candidate = CandidateChapter(
                    chapterStart: found.start,
                    firstLocator: found.units.first?.locator ?? found.start,
                    chapterIndex: chapterIndex(of: found.start ?? found.units.first?.locator)
                )
                current.stage = .awaitingFirstOutput(candidate)
                activeRequest = current
                // `speak(units:)` resets any previous engine playback before starting.
                enginePlaybackActive = false

                guard let service = ttsService else {
                    handleSpeakFailure(for: current, error: nil)
                    return
                }
                let started = try await service.speak(units: found.units)
                guard !Task.isCancelled, ttsService === service else { return }
                guard let latest = activeRequest, latest.token == token else { return }
                if !started {
                    handleUnplayableCandidate(latest, candidate: candidate)
                } else if latest.desiredState == .paused, service.status == .playing {
                    // Paused skip: hold the engine *before* it announces anything, so
                    // the page and the saved position only move once Play resumes it
                    // and speech at the new position actually starts.
                    service.pause()
                }
            } catch {
                Log.tts.error("speak() failed: \(error.localizedDescription, privacy: .public)")
                if unavailableRequestToken == token {
                    // Engine went `.unavailable` and then threw: the controller has
                    // already ended the request; only add the reason.
                    unavailableRequestToken = nil
                    if isReaderOpen, speechErrorMessage != nil {
                        let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        if !detail.isEmpty { speechErrorMessage = detail }
                    }
                    return
                }
                guard !Task.isCancelled, let current = activeRequest, current.token == token else { return }
                handleSpeakFailure(for: current, error: error)
            }
        }
    }

    /// THE commit point. The engine reports that audio for `locator` is audible now;
    /// this is the only place the page moves and the reading position is saved. A
    /// pending request is promoted here; later ranges of committed playback move the
    /// page the same way. Anything from an engine with no committed audio (a
    /// superseded start, a stopped session) is ignored.
    private func handleAudible(_ locator: Locator) {
        if let request = activeRequest {
            if case .awaitingFirstOutput(let candidate) = request.stage {
                if let index = candidate.chapterIndex, let heard = chapterIndex(of: locator), heard != index {
                    // A start heard from the run this request replaced (drained as it was
                    // cleared): keep what was heard, but it is not this request's output.
                    resumeLocator = locator
                    persistPosition(for: .utteranceBoundary)
                    return
                }
                commitPendingRequest(request, locator: locator)
                return
            }
            if !enginePlaybackActive { return }
        }
        guard isSessionActive else { return }
        resumeLocator = locator
        persistPosition(for: .utteranceBoundary)
        guard status != .unavailable, ttsService != nil else { return }
        onAdvance?(locator)
    }

    private func commitPendingRequest(_ request: SpeechRequest, locator: Locator?) {
        guard activeRequest?.token == request.token else { return }
        activeRequest = nil
        enginePlaybackActive = true

        if let locator {
            resumeLocator = locator
            persistPosition(for: .utteranceBoundary)
            // The save may have ended the session (`.endSession` tears it down and
            // releases the engine): nothing below may revive it.
            guard status != .unavailable, ttsService != nil else { return }
            onAdvance?(locator)
        }
        if request.isManualSkip {
            onChapterSkipCommitted?()
        }

        switch request.desiredState {
        case .playing:
            status = .playing
            reconcileTransport()
        case .paused:
            if ttsService?.status == .playing {
                ttsService?.pause()
            }
            if status != .paused {
                status = .paused
                clearSpeechEnergy()
                reconcileTransport()
            }
        }
    }

    /// Engine refused a candidate or finished it with zero audio before emitting a
    /// playable utterance. Continues searching in `request.direction` without moving
    /// the reader or touching `resumeLocator`.
    private func handleUnplayableCandidate(_ request: SpeechRequest, candidate: CandidateChapter) {
        if status == .unavailable {
            activeRequest = nil
            enginePlaybackActive = false
            return
        }
        if let next = nextChapterStart(from: candidate, direction: request.direction) {
            var continued = request
            continued.stage = .scanning
            launchSpeechRequest(continued, from: next)
            return
        }
        handleNothingToSpeak(request)
    }

    private func handleSpeakFailure(for request: SpeechRequest, error: Error?) {
        activeRequest = nil
        enginePlaybackActive = false
        stopEngineSilently()
        endSessionAfterSilentStop()
        if !isSessionActive {
            // A fresh start never published Now Playing but did register the remote
            // targets; nothing is left for them to control.
            reconcileTransport()
        }
        if request.isUserInitiated, isReaderOpen {
            let detail = (error as? LocalizedError)?.errorDescription ?? error?.localizedDescription
            speechErrorMessage = (detail?.isEmpty == false)
                ? detail
                : "Read Aloud could not start audio playback."
        }
    }

    /// One chapter's speech units: the test seam's, else the publication's.
    private func units(at locator: Locator?) async -> [TTSSpeechUnit] {
        #if DEBUG
        if let testUnitProvider { return await testUnitProvider(locator) }
        #endif
        guard let publication else { return [] }
        return await Self.chapterUnits(from: locator, in: publication)
    }

    /// Whether any unit has a letter or digit in it — the rule every engine applies
    /// (`TTSSpeechUnit.hasSpeakableText`), checked before handing an engine a
    /// chapter, so symbols-only chapters never reach one (Kokoro would "play" them
    /// silently and report a natural finish).
    static func isSpeakable(_ units: [TTSSpeechUnit]) -> Bool {
        units.contains(where: \.hasSpeakableText)
    }

    /// The chapter to speak: `locator`'s own when it has speakable text, else the
    /// first chapter after (or before) it in `direction` that does. `moved` is true
    /// when it is not `locator`'s chapter.
    private func speakableChapter(
        from locator: Locator?,
        direction: ScanDirection
    ) async -> (start: Locator?, units: [TTSSpeechUnit], moved: Bool)? {
        let own = await units(at: locator)
        if Task.isCancelled { return nil }
        if Self.isSpeakable(own) { return (locator, own, false) }
        guard let index = chapterIndex(of: locator) else { return nil }
        let candidates: [Int] = direction == .forward
            ? Array(chapterStartLocators.indices.dropFirst(index + 1))
            : Array((0..<index).reversed())
        for candidate in candidates {
            if Task.isCancelled { return nil }
            guard let start = chapterStartLocators[candidate] else { continue }
            let found = await units(at: start)
            if Task.isCancelled { return nil }
            if Self.isSpeakable(found) { return (start, found, true) }
        }
        return nil
    }

    /// `locator`'s chapter in `chapterStartLocators`, matched by normalized href.
    private func chapterIndex(of locator: Locator?) -> Int? {
        guard let locator else { return nil }
        let stripped = locator.href.removingQuery().removingFragment()
        if let exact = chapterStartLocators.firstIndex(where: {
            $0.map { $0.href.removingQuery().removingFragment().isEquivalentTo(stripped) } ?? false
        }) {
            return exact
        }
        let key = ReaderSectionBuilder.hrefKey(locator.href.string)
        return chapterStartLocators.firstIndex {
            $0.map { ReaderSectionBuilder.hrefKey($0.href.string) == key } ?? false
        }
    }

    /// Nothing speakable from where `request` asked to the end (or start) of the
    /// work. The reader has not moved and `resumeLocator` was never modified.
    /// Old playback still holding the session carries on where it was; if the
    /// engine has no live playback, the session ends cleanly.
    private func handleNothingToSpeak(_ request: SpeechRequest) {
        activeRequest = nil
        if isSessionActive, !enginePlaybackActive {
            endSessionAfterSilentStop()
        }
        if !isSessionActive {
            // Nothing is playing and nothing will: no card, no remote targets (a
            // still-playing committed chapter keeps both).
            reconcileTransport()
        }
        if request.isUserInitiated, isReaderOpen {
            nothingToSpeakDirection = request.direction
            showsNothingToSpeakAlert = true
        }
    }

    /// Stops the engine without letting its `.stopped` callback auto-advance.
    private func stopEngineSilently() {
        let wasStoppedManually = stoppedManually
        stoppedManually = true
        ttsService?.stop()
        stoppedManually = wasStoppedManually
        enginePlaybackActive = false
    }

    /// Ends an active session whose engine is (or has just been made) silent.
    private func endSessionAfterSilentStop() {
        enginePlaybackActive = false
        spokenText = ""
        if status == .paused || status == .playing {
            onSessionEnded?()
            status = ttsService == nil ? .unavailable : .stopped
            clearSpeechEnergy()
            reconcileTransport()
        }
        if !isReaderOpen { releasePreparedSession() }
    }

    func toggle(from locator: Locator?) {
        guard ttsService != nil else { return }
        applyPreferences()
        switch status {
        case .unavailable:
            return
        case .playing:
            pause()
        case .paused:
            resumeFromPaused(fallbackLocator: locator)
        case .stopped:
            if activeRequest != nil {
                // A start is already in flight. A paused engine (audio interruption
                // before its first output) is resumed; otherwise a second tap is a
                // cancel, never a second start racing the first.
                if resumePendingRequestIfPaused() { return }
                stop()
                return
            }
            startSpeechRequest(
                from: locator ?? resumeLocator,
                direction: .forward,
                desiredState: .playing,
                isUserInitiated: true,
                isManualSkip: false
            )
        }
    }

    /// Play for a request whose engine was paused (an audio interruption) before it
    /// produced its first output. The engine's own `.playing` is held back until the
    /// commit, so only the engine and the request's intent change here.
    @discardableResult
    private func resumePendingRequestIfPaused() -> Bool {
        guard var request = activeRequest,
              case .awaitingFirstOutput = request.stage,
              ttsService?.status == .paused
        else { return false }
        request.desiredState = .playing
        activeRequest = request
        ttsService?.resume()
        return true
    }

    private func resumeFromPaused(fallbackLocator: Locator?) {
        if var request = activeRequest {
            request.desiredState = .playing
            activeRequest = request
            if enginePlaybackActive, case .scanning = request.stage {
                ttsService?.resume()
            } else {
                // An audio interruption can pause the replacement engine before its
                // first output; flipping only the controller to `.playing` would
                // leave it held at its pause gate under a Pause button.
                resumePendingRequestIfPaused()
                // Resuming can end the session synchronously (the engine failed to
                // restart and reported `.unavailable`, which also released a detached
                // session): never write `.playing` over that.
                guard status != .unavailable, ttsService != nil else { return }
                status = .playing
                reconcileTransport()
            }
            return
        }
        if enginePlaybackActive {
            ttsService?.resume()
        } else {
            startSpeechRequest(
                from: fallbackLocator ?? resumeLocator,
                direction: .forward,
                desiredState: .playing,
                isUserInitiated: true,
                isManualSkip: false
            )
        }
    }

    /// Speaks a one-off sample under the current settings, with no publication
    /// open — the settings audition harness. Quality here is judged by ear, and
    /// this is the only way to compare two settings without reading a whole
    /// chapter.
    ///
    /// Deliberately does **not** install remote commands or publish Now Playing:
    /// a few seconds of preview in Settings must not take over the Lock Screen
    /// and Control Center transport, which is reader-session scoped.
    func audition(text: String) {
        activeRequest = nil
        nextRequestToken &+= 1
        currentAuditionToken &+= 1
        let auditionToken = currentAuditionToken
        startTask?.cancel()
        isAuditioning = true
        stoppedManually = false
        #if DEBUG
        if !skipsEngineReplacementForTests { ensureEngineForPlayback() }
        #else
        ensureEngineForPlayback()
        #endif
        applyPreferences()
        guard let service = ttsService else {
            status = .unavailable
            isAuditioning = false
            return
        }
        let unit = TTSSpeechUnit(text: text, locator: nil)
        startTask = Task { [weak self] in
            do {
                let started = try await service.speak(units: [unit])
                guard let self, !Task.isCancelled, self.currentAuditionToken == auditionToken,
                      self.ttsService === service
                else { return }
                if !started {
                    self.isAuditioning = false
                }
            } catch {
                Log.tts.error(
                    "Audition failed: \(error.localizedDescription, privacy: .public)"
                )
                guard let self, !Task.isCancelled, self.currentAuditionToken == auditionToken,
                      self.ttsService === service
                else { return }
                self.status = .stopped
                self.isAuditioning = false
            }
        }
    }

    func stop() {
        isAuditioning = false
        if isSessionActive {
            persistPosition(for: .stop)
        }
        let releasesPublication = !isReaderOpen && publication != nil
        SpeechOwnerRegistry.shared.release(self)
        // Stop the engine first, while the request is still live: a start the engine
        // had already confirmed audible is drained into `handleAudible` as it stops, so
        // a heard position survives Stop.
        stoppedManually = true
        ttsService?.stop()
        activeRequest = nil
        nextRequestToken &+= 1
        currentAuditionToken &+= 1
        speechErrorMessage = nil
        enginePlaybackActive = false
        startTask?.cancel()
        startTask = nil
        status = ttsService == nil ? .unavailable : .stopped
        spokenText = ""
        clearSpeechEnergy()
        // Stopped: `reconcileTransport` drops the card and the remote targets (no
        // ghost Play/Skip aimed at a dead session); the next start re-adds them.
        reconcileTransport()
        if releasesPublication {
            releasePreparedSession()
        }
    }

    /// Pause without ending the session (hold-to-seek while scrubbing).
    func pause() {
        persistPosition(for: .pause)
        if var request = activeRequest {
            request.desiredState = .paused
            activeRequest = request
        }
        var awaitingFirstOutput = false
        if let request = activeRequest, case .awaitingFirstOutput = request.stage {
            awaitingFirstOutput = true
        }
        if enginePlaybackActive || awaitingFirstOutput {
            // An engine still preparing its first output must be held too, or it
            // announces (moves the page, saves the position) under a paused UI.
            ttsService?.pause()
        }
        if !enginePlaybackActive, activeRequest != nil, status == .playing {
            status = .paused
            reconcileTransport()
        }
        clearSpeechEnergy()
    }

    /// Move the speech cursor to `locator` after a chapter skip or seek release.
    /// - Parameter resumePlaying: if true, start speaking; if false but a session
    ///   was active, start then immediately pause so Play resumes from the new spot.
    /// - Parameter direction: where to look if `locator`'s chapter has nothing to
    ///   speak (`.backward` for ⏮).
    /// - Parameter isManualSkip: true for user-tapped ⏭/⏮ so the chapter haptic
    ///   fires only once a speakable chapter commits.
    func reanchor(
        to locator: Locator?,
        resumePlaying: Bool,
        direction: ScanDirection = .forward,
        isManualSkip: Bool = false
    ) {
        guard ttsService != nil, status != .unavailable else { return }

        applyPreferences()

        if resumePlaying {
            startSpeechRequest(
                from: locator,
                direction: direction,
                desiredState: .playing,
                isUserInitiated: true,
                isManualSkip: isManualSkip
            )
        } else if isSessionActive {
            startSpeechRequest(
                from: locator,
                direction: direction,
                desiredState: .paused,
                isUserInitiated: true,
                isManualSkip: isManualSkip
            )
        }
    }

    /// Updates the resume point during hold-to-seek without touching playback.
    func noteSeekLocator(_ locator: Locator?) {
        resumeLocator = locator
    }

    /// Full teardown used for an idle reader close or switching publications.
    /// Active speech normally uses `readerDidClose(workID:)` and detaches instead.
    func tearDown() {
        if isSessionActive {
            persistPosition(for: .sessionEnd)
        }
        SpeechOwnerRegistry.shared.release(self)
        activeRequest = nil
        nextRequestToken &+= 1
        currentAuditionToken &+= 1
        showsNothingToSpeakAlert = false
        speechErrorMessage = nil
        stoppedManually = true
        enginePlaybackActive = false
        startTask?.cancel()
        startTask = nil
        onSessionEnded?()
        onAdvance = nil
        onSpokenRange = nil
        onSessionEnded = nil
        onChapterSkipCommitted = nil
        onSkipPrevious = nil
        onSkipNext = nil
        unbindTTSService(ttsService, stop: true)
        releasePreparedSession()
        reconcileTransport()
    }

    private func detachReaderCallbacks() {
        onAdvance = nil
        onSpokenRange = nil
        onSessionEnded = nil
        onChapterSkipCommitted = nil
        onSkipPrevious = nil
        onSkipNext = nil
    }

    private func releasePreparedSession() {
        let releasedWorkID = sessionWorkID
        SpeechOwnerRegistry.shared.release(self)
        activeRequest = nil
        nextRequestToken &+= 1
        enginePlaybackActive = false
        clearSpeechEnergy()
        unbindTTSService(ttsService, stop: status != .unavailable)
        ttsService = nil
        ttsServiceKind = nil
        ttsServiceRuntimeConfiguration = nil
        publication = nil
        sessionWorkID = nil
        sections = []
        chapterStartLocators = []
        resumeLocator = nil
        nowPlayingTitle = ""
        nowPlayingArtist = nil
        concealsNowPlayingMetadata = false
        totalPositionCount = 0
        spokenText = ""
        resetDetachedPositionSaving()
        status = .unavailable
        reconcileTransport()
        if !isReaderOpen, let releasedWorkID {
            onReleaseDetachedWork?(releasedWorkID)
        }
    }

    private func persistPosition(
        for event: ReaderSpeechPositionSaveThrottle.Event,
        locator: Locator? = nil,
        at date: Date = Date()
    ) {
        if !isAuditioning, let workID = sessionWorkID, status == .playing {
            onPlaybackActivity?(workID, date)
        }
        guard !isReaderOpen,
              !detachedWritesSuspended,
              let workID = sessionWorkID,
              let detachedProgressStamp,
              let locatorString = (locator ?? resumeLocator)?.persistenceString,
              positionSaveThrottle.shouldSave(locatorString: locatorString, for: event)
        else { return }
        guard let result = onSavePosition?(
            workID,
            locatorString,
            sections,
            event,
            date,
            detachedProgressStamp
        ) else { return }
        switch result {
        case .wrote(let progressStamp):
            self.detachedProgressStamp = progressStamp
            positionSaveThrottle.didSave(for: event)
        case .endSession:
            detachedWritesSuspended = true
            tearDown()
        case .suspendWrites:
            detachedWritesSuspended = true
        }
    }

    private func resetDetachedPositionSaving() {
        detachedProgressStamp = nil
        detachedWritesSuspended = false
        positionSaveThrottle.reset()
    }

    private func installWorkEPUBChangeObserverIfNeeded() {
        guard workEPUBChangeObserver == nil else { return }
        workEPUBChangeObserver = NotificationCenter.default.addObserver(
            forName: .kudosWorkEPUBWillChange,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self,
                      let workID = notification.object as? UUID,
                      workID == self.sessionWorkID
                else { return }
                self.detachedWritesSuspended = true
                self.tearDown()
            }
        }
    }

    private func requestNextChapter() -> Bool {
        if isReaderOpen, let onSkipNext {
            return onSkipNext()
        }
        return skipDetachedChapter(forward: true)
    }

    /// The first position of the chapter after `locator`'s, if there is one.
    private func nextChapterStart(after locator: Locator?) -> Locator? {
        guard let index = chapterIndex(of: locator) else { return nil }
        return chapterStartLocators.dropFirst(index + 1).lazy.compactMap { $0 }.first
    }

    /// The next chapter start in `direction` after `candidate`, used when an engine
    /// rejects or finishes a candidate with zero audio before its first utterance.
    private func nextChapterStart(from candidate: CandidateChapter, direction: ScanDirection) -> Locator? {
        guard let index = candidate.chapterIndex ?? chapterIndex(of: candidate.chapterStart) else {
            return nil
        }
        switch direction {
        case .forward:
            return chapterStartLocators.dropFirst(index + 1).lazy.compactMap { $0 }.first
        case .backward:
            return chapterStartLocators[..<index].reversed().lazy.compactMap { $0 }.first
        }
    }

    #if DEBUG
    /// Test seam: seeds controller state without initializing an audio engine or Readium publication.
    func seedSessionForTests(
        workID: UUID,
        status: Status,
        isReaderOpen: Bool,
        isAuditioning: Bool = false,
        withSystemEngine: Bool = false,
        ttsService customService: TTSService? = nil,
        unitProvider: ((Locator?) async -> [TTSSpeechUnit])? = nil,
        resumeLocator: Locator? = nil,
        chapterStartLocators: [Locator?] = [],
        onSkipNext: (() -> Bool)? = nil
    ) {
        self.startTask?.cancel()
        self.startTask = nil
        self.activeRequest = nil
        self.isAuditioning = true
        if let customService {
            self.skipsEngineReplacementForTests = true
            installTTSService(customService, kind: .system, runtimeConfiguration: nil)
        } else if withSystemEngine, ttsService == nil {
            installTTSService(SystemTTSService(), kind: .system, runtimeConfiguration: nil)
        }
        self.testUnitProvider = unitProvider
        self.sessionWorkID = workID
        self.isReaderOpen = isReaderOpen
        self.openReaderWorkID = isReaderOpen ? workID : nil
        self.resumeLocator = resumeLocator
        self.chapterStartLocators = chapterStartLocators
        self.stoppedManually = false
        self.enginePlaybackActive = (status == .playing || status == .paused)
        self.showsNothingToSpeakAlert = false
        self.nothingToSpeakDirection = .forward
        self.speechErrorMessage = nil
        self.status = status
        self.onSkipNext = onSkipNext
        self.isAuditioning = isAuditioning
    }

    /// Awaits the current in-flight `startSpeechRequest` / `audition` task (and any
    /// chained continuation task it spawned) so unit tests exercise real async wiring.
    func waitForStartTaskForTests() async {
        while let task = startTask {
            await task.value
            if startTask == task {
                break
            }
        }
    }

    var remoteCommandsInstalledForTests: Bool { remoteCommandsInstalled }

    /// Test seam: invokes the Lock Screen / Now Playing Play handler directly.
    @discardableResult
    func handleRemotePlayForTests() -> MPRemoteCommandHandlerStatus {
        handleRemotePlay()
    }

    /// Test seam: invokes the Lock Screen / Now Playing Pause handler directly.
    @discardableResult
    func handleRemotePauseForTests() -> MPRemoteCommandHandlerStatus {
        handleRemotePause()
    }
    #endif

    /// Processes a speech-engine status transition without splitting continuous
    /// chapter auto-advance into separate `.stopped` -> `.playing` visits.
    func handleEngineStatusChange(_ newStatus: TTSServiceStatus) {
        if isAuditioning {
            switch newStatus {
            case .unavailable:
                status = .unavailable
                isAuditioning = false
            case .stopped:
                status = .stopped
                isAuditioning = false
                clearSpeechEnergy()
            case .playing:
                status = .playing
            case .paused:
                status = .paused
                clearSpeechEnergy()
            }
            return
        }

        switch newStatus {
        case .unavailable:
            let failed = activeRequest
            activeRequest = nil
            nextRequestToken &+= 1
            startTask?.cancel()
            startTask = nil
            enginePlaybackActive = false
            status = .unavailable
            persistPosition(for: .sessionEnd)
            onSessionEnded?()
            // Attached or detached, there is no session left: drop the Lock Screen
            // card and its remote targets (a detached release does it too).
            reconcileTransport()
            if let failed {
                // The engine can report `.unavailable` and then throw from the same
                // `speak`; that throw lands after the request is gone, so the reader
                // is told here (and the throw's detail upgrades it).
                unavailableRequestToken = failed.token
                if failed.isUserInitiated, isReaderOpen {
                    speechErrorMessage = "Read Aloud could not start audio playback."
                }
            }
            if publication != nil, !isReaderOpen {
                releasePreparedSession()
            }
        case .stopped:
            enginePlaybackActive = false
            guard !stoppedManually else { return }

            // If a replacement candidate ended with zero audio before emitting a
            // playable utterance (e.g. Kokoro on an unrenderable chapter), continue
            // scanning in the request's own direction without moving the reader.
            if let request = activeRequest {
                switch request.stage {
                case .awaitingFirstOutput(let candidate):
                    handleUnplayableCandidate(request, candidate: candidate)
                    return
                case .scanning:
                    // Old chapter finished naturally while a scan is in flight.
                    // Keep the in-flight request (user skip or auto-advance)
                    // running instead of cancelling it to start a new forward scan.
                    persistPosition(for: .sessionEnd)
                    onSessionEnded?()
                    return
                }
            }

            // Only auto-advance when a playing chapter actually finished.
            let shouldContinue = status == .playing
            persistPosition(for: .sessionEnd)
            onSessionEnded?()
            if shouldContinue, let next = nextChapterStart(after: resumeLocator) {
                // Keep `status == .playing` across chapters so continuous Read Aloud
                // logs one sitting and Now Playing does not flicker. The chapter is
                // found (and the page moved) inside `startSpeechRequest`, never ahead of it.
                startSpeechRequest(
                    from: next,
                    direction: .forward,
                    desiredState: .playing,
                    isUserInitiated: false,
                    isManualSkip: false
                )
                return
            }
            status = .stopped
            clearSpeechEnergy()
            reconcileTransport()
            if !isReaderOpen {
                releasePreparedSession()
            }
        case .playing:
            if let request = activeRequest, case .awaitingFirstOutput = request.stage {
                // Wait for the first playable utterance before exposing `.playing`
                // (avoids unpausing a paused skip or flashing `.playing` on failure).
                return
            }
            enginePlaybackActive = true
            status = .playing
            reconcileTransport()
        case .paused:
            if var request = activeRequest {
                request.desiredState = .paused
                activeRequest = request
                if case .awaitingFirstOutput = request.stage {
                    if status == .playing {
                        status = .paused
                        clearSpeechEnergy()
                        reconcileTransport()
                    }
                    return
                }
            }
            enginePlaybackActive = true
            status = .paused
            clearSpeechEnergy()
            reconcileTransport()
        }
    }

    private func requestPreviousChapter() -> Bool {
        if isReaderOpen, let onSkipPrevious {
            onSkipPrevious()
            return true
        }
        return skipDetachedChapter(forward: false)
    }

    /// Detached fallback for auto-advance and Lock Screen chapter controls.
    /// Locators come from the publication's reading-order position lists, so no
    /// navigator or view-owned `ReadiumBook` is retained.
    private func skipDetachedChapter(forward: Bool) -> Bool {
        guard !isReaderOpen, !chapterStartLocators.isEmpty else { return false }
        let currentIndex = resumeLocator.flatMap { locator in
            let key = ReaderSectionBuilder.hrefKey(locator.href.string)
            return chapterStartLocators.firstIndex {
                $0.map { ReaderSectionBuilder.hrefKey($0.href.string) == key } ?? false
            }
        } ?? 0
        let targetIndex: Int
        if forward {
            targetIndex = currentIndex + 1
        } else if currentIndex > 0 {
            targetIndex = currentIndex - 1
        } else {
            guard (resumeLocator?.locations.progression ?? 0) > 0 else { return false }
            targetIndex = 0
        }
        guard chapterStartLocators.indices.contains(targetIndex),
              let target = chapterStartLocators[targetIndex]
        else { return false }
        reanchor(to: target, resumePlaying: isPlaying, direction: forward ? .forward : .backward)
        return true
    }

    private func startSpeechEnergySmoothingIfNeeded() {
        guard speechEnergySmoothTask == nil else { return }
        speechEnergySmoothTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 16_000_000) // ~60 fps
                guard !Task.isCancelled else { return }

                // Ease target down so energy falls during real silence between pulses.
                // Slightly snappier than a pure DI-smooth release — still smooth, less lag.
                // Only decay a *pulsed* source. A measured spectrogram is
                // already arriving ~30x a second and decaying between frames
                // would erase the detail we measured it for.
                let streaming = self.lastSpectrumAt.map {
                    Date().timeIntervalSince($0) < 0.12
                } ?? false
                if !streaming {
                    self.speechEnergyTarget *= 0.90
                    self.speechSpectrumTarget = self.speechSpectrumTarget.map { $0 * 0.90 }
                }

                // Per band, so bass / formants / sibilance move independently
                // instead of sharing one scalar.
                //
                // A *measured* source needs a much faster release than a pulsed
                // one. Frames arrive every ~33 ms while this loop runs at 60 Hz;
                // at the pulsed release (0.16) a peak takes ~0.25 s to fall, so
                // the next frame always landed before the bar had come down and
                // the display sat pinned near the top. Tracking the measurement
                // is the whole point when we actually have one.
                let releaseAlpha = streaming ? 0.45 : 0.16
                self.speechSpectrum = zip(self.speechSpectrum, self.speechSpectrumTarget)
                    .map { current, bandTarget in
                        let bandAlpha = bandTarget > current ? 0.6 : releaseAlpha
                        return current + (bandTarget - current) * bandAlpha
                    }

                let target = self.speechEnergyTarget
                // Fast attack, moderate release (was 0.11 — felt a touch sluggish).
                let alpha = target > self.speechEnergy ? 0.55 : 0.16
                self.speechEnergy += (target - self.speechEnergy) * alpha

                if self.speechEnergy < 0.02, target < 0.02 {
                    self.speechEnergy = 0
                    self.speechEnergyTarget = 0
                    self.speechSpectrum = Array(repeating: 0, count: SpeechSpectrum.bandCount)
                    self.speechSpectrumTarget = self.speechSpectrum
                    // Keep the loop only while a session might still pulse.
                    if self.status != .playing {
                        self.speechEnergySmoothTask = nil
                        return
                    }
                }
            }
            self?.speechEnergySmoothTask = nil
        }
    }

    private func clearSpeechEnergy() {
        speechEnergySmoothTask?.cancel()
        speechEnergySmoothTask = nil
        speechEnergyTarget = 0
        speechEnergy = 0
        speechEnergySeed = 0
        speechSpectrum = Array(repeating: 0, count: SpeechSpectrum.bandCount)
        speechSpectrumTarget = speechSpectrum
        lastSpectrumAt = nil
    }

    // MARK: Now Playing (system media / Dynamic Island)

    private func publishNowPlaying(playing: Bool) {
        installRemoteCommandsIfNeeded()
        UIApplication.shared.beginReceivingRemoteControlEvents()

        let title = concealsNowPlayingMetadata
            ? "Reading Aloud"
            : (nowPlayingTitle.isEmpty ? "Reading aloud" : nowPlayingTitle)
        let artist = concealsNowPlayingMetadata ? nil : nowPlayingArtist
        if NowPlayingInfo.shared.media?.title != title
            || NowPlayingInfo.shared.media?.artist != artist {
            NowPlayingInfo.shared.media = .init(
                title: title,
                artist: artist
            )
        }

        // Speech-paced, not `ReaderTimeEstimate.secondsPerPosition` (that's the
        // silent-reading model behind the position card's "X min left" labels —
        // left alone). `ttsSecondsPerPosition(rate:)` scales off the reader's
        // live TTS rate preference so duration/elapsed track the actual read-
        // aloud pace instead of claiming a number that isn't what's playing.
        let remaining: Int = {
            guard let pos = resumeLocator?.locations.position else {
                return totalPositionCount
            }
            // Match `ReadiumBook.remainingPositions`: positions still ahead.
            return max(0, totalPositionCount - pos)
        }()
        let timing = ReaderTimeEstimate.ttsNowPlayingTiming(
            totalPositions: totalPositionCount,
            remainingPositions: remaining,
            rate: ReaderSpeechPreferences.rateMultiplier
        )

        NowPlayingInfo.shared.playback = .init(
            duration: timing?.duration,
            elapsedTime: timing?.elapsed,
            // rate 0 keeps the lock-screen/Island control in a paused visual state.
            rate: playing ? 1 : 0
        )
    }

    #if DEBUG
    /// What the last `reconcileTransport` decided, for tests.
    private(set) var transportForTests = "none"
    #endif

    /// The ONE place the Lock Screen card and remote targets are decided, derived
    /// from session state (`status`, a pending request). Nothing else installs,
    /// removes, publishes or clears them.
    private func reconcileTransport() {
        guard !isAuditioning else { return }
        switch status {
        case .playing:
            publishNowPlaying(playing: true)
            #if DEBUG
            transportForTests = "playing"
            #endif
        case .paused:
            publishNowPlaying(playing: false)
            #if DEBUG
            transportForTests = "paused"
            #endif
        case .stopped where activeRequest != nil:
            installRemoteCommandsIfNeeded()
            clearNowPlaying()
            #if DEBUG
            transportForTests = "starting"
            #endif
        case .stopped, .unavailable:
            clearNowPlaying()
            removeRemoteCommands()
            #if DEBUG
            transportForTests = "none"
            #endif
        }
    }

    private func clearNowPlaying() {
        NowPlayingInfo.shared.clear()
    }

    private func installRemoteCommandsIfNeeded() {
        guard !remoteCommandsInstalled else { return }
        remoteCommandsInstalled = true

        let rcc = MPRemoteCommandCenter.shared()
        // Drop any prior targets from a previous reader open in this process.
        rcc.playCommand.removeTarget(nil)
        rcc.pauseCommand.removeTarget(nil)
        rcc.togglePlayPauseCommand.removeTarget(nil)
        rcc.nextTrackCommand.removeTarget(nil)
        rcc.previousTrackCommand.removeTarget(nil)
        rcc.stopCommand.removeTarget(nil)

        rcc.playCommand.isEnabled = true
        rcc.pauseCommand.isEnabled = true
        rcc.togglePlayPauseCommand.isEnabled = true
        rcc.nextTrackCommand.isEnabled = true
        rcc.previousTrackCommand.isEnabled = true
        rcc.stopCommand.isEnabled = true

        rcc.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return self.handleRemotePlay()
        }
        rcc.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return self.handleRemotePause()
        }
        rcc.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.toggle(from: self.resumeLocator)
            return .success
        }
        rcc.nextTrackCommand.addTarget { [weak self] _ in
            guard let self, self.isSessionActive else { return .noActionableNowPlayingItem }
            // Same chapter-skip as the mini player `>>` (not sentence step).
            return self.requestNextChapter() ? .success : .noActionableNowPlayingItem
        }
        rcc.previousTrackCommand.addTarget { [weak self] _ in
            guard let self, self.isSessionActive else { return .noActionableNowPlayingItem }
            return self.requestPreviousChapter() ? .success : .noActionableNowPlayingItem
        }
        rcc.stopCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.stop()
            return .success
        }
    }

    private func removeRemoteCommands() {
        guard remoteCommandsInstalled else { return }
        remoteCommandsInstalled = false
        let rcc = MPRemoteCommandCenter.shared()
        rcc.playCommand.removeTarget(nil)
        rcc.pauseCommand.removeTarget(nil)
        rcc.togglePlayPauseCommand.removeTarget(nil)
        rcc.nextTrackCommand.removeTarget(nil)
        rcc.previousTrackCommand.removeTarget(nil)
        rcc.stopCommand.removeTarget(nil)
        rcc.playCommand.isEnabled = false
        rcc.pauseCommand.isEnabled = false
        rcc.togglePlayPauseCommand.isEnabled = false
        rcc.nextTrackCommand.isEnabled = false
        rcc.previousTrackCommand.isEnabled = false
        rcc.stopCommand.isEnabled = false
    }

    private func handleRemotePlay() -> MPRemoteCommandHandlerStatus {
        guard ttsService != nil else { return .commandFailed }
        applyPreferences()
        switch status {
        case .unavailable:
            return .noActionableNowPlayingItem
        case .playing:
            if var request = activeRequest {
                request.desiredState = .playing
                activeRequest = request
            }
            return .success
        case .paused:
            resumeFromPaused(fallbackLocator: resumeLocator)
            return .success
        case .stopped:
            if activeRequest != nil {
                // Already starting: resume it if an interruption paused it, else
                // let it finish; never a second start over the first.
                if !resumePendingRequestIfPaused(), var request = activeRequest {
                    request.desiredState = .playing
                    activeRequest = request
                }
                return .success
            }
            startSpeechRequest(
                from: resumeLocator,
                direction: .forward,
                desiredState: .playing,
                isUserInitiated: true,
                isManualSkip: false
            )
            return .success
        }
    }

    private func handleRemotePause() -> MPRemoteCommandHandlerStatus {
        guard ttsService != nil else { return .commandFailed }
        switch status {
        case .unavailable:
            return .noActionableNowPlayingItem
        case .stopped:
            // Starting (nothing audible yet): Pause holds the engine like the in-app
            // button, so the start cannot commit a position nobody hears.
            if activeRequest != nil {
                pause()
                return .success
            }
            return .noActionableNowPlayingItem
        case .paused:
            if var request = activeRequest {
                request.desiredState = .paused
                activeRequest = request
            }
            return .success
        case .playing:
            pause()
            return .success
        }
    }

}

/// The read-aloud transport strip. When chrome is up it sits *inside*
/// `ReaderPositionCard`; when chrome is dismissed mid-session it is shown alone
/// in its own glass surface so transport stays reachable.
///
/// Layout: system `waveform` (left) · centered `<<` / play-pause / `>>` · stop
/// (right); spoken caption on a second row underneath.
///
/// Skip controls follow Apple Music: tap `<<` restarts the chapter (or previous
/// when near the start), tap `>>` goes to the next chapter, hold either seeks
/// within the current chapter.
struct ReaderSpeechMiniPlayer: View {
    let controller: ReaderSpeechController
    let tint: SwiftUI.Color
    /// Stops speech and collapses this strip. Must not hide the position card
    /// or the rest of the reader chrome — only ends read-aloud.
    let onStop: () -> Void
    let onSkipBack: () -> Void
    let onSkipForward: () -> Void
    /// Hold-to-seek: `forward` direction; called once when hold is recognized.
    let onSeekHoldStart: (_ forward: Bool) -> Void
    let onSeekHoldTick: (_ forward: Bool) -> Void
    let onSeekHoldEnd: () -> Void
    /// Tap on non-control chrome (caption, waveform, gutters) — typically shows
    /// the full reader chrome when only the mini player is visible.
    let onBackgroundTap: () -> Void
    /// Opens the reader's shared Read Aloud settings sheet (with cast ranking,
    /// pronunciation scan, and listening-rate log sync).
    let onOpenSettings: () -> Void

    /// HIG minimum; matches the floating chrome round buttons so a near-miss
    /// doesn't fall through to the page and toggle chrome instead.
    private static let hitSize: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // ZStack keeps transport optically centered while waveform/stop
            // pin to the leading/trailing edges (same width so the center holds).
            ZStack {
                HStack(spacing: 0) {
                    playingWaveform
                    Spacer(minLength: 0)
                    stopButton
                }

                // Transport (skip/play-pause) is neutral, not the theme tint — no
                // active state of its own to signal. Stop and the waveform below
                // keep tint: both are deliberately left alone.
                HStack(spacing: 4) {
                    HoldableTransportButton(
                        systemImage: "backward.fill",
                        font: .body,
                        tint: Color.primary,
                        hitSize: Self.hitSize,
                        accessibilityLabel: "Previous chapter",
                        accessibilityHint: "Double-tap and hold to seek backward",
                        onTap: onSkipBack,
                        onHoldStart: { onSeekHoldStart(false) },
                        onHoldTick: { onSeekHoldTick(false) },
                        onHoldEnd: onSeekHoldEnd
                    )

                    Button { controller.toggle(from: nil) } label: {
                        Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .contentTransition(.symbolEffect(.replace))
                            .foregroundStyle(Color.primary)
                            .frame(width: Self.hitSize, height: Self.hitSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(controller.isPlaying ? "Pause" : "Play")

                    HoldableTransportButton(
                        systemImage: "forward.fill",
                        font: .body,
                        tint: Color.primary,
                        hitSize: Self.hitSize,
                        accessibilityLabel: "Next chapter",
                        accessibilityHint: "Double-tap and hold to seek forward",
                        onTap: onSkipForward,
                        onHoldStart: { onSeekHoldStart(true) },
                        onHoldTick: { onSeekHoldTick(true) },
                        onHoldEnd: onSeekHoldEnd
                    )
                }
            }
            // The glyphs take text styles but sit in fixed 44pt buttons: at the accessibility
            // sizes they grew past their buttons and into each other. They stop growing at the
            // largest standard size; the caption below keeps growing.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

            Text(controller.spokenText)
                .font(.footnote)
                .foregroundStyle(.secondaryInk)
                .tint(nil)
                // Always reserve two lines so a short sentence (1 line) doesn't
                // collapse the strip height under the transport row.
                .lineLimit(2, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Let the background tap handle caption hits (not a control).
                .allowsHitTesting(false)
        }
        // Claim empty space so taps don't fall through to the page; buttons
        // still win hit-testing over this gesture.
        .contentShape(Rectangle())
        .onTapGesture(perform: onBackgroundTap)
    }

    /// Compact equalizer: still in silence, dramatic only while speech energy > 0.
    ///
    /// Doubles as the way into read-aloud settings from inside the book. It is
    /// a real `Button`, not a tap gesture on decoration: the bars used to be
    /// `accessibilityHidden` (correct while purely ornamental), and leaving
    /// them hidden once they became the only route to the settings would put
    /// that screen out of reach for VoiceOver entirely.
    ///
    /// This does take the waveform out of `onBackgroundTap`'s area — a button
    /// wins hit-testing over the strip's tap gesture — but the caption line and
    /// both gutters still reveal chrome, so that gesture keeps most of its
    /// target.
    private var playingWaveform: some View {
        Button(action: onOpenSettings) {
            NowPlayingEqualizerBars(
                isPlaying: controller.isPlaying,
                spectrum: controller.speechSpectrum,
                energySeed: controller.speechEnergySeed,
                color: tint
            )
            .frame(width: Self.hitSize, height: Self.hitSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Read-aloud settings")
        .accessibilityHint("Change the voice, speed, or engine")
    }

    private var stopButton: some View {
        Button(action: onStop) {
            Image(systemName: "stop.fill")
                .font(.footnote)
                .foregroundStyle(tint)
                .frame(width: Self.hitSize, height: Self.hitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop reading aloud")
    }
}

/// Compact equalizer tuned toward Dynamic Island Now Playing bars.
///
/// **Silence = unmoving.** **Speech = genuine multi-band motion:** each bar is
/// its own frequency band — pitch, vowel formants, consonant bursts,
/// sibilance — so `s` sounds spike the top bar while vowels hold the middle.
///
/// Previously every bar shared one scalar and differed only by a fixed gain
/// and a sine phase, which is why no amount of re-feeding could make it look
/// like real metering: there was no frequency information in the pipeline at
/// all. The carrier below is now only a small liveliness term on top of a
/// measured level, not the thing generating the movement.
private struct NowPlayingEqualizerBars: View {
    let isPlaying: Bool
    /// 0…1 smoothed level per band, from `SpeechSpectrum`.
    let spectrum: [Double]
    /// Varies per spoken fragment so bar phases differ.
    let energySeed: Double
    let color: SwiftUI.Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barCount = SpeechSpectrum.bandCount
    private let barWidth: CGFloat = 2.5
    private let barSpacing: CGFloat = 1.8
    private let minHeight: CGFloat = 2
    private let maxHeight: CGFloat = 28
    private let silenceThreshold: Double = 0.04

    private var isSilent: Bool {
        !isPlaying || (spectrum.max() ?? 0) < silenceThreshold
    }

    private func level(_ index: Int) -> Double {
        index < spectrum.count ? min(1, max(0, spectrum[index])) : 0
    }

    var body: some View {
        // Keep the clock running while energy is draining so release stays smooth.
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: reduceMotion || isSilent
            )
        ) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: barSpacing) {
                ForEach(0 ..< barCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(color)
                        .frame(width: barWidth, height: height(for: index, at: t))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func height(for index: Int, at time: TimeInterval) -> CGFloat {
        if isSilent {
            return minHeight
        }
        let e = CGFloat(level(index))
        if reduceMotion {
            return minHeight + (maxHeight - minHeight) * e
        }

        // Moderate speeds — DI is fluid, not frantic.
        let seed = energySeed * .pi * 2
        let w1 = 4.6 + Double(index) * 0.95
        let w2 = 6.8 - Double(index) * 0.7
        let p1 = seed + Double(index) * 0.85
        let p2 = seed * 1.15 + Double(index) * 1.25
        // Soft peaks: lift abs(sin) with a square-root for rounded tops.
        let s1 = abs(sin(time * w1 + p1))
        let s2 = abs(sin(time * w2 + p2))
        let carrier = sqrt(0.55 * s1 + 0.45 * s2) // 0…1, less spiky

        // The band level is the signal; the carrier only keeps a held level
        // from looking frozen between frames. A shallow trough means a loud
        // band stays visibly loud instead of being swung by the oscillator.
        let trough: CGFloat = 0.88
        let modulated = trough + (1 - trough) * CGFloat(carrier)
        return minHeight + (maxHeight - minHeight) * e * modulated
    }
}

/// Tap vs press-and-hold control for Music-like skip / seek.
private struct HoldableTransportButton: View {
    let systemImage: String
    let font: Font
    let tint: SwiftUI.Color
    let hitSize: CGFloat
    let accessibilityLabel: String
    let accessibilityHint: String
    let onTap: () -> Void
    let onHoldStart: () -> Void
    let onHoldTick: () -> Void
    let onHoldEnd: () -> Void

    /// Delay before a press becomes hold-to-seek (Music-like).
    private static let holdThresholdNanos: UInt64 = 400_000_000
    /// Interval between seek steps while held.
    private static let holdTickNanos: UInt64 = 180_000_000

    @State private var holdTask: Task<Void, Never>?
    @State private var didEnterHold = false

    var body: some View {
        Image(systemName: systemImage)
            .font(font)
            .foregroundStyle(tint)
            .frame(width: hitSize, height: hitSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard holdTask == nil else { return }
                        didEnterHold = false
                        holdTask = Task { @MainActor in
                            do {
                                try await Task.sleep(nanoseconds: Self.holdThresholdNanos)
                                guard !Task.isCancelled else { return }
                                didEnterHold = true
                                onHoldStart()
                                while !Task.isCancelled {
                                    onHoldTick()
                                    try await Task.sleep(nanoseconds: Self.holdTickNanos)
                                }
                            } catch {
                                // Cancelled — normal on release.
                            }
                        }
                    }
                    .onEnded { _ in
                        let wasHold = didEnterHold
                        holdTask?.cancel()
                        holdTask = nil
                        didEnterHold = false
                        if wasHold {
                            onHoldEnd()
                        } else {
                            onTap()
                        }
                    }
            )
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap() }
    }
}
#endif
