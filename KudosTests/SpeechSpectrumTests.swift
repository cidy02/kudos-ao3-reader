#if os(iOS)
import Foundation
import Testing
@testable import Kudos

@Suite("Speech spectrum")
struct SpeechSpectrumTests {
    private static let sampleRate = 24_000.0

    /// A pure tone at `hz`, long enough for several analysis frames.
    private func tone(hz: Double, seconds: Double = 0.5) -> [Float] {
        let count = Int(Self.sampleRate * seconds)
        return (0 ..< count).map {
            Float(0.5 * sin(2 * Double.pi * hz * Double($0) / Self.sampleRate))
        }
    }

    private func loudestBand(_ frames: [SpeechSpectrum]) -> Int? {
        guard !frames.isEmpty else { return nil }
        var totals = [Double](repeating: 0, count: SpeechSpectrum.bandCount)
        for frame in frames {
            for (index, value) in frame.bands.enumerated() { totals[index] += value }
        }
        return totals.firstIndex(of: totals.max() ?? 0)
    }

    /// The whole point of the change: a tone must light *its own* band. If the
    /// bars shared one scalar again this would fail for every frequency.
    @Test func eachBandRespondsToItsOwnFrequency() {
        let cases: [(hz: Double, band: Int, label: String)] = [
            (150, 0, "fundamental"),
            (500, 1, "F1"),
            (1_400, 2, "F2"),
            (3_000, 3, "consonant burst"),
            (6_000, 4, "sibilance"),
        ]
        for probe in cases {
            let frames = SpeechSpectrum.analyze(
                samples: tone(hz: probe.hz), sampleRate: Self.sampleRate
            )
            #expect(!frames.isEmpty, "\(probe.label): no frames")
            #expect(
                loudestBand(frames) == probe.band,
                "\(probe.hz) Hz should dominate band \(probe.band) (\(probe.label))"
            )
        }
    }

    /// Bands must be genuinely independent, not one level with fixed gains.
    @Test func aToneLeavesOtherBandsQuiet() {
        let frames = SpeechSpectrum.analyze(samples: tone(hz: 6_000), sampleRate: Self.sampleRate)
        let mid = frames.map { $0.bands[2] }.max() ?? 0
        let high = frames.map { $0.bands[4] }.max() ?? 0
        #expect(high > 0.5, "sibilance band should be loud, was \(high)")
        #expect(mid < high / 2, "formant band should stay quiet, was \(mid)")
    }

    /// Regression for "the waveform peaks too often — it's basically a
    /// rectangle". Linear magnitude put nearly every speech frame in a narrow
    /// band near the top; on a dB scale the same audio has to use its range.
    @Test func loudAndQuietPassagesLookDifferent() {
        // A tone that swells and fades, like speech between pauses.
        let count = Int(Self.sampleRate * 1.0)
        let samples: [Float] = (0 ..< count).map { index in
            let t = Double(index) / Self.sampleRate
            let envelope = pow(abs(sin(2 * Double.pi * 1.5 * t)), 3)
            return Float(envelope * 0.6 * sin(2 * Double.pi * 900 * t))
        }
        let frames = SpeechSpectrum.analyze(samples: samples, sampleRate: Self.sampleRate)
        #expect(!frames.isEmpty)

        let levels = frames.map(\.level).sorted()
        let low = levels[levels.count / 10]
        let high = levels[levels.count * 9 / 10]

        // Loud moments near the top, quiet ones genuinely low — not a block.
        #expect(high > 0.75, "peaks should reach the top, was \(high)")
        #expect(low < 0.45, "quiet passages should drop, was \(low)")
        #expect(high - low > 0.35, "range collapsed to \(high - low)")
    }

    /// Speech tilts: the fundamental carries far more energy than sibilance.
    /// Bands are deliberately not normalised individually, so that tilt has to
    /// survive — four equal bars would mean the shape was flattened away.
    @Test func spectralTiltIsPreserved() {
        let count = Int(Self.sampleRate * 0.4)
        let samples: [Float] = (0 ..< count).map { index in
            let t = Double(index) / Self.sampleRate
            return Float(0.5 * sin(2 * Double.pi * 150 * t)
                + 0.02 * sin(2 * Double.pi * 6_000 * t))
        }
        let frames = SpeechSpectrum.analyze(samples: samples, sampleRate: Self.sampleRate)
        let fundamental = frames.map { $0.bands[0] }.max() ?? 0
        let sibilance = frames.map { $0.bands[4] }.max() ?? 0
        #expect(fundamental > sibilance, "tilt lost: \(fundamental) vs \(sibilance)")
    }

    @Test func silenceProducesNoLevel() {
        let quiet = [Float](repeating: 0, count: 12_000)
        let frames = SpeechSpectrum.analyze(samples: quiet, sampleRate: Self.sampleRate)
        #expect(frames.allSatisfy { $0.bands.allSatisfy { $0 == 0 } })
    }

    /// A near-silent clip must not be normalised up into a full display.
    @Test func nearSilenceIsNotAmplified() {
        let faint = (0 ..< 12_000).map { _ in Float.random(in: -1e-6 ... 1e-6) }
        let frames = SpeechSpectrum.analyze(samples: faint, sampleRate: Self.sampleRate)
        #expect(frames.allSatisfy { $0.level < 0.01 })
    }

    @Test func shortOrInvalidInputIsHandled() {
        #expect(SpeechSpectrum.analyze(samples: [0.1, 0.2], sampleRate: Self.sampleRate).isEmpty)
        #expect(SpeechSpectrum.analyze(samples: tone(hz: 440), sampleRate: 0).isEmpty)
    }

    @Test func valuesAreClampedAndFinite() {
        let wild = SpeechSpectrum(bands: [-5, 2, .nan, .infinity])
        #expect(wild.bands.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 })
        #expect(SpeechSpectrum(bands: [0.5]).bands.count == SpeechSpectrum.bandCount)
    }

    @Test func playheadLookupStaysInBounds() {
        let frames = SpeechSpectrum.analyze(samples: tone(hz: 1_000), sampleRate: Self.sampleRate)
        #expect(SpeechSpectrum.frame(in: frames, at: -1, sampleRate: Self.sampleRate) == .silent)
        #expect(SpeechSpectrum.frame(in: frames, at: 999, sampleRate: Self.sampleRate) == .silent)
        #expect(SpeechSpectrum.frame(in: [], at: 0, sampleRate: Self.sampleRate) == .silent)
        #expect(SpeechSpectrum.frame(in: frames, at: 0.1, sampleRate: Self.sampleRate).level > 0)
    }

    // MARK: - Apple's inferred spectrum

    /// Not measurement — but it has to track the text, which random never did.
    @Test func sibilantWordsFavourTheHighBand() {
        let hissing = SpeechSpectrum.forSpoken(word: "sisters")
        let humming = SpeechSpectrum.forSpoken(word: "morning")
        #expect(hissing.bands[4] > humming.bands[4])
        #expect(humming.bands[0] > hissing.bands[0])
    }

    /// Vowels live in the two formant bands; which of the pair leads depends on
    /// whether they are front or back, so assert the region rather than a bar.
    @Test func vowelWordsFavourTheFormantBands() {
        let vowelly = SpeechSpectrum.forSpoken(word: "aeiou")
        let formants = max(vowelly.bands[1], vowelly.bands[2])
        #expect(formants == vowelly.bands.max())
    }

    /// The fifth bar exists so different vowels stop looking identical: front
    /// vowels carry a higher F2 than back vowels.
    @Test func frontAndBackVowelsSeparate() {
        let front = SpeechSpectrum.forSpoken(word: "eee")
        let back = SpeechSpectrum.forSpoken(word: "ooo")
        #expect(front.bands[2] > back.bands[2])
        #expect(back.bands[1] > front.bands[1])
    }

    @Test func bandCountMatchesTheBarCount() {
        #expect(SpeechSpectrum.bandCount == 5)
        #expect(SpeechSpectrum.bandEdges.count == SpeechSpectrum.bandCount)
        #expect(SpeechSpectrum.spread(level: 0.5).bands.count == SpeechSpectrum.bandCount)
    }

    /// Every band keeps a floor, so a word never collapses to one lit bar.
    @Test func everyBandKeepsABody() {
        let extreme = SpeechSpectrum.forSpoken(word: "sss")
        #expect(extreme.bands.allSatisfy { $0 > 0.2 })
    }

    @Test func emptyAndNonLetterInputIsSilent() {
        #expect(SpeechSpectrum.forSpoken(word: "") == .silent)
        #expect(SpeechSpectrum.forSpoken(word: "—  ,") == .silent)
    }

    /// The same word must always look the same; the old path was random.
    @Test func inferredSpectrumIsDeterministic() {
        #expect(SpeechSpectrum.forSpoken(word: "Hermione")
            == SpeechSpectrum.forSpoken(word: "Hermione"))
    }
}
#endif
