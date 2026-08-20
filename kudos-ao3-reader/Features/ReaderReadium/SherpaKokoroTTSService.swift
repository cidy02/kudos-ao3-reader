import AVFoundation
import Foundation
import OSLog
import ReadiumNavigator
import ReadiumShared

#if canImport(SherpaOnnx)
import SherpaOnnx
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

    private var activeTask: Task<Void, Never>?
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var playerAttached = false
    private var playbackFormat: AVAudioFormat?
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []

    private var tts: SherpaOnnxOfflineTtsWrapper?
    private let modelDirectory: URL
    private static let synthesisQueue = DispatchQueue(
        label: "com.cidy02.Kudos.tts.synthesis",
        qos: .userInitiated
    )

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

    public func speak(text: String, startLocator: Locator?) async throws {
        resetPlayback(notifyStopped: false)

        let chunks = TextChunker.chunk(text: text)
        guard !chunks.isEmpty else { return }

        guard loadEngineIfNeeded(), let tts else {
            Log.tts.error("Kokoro engine unavailable — model missing or failed to load")
            status = .unavailable
            return
        }

        try activateAudioSession()
        let sampleRate = Double(tts.sampleRate)
        configureEngineGraph(sampleRate: sampleRate > 0 ? sampleRate : 24_000)

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

        activeTask = Task { [weak self] in
            for chunk in chunks {
                guard let self, !Task.isCancelled else { break }
                await self.waitWhilePaused()
                guard !Task.isCancelled, self.status != .stopped else { break }

                self.spokenText = chunk
                if let startLocator {
                    self.onAdvance?(startLocator)
                }
                self.speechEnergySeed = Double.random(in: 0...1)
                self.speechEnergy = 0.8
                self.onSpeechEnergyPulse?(self.speechEnergy, self.speechEnergySeed)

                let generated = await Self.generateChunk(
                    tts: engineRef,
                    text: chunk,
                    sid: sid,
                    speed: speed
                )
                guard !Task.isCancelled else { break }
                guard !generated.samples.isEmpty else { continue }

                await self.enqueueAndWait(samples: generated.samples)
            }

            await self?.finishNaturally()
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
        playerNode.play()
        status = .playing
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
    }

    private static func generateChunk(
        tts: SherpaOnnxOfflineTtsWrapper,
        text: String,
        sid: Int,
        speed: Float
    ) async -> GeneratedChunk {
        await withCheckedContinuation { continuation in
            synthesisQueue.async {
                let audio = tts.generate(text: text, sid: sid, speed: speed)
                continuation.resume(returning: GeneratedChunk(samples: audio.samples))
            }
        }
    }

    private func enqueueAndWait(samples: [Float]) async {
        await waitWhilePaused()
        guard status == .playing, !Task.isCancelled else { return }
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

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            playerNode.scheduleBuffer(buffer) {
                continuation.resume()
            }
            if !playerNode.isPlaying, status == .playing {
                playerNode.play()
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
        playerNode.stop()
        if engine.isRunning {
            engine.stop()
        }
        resumePauseWaiters()
        spokenText = ""
        speechEnergy = 0
        if notifyStopped, status != .unavailable {
            status = .stopped
        }
    }

    private func finishNaturally() {
        guard !Task.isCancelled else { return }
        activeTask = nil
        playerNode.stop()
        if engine.isRunning {
            engine.stop()
        }
        spokenText = ""
        speechEnergy = 0
        if status == .playing {
            status = .stopped
        }
    }
}
