#if os(iOS)
import AVFoundation
import Foundation
import OSLog
import ReadiumNavigator
import ReadiumShared

#if canImport(FluidAudio)
import FluidAudio
#endif

/// Native Kokoro 82M via FluidAudio's staged Core ML graphs.
///
/// `KokoroAneComputeUnits.default` keeps Albert / PostAlbert / Alignment /
/// Vocoder on `cpuAndNeuralEngine` (ANE-resident) and Noise / Tail on GPU.
/// This is not Sherpa and not ONNX Runtime's experimental Core ML EP.
@MainActor
public final class CoreMLKokoroTTSService: TTSService {
    public private(set) var status: TTSServiceStatus = .stopped {
        didSet { onStatusChange?(status) }
    }

    public private(set) var spokenText: String = "" {
        didSet { onSpokenTextChange?(spokenText) }
    }

    public private(set) var speechEnergy: Double = 0
    public private(set) var speechEnergySeed: Double = 0

    public var availableVoices: [TTSVoice] = KokoroVoiceCatalog.installedVoices()

    public var onStatusChange: ((TTSServiceStatus) -> Void)?
    public var onSpokenTextChange: ((String) -> Void)?
    public var onSpeechEnergyPulse: ((Double, Double) -> Void)?
    public var onSpeechSpectrum: ((SpeechSpectrum) -> Void)?
    public var onAdvance: ((Locator) -> Void)?
    public var onSpokenRange: ((Locator) -> Void)?

    private var activeTask: Task<Void, Never>?
    /// The prefetch is an *unstructured* `Task`, so cancelling `activeTask`
    /// does not reach it. Type-erased so the property needs no `#if`.
    private var cancelPrefetch: (() -> Void)?
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var playerAttached = false
    private var playbackFormat: AVAudioFormat?
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
    private var currentSpeed: Float = 1.0
    private var currentVoice: String = KokoroVoiceCatalog.defaultIdentifier(
        among: KokoroVoiceCatalog.installedVoices()
    )
    private let phonemeCache = KokoroSpeechSessionCache()
    private let pronunciations = KokoroPronunciationStore()

    public init() {
        attachPlayerNodeIfNeeded()
    }

    public func speak(units: [TTSSpeechUnit]) async throws {
        resetPlayback(notifyStopped: false)

        guard KokoroAneAvailability.isUsableForPlayback else {
            Log.tts.error("Kokoro Neural Engine pack is not installed")
            status = .unavailable
            return
        }

        let utterances = TTSSpeechUnit.kokoroUtterances(from: units)
        guard !utterances.isEmpty else { return }

        try activateAudioSession()

        #if canImport(FluidAudio)
        let manager = try await CoreMLKokoroPackInstaller.shared.readyManager()
        let (lexicon, lexiconRevision) = pronunciations.resolved()
        // `KokoroAneManager` is an actor: without `await` the lexicon lands
        // *after* the first utterances synthesize (and it is a hard error in
        // Swift 6 language mode).
        await manager.setEnglishCustomLexicon(lexicon)
        #else
        status = .unavailable
        return
        #endif

        status = .playing
        let speed = currentSpeed
        let voice = currentVoice

        activeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            #if canImport(FluidAudio)
            var prefetched: PreparedClip?
            for index in utterances.indices {
                guard !Task.isCancelled, self.status != .stopped else { return }
                await self.waitWhilePaused()
                guard !Task.isCancelled, self.status == .playing else { return }

                let utterance = utterances[index]
                self.spokenText = utterance.text
                if let locator = utterance.locator {
                    self.onAdvance?(locator)
                    self.onSpokenRange?(locator)
                }

                let clip: PreparedClip
                do {
                    if let prefetched {
                        clip = prefetched
                    } else {
                        clip = try await self.prepareClip(
                            utterance: utterance,
                            isLast: index == utterances.indices.last,
                            manager: manager,
                            voice: voice,
                            speed: speed,
                            lexiconRevision: lexiconRevision
                        )
                    }
                    prefetched = nil
                } catch is CancellationError {
                    return
                } catch {
                    Log.tts.error(
                        "Kokoro ANE synthesize failed: \(error.localizedDescription, privacy: .public)"
                    )
                    self.status = .unavailable
                    return
                }

                let nextIndex = utterances.index(after: index)
                let prefetch: Task<PreparedClip, Error>?
                if nextIndex < utterances.endIndex {
                    let next = utterances[nextIndex]
                    let task = Task {
                        try await self.prepareClip(
                            utterance: next,
                            isLast: nextIndex == utterances.indices.last,
                            manager: manager,
                            voice: voice,
                            speed: speed,
                            lexiconRevision: lexiconRevision
                        )
                    }
                    self.cancelPrefetch = { task.cancel() }
                    prefetch = task
                } else {
                    prefetch = nil
                }

                Log.tts.info(
                    "Kokoro ANE \(clip.timingsMs, privacy: .public)ms phonemes=\(clip.phonemeCount, privacy: .public)"
                )
                await self.play(clip: clip)

                if let prefetch {
                    do {
                        prefetched = try await prefetch.value
                    } catch is CancellationError {
                        return
                    } catch {
                        prefetched = nil
                    }
                    self.cancelPrefetch = nil
                }
            }
            #endif
            guard !Task.isCancelled else { return }
            self.finishNaturally()
        }
    }

    #if canImport(FluidAudio)
    private struct PreparedClip {
        let samples: [Float]
        let sampleRate: Double
        let timingsMs: Double
        let phonemeCount: Int
        /// Per-frame spectrogram, measured off the main actor at synthesis and
        /// replayed against the playhead. We hold the whole clip before a
        /// sample plays, so a realtime tap would buy nothing but jitter and an
        /// audio-thread hop.
        let spectrum: [SpeechSpectrum]
    }

    /// `nonisolated` on purpose: the project builds with
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so without this the
    /// per-sample RMS/zero-crossing scan in `KokoroPauseAssembler` and the
    /// whole packing pass run on the main thread for every utterance. Only
    /// `phonemeCache` (lock-guarded) and the `manager` actor are touched.
    private nonisolated func prepareClip(
        utterance: KokoroUtterance,
        isLast: Bool,
        manager: KokoroAneManager,
        voice: String,
        speed: Float,
        lexiconRevision: String
    ) async throws -> PreparedClip {
        var queue = [utterance.text]
        var samples: [Float] = []
        var totalMs = 0.0
        var phonemeCount = 0
        var sampleRate = KokoroPauseAssembler.sampleRate

        while !queue.isEmpty {
            let text = queue.removeFirst()
            let ipa = try await cachedPhonemes(
                for: text,
                manager: manager,
                revision: lexiconRevision
            )
            if ipa.count > KokoroPhonemeBudget.splitThreshold {
                let sentences = KokoroUtterancePacker.completeSentences(in: text)
                if sentences.count > 1 {
                    let mid = max(1, sentences.count / 2)
                    queue.insert(contentsOf: [
                        sentences[..<mid].joined(separator: " "),
                        sentences[mid...].joined(separator: " ")
                    ], at: 0)
                    continue
                }
                let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                if words.count > 1 {
                    let mid = max(1, words.count / 2)
                    queue.insert(contentsOf: [
                        words[..<mid].joined(separator: " "),
                        words[mid...].joined(separator: " ")
                    ], at: 0)
                    continue
                }
                // No sentence or word boundary to cut on: an unspaced CJK run,
                // a long URL, a keysmash. Splitting is driven by
                // `splitThreshold` for prosody, but the reason there is a
                // last resort at all is `modelLimit`: `KokoroAneVocab.encode`
                // *throws* above it, ending Read Aloud for the whole chapter.
                // Halve the raw text instead. Halving terminates.
                if text.count > 1 {
                    let mid = text.index(text.startIndex, offsetBy: text.count / 2)
                    queue.insert(contentsOf: [
                        String(text[..<mid]),
                        String(text[mid...])
                    ], at: 0)
                    continue
                }
            }

            // Bracket the exact call that SIGSEGVs inside libBNNS. A marker
            // surviving to the next launch is the only signal that this
            // happened — see `KokoroAneHealth`.
            KokoroAneHealth.beginSynthesis()
            // `defer`, not a trailing call: an ordinary thrown error must not
            // leave the marker behind and be miscounted as a crash.
            defer { KokoroAneHealth.endSynthesis() }
            let result = try await manager.synthesizeFromPhonemesDetailed(
                ipa,
                voice: voice,
                speed: speed
            )
            let pause: KokoroBoundary = queue.isEmpty
                ? (isLast ? .none : utterance.pauseAfter)
                : .continuation
            samples.append(contentsOf: KokoroPauseAssembler.assemble(
                samples: result.samples,
                sampleRate: Double(result.sampleRate),
                pauseAfter: pause,
                speed: speed
            ))
            totalMs += result.timings.totalMs
            phonemeCount += ipa.count
            sampleRate = Double(result.sampleRate)
        }

        return PreparedClip(
            samples: samples,
            sampleRate: sampleRate,
            timingsMs: totalMs,
            phonemeCount: phonemeCount,
            spectrum: SpeechSpectrum.analyze(samples: samples, sampleRate: sampleRate)
        )
    }

    private nonisolated func cachedPhonemes(
        for text: String,
        manager: KokoroAneManager,
        revision: String
    ) async throws -> String {
        if let cached = phonemeCache.phonemeString(for: text, revision: revision) {
            return cached
        }
        let ipa = try await manager.phonemes(for: text)
        phonemeCache.store(phonemes: ipa, for: text, revision: revision)
        return ipa
    }
    #endif

    public func pause() {
        guard status == .playing else { return }
        status = .paused
        if playerNode.isPlaying { playerNode.pause() }
        engine.pause()
    }

    public func resume() {
        guard status == .paused else { return }
        status = .playing
        do {
            try engine.start()
            playerNode.play()
        } catch {
            Log.tts.error("Kokoro ANE resume failed: \(error.localizedDescription, privacy: .public)")
            status = .unavailable
            return
        }
        let waiters = pauseWaiters
        pauseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    public func stop() {
        resetPlayback(notifyStopped: true)
    }

    public func setVoice(id: String) {
        if availableVoices.contains(where: { $0.identifier == id }) {
            currentVoice = id
        }
    }

    public func setRate(_ rate: Float) {
        currentSpeed = max(0.5, min(2.0, rate))
    }

    public func setPitch(_: Float) {}

    private func finishNaturally() {
        guard status != .stopped else { return }
        status = .stopped
        spokenText = ""
        speechEnergy = 0
    }

    private func resetPlayback(notifyStopped: Bool) {
        activeTask?.cancel()
        activeTask = nil
        cancelPrefetch?()
        cancelPrefetch = nil
        phonemeCache.clear()
        if playerNode.isPlaying { playerNode.stop() }
        playerNode.reset()
        if engine.isRunning { engine.stop() }
        let waiters = pauseWaiters
        pauseWaiters.removeAll()
        waiters.forEach { $0.resume() }
        if notifyStopped {
            status = .stopped
            spokenText = ""
            speechEnergy = 0
        }
    }

    private func waitWhilePaused() async {
        while status == .paused {
            await withCheckedContinuation { pauseWaiters.append($0) }
        }
    }

    private func play(clip: PreparedClip) async {
        let samples = clip.samples
        let sampleRate = clip.sampleRate
        guard status == .playing, !samples.isEmpty else { return }
        configureEngineGraph(sampleRate: sampleRate)
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            Log.tts.error("AVAudioEngine.start failed: \(error.localizedDescription, privacy: .public)")
            status = .unavailable
            return
        }

        guard let format = playbackFormat,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
              )
        else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            guard let base = src.baseAddress, let dest = buffer.floatChannelData?[0] else { return }
            dest.update(from: base, count: samples.count)
        }

        let energy = KokoroPlaybackAnalysis.waveformEnergy(samples: samples)
        speechEnergy = energy
        speechEnergySeed = Double.random(in: 0...1)
        onSpeechEnergyPulse?(speechEnergy, speechEnergySeed)

        // Walk the measured spectrogram in step with playback. Elapsed time is
        // accumulated only while `.playing`, so a pause freezes the bars with
        // the audio instead of letting wall-clock run the display ahead.
        let spectrum = clip.spectrum
        let ticker = Task { @MainActor [weak self] in
            let interval = 1.0 / 30.0
            var elapsed = 0.0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                guard self.status == .playing else { continue }
                elapsed += interval
                self.onSpeechSpectrum?(
                    SpeechSpectrum.frame(in: spectrum, at: elapsed, sampleRate: sampleRate)
                )
            }
        }
        defer { ticker.cancel() }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            playerNode.scheduleBuffer(buffer) {
                continuation.resume()
            }
            if !playerNode.isPlaying { playerNode.play() }
        }
    }

    private func attachPlayerNodeIfNeeded() {
        guard !playerAttached else { return }
        engine.attach(playerNode)
        playerAttached = true
    }

    private func configureEngineGraph(sampleRate: Double) {
        attachPlayerNodeIfNeeded()
        engine.disconnectNodeOutput(playerNode)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )
        playbackFormat = format
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    }

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
}
#endif
