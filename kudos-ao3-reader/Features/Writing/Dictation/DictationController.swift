#if os(iOS)
import AVFoundation
import Foundation
import Speech

/// On-device dictation for the chapter editor (`Phone-Dictate.dc.html`).
///
/// Recognition uses `SFSpeechRecognizer` with `requiresOnDeviceRecognition`, so audio stays
/// on this iPhone. On-device requests end on their own; while the writer is still dictating
/// a fresh request takes over. A phrase is inserted when the result is final or the hypothesis
/// has sat for about a second.
@MainActor
@Observable
final class DictationController {
    enum Phase: Equatable {
        case idle
        case requestingPermission
        case listening
        case stopped
        case denied
        case unavailable
    }

    private(set) var phase: Phase = .idle
    private(set) var pendingText = ""
    private(set) var levels: [CGFloat] = Array(repeating: 0.08, count: Self.meterBars)

    var isPresented: Bool { phase != .idle }

    var statusLine: String {
        switch phase {
        case .idle:
            ""
        case .requestingPermission:
            "Asking to listen on this iPhone"
        case .listening:
            "Listening · on this iPhone, nothing leaves it"
        case .stopped:
            "Stopped · on this iPhone, nothing leaves it"
        case .denied:
            "Dictation needs the microphone and speech recognition. "
                + "Both stay on this iPhone. Allow them in Settings to dictate."
        case .unavailable:
            "Dictation couldn't start. Speech stays on this iPhone, and it isn't available right now."
        }
    }

    /// Settled phrases, in order. The screen inserts each one.
    @ObservationIgnored var onPhrase: (@MainActor (String) async -> Void)?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let requestBox = SpeechRequestBox()
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var silenceTask: Task<Void, Never>?
    @ObservationIgnored private var presentToken = UUID()
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var wantsListening = false
    @ObservationIgnored private var committedThisRequest = false
    @ObservationIgnored private var restartCount = 0
    @ObservationIgnored private var tapInstalled = false

    private static let meterBars = 21
    private static let silence = Duration.seconds(1)

    /// Shows the panel, asks the first time, and starts listening when both permissions are allowed.
    func present() {
        guard DictationOffer.currentDeviceAllows else { return }
        let token = UUID()
        presentToken = token
        phase = .requestingPermission
        pendingText = ""
        Task { @MainActor in
            let allowed = await Self.authorize()
            guard presentToken == token, phase == .requestingPermission else { return }
            if allowed {
                beginListening()
            } else {
                phase = .denied
            }
        }
    }

    /// Stops the microphone but leaves the panel up so Undo and Keyboard are still there.
    func pause() {
        presentToken = UUID()
        stopAudio()
        guard phase == .listening || phase == .requestingPermission else { return }
        phase = .stopped
        pendingText = ""
    }

    /// Leaves dictation and lets the keyboard return.
    func dismiss() {
        presentToken = UUID()
        wantsListening = false
        stopAudio()
        pendingText = ""
        levels = Array(repeating: 0.08, count: Self.meterBars)
        phase = .idle
    }

    func toggleListening() {
        if phase == .listening {
            pause()
        } else {
            present()
        }
    }

    private func beginListening() {
        guard let recognizer = SFSpeechRecognizer(), recognizer.supportsOnDeviceRecognition else {
            phase = .unavailable
            return
        }
        self.recognizer = recognizer
        wantsListening = true
        restartCount = 0
        do {
            try startEngine()
            phase = .listening
            beginRequest()
        } catch {
            stopAudio()
            wantsListening = false
            phase = .unavailable
        }
    }

    private func startEngine() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw DictationAudioError.noInput
        }
        if tapInstalled {
            input.removeTap(onBus: 0)
            tapInstalled = false
        }
        let box = requestBox
        let clock = LevelClock()
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            box.append(buffer)
            clock.buffers += 1
            guard clock.buffers.isMultiple(of: 3) else { return }
            let level = DictationController.meterLevel(buffer)
            Task { @MainActor in
                self.appendLevel(CGFloat(level))
            }
        }
        tapInstalled = true
        engine.prepare()
        try engine.start()
    }

    private func beginRequest() {
        guard wantsListening, let recognizer else { return }
        generation += 1
        let generation = generation
        committedThisRequest = false
        pendingText = ""
        silenceTask?.cancel()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.contextualStrings = DictationCommand.all.map(\.spoken)
        requestBox.set(request)

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.handle(result: result, error: error, generation: generation)
            }
        }
    }

    private func handle(
        result: SFSpeechRecognitionResult?,
        error: (any Error)?,
        generation: Int
    ) {
        guard generation == self.generation, wantsListening else { return }
        if let result {
            restartCount = 0
            let text = result.bestTranscription.formattedString
            if result.isFinal {
                commit(text, generation: generation)
                return
            }
            pendingText = text
            armSilence(text, generation: generation)
        }
        guard error != nil else { return }
        guard generation == self.generation, !committedThisRequest else { return }
        if pendingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            noteRequestEnded()
        } else {
            commit(pendingText, generation: generation)
        }
    }

    private func armSilence(_ text: String, generation: Int) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        silenceTask?.cancel()
        silenceTask = Task { @MainActor in
            try? await Task.sleep(for: Self.silence)
            guard !Task.isCancelled else { return }
            self.commit(text, generation: generation)
        }
    }

    private func commit(_ text: String, generation: Int) {
        guard generation == self.generation, !committedThisRequest else { return }
        committedThisRequest = true
        silenceTask?.cancel()
        pendingText = ""
        requestBox.end()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let handler = onPhrase
        let committedGeneration = generation
        Task { @MainActor in
            if !trimmed.isEmpty, let handler {
                await handler(trimmed)
            }
            // A pause or a newer request bumps `generation`; don't start a second one over it.
            guard self.wantsListening, self.generation == committedGeneration else { return }
            self.beginRequest()
        }
    }

    private func noteRequestEnded() {
        restartCount += 1
        guard restartCount <= 8 else {
            wantsListening = false
            stopAudio()
            phase = .unavailable
            return
        }
        beginRequest()
    }

    private func stopAudio() {
        wantsListening = false
        generation += 1
        silenceTask?.cancel()
        silenceTask = nil
        task?.cancel()
        task = nil
        requestBox.end()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning {
            engine.stop()
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func appendLevel(_ level: CGFloat) {
        guard phase == .listening else { return }
        var next = levels
        next.append(min(1, max(0, level)))
        if next.count > Self.meterBars {
            next.removeFirst(next.count - Self.meterBars)
        }
        levels = next
    }

    nonisolated static func meterLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<count {
            let sample = samples[index]
            sum += sample * sample
        }
        return min(1, sqrt(sum / Float(count)) * 12)
    }

    private static func authorize() async -> Bool {
        guard DictationOffer.infoPlistAllowsDictation(Bundle.main.infoDictionary) else { return false }
        let speech = await speechAllowed()
        let microphone = await microphoneAllowed()
        return speech && microphone
    }

    private static func speechAllowed() async -> Bool {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current == .authorized { return true }
        guard current == .notDetermined else { return false }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private static func microphoneAllowed() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }
}

private enum DictationAudioError: Error {
    case noInput
}

/// The recognition request the audio tap appends to. The tap runs off the main actor.
private final class SpeechRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        self.request = request
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let request = request
        lock.unlock()
        request?.append(buffer)
    }

    func end() {
        lock.lock()
        let request = request
        self.request = nil
        lock.unlock()
        request?.endAudio()
    }
}

/// Counts buffers on the audio thread so the meter doesn't republish every callback.
private final class LevelClock: @unchecked Sendable {
    var buffers = 0
}
#endif
