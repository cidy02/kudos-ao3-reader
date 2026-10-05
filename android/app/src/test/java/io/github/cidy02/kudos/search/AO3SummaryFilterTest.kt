package io.github.cidy02.kudos.search

import io.github.cidy02.kudos.account.SubscriptionWatermark
import io.github.cidy02.kudos.account.SubscriptionWatermarks
import io.github.cidy02.kudos.network.ao3.search.AO3ChapterCount
import io.github.cidy02.kudos.network.ao3.search.AO3Crossover
import io.github.cidy02.kudos.network.ao3.search.AO3SearchSort
import io.github.cidy02.kudos.network.ao3.search.AO3SortDirection
import io.github.cidy02.kudos.network.ao3.search.AO3Updated
import java.time.LocalDate
import io.github.cidy02.kudos.network.ao3.search.AO3Category
import io.github.cidy02.kudos.network.ao3.search.AO3Completion
import io.github.cidy02.kudos.network.ao3.search.AO3Language
import io.github.cidy02.kudos.network.ao3.search.AO3Rating
import io.github.cidy02.kudos.network.ao3.search.AO3RatingMatch
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.network.ao3.search.AO3Warning
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AO3SummaryFilterTest {
    private val work = AO3WorkSummary(
        id = 12L, title = "Title", authors = listOf("Author"),
        fandoms = listOf("Avatar: The Last Airbender"), rating = "Mature",
        warnings = listOf("Underage"), categories = listOf("F/F"),
        characters = listOf("Katara", "Toph Beifong"), relationships = listOf("Katara/Toph Beifong"),
        freeforms = listOf("Slow Burn", "Fluff"), language = "English", wordCount = 2500,
        chapters = "3/?", isComplete = false
    )

    @Test
    fun refineCombinesFacetsAndKeepsPageOrder() {
        val filters = AO3SearchFilters(
            fandom = "avatar", characters = "katara, toph", additionalTags = "slow burn, fluff",
            warnings = setOf(AO3Warning.UNDERAGE), categories = setOf(AO3Category.FF),
            language = AO3Language.ENGLISH, wordsFrom = "2,000", wordsTo = "3000",
            completion = AO3Completion.IN_PROGRESS
        )
        val page = listOf(work.copy(id = 3), work.copy(id = 1, wordCount = 100), work.copy(id = 2))
        assertEquals(listOf(3L, 2L), page.filter(filters::matchesSummary).map { it.id })
        assertFalse(filters.copy(characters = "Katara, Zuko").matchesSummary(work))
        assertFalse(filters.copy(excludedAdditionalTags = "FLUFF").matchesSummary(work))
        // An exclusion applies across all tag groups, matching iOS.
        assertFalse(filters.copy(excludedFandoms = "slow burn").matchesSummary(work))
        assertFalse(filters.copy(excludedWarnings = setOf(AO3Warning.UNDERAGE)).matchesSummary(work))
    }

    @Test
    fun ratingLadderAndUnratedToggleFollowIOS() {
        val filters = AO3SearchFilters(rating = AO3Rating.TEEN, includeNotRated = false)
        assertFalse(filters.matchesSummary(work))
        assertTrue(filters.copy(ratingMatch = AO3RatingMatch.OR_HIGHER).matchesSummary(work))
        assertFalse(filters.copy(ratingMatch = AO3RatingMatch.OR_LOWER).matchesSummary(work))
        assertTrue(filters.copy(includeNotRated = true).matchesSummary(work.copy(rating = "Not Rated")))
        assertFalse(AO3SearchFilters(includeNotRated = false).matchesSummary(work.copy(rating = "Not Rated")))
        assertTrue(filters.matchesSummary(work.copy(rating = "Teen And Up Audiences")))
    }

    @Test
    fun unknownSubscriptionsStayUntilTheirSummaryCanJudgeThem() {
        val indexOnly = work.copy(rating = "", fandoms = emptyList(), chapters = "")
        val filters = AO3SearchFilters(rating = AO3Rating.EXPLICIT, includeNotRated = false)
        assertTrue(filters.includesAccountWork(indexOnly, subscriptions = true))
        assertFalse(filters.includesAccountWork(indexOnly, subscriptions = false))
        assertFalse(filters.includesAccountWork(work, subscriptions = true))
        assertTrue(filters.includesAccountWork(work.copy(rating = "Explicit"), subscriptions = true))
    }

    @Test
    fun completionUsesSubscriptionChapterMetadataAndMissingWordsStayVisible() {
        val filters = AO3SearchFilters(completion = AO3Completion.COMPLETE, wordsFrom = "5000")
        assertTrue(filters.matchesSummary(work.copy(isComplete = null, chapters = "3/3", wordCount = null)))
        assertFalse(filters.matchesSummary(work.copy(isComplete = null, chapters = "3/?", wordCount = null)))
        assertTrue(filters.copy(completion = AO3Completion.IN_PROGRESS)
            .matchesSummary(work.copy(isComplete = null, chapters = "3/?", wordCount = null)))
    }

    @Test
    fun sharedLibraryMatchersPreserveExactFacetsAndBothUnderageSpellings() {
        val filters = AO3SearchFilters(warnings = setOf(AO3Warning.UNDERAGE), categories = setOf(AO3Category.FF))
        assertTrue(filters.matchesSummary(work.copy(warnings = listOf("UNDERAGE SEX"), categories = listOf("f/f"))))
        assertTrue(filters.matchesSummary(work))
        assertFalse(filters.matchesSummary(work.copy(warnings = listOf("Underage Sex Mentioned"))))
        assertFalse(filters.matchesSummary(work.copy(categories = listOf("F/F Relationship"))))
        assertTrue(filters.copy(wordsFrom = "abc", wordsTo = "99999999999999999999999999").matchesSummary(work))
        assertFalse(filters.copy(wordsFrom = "2147483648").matchesSummary(work))
    }

    @Test
    fun unknownChapterCountsCannotBecomeSeenWatermarks() {
        assertFalse(work.copy(chapters = "").hasPostedChapterCount())
        assertFalse(work.copy(chapters = "?/10").hasPostedChapterCount())
        assertTrue(work.hasPostedChapterCount())
        assertEquals(2, SubscriptionWatermarks.newChapterCount(work, mapOf(12L to SubscriptionWatermark(1))))
    }

    @Test
    fun liveMatchLineSeparatesUnknownRowsFromMatches() {
        assertEquals("1 of the 1 work on this page matches", refineMatchText(1, 1, 0))
        assertEquals("0 of the 3 works on this page match · 2 not checked yet", refineMatchText(3, 0, 2))
    }
    @Test
    fun singleChapterMeansFinishedAtOne() {
        val filters = AO3SearchFilters(chapterCount = AO3ChapterCount.SINGLE_CHAPTER)
        assertTrue(filters.matchesSummary(work.copy(chapters = "1/1")))
        assertTrue(filters.matchesSummary(work.copy(chapters = " 1 / 1 ")))
        assertFalse(filters.matchesSummary(work.copy(chapters = "1/?")))
        assertFalse(filters.matchesSummary(work.copy(chapters = "3/3")))
        assertFalse(filters.matchesSummary(work.copy(chapters = "1/2")))
        val page = listOf(work.copy(id = 3, chapters = "1/1"), work.copy(id = 1), work.copy(id = 2, chapters = "1/1"))
        assertEquals(listOf(3L, 2L), page.filter(filters::matchesSummary).map { it.id })
    }

    @Test
    fun unreadableChapterTextDoesNotHideAWork() {
        val filters = AO3SearchFilters(chapterCount = AO3ChapterCount.SINGLE_CHAPTER)
        assertTrue(filters.matchesSummary(work.copy(chapters = "")))
        assertTrue(filters.matchesSummary(work.copy(chapters = "unknown")))
        assertTrue(filters.matchesSummary(work.copy(chapters = "1/1/1")))
        val sparse = work.copy(rating = "", fandoms = emptyList(), chapters = "")
        assertTrue(filters.includesAccountWork(sparse, subscriptions = true))
        assertFalse(filters.includesAccountWork(work, subscriptions = true))
    }

    @Test
    fun queryOnlyFacetsDoNotNarrowLoadedPages() {
        val filters = AO3SearchFilters(
            query = "not present", title = "not present", creators = "not present",
            crossover = AO3Crossover.ONLY, updated = AO3Updated.WEEK,
            dateFrom = LocalDate.of(2099, 1, 1), dateTo = LocalDate.of(1900, 1, 1),
            hitsFrom = "999999", kudosTo = "1", commentsFrom = "999999", bookmarksTo = "1",
            sort = AO3SearchSort.TITLE, sortDirection = AO3SortDirection.ASCENDING
        )
        assertTrue(filters.matchesSummary(work))
        assertTrue(AO3SearchFilters(language = AO3Language.FRENCH)
            .matchesSummary(work.copy(language = "Français")))
    }

}
