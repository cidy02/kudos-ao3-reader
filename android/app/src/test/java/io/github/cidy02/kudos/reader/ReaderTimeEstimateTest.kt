package io.github.cidy02.kudos.reader

import org.junit.Assert.*
import org.junit.Test

class ReaderTimeEstimateTest {
    @Test fun playbackDoesNotJumpBackAtChunkBoundariesOrAdvanceWhilePaused() {
        val clock = ReaderPlaybackClock()
        val normal = requireNotNull(ReaderTimeEstimate.ttsNowPlayingTiming(100, 25, 1.0))
        clock.update(normal, true, 0)
        assertEquals(normal.elapsed + 10, requireNotNull(clock.update(normal, true, 10_000)).elapsed, 0.0001)
        val paused = requireNotNull(clock.update(normal, false, 15_000))
        assertEquals(normal.elapsed + 15, paused.elapsed, 0.0001)
        assertEquals(paused.elapsed, requireNotNull(clock.update(normal, true, 60_000)).elapsed, 0.0001)
        val faster = requireNotNull(ReaderTimeEstimate.ttsNowPlayingTiming(100, 25, 1.5))
        assertEquals(paused.elapsed / 1.5, requireNotNull(clock.update(faster, true, 60_000)).elapsed, 0.0001)
        clock.reset()
        assertEquals(faster.elapsed, requireNotNull(clock.update(faster, false, 60_000)).elapsed, 0.0001)
    }

    @Test fun speechPaceIsSlowerThanSilentReadingAndScalesInverselyWithRate() {
        assertEquals(68.75, ReaderTimeEstimate.ttsSecondsPerPosition(1.0), 0.0001)
        assertTrue(ReaderTimeEstimate.ttsSecondsPerPosition(1.0) > 55.0)
        assertEquals(68.75 / 1.5, ReaderTimeEstimate.ttsSecondsPerPosition(1.5), 0.0001)
        assertEquals(137.5, ReaderTimeEstimate.ttsSecondsPerPosition(0.5), 0.0001)
    }

    @Test fun nowPlayingExposesDurationAndElapsed() {
        val timing = requireNotNull(ReaderTimeEstimate.ttsNowPlayingTiming(100, 25, 1.0))
        assertEquals(100 * 68.75, timing.duration, 0.0001)
        assertEquals(75 * 68.75, timing.elapsed, 0.0001)
        val faster = requireNotNull(ReaderTimeEstimate.ttsNowPlayingTiming(100, 25, 1.5))
        assertTrue(faster.duration < timing.duration)
    }

    @Test fun unknownTotalAndStaleRemainingPositionsAreHandled() {
        assertNull(ReaderTimeEstimate.ttsNowPlayingTiming(0, 0, 1.0))
        assertNull(ReaderTimeEstimate.ttsNowPlayingTiming(-1, 0, 1.0))
        val over = requireNotNull(ReaderTimeEstimate.ttsNowPlayingTiming(10, 50, 1.0))
        assertEquals(10 * 68.75, over.duration, 0.0001)
        assertEquals(0.0, over.elapsed, 0.0)
        val negative = requireNotNull(ReaderTimeEstimate.ttsNowPlayingTiming(10, -1, 1.0))
        assertEquals(negative.duration, negative.elapsed, 0.0)
    }
}
