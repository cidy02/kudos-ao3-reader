import Foundation

/// Strips Kokoro's incidental edge silence and inserts a pause chosen from
/// EPUB structure. Cuts land on a nearby zero crossing so concatenated
/// buffers do not click.
nonisolated enum KokoroPauseAssembler: Sendable {
    static let keepEdgeSeconds = 0.02
    static let rmsThreshold: Float = 0.006
    static let sampleRate = 24_000.0

    static func assemble(
        samples: [Float],
        sampleRate: Double,
        pauseAfter: KokoroBoundary
    ) -> [Float] {
        let trimmed = trimEdgeSilence(samples: samples, sampleRate: sampleRate)
        let speech = trimmed.isEmpty ? samples : trimmed
        let pauseCount = Int((pauseAfter.pauseSeconds * sampleRate).rounded())
        guard pauseCount > 0 else { return speech }
        var output = speech
        output.append(contentsOf: repeatElement(Float(0), count: pauseCount))
        return output
    }

    static func trimEdgeSilence(samples: [Float], sampleRate: Double) -> [Float] {
        guard samples.count > 16, sampleRate > 0 else { return samples }
        let keep = max(1, Int((keepEdgeSeconds * sampleRate).rounded()))
        let window = max(1, Int(sampleRate / 200)) // 5 ms RMS windows
        let start = firstVoiceIndex(samples: samples, window: window) ?? 0
        let end = lastVoiceIndex(samples: samples, window: window) ?? (samples.count - 1)
        let lo = max(0, start - keep)
        let hi = min(samples.count - 1, end + keep)
        guard lo < hi else { return samples }

        let cutStart = zeroCrossing(in: samples, around: lo, sampleRate: sampleRate)
        let cutEnd = zeroCrossing(in: samples, around: hi, sampleRate: sampleRate)
        guard cutStart < cutEnd else { return samples }
        return Array(samples[cutStart ... cutEnd])
    }

    private static func firstVoiceIndex(samples: [Float], window: Int) -> Int? {
        var index = 0
        while index < samples.count {
            let end = min(samples.count, index + window)
            if rms(samples[index ..< end]) >= rmsThreshold { return index }
            index = end
        }
        return nil
    }

    private static func lastVoiceIndex(samples: [Float], window: Int) -> Int? {
        var index = samples.count
        while index > 0 {
            let start = max(0, index - window)
            if rms(samples[start ..< index]) >= rmsThreshold { return index - 1 }
            index = start
        }
        return nil
    }

    private static func rms(_ slice: ArraySlice<Float>) -> Float {
        guard !slice.isEmpty else { return 0 }
        var sum: Float = 0
        var count = 0
        for sample in slice where sample.isFinite {
            sum += sample * sample
            count += 1
        }
        guard count > 0 else { return 0 }
        return sqrt(sum / Float(count))
    }

    private static func zeroCrossing(
        in samples: [Float],
        around index: Int,
        sampleRate: Double
    ) -> Int {
        let radius = max(1, Int(0.008 * sampleRate))
        let lo = max(1, index - radius)
        let hi = min(samples.count - 1, index + radius)
        var best = index
        var bestAbs = abs(samples[index])
        for i in lo ... hi {
            let crossed = samples[i - 1] == 0
                || samples[i] == 0
                || (samples[i - 1] < 0) != (samples[i] < 0)
            let magnitude = abs(samples[i])
            if crossed, magnitude <= bestAbs {
                best = i
                bestAbs = magnitude
            }
        }
        return best
    }
}
