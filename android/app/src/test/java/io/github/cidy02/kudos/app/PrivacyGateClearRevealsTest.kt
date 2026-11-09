package io.github.cidy02.kudos.app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS parity: another AO3 account starts with nothing revealed. */
class PrivacyGateClearRevealsTest {
    @Test
    fun clearRevealsForgetsEveryRevealedWork() {
        val gate = PrivacyGate()
        gate.reveal(setOf("local-1", "12345"))
        assertTrue(gate.isRevealed("local-1"))
        assertTrue(gate.isRevealed("12345"))
        gate.clearReveals()
        assertFalse(gate.isRevealed("local-1"))
        assertFalse(gate.isRevealed("12345"))
    }
}
