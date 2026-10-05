package io.github.cidy02.kudos.network.ao3.search

import java.time.LocalDate
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Names follow iOS SearchURLTests and SearchFiltersTests; assertions inspect built URLs, never dispatch them. */
class SearchURLTests {
    private val builder = AO3SearchUrlBuilder()

    @Test
    fun rangeExpressionCoversBothBoundsAndNeither() {
        val cases = listOf(
            Triple("10", "20", "10-20"), Triple("10", "", "> 10"),
            Triple("", "20", "< 20"), Triple("", "", null), Triple("  ", "  ", null)
        )
        for ((from, to, expected) in cases) {
            val filters = AO3SearchFilters(
                wordsFrom = from, wordsTo = to, hitsFrom = from, hitsTo = to,
                kudosFrom = from, kudosTo = to, commentsFrom = from, commentsTo = to,
                bookmarksFrom = from, bookmarksTo = to
            )
            for (url in listOf(builder.buildSearchUrl(filters), builder.buildFandomWorksUrl("Naruto", filters)!!)) {
                val parsed = url.toHttpUrl()
                for (field in listOf("word_count", "hits", "kudos_count", "comments_count", "bookmarks_count")) {
                    assertEquals("$field: $url", expected, parsed.queryParameter("work_search[$field]"))
                }
            }
        }
    }

    @Test
    fun titleAndCreatorUseTheirOwnFieldsNotTheFreeTextQuery() {
        val filters = AO3SearchFilters(
            title = "  Sea & Sky  ", creators = " writer_pseud ",
            chapterCount = AO3ChapterCount.SINGLE_CHAPTER,
            updated = AO3Updated.WEEK, dateFrom = LocalDate.of(2025, 1, 2), dateTo = LocalDate.of(2025, 3, 4)
        )
        for (url in listOf(builder.buildSearchUrl(filters), builder.buildFandomWorksUrl("Naruto", filters)!!)) {
            val parsed = url.toHttpUrl()
            assertEquals("Sea & Sky", parsed.queryParameter("work_search[title]"))
            assertEquals("writer_pseud", parsed.queryParameter("work_search[creators]"))
            assertEquals("1", parsed.queryParameter("work_search[single_chapter]"))
            assertEquals("< 1 week ago", parsed.queryParameter("work_search[revised_at]"))
            assertEquals("2025-01-02", parsed.queryParameter("work_search[date_from]"))
            assertEquals("2025-03-04", parsed.queryParameter("work_search[date_to]"))
            assertNull(parsed.queryParameter("work_search[query]"))
        }
        val empty = builder.buildSearchUrl(AO3SearchFilters(title = " ", creators = " ")).toHttpUrl()
        for (field in listOf("title", "creators", "single_chapter", "date_from", "date_to")) {
            assertNull(empty.queryParameter("work_search[$field]"))
        }
    }

    @Test
    fun sortSendsColumnAndDirectionTogether() {
        assertEquals(AO3SortDirection.ASCENDING, AO3SearchSort.TITLE.naturalDirection)
        assertEquals(AO3SortDirection.ASCENDING, AO3SearchSort.CREATOR.naturalDirection)
        assertEquals(AO3SortDirection.DESCENDING, AO3SearchSort.KUDOS.naturalDirection)
        assertEquals(AO3SortDirection.DESCENDING, AO3SearchSort.DATE_UPDATED.naturalDirection)
        for (sort in AO3SearchSort.entries) {
            for (direction in AO3SortDirection.entries) {
                val filters = AO3SearchFilters(sort = sort, sortDirection = direction)
                for (url in listOf(builder.buildSearchUrl(filters), builder.buildFandomWorksUrl("Naruto", filters)!!)) {
                    val parsed = url.toHttpUrl()
                    assertEquals(sort.sortColumn, parsed.queryParameter("work_search[sort_column]"))
                    assertEquals(if (sort == AO3SearchSort.RELEVANCE) null else direction.ao3Value,
                        parsed.queryParameter("work_search[sort_direction]"))
                }
            }
        }
        assertEquals("authors_to_sort_on", AO3SearchSort.CREATOR.sortColumn)
        assertEquals("title_to_sort_on", AO3SearchSort.TITLE.sortColumn)
    }

    @Test
    fun absoluteDateBoundsUseAO3sISOFormat() {
        val filters = AO3SearchFilters(dateFrom = LocalDate.of(2024, 1, 31), dateTo = LocalDate.of(2025, 12, 25))
        val parsed = builder.buildSearchUrl(filters).toHttpUrl()
        // LocalDate preserves the picked day without a UTC/time-of-day conversion.
        assertEquals("2024-01-31", parsed.queryParameter("work_search[date_from]"))
        assertEquals("2025-12-25", parsed.queryParameter("work_search[date_to]"))
    }

    @Test
    fun facetedChoicesUseAO3sFlagValues() {
        val parsed = builder.buildSearchUrl(AO3SearchFilters(
            crossover = AO3Crossover.EXCLUDE, completion = AO3Completion.COMPLETE,
            chapterCount = AO3ChapterCount.SINGLE_CHAPTER
        )).toHttpUrl()
        assertEquals("F", parsed.queryParameter("work_search[crossover]"))
        assertEquals("T", parsed.queryParameter("work_search[complete]"))
        assertEquals("1", parsed.queryParameter("work_search[single_chapter]"))
    }

    @Test
    fun everyNumericFieldUsesAO3sRangeGrammar() {
        val parsed = builder.buildSearchUrl(AO3SearchFilters(
            wordsFrom = "1000", wordsTo = "5000", hitsFrom = "100", kudosTo = "50",
            commentsFrom = "5", bookmarksFrom = "2", bookmarksTo = "20"
        )).toHttpUrl()
        assertEquals("1000-5000", parsed.queryParameter("work_search[word_count]"))
        assertEquals("> 100", parsed.queryParameter("work_search[hits]"))
        assertEquals("< 50", parsed.queryParameter("work_search[kudos_count]"))
        assertEquals("> 5", parsed.queryParameter("work_search[comments_count]"))
        assertEquals("2-20", parsed.queryParameter("work_search[bookmarks_count]"))
    }

    @Test
    fun relevanceSortSendsNeitherColumnNorDirection() {
        val parsed = builder.buildSearchUrl(AO3SearchFilters(sortDirection = AO3SortDirection.ASCENDING)).toHttpUrl()
        assertNull(parsed.queryParameter("work_search[sort_column]"))
        assertNull(parsed.queryParameter("work_search[sort_direction]"))
    }

    @Test
    fun languageCatalogUsesIOSNativeNamesAndQueryIDs() {
        assertEquals(163, AO3Language.entries.size)
        assertEquals(AO3Language.ANY, AO3Language.entries.first())
        assertEquals("Français", AO3Language.FRENCH.title)
        assertEquals("Português brasileiro", AO3Language.PORTUGUESE.title)
        assertEquals("中文-普通话 國語", AO3Language.CHINESE.title)
        assertTrue(AO3Language.entries.any { it.code == "ptPT" })
        for (language in AO3Language.entries) {
            val parsed = builder.buildSearchUrl(AO3SearchFilters(language = language)).toHttpUrl()
            assertEquals(language.code, parsed.queryParameter("work_search[language_id]"))
        }
    }
}
