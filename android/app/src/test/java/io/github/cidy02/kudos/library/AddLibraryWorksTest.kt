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

    @Test fun aCollectionTilesCoversLeaveOutAnObscuredWork() {
        // The covers carry a title and an author; the page's own card says "Hidden mature work".
        val items = listOf(
            LibraryDisplayItem(LibraryWorkListItem(tame)),
            LibraryDisplayItem(LibraryWorkListItem(explicit), LibraryPrivacyVisibility.Obscured)
        )
        assertEquals(listOf("tame"), LibraryPrivacy.nameableWorks(items).map { it.id })
    }

    @Test fun aRowOfItsOwnCallsAnObscuredWorkHiddenAndNothingElse() {
        // The Library's Select mode listed an obscured work by title and author.
        assertEquals("Title tame", LibraryPrivacy.shownTitle(LibraryDisplayItem(LibraryWorkListItem(tame))))
        assertEquals("Hidden mature work", LibraryPrivacy.shownTitle(
            LibraryDisplayItem(LibraryWorkListItem(explicit), LibraryPrivacyVisibility.Obscured)))
    }

    @Test fun aScreenThatMarksThingsByTheLibraryLeavesOutWhatHideModeHides() {
        fun ids(privacy: PrivacySettings, reveal: PrivacyRevealState = PrivacyRevealState()) =
            LibraryPrivacy.withoutHidden(all, privacy, reveal).map { it.id }
        // Browse starred a fandom because of a hidden work. Obscure keeps its works (owner question 23).
        assertEquals(listOf("tame"), ids(PrivacySettings(matureContentMode = MatureContentMode.Hide)))
        assertEquals(listOf("tame", "explicit", "mature"), ids(PrivacySettings()))
        assertEquals(listOf("tame", "explicit", "mature"),
            ids(PrivacySettings(matureContentMode = MatureContentMode.Hide), PrivacyRevealState(revealAll = true)))
        // Before the setting has been read a screen assumes the stricter one.
        assertEquals(listOf("tame"), ids(LibraryPrivacy.UNREAD_SETTING))
    }

    /** Brief 3ck: a selection on a queue's or a collection's page. */
    @Test fun aSelectionsRemovalIsAskedInTheseWordsAndOnlyMissingCopiesAreFetched() {
        assertEquals("Remove 1 work?", SelectionActions.removeTitle(1))
        assertEquals("Remove 3 works?", SelectionActions.removeTitle(3))
        assertEquals("Kudos will remove the selected works from this queue. They will stay in your Library.",
            SelectionActions.removeMessage("queue"))
        val onDevice = work("kept").copy(sourceUrl = "https://archiveofourown.org/works/1", hasEpub = true)
        val missing = work("gone").copy(sourceUrl = "https://archiveofourown.org/works/2", hasEpub = false)
        val imported = work("file").copy(sourceUrl = "", hasEpub = false)
        // Not a copy already here, and not a file AO3 never had.
        assertEquals(listOf("gone"), SelectionActions.missingCopies(listOf(onDevice, missing, imported)).map { it.id })
    }

    @Test fun theButtonCountsWhatItWillAdd() {
        assertEquals("Add", AddLibraryWorks.confirmationTitle(0))
        assertEquals("Add 3", AddLibraryWorks.confirmationTitle(3))
    }
}
