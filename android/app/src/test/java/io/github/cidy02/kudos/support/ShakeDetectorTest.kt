package io.github.cidy02.kudos.support

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ShakeDetectorTest {

    @Test
    fun constantsMatchParitySpecification() {
        assertEquals(2, ShakeMath.REQUIRED_REVERSALS)
        assertEquals(600L, ShakeMath.REVERSAL_WINDOW_MS)
        assertEquals(13.5f, ShakeMath.THRESHOLD_MS2, 0.001f)
        assertEquals(1_500L, ShakeMath.DEBOUNCE_MS)
        assertEquals(2f, ShakeMath.REVERSAL_MAGNITUDE_FLOOR_MS2, 0.001f)
    }

    @Test
    fun dominantAxisIdentifiesLargestComponent() {
        assertEquals(0, ShakeMath.dominantAxis(10f, 1f, 2f))
        assertEquals(10f, ShakeMath.dominantAxisValue(10f, 1f, 2f), 0.001f)

        assertEquals(1, ShakeMath.dominantAxis(-2f, -12f, 1f))
        assertEquals(-12f, ShakeMath.dominantAxisValue(-2f, -12f, 1f), 0.001f)

        assertEquals(2, ShakeMath.dominantAxis(0f, 1f, -15f))
        assertEquals(-15f, ShakeMath.dominantAxisValue(0f, 1f, -15f), 0.001f)
    }

    @Test
    fun opposingSwingsAlongDominantAxisCountAsReversed() {
        // X dominant
        assertTrue(ShakeMath.samplesReversed(-5f, 0f, 0f, 5f, 0f, 0f))
        // Y dominant
        assertTrue(ShakeMath.samplesReversed(0f, -6f, 0.5f, 0f, 6f, 0.2f))
        // Z dominant
        assertTrue(ShakeMath.samplesReversed(0.1f, 0f, 7f, -0.2f, 0.1f, -7f))
    }

    @Test
    fun sameDirectionSwingsDoNotCountAsReversed() {
        assertFalse(ShakeMath.samplesReversed(5f, 0f, 0f, 4f, 0.5f, 0f))
        assertFalse(ShakeMath.samplesReversed(0f, -5f, 0f, 0.2f, -4f, 0f))
    }

    @Test
    fun swingsBelowNoiseFloorAreIgnored() {
        assertFalse(ShakeMath.samplesReversed(-0.5f, 0f, 0f, 0.5f, 0f, 0f))
        assertFalse(ShakeMath.samplesReversed(-5f, 0f, 0f, 0.1f, 0f, 0f))
        assertFalse(ShakeMath.samplesReversed(0.2f, 0f, 0f, 5f, 0f, 0f))
    }

    @Test
    fun countReversalsCountsOscillationsInSampleSequence() {
        // Back-and-forth shake along X: +5 -> -5 -> +5 (2 reversals)
        val shakeSequence = listOf(
            Triple(5f, 0f, 0f),
            Triple(-5f, 0f, 0f),
            Triple(5f, 0f, 0f)
        )
        assertEquals(2, ShakeMath.countReversals(shakeSequence))

        // Single sustained jolt in one direction: no reversals
        val joltSequence = listOf(
            Triple(3f, 0f, 0f),
            Triple(8f, 0.2f, 0f),
            Triple(5f, 0.1f, 0f),
            Triple(2f, 0f, 0f)
        )
        assertEquals(0, ShakeMath.countReversals(joltSequence))
    }

    @Test
    fun recentReversalsWithinWindowCountTowardGesture() {
        val now = 2_000L
        val timestamps = listOf(
            now - 500L, // within 600ms window
            now - 200L  // within 600ms window
        )
        assertEquals(2, ShakeMath.countRecentReversals(timestamps, now))
    }

    @Test
    fun reversalsOutsideWindowExpire() {
        val now = 2_000L
        val timestamps = listOf(
            now - 700L, // expired (> 600ms)
            now - 300L  // valid
        )
        assertEquals(1, ShakeMath.countRecentReversals(timestamps, now))
    }

    @Test
    fun pruneAndCountReversalsRemovesExpiredFromDeque() {
        val deque = ArrayDeque<Long>()
        val now = 10_000L
        deque.add(now - 800L) // expired
        deque.add(now - 650L) // expired
        deque.add(now - 400L) // valid
        deque.add(now - 100L) // valid

        val count = ShakeMath.pruneAndCountReversals(deque, now)
        assertEquals(2, count)
        assertEquals(2, deque.size)
        assertEquals(now - 400L, deque.first())
    }

    @Test
    fun debounceBlocksRapidSuccessiveTriggers() {
        val t0 = 1_000_000L
        assertTrue(ShakeMath.shouldFire(t0, lastFireMs = 0L))
        assertFalse(ShakeMath.shouldFire(t0 + 500L, lastFireMs = t0))
        assertFalse(ShakeMath.shouldFire(t0 + ShakeMath.DEBOUNCE_MS - 1, lastFireMs = t0))
        assertTrue(ShakeMath.shouldFire(t0 + ShakeMath.DEBOUNCE_MS, lastFireMs = t0))
    }
}
