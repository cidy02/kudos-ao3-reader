import Foundation

#if canImport(FluidAudio)
import FluidAudio
#endif

/// Where Kokoro runs, per OS line.
///
/// **iOS 26.x — Sherpa/ONNX.** Core ML Kokoro faults with a `SIGSEGV` inside
/// `libBNNS` (`BNNSGraphContextExecute_v2`); it is time/environment-gated
/// rather than input-gated, `cpuOnly` does not avoid it because `cpuOnly`
/// *is* BNNS, and a `SIGSEGV` cannot be caught in-process — so there is no
/// runtime recovery to build. Upstream scopes it to the 26.x line
/// (FluidAudio #817 / #844). Kudos does not gamble a hard app kill on it and
/// uses the Sherpa/ONNX engine there instead.
///
/// **iOS 27+ — Core ML on the Neural Engine.** The BNNS bug is gone on this
/// line, so Kokoro runs as staged Core ML graphs with each stage on whichever
/// unit measures fastest.
nonisolated enum KokoroAnePlayback: Sendable {
    /// The OS lines where the Core ML engine is used at all.
    static func supportsCoreML(
        for version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> Bool {
        version.majorVersion >= 27
    }

    #if canImport(FluidAudio)
    /// `KokoroAneComputeUnits.default` is itself OS-aware and already places
    /// every stage on the unit upstream measured fastest for it: the Albert /
    /// PostAlbert / alignment / prosody / vocoder stages on
    /// `cpuAndNeuralEngine`, and the noise + tail iSTFT graphs — which are
    /// fp32-only, so the fp16 ANE can take *none* of them — on `cpuOnly` for
    /// OS 27+, where Metal aborts intermittently inside MPSGraph under Core ML
    /// (#843, FB24243070). So this is already "the ANE for every workload the
    /// ANE is better at", and second-guessing it per stage would only be
    /// worse.
    ///
    /// The demotion after a recorded crash is `cpuOnly`, **not** `cpuAndGpu`:
    /// on the 27 line the GPU is the other known-bad path.
    static var computeUnits: KokoroAneComputeUnits {
        KokoroAneHealth.currentTier == .neuralEngine ? .default : .cpuOnly
    }
    #endif
}
