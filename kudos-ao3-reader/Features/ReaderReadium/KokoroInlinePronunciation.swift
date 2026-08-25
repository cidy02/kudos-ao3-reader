import Foundation

/// The `[Worcester](/wˈʊstəɹ/)` notation, parsed into store entries.
///
/// Not invented here: Kokoro-FastAPI and MisakiSwift both use this shape, so
/// a reader who already keeps a list of corrections for another Kokoro
/// frontend can paste it in, and anything exported from here is meaningful
/// elsewhere. Reusing an existing convention beats a private one that only
/// this app understands.
///
/// Deliberately a *paste* format rather than something read out of work text.
/// AO3 authors do not write phoneme markup, and treating square brackets in
/// fiction as pronunciation directives would misread ordinary prose.
nonisolated enum KokoroInlinePronunciation {
    struct Entry: Equatable, Sendable {
        let word: String
        let phonemes: String
    }

    /// `[word](/phonemes/)`, allowing whitespace between the two halves.
    ///
    /// The word excludes brackets rather than being merely lazy. A lazy `.+?`
    /// still matches `[` and `]`, so `[a][b](/x/)` captured `a][b` — laziness
    /// only picks the shortest match that lets the *rest* succeed, and
    /// spanning the brackets did. Excluding them makes it impossible.
    ///
    /// The phoneme run excludes `/` for the same reason: it stops an
    /// unterminated entry consuming everything after it, so one typo costs one
    /// line of a pasted list instead of the whole list.
    private static let pattern = try? NSRegularExpression(
        pattern: #"\[\s*([^\[\]]+?)\s*\]\s*\(\s*/([^/]+)/\s*\)"#
    )

    /// Every entry in `text`, in the order written.
    ///
    /// Text between entries is ignored, so a pasted note or a list with
    /// commentary around it still parses. Duplicates are preserved here and
    /// resolved by the caller — last-wins is the caller's policy, not this
    /// parser's business.
    static func entries(in text: String) -> [Entry] {
        guard let pattern else { return [] }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return pattern.matches(in: text, range: range).compactMap { match in
            guard let wordRange = Range(match.range(at: 1), in: text),
                  let phonemeRange = Range(match.range(at: 2), in: text)
            else { return nil }
            let word = String(text[wordRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let phonemes = String(text[phonemeRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty, !phonemes.isEmpty else { return nil }
            return Entry(word: word, phonemes: phonemes)
        }
    }

    /// Render entries back out, so a reader can copy their corrections
    /// somewhere else or hand them to someone in the same fandom.
    static func text(for entries: [Entry]) -> String {
        entries.map { "[\($0.word)](/\($0.phonemes)/)" }.joined(separator: "\n")
    }

    /// Whether `text` looks like this notation at all.
    ///
    /// Lets a single paste field decide between "a batch to import" and "one
    /// pronunciation for the word being edited", without a mode switch the
    /// reader has to understand.
    static func looksLikeInlineNotation(_ text: String) -> Bool {
        !entries(in: text).isEmpty
    }
}
