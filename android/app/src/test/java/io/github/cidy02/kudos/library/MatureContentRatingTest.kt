package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.app.PrivacyRevealState
import io.github.cidy02.kudos.core.model.MatureContentMode
import io.github.cidy02.kudos.core.model.PrivacySettings
import io.github.cidy02.kudos.core.model.SavedWork
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * AO3's adult-rating rule, shared by local works and remote blurbs.
 * Each assertion fails if the rule is reverted to "contains mature or explicit".
 */
class MatureContentRatingTest {
    private val hide = PrivacySettings(hideMatureContent = true, matureContentMode = MatureContentMode.Hide)
    private val blur = PrivacySettings(hideMatureContent = true, matureContentMode = MatureContentMode.Obscure)
    private val off = PrivacySettings(hideMatureContent = false, matureContentMode = MatureContentMode.Hide)

    @Test
    fun onlyGeneralAndTeenAreNotAdult() {
        assertFalse(LibraryPrivacy.isAdultRating("General Audiences"))
        assertFalse(LibraryPrivacy.isAdultRating("Teen And Up Audiences"))
        assertFalse(LibraryPrivacy.isAdultRating("  general   audiences "))
        assertFalse(LibraryPrivacy.isAdultRating("TEEN AND UP AUDIENCES"))
    }

    @Test
    fun matureExplicitNotRatedAndUnknownAreAdult() {
        assertTrue(LibraryPrivacy.isAdultRating("Mature"))
        assertTrue(LibraryPrivacy.isAdultRating("Explicit"))
        assertTrue(LibraryPrivacy.isAdultRating("Not Rated"))
        assertTrue(LibraryPrivacy.isAdultRating("  NOT   rated "))
        assertTrue(LibraryPrivacy.isAdultRating("Unrated"))
        assertTrue(LibraryPrivacy.isAdultRating("Teen"))
        assertTrue(LibraryPrivacy.isAdultRating("E"))
    }

    @Test
    fun nullFailsClosedAndBlankIsNotAdultByItself() {
        assertTrue(LibraryPrivacy.isAdultRating(null))
        assertFalse(LibraryPrivacy.isAdultRating(""))
        assertFalse(LibraryPrivacy.isAdultRating("   "))
        assertFalse(LibraryPrivacy.isAdultRating("\n\t"))
    }

    @Test
    fun aBlankRemoteRowIsBlurredInBothModesAndNeverHidden() {
        for (rating in listOf<String?>(null, "", "   ")) {
            assertEquals(LibraryPrivacyVisibility.Obscured, remote(hide, rating))
            assertEquals(LibraryPrivacyVisibility.Obscured, remote(blur, rating))
            assertEquals(LibraryPrivacyVisibility.Visible, remote(hide, rating, PrivacyRevealState(revealedIds = setOf("9"))))
            assertEquals(LibraryPrivacyVisibility.Visible, remote(blur, rating, PrivacyRevealState(revealAll = true)))
        }
        assertEquals(LibraryPrivacyVisibility.Visible, remote(off, null))
        assertEquals(LibraryPrivacyVisibility.Visible, remote(off, ""))
    }

    @Test
    fun hideOmitsAKnownAdultRatingAndBlurKeepsItConcealed() {
        assertEquals(LibraryPrivacyVisibility.Hidden, remote(hide, "Not Rated"))
        assertEquals(LibraryPrivacyVisibility.Hidden, remote(hide, "Explicit"))
        assertEquals(LibraryPrivacyVisibility.Obscured, remote(blur, "Mature"))
        assertEquals(LibraryPrivacyVisibility.Obscured, remote(blur, "something else"))
        assertEquals(LibraryPrivacyVisibility.Visible, remote(hide, "General Audiences"))
        assertEquals(LibraryPrivacyVisibility.Visible, remote(hide, "Teen And Up Audiences"))
        assertEquals(LibraryPrivacyVisibility.Visible, remote(hide, "Explicit", PrivacyRevealState(revealedIds = setOf("9"))))
        assertEquals(LibraryPrivacyVisibility.Visible, remote(off, "Explicit"))
    }

    @Test
    fun aSavedWorkUsesTheSameRule() {
        assertEquals(LibraryPrivacyVisibility.Hidden, LibraryPrivacy.visibility(work("Not Rated"), hide))
        assertEquals(LibraryPrivacyVisibility.Hidden, LibraryPrivacy.visibility(work("Unknown"), hide))
        assertEquals(LibraryPrivacyVisibility.Visible, LibraryPrivacy.visibility(work(""), hide))
        assertEquals(LibraryPrivacyVisibility.Visible, LibraryPrivacy.visibility(work("   "), hide))
        assertEquals(LibraryPrivacyVisibility.Visible, LibraryPrivacy.visibility(work("Teen And Up Audiences"), hide))
        assertEquals(LibraryPrivacyVisibility.Obscured, LibraryPrivacy.visibility(work("Explicit"), blur))
        assertEquals(
            LibraryPrivacyVisibility.Visible,
            LibraryPrivacy.visibility(work("Mature"), hide, PrivacyRevealState(revealedIds = setOf("w")))
        )
    }

    @Test
    fun aRatedLocalCopySpeaksForABlankRemoteBlurb() {
        val local = work("General Audiences")
        assertEquals(
            LibraryPrivacyVisibility.Visible,
            LibraryPrivacy.remoteRowVisibility("9", "", local, hide, PrivacyRevealState())
        )
        assertEquals(
            LibraryPrivacyVisibility.Obscured,
            LibraryPrivacy.remoteRowVisibility("9", "", work(""), blur, PrivacyRevealState())
        )
        assertTrue(LibraryPrivacy.keepsRemoteRow("9", "", null, hide, PrivacyRevealState()))
        assertFalse(LibraryPrivacy.keepsRemoteRow("9", "Not Rated", null, hide, PrivacyRevealState()))
    }

    private fun remote(
        privacy: PrivacySettings,
        rating: String?,
        reveal: PrivacyRevealState = PrivacyRevealState()
    ) = LibraryPrivacy.remoteVisibility("9", rating, privacy, reveal)

    private fun work(rating: String) = SavedWork(id = "w", title = "Title", author = "Author", rating = rating)
}
