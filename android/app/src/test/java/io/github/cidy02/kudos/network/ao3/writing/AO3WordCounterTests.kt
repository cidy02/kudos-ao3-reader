package io.github.cidy02.kudos.network.ao3.writing

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.assertEquals
import org.junit.Test

/** Exact names and vectors from iOS KudosTests/AO3WordCounterTests.swift. */
class AO3WordCounterTests {
    @Test fun englishDropsApostrophesAndHyphensInsideWords() {
        assertEquals(5, AO3WordCounter.count("<p>It's a well-known don’t ‘quote’</p>"))
        assertEquals(2, AO3WordCounter.count("left - right"))
    }
    @Test fun aDoubleHyphenIsADashBetweenTwoWords() {
        assertEquals(2, AO3WordCounter.count("Stop--now"))
        assertEquals(2, AO3WordCounter.count("wait---no"))
    }
    @Test fun eachHanKanaOrThaiCharacterIsOneWord() {
        assertEquals(3, AO3WordCounter.count("日本語"))
        assertEquals(4, AO3WordCounter.count("ひらがな"))
        assertEquals(4, AO3WordCounter.count("カタカナ"))
        assertEquals(6, AO3WordCounter.count("สวัสดี"))
        assertEquals(2, AO3WordCounter.count("한국어 문장"))
    }
    @Test fun mixedScriptsCountEachWayInOneText() {
        assertEquals(4, AO3WordCounter.count("Hello 世界 world"))
        assertEquals(4, AO3WordCounter.count("東京でcoffee"))
    }
    @Test fun onlyTextNodesCount() {
        val html = """<p class="lead" title="three hidden words">One <em>two</em></p>""" +
            "<!-- a comment of five words --><p>three</p>"
        assertEquals(3, AO3WordCounter.count(html))
        assertEquals(2, AO3WordCounter.count("caf&eacute; &amp; tea"))
        assertEquals(2, AO3WordCounter.count("<b>foo</b>bar"))
    }
    @Test fun wordCharactersAreRubysWordClass() {
        assertEquals(3, AO3WordCounter.count("Ⓐ Ⅷ ０"))
        assertEquals(0, AO3WordCounter.count("² ①"))
        assertEquals(2, AO3WordCounter.count("a\u200Cb"))
        assertEquals(2, AO3WordCounter.count("日\u200C本"))
    }
    @Test fun digitsAndUnderscoresAreWordCharacters() {
        assertEquals(3, AO3WordCounter.count("in 2024, snake_case"))
        assertEquals(2, AO3WordCounter.count("3.5"))
    }
    @Test fun emptyAndMarkupOnlyAreZero() {
        assertEquals(0, AO3WordCounter.count(""))
        assertEquals(0, AO3WordCounter.count("<p></p><hr><br>"))
        assertEquals(0, AO3WordCounter.count("  \n\t "))
    }
    @Test fun theEditorCountIsAO3s() {
        assertEquals(5, WritingWordCount.count("<p>Stop--now 日本語</p>"))
    }

    @Test fun supplementaryScriptsAndInheritedMarksUseCodePoints() {
        assertEquals(2, AO3WordCounter.count("𠀀𠀁"))
        assertEquals(1, AO3WordCounter.count("e\u0301"))
        assertEquals(2, AO3WordCounter.count("a\u200Db"))
    }
}

/** Names and vectors from WritingCheckpointTests.swift. */
class WritingWordCountTests {
    @Test fun countsTheWordsBetweenTheTags() {
        assertEquals(4, WritingWordCount.count("<p>Hello <strong>brave</strong> world</p>\n<p>Again</p>"))
        assertEquals(0, WritingWordCount.count(""))
    }
    @Test fun countsOffTheMainActor() = runBlocking {
        val count = withContext(Dispatchers.Default) { WritingWordCount.count("<p>one two three</p>") }
        assertEquals(3, count)
    }
}
