import AVFoundation
import Foundation
import OSLog
import ReadiumNavigator
import ReadiumShared

#if canImport(SherpaOnnx)
@preconcurrency import SherpaOnnx
#elseif canImport(sherpa_onnx)
import sherpa_onnx
#else
#error("sherpa-onnx Swift module is not linked (expected import SherpaOnnx)")
#endif

/// Offline Kokoro TTS via sherpa-onnx, playing through `AVAudioEngine`.
///
/// The SPM product is `sherpa-onnx` and the Swift target/module is `SherpaOnnx`.
/// The C++ wrapper type is `SherpaOnnxOfflineTtsWrapper` (not a fictional
/// `SherpaOnnxOfflineTts` class). Configs are built with the package's
/// `sherpaOnnxOfflineTts*` helpers so C-string fields stay valid.
@MainActor
public final class SherpaKokoroTTSService: TTSService {

    public private(set) var status: TTSServiceStatus = .stopped {
        didSet { onStatusChange?(status) }
    }

    public private(set) var spokenText: String = "" {
        didSet { onSpokenTextChange?(spokenText) }
    }

    public private(set) var speechEnergy: Double = 0
    public private(set) var speechEnergySeed: Double = 0

    public var availableVoices: [TTSVoice] = SherpaKokoroTTSService.catalogVoices

    public var onStatusChange: ((TTSServiceStatus) -> Void)?
    public var onSpokenTextChange: ((String) -> Void)?
    public var onSpeechEnergyPulse: ((Double, Double) -> Void)?
    public var onAdvance: ((Locator) -> Void)?
    public var onSpokenRange: ((Locator) -> Void)?

    private var activeTask: Task<Void, Never>?
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var playerAttached = false
    private var playbackFormat: AVAudioFormat?
    private var hasScheduledPlayback = false
    private var playbackStartedAt: Date?
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
    private var speechEnergyTask: Task<Void, Never>?
    private var speechEnergyEnvelopes: [SpeechEnergyEnvelope] = []
    private var speechEnergyWaiter: CheckedContinuation<SpeechEnergyEnvelope?, Never>?

    private var tts: SherpaOnnxOfflineTtsWrapper?
    private let modelDirectory: URL
    private static let synthesisQueue = DispatchQueue(
        label: "com.cidy02.Kudos.tts.synthesis",
        qos: .userInitiated
    )
    private static let requiredFollowingAudioSeconds = 1.5

    private var currentSpeed: Float = 1.0
    private var currentVoiceId: Int = 0

    /// Display names for kokoro-int8-en-v0_19 speaker IDs (sherpa-onnx docs).
    private static let catalogVoices: [TTSVoice] = {
        let language = Language(code: .bcp47("en"))
        let names = [
            "Default",
            "Bella",
            "Nicole",
            "Sarah",
            "Sky",
            "Adam",
            "Michael",
            "Emma",
            "Isabella",
            "George",
            "Lewis"
        ]
        return names.enumerated().map { index, name in
            TTSVoice(
                identifier: String(index),
                language: language,
                name: name,
                gender: index <= 4 || index == 7 || index == 8 ? .female : .male,
                quality: .higher
            )
        }
    }()

    public init(modelDirectory: URL) {
        self.modelDirectory = modelDirectory
        attachPlayerNodeIfNeeded()
    }

    public func speak(units: [TTSSpeechUnit]) async throws {
        resetPlayback(notifyStopped: false)

        // The sherpa Kokoro frontend is configured for one sentence. Supplying
        // complete sentence units preserves punctuation/prosody and avoids
        // handing it a short paragraph that can end mid-thought.
        let chunks = TTSSpeechUnit.sentenceChunks(from: units)
        guard !chunks.isEmpty else { return }

        guard loadEngineIfNeeded(), let tts else {
            Log.tts.error("Kokoro engine unavailable — model missing or failed to load")
            status = .unavailable
            return
        }

        try activateAudioSession()
        let reportedSampleRate = Double(tts.sampleRate)
        let sampleRate = reportedSampleRate > 0 ? reportedSampleRate : 24_000
        configureEngineGraph(sampleRate: sampleRate)

        do {
            try engine.start()
        } catch {
            Log.tts.error("AVAudioEngine.start failed: \(error.localizedDescription, privacy: .public)")
            status = .unavailable
            throw error
        }

        status = .playing
        let speed = currentSpeed
        let sid = currentVoiceId
        let engineRef = tts

        activeTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let synthesis = SynthesisRequest(
                tts: engineRef,
                sid: sid,
                speed: speed,
                sampleRate: sampleRate
            )
            var primed: [GeneratedTextChunk] = []
            var nextStartIndex = 0
            var sourceExhausted = false

            // Keep enough generated PCM *after* the currently playing buffer
            // to cover a slow following inference. This is deliberately a
            // bounded in-memory audio cache: normally 1.5 seconds of following
            // audio, not an unbounded chapter cache. A sentence can overshoot
            // the target because sentence boundaries remain intact.
            while !Task.isCancelled,
                  KokoroPlaybackAnalysis.needsMoreQueuedAudio(
                    queuedAudioSeconds: primed.map {
                        Double($0.generated.samples.count) / sampleRate
                    },
                    requiredFollowingAudioSeconds: Self.requiredFollowingAudioSeconds
                  ) {
                await self.waitWhilePaused()
                guard !Task.isCancelled, self.status != .stopped else { return }

                guard let next = await Self.generateNextAudibleChunk(
                    request: synthesis,
                    chunks: chunks,
                    startingAt: nextStartIndex
                ) else {
                    sourceExhausted = true
                    break
                }
                primed.append(next)
                nextStartIndex = next.index + 1
            }

            guard !primed.isEmpty else {
                self.finishNaturally()
                return
            }

            // Nothing is scheduled until the whole initial lead is ready. That
            // keeps pause/resume from starting a lone first sentence mid-prime.
            await self.waitWhilePaused()
            guard !Task.isCancelled, self.status == .playing else { return }

            var queued: [(chunk: GeneratedTextChunk, playback: ScheduledPlayback)] = []
            for chunk in primed {
                guard let playback = self.enqueue(
                    unit: chunk.unit,
                    samples: chunk.generated.samples,
                    energyEnvelope: chunk.generated.energyEnvelope,
                    seed: Double.random(in: 0...1),
                    startsPlayback: false
                ) else {
                    self.finishNaturally()
                    return
                }
                queued.append((chunk, playback))
            }
            self.startPlayerIfNeeded()
            let followingAudioSeconds = queued.dropFirst()
                .map { $0.playback.audioSeconds }
                .reduce(0, +)
            let primingMessage = (
                "Kokoro playback primed with \(queued.count) PCM buffers; "
                    + "followingAudio=\(followingAudioSeconds)s"
            )
            Log.tts.debug("\(primingMessage, privacy: .public)")

            while !Task.isCancelled {
                await self.waitWhilePaused()
                guard !Task.isCancelled, self.status != .stopped else { return }

                if !sourceExhausted,
                   KokoroPlaybackAnalysis.needsMoreQueuedAudio(
                    queuedAudioSeconds: queued.map { $0.playback.audioSeconds },
                    requiredFollowingAudioSeconds: Self.requiredFollowingAudioSeconds
                   ) {
                    guard let next = await Self.generateNextAudibleChunk(
                        request: synthesis,
                        chunks: chunks,
                        startingAt: nextStartIndex
                    ) else {
                        sourceExhausted = true
                        continue
                    }
                    nextStartIndex = next.index + 1

                    await self.waitWhilePaused()
                    guard !Task.isCancelled, self.status == .playing else { return }
                    guard let playback = self.enqueue(
                        unit: next.unit,
                        samples: next.generated.samples,
                        energyEnvelope: next.generated.energyEnvelope,
                        seed: Double.random(in: 0...1)
                    ) else {
                        Log.tts.error("Kokoro could not enqueue a generated audio buffer")
                        await self.waitForPlaybackDrain()
                        break
                    }
                    queued.append((next, playback))
                    continue
                }

                guard !queued.isEmpty else { break }
                let oldest = queued.removeFirst()
                await self.waitUntilConsumed(oldest.playback)
                guard !Task.isCancelled, self.status != .stopped else { return }

                if sourceExhausted, queued.isEmpty {
                    await self.waitForPlaybackDrain()
                    break
                }
            }

            self.finishNaturally()
        }
    }

    public func pause() {
        guard status == .playing else { return }
        playerNode.pause()
        status = .paused
    }

    public func resume() {
        guard status == .paused else { return }
        if !engine.isRunning {
            try? engine.start()
        }
        status = .playing
        startPlayerIfNeeded()
        resumePauseWaiters()
    }

    public func stop() {
        resetPlayback(notifyStopped: true)
    }

    public func setVoice(id: String) {
        if let sid = Int(id) {
            currentVoiceId = sid
        }
    }

    public func setRate(_ rate: Float) {
        currentSpeed = max(0.5, min(2.0, rate))
    }

    public func setPitch(_: Float) {
        // Sherpa-onnx Kokoro has no dynamic pitch control.
    }

    // MARK: - Engine

    @discardableResult
    private func loadEngineIfNeeded() -> Bool {
        if let tts, tts.tts != nil { return true }

        let modelPath = modelDirectory.appendingPathComponent("model.int8.onnx").path
        let voicesPath = modelDirectory.appendingPathComponent("voices.bin").path
        let tokensPath = modelDirectory.appendingPathComponent("tokens.txt").path
        let dataDir = modelDirectory.appendingPathComponent("espeak-ng-data").path

        let fm = FileManager.default
        guard fm.fileExists(atPath: modelPath),
              fm.fileExists(atPath: voicesPath),
              fm.fileExists(atPath: tokensPath)
        else {
            return false
        }

        let kokoro = sherpaOnnxOfflineTtsKokoroModelConfig(
            model: modelPath,
            voices: voicesPath,
            tokens: tokensPath,
            dataDir: dataDir,
            lengthScale: 1.0
        )
        let modelConfig = sherpaOnnxOfflineTtsModelConfig(
            kokoro: kokoro,
            numThreads: 2,
            debug: 0,
            provider: "cpu"
        )
        var ttsConfig = sherpaOnnxOfflineTtsConfig(
            model: modelConfig,
            // `sentenceChunks` supplies one natural sentence per generation.
            maxNumSentences: 1
        )
        let wrapper = SherpaOnnxOfflineTtsWrapper(config: &ttsConfig)
        guard wrapper.tts != nil else {
            Log.tts.error("SherpaOnnxCreateOfflineTts returned nil")
            return false
        }

        tts = wrapper
        let count = Int(wrapper.numSpeakers)
        if count > 0 {
            availableVoices = Self.voices(count: count)
        }
        return true
    }

    private static func voices(count: Int) -> [TTSVoice] {
        if count == catalogVoices.count { return catalogVoices }
        let language = Language(code: .bcp47("en"))
        return (0..<count).map { index in
            if catalogVoices.indices.contains(index) {
                return catalogVoices[index]
            }
            return TTSVoice(
                identifier: String(index),
                language: language,
                name: "Voice \(index + 1)",
                gender: .unspecified,
                quality: .higher
            )
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
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playback,
            mode: .spokenAudio,
            policy: .longFormAudio,
            options: []
        )
        try session.setActive(true)
        #endif
    }

    private struct GeneratedChunk: Sendable {
        let samples: [Float]
        let energyEnvelope: [Double]

        static let empty = GeneratedChunk(samples: [], energyEnvelope: [])
    }

    private struct SynthesisRequest: @unchecked Sendable {
        let tts: SherpaOnnxOfflineTtsWrapper
        let sid: Int
        let speed: Float
        let sampleRate: Double
    }

    private struct GeneratedTextChunk: Sendable {
        let index: Int
        let unit: TTSSpeechUnit
        let generated: GeneratedChunk
    }

    private struct SpeechEnergyEnvelope: Sendable {
        let levels: [Double]
        let seed: Double
        let unit: TTSSpeechUnit
    }

    private struct ScheduledPlayback {
        let consumption: AsyncStream<Void>
        let scheduledAt: Date
        let audioSeconds: Double
    }

    /// Schedules a buffer immediately and exposes its data-consumed event. The
    /// event is intentionally used only to bound lookahead, never as audible
    /// playback completion.
    private func enqueue(
        unit: TTSSpeechUnit,
        samples: [Float],
        energyEnvelope: [Double],
        seed: Double,
        startsPlayback: Bool = true
    ) -> ScheduledPlayback? {
        guard status == .playing, !Task.isCancelled else { return nil }
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

        let playerNode = playerNode
        let scheduledAt = Date()
        let audioSeconds = Double(samples.count) / format.sampleRate
        var streamContinuation: AsyncStream<Void>.Continuation?
        let consumption = AsyncStream<Void>(bufferingPolicy: .bufferingNewest(1)) {
            streamContinuation = $0
        }
        guard let streamContinuation else { return nil }

        playerNode.scheduleBuffer(buffer) {
            streamContinuation.yield()
            streamContinuation.finish()
        }
        hasScheduledPlayback = true
        enqueueSpeechEnergy(energyEnvelope, seed: seed, unit: unit)
        if startsPlayback {
            startPlayerIfNeeded()
        }
        return ScheduledPlayback(
            consumption: consumption,
            scheduledAt: scheduledAt,
            audioSeconds: audioSeconds
        )
    }

    private func startPlayerIfNeeded() {
        guard hasScheduledPlayback, !playerNode.isPlaying, status == .playing else { return }
        if playbackStartedAt == nil {
            playbackStartedAt = Date()
        }
        playerNode.play()
        startSpeechEnergyPulsesIfNeeded()
    }

    private func waitUntilConsumed(_ playback: ScheduledPlayback) async {
        var iterator = playback.consumption.makeAsyncIterator()
        _ = await iterator.next()
        let playerElapsed = playbackStartedAt.map { Date().timeIntervalSince($0) }
        let diagnosticMessage = "Kokoro buffer data-consumed; "
            + "queuedFor=\(Date().timeIntervalSince(playback.scheduledAt))s, "
            + "sincePlayerStart=\(playerElapsed ?? -1)s, audio=\(playback.audioSeconds)s"
        Log.tts.debug("\(diagnosticMessage, privacy: .public)")
    }

    /// The default scheduling callback above can fire before a buffer is audible.
    /// A one-frame silent marker waits for the tail of the final real buffer
    /// without making every refill wait for `.dataPlayedBack`.
    private func waitForPlaybackDrain() async {
        await waitWhilePaused()
        guard status == .playing, !Task.isCancelled else { return }
        guard let format = playbackFormat,
              let marker = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)
        else { return }

        marker.frameLength = 1
        marker.floatChannelData?[0][0] = 0

        let playerNode = playerNode
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            playerNode.scheduleBuffer(
                marker,
                completionCallbackType: .dataPlayedBack
            ) { _ in
                continuation.resume()
            }
        }
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
        stopSpeechEnergyPulses()
        playerNode.stop()
        hasScheduledPlayback = false
        playbackStartedAt = nil
        if engine.isRunning {
            engine.stop()
        }
        resumePauseWaiters()
        spokenText = ""
        speechEnergy = 0
        speechEnergySeed = 0
        if notifyStopped, status != .unavailable {
            status = .stopped
        }
    }

    private func finishNaturally() {
        guard !Task.isCancelled else { return }
        activeTask = nil
        stopSpeechEnergyPulses()
        playerNode.stop()
        hasScheduledPlayback = false
        playbackStartedAt = nil
        if engine.isRunning {
            engine.stop()
        }
        spokenText = ""
        speechEnergy = 0
        speechEnergySeed = 0
        if status == .playing {
            status = .stopped
        }
    }
}

private extension SherpaKokoroTTSService {

    private func enqueueSpeechEnergy(
        _ envelope: [Double],
        seed: Double,
        unit: TTSSpeechUnit
    ) {
        guard !envelope.isEmpty else { return }

        let nextEnvelope = SpeechEnergyEnvelope(levels: envelope, seed: seed, unit: unit)
        if let waiter = speechEnergyWaiter {
            speechEnergyWaiter = nil
            waiter.resume(returning: nextEnvelope)
        } else {
            speechEnergyEnvelopes.append(nextEnvelope)
        }

        startSpeechEnergyPulsesIfNeeded()
    }

    private func startSpeechEnergyPulsesIfNeeded() {
        guard speechEnergyTask == nil, playerNode.isPlaying else { return }
        let reportedOutputLatency = engine.outputNode.presentationLatency
        let outputLatency = reportedOutputLatency.isFinite
            ? max(0, reportedOutputLatency)
            : 0
        speechEnergyTask = Task { @MainActor [weak self] in
            if outputLatency > 0 {
                try? await Task.sleep(nanoseconds: UInt64(outputLatency * 1_000_000_000))
            }
            while let self, !Task.isCancelled {
                guard let envelope = await self.nextSpeechEnergyEnvelope() else { return }
                await self.waitWhilePaused()
                guard !Task.isCancelled, self.status == .playing else { return }

                self.spokenText = envelope.unit.text
                if let locator = envelope.unit.locator {
                    self.onAdvance?(locator)
                    self.onSpokenRange?(locator)
                }
                self.speechEnergySeed = envelope.seed

                for energy in envelope.levels {
                    guard !Task.isCancelled else { return }
                    await self.waitWhilePaused()
                    guard !Task.isCancelled, self.status == .playing else { return }

                    self.speechEnergy = energy
                    self.onSpeechEnergyPulse?(energy, envelope.seed)
                    try? await Task.sleep(nanoseconds: 33_333_333)
                }
            }
        }
    }

    private func nextSpeechEnergyEnvelope() async -> SpeechEnergyEnvelope? {
        if !speechEnergyEnvelopes.isEmpty {
            return speechEnergyEnvelopes.removeFirst()
        }

        return await withCheckedContinuation { speechEnergyWaiter = $0 }
    }

    private func stopSpeechEnergyPulses() {
        speechEnergyTask?.cancel()
        speechEnergyTask = nil
        speechEnergyEnvelopes = []
        let waiter = speechEnergyWaiter
        speechEnergyWaiter = nil
        waiter?.resume(returning: nil)
    }

    private static func generateChunk(
        request: SynthesisRequest,
        text: String
    ) async -> GeneratedChunk {
        let cancellation = KokoroSynthesisCancellation()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                synthesisQueue.async {
                    guard !cancellation.isCancelled else {
                        continuation.resume(returning: .empty)
                        return
                    }

                    let startedAt = Date()
                    let audio = request.tts.generate(
                        text: text,
                        sid: request.sid,
                        speed: request.speed
                    )
                    guard !cancellation.isCancelled else {
                        continuation.resume(returning: .empty)
                        return
                    }

                    let synthesisSeconds = Date().timeIntervalSince(startedAt)
                    let diagnostics = KokoroPlaybackAnalysis.sampleDiagnostics(samples: audio.samples)
                    let audioSeconds = request.sampleRate > 0
                        ? Double(audio.samples.count) / request.sampleRate
                        : 0
                    let energyEnvelope = KokoroPlaybackAnalysis.waveformEnergyEnvelope(
                        samples: audio.samples,
                        sampleRate: request.sampleRate
                    )
                    let diagnosticMessage = (
                        "Kokoro chunk generated \(audio.samples.count) frames in \(synthesisSeconds)s; "
                            + "audio=\(audioSeconds)s, min=\(diagnostics.minimum), "
                            + "max=\(diagnostics.maximum), peak=\(diagnostics.peak), "
                            + "edgesRMS=\(diagnostics.leadingEdgeRMS)->\(diagnostics.trailingEdgeRMS), "
                            + "outOfRange=\(diagnostics.outOfRange), nonFinite=\(diagnostics.nonFinite)"
                    )
                    Log.tts.debug("\(diagnosticMessage, privacy: .public)")
                    continuation.resume(returning: GeneratedChunk(
                        samples: audio.samples,
                        energyEnvelope: energyEnvelope
                    ))
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private static func generateNextAudibleChunk(
        request: SynthesisRequest,
        chunks: [TTSSpeechUnit],
        startingAt: Int
    ) async -> GeneratedTextChunk? {
        guard !Task.isCancelled, startingAt < chunks.count else { return nil }

        for index in startingAt..<chunks.count {
            guard !Task.isCancelled else { return nil }
            let unit = chunks[index]
            let generated = await generateChunk(request: request, text: unit.text)
            guard !Task.isCancelled else { return nil }
            if !generated.samples.isEmpty {
                return GeneratedTextChunk(index: index, unit: unit, generated: generated)
            }
        }
        return nil
    }
}
