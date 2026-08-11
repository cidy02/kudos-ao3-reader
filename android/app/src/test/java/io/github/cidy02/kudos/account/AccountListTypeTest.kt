package io.github.cidy02.kudos.account

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Test

/**
 * Regression guard for the Account-tab crash fixed in 6da39ab3.
 *
 * `AccountViewModel.refreshCounts` iterates [AccountListType.hubEntries] and
 * hit a JVM-null entry from a class-initialization race, throwing an NPE that
 * shipped in 0.1.7. The production fix is a defensive null check the Kotlin
 * type system insists is unnecessary; this pins the invariant that check
 * exists to protect — the companion list is fully initialized and every entry
 * carries a usable, unique `listKey` for the counts cache.
 */
class AccountListTypeTest {

    @Test
    fun `hub entries are all initialized`() {
        val entries = AccountListType.hubEntries
        assertEquals("all five static hub rows must be present", 5, entries.size)
        entries.forEachIndexed { index, entry ->
            @Suppress("SENSELESS_COMPARISON")
            assertNotNull("hubEntries[$index] was null — class-init race is back", entry)
        }
    }

    @Test
    fun `hub entries have unique non-blank list keys`() {
        val keys = AccountListType.hubEntries.map { it.listKey }
        assertFalse("a blank listKey would collide in the counts cache", keys.any { it.isBlank() })
        assertEquals("listKey is the counts-cache key and must be unique", keys.size, keys.toSet().size)
    }
}
