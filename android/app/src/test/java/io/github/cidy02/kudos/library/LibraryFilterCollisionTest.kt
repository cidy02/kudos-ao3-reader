package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.core.model.MatureContentMode
import io.github.cidy02.kudos.core.model.PrivacySettings
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.Tag
import io.github.cidy02.kudos.network.ao3.search.AO3Rating
import org.junit.After
import org.junit.Before
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.Locale

/** iOS LibraryFiltersTests names; ICU supplies Swift's localized compact word label. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class LibraryFilterCollisionTest {
    private val originalLocale = Locale.getDefault()
    @Before fun useEnglishLabels() { Locale.setDefault(Locale.US) }
    @After fun restoreLocale() { Locale.setDefault(originalLocale) }

    private fun work(title: String) = SavedWork(id = title, title = title, author = "Writer")
    private fun items(vararg works: SavedWork) = works.map { LibraryDisplayItem(LibraryWorkListItem(it)) }
    private fun disjointWorks() = items(
        work("CompleteExplicit").copy(isComplete = true, rating = "Explicit", language = "English"),
        work("WIPTeen").copy(isComplete = false, rating = "Teen And Up Audiences", language = "English")
    )

    @Test
    fun droppingEachActiveFilterCountsWorksRevealedByDroppingOne() {
        val filters = LibraryFilterState(completion = LibraryCompletionFilter.Complete, rating = AO3Rating.TEEN)
        val works = disjointWorks()
        assertTrue(LibraryQuery.filterOnly(works, filters = filters).isEmpty())
        val drops = filters.droppingEachActiveFilter(works)
        assertEquals(mapOf("Complete" to 1, "Teen And Up" to 1), drops.associate { it.filterLabel to it.remainingCount })
        val withoutComplete = drops.first { it.filterLabel == "Complete" }.remainingFilters
        assertEquals(LibraryCompletionFilter.Any, withoutComplete.completion)
        assertEquals(AO3Rating.TEEN, withoutComplete.rating)
        drops.forEach {
            assertEquals(it.remainingCount, LibraryQuery.filterOnly(works, filters = it.remainingFilters).size)
        }
    }

    @Test
    fun collidingFilterLabelsNamesTheDisjointPair() {
        val filters = LibraryFilterState(
            completion = LibraryCompletionFilter.Complete, rating = AO3Rating.TEEN, language = "English"
        )
        assertEquals(listOf("Teen And Up", "Complete"), filters.collidingFilterLabels(disjointWorks()))
        assertEquals(listOf("Français"), filters.copy(language = "Français").collidingFilterLabels(disjointWorks()))
        // The bystander drop reveals zero and must not be offered by the card.
        assertEquals(0, filters.droppingEachActiveFilter(disjointWorks()).first { it.filterLabel == "English" }.remainingCount)
        assertEquals(2, filters.droppingEachActiveFilter(disjointWorks()).count { it.remainingCount > 0 })
    }

    @Test
    fun sameNamedFiltersOnDifferentFacetsStayDistinct() {
        val works = items(work("French").copy(language = "Français"))
        val filters = LibraryFilterState(userTagIds = setOf("tag-id"), language = "English")
        val names = mapOf("tag-id" to "English")
        val drops = filters.droppingEachActiveFilter(works, names)
        assertEquals(2, drops.map { it.id }.toSet().size)
        assertEquals(listOf("English (your tag)", "English (language)"), drops.map { it.filterLabel })
        assertFalse(filters.collidingFilterLabels(works, names).contains("English"))
        assertTrue(drops.all { it.remainingCount == 0 })
    }

    @Test
    fun droppingEachActiveFilterTreatsWordBoundsAsOneMember() {
        val works = items(
            work("Short").copy(isComplete = true, wordCount = 1000),
            work("Long").copy(isComplete = false, wordCount = 80000)
        )
        val filters = LibraryFilterState(completion = LibraryCompletionFilter.Complete, wordsFrom = "50000")
        assertTrue(LibraryQuery.filterOnly(works, filters = filters).isEmpty())
        val drops = filters.droppingEachActiveFilter(works)
        assertEquals(mapOf("Complete" to 1, "50K+ words" to 1), drops.associate { it.filterLabel to it.remainingCount })
        val bounded = filters.copy(wordsTo = "90000").droppingEachActiveFilter(works)
        assertEquals(2, bounded.size)
        val withoutWords = bounded.first { it.id.startsWith("words:") }
        assertEquals("Words 50000–90000", withoutWords.filterLabel)
        assertEquals(1, withoutWords.remainingCount)
        assertEquals("", withoutWords.remainingFilters.wordsFrom)
        assertEquals("", withoutWords.remainingFilters.wordsTo)
    }

    @Test
    fun tripleCollisionFallsBackToAllMembersWhenEveryPairOverlaps() {
        val filters = LibraryFilterState(rating = AO3Rating.TEEN, completion = LibraryCompletionFilter.Complete, language = "English")
        val works = items(
            work("RatingStatus").copy(rating = "Teen", isComplete = true, language = "Français"),
            work("RatingLanguage").copy(rating = "Teen", isComplete = false, language = "English"),
            work("StatusLanguage").copy(rating = "Explicit", isComplete = true, language = "English")
        )
        assertTrue(LibraryQuery.filterOnly(works, filters = filters).isEmpty())
        assertEquals(listOf("Teen And Up", "Complete", "English"), filters.collidingFilterLabels(works))
        assertEquals(listOf(1, 1, 1), filters.droppingEachActiveFilter(works).map { it.remainingCount })
    }

    @Test
    fun individualTagMembersAndUnknownWordCountsUseTheExistingMatcher() {
        val work = work("Tagged").copy(workTags = listOf("Fluff"), wordCount = 0)
        val works = listOf(LibraryDisplayItem(LibraryWorkListItem(work, userTags = listOf(Tag(id = "one", name = "One")))))
        val filters = LibraryFilterState(userTagIds = setOf("one", "two"), wordsFrom = "999999", excludeTags = setOf("Angst"))
        val drops = filters.droppingEachActiveFilter(works, mapOf("one" to "One", "two" to "Two"))
        assertEquals(1, drops.first { it.filterLabel == "Two" }.remainingCount)
        assertEquals(0, drops.first { it.filterLabel == "One" }.remainingCount)
        assertEquals(setOf("one"), drops.first { it.filterLabel == "Two" }.remainingFilters.userTagIds)
        assertEquals(listOf("Two"), filters.collidingFilterLabels(works, mapOf("one" to "One", "two" to "Two")))
        val excluded = LibraryFilterState(excludeTags = setOf("Fluff", "Angst"))
        assertEquals(1, excluded.droppingEachActiveFilter(works).first { it.filterLabel == "−Fluff" }.remainingCount)
        assertEquals(setOf("Angst"), excluded.droppingEachActiveFilter(works).first { it.filterLabel == "−Fluff" }.remainingFilters.excludeTags)
    }

    @Test
    fun sectionCountsAreBeforeFiltersButAfterPrivacyAndMembership() {
        val saved = LibraryWorkListItem(work("Saved").copy(isSaved = true, rating = "General Audiences"))
        val queued = LibraryWorkListItem(work("Queued").copy(isQueuedForLater = true, rating = "General Audiences"), inSavedForLater = true)
        val hidden = LibraryWorkListItem(work("Hidden").copy(isSaved = true, rating = "Explicit"))
        val other = LibraryWorkListItem(work("Other").copy(rating = "Teen And Up"))
        val filters = LibraryFilterState(rating = AO3Rating.TEEN)
        val state = LibraryQuery.buildState(
            LibrarySnapshot(listOf(saved, queued, hidden, other), emptyList(), emptyList(),
                PrivacySettings(hideMatureContent = true, matureContentMode = MatureContentMode.Hide)),
            "", filters, LibrarySort.Title
        )
        assertTrue(state.savedForLater.isEmpty())
        val base = LibrarySectionKind.SavedForLater.unfilteredItems(state)
        assertEquals(setOf("Saved", "Queued"), base.map { it.item.work.id }.toSet())
        assertEquals(2, filters.droppingEachActiveFilter(base).single().remainingCount)
        // Sort is absent from the filter members; defaults have no drops or collisions.
        assertTrue(LibraryFilterState().droppingEachActiveFilter(base).isEmpty())
        assertTrue(LibraryFilterState().collidingFilterLabels(base).isEmpty())
    }

    @Test
    fun collisionStringsKeepIosSingularPluralAndJoinedList() {
        assertEquals("Nothing matches.", libraryCollisionTitle(0))
        assertEquals("Nothing matches this filter.", libraryCollisionTitle(1))
        assertEquals("Nothing matches both filters.", libraryCollisionTitle(2))
        assertEquals("Nothing matches all three filters.", libraryCollisionTitle(3))
        assertEquals("Nothing matches all four filters.", libraryCollisionTitle(4))
        assertEquals("Nothing matches all five filters.", libraryCollisionTitle(5))
        assertEquals("Nothing matches all 6 filters.", libraryCollisionTitle(6))
        assertEquals("Your 1 work in Saved for Later is hidden by this filter.", libraryCollisionDetail("Saved for Later", 1, 1, listOf("Teen And Up")))
        assertEquals("All 2 of your works in Finished are hidden by these filters. Teen And Up and Complete have no works in common here.",
            libraryCollisionDetail("Finished", 2, 3, listOf("Teen And Up", "Complete")))
        assertEquals("Your 1 work in Favorites is hidden by this filter. Français matches no works here.",
            libraryCollisionDetail("Favorites", 1, 2, listOf("Français")))
        assertEquals("All 3 of your works in Reading Now are hidden by these filters. Teen And Up, Complete, and English have no works in common here.",
            libraryCollisionDetail("Reading Now", 3, 3, listOf("Teen And Up", "Complete", "English")))
    }
}
