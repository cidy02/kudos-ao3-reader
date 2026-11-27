#if os(iOS)
import AVFoundation
import Foundation
import Speech
import UIKit

/// On-device dictation for the chapter editor (`Phone-Dictate.dc.html`).
///
/// Recognition uses `SFSpeechRecognizer` with `requiresOnDeviceRecognition`, so audio stays
/// on this device. On-device requests end on their own (e.g. the one-minute limit); while the
/// writer is still dictating a fresh request takes over. A phrase is inserted when the result
/// is final, after about a second of silence, or before audio stops so nothing spoken is lost.
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
    private(set) var levels: [CGFloat] = Array(repeating: 0.08, count: DictationController.meterBars)

    var isPresented: Bool { phase != .idle }

    var statusLine: String {
        let device = ThisDevice.name
        switch phase {
        case .idle:
            return ""
        case .requestingPermission:
            return "Asking to listen on this \(device)"
        case .listening:
            return "Listening · on this \(device), nothing leaves it"
        case .stopped:
            return "Stopped · on this \(device), nothing leaves it"
        case .denied:
            return "Dictation needs the microphone and speech recognition. "
                + "Both stay on this \(device). Allow them in Settings to dictate."
        case .unavailable:
            return "Dictation couldn't start. Speech stays on this \(device), and it isn't available right now."
        }
    }

    /// Settled phrases, in order. The screen inserts each one.
    @ObservationIgnored var onPhrase: (@MainActor (String) async -> Void)?

    // Injectable environment hooks with production defaults so state transitions can be tested without live audio.
    @ObservationIgnored var infoDictionaryProvider: () -> [String: Any]? = { Bundle.main.infoDictionary }
    @ObservationIgnored var isBackgrounded: () -> Bool = { UIApplication.shared.applicationState == .background }
    @ObservationIgnored var now: () -> Date = Date.init
    @ObservationIgnored var silenceDuration: Duration = .seconds(1)
    @ObservationIgnored var restartBackoff: Duration = .milliseconds(250)
    @ObservationIgnored var startRecognitionOverride: ((Int) -> Void)?

    @ObservationIgnored private var engine = AVAudioEngine()
    @ObservationIgnored private let requestBox = SpeechRequestBox()
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var silenceTask: Task<Void, Never>?
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    @ObservationIgnored private var phraseChain: Task<Void, Never>?
    @ObservationIgnored private var audioObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var lifecycleObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var presentToken = UUID()
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var audioGeneration = 0
    @ObservationIgnored private var wantsListening = false
    @ObservationIgnored private var committedThisRequest = false
    @ObservationIgnored private var hadSpeechInRequest = false
    @ObservationIgnored private var requestStartedAt: Date?
    @ObservationIgnored private var quickFailureCount = 0
    @ObservationIgnored private var tapInstalled = false
    @ObservationIgnored private var audioSessionActive = false
    @ObservationIgnored private var isConfiguringEngine = false

    private static let meterBars = 21
    private static let maxQuickFailures = 5
    private static let quickFailureWindowSeconds: TimeInterval = 5

    deinit {
        for observer in audioObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Shows the panel, asks the first time, and starts listening when both permissions are allowed.
    func present() {
        guard phase != .listening, phase != .requestingPermission else { return }
        let info = infoDictionaryProvider()
        guard DictationOffer.infoPlistAllowsDictation(info), !isBackgrounded() else { return }
        if startRecognitionOverride == nil {
            guard SFSpeechRecognizer()?.supportsOnDeviceRecognition == true else { return }
        }
        installLifecycleObserversIfNeeded()
        let token = UUID()
        presentToken = token
        phase = .requestingPermission
        pendingText = ""
        Task { @MainActor [weak self] in
            let allowed = await Self.authorize(infoDictionary: info)
            guard let self, self.presentToken == token, self.phase == .requestingPermission else { return }
            guard !self.isBackgrounded() else {
                self.phase = .stopped
                return
            }
            if allowed {
                self.beginListening()
            } else {
                self.phase = .denied
            }
        }
    }

    /// Stops the microphone but leaves the panel up so Undo and Keyboard are still there.
    func pause() {
        presentToken = UUID()
        guard phase == .listening || phase == .requestingPermission else { return }
        flushPendingPhrase()
        stopAudio()
        phase = .stopped
    }

    /// Leaves dictation and lets the keyboard return.
    func dismiss(commitPending: Bool = false) {
        presentToken = UUID()
        guard phase != .idle || audioSessionActive || !lifecycleObservers.isEmpty else { return }
        if commitPending {
            flushPendingPhrase()
        }
        stopAudio()
        removeObservers(&lifecycleObservers)
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

    func processRecognitionEvent(
        text: String?,
        isFinal: Bool,
        hasError: Bool,
        generation: Int
    ) {
        guard generation == self.generation, wantsListening else { return }
        if let text {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                hadSpeechInRequest = true
                quickFailureCount = 0
            }
            if isFinal {
                commit(text, generation: generation)
                return
            }
            // Ignore transient empty partial results so an error right after cannot wipe pending text.
            if !trimmed.isEmpty {
                pendingText = text
                armSilence(text, generation: generation)
            }
        }
        guard hasError else { return }
        guard generation == self.generation, !committedThisRequest else { return }
        if pendingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            noteRequestEnded()
        } else {
            commit(pendingText, generation: generation)
        }
    }

    func handleInterruption(typeRaw: UInt?) {
        guard let typeRaw, let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        if type == .began {
            pause()
        }
    }

    func handleMediaServicesReset() {
        if phase == .listening {
            flushPendingPhrase()
        }
        stopAudio()
        engine = AVAudioEngine()
        if phase == .listening || phase == .requestingPermission {
            phase = .stopped
        }
    }

    func beginSimulatedListeningForTesting() {
        wantsListening = true
        quickFailureCount = 0
        phase = .listening
        beginRequest()
    }

    func waitForPendingPhrasesForTesting() async {
        await phraseChain?.value
    }
}

// MARK: - Audio engine, recognition requests, observers & authorization

extension DictationController {
    private func beginListening() {
        guard !isBackgrounded() else {
            phase = .stopped
            return
        }
        guard let recognizer = SFSpeechRecognizer(),
              recognizer.supportsOnDeviceRecognition,
              recognizer.isAvailable else {
            phase = .unavailable
            return
        }
        self.recognizer = recognizer
        wantsListening = true
        quickFailureCount = 0
        do {
            try startEngine()
            installAudioObservers()
            phase = .listening
            beginRequest()
        } catch {
            stopAudio()
            phase = .unavailable
        }
    }

    private func startEngine() throws {
        isConfiguringEngine = true
        defer { isConfiguringEngine = false }
        audioGeneration += 1
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
        try session.setActive(true)
        audioSessionActive = true
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw DictationAudioError.noInput
        }
        if tapInstalled {
            input.removeTap(onBus: 0)
            tapInstalled = false
        }
        Self.installAudioTap(on: input, format: format, box: requestBox) { [weak self] level in
            Task { @MainActor [weak self] in
                self?.appendLevel(CGFloat(level))
            }
        }
        tapInstalled = true
        engine.prepare()
        try engine.start()
    }

    private func beginRequest() {
        guard wantsListening, !isBackgrounded() else {
            if phase == .listening { pause() }
            return
        }
        restartTask?.cancel()
        restartTask = nil
        cancelRecognitionTask()

        generation += 1
        let currentGeneration = generation
        committedThisRequest = false
        hadSpeechInRequest = false
        requestStartedAt = now()
        pendingText = ""
        silenceTask?.cancel()
        silenceTask = nil

        if let override = startRecognitionOverride {
            override(currentGeneration)
            return
        }

        guard let recognizer, recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else {
            stopAudio()
            phase = .unavailable
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.contextualStrings = DictationCommand.allCases.map(\.spoken)
        requestBox.set(request)

        task = Self.startRecognitionTask(recognizer: recognizer, request: request) {
            [weak self] text, isFinal, hasError in
            Task { @MainActor [weak self] in
                self?.processRecognitionEvent(
                    text: text,
                    isFinal: isFinal,
                    hasError: hasError,
                    generation: currentGeneration
                )
            }
        }
    }

    private func armSilence(_ text: String, generation: Int) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        silenceTask?.cancel()
        let delay = silenceDuration
        silenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            self.commit(text, generation: generation)
        }
    }

    private func commit(_ text: String, generation: Int) {
        guard generation == self.generation, !committedThisRequest else { return }
        committedThisRequest = true
        silenceTask?.cancel()
        silenceTask = nil
        let fallback = pendingText.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingText = ""
        cancelRecognitionTask()

        // On-device Speech occasionally delivers an empty `isFinal` when ending a request; keep `pendingText`.
        let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let settled = candidate.isEmpty ? fallback : candidate
        if !settled.isEmpty {
            enqueuePhrase(settled)
        }
        if wantsListening {
            beginRequest()
        }
    }

    private func flushPendingPhrase() {
        guard !committedThisRequest else { return }
        let trimmed = pendingText.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingText = ""
        guard !trimmed.isEmpty else { return }
        committedThisRequest = true
        enqueuePhrase(trimmed)
    }

    private func enqueuePhrase(_ text: String) {
        guard let handler = onPhrase else { return }
        let previous = phraseChain
        phraseChain = Task { @MainActor in
            await previous?.value
            await handler(text)
        }
    }

    private func noteRequestEnded() {
        cancelRecognitionTask()
        if startRecognitionOverride == nil {
            guard let recognizer, recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else {
                stopAudio()
                phase = .unavailable
                return
            }
        }
        let elapsed = requestStartedAt.map { now().timeIntervalSince($0) } ?? 0
        if !hadSpeechInRequest, elapsed < Self.quickFailureWindowSeconds {
            quickFailureCount += 1
            guard quickFailureCount < Self.maxQuickFailures else {
                stopAudio()
                phase = .unavailable
                return
            }
            let expectedGeneration = generation
            let backoff = restartBackoff
            restartTask?.cancel()
            restartTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: backoff)
                guard let self, !Task.isCancelled else { return }
                guard self.wantsListening, self.generation == expectedGeneration else { return }
                self.beginRequest()
            }
        } else {
            quickFailureCount = 0
            beginRequest()
        }
    }

    private func cancelRecognitionTask() {
        requestBox.end()
        task?.cancel()
        task = nil
    }

    private func stopAudio() {
        wantsListening = false
        generation += 1
        audioGeneration += 1
        removeObservers(&audioObservers)
        silenceTask?.cancel()
        silenceTask = nil
        restartTask?.cancel()
        restartTask = nil
        cancelRecognitionTask()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning {
            engine.stop()
        }
        if audioSessionActive {
            audioSessionActive = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        levels = Array(repeating: 0.08, count: Self.meterBars)
    }

    private func installLifecycleObserversIfNeeded() {
        guard lifecycleObservers.isEmpty else { return }
        let center = NotificationCenter.default
        let bg = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pause() }
        }
        let resign = center.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.phase == .listening else { return }
                self.pause()
            }
        }
        lifecycleObservers = [bg, resign]
    }

    private func installAudioObservers() {
        removeObservers(&audioObservers)
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        let expectedAudioGeneration = audioGeneration

        let interruption = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            let typeRaw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor [weak self] in
                guard let self, self.audioGeneration == expectedAudioGeneration else { return }
                self.handleInterruption(typeRaw: typeRaw)
            }
        }
        let routeChange = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            let reasonRaw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor [weak self] in
                guard let self, self.audioGeneration == expectedAudioGeneration else { return }
                self.handleRouteChange(reasonRaw: reasonRaw)
            }
        }
        let configChange = center.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.audioGeneration == expectedAudioGeneration else { return }
                self.reconfigureAudioAfterRouteChange()
            }
        }
        let mediaReset = center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleMediaServicesReset() }
        }
        audioObservers = [interruption, routeChange, configChange, mediaReset]
    }

    private func removeObservers(_ list: inout [NSObjectProtocol]) {
        for observer in list {
            NotificationCenter.default.removeObserver(observer)
        }
        list.removeAll()
    }

    private func handleRouteChange(reasonRaw: UInt?) {
        guard let reasonRaw, let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else { return }
        switch reason {
        case .noSuitableRouteForCategory:
            if phase == .listening { flushPendingPhrase() }
            stopAudio()
            phase = .unavailable
        case .oldDeviceUnavailable, .newDeviceAvailable, .override, .wakeFromSleep:
            reconfigureAudioAfterRouteChange()
        default:
            break
        }
    }

    private func reconfigureAudioAfterRouteChange() {
        guard phase == .listening, wantsListening, !isConfiguringEngine else { return }
        guard !isBackgrounded() else {
            pause()
            return
        }
        flushPendingPhrase()
        silenceTask?.cancel()
        silenceTask = nil
        restartTask?.cancel()
        restartTask = nil
        cancelRecognitionTask()
        removeObservers(&audioObservers)
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning {
            engine.stop()
        }
        engine.reset()
        quickFailureCount += 1
        guard quickFailureCount <= Self.maxQuickFailures else {
            stopAudio()
            phase = .unavailable
            return
        }
        do {
            try startEngine()
            installAudioObservers()
            beginRequest()
        } catch {
            stopAudio()
            phase = .unavailable
        }
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

    /// Installs the audio tap from a nonisolated context so the real-time CoreAudio callback never
    /// inherits `@MainActor` isolation under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
    private nonisolated static func installAudioTap(
        on input: AVAudioInputNode,
        format: AVAudioFormat,
        box: SpeechRequestBox,
        onLevel: @escaping @Sendable (Float) -> Void
    ) {
        let clock = LevelClock()
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            box.append(buffer)
            clock.buffers += 1
            guard clock.buffers.isMultiple(of: 3) else { return }
            onLevel(DictationController.meterLevel(buffer))
        }
    }

    /// Starts the recognition task from a nonisolated context and extracts Sendable values before
    /// hopping back to the main actor.
    private nonisolated static func startRecognitionTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onEvent: @escaping @Sendable (String?, Bool, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            onEvent(text, isFinal, error != nil)
        }
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

    private static func authorize(infoDictionary: [String: Any]?) async -> Bool {
        guard DictationOffer.infoPlistAllowsDictation(infoDictionary) else { return false }
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let micStatus = AVAudioApplication.shared.recordPermission
        if speechStatus == .denied || speechStatus == .restricted || micStatus == .denied {
            return false
        }
        let speech: Bool
        if speechStatus == .authorized {
            speech = true
        } else {
            speech = await requestSpeechAuthorization() == .authorized
        }
        guard speech else { return false }
        return await microphoneAllowed()
    }

    /// Nonisolated so Speech's background authorization callback never hits a main-actor assertion.
    private nonisolated static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private nonisolated static func microphoneAllowed() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await AVAudioApplication.requestRecordPermission()
        @unknown default:
            return false
        }
    }
}

private enum DictationAudioError: Error {
    case noInput
}

/// The recognition request the audio tap appends to. Explicitly nonisolated because the tap runs
/// on CoreAudio's real-time thread; locking across `append` and `endAudio` avoids racing teardown.
private nonisolated final class SpeechRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        defer { lock.unlock() }
        self.request = request
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        request?.append(buffer)
    }

    func end() {
        lock.lock()
        defer { lock.unlock() }
        let current = request
        request = nil
        current?.endAudio()
    }
}

/// Counts buffers on the audio thread so the meter doesn't republish every callback.
private nonisolated final class LevelClock: @unchecked Sendable {
    var buffers = 0
}
#endif
