package io.github.cidy02.kudos.writing

import io.github.cidy02.kudos.account.WritingDraftsRepository
import io.github.cidy02.kudos.library.LibraryPrivacy
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.writing.AO3DraftsPage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WritingScreenTest {
    @Test
    fun signedOutStateDoesNotExposeCreatorData() {
        val state = writingRootState(isSignedIn = false, drafts = drafts(draft()))

        assertFalse(state.isSignedIn)
        assertNull(state.latestDraft)
    }

    @Test
    fun loadedEmptyDraftsStateIsDistinctFromNotLoaded() {
        val empty = writingRootState(isSignedIn = true, drafts = drafts())
        val notLoaded = writingRootState(isSignedIn = true, drafts = null)

        assertTrue(empty.draftsLoaded)
        assertNull(empty.latestDraft)
        assertFalse(notLoaded.draftsLoaded)
    }

    @Test
    fun latestLoadedDraftIsTheContinueTarget() {
        val latest = draft(id = 42, title = "Last edited")
        val state = writingRootState(isSignedIn = true, drafts = drafts(latest, draft()))

        assertEquals(42L, state.latestDraft?.id)
        assertEquals("Last edited", state.latestDraft?.title)
    }

    @Test
    fun cachedDraftsStayWithTheAccountThatLoadedThem() {
        val cached = WritingDraftsRepository.CachedPage("Writer", 2, drafts(draft(title = "Secret")))

        assertNull(cachedWritingDrafts(cached, "Writer", 3))
        assertNull(cachedWritingDrafts(cached, "Other", 2))
        assertNull(cachedWritingDrafts(cached, null, 2))
        assertEquals("Secret", cachedWritingDrafts(cached, "writer", 2)?.page?.works?.first()?.title)
    }

    @Test
    fun hiddenMatureDraftUsesTheLibraryTitle() {
        val mature = draft(title = "Explicit Draft", rating = "Explicit")

        assertEquals(LibraryPrivacy.HIDDEN_WORK_TITLE, writingDraftTitle(mature, hideMature = true))
        assertEquals("Explicit Draft", writingDraftTitle(mature, hideMature = false))
        assertEquals("Quiet", writingDraftTitle(draft(title = "Quiet", rating = "General Audiences"), hideMature = true))
        assertEquals(LibraryPrivacy.HIDDEN_WORK_TITLE, writingDraftTitle(draft(title = "Unrated", rating = "Not Rated"), hideMature = true))
        assertEquals(LibraryPrivacy.HIDDEN_WORK_TITLE, writingDraftTitle(draft(title = "Pending", rating = ""), hideMature = true))
        assertEquals("Pending", writingDraftTitle(draft(title = "Pending", rating = ""), hideMature = false))
    }

    private fun drafts(vararg works: AO3WorkSummary) = AO3DraftsPage(
        page = AO3SearchPage(works.toList(), currentPage = 1, totalPages = 1),
        deletionDates = emptyMap()
    )

    private fun draft(
        id: Long = 1,
        title: String = "Draft title",
        rating: String = "General Audiences"
    ) = AO3WorkSummary(
        id = id,
        title = title,
        authors = listOf("writer"),
        fandoms = emptyList(),
        rating = rating,
        warnings = emptyList(),
        categories = emptyList()
    )
}
