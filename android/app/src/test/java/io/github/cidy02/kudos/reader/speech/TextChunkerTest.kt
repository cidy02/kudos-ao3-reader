package io.github.cidy02.kudos.reader.speech

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TextChunkerTest {
    @Test fun sentenceChunksSplitShortParagraphIntoCompleteSentences() {
        assertEquals(listOf("First sentence.", "Second sentence?", "Third sentence!"),
            TextChunker.sentenceChunks("First sentence. Second sentence? Third sentence!"))
    }

    @Test fun sentenceChunksPreserveCommasInsideOrdinarySentence() {
        assertEquals(listOf("Rain fell, softly.", "Then it stopped."),
            TextChunker.sentenceChunks("Rain fell, softly. Then it stopped."))
    }

    @Test fun sentenceChunksProtectHonorificsAndAbbreviations() {
        assertEquals(listOf("Dr. Smith went home.", "Mr. Darcy stayed."),
            TextChunker.sentenceChunks("Dr. Smith went home. Mr. Darcy stayed."))
        assertEquals(listOf("Try e.g. apples and pears.", "Then decide."),
            TextChunker.sentenceChunks("Try e.g. apples and pears. Then decide."))
    }

    @Test fun defaultChunkerKeepsShortMultiSentenceParagraphTogether() {
        val text = "First sentence. Second sentence."
        assertEquals(listOf(text), TextChunker.chunk(text))
    }

    @Test fun oversizedSentenceSplitsOnlyAtUsefulClauses() {
        val first = "A".repeat(150)
        val second = "B".repeat(150)
        val text = "$first, $second."
        assertEquals(listOf("$first,", "$second."), TextChunker.sentenceChunks(text))
        assertEquals(listOf("$first,", "$second."), TextChunker.chunk(text))
        assertEquals(listOf("$first.", "$second."), TextChunker.chunk("$first. $second."))
    }

    @Test fun sentenceChunksKeepClosingQuotesAndHandleEmptyInputAndCarriageReturns() {
        assertEquals(emptyList<String>(), TextChunker.sentenceChunks(" \n\r"))
        assertEquals(listOf("“Go!”", "Then wait."), TextChunker.sentenceChunks("“Go!” Then wait."))
        assertEquals(listOf("First.", "Next."), TextChunker.sentenceChunks("First.\rNext."))
        assertEquals(listOf("Wait...", "Then go."), TextChunker.sentenceChunks("Wait... Then go."))
    }

    @Test
    fun testEmptyInput() {
        assertEquals(emptyList<String>(), TextChunker.chunk(""))
    }

    @Test
    fun testSingleShortSentence() {
        val text = "This is a short sentence."
        assertEquals(listOf(text), TextChunker.chunk(text))
    }

    @Test
    fun testParagraphBreak() {
        val text = "First paragraph.\n\nSecond paragraph."
        assertEquals(listOf("First paragraph.", "Second paragraph."), TextChunker.chunk(text))
    }

    @Test
    fun testRunOnSentenceFallbackMultipleWords() {
        val words = List(60) { "word" }
        val text = words.joinToString(" ")
        val chunks = TextChunker.chunk(text, maxLength = 250)
        // 60 words * 5 chars (word+) = 300 chars. Needs 2 chunks.
        assertEquals(2, chunks.size)
        for (chunk in chunks) {
            assertTrue(chunk.length <= 250)
        }
    }
}
