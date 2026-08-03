package io.github.cidy02.kudos.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ReaderContentTextTest {
    @Test
    fun splitsLongTextIntoSpeakableChunks() {
        val text = (1..20).joinToString(" ") { "Sentence number $it is here." }
        val chunks = ReaderContentText.splitIntoSpeakableChunks(text)
        assertTrue(chunks.size > 1)
        assertTrue(chunks.all { it.isNotBlank() })
        assertEquals(text.replace(Regex("\\s+"), " ").trim(), chunks.joinToString(" "))
    }

    @Test
    fun emptyTextYieldsNoChunks() {
        assertTrue(ReaderContentText.splitIntoSpeakableChunks("   ").isEmpty())
    }
}
