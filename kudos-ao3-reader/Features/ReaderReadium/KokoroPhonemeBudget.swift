import Foundation

/// Kokoro ANE token budget. FluidAudio encodes IPA **characters** (plus BOS/EOS)
/// into a dynamic `[1, T_enc]` Albert input — there are no fixed 64/128/256
/// Core ML buckets. `maxPhonemeLength` is 510; filling it routinely hurts
/// prosody, so packing aims at the quality sweet spot instead.
nonisolated enum KokoroPhonemeBudget: Sendable {
    /// Soft grouping target when packing *whole sentences* together.
    /// Never a reason to cut a sentence in half.
    static let preferredTarget = 175
    static let preferredMin = 110
    static let preferredMax = 220
    static let softUpper = 250
    /// Hard model cap from `KokoroAneConstants.maxPhonemeLength`. This is the
    /// only size that may split a complete sentence.
    static let modelLimit = 510

    /// Merge fragments shorter than this into a neighbor in the same block.
    static let shortFragment = 40
}

/// Over-estimates IPA length so packing stays under the emergency cap without
/// running Misaki. Runtime synthesis still measures the real G2P string.
nonisolated struct KokoroPhonemeEstimator: Sendable {
    func estimatePhonemeLength(_ text: String) -> Int {
        let prepared = KokoroSpeechNormalizer.normalize(text)
        guard !prepared.isEmpty else { return 0 }
        let words = KokoroSpeechNormalizer.words(in: prepared)
        let punctuation = prepared.filter { !$0.isLetter && !$0.isNumber && !$0.isWhitespace && $0 != "'" }.count
        // IPA is typically near grapheme length plus one space per word gap.
        let graphemes = prepared.filter { !$0.isWhitespace }.count
        let spaces = max(0, words.count - 1)
        let estimate = Int((Double(graphemes) * 1.15).rounded()) + spaces + punctuation
        return max(1, estimate)
    }
}
