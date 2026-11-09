package io.github.cidy02.kudos.account

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class AccountOverviewRowsTest {
    @Test
    fun readingOverviewOmitsMarkedForLaterAndSaysPage() {
        assertEquals(
            listOf("Bookmarks", "Collections", "Subscriptions"),
            accountOverviewReadingRows().map { it.title }
        )
        assertFalse(accountOverviewReadingRows().any { it.title == "Marked for Later" })
        assertEquals(
            "When you sign in, this page shows your AO3 account and activity.",
            SIGNED_OUT_ACCOUNT_LINE
        )
    }
}
