#if os(iOS)
import AVFoundation
import Foundation
import ReadiumNavigator
import ReadiumShared

/// Apple system-voice TTS, using the same `AVSpeechSynthesizer` integration the
/// reader used before the Kokoro migration (commit `863d33c2`'s parent).
///
/// The old path was Readium `PublicationSpeechSynthesizer` + `AVTTSEngine` +
/// `EngineBridge`. `TTSUtterance`'s memberwise init is internal, so this service
/// cannot wrap `AVTTSEngine.speak` from app code. Instead it owns
/// `AVSpeechSynthesizer` directly and reuses:
/// - `EngineBridge` rate / pitch / `sentencePause` on every utterance
/// - `willSpeakRange` energy (old `pulseSpeechEnergy`)
/// - voice catalog via `ReaderSpeechPreferences.catalogVoices()`
/// - audio session `.playback` / `.spokenAudio` / long-form (same config as
///   the old `PublicationSpeechSynthesizer`)
/// - interruption pause/resume
///
/// Chapter text arrives through `TTSService.speak(text:startLocator:)` (the
/// controller now extracts the spine resource). Utterances are spoken
/// sequentially so a new `speak` is never submitted before `didFinish` of the
/// previous one (the iOS 15 `AVTTSEngine` deadlock this codebase already
/// worked around).
@MainActor
public final class SystemTTSService: TTSService {

    public private(set) var status: TTSServiceStatus = .stopped {
        didSet { onStatusChange?(status) }
    }

    public private(set) var spokenText: String = "" {
        didSet { onSpokenTextChange?(spokenText) }
    }

    public private(set) var speechEnergy: Double = 0
    public private(set) var speechEnergySeed: Double = 0

    public var availableVoices: [TTSVoice] {
        ReaderSpeechPreferences.catalogVoices()
    }

    public var onStatusChange: ((TTSServiceStatus) -> Void)?
    public var onSpokenTextChange: ((String) -> Void)?
    public var onSpeechEnergyPulse: ((Double, Double) -> Void)?
    public var onAdvance: ((Locator) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private let delegateProxy = DelegateProxy()
    private var activeTask: Task<Void, Never>?
    private var interruptionObserver: NSObjectProtocol?
    private var utteranceWaiter: CheckedContinuation<Void, Never>?
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []

    private var chunks: [String] = []
    private var currentIndex: Int = 0
    private var startLocator: Locator?
    private var currentVoiceId: String = ""
    private var wasPlayingBeforeInterruption = false

    public init() {
        delegateProxy.owner = self
        synthesizer.delegate = delegateProxy
        observeInterruptions()
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    public func speak(text: String, startLocator: Locator?) async throws {
        resetPlayback(notifyStopped: false)

        let prepared = TextChunker.chunk(text: text)
            .map { ReaderSpeechPreferences.cleanUtteranceText($0) }
            .filter { chunk in
                chunk.unicodeScalars.contains { CharacterSet.letters.contains($0)
                    || CharacterSet.decimalDigits.contains($0) }
            }
        guard !prepared.isEmpty else { return }

        chunks = prepared
        currentIndex = 0
        self.startLocator = startLocator

        try activateAudioSession()
        status = .playing
        startPlayback(from: 0)
    }

    public func pause() {
        guard status == .playing else { return }
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
        }
        status = .paused
        speechEnergy = 0
    }

    public func resume() {
        guard status == .paused else { return }
        status = .playing
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
        }
        resumePauseWaiters()
    }

    public func stop() {
        resetPlayback(notifyStopped: true)
    }

    public func setVoice(id: String) {
        currentVoiceId = id
    }

    public func setRate(_: Float) {
        // Applied per utterance from live `ReaderSpeechPreferences`, matching
        // the pre-Kokoro `EngineBridge`.
    }

    public func setPitch(_: Float) {
        // Applied per utterance from live `ReaderSpeechPreferences`.
    }

    // MARK: - Playback

    private func startPlayback(from index: Int) {
        activeTask?.cancel()
        currentIndex = index
        activeTask = Task { [weak self] in
            await self?.playChunks(from: index)
        }
    }

    private func playChunks(from startIndex: Int) async {
        let bound = chunks.count
        guard startIndex < bound else {
            finishNaturally()
            return
        }

        for index in startIndex..<bound {
            guard !Task.isCancelled else { return }
            await waitWhilePaused()
            guard !Task.isCancelled, status != .stopped else { return }

            currentIndex = index
            let text = chunks[index]
            spokenText = text
            if let startLocator {
                onAdvance?(startLocator)
            }

            await speakUtterance(text)
        }

        finishNaturally()
    }

    /// One utterance at a time: wait for `didFinish`/`didCancel` before the
    /// next `synthesizer.speak`, matching `AVTTSEngine`'s iOS 15 state machine.
    private func speakUtterance(_ text: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            utteranceWaiter = continuation
            let utterance = AVSpeechUtterance(string: text)
            // Pre-Kokoro EngineBridge (ReaderSpeechController at 863d33c2^).
            utterance.rate = ReaderSpeechPreferences.avSpeechRate
            utterance.pitchMultiplier = ReaderSpeechPreferences.avPitch
            utterance.postUtteranceDelay = ReaderSpeechPreferences.sentencePause
            if !currentVoiceId.isEmpty {
                utterance.voice = AVSpeechSynthesisVoice(identifier: currentVoiceId)
            }
            synthesizer.speak(utterance)
        }
    }

    /// Same envelope as the pre-Kokoro `ReaderSpeechController.pulseSpeechEnergy`.
    fileprivate func pulseSpeechEnergy(spokenFragment: String) {
        let trimmed = spokenFragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.unicodeScalars.contains(where: { CharacterSet.letters.contains($0)
                  || CharacterSet.decimalDigits.contains($0) })
        else { return }

        speechEnergy = Double.random(in: 0.88 ... 1.0)
        speechEnergySeed = Double(trimmed.unicodeScalars.reduce(0) { ($0 &+ UInt32($1.value)) } % 997) / 997.0
        onSpeechEnergyPulse?(speechEnergy, speechEnergySeed)
    }

    fileprivate func handleUtteranceEnded() {
        let waiter = utteranceWaiter
        utteranceWaiter = nil
        waiter?.resume()
    }

    private func waitWhilePaused() async {
        while status == .paused, !Task.isCancelled {
            await withCheckedContinuation { pauseWaiters.append($0) }
        }
    }

    private func resumePauseWaiters() {
        let waiters = pauseWaiters
        pauseWaiters = []
        waiters.forEach { $0.resume() }
    }

    private func resetPlayback(notifyStopped: Bool) {
        activeTask?.cancel()
        activeTask = nil
        synthesizer.stopSpeaking(at: .immediate)
        handleUtteranceEnded()
        resumePauseWaiters()
        chunks = []
        currentIndex = 0
        spokenText = ""
        speechEnergy = 0
        wasPlayingBeforeInterruption = false
        if notifyStopped, status != .unavailable {
            status = .stopped
        }
    }

    private func finishNaturally() {
        guard !Task.isCancelled else { return }
        activeTask = nil
        spokenText = ""
        speechEnergy = 0
        if status == .playing {
            status = .stopped
        }
    }

    /// Same category/mode/policy as pre-Kokoro `PublicationSpeechSynthesizer`
    /// (`AudioSession.Configuration` playback / spokenAudio / long-form).
    private func activateAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playback,
            mode: .spokenAudio,
            policy: .longFormAudio,
            options: []
        )
        try session.setActive(true)
    }

    // MARK: - Interruptions

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let typeRaw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor [weak self] in
                self?.handleInterruption(typeRaw: typeRaw, optionRaw: optionRaw)
            }
        }
    }

    private func handleInterruption(typeRaw: UInt?, optionRaw: UInt?) {
        guard let typeRaw, let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }

        switch type {
        case .began:
            if status == .playing {
                wasPlayingBeforeInterruption = true
                pause()
            }
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionRaw ?? 0)
            if wasPlayingBeforeInterruption, options.contains(.shouldResume) {
                wasPlayingBeforeInterruption = false
                resume()
            } else {
                wasPlayingBeforeInterruption = false
            }
        @unknown default:
            break
        }
    }

    /// Readium's `AVSpeechSynthesizerDelegate` cannot sit on the `@Observable`
    /// controller; same thin-proxy pattern as the pre-Kokoro `DelegateProxy`.
    private final class DelegateProxy: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
        weak var owner: SystemTTSService?

        func speechSynthesizer(
            _ synthesizer: AVSpeechSynthesizer,
            didFinish utterance: AVSpeechUtterance
        ) {
            Task { @MainActor [weak owner] in
                owner?.handleUtteranceEnded()
            }
        }

        func speechSynthesizer(
            _ synthesizer: AVSpeechSynthesizer,
            didCancel utterance: AVSpeechUtterance
        ) {
            Task { @MainActor [weak owner] in
                owner?.handleUtteranceEnded()
            }
        }

        func speechSynthesizer(
            _ synthesizer: AVSpeechSynthesizer,
            willSpeakRangeOfSpeechString characterRange: NSRange,
            utterance: AVSpeechUtterance
        ) {
            let text = utterance.speechString
            guard let range = Range(characterRange, in: text) else { return }
            let fragment = String(text[range])
            Task { @MainActor [weak owner] in
                owner?.pulseSpeechEnergy(spokenFragment: fragment)
            }
        }
    }

}
#endif
