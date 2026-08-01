package io.github.cidy02.kudos.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins the session-only reveal semantics `PrivacyGate` exists to provide — this is the
 * shared state that fixed a real bug found in review: Home's mature-content cards had
 * no reveal step at all, and Library's own toolbar toggle mutated the *persisted*
 * "Hide mature content" setting rather than a session-only reveal-all, which is what
 * Apple's `MatureRevealToggle` / `PrivacyGate.toggleRevealAll` actually does.
 */
class PrivacyGateTest {
    @Test
    fun aWorkIsNotRevealedUntilItIs() {
        val gate = PrivacyGate()
        assertFalse(gate.isRevealed("w1"))
    }

    @Test
    fun revealingOneWorkDoesNotRevealAnother() {
        val gate = PrivacyGate()
        gate.reveal("w1")
        assertTrue(gate.isRevealed("w1"))
        assertFalse(gate.isRevealed("w2"))
    }

    @Test
    fun toggleRevealAllShowsEveryWork() {
        val gate = PrivacyGate()
        gate.toggleRevealAll()
        assertTrue(gate.isRevealed("w1"))
        assertTrue(gate.isRevealed("anything"))
        assertTrue(gate.state.value.revealAll)
    }

    @Test
    fun togglingRevealAllBackOffAlsoClearsIndividualReveals() {
        // Matches Apple's toggleRevealAll: re-hiding is a full reset, not just the
        // headline flag — a work revealed one-by-one before Show All was tapped should
        // not stay revealed after Hide is tapped again.
        val gate = PrivacyGate()
        gate.reveal("w1")
        gate.toggleRevealAll()
        gate.toggleRevealAll()
        assertFalse(gate.state.value.revealAll)
        assertFalse(gate.isRevealed("w1"))
    }

    @Test
    fun revealAllOverridesPerWorkStateInTheCombinedPredicate() {
        val state = PrivacyRevealState(revealAll = true, revealedIds = emptySet())
        assertEquals(true, state.isRevealed("literally-anything"))
    }
}
