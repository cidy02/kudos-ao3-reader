import Foundation

/// Conservative pre-G2P cleanup for Kokoro. Punctuation that carries prosody
/// is kept; curly apostrophes become ASCII `'` so Misaki cannot split
/// `wasn’t` into `was` + `nt` (FluidAudio issue #774).
nonisolated enum KokoroSpeechNormalizer: Sendable {
    private static let smartApostrophes: Set<Character> = [
        "\u{2018}", "\u{2019}", "\u{201B}", "\u{2032}", "\u{00B4}", "\u{02BC}"
    ]
    private static let doubleQuotes: Set<Character> = [
        "\u{201C}", "\u{201D}", "\u{201E}", "\u{00AB}", "\u{00BB}"
    ]

    static func normalize(_ text: String) -> String {
        let folded = text.precomposedStringWithCanonicalMapping
        var scalars: [Character] = []
        scalars.reserveCapacity(folded.count)
        var pendingDots = 0

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
            } else if doubleQuotes.contains(ch) {
                scalars.append("\"")
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
