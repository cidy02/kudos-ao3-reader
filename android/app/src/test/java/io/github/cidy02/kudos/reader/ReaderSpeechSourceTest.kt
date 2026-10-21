package io.github.cidy02.kudos.reader

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ReaderSpeechSourceTest {
    @Test fun fallbackIsOnlySpokenWhenThePublicationHasNoProse() = runBlocking {
        val empty = ReaderSpeechSource { null }.withFallback(listOf("Title", "Chapter"))
        assertEquals("Title", empty.next())
        assertEquals("Chapter", empty.next())
        assertNull(empty.next())
        var reads = 0
        val prose = ReaderSpeechSource { if (reads++ == 0) "Story" else null }
            .withFallback(listOf("Title"))
        assertEquals(0, reads)
        assertEquals("Story", prose.next())
        assertEquals(1, reads)
        assertNull(prose.next())
    }
}
