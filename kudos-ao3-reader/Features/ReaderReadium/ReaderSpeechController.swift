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
/// **Engine:** `SystemTTSService` (Apple `AVSpeechSynthesizer` via Readium
/// `AVTTSEngine`) until the Kokoro pack is on disk, then
/// `SherpaKokoroTTSService`. Selection is re-checked each time speech starts.
///
/// **Audio session:** owned by the active `TTSService` (`.playback` /
/// `.spokenAudio` / long-form).
///
/// **Now Playing / Dynamic Island:** while a session is playing or paused, we
/// publish system Now Playing info + remote commands so Lock Screen / Control
/// Center / Dynamic Island can control transport. Lifetime is **reader-scoped**:
/// leaving the work stops speech and clears Now Playing. Backgrounding the app
/// with the reader still open keeps speech (requires `UIBackgroundModes=audio`).
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

    /// Called with each utterance's locator so the reader can page along with
    /// the voice.
    var onAdvance: ((Locator) -> Void)?
    /// Now Playing / Lock Screen previous-track — chapter skip (same as mini player).
    var onSkipPrevious: (() -> Void)?
    /// Now Playing / Lock Screen next-track — chapter skip (same as mini player).
    var onSkipNext: (() -> Void)?

    private var publication: Publication?
    private var ttsService: TTSService?
    private let downloadManager = TTSDownloadManager()
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

    /// Work metadata for the system Now Playing card (title + author byline).
    private var nowPlayingTitle: String = ""
    private var nowPlayingArtist: String?
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

    /// Voices the settings UI can offer (already filtered for long-form reading).
    var availableVoices: [TTSVoice] {
        ttsService?.availableVoices ?? ReaderSpeechPreferences.catalogVoices()
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
        title: String,
        author: String,
        totalPositions: Int
    ) {
        nowPlayingTitle = title
        nowPlayingArtist = author.isEmpty ? nil : author
        totalPositionCount = max(0, totalPositions)

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
        self.publication = publication

        installTTSService(makeTTSService(for: preferredEngineKind()))
        self.status = .stopped
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

    /// Kokoro if the voice pack is on disk, otherwise the system voice.
    /// Re-checked at every playback start (not on pause/resume).
    private func preferredEngineKind() -> ReaderTTSEngineKind {
        ReaderTTSEngineKind.preferred(modelDownloaded: downloadManager.isModelDownloaded())
    }

    private func currentEngineKind() -> ReaderTTSEngineKind? {
        switch ttsService {
        case is SherpaKokoroTTSService: return .kokoro
        case is SystemTTSService: return .system
        default: return nil
        }
    }

    private func makeTTSService(for kind: ReaderTTSEngineKind) -> TTSService {
        switch kind {
        case .kokoro:
            return SherpaKokoroTTSService(modelDirectory: downloadManager.modelDirectory)
        case .system:
            return SystemTTSService()
        }
    }

    /// Swap the bound engine if the download state changed since last start.
    /// Unbinds callbacks before `stop()` so a swap cannot auto-skip a chapter.
    private func ensureEngineForPlayback() {
        let kind = preferredEngineKind()
        guard currentEngineKind() != kind else { return }
        installTTSService(makeTTSService(for: kind))
    }

    private func installTTSService(_ service: TTSService) {
        if let existing = ttsService {
            existing.onStatusChange = nil
            existing.onSpokenTextChange = nil
            existing.onSpeechEnergyPulse = nil
            existing.onAdvance = nil
            existing.stop()
        }

        service.onStatusChange = { [weak self] newStatus in
            guard let self else { return }
            switch newStatus {
            case .unavailable:
                self.status = .unavailable
            case .stopped:
                // Only auto-advance when a playing chapter actually finished.
                // `speak()` used to call `stop()` on the way in, which fired this
                // path with `stoppedManually == false` and skipped a chapter on
                // every Read Aloud tap.
                let shouldContinue = self.status == .playing && !self.stoppedManually
                self.status = .stopped
                self.clearSpeechEnergy()
                self.clearNowPlaying()
                if shouldContinue {
                    self.pendingAutoContinue = true
                    self.onSkipNext?()
                    self.pendingAutoContinue = false
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

        service.onAdvance = { [weak self] locator in
            self?.resumeLocator = locator
            self?.onAdvance?(locator)
        }

        ttsService = service
    }

    /// Starts at `locator` (normally the reader's current position) or resumes
    /// where it left off. Walks only the current spine resource — not the rest
    /// of the publication — so a long work does not stall the first tap.
    private func startSpeech(from locator: Locator?) {
        guard let publication else { return }
        let startLoc = locator ?? resumeLocator
        ensureEngineForPlayback()
        applyPreferences()

        startTask?.cancel()
        startTask = Task {
            do {
                guard let content = publication.content(from: startLoc) else {
                    Log.tts.error("Publication has no ContentService — cannot extract read-aloud text")
                    return
                }

                // `content(from:)` already starts at `startLoc`. Take the first
                // spine resource's remaining text and stop at the next href —
                // do not also filter by `startLoc.href`, which can disagree on
                // URL form and yield an empty chapter.
                var chapterHref: AnyURL?
                var texts: [String] = []
                var firstLocator: Locator?
                for await element in content.sequence() {
                    if Task.isCancelled { return }
                    if chapterHref == nil {
                        chapterHref = element.locator.href
                    } else if element.locator.href != chapterHref {
                        break
                    }
                    if firstLocator == nil {
                        firstLocator = element.locator
                    }
                    if let text = (element as? TextualContentElement)?.text, !text.isEmpty {
                        texts.append(text)
                    }
                }

                let text = texts.joined(separator: "\n")
                guard !text.isEmpty else {
                    Log.tts.error("No extractable text in the current chapter")
                    return
                }

                installRemoteCommandsIfNeeded()
                stoppedManually = false
                // Re-check after chapter extract so a download that finished
                // while we were walking the spine is used for this tap.
                ensureEngineForPlayback()
                applyPreferences()
                try await ttsService?.speak(
                    text: text,
                    startLocator: startLoc ?? firstLocator
                )
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

    func stop() {
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
    }

    /// Pause without ending the session (hold-to-seek while scrubbing).
    func pause() {
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

    /// Full teardown used when leaving the reader or switching publications.
    /// Clears synthesizer, Now Playing, remote commands, and advance callbacks.
    /// Prefer this over `stop()` when the reader view goes away so Lock Screen /
    /// Island transport does not keep targeting a dead session.
    func tearDown() {
        pendingPauseAfterReanchor = false
        pendingAutoContinue = false
        stoppedManually = true
        startTask?.cancel()
        startTask = nil
        onAdvance = nil
        onSkipPrevious = nil
        onSkipNext = nil
        ttsService?.stop()
        ttsService = nil
        publication = nil
        clearNowPlaying()
        removeRemoteCommands()
        status = .unavailable
    }

    private func startSpeechEnergySmoothingIfNeeded() {
        guard speechEnergySmoothTask == nil else { return }
        speechEnergySmoothTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 16_000_000) // ~60 fps
                guard !Task.isCancelled else { return }

                // Ease target down so energy falls during real silence between pulses.
                // Slightly snappier than a pure DI-smooth release — still smooth, less lag.
                self.speechEnergyTarget *= 0.90

                let target = self.speechEnergyTarget
                // Fast attack, moderate release (was 0.11 — felt a touch sluggish).
                let alpha = target > self.speechEnergy ? 0.55 : 0.16
                self.speechEnergy += (target - self.speechEnergy) * alpha

                if self.speechEnergy < 0.02, target < 0.02 {
                    self.speechEnergy = 0
                    self.speechEnergyTarget = 0
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
    }

    // MARK: Now Playing (system media / Dynamic Island)

    private func publishNowPlaying(playing: Bool) {
        installRemoteCommandsIfNeeded()
        UIApplication.shared.beginReceivingRemoteControlEvents()

        let title = nowPlayingTitle.isEmpty ? "Reading aloud" : nowPlayingTitle
        if NowPlayingInfo.shared.media?.title != title
            || NowPlayingInfo.shared.media?.artist != nowPlayingArtist
        {
            NowPlayingInfo.shared.media = .init(
                title: title,
                artist: nowPlayingArtist
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
            if let onSkipNext {
                onSkipNext()
                return .success
            }
            return .commandFailed
        }
        rcc.previousTrackCommand.addTarget { [weak self] _ in
            guard let self, self.isSessionActive else { return .noActionableNowPlayingItem }
            if let onSkipPrevious {
                onSkipPrevious()
                return .success
            }
            return .commandFailed
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
    }

    /// Compact equalizer: still in silence, dramatic only while speech energy > 0.
    private var playingWaveform: some View {
        NowPlayingEqualizerBars(
            isPlaying: controller.isPlaying,
            energy: controller.speechEnergy,
            energySeed: controller.speechEnergySeed,
            color: tint
        )
        .frame(width: Self.hitSize, height: Self.hitSize)
        .accessibilityHidden(true)
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
/// **Silence = unmoving.** **Speech = smooth multi-band undulation** driven by
/// the controller’s already-smoothed `speechEnergy` (not raw pulse jumps).
/// Moderate carrier speeds + soft peaks read closer to system metering.
private struct NowPlayingEqualizerBars: View {
    let isPlaying: Bool
    /// 0…1 smoothed level from the speech controller.
    let energy: Double
    /// Varies per spoken fragment so bar phases differ.
    let energySeed: Double
    let color: SwiftUI.Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let bandGains: [CGFloat] = [0.72, 1.0, 0.8, 0.9]
    private let barCount = 4
    private let barWidth: CGFloat = 2.5
    private let barSpacing: CGFloat = 1.8
    private let minHeight: CGFloat = 2
    private let maxHeight: CGFloat = 28
    private let silenceThreshold: Double = 0.04

    private var isSilent: Bool {
        !isPlaying || energy < silenceThreshold
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
        let e = CGFloat(min(1, max(0, energy)))
        if reduceMotion {
            return minHeight + (maxHeight - minHeight) * e * bandGains[index]
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

        // Full travel at high energy; collapses smoothly as envelope falls.
        let trough: CGFloat = 0.15
        let modulated = trough + (1 - trough) * CGFloat(carrier)
        let level = e * bandGains[index] * modulated
        return minHeight + (maxHeight - minHeight) * level
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
