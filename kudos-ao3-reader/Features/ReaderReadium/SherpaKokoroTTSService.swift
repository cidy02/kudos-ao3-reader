import AVFoundation
import Foundation
import ReadiumNavigator
import ReadiumShared

#if canImport(sherpa_onnx)
import sherpa_onnx
#endif

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

    public var availableVoices: [TTSVoice] = []

    public var onStatusChange: ((TTSServiceStatus) -> Void)?
    public var onSpokenTextChange: ((String) -> Void)?
    public var onSpeechEnergyPulse: ((Double, Double) -> Void)?
    public var onAdvance: ((Locator) -> Void)?

    private var activeTask: Task<Void, Never>?
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    #if canImport(sherpa_onnx)
    private var tts: SherpaOnnxOfflineTts?
    #endif

    private var currentSpeed: Float = 1.0
    private var currentVoiceId: Int32 = 0

    public init(modelDirectory: URL) {
        // Set up the audio engine
        engine.attach(playerNode)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false) else { return }
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        #if canImport(sherpa_onnx)
        // Verify files exist before loading
        let modelPath = modelDirectory.appendingPathComponent("model.int8.onnx").path
        let voicesPath = modelDirectory.appendingPathComponent("voices.bin").path
        let tokensPath = modelDirectory.appendingPathComponent("tokens.txt").path
        let dataDir = modelDirectory.appendingPathComponent("espeak-ng-data").path

        let fm = FileManager.default
        if fm.fileExists(atPath: modelPath), fm.fileExists(atPath: voicesPath), fm.fileExists(atPath: tokensPath) {
            let config = SherpaOnnxOfflineTtsConfig(
                model: SherpaOnnxOfflineTtsModelConfig(
                    kokoro: SherpaOnnxOfflineTtsKokoroModelConfig(
                        model: modelPath,
                        voices: voicesPath,
                        tokens: tokensPath,
                        dataDir: dataDir,
                        lengthScale: 1.0
                    ),
                    numThreads: 2,
                    debug: 0,
                    provider: "cpu"
                ),
                maxNumSentences: 1
            )

            // Initialize TTS. This will succeed if the models are valid.
            // If it fails, tts will be nil (or it might crash depending on C++ wrapper, but we assume safe init)
            tts = SherpaOnnxOfflineTts(config: config)

            // For Kokoro, voices are determined by ID. We can populate some common voices or read from config if sherpa exposes it.
            // (Assuming generic IDs for now)
            availableVoices = [
                TTSVoice(identifier: "0", language: Language(code: "en"), name: "Kokoro Default Voice", gender: .unspecified, quality: .higher)
            ]
        }
        #endif
    }

    public func speak(text: String, startLocator: Locator?) async throws {
        stop()

        let chunks = TextChunker.chunk(text: text)
        guard !chunks.isEmpty else { return }

        #if canImport(sherpa_onnx)
        guard let tts else {
            status = .unavailable
            return
        }
        #else
        status = .unavailable
        return
        #endif

        status = .playing

        do {
            try engine.start()
        } catch {
            status = .unavailable
            throw error
        }
        playerNode.play()

        activeTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            #if canImport(sherpa_onnx)
            guard let tts = await self.tts else { return }
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 24000,
                channels: 1,
                interleaved: false
            )!
            
            for chunk in chunks {
                if Task.isCancelled { break }
                
                await MainActor.run {
                    self.spokenText = chunk
                    if let startLocator = startLocator {
                        self.onAdvance?(startLocator)
                    }
                    self.speechEnergySeed = Double.random(in: 0...1)
                    self.speechEnergy = 0.8
                    self.onSpeechEnergyPulse?(self.speechEnergy, self.speechEnergySeed)
                }
                
                let speed = await self.currentSpeed
                let sid = await self.currentVoiceId
                
                // Generate audio (runs off main thread)
                let audio = tts.generate(text: chunk, sid: sid, speed: speed)
                
                // If chunk generation fails, skip to next chunk
                if audio.samples.isEmpty {
                    continue
                }
                
                if Task.isCancelled { break }
                
                // Convert samples to AVAudioPCMBuffer
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audio.samples.count)) else { continue }
                buffer.frameLength = buffer.frameCapacity
                
                let channels = Int(format.channelCount)
                for ch in 0..<channels {
                    let channelData = buffer.floatChannelData?[ch]
                    for i in 0..<audio.samples.count {
                        channelData?[i] = audio.samples[i]
                    }
                }
                
                // Wait for the player node to finish previous buffer if needed.
                // We await the completion handler so we don't queue infinitely ahead.
                await withCheckedContinuation { continuation in
                    self.playerNode.scheduleBuffer(buffer, completionHandler: {
                        continuation.resume()
                    })
                }
            }
            #endif

            await MainActor.run {
                self.stop()
            }
        }
    }

    public func pause() {
        guard status == .playing else { return }
        playerNode.pause()
        status = .paused
    }

    public func resume() {
        guard status == .paused else { return }
        playerNode.play()
        status = .playing
    }

    public func stop() {
        activeTask?.cancel()
        activeTask = nil
        playerNode.stop()
        engine.stop()
        if status != .unavailable {
            status = .stopped
        }
        spokenText = ""
        speechEnergy = 0
    }

    public func setVoice(id: String) {
        if let sid = Int32(id) {
            currentVoiceId = sid
        }
    }

    public func setRate(_ rate: Float) {
        // Clamp speed to sensible TTS values (0.5 to 2.0 typically)
        currentSpeed = max(0.5, min(2.0, rate))
    }

    public func setPitch(_: Float) {
        // Sherpa-onnx Kokoro doesn't currently support dynamic pitch modification, ignored.
    }
}
