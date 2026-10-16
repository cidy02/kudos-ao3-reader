package io.github.cidy02.kudos.network.ao3.author

import org.junit.Assert.*
import org.junit.Test

class SeriesCreatorTest {
    // SeriesCreatorTests: only the account behind a registered byline can edit.
    private fun creators(vararg paths: String) = ao3CreatorUsernames(paths.map { "https://archiveofourown.org$it" })

    @Test fun registeredUsernameWinsOverItsDisplayedPseud() {
        val identities = creators("/users/mirrorsalt/pseuds/saltandsilver")
        assertTrue(isSeriesCreator(identities, "mirrorsalt"))
        assertFalse(isSeriesCreator(creators("/users/someoneelse/pseuds/mirrorsalt"), "mirrorsalt"))
    }

    @Test fun matchingIgnoresAccountCaseAndSurroundingWhitespace() {
        assertTrue(isSeriesCreator(creators("/users/MirrorSalt"), "  mirrorsalt \n"))
        assertTrue(isSeriesCreator(listOf(" MirrorSalt "), "mirrorsalt"))
    }

    @Test fun orphanedAnonymousDeletedSignedOutAndEmptyNeverMatch() {
        assertTrue(creators("/users/orphan_account").isEmpty())
        assertFalse(isSeriesCreator(listOf("orphan_account"), " orphan_account "))
        for (username in listOf(null, "", "   ", "mirrorsalt")) {
            assertFalse(isSeriesCreator(emptyList(), username))
        }
        assertFalse(isSeriesCreator(creators("/users/mirrorsalt"), null))
        assertFalse(isSeriesCreator(creators("/users/mirrorsalt"), "   "))
    }

    @Test fun coCreatorsStillMatchAndOffsiteLinksNeverGrantEditing() {
        assertTrue(isSeriesCreator(creators("/users/someoneelse", "/users/mirrorsalt/pseuds/saltandsilver"), "mirrorsalt"))
        assertTrue(ao3CreatorUsernames(listOf("https://example.org/users/mirrorsalt")).isEmpty())
    }
}
