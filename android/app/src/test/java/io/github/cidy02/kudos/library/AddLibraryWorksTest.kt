package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.app.PrivacyRevealState
import io.github.cidy02.kudos.core.model.MatureContentMode
import io.github.cidy02.kudos.core.model.PrivacySettings
import io.github.cidy02.kudos.core.model.SavedWork
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Test

/** The "Add Works" picker of a collection and of a reading queue (iOS `AddLibraryWorksSheet`). */
class AddLibraryWorksTest {
    private fun work(id: String, rating: String = "General Audiences", added: Long = 0, author: String = "someone") =
        SavedWork(id = id, title = "Title $id", author = author, rating = rating, isSaved = true,
            dateAdded = Instant.ofEpochSecond(added))

    private val tame = work("tame", added = 1)
    private val explicit = work("explicit", rating = "Explicit", added = 2)
    private val mature = work("mature", rating = "Mature", added = 3)
    private val all = listOf(tame, explicit, mature)

    private fun ids(privacy: PrivacySettings, reveal: PrivacyRevealState = PrivacyRevealState()) =
        AddLibraryWorks.eligible(all, privacy, reveal).map { it.id }

    @Test fun aWorkHideMatureKeepsOutOrObscuresIsNotOfferedByName() {
        // The picker shows titles and authors and searches them: both modes keep a work out.
        assertEquals(listOf("tame"), ids(PrivacySettings(matureContentMode = MatureContentMode.Hide)))
        assertEquals(listOf("tame"), ids(PrivacySettings(matureContentMode = MatureContentMode.Obscure)))
        assertEquals("the app's default setting obscures", listOf("tame"), ids(PrivacySettings()))
    }

    @Test fun revealingBringsAWorkBackAndTheNewestAddedComesFirst() {
        assertEquals(listOf("mature", "explicit", "tame"), ids(PrivacySettings(), PrivacyRevealState(revealAll = true)))
        assertEquals(listOf("explicit", "tame"), ids(PrivacySettings(), PrivacyRevealState(revealedIds = setOf("explicit"))))
        assertEquals(listOf("mature", "explicit", "tame"), ids(PrivacySettings(hideMatureContent = false)))
    }

    @Test fun searchIsGlobalSearchsEveryTermAcrossTitleAndAuthor() {
        val works = listOf(work("a", author = "Avery"), work("b", author = "Blake"))
        assertEquals(works, AddLibraryWorks.matching(works, "  "))
        assertEquals(listOf("a"), AddLibraryWorks.matching(works, "title avery").map { it.id })
        assertEquals(emptyList<String>(), AddLibraryWorks.matching(works, "avery blake").map { it.id })
    }

    @Test fun theChosenWorksGoInTheOrderShownAndAHiddenChoiceIsDropped() {
        val shown = AddLibraryWorks.eligible(all, PrivacySettings(hideMatureContent = false), PrivacyRevealState())
        assertEquals(listOf("mature", "tame"), AddLibraryWorks.chosen(shown, setOf("tame", "mature")).map { it.id })
        // Chosen while revealed, then hidden again before Add: it is not added by a name no longer shown.
        val hiddenAgain = AddLibraryWorks.eligible(all, PrivacySettings(), PrivacyRevealState())
        assertEquals(listOf("tame"), AddLibraryWorks.chosen(hiddenAgain, setOf("tame", "mature")).map { it.id })
    }

    @Test fun theButtonCountsWhatItWillAdd() {
        assertEquals("Add", AddLibraryWorks.confirmationTitle(0))
        assertEquals("Add 3", AddLibraryWorks.confirmationTitle(3))
    }
}
