package io.github.cidy02.kudos.reader

import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ReaderProgressSaverTest {
    @Test
    fun debouncesRapidUpdatesToTheLastValue() = runTest {
        val saved = mutableListOf<ReaderProgress>()
        val saver = ReaderProgressSaver(backgroundScope, debounceMillis = 1000) { saved += it }

        saver.onProgress(ReaderProgress(1, 0.1))
        saver.onProgress(ReaderProgress(2, 0.2))
        saver.onProgress(ReaderProgress(3, 0.3))

        // Before the debounce window elapses, nothing is saved.
        advanceTimeBy(500)
        runCurrent()
        assertEquals(0, saved.size)

        advanceTimeBy(600)
        runCurrent()
        assertEquals(1, saved.size)
        assertEquals(3, saved.first().spineIndex)
    }

    @Test
    fun flushPersistsPendingImmediately() = runTest {
        var saved: ReaderProgress? = null
        val saver = ReaderProgressSaver(backgroundScope, debounceMillis = 5000) { saved = it }

        saver.onProgress(ReaderProgress(8, 0.8))
        assertNull(saved)
        saver.flush()
        assertEquals(8, saved?.spineIndex)
    }
}
