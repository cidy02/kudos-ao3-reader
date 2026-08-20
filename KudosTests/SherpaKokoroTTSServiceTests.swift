#if os(iOS)
import Testing
@testable import Kudos

@Suite("Kokoro playback energy")
struct SherpaKokoroTTSServiceTests {
    @Test func silenceHasNoEnergy() {
        #expect(KokoroPlaybackAnalysis.waveformEnergy(samples: [0, 0, 0]) == 0)
    }

    @Test func louderSamplesProduceMoreEnergy() {
        let quiet = KokoroPlaybackAnalysis.waveformEnergy(samples: [0.01, -0.01])
        let loud = KokoroPlaybackAnalysis.waveformEnergy(samples: [0.5, -0.5])

        #expect(loud > quiet)
    }

    @Test func energyIsFiniteAndClamped() {
        let energy = KokoroPlaybackAnalysis.waveformEnergy(
            samples: [Float.nan, .infinity, -2, 2]
        )

        #expect(energy.isFinite)
        #expect((0...1).contains(energy))
    }

    @Test func diagnosticsReportRangeAndEdges() {
        let diagnostics = KokoroPlaybackAnalysis.sampleDiagnostics(
            samples: [-0.25, 0, 0.5]
        )

        #expect(diagnostics.minimum == -0.25)
        #expect(diagnostics.maximum == 0.5)
        #expect(diagnostics.peak == 0.5)
        #expect(diagnostics.leadingEdgeRMS > 0)
        #expect(diagnostics.trailingEdgeRMS > 0)
    }

    @Test func energyEnvelopeUsesFixedDurationWindows() {
        let envelope = KokoroPlaybackAnalysis.waveformEnergyEnvelope(
            samples: Array(repeating: 0.1, count: 10),
            sampleRate: 10,
            updatesPerSecond: 2
        )

        #expect(envelope.count == 2)
        #expect(envelope.allSatisfy { $0 > 0 })
    }
}
#endif
