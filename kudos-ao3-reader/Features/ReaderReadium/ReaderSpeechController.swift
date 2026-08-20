#if os(iOS)
import AVFoundation
import MediaPlayer
import ReadiumNavigator
import ReadiumShared
import SwiftUI
import UIKit

/// Read-aloud for the reader, on top of Readium's own
/// `PublicationSpeechSynthesizer`.
///
/// Readium's synthesizer walks the publication and yields utterances with
/// `Locator`s (so the page can follow the voice). The engine underneath is
/// Apple's `AVSpeechSynthesizer` via `AVTTSEngine`, configured with the user's
/// voice / rate / pitch preferences from `ReaderSpeechPreferences`.
///
/// **Audio session:** owned by Readium (`PublicationSpeechSynthesizer`'s
/// `AudioSession` with `.spokenAudio` / long-form). This controller must not
/// activate or deactivate `AVAudioSession` on its own — dual ownership races
/// stop/start and unducking.
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

    private var synthesizer: PublicationSpeechSynthesizer?
    /// After a re-anchor while paused, pause again once the first utterance starts.
    private var pendingPauseAfterReanchor = false
    /// Instantaneous target (0…1); `speechEnergy` lerps toward this at ~60 fps.
    private var speechEnergyTarget: Double = 0
    /// Runs the attack/release smoother while energy is live or speaking.
    private var speechEnergySmoothTask: Task<Void, Never>?
    private var delegateProxy: DelegateProxy?
    private var engineBridge: EngineBridge?
    /// Identity of the publication the live synthesizer was built for. Used so
    /// a re-entrant `.ready` for the same open does not tear down playback.
    private var preparedPublicationID: ObjectIdentifier?

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
        synthesizer?.availableVoices ?? ReaderSpeechPreferences.catalogVoices()
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

        guard let publication,
              PublicationSpeechSynthesizer.canSpeak(publication: publication)
        else {
            tearDown()
            return
        }

        let id = ObjectIdentifier(publication)
        if preparedPublicationID == id, synthesizer != nil {
            // Same open — keep the engine and any in-flight playback; still
            // refresh metadata in case the view re-bound.
            return
        }

        tearDown()
        // tearDown clears totalPositionCount — restore after.
        nowPlayingTitle = title
        nowPlayingArtist = author.isEmpty ? nil : author
        totalPositionCount = max(0, totalPositions)

        let bridge = EngineBridge()
        let proxy = DelegateProxy()
        proxy.owner = self

        let voices = ReaderSpeechPreferences.catalogVoices()
        let language = publication.metadata.language
        let voiceID = ReaderSpeechPreferences.resolvedVoiceIdentifier(
            language: language,
            voices: voices
        )

        guard let synthesizer = PublicationSpeechSynthesizer(
            publication: publication,
            config: .init(
                defaultLanguage: language,
                voiceIdentifier: voiceID
            ),
            // Readium owns category/mode/activation; leave defaults.
            engineFactory: { bridge.makeEngine() },
            delegate: proxy
        ) else { return }

        self.engineBridge = bridge
        self.delegateProxy = proxy
        self.synthesizer = synthesizer
        preparedPublicationID = id
        status = .stopped
    }

    /// Pushes the latest UserDefaults preferences into the live synthesizer.
    /// Rate/pitch apply on the next utterance via the engine bridge; voice
    /// changes take effect on the next utterance through `config`.
    func applyPreferences() {
        guard let synthesizer else { return }
        let language = synthesizer.config.defaultLanguage
        let voiceID = ReaderSpeechPreferences.resolvedVoiceIdentifier(
            language: language,
            voices: synthesizer.availableVoices
        )
        synthesizer.config.voiceIdentifier = voiceID
    }

    /// Starts at `locator` (normally the reader's current position) or resumes
    /// where it left off.
    func toggle(from locator: Locator?) {
        guard let synthesizer else { return }
        applyPreferences()
        switch status {
        case .unavailable:
            return
        case .playing:
            synthesizer.pause()
        case .paused:
            synthesizer.resume()
        case .stopped:
            if let locator {
                resumeLocator = locator
            }
            installRemoteCommandsIfNeeded()
            synthesizer.start(from: locator ?? resumeLocator)
        }
    }

    func stop() {
        pendingPauseAfterReanchor = false
        synthesizer?.stop()
        status = synthesizer == nil ? .unavailable : .stopped
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
        synthesizer?.pause()
        clearSpeechEnergy()
    }

    /// Move the speech cursor to `locator` after a chapter skip or seek release.
    /// - Parameter resumePlaying: if true, start speaking; if false but a session
    ///   was active, start then immediately pause so Play resumes from the new spot.
    func reanchor(to locator: Locator?, resumePlaying: Bool) {
        resumeLocator = locator
        guard let synthesizer, status != .unavailable else { return }
        applyPreferences()
        installRemoteCommandsIfNeeded()
        if resumePlaying {
            pendingPauseAfterReanchor = false
            synthesizer.start(from: locator)
        } else if isSessionActive {
            pendingPauseAfterReanchor = true
            synthesizer.start(from: locator)
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
        onAdvance = nil
        onSkipPrevious = nil
        onSkipNext = nil
        synthesizer?.stop()
        synthesizer = nil
        delegateProxy = nil
        engineBridge = nil
        preparedPublicationID = nil
        resumeLocator = nil
        totalPositionCount = 0
        status = .unavailable
        spokenText = ""
        clearSpeechEnergy()
        clearNowPlaying()
        removeRemoteCommands()
    }

    fileprivate func apply(state: PublicationSpeechSynthesizer.State) {
        switch state {
        case .stopped:
            status = .stopped
            spokenText = ""
            clearSpeechEnergy()
            clearNowPlaying()
        case let .paused(utterance):
            status = .paused
            spokenText = ReaderSpeechPreferences.cleanUtteranceText(utterance.text)
            resumeLocator = utterance.locator
            clearSpeechEnergy()
            publishNowPlaying(playing: false)
        case let .playing(utterance, range):
            spokenText = ReaderSpeechPreferences.cleanUtteranceText(utterance.text)
            resumeLocator = utterance.locator
            if pendingPauseAfterReanchor {
                pendingPauseAfterReanchor = false
                status = .playing
                synthesizer?.pause()
                return
            }
            status = .playing
            // Only pulse on real willSpeakRange updates — not the initial
            // `.playing(utterance, range: nil)` seed (that jumped bars before audio).
            if let range, let fragment = range.text.highlight {
                pulseSpeechEnergy(spokenFragment: fragment)
            }
            onAdvance?(utterance.locator)
            publishNowPlaying(playing: true)
        }
    }

    /// Raise the energy *target* from a currently spoken fragment. A background
    /// loop smooths `speechEnergy` toward the target (fast attack / slower release)
    /// and eases the target back to 0 between range callbacks.
    private func pulseSpeechEnergy(spokenFragment: String) {
        let trimmed = spokenFragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.unicodeScalars.contains(where: { CharacterSet.letters.contains($0)
                  || CharacterSet.decimalDigits.contains($0) })
        else { return }

        speechEnergyTarget = Double.random(in: 0.88 ... 1.0)
        speechEnergySeed = Double(trimmed.unicodeScalars.reduce(0) { ($0 &+ UInt32($1.value)) } % 997) / 997.0
        startSpeechEnergySmoothingIfNeeded()
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
        guard let synthesizer else { return .commandFailed }
        applyPreferences()
        switch status {
        case .unavailable:
            return .noActionableNowPlayingItem
        case .playing:
            return .success
        case .paused:
            synthesizer.resume()
            return .success
        case .stopped:
            installRemoteCommandsIfNeeded()
            synthesizer.start(from: resumeLocator)
            return .success
        }
    }

    private func handleRemotePause() -> MPRemoteCommandHandlerStatus {
        guard synthesizer != nil else { return .commandFailed }
        switch status {
        case .playing:
            synthesizer?.pause()
            return .success
        case .paused, .stopped, .unavailable:
            return .success
        }
    }

    /// Owns the `AVTTSEngine` + rate/pitch delegate. Readium's synthesizer
    /// constructs the engine lazily through `engineFactory`; we keep one bridge
    /// so preference changes always hit the same live engine.
    ///
    /// Note: utterance *text* cleanup can't run here — Readium's `TTSUtterance`
    /// initializer is internal. We still normalize whitespace for the mini
    /// player's caption in `apply(state:)`. Sentence pauses + rate/pitch are
    /// applied on each `AVSpeechUtterance` via the delegate.
    private final class EngineBridge: AVTTSEngineDelegate {
        private var engine: AVTTSEngine?

        func makeEngine() -> TTSEngine {
            if let engine { return engine }
            let av = AVTTSEngine(delegate: self)
            engine = av
            return av
        }

        func avTTSEngine(_ engine: AVTTSEngine, didCreateUtterance utterance: AVSpeechUtterance) {
            utterance.rate = ReaderSpeechPreferences.avSpeechRate
            utterance.pitchMultiplier = ReaderSpeechPreferences.avPitch
            // A short post-sentence pause makes chapter prose less machine-gun.
            utterance.postUtteranceDelay = ReaderSpeechPreferences.sentencePause
        }
    }

    /// Readium's delegate is a class-bound protocol, so the `@Observable`
    /// controller can't conform directly without becoming an `NSObject`
    /// subclass; this thin proxy keeps that detail out of the model.
    private final class DelegateProxy: PublicationSpeechSynthesizerDelegate {
        weak var owner: ReaderSpeechController?

        func publicationSpeechSynthesizer(
            _: PublicationSpeechSynthesizer,
            stateDidChange state: PublicationSpeechSynthesizer.State
        ) {
            Task { @MainActor [weak owner] in owner?.apply(state: state) }
        }

        func publicationSpeechSynthesizer(
            _: PublicationSpeechSynthesizer,
            utterance _: PublicationSpeechSynthesizer.Utterance,
            didFailWithError _: PublicationSpeechSynthesizer.Error
        ) {
            // A single utterance failing (an unsupported language, say) should
            // not tear playback down; the synthesizer moves to the next one.
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
