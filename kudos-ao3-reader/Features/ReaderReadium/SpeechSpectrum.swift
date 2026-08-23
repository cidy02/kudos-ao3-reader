import Accelerate
import Foundation

/// Per-band speech energy driving the mini-player equalizer.
///
/// The bars used to share **one** scalar, separated only by fixed gains and a
/// sine phase offset — so they could never do anything but bounce in
/// lockstep-with-offset, however often they were fed. Real metering moves each
/// band independently, which is what makes bass, mids and sibilance visibly
/// separate.
///
/// Two engines, two sources, because only one of them lets us hear the audio:
///
/// - **Kokoro** owns its PCM (`AVAudioPlayerNode` in-process), so
///   ``analyze(samples:sampleRate:)`` runs a real FFT and returns a true
///   spectrogram. Computed once at synthesis, then replayed against the
///   playhead — we hold the whole clip before a sample plays, so there is no
///   reason to pay for a realtime tap, hop off the audio thread, or tolerate
///   its jitter.
/// - **Apple** renders inside `AVSpeechSynthesizer`; the samples are never
///   ours. ``forSpoken(word:)`` derives a *plausible* spectrum from the
///   spelling instead. Not measurement, and it does not pretend to be — but it
///   correlates with what is actually being said, which is the difference
///   between "alive" and the previous `Double.random(in: 0.88 ... 1.0)`.
public nonisolated struct SpeechSpectrum: Equatable, Sendable {
    /// One value per bar, 0…1.
    public static let bandCount = 5

    /// Band edges in Hz, chosen for *speech* rather than music. Sibilance
    /// getting its own band is what makes the result read as talking: `s` and
    /// `sh` spike the top while vowels hold the middle.
    ///
    /// The formant region is split into two rather than left as one wide band,
    /// which is what the fifth bar buys. F1 and F2 are the pair that actually
    /// distinguishes one vowel from another, so separating them means "ah" and
    /// "ee" no longer look identical — most of speech's visible motion lives
    /// here, and one band was averaging it away.
    ///
    /// 0: fundamental / pitch · 1: F1, vowel openness ·
    /// 2: F2, vowel frontness · 3: consonant bursts · 4: sibilance
    public static let bandEdges: [(low: Double, high: Double)] = [
        (85, 255), (255, 800), (800, 2000), (2000, 4000), (4000, 8000),
    ]

    public var bands: [Double]

    public static let silent = SpeechSpectrum(bands: Array(repeating: 0, count: bandCount))

    public init(bands: [Double]) {
        var padded = bands.prefix(Self.bandCount).map { $0.isFinite ? min(1, max(0, $0)) : 0 }
        while padded.count < Self.bandCount { padded.append(0) }
        self.bands = padded
    }

    /// Loudest band — what a single-value consumer should see.
    public var level: Double { bands.max() ?? 0 }

    // MARK: - Kokoro: measured

    /// Window size. At 24 kHz this is ~43 ms, and hopping by half gives ~47
    /// frames a second — comfortably above the 30 fps the bars redraw at, so
    /// the envelope is never the limiting factor.
    public static let frameSize = 1024
    public static let hopSize = 512

    /// FFT the clip into a per-frame spectrogram.
    ///
    /// Normalised against the clip's own peak rather than an absolute
    /// reference: Kokoro's output level varies per voice and per utterance, and
    /// a fixed reference would leave quiet voices permanently flat. `floor`
    /// stops a near-silent clip from being amplified into a full-scale display.
    public static func analyze(samples: [Float], sampleRate: Double) -> [SpeechSpectrum] {
        guard samples.count >= frameSize, sampleRate > 0 else { return [] }
        let log2n = vDSP_Length(round(log2(Double(frameSize))))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }

        // Hann, or spectral leakage smears a vowel across every band and the
        // separation we are doing this for disappears.
        var window = [Float](repeating: 0, count: frameSize)
        vDSP_hann_window(&window, vDSP_Length(frameSize), Int32(vDSP_HANN_DENORM))

        let binWidth = sampleRate / Double(frameSize)
        let ranges = bandEdges.map { edge in
            let lo = max(1, Int(edge.low / binWidth))
            let hi = min(frameSize / 2 - 1, Int(edge.high / binWidth))
            return lo ... max(lo, hi)
        }

        // Raw magnitudes, deliberately *not* `SpeechSpectrum` yet: its
        // initialiser clamps to 0…1, and FFT magnitudes routinely exceed 1, so
        // building frames here would flatten every loud one onto the ceiling
        // before `normalized` ever saw them — which is exactly what made the
        // display a rectangle.
        var frames: [[Double]] = []
        var real = [Float](repeating: 0, count: frameSize / 2)
        var imaginary = [Float](repeating: 0, count: frameSize / 2)
        var magnitudes = [Float](repeating: 0, count: frameSize / 2)

        var start = 0
        while start + frameSize <= samples.count {
            var windowed = [Float](repeating: 0, count: frameSize)
            vDSP_vmul(Array(samples[start ..< start + frameSize]), 1, window, 1,
                      &windowed, 1, vDSP_Length(frameSize))

            real.withUnsafeMutableBufferPointer { realPtr in
                imaginary.withUnsafeMutableBufferPointer { imagPtr in
                    var split = DSPSplitComplex(realp: realPtr.baseAddress!,
                                                imagp: imagPtr.baseAddress!)
                    windowed.withUnsafeBufferPointer { src in
                        src.baseAddress!.withMemoryRebound(
                            to: DSPComplex.self, capacity: frameSize / 2
                        ) { typed in
                            vDSP_ctoz(typed, 2, &split, 1, vDSP_Length(frameSize / 2))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(frameSize / 2))
                }
            }

            let bands = ranges.map { range -> Double in
                let slice = magnitudes[range]
                guard !slice.isEmpty else { return 0 }
                // Mean, not sum: wider bands hold more bins and would otherwise
                // dominate purely by width.
                return Double(slice.reduce(0, +)) / Double(slice.count)
            }
            frames.append(bands)
            start += hopSize
        }

        return normalized(frames)
    }

    /// Dynamic range shown, in dB below the clip's loudest moment.
    ///
    /// 40, not the 60 a lab meter would use. A 60 dB window still renders a
    /// passage ten times quieter at 0.67 and a hundred times quieter at 0.33,
    /// so on four bars nearly everything piles into the top third and the
    /// display reads as a solid block. Roughly 40 dB is the span between a
    /// vowel and a quiet consonant, which is exactly the contrast the bars
    /// should be spending their travel on.
    public static let dynamicRangeDb = 40.0

    /// Map a spectrogram onto a **decibel** scale relative to the clip's peak.
    ///
    /// Linear magnitude is why the bars read as a solid block: hearing is
    /// logarithmic, and in linear terms most speech frames sit within a narrow
    /// band near the top, so every bar pinned high and the display stopped
    /// carrying information. In dB the same audio spreads across the full
    /// range — a vowel and the silence after it are ~40 dB apart and now look
    /// it.
    ///
    /// The reference is the clip's own peak rather than an absolute level,
    /// because Kokoro's output level varies per voice and utterance. Cross-band
    /// truth is kept — bands are *not* individually normalised, so the natural
    /// spectral tilt of speech (sibilance sits well below the fundamental)
    /// stays visible instead of being flattened into four equal bars.
    public static func normalized(_ frames: [[Double]]) -> [SpeechSpectrum] {
        let peak = frames.flatMap { $0 }.max() ?? 0
        // Below this the clip is effectively silence; scaling it up would show
        // a full display for nothing.
        let floor = 1e-4
        guard peak > floor else {
            return frames.map { _ in .silent }
        }
        return frames.map { frame in
            SpeechSpectrum(bands: frame.map { magnitude in
                guard magnitude > 0 else { return 0 }
                let db = 20 * log10(magnitude / peak)          // <= 0
                return max(0, (db + dynamicRangeDb) / dynamicRangeDb)
            })
        }
    }

    /// The frame audible at `seconds` into a clip.
    public static func frame(
        in frames: [SpeechSpectrum],
        at seconds: Double,
        sampleRate: Double
    ) -> SpeechSpectrum {
        guard !frames.isEmpty, sampleRate > 0, seconds >= 0 else { return .silent }
        let index = Int(seconds * sampleRate / Double(hopSize))
        guard index >= 0, index < frames.count else { return .silent }
        return frames[index]
    }

    // MARK: - Apple: inferred from spelling

    /// A plausible spectrum for a word we can hear but not measure.
    ///
    /// Letters are grouped by how the sounds they usually spell distribute
    /// energy. English spelling is only loosely phonetic, so this is an
    /// approximation on purpose — the goal is motion that *tracks the text*,
    /// not a phonetic transcription. A word full of `s` lights the top band; a
    /// vowel-heavy word sits in the formant band.
    public static func forSpoken(word: String) -> SpeechSpectrum {
        let letters = word.lowercased().filter(\.isLetter)
        guard !letters.isEmpty else { return .silent }

        var counts = [Double](repeating: 0, count: bandCount)
        for character in letters {
            switch character {
            case "s", "z", "f", "x", "c", "h":
                counts[4] += 1          // sibilant / fricative
            case "p", "t", "k", "b", "d", "g", "j", "q":
                counts[3] += 1          // plosive burst
            case "e", "i", "y":
                counts[2] += 1          // front vowel — higher F2
            case "a", "o", "u":
                counts[1] += 1          // back / open vowel — lower F2
            case "m", "n", "l", "r", "w", "v":
                counts[0] += 1          // nasal / approximant, low energy
            default:
                counts[1] += 0.5        // unclassified: treat as mild voicing
            }
        }

        let total = counts.reduce(0, +)
        guard total > 0 else { return .silent }

        // Voiced speech always carries some fundamental, so give every band a
        // floor: a word of pure sibilants should still show a body, not a
        // single lit bar.
        let base = 0.35
        return SpeechSpectrum(bands: counts.map { base + (1 - base) * ($0 / total) })
    }

    /// Spread a single 0…1 level across the bands, for an engine that reports
    /// loudness but no spectrum. Keeps the previous look rather than inventing
    /// detail that was never measured.
    public static func spread(level: Double) -> SpeechSpectrum {
        let gains: [Double] = [0.72, 1.0, 0.9, 0.8, 0.85]
        return SpeechSpectrum(bands: gains.map { $0 * level })
    }
}
