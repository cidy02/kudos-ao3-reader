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

    /// Where a complete sentence may be split. Deliberately **below**
    /// `modelLimit`: Kokoro rushes past roughly 400 phonemes, and
    /// Kokoro-FastAPI likewise stops at 450 against the same 510 cap. Using
    /// the hard cap as the split trigger meant a long sentence could
    /// legitimately synthesize at ~500 and be delivered rushed.
    ///
    /// Corpus run 3 measured **558 utterances above 400** across 12
    /// formatting-diverse works, with four of them touching exactly 510.
    static let splitThreshold = 400

    /// Hard model cap from `KokoroAneConstants.maxPhonemeLength`. Above this
    /// `KokoroAneVocab.encode` *throws*, which would end Read Aloud for the
    /// whole chapter — so this is a correctness boundary, not a quality one.
    /// Split at `splitThreshold` instead.
    static let modelLimit = 510

    /// Merge fragments shorter than this into a neighbor in the same block.
    static let shortFragment = 40
}

/// Over-estimates IPA length so packing stays under the emergency cap without
/// running Misaki. Runtime synthesis still measures the real G2P string.
///
/// **Measured bias.** Against real Misaki output (espeak fallback for OOV
/// names) over 7,000 grouped utterances from the 20-work corpus, the real
/// phoneme-string length is **0.866x this estimate** (p5 0.79, p95 0.94), and
/// the ratio is stable across every work sampled (0.850-0.891). So the
/// constants above describe estimate-space, and their real-phoneme meanings
/// are roughly:
///
///     preferredTarget 175 -> ~152    preferredMin 110 -> ~95
///     preferredMax    220 -> ~190    splitThreshold 400 -> ~346
///
/// That is *deliberately left alone*: upstream `VOICES.md` puts the quality
/// sweet spot at 100-200 phonemes, whose midpoint is 150, and the real centre
/// of ~152 sits on it. Removing the bias would move the real centre to 175 and
/// off that midpoint, which is a change only listening can justify.
///
/// English IPA is *shorter* than English spelling (`through` is seven letters
/// and three phonemes), which is why a 1.15x grapheme factor over-shoots even
/// though stress marks — 12.8% of a real phoneme string — are not modelled.
nonisolated struct KokoroPhonemeEstimator: Sendable {
    /// Extra phoneme characters charged per digit, on top of the grapheme
    /// factor every character already gets.
    ///
    /// Digits are the one place orthography lies badly about length: `1985` is
    /// four characters and around twenty phoneme characters once spoken as a
    /// year. Least squares over the same corpus puts a digit at ~10.3 phoneme
    /// characters against ~0.92 for a letter, and digit-bearing text was by far
    /// the strongest predictor of an under-estimate — the worst-undercounting
    /// groups carried ~500x the digit density of median text.
    ///
    /// This is a *tail* fix, not a bias fix: most prose holds no digits at all,
    /// so the median ratio is untouched (0.866 -> 0.865) while p99 drops from
    /// 1.04 to 1.00. Utterances that under-estimate are re-split at synthesis
    /// by phoneme count, and that split cuts blindly at the midpoint rather
    /// than on prosody, so keeping them out of it is worth one term.
    static let digitPhonemeBonus = 9

    func estimatePhonemeLength(_ text: String) -> Int {
        let prepared = KokoroSpeechNormalizer.normalize(text)
        guard !prepared.isEmpty else { return 0 }
        let words = KokoroSpeechNormalizer.words(in: prepared)
        let punctuation = prepared.filter { !$0.isLetter && !$0.isNumber && !$0.isWhitespace && $0 != "'" }.count
        // IPA is typically near grapheme length plus one space per word gap.
        let graphemes = prepared.filter { !$0.isWhitespace }.count
        let spaces = max(0, words.count - 1)
        let digits = prepared.filter(\.isNumber).count
        let estimate = Int((Double(graphemes) * 1.15).rounded()) + spaces + punctuation
            + Self.digitPhonemeBonus * digits
        return max(1, estimate)
    }
}
