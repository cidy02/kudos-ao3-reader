import Foundation

/// Turns a plain-English respelling into the IPA the pronunciation store wants.
///
/// The store is tier 1 of the phonemizer and takes IPA, which nobody types.
/// `her-MY-oh-nee` is the notation dictionaries and fandom wikis already use,
/// so it is the one to accept.
///
/// **This invents no phoneme table.** Each syllable is sent through the same
/// G2P the reader itself uses, so `nee` is resolved by the machinery that
/// already knows how to resolve `nee`, and the result is by construction in
/// the model's own phoneme inventory. A hand-written spelling-to-IPA table
/// would be a second, worse copy of something we already ship.
nonisolated enum KokoroRespelling {
    /// Primary and secondary stress, per Misaki's inventory.
    static let primaryStress: Character = "\u{02C8}"
    static let secondaryStress: Character = "\u{02CC}"

    /// Whether `text` already looks like phonemes rather than a respelling.
    ///
    /// Someone pasting IPA they already have should not have it re-processed
    /// as if it were spelling. Stress marks and non-ASCII phoneme letters are
    /// the giveaway — a respelling is plain ASCII words and hyphens.
    static func looksLikeIPA(_ text: String) -> Bool {
        text.contains(primaryStress)
            || text.contains(secondaryStress)
            || text.unicodeScalars.contains { $0.value > 127 }
    }

    /// Split a respelling into its syllables, dropping empties so `her--MY`
    /// and a trailing hyphen behave.
    static func syllables(of respelling: String) -> [String] {
        respelling
            .split(whereSeparator: { $0 == "-" || $0 == "\u{2013}" || $0 == "\u{2014}" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Index of the syllable carrying primary stress.
    ///
    /// The convention is that the capitalised syllable is the stressed one
    /// (`her-MY-oh-nee`). It only reads as emphasis when something else is
    /// lower-case, so an all-capitals respelling means "no marked stress"
    /// rather than "every syllable stressed" — otherwise `ANNA` would come
    /// out with two primaries, which is not a thing.
    static func stressedIndex(in syllables: [String]) -> Int? {
        let capitalised = syllables.indices.filter { index in
            let syllable = syllables[index]
            let letters = syllable.filter(\.isLetter)
            return !letters.isEmpty && letters.allSatisfy(\.isUppercase)
        }
        guard !capitalised.isEmpty, capitalised.count < syllables.count else { return nil }
        return capitalised.first
    }

    /// Vowel characters, from Misaki's own set. Diphthong shorthands
    /// (`A I O Q W Y`) are first-class in this vocab and count as vowels.
    private static let vowels = Set<Character>("AIOQWYaiuæɑɒɔəɛɜɪʊʌᵻ")

    /// Mark primary stress *inside* a syllable, immediately before its first
    /// vowel — not at the syllable boundary.
    ///
    /// This is the convention the lexicon itself uses: `want` is `wˈɑnt`, not
    /// `ˈwɑnt`, and Misaki writes Hermione as `hɜɹmˈIəni`. Placing the mark at
    /// the boundary produces a string the model was never trained on, which is
    /// the sort of thing that sounds subtly wrong rather than obviously broken.
    ///
    /// A syllable with no vowel at all (a stray consonant cluster) is returned
    /// unmarked rather than gaining a stress mark with nothing to attach to.
    static func stressing(_ phonemes: String) -> String {
        guard let index = phonemes.firstIndex(where: { vowels.contains($0) }) else {
            return phonemes
        }
        return String(phonemes[..<index]) + String(primaryStress) + String(phonemes[index...])
    }

    /// Strip stress marks a syllable's own lookup contributed, so the only
    /// stress in the result is the one the respelling asked for.
    static func removingStress(_ phonemes: String) -> String {
        phonemes.filter { $0 != primaryStress && $0 != secondaryStress }
    }

    /// `her-MY-oh-nee` → `hɜɹmˈIoni`.
    ///
    /// - Parameter phonemize: resolves one syllable to phonemes. Injected so
    ///   this is testable without a downloaded model pack, and so the caller
    ///   decides whether that means the real G2P or a stand-in.
    /// - Returns: `nil` when nothing could be resolved, so the caller can say
    ///   so rather than saving an empty override.
    static func ipa(
        forRespelling respelling: String,
        phonemize: (String) async throws -> String?
    ) async rethrows -> String? {
        let parts = syllables(of: respelling)
        guard !parts.isEmpty else { return nil }
        let stressed = stressedIndex(in: parts)

        var out = ""
        for (index, syllable) in parts.enumerated() {
            // Lower-cased: the capitals are stress notation, not spelling, and
            // an all-caps token would otherwise be read as an initialism and
            // spelled out letter by letter.
            guard let resolved = try await phonemize(syllable.lowercased()),
                  !resolved.isEmpty
            else { continue }
            let bare = removingStress(resolved)
            guard !bare.isEmpty else { continue }
            out.append(index == stressed ? stressing(bare) : bare)
        }
        return out.isEmpty ? nil : out
    }
}
