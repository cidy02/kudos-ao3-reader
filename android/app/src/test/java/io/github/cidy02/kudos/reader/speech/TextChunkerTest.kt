package io.github.cidy02.kudos.reader.speech

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TextChunkerTest {
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
