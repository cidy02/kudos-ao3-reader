#if os(iOS)
import Foundation
import NaturalLanguage

/// The proper nouns a work will repeat, ranked so a short list is worth
/// showing.
///
/// Three sources that fail in different directions, which is the whole reason
/// to use all three:
///
/// | source | finds | misses |
/// |---|---|---|
/// | AO3 character tags | the canonical cast, free, before playback | OCs, minor names, every non-person noun |
/// | `NLTagger` over the text | untagged people, places, organisations | invented words it has no prior for |
/// | the guessed-word log | *exactly* what actually missed every tier | only after it has been spoken once |
///
/// **The guessed log is the only evidence; the other two are priors.** A word
/// the lexicon already knows needs no correction however prominent it is, so
/// a tag or an NER hit alone never earns a place — it only moves something the
/// engine actually guessed at further up the list.
///
/// Measured over a 20-work corpus: ~1,700 distinct fallbacks per work, of
/// which the top ten cover a median 46% of occurrences. Ranking is what makes
/// that tractable.
nonisolated enum KokoroCastDiscovery {
    struct Candidate: Equatable, Sendable {
        let word: String
        /// Times the engine had to guess at it.
        let guessCount: Int
        /// Named in the work's AO3 character tags.
        let isTaggedCharacter: Bool
        /// Recognised as a name by on-device NER.
        let isRecognisedName: Bool

        /// Guess count is the base, because it is the only measured signal.
        /// The two priors are multipliers, not additions: they say "this is
        /// more likely to matter", which is a statement about the same
        /// evidence rather than extra evidence of its own.
        var score: Double {
            var score = Double(guessCount)
            if isTaggedCharacter { score *= 2.0 }
            if isRecognisedName { score *= 1.5 }
            return score
        }
    }

    /// Bare names from AO3 character tags.
    ///
    /// Tags carry disambiguators — `Hermione Granger (Harry Potter)` — which
    /// are cataloguing, not part of the name, so the parenthetical goes. Both
    /// the full tag and its individual words are kept: a reader hears "Granger"
    /// on its own far more often than the full form.
    static func namesFromCharacterTags(_ tags: [String]) -> Set<String> {
        var names: Set<String> = []
        for tag in tags {
            let bare = tag
                .replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bare.isEmpty else { continue }
            names.insert(bare)
            for part in bare.split(whereSeparator: { $0.isWhitespace }) {
                let word = part.trimmingCharacters(in: CharacterSet.letters.inverted)
                if word.count > 2 { names.insert(word) }
            }
        }
        return names
    }

    /// Personal, place and organisation names in `text`, via on-device NER.
    ///
    /// Capped because this runs over a whole chapter and the result is only a
    /// prior — exhaustiveness buys nothing once the ranking is dominated by
    /// guess counts.
    static func recognisedNames(in text: String, limit: Int = 400) -> Set<String> {
        var names: Set<String> = []
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let wanted: Set<NLTag> = [.personalName, .placeName, .organizationName]
        tagger.enumerateTags(
            in: text.startIndex ..< text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitPunctuation, .omitWhitespace, .joinNames]
        ) { tag, range in
            if let tag, wanted.contains(tag) {
                let name = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if name.count > 2 { names.insert(name) }
            }
            return names.count < limit
        }
        return names
    }

    /// The keys a name can match under: the whole name, plus each word.
    ///
    /// `recognisedNames` uses `.joinNames`, so NER returns "Severus Snape" as
    /// one span — but the guessed log stores single words, so a joined span
    /// alone would never match. Tags are split for the same reason a reader
    /// hears "Granger" far more often than the full form.
    private static func lookupKeys(_ name: String) -> [String] {
        var keys = [normalizedKey(name)]
        for part in name.split(whereSeparator: { $0.isWhitespace }) {
            let key = normalizedKey(String(part))
            if key.count > 2 { keys.append(key) }
        }
        return keys.filter { !$0.isEmpty }
    }

    /// Mirrors FluidAudio's `KokoroAneEnglishPhonemizer.normalizeKey`
    /// (lowercase, keep only letters/digits/apostrophe). That one is internal
    /// to the package and cannot be called, so it is reproduced — if upstream
    /// changes it, the priors go quietly dead again.
    static func normalizedKey(_ word: String) -> String {
        let allowed = CharacterSet.letters.union(.decimalDigits)
            .union(CharacterSet(charactersIn: "'"))
        return String(String.UnicodeScalarView(
            word.lowercased().unicodeScalars.filter { allowed.contains($0) }
        ))
    }

    /// Merge the three sources into one ranked list.
    ///
    /// - Parameter guessed: what the engine actually had to guess at.
    /// - Returns: candidates ordered by score, highest first, then
    ///   alphabetically so the order is stable between launches rather than
    ///   shuffling whenever two names tie.
    static func rank(
        guessed: [KokoroGuessedWordStore.Entry],
        characterTags: [String] = [],
        recognisedNames: Set<String> = []
    ) -> [Candidate] {
        // Both priors keep source capitalisation ("Severus"), but the guessed
        // log only ever holds the phonemiser's *normalised* key ("severus") —
        // the observer is handed `fallback(normalized)`, and the store only
        // trims whitespace. Comparing them raw made both priors dead for every
        // proper noun, which is the only kind of word this ranking is for, so
        // both sides are normalised here.
        let tagged = Set(namesFromCharacterTags(characterTags).flatMap(lookupKeys))
        let recognised = Set(recognisedNames.flatMap(lookupKeys))
        return guessed
            .map { entry in
                let key = normalizedKey(entry.word)
                return Candidate(
                    word: entry.word,
                    guessCount: entry.count,
                    isTaggedCharacter: tagged.contains(key),
                    isRecognisedName: recognised.contains(key)
                )
            }
            .sorted {
                $0.score == $1.score
                    ? $0.word.localizedStandardCompare($1.word) == .orderedAscending
                    : $0.score > $1.score
            }
    }
}
#endif
