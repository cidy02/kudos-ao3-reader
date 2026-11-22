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
    /// Monotonic token incremented on every `resetPlayback` so a cancelled `speak`
    /// waking up after setup awaits (`readyManager`, lexicon, observer) can never
    /// publish `.playing` or start audio after Stop or reader teardown.
    private var playbackGeneration: UInt64 = 0
    /// The prefetch is an *unstructured* `Task`, so cancelling `activeTask`
    /// does not reach it. Type-erased so the property needs no `#if`.
    private var cancelPrefetch: (() -> Void)?
    #if DEBUG
    /// Test seams. They replace only the parts that need the 180 MB pack or real
    /// audio hardware; `speak`'s ordering (generation checks, status, task launch)
    /// and the playback loop (arm -> announce -> hold while paused -> play) are the
    /// production code.
    /// Replaces availability + audio-session + Core ML pack/manager setup.
    var testSetupOverride: (() async throws -> Void)?
    /// Stand in for the manager's lexicon / fallback-observer steps (only used when
    /// `testSetupOverride` replaced the manager), so the generation checks after each
    /// production suspension point are the real ones.
    var testLexiconStep: (() async -> Void)?
    var testObserverStep: (() async -> Void)?
    /// Replaces one utterance's synthesis: returns the raw synthesized samples.
    var testSynthesize: ((String) async throws -> [Float])?
    /// Replaces graph configuration + `AVAudioEngine.start()` (may throw).
    var testStartAudioEngine: (() throws -> Void)?
    /// Replaces scheduling the buffer and awaiting its playback; gets the sample count.
    var testPlayBuffer: ((Int) async -> Void)?
    var testDidStartPlaybackTask = false
    #endif
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

    /// One utterance's PCM (silence for a pause already appended). `Sendable` closure
    /// so the playback loop's prefetch can run it off the main actor.
    private typealias SynthesizeClip = @Sendable (KokoroUtterance, Bool, Float) async throws -> PreparedClip

    @discardableResult
    public func speak(units: [TTSSpeechUnit]) async throws -> Bool {
        resetPlayback(notifyStopped: false)
        let generation = playbackGeneration
        guard !Task.isCancelled else { return false }

        #if DEBUG
        let seamed = testSetupOverride != nil
        #else
        let seamed = false
        #endif

        if !seamed {
            guard KokoroAneAvailability.isUsableForPlayback else {
                Log.tts.error("Kokoro Neural Engine pack is not installed")
                status = .unavailable
                return false
            }
        }

        let utterances = TTSSpeechUnit.kokoroUtterances(from: units)
        guard !utterances.isEmpty else { return false }

        if !seamed { try activateAudioSession() }

        #if canImport(FluidAudio)
        var realManager: KokoroAneManager?
        #if DEBUG
        if let testSetupOverride {
            try await testSetupOverride()
        } else {
            realManager = try await CoreMLKokoroPackInstaller.shared.readyManager()
        }
        #else
        realManager = try await CoreMLKokoroPackInstaller.shared.readyManager()
        #endif
        guard isCurrentStart(generation) else { return false }
        var lexiconRevision = ""
        if let manager = realManager {
            let (lexicon, revision) = pronunciations.resolved()
            lexiconRevision = revision
            // `KokoroAneManager` is an actor: without `await` the lexicon lands
            // *after* the first utterances synthesize (and it is a hard error in
            // Swift 6 language mode).
            await manager.setEnglishCustomLexicon(lexicon)
        } else {
            #if DEBUG
            await testLexiconStep?()
            #endif
        }
        guard isCurrentStart(generation) else { return false }
        // Record what the model had to guess at, so the reader can correct it
        // later. Buffered, not written per word: the observer fires inside
        // synthesis and a disk write there would sit on the path that has to
        // keep audio fed. Flushed when playback stops.
        if let manager = realManager {
            let collector = guessedWords
            await manager.setNeuralFallbackObserver { word in
                collector.add(word)
            }
        } else {
            #if DEBUG
            await testObserverStep?()
            #endif
        }
        guard isCurrentStart(generation) else { return false }
        let voice = currentVoice
        let synthesize: SynthesizeClip
        if let manager = realManager {
            let revision = lexiconRevision
            synthesize = { [self] utterance, isLast, speed in
                try await prepareClip(
                    utterance: utterance,
                    isLast: isLast,
                    manager: manager,
                    voice: voice,
                    speed: speed,
                    lexiconRevision: revision
                )
            }
        } else {
            #if DEBUG
            let synthesizeSeam = testSynthesize
            synthesize = { utterance, _, _ in
                let raw = try await synthesizeSeam?(utterance.text) ?? [0.1, -0.1]
                return PreparedClip(
                    samples: raw,
                    sampleRate: KokoroPauseAssembler.sampleRate,
                    timingsMs: 0,
                    phonemeCount: 0,
                    spectrum: []
                )
            }
            #else
            return false
            #endif
        }
        return beginPlayback(utterances: utterances, generation: generation, synthesize: synthesize)
        #else
        status = .unavailable
        return false
        #endif
    }

    /// Publishes `.playing` and launches the loop. The loop itself announces nothing
    /// (`onAdvance` / caption) until the first clip is synthesized *and* the audio
    /// engine has started, so a controller commit always means audio is imminent.
    private func beginPlayback(
        utterances: [KokoroUtterance],
        generation: UInt64,
        synthesize: @escaping SynthesizeClip
    ) -> Bool {
        status = .playing
        // Speed is deliberately *not* captured here. It used to be, which
        // meant dragging the rate slider did nothing until the next batch —
        // for a chapter-long batch, effectively never. Each clip reads the
        // live value instead, so a change lands one clip later (the next one
        // is already prefetched and rendered at the old rate).
        //
        // Voice stays captured: switching narrator mid-chapter should finish
        // the chapter in the voice it started in.
        #if DEBUG
        testDidStartPlaybackTask = true
        #endif
        activeTask = Task { @MainActor [weak self] in
            await self?.runPlaybackLoop(
                utterances: utterances,
                generation: generation,
                synthesize: synthesize
            )
        }
        return true
    }

    private func runPlaybackLoop(
        utterances: [KokoroUtterance],
        generation: UInt64,
        synthesize: @escaping SynthesizeClip
    ) async {
        var prefetched: PreparedClip?
        for index in utterances.indices {
            guard isCurrentStart(generation), status != .stopped else { return }
            await waitWhilePaused()
            guard isCurrentStart(generation), status == .playing else { return }

            let utterance = utterances[index]
            let clip: PreparedClip
            do {
                if let prefetched {
                    clip = prefetched
                } else {
                    clip = try await synthesize(
                        utterance,
                        index == utterances.indices.last,
                        currentSpeed
                    )
                }
                prefetched = nil
            } catch is CancellationError {
                return
            } catch {
                guard isCurrentStart(generation) else { return }
                Log.tts.error(
                    "Kokoro ANE synthesize failed: \(error.localizedDescription, privacy: .public)"
                )
                status = .unavailable
                return
            }

            guard isCurrentStart(generation), status != .stopped else { return }
            guard !clip.samples.isEmpty else { continue }

            // Start the audio engine and build the buffer *before* announcing the
            // utterance: the controller moves the page and saves the position on
            // that announcement, so it must only happen once audio can really
            // start. A failure here goes `.unavailable` with nothing committed.
            guard let armed = arm(clip) else {
                if status == .unavailable { return }
                continue
            }
            guard isCurrentStart(generation), status != .stopped else { return }

            // Hold the armed clip while paused: a paused skip must not announce (move
            // the page, save the position) until Play lets speech at it start.
            await waitWhilePaused()
            guard isCurrentStart(generation), status == .playing else { return }

            // Announce immediately before scheduling, with no suspension between.
            if let locator = utterance.locator {
                onAdvance?(locator)
            }
            guard isCurrentStart(generation), status != .stopped else { return }
            spokenText = utterance.text
            if let locator = utterance.locator {
                onSpokenRange?(locator)
            }
            // The announcement itself may pause (a request that wanted it).
            await waitWhilePaused()
            guard isCurrentStart(generation), status == .playing else { return }

            let nextIndex = utterances.index(after: index)
            let prefetch: Task<PreparedClip, Error>?
            if nextIndex < utterances.endIndex {
                let next = utterances[nextIndex]
                let isLast = nextIndex == utterances.indices.last
                let speed = currentSpeed
                let task = Task { try await synthesize(next, isLast, speed) }
                cancelPrefetch = { task.cancel() }
                prefetch = task
            } else {
                prefetch = nil
            }

            Log.tts.info(
                "Kokoro ANE \(clip.timingsMs, privacy: .public)ms phonemes=\(clip.phonemeCount, privacy: .public)"
            )
            await play(armed)

            if let prefetch {
                do {
                    prefetched = try await prefetch.value
                } catch is CancellationError {
                    return
                } catch {
                    prefetched = nil
                }
                cancelPrefetch = nil
            }
        }
        guard isCurrentStart(generation) else { return }
        finishNaturally()
    }

    private func isCurrentStart(_ generation: UInt64) -> Bool {
        !Task.isCancelled && playbackGeneration == generation
    }

    private struct PreparedClip: @unchecked Sendable {
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

    #if canImport(FluidAudio)
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
            // An empty synthesis stays empty: `KokoroPauseAssembler.assemble` adds no
            // structural silence to it (tested there), so the clip is rejected.
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
            #if DEBUG
            if let testStartAudioEngine {
                try testStartAudioEngine()
            } else {
                try engine.start()
                playerNode.play()
            }
            #else
            try engine.start()
            playerNode.play()
            #endif
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
        guessedWords.flush()
    }

    /// Buffers words the model guessed at, and writes them once at the end.
    ///
    /// A final class with a lock rather than an actor: the observer closure is
    /// `@Sendable` and synchronous, called from inside synthesis, so it cannot
    /// await. The lock is held only to append to an array.
    final class GuessedWordCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var pending: [String] = []
        private let store = KokoroGuessedWordStore()

        func add(_ word: String) {
            lock.lock()
            pending.append(word)
            lock.unlock()
        }

        /// Write and clear. Failure is deliberately silent: this is a
        /// convenience list, and losing it must never interrupt reading.
        func flush() {
            lock.lock()
            let batch = pending
            pending.removeAll(keepingCapacity: true)
            lock.unlock()
            guard !batch.isEmpty else { return }
            try? store.record(batch)
        }
    }

    private let guessedWords = GuessedWordCollector()

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
        playbackGeneration &+= 1
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
        // Like the Apple and sherpa engines: a stop never overwrites `.unavailable`.
        if notifyStopped, status != .unavailable {
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

    /// A clip whose audio path is ready: engine running, buffer built. Nothing is
    /// scheduled yet, so a paused skip can hold it for Resume.
    private struct ArmedClip {
        let clip: PreparedClip
        let buffer: AVAudioPCMBuffer?
    }

    /// Starts the audio engine and builds the clip's buffer without scheduling it.
    /// Returns nil when that cannot be done; `AVAudioEngine.start()` failing also
    /// takes the engine `.unavailable` (before the caller has announced anything).
    private func arm(_ clip: PreparedClip) -> ArmedClip? {
        let samples = clip.samples
        guard status != .stopped, status != .unavailable, !samples.isEmpty else { return nil }
        #if DEBUG
        if let testStartAudioEngine {
            do {
                try testStartAudioEngine()
            } catch {
                status = .unavailable
                return nil
            }
            return ArmedClip(clip: clip, buffer: nil)
        }
        #endif
        configureEngineGraph(sampleRate: clip.sampleRate)
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            Log.tts.error("AVAudioEngine.start failed: \(error.localizedDescription, privacy: .public)")
            status = .unavailable
            return nil
        }
        // A pause that landed while this clip was synthesizing: keep the engine
        // quiet until Resume (which restarts it).
        if status == .paused { engine.pause() }

        guard let format = playbackFormat,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
              )
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            guard let base = src.baseAddress, let dest = buffer.floatChannelData?[0] else { return }
            dest.update(from: base, count: samples.count)
        }
        return ArmedClip(clip: clip, buffer: buffer)
    }

    private func play(_ armed: ArmedClip) async {
        let clip = armed.clip
        let samples = clip.samples
        let sampleRate = clip.sampleRate
        guard status == .playing, !samples.isEmpty else { return }
        #if DEBUG
        if let testPlayBuffer {
            await testPlayBuffer(samples.count)
            return
        }
        #endif
        guard let buffer = armed.buffer else { return }

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
