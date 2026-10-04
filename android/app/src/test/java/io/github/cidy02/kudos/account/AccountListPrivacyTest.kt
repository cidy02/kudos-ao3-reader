package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.app.PrivacyRevealState
import io.github.cidy02.kudos.core.model.MatureContentMode
import io.github.cidy02.kudos.core.model.PrivacySettings
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.works.CanonicalWork
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/** iOS `AO3AccountWorksList.visibleEntries`: which library works stay paired with their AO3 row. */
class AccountListPrivacyTest {
    private fun paired(rating: String) = listOf(
        CanonicalWork(
            local = SavedWork(
                id = "w1",
                title = "Title",
                author = "Author",
                sourceUrl = "https://archiveofourown.org/works/12345",
                rating = rating
            ),
            remote = AO3WorkSummary(
                id = 12345L,
                title = "Title",
                authors = listOf("Author"),
                fandoms = emptyList(),
                rating = rating,
                warnings = emptyList(),
                categories = emptyList()
            )
        )
    )

    private fun privacy(mode: MatureContentMode, hide: Boolean = true) =
        PrivacySettings(hideMatureContent = hide, matureContentMode = mode)

    private fun local(
        rating: String,
        privacy: PrivacySettings,
        reveal: PrivacyRevealState = PrivacyRevealState()
    ) = visibleEntries(paired(rating), privacy, reveal).single().local

    @Test
    fun hideModeUnpairsAMatureLibraryWork() {
        assertNull(local("Explicit", privacy(MatureContentMode.Hide)))
        assertNull(local("Mature", privacy(MatureContentMode.Hide)))
    }

    @Test
    fun revealingKeepsItPaired() {
        assertNotNull(local("Explicit", privacy(MatureContentMode.Hide), PrivacyRevealState(revealAll = true)))
        assertNotNull(local("Explicit", privacy(MatureContentMode.Hide), PrivacyRevealState(revealedIds = setOf("w1"))))
    }

    @Test
    fun blurModeKeepsItPairedSoItsRowCanBlur() {
        assertNotNull(local("Explicit", privacy(MatureContentMode.Obscure)))
    }

    @Test
    fun otherRatingsAndTheSettingOffStayPaired() {
        assertNotNull(local("Teen And Up Audiences", privacy(MatureContentMode.Hide)))
        assertNotNull(local("Explicit", privacy(MatureContentMode.Hide, hide = false)))
    }
}
