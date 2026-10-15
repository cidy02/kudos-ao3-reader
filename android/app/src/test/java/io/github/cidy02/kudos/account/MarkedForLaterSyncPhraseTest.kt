package io.github.cidy02.kudos.account

import org.junit.Assert.assertEquals
import org.junit.Test

/** iOS `AO3MarkedForLaterCopy.relativeSyncPhrase`, the same steps. */
class MarkedForLaterSyncPhraseTest {
    @Test fun agesReadAsIOSWritesThem() {
        val minute = 60_000L
        assertEquals("just now", relativeSyncPhrase(0, 59_999))
        assertEquals("1 min ago", relativeSyncPhrase(0, minute))
        assertEquals("59 min ago", relativeSyncPhrase(0, 59 * minute))
        assertEquals("1 hr ago", relativeSyncPhrase(0, 60 * minute))
        assertEquals("23 hr ago", relativeSyncPhrase(0, 23 * 60 * minute))
        assertEquals("1 day ago", relativeSyncPhrase(0, 24 * 60 * minute))
        assertEquals("3 days ago", relativeSyncPhrase(0, 3 * 24 * 60 * minute))
        assertEquals("just now", relativeSyncPhrase(minute, 0)) // a clock that went back
    }
}
