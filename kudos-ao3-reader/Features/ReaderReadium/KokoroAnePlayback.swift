import Foundation

#if canImport(FluidAudio)
import FluidAudio
#endif

/// Compute-unit choice for Neural Engine Kokoro playback.
///
/// iOS 26.4–26.6 SIGSEGVs inside `libBNNS` (`BnnsCpuInferenceOperation` on
/// `com.apple.e5rt.concurrentExecutionQueue`). `cpuOnly` *is* BNNS. Seven-stage
/// CPU+GPU is not enough: FluidAudio G2P BART still loaded `.cpuOnly`.
/// Staging uses Metal for both G2P and the seven stages (see
/// `Packages/FluidAudio/KUDOS_PATCHES.md`). Not a feature gate.
nonisolated enum KokoroAnePlayback: Sendable {
    /// True on the iOS 26.4+ line where ANE/BNNS Kokoro is known to fault.
    static func prefersGpuOverBnns(
        for version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> Bool {
        version.majorVersion == 26 && version.minorVersion >= 4
    }

    /// The ANE is the point of this engine, so it is tried first even on the
    /// affected OS line, and `KokoroAneHealth` demotes the device permanently
    /// the first time synthesis actually dies. Flip this to
    /// `prefersGpuOverBnns()` to be conservative instead and never attempt the
    /// ANE on iOS 26.4–26.6.
    static func avoidsBnns(
        for version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> Bool {
        _ = version
        return KokoroAneHealth.currentTier != .neuralEngine
    }

    #if canImport(FluidAudio)
    static var computeUnits: KokoroAneComputeUnits {
        avoidsBnns() ? .cpuAndGpu : .default
    }
    #endif
}
