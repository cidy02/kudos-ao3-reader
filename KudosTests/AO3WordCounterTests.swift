import Foundation
import Testing
@testable import Kudos

/// E2 (OD3): AO3's word count, the golden fixtures for docs/WRITING_EDITOR_ARCHITECTURE.md
/// §3.6. Each expectation is what otwarchive's `WordCounter` prints for the same HTML.
struct AO3WordCounterTests {
    @Test func englishDropsApostrophesAndHyphensInsideWords() {
        // "Its a wellknown dont quote": five words, not seven.
        #expect(AO3WordCounter.count("<p>It's a well-known don’t ‘quote’</p>") == 5)
        // A spaced hyphen is removed and separates nothing.
        #expect(AO3WordCounter.count("left - right") == 2)
    }

    @Test func aDoubleHyphenIsADashBetweenTwoWords() {
        #expect(AO3WordCounter.count("Stop--now") == 2)
        #expect(AO3WordCounter.count("wait---no") == 2)
    }

    @Test func eachHanKanaOrThaiCharacterIsOneWord() {
        #expect(AO3WordCounter.count("日本語") == 3)
        #expect(AO3WordCounter.count("ひらがな") == 4)
        #expect(AO3WordCounter.count("カタカナ") == 4)
        // Thai counts per code point, combining vowels included, as AO3's scan does.
        #expect(AO3WordCounter.count("สวัสดี") == 6)
        // Hangul is not one of the scripts: a run is one word.
        #expect(AO3WordCounter.count("한국어 문장") == 2)
    }

    @Test func mixedScriptsCountEachWayInOneText() {
        #expect(AO3WordCounter.count("Hello 世界 world") == 4)
        #expect(AO3WordCounter.count("東京でcoffee") == 4)
    }

    @Test func onlyTextNodesCount() {
        let html = #"<p class="lead" title="three hidden words">One <em>two</em></p>"#
            + "<!-- a comment of five words --><p>three</p>"
        #expect(AO3WordCounter.count(html) == 3)
        // Entities are text; `&` is no word.
        #expect(AO3WordCounter.count("caf&eacute; &amp; tea") == 2)
        // Per text node, as AO3 counts: a tag between letters splits the word.
        #expect(AO3WordCounter.count("<b>foo</b>bar") == 2)
    }

    @Test func digitsAndUnderscoresAreWordCharacters() {
        #expect(AO3WordCounter.count("in 2024, snake_case") == 3)
        #expect(AO3WordCounter.count("3.5") == 2)
    }

    @Test func emptyAndMarkupOnlyAreZero() {
        #expect(AO3WordCounter.count("") == 0)
        #expect(AO3WordCounter.count("<p></p><hr><br>") == 0)
        #expect(AO3WordCounter.count("  \n\t ") == 0)
    }

    /// The editor's rule reads `WritingWordCount`, the one draft counter in the
    /// app. It must be AO3's count, not the old whitespace split: those two
    /// disagree on a dash and on CJK.
    @Test func theEditorCountIsAO3s() {
        #expect(WritingWordCount.count("<p>Stop--now 日本語</p>") == 5)
        #expect(WritingWordCount.count("<p>Stop--now 日本語</p>") == AO3WordCounter.count("<p>Stop--now 日本語</p>"))
    }
}
