package io.github.cidy02.kudos.reader.speech

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ReaderSpeechSeekTest {
    @Test fun eachHoldTickMovesOneParagraphAndBoundsNeverWrap() {
        assertEquals(2, ReaderSpeechSeek.seekIndex(1, 4, 1))
        assertEquals(0, ReaderSpeechSeek.seekIndex(1, 4, -1))
        assertNull(ReaderSpeechSeek.seekIndex(0, 4, -1))
        assertNull(ReaderSpeechSeek.seekIndex(3, 4, 1))
        assertNull(ReaderSpeechSeek.seekIndex(0, 0, 1))
        assertNull(ReaderSpeechSeek.seekIndex(0, 4, 0))
        assertNull(ReaderSpeechSeek.seekIndex(Int.MAX_VALUE, Int.MAX_VALUE, 1))
        var index = 0
        repeat(10) { index = ReaderSpeechSeek.seekIndex(index, 4, 1) ?: index }
        assertEquals(3, index)
        repeat(10) { index = ReaderSpeechSeek.seekIndex(index, 4, -1) ?: index }
        assertEquals(0, index)
    }
}
