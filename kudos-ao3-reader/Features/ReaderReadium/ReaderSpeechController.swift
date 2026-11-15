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

    private(set) var status: Status = .unavailable
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
    /// Now Playing / Lock Screen previous-track — chapter skip (same as mini player).
    var onSkipPrevious: (() -> Void)?
    /// Now Playing / Lock Screen next-track — chapter skip (same as mini player).
    var onSkipNext: (() -> Void)?

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
    /// controller has released the Publication that still read from that EPUB.
    var onReleaseDetachedWork: ((_ workID: UUID) -> Void)?

    private var publication: Publication?
    private(set) var sessionWorkID: UUID?
    private(set) var isReaderOpen = false
    private var openReaderWorkID: UUID?
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

    /// After a re-anchor while paused, pause again once the first utterance starts.
    private var pendingPauseAfterReanchor = false
    /// Chapter finished speaking — next `reanchor` should resume even though
    /// status has already flipped to `.stopped`.
    private var pendingAutoContinue = false
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
    /// when the in-reader `toggle(from:)` call has no locator.
    private var resumeLocator: Locator?
    private var remoteCommandsInstalled = false

    var isAvailable: Bool { status != .unavailable }
    var isPlaying: Bool { status == .playing }
    /// Mini player / fan "session on" — playing or paused, not fully stopped.
    var isSessionActive: Bool { status == .playing || status == .paused }
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
    }

    /// Installs only callbacks owned by the live navigator. A same-work reopen
    /// immediately catches the page and audible decoration up to the voice.
    func attachReader(
        workID: UUID,
        onAdvance: @escaping (Locator) -> Void,
        onSpokenRange: @escaping (Locator) -> Void,
        onSessionEnded: @escaping () -> Void,
        onSkipPrevious: @escaping () -> Void,
        onSkipNext: @escaping () -> Void
    ) {
        guard openReaderWorkID == workID, sessionWorkID == workID else { return }
        resetDetachedPositionSaving()
        self.onAdvance = onAdvance
        self.onSpokenRange = onSpokenRange
        self.onSessionEnded = onSessionEnded
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
            publishNowPlaying(playing: isPlaying)
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

    private func installTTSService(
        _ service: TTSService,
        kind: ReaderTTSEngineKind,
        runtimeConfiguration: KokoroRuntimeConfiguration?
    ) {
        if let existing = ttsService {
            existing.onStatusChange = nil
            existing.onSpokenTextChange = nil
            existing.onSpeechEnergyPulse = nil
            existing.onSpeechSpectrum = nil
            existing.onAdvance = nil
            existing.onSpokenRange = nil
            existing.stop()
        }

        service.onStatusChange = { [weak self] newStatus in
            guard let self else { return }
            switch newStatus {
            case .unavailable:
                self.status = .unavailable
                self.persistPosition(for: .sessionEnd)
                self.onSessionEnded?()
                if self.publication != nil, !self.isReaderOpen {
                    self.releasePreparedSession()
                }
            case .stopped:
                // Only auto-advance when a playing chapter actually finished.
                // `speak()` used to call `stop()` on the way in, which fired this
                // path with `stoppedManually == false` and skipped a chapter on
                // every Read Aloud tap.
                let shouldContinue = self.status == .playing && !self.stoppedManually
                self.status = .stopped
                self.clearSpeechEnergy()
                self.clearNowPlaying()
                if !self.stoppedManually {
                    self.persistPosition(for: .sessionEnd)
                }
                self.onSessionEnded?()
                if shouldContinue {
                    self.pendingAutoContinue = true
                    let didAdvance = self.requestNextChapter()
                    self.pendingAutoContinue = false
                    if !didAdvance, !self.isReaderOpen {
                        self.releasePreparedSession()
                    }
                } else if !self.stoppedManually, !self.isReaderOpen {
                    self.releasePreparedSession()
                }
            case .playing:
                self.status = .playing
                self.publishNowPlaying(playing: true)
            case .paused:
                self.status = .paused
                self.clearSpeechEnergy()
                self.publishNowPlaying(playing: false)
            }
        }

        service.onSpokenTextChange = { [weak self] text in
            guard let self else { return }
            self.spokenText = ReaderSpeechPreferences.cleanUtteranceText(text)
            if self.pendingPauseAfterReanchor && !text.isEmpty {
                self.pendingPauseAfterReanchor = false
                self.status = .playing
                self.ttsService?.pause()
            }
        }

        service.onSpeechEnergyPulse = { [weak self] energy, seed in
            guard let self else { return }
            self.speechEnergyTarget = energy
            self.speechEnergySeed = seed
            self.startSpeechEnergySmoothingIfNeeded()
        }

        service.onSpeechSpectrum = { [weak self] spectrum in
            guard let self else { return }
            self.speechSpectrumTarget = spectrum.bands
            self.lastSpectrumAt = Date()
            // Keep the single-value envelope in step so anything still reading
            // `speechEnergy` stays correct.
            self.speechEnergyTarget = max(self.speechEnergyTarget, spectrum.level)
            self.startSpeechEnergySmoothingIfNeeded()
        }

        service.onAdvance = { [weak self] locator in
            self?.resumeLocator = locator
            self?.persistPosition(for: .utteranceBoundary)
            self?.onAdvance?(locator)
        }

        service.onSpokenRange = { [weak self] locator in
            self?.persistPosition(for: .spokenRange, locator: locator)
            self?.onSpokenRange?(locator)
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
    /// Shared by playback and the pronunciation pre-flight so the two cannot
    /// disagree about where a chapter ends.
    private static func chapterUnits(
        from startLoc: Locator?,
        in publication: Publication
    ) async -> [TTSSpeechUnit] {
        guard let content = publication.content(from: startLoc) else {
            Log.tts.error("Publication has no ContentService — cannot extract read-aloud text")
            return []
        }

        // `content(from:)` already starts at `startLoc`. Take the first
        // spine resource's remaining text and stop at the next href —
        // do not also filter by `startLoc.href`, which can disagree on
        // URL form and yield an empty chapter.
        var chapterHref: AnyURL?
        var units: [TTSSpeechUnit] = []
        for await element in content.sequence() {
            if Task.isCancelled { return [] }
            if chapterHref == nil {
                chapterHref = element.locator.href
            } else if element.locator.href != chapterHref {
                break
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
        return units
    }

    /// Starts at `locator` (normally the reader's current position) or resumes
    /// where it left off. Walks only the current spine resource — not the rest
    /// of the publication — so a long work does not stall the first tap.
    private func startSpeech(from locator: Locator?) {
        guard let publication else { return }
        SpeechOwnerRegistry.shared.claim(self)
        let startLoc = locator ?? resumeLocator
        ensureEngineForPlayback()
        applyPreferences()

        startTask?.cancel()
        startTask = Task {
            do {
                let units = await Self.chapterUnits(
                    from: startLoc, in: publication
                )
                guard !units.isEmpty else {
                    Log.tts.error("No extractable text in the current chapter")
                    return
                }

                installRemoteCommandsIfNeeded()
                stoppedManually = false
                // Re-check after chapter extract so a download that finished
                // while we were walking the spine is used for this tap.
                ensureEngineForPlayback()
                applyPreferences()
                try await ttsService?.speak(units: units)
            } catch {
                Log.tts.error("speak() failed: \(error.localizedDescription, privacy: .public)")
            }
        }
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
            ttsService?.resume()
        case .stopped:
            if let locator {
                resumeLocator = locator
            }
            startSpeech(from: locator ?? resumeLocator)
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
        startTask?.cancel()
        stoppedManually = false
        ensureEngineForPlayback()
        applyPreferences()
        guard let service = ttsService else {
            status = .unavailable
            return
        }
        let unit = TTSSpeechUnit(text: text, locator: nil)
        startTask = Task { [weak self] in
            do {
                try await service.speak(units: [unit])
            } catch {
                Log.tts.error(
                    "Audition failed: \(error.localizedDescription, privacy: .public)"
                )
                self?.status = .stopped
            }
        }
    }

    func stop() {
        if isSessionActive {
            persistPosition(for: .stop)
        }
        let releasesPublication = !isReaderOpen && publication != nil
        SpeechOwnerRegistry.shared.release(self)
        pendingPauseAfterReanchor = false
        pendingAutoContinue = false
        stoppedManually = true
        startTask?.cancel()
        startTask = nil
        ttsService?.stop()
        status = ttsService == nil ? .unavailable : .stopped
        spokenText = ""
        clearSpeechEnergy()
        clearNowPlaying()
        // Once Now Playing info is cleared there's no Lock Screen / Control
        // Center widget left to show transport on, so leaving the remote
        // commands registered only risked a ghost Play/Skip target aimed at a
        // dead session. `installRemoteCommandsIfNeeded()` re-adds them the next
        // time playback actually starts.
        removeRemoteCommands()
        if releasesPublication {
            releasePreparedSession()
        }
    }

    /// Pause without ending the session (hold-to-seek while scrubbing).
    func pause() {
        persistPosition(for: .pause)
        pendingPauseAfterReanchor = false
        ttsService?.pause()
        clearSpeechEnergy()
    }

    /// Move the speech cursor to `locator` after a chapter skip or seek release.
    /// - Parameter resumePlaying: if true, start speaking; if false but a session
    ///   was active, start then immediately pause so Play resumes from the new spot.
    func reanchor(to locator: Locator?, resumePlaying: Bool) {
        resumeLocator = locator
        guard ttsService != nil, status != .unavailable else { return }

        applyPreferences()

        let shouldPlay = resumePlaying || pendingAutoContinue
        if shouldPlay {
            pendingPauseAfterReanchor = false
            startSpeech(from: locator)
        } else if isSessionActive {
            pendingPauseAfterReanchor = true
            startSpeech(from: locator)
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
        pendingPauseAfterReanchor = false
        pendingAutoContinue = false
        stoppedManually = true
        startTask?.cancel()
        startTask = nil
        onSessionEnded?()
        onAdvance = nil
        onSpokenRange = nil
        onSessionEnded = nil
        onSkipPrevious = nil
        onSkipNext = nil
        ttsService?.stop()
        releasePreparedSession()
        clearNowPlaying()
        removeRemoteCommands()
    }

    private func detachReaderCallbacks() {
        onAdvance = nil
        onSpokenRange = nil
        onSessionEnded = nil
        onSkipPrevious = nil
        onSkipNext = nil
    }

    private func releasePreparedSession() {
        let releasedWorkID = sessionWorkID
        SpeechOwnerRegistry.shared.release(self)
        clearSpeechEnergy()
        clearNowPlaying()
        removeRemoteCommands()
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
        if !isReaderOpen, let releasedWorkID {
            onReleaseDetachedWork?(releasedWorkID)
        }
    }

    private func persistPosition(
        for event: ReaderSpeechPositionSaveThrottle.Event,
        locator: Locator? = nil,
        at date: Date = Date()
    ) {
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
            onSkipNext()
            return true
        }
        return skipDetachedChapter(forward: true)
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
        reanchor(to: target, resumePlaying: isPlaying)
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
            return .success
        case .paused:
            ttsService?.resume()
            return .success
        case .stopped:
            startSpeech(from: resumeLocator)
            return .success
        }
    }

    private func handleRemotePause() -> MPRemoteCommandHandlerStatus {
        guard ttsService != nil else { return .commandFailed }
        switch status {
        case .unavailable, .stopped:
            return .noActionableNowPlayingItem
        case .paused:
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

    /// HIG minimum; matches the floating chrome round buttons so a near-miss
    /// doesn't fall through to the page and toggle chrome instead.
    private static let hitSize: CGFloat = 44

    @State private var showingSpeechSettings = false

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
                .foregroundStyle(.secondary)
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
        .sheet(isPresented: $showingSpeechSettings, onDismiss: {
            controller.applyPreferences()
        }) {
            ReaderSpeechSettingsSheet()
        }
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
        Button {
            showingSpeechSettings = true
        } label: {
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
