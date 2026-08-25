import Foundation

/// Emphasis from EPUB markup (`<em>` / `<i>` / `<strong>` / `<b>`), expressed
/// the only way this model can hear it.
///
/// Kokoro ignores capitalisation and has no emphasis token — the vocab's
/// arrow glyphs turned out to be **Mandarin lexical tones**, not English
/// intonation, so the one lever left inside its own inventory is the stress
/// marks its lexicon already uses.
///
/// **The rule: an emphasised word must carry primary stress.** That is all.
/// It sounds thin, but measurement says it is exactly the right size.
///
/// Across 29 works, 38,149 emphasised spans (12.9% of paragraphs carry one),
/// 66% of them a single word. Of those single words:
///
/// | case | share | example |
/// |---|---|---|
/// | promote a lone secondary | 5.7% | `not` `nˌɑt` → `nˈɑt` |
/// | add stress to a weak form | 9.6% | `you` `ju` → `jˈu` |
/// | already primary — nothing to do | 68.1% | |
/// | not in the lexicon | 16.5% | |
///
/// So 15.4% change, and the ones that do are almost all **function words** —
/// which is what emphasis markup is used for in prose (*I did **not** say
/// that*). Content words already carry primary stress, and inventing a second
/// one would produce a string the model was never trained on. Doing nothing
/// for those is the correct behaviour, not a gap.
nonisolated enum KokoroEmphasis {
    static let primaryStress: Character = "\u{02C8}"
    static let secondaryStress: Character = "\u{02CC}"

    /// The emphasised reading of an already-resolved phoneme string.
    ///
    /// - Returns: `nil` when nothing should change, so a caller can keep the
    ///   original rather than rewriting it to an identical value.
    static func stressed(_ phonemes: String) -> String? {
        guard !phonemes.isEmpty else { return nil }

        // Already carries primary stress: there is no lever here. Adding a
        // second `ˈ` would be out of distribution — no lexicon entry has two.
        if phonemes.contains(primaryStress) { return nil }

        // A lone secondary is the weak reading of a word that has a strong
        // one — `not` is `nˌɑt` unemphasised and `nˈɑt` emphasised. Promote
        // the first, and only the first.
        if let index = phonemes.firstIndex(of: secondaryStress) {
            var promoted = phonemes
            promoted.replaceSubrange(index ... index, with: String(primaryStress))
            return promoted
        }

        // No stress at all is the signature of a function word's weak form
        // (`you` → `ju`, `are` → `ɑɹ`). Emphasis is precisely when English
        // uses the strong form instead, so give it one.
        //
        // Reuses the respelling converter's placement, which puts the mark
        // before the vowel rather than at the word boundary — `wˈɑnt`, never
        // `ˈwɑnt`. A syllable with no vowel comes back unchanged there, which
        // is also right here.
        let marked = KokoroRespelling.stressing(phonemes)
        return marked == phonemes ? nil : marked
    }

    /// Whether an emphasis span is worth acting on at all.
    ///
    /// Single words are 66% of spans and are what the rule is for. A long
    /// italic run — a letter, a dream sequence, a passage in another language
    /// — is 6% and is *typographic*, not emphatic: stressing every word in it
    /// would be worse than leaving it alone.
    static func isEmphasisWorthApplying(to text: String) -> Bool {
        let words = text.split(whereSeparator: { $0.isWhitespace })
        return (1 ... 3).contains(words.count)
    }
}
