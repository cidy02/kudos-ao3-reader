import Foundation
import SwiftSoup

/// AO3's own word count (OD3, E2), so the number a writer sees in the editor is
/// the number AO3 prints once the chapter is posted.
///
/// otwarchive's `WordCounter` (`lib/word_counter.rb`, scripts from
/// `config/config.yml:894`), as docs/WRITING_EDITOR_ARCHITECTURE.md §3.6 records:
/// 1. text nodes only (tags, attributes and comments are not words);
/// 2. `--` becomes `—`;
/// 3. `'`, `’`, `‘` and `-` are removed, so "don't" and "well-known" are one word;
/// 4. each Han, Hiragana, Katakana or Thai character is one word;
/// 5. each other run of word characters is one word. Ruby's Unicode
///    `[[:word:]]` is Alphabetic + marks + decimal digits + connector
///    punctuation — checked against Ruby itself: Ⓐ and Ⅷ are word characters,
///    ² and ① are not, and ZWNJ/ZWJ are not (Persian "نمی‌دانم" is two words there).
///
/// Counted per text node, as AO3 does: `<b>foo</b>bar` is two words there too.
/// O(n) in the HTML; callers with a whole chapter run it off the main thread.
nonisolated enum AO3WordCounter {
    struct Breakdown: Equatable, Sendable {
        let total: Int
        let scriptCharacters: Int
    }

    static func count(_ html: String) -> Int {
        measure(html).total
    }

    /// Single-pass word/character count alongside how many tokens came from
    /// no-space scripts (`CHARACTER_COUNT_SCRIPTS`), so unit detection does not
    /// have to re-walk the DOM.
    static func measure(_ html: String) -> Breakdown {
        guard !html.isEmpty else { return Breakdown(total: 0, scriptCharacters: 0) }
        guard let document = try? SwiftSoup.parseBodyFragment(html),
              let body = document.body()
        else { return measureText(html) }
        var total = 0
        var scriptCharacters = 0
        var pending: [Node] = [body]
        while let node = pending.popLast() {
            if let text = node as? TextNode {
                let measured = measureText(text.getWholeText())
                total += measured.total
                scriptCharacters += measured.scriptCharacters
            } else if !(node is Comment) {
                pending.append(contentsOf: node.getChildNodes())
            }
        }
        return Breakdown(total: total, scriptCharacters: scriptCharacters)
    }

    /// Steps 2–5 over one text node's text.
    static func countText(_ text: String) -> Int {
        measureText(text).total
    }

    static func measureText(_ text: String) -> Breakdown {
        let normalized = text
            .replacingOccurrences(of: "--", with: "—")
            .replacingOccurrences(of: #"['’‘-]"#, with: "", options: .regularExpression)
        let range = NSRange(normalized.startIndex..., in: normalized)
        guard let wordPattern else { return Breakdown(total: 0, scriptCharacters: 0) }
        let matches = wordPattern.matches(in: normalized, range: range)
        let scriptCount = scriptPattern?.numberOfMatches(in: normalized, range: range) ?? 0
        return Breakdown(total: matches.count, scriptCharacters: scriptCount)
    }

    /// `CHARACTER_COUNT_SCRIPTS`: one word per character.
    private static let scripts = #"\p{Han}\p{Hiragana}\p{Katakana}\p{Thai}"#

    private static let scriptPattern = try? NSRegularExpression(pattern: "[\(scripts)]")

    /// AO3's `[scripts]|((?!scripts)[[:word:]])+`. A constant pattern, so it
    /// either always compiles or never does; the fixtures would catch never.
    private static let wordPattern = try? NSRegularExpression(
        pattern: "[\(scripts)]|(?:(?![\(scripts)])[\\p{Alphabetic}\\p{M}\\p{Nd}\\p{Pc}])+"
    )
}
