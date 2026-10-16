package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.settings.LocalStorageFootprint
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** iOS `AO3MarkedForLaterScreenTests` (A59). */
class MarkedForLaterRulesTest {
    @Test fun anEmptiedPageReloadsOneThatHasRows() {
        assertEquals(1, pageAfterEmptying(currentPage = 2, totalPages = 2))
        assertEquals(3, pageAfterEmptying(currentPage = 4, totalPages = 4))
        assertEquals(1, pageAfterEmptying(currentPage = 1, totalPages = 3))
        assertEquals(2, pageAfterEmptying(currentPage = 2, totalPages = 3))
        assertNull(pageAfterEmptying(currentPage = 1, totalPages = 1))
    }

    @Test fun downloadLineRequiresARealSizeAndUsesTheSharedFileSizeLabel() {
        val label = LocalStorageFootprint.formatted(1_400_000)
        assertEquals("Downloaded · $label", markedForLaterDownloadLine(hasEpub = true, byteLabel = label))
        assertNull(markedForLaterDownloadLine(hasEpub = false, byteLabel = label))
        assertNull(markedForLaterDownloadLine(hasEpub = true, byteLabel = null))
        assertNull(markedForLaterDownloadLine(hasEpub = true, byteLabel = ""))
    }
}
