package io.github.cidy02.kudos.reader

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.launch
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

    /**
     * Audit A5-1: the debounced save had taken the value and was waiting on the database when
     * the reader was left. The flush cancelled it, found nothing pending and wrote nothing.
     */
    @Test
    fun aFlushDuringASaveWaitsForItAndLosesNothing() = runTest {
        val saved = mutableListOf<Int>()
        val database = CompletableDeferred<Unit>()
        val saver = ReaderProgressSaver(backgroundScope, debounceMillis = 1000) {
            database.await() // the save is suspended, as Room's is
            saved += it.spineIndex
        }
        saver.onProgress(ReaderProgress(4, 0.4))
        advanceTimeBy(1100)
        runCurrent()
        assertEquals("the save has begun and not finished", 0, saved.size)

        var flushed = false
        val leaving = launch { saver.flush(); flushed = true }
        runCurrent()
        assertEquals("the flush waits for the save in flight", false, flushed)
        database.complete(Unit)
        leaving.join()
        assertEquals(listOf(4), saved)
    }

    /** A page turned while a save is in flight is written by the flush, after it. */
    @Test
    fun aFlushWritesWhatArrivedDuringASave() = runTest {
        val saved = mutableListOf<Int>()
        val database = CompletableDeferred<Unit>()
        val saver = ReaderProgressSaver(backgroundScope, debounceMillis = 1000) {
            if (it.spineIndex == 4) database.await()
            saved += it.spineIndex
        }
        saver.onProgress(ReaderProgress(4, 0.4))
        advanceTimeBy(1100)
        runCurrent()
        saver.onProgress(ReaderProgress(5, 0.5)) // cancels the debounce job mid-save
        val leaving = launch { saver.flush() }
        runCurrent()
        database.complete(Unit)
        leaving.join()
        assertEquals(listOf(4, 5), saved)
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
