import Foundation

/// Tracks whether Core ML Kokoro synthesis has ever died on *this* device.
///
/// Only consulted on the OS lines where Core ML runs at all — see
/// `KokoroAnePlayback.supportsCoreML(for:)`.
///
/// The libBNNS fault (FluidAudio #817) is a `SIGSEGV` in
/// `BNNSGraphContextExecute_v2` — there is no error to catch and no
/// `do/catch` that can recover it, so the engine cannot degrade itself at
/// runtime. Instead a marker file is written immediately before each
/// synthesis and removed immediately after. A marker still on disk at the
/// next launch means the process died mid-synthesis.
///
/// The marker is written through the kernel, so it survives process death
/// even though no `fsync` is issued.
///
/// Escalation, checked in `KokoroAnePlayback` and `ReaderSpeechController`:
///
/// | strikes | behaviour                                    |
/// |---------|----------------------------------------------|
/// | 0       | `KokoroAneComputeUnits.default` — ANE per stage |
/// | 1       | Core ML, every stage `cpuOnly`                  |
/// | 2+      | Core ML abandoned; Sherpa/ONNX takes over       |
nonisolated enum KokoroAneHealth: Sendable {
    enum Tier: Equatable, Sendable {
        /// `cpuAndNeuralEngine` — the reason this engine exists.
        case neuralEngine
        /// Core ML with every stage on `cpuOnly` — no ANE, and no GPU
        /// either, since Metal is the other known-bad path on iOS 27.
        case coreMLCpuOnly
        /// Core ML has died twice here; hand off to Sherpa/ONNX.
        case abandonCoreML
    }

    /// Strikes at or above this abandon Core ML entirely.
    static let abandonThreshold = 2

    /// The whole escalation rule, free of `UserDefaults` and the filesystem.
    static func tier(forStrikes strikes: Int) -> Tier {
        switch strikes {
        case ..<1: .neuralEngine
        case ..<abandonThreshold: .coreMLCpuOnly
        default: .abandonCoreML
        }
    }

    static var currentTier: Tier { tier(forStrikes: strikes) }

    private static let strikeKey = "kokoro.ane.crashStrikes"

    private static var markerURL: URL {
        KokoroAneAvailability.modelsDirectory
            .appendingPathComponent(".kudos-kokoro-synthesis-inflight")
    }

    /// Runs `auditPreviousLaunch()` exactly once per process, on first read.
    private static let audited: Bool = {
        guard FileManager.default.fileExists(atPath: markerURL.path) else { return true }
        try? FileManager.default.removeItem(at: markerURL)
        let recorded = UserDefaults.standard.integer(forKey: strikeKey) + 1
        UserDefaults.standard.set(recorded, forKey: strikeKey)
        return true
    }()

    /// Crashes observed on this device. Reading this performs the one-time
    /// audit of the previous launch.
    static var strikes: Int {
        _ = audited
        return UserDefaults.standard.integer(forKey: strikeKey)
    }

    static var hasAbandonedCoreML: Bool { currentTier == .abandonCoreML }

    static func beginSynthesis() {
        _ = audited
        try? FileManager.default.createDirectory(
            at: KokoroAneAvailability.modelsDirectory,
            withIntermediateDirectories: true
        )
        try? Data().write(to: markerURL, options: .atomic)
    }

    static func endSynthesis() {
        try? FileManager.default.removeItem(at: markerURL)
    }

    /// Clears the record so the ANE is retried — for a "try again" affordance
    /// or after installing a new pack.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: strikeKey)
        endSynthesis()
    }
}
