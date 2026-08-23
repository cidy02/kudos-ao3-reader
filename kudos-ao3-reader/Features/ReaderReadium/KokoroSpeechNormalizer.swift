import Foundation

/// Conservative pre-G2P cleanup for Kokoro. Punctuation that carries prosody
/// is kept; curly apostrophes become ASCII `'` so Misaki cannot split
/// `wasn’t` into `was` + `nt` (FluidAudio issue #774).
nonisolated enum KokoroSpeechNormalizer: Sendable {
    /// Kokoro's 114-entry `vocab.json` carries `“` and `”` as *separate*
    /// tokens from `"`, and the model reads them as different intonation
    /// cues — in fiction that is the most common prosodic signal there is.
    /// So every double quote is resolved to a direction instead of being
    /// flattened, and these two are the only shapes that leave `normalize`.
    static let openQuote: Character = "\u{201C}"
    static let closeQuote: Character = "\u{201D}"

    private static let smartApostrophes: Set<Character> = [
        "\u{2018}", "\u{2019}", "\u{201B}", "\u{2032}", "\u{00B4}", "\u{02BC}"
    ]
    /// Quotes whose direction the character itself already states. The low-9
    /// `„` and the guillemets are not in the vocab at all, so they land on the
    /// nearest token by role — German's reversed `»…«` is a knowing miss, the
    /// French order being far commoner in the translated fic this sees.
    private static let openingQuotes: Set<Character> = ["\u{201C}", "\u{201E}", "\u{00AB}"]
    private static let closingQuotes: Set<Character> = ["\u{201D}", "\u{00BB}"]

    static func normalize(_ text: String) -> String {
        let folded = text.precomposedStringWithCanonicalMapping
        var scalars: [Character] = []
        scalars.reserveCapacity(folded.count)
        var pendingDots = 0
        var quoteIsOpen = false

        func flushDots() {
            guard pendingDots > 0 else { return }
            if pendingDots >= 3 {
                scalars.append("…")
            } else {
                for _ in 0 ..< pendingDots { scalars.append(".") }
            }
            pendingDots = 0
        }

        for ch in folded {
            if ch == "." {
                pendingDots += 1
                continue
            }
            flushDots()
            if smartApostrophes.contains(ch) {
                scalars.append("'")
            } else if openingQuotes.contains(ch) {
                scalars.append(openQuote)
                quoteIsOpen = true
            } else if closingQuotes.contains(ch) {
                scalars.append(closeQuote)
                quoteIsOpen = false
            } else if ch == "\"" {
                let opens = straightQuoteOpens(after: scalars.last, quoteIsOpen: quoteIsOpen)
                scalars.append(opens ? openQuote : closeQuote)
                quoteIsOpen = opens
            } else if ch == "\u{2013}" || ch == "\u{2014}" {
                scalars.append("—")
            } else if ch == "-", scalars.last == "-" {
                scalars[scalars.count - 1] = "—"
            } else if ch == "\u{00A0}" || ch == "\u{202F}" || ch == "\u{2007}" {
                scalars.append(" ")
            } else if ch == "\u{00AD}" {
                continue
            } else {
                scalars.append(ch)
            }
        }
        flushDots()

        let joined = String(scalars)
        let collapsed = joined.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `"` states no direction, so infer it from what precedes it.
    ///
    /// Whitespace wins over the running open/close state deliberately: a
    /// speech continuing across paragraphs opens a quote in every paragraph
    /// and closes none of them, which is ordinary fiction rather than an
    /// error, and a plain toggle would mislabel every quote after it. The
    /// state only breaks the tie after a dash, where `"Wait—"` closes but
    /// `—"Yes"` opens and nothing else separates them.
    private static func straightQuoteOpens(
        after previous: Character?,
        quoteIsOpen: Bool
    ) -> Bool {
        guard let previous else { return true }
        if previous.isWhitespace { return true }
        if "([{".contains(previous) { return true }
        if previous == "—" { return !quoteIsOpen }
        return false
    }

    /// Word-like tokens after normalization. Contractions stay one token.
    static func words(in text: String) -> [String] {
        let prepared = normalize(text)
        var out: [String] = []
        var current = ""
        for ch in prepared {
            if ch.isLetter || ch.isNumber || ch == "'" || ch == "-" {
                current.append(ch)
            } else {
                if !current.isEmpty {
                    out.append(current)
                    current = ""
                }
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}
