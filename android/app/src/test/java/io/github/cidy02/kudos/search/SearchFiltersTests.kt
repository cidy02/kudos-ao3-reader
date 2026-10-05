package io.github.cidy02.kudos.search

import io.github.cidy02.kudos.network.ao3.search.AO3ChapterCount
import io.github.cidy02.kudos.network.ao3.search.AO3Language
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.network.ao3.search.AO3SearchSort
import io.github.cidy02.kudos.network.ao3.search.AO3SortDirection
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Pure iOS FilterRangeSlider, FilterLanguagePicker, and TagSelectField behavior. */
class SearchFiltersTests {
    @Test
    fun languageSearchFiltersByNativeNameAndKeepsAnyFirst() {
        assertEquals(AO3Language.ANY, matchingFilterLanguages("").first())
        assertEquals(163, matchingFilterLanguages("  ").size)
        assertTrue(AO3Language.ENGLISH in matchingFilterLanguages("English"))
        assertFalse(AO3Language.ANY in matchingFilterLanguages("English"))
        assertTrue(matchingFilterLanguages("cestina").any { it.code == "cs" })
        assertTrue(matchingFilterLanguages("العربية").any { it.code == "ar" })
        assertTrue(matchingFilterLanguages("ptPT").any { it.code == "ptPT" })
        assertTrue(matchingFilterLanguages("xyzzy-not-a-language").isEmpty())
    }

    @Test
    fun rangeSliderDomainExpandsPastTheDefaultMaximum() {
        assertEquals(5000L, FilterRangeValues.integer("5000"))
        assertNull(FilterRangeValues.integer(""))
        assertNull(FilterRangeValues.integer("  "))
        assertNull(FilterRangeValues.integer("٥٠٠"))
        assertEquals("123", FilterRangeValues.digitsOnly("a1,2٣3"))
        assertEquals(200_000L, FilterRangeValues.expandedMaximum(200_000, listOf(10, 20)))
        assertEquals(1_000_000L, FilterRangeValues.expandedMaximum(200_000, listOf(500_000)))
        assertEquals(200_000L, FilterRangeValues.expandedMaximum(200_000, emptyList()))
    }

    @Test
    fun rangeSliderClampsExtremeInput() {
        assertEquals(Long.MAX_VALUE, FilterRangeValues.expandedMaximum(200_000, listOf(Long.MAX_VALUE)))
        assertNull(FilterRangeValues.integer("9999999999999999999999999999"))
    }

    @Test
    fun tagSelectionCyclesIncludeExcludeClear() {
        val tag = "Fluff"
        val included = cycleFilterTag(tag, "", "")
        assertEquals("Fluff" to "", included)
        assertEquals("1 included", tagSelectionSummary(included.first, included.second))
        val excluded = cycleFilterTag(tag, included.first, included.second)
        assertEquals("" to "Fluff", excluded)
        assertEquals("1 excluded", tagSelectionSummary(excluded.first, excluded.second))
        val cleared = cycleFilterTag(tag, excluded.first, excluded.second)
        assertEquals("" to "", cleared)
        assertEquals("Any", tagSelectionSummary(cleared.first, cleared.second))
        assertEquals("1 included · 1 excluded", tagSelectionSummary("Fluff", "Angst"))
        assertEquals("A, B" to "", cycleFilterTag("B", "A", ""))
    }

    @Test
    fun everyNewFacetIsSearchableAndCounted() {
        val newFacets = listOf(
            AO3SearchFilters(title = "Title"), AO3SearchFilters(creators = "Creator"),
            AO3SearchFilters(chapterCount = AO3ChapterCount.SINGLE_CHAPTER),
            AO3SearchFilters(hitsFrom = "10"), AO3SearchFilters(hitsTo = "20"),
            AO3SearchFilters(kudosFrom = "10"), AO3SearchFilters(kudosTo = "20"),
            AO3SearchFilters(commentsFrom = "10"), AO3SearchFilters(commentsTo = "20"),
            AO3SearchFilters(bookmarksFrom = "10"), AO3SearchFilters(bookmarksTo = "20"),
            AO3SearchFilters(dateFrom = LocalDate.of(2025, 1, 1)),
            AO3SearchFilters(dateTo = LocalDate.of(2025, 1, 1)),
            AO3SearchFilters(sortDirection = AO3SortDirection.ASCENDING),
            AO3SearchFilters(sort = AO3SearchSort.TITLE), AO3SearchFilters(sort = AO3SearchSort.CREATOR)
        )
        newFacets.forEach {
            assertTrue(it.hasActiveFilters)
            assertTrue(it.isSearchable)
            assertTrue(activeFilterCount(it) > 0)
            assertEquals(AO3SearchFilters(), clearedFiltersPreservingQuery(it))
        }
    }
}
