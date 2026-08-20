import Foundation

/// Lets a queued synthesis block observe cancellation before entering sherpa-onnx.
/// The native batch inference call itself has no exposed cancellation API.
nonisolated final class KokoroSynthesisCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

/// Pure sample analysis used for Kokoro timing diagnostics and the reader waveform.
enum KokoroPlaybackAnalysis {

    /// Returns whether playback needs another generated PCM buffer before it
    /// waits for the current buffer to be consumed. The buffer after the one
    /// currently playing is what protects the next synthesis deadline.
    static func needsMoreQueuedAudio(
        queuedAudioSeconds: [Double],
        requiredFollowingAudioSeconds: Double = 1.5
    ) -> Bool {
        guard queuedAudioSeconds.count < 2 else {
            let followingAudioSeconds = queuedAudioSeconds.dropFirst().reduce(0, +)
            return followingAudioSeconds < requiredFollowingAudioSeconds
        }
        return true
    }

    struct SampleDiagnostics: Sendable {
        let minimum: Float
        let maximum: Float
        let peak: Float
        let leadingEdgeRMS: Double
        let trailingEdgeRMS: Double
        let outOfRange: Int
        let nonFinite: Int
    }

    static func waveformEnergy(samples: [Float]) -> Double {
        samples.withUnsafeBufferPointer { waveformEnergy(samples: $0) }
    }

    /// Splits the exact PCM sent to the player into a smooth 30 Hz envelope.
    static func waveformEnergyEnvelope(
        samples: [Float],
        sampleRate: Double,
        updatesPerSecond: Double = 30
    ) -> [Double] {
        guard !samples.isEmpty, sampleRate > 0, updatesPerSecond > 0 else { return [] }

        return samples.withUnsafeBufferPointer { samples in
            guard let baseAddress = samples.baseAddress else { return [] }

            let windowLength = max(1, Int((sampleRate / updatesPerSecond).rounded()))
            var envelope: [Double] = []
            envelope.reserveCapacity((samples.count + windowLength - 1) / windowLength)

            for offset in stride(from: 0, to: samples.count, by: windowLength) {
                let length = min(windowLength, samples.count - offset)
                let window = UnsafeBufferPointer(
                    start: baseAddress.advanced(by: offset),
                    count: length
                )
                envelope.append(waveformEnergy(samples: window))
            }
            return envelope
        }
    }

    static func sampleDiagnostics(samples: [Float]) -> SampleDiagnostics {
        var minimum: Float = 0
        var maximum: Float = 0
        var peak: Float = 0
        var outOfRange = 0
        var nonFinite = 0
        var hasFiniteSample = false

        for sample in samples {
            guard sample.isFinite else {
                nonFinite += 1
                continue
            }
            if !hasFiniteSample {
                minimum = sample
                maximum = sample
                hasFiniteSample = true
            } else {
                minimum = min(minimum, sample)
                maximum = max(maximum, sample)
            }
            peak = max(peak, abs(sample))
            if abs(sample) > 1 {
                outOfRange += 1
            }
        }

        let edgeSampleCount = min(120, samples.count)
        return SampleDiagnostics(
            minimum: minimum,
            maximum: maximum,
            peak: peak,
            leadingEdgeRMS: rms(samples: samples, range: 0..<edgeSampleCount),
            trailingEdgeRMS: rms(
                samples: samples,
                range: max(0, samples.count - edgeSampleCount)..<samples.count
            ),
            outOfRange: outOfRange,
            nonFinite: nonFinite
        )
    }

    private static func rms(samples: [Float], range: Range<Int>) -> Double {
        guard !range.isEmpty else { return 0 }

        var sumOfSquares = 0.0
        var sampleCount = 0
        for sample in samples[range] where sample.isFinite {
            let amplitude = Double(sample)
            sumOfSquares += amplitude * amplitude
            sampleCount += 1
        }
        guard sampleCount > 0 else { return 0 }
        return sqrt(sumOfSquares / Double(sampleCount))
    }

    private static func waveformEnergy(samples: UnsafeBufferPointer<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }

        var sumOfSquares = 0.0
        var sampleCount = 0
        for sample in samples where sample.isFinite {
            let amplitude = Double(sample)
            sumOfSquares += amplitude * amplitude
            sampleCount += 1
        }
        guard sampleCount > 0 else { return 0 }

        let rms = sqrt(sumOfSquares / Double(sampleCount))
        guard rms > 0.000_01 else { return 0 }

        // Normalize a useful -60 dB...0 dB speech range for the waveform.
        let decibels = 20 * log10(rms)
        return min(1, max(0, (decibels + 60) / 60))
    }
}
