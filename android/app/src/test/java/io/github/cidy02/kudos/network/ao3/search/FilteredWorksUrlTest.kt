package io.github.cidy02.kudos.network.ao3.search

import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Port of iOS KudosTests/FilteredWorksURLTests.swift.
 * Pins the tag drill-down's endpoint — the URL built when a tag tapped inside a
 * work is filtered.
 */
class FilteredWorksUrlTest {
    private val builder = AO3SearchUrlBuilder()
    private val tagUrl = "https://archiveofourown.org/tags/Fluff/works"

    private fun url(string: String, filters: AO3SearchFilters = AO3SearchFilters(), page: Int = 1) =
        builder.buildFilteredWorksUrl(string, filters, page).toHttpUrl()

    @Test
    fun theTagsOwnPathIsUntouched() {
        val parsed = url(tagUrl)
        assertEquals("/tags/Fluff/works", parsed.encodedPath)
        assertEquals("archiveofourown.org", parsed.host)
    }

    @Test
    fun filtersReachAO3RatherThanBeingAppliedHere() {
        val filters = AO3SearchFilters(
            rating = AO3Rating.EXPLICIT,
            includeNotRated = false,
            completion = AO3Completion.COMPLETE,
            kudosFrom = "500",
            sort = AO3SearchSort.KUDOS
        )
        val parsed = url(tagUrl, filters)
        assertEquals("13", parsed.queryParameter("work_search[rating_ids]"))
        assertEquals("T", parsed.queryParameter("work_search[complete]"))
        assertEquals("> 500", parsed.queryParameter("work_search[kudos_count]"))
        assertEquals("kudos_count", parsed.queryParameter("work_search[sort_column]"))
    }

    @Test
    fun aTwoRatingSelectionTravelsInTheQueryInstead() {
        val filters = AO3SearchFilters(rating = AO3Rating.EXPLICIT)
        val parsed = url(tagUrl, filters)
        assertNull(parsed.queryParameter("work_search[rating_ids]"))
        assertTrue(parsed.queryParameter("work_search[query]")?.contains("rating_ids") == true)
    }

    @Test
    fun aTappedURLsOwnParametersSurvive() {
        val parsed = url("$tagUrl?utf8=%E2%9C%93&commit=Sort%20and%20Filter")
        assertEquals("✓", parsed.queryParameter("utf8"))
        assertEquals("Sort and Filter", parsed.queryParameter("commit"))
    }

    @Test
    fun theTappedURLsOwnFilterParametersAreReplacedNotDuplicated() {
        val filters = AO3SearchFilters(sort = AO3SearchSort.KUDOS)
        val stale = "$tagUrl?work_search%5Bsort_column%5D=word_count&work_search%5Bcomplete%5D=F"
        val parsed = url(stale, filters)
        assertEquals("kudos_count", parsed.queryParameter("work_search[sort_column]"))
        assertNull(parsed.queryParameter("work_search[complete]"))
    }

    @Test
    fun pageIsTheOneTheCallerAskedFor() {
        val parsed = url("$tagUrl?page=9", page = 2)
        assertEquals("2", parsed.queryParameter("page"))
    }

    @Test
    fun viewAdultIsSentExactlyOnce() {
        val parsed = url("$tagUrl?view_adult=true")
        assertEquals(listOf("true"), parsed.queryParameterValues("view_adult"))
    }
}
