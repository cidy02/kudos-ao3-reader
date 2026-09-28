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
/// 5. each other run of word characters (Ruby's `[[:word:]]`: letters, marks,
///    decimal digits, connector punctuation) is one word.
///
/// Counted per text node, as AO3 does: `<b>foo</b>bar` is two words there too.
/// O(n) in the HTML; callers with a whole chapter run it off the main thread.
nonisolated enum AO3WordCounter {
    static func count(_ html: String) -> Int {
        guard !html.isEmpty else { return 0 }
        guard let document = try? SwiftSoup.parseBodyFragment(html),
              let body = document.body()
        else { return countText(html) }
        var total = 0
        var pending: [Node] = [body]
        while let node = pending.popLast() {
            if let text = node as? TextNode {
                total += countText(text.getWholeText())
            } else if !(node is Comment) {
                pending.append(contentsOf: node.getChildNodes())
            }
        }
        return total
    }

    /// Steps 2–5 over one text node's text.
    static func countText(_ text: String) -> Int {
        let normalized = text
            .replacingOccurrences(of: "--", with: "—")
            .replacingOccurrences(of: #"['’‘-]"#, with: "", options: .regularExpression)
        let range = NSRange(normalized.startIndex..., in: normalized)
        return wordPattern?.numberOfMatches(in: normalized, range: range) ?? 0
    }

    /// `CHARACTER_COUNT_SCRIPTS`: one word per character.
    private static let scripts = #"\p{Han}\p{Hiragana}\p{Katakana}\p{Thai}"#

    /// AO3's `[scripts]|((?!scripts)[[:word:]])+`. A constant pattern, so it
    /// either always compiles or never does; the fixtures would catch never.
    private static let wordPattern = try? NSRegularExpression(
        pattern: "[\(scripts)]|(?:(?![\(scripts)])[\\p{L}\\p{M}\\p{Nd}\\p{Pc}])+"
    )
}
