package io.github.cidy02.kudos.support

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

class ShakeMathTest {

    @Test
    fun atRestNearGravityProducesNearZeroDelta() {
        // Phone lying still: one axis ≈ g, others ≈ 0.
        val delta = ShakeMath.accelerationDelta(0f, 0f, ShakeMath.GRAVITY_MS2)
        assertTrue(abs(delta) < 0.01f)
        assertFalse(ShakeMath.isShake(delta))
    }

    @Test
    fun strongJoltExceedsThreshold() {
        // Synthetic spike well above gravity on all axes.
        val delta = ShakeMath.accelerationDelta(15f, 15f, 15f)
        assertTrue(delta > ShakeMath.THRESHOLD_MS2)
        assertTrue(ShakeMath.isShake(delta))
    }

    @Test
    fun justBelowThresholdIsNotAShake() {
        // Magnitude = g + threshold → delta == threshold (strict > required).
        val axis = ShakeMath.GRAVITY_MS2 + ShakeMath.THRESHOLD_MS2
        val delta = ShakeMath.accelerationDelta(axis, 0f, 0f)
        assertEquals(ShakeMath.THRESHOLD_MS2, delta, 0.001f)
        assertFalse(ShakeMath.isShake(delta))
    }

    @Test
    fun justAboveThresholdIsAShake() {
        val axis = ShakeMath.GRAVITY_MS2 + ShakeMath.THRESHOLD_MS2 + 0.5f
        val delta = ShakeMath.accelerationDelta(axis, 0f, 0f)
        assertTrue(ShakeMath.isShake(delta))
    }

    @Test
    fun debounceBlocksRapidRepeatFires() {
        val t0 = 1_000_000L
        assertTrue(ShakeMath.shouldFire(t0, lastFireMs = 0L))
        assertFalse(ShakeMath.shouldFire(t0 + 500L, lastFireMs = t0))
        assertFalse(ShakeMath.shouldFire(t0 + ShakeMath.DEBOUNCE_MS - 1, lastFireMs = t0))
        assertTrue(ShakeMath.shouldFire(t0 + ShakeMath.DEBOUNCE_MS, lastFireMs = t0))
    }
}
