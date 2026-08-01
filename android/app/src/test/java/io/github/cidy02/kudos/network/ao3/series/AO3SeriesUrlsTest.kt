package io.github.cidy02.kudos.network.ao3.series

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AO3SeriesUrlsTest {
    @Test
    fun pageOneOmitsPageQuery() {
        val series = "https://archiveofourown.org/series/55"
        assertEquals(
            "https://archiveofourown.org/series/55",
            AO3SeriesUrls.seriesPageUrl(series, page = 1)
        )
    }

    @Test
    fun pagePastOneAddsPageQuery() {
        val series = "https://archiveofourown.org/series/55"
        assertEquals(
            "https://archiveofourown.org/series/55?page=3",
            AO3SeriesUrls.seriesPageUrl(series, page = 3)
        )
    }

    @Test
    fun replacesExistingPageQuery() {
        val paged = "https://archiveofourown.org/series/55?page=2"
        assertEquals(
            "https://archiveofourown.org/series/55?page=4",
            AO3SeriesUrls.seriesPageUrl(paged, page = 4)
        )
        assertEquals(
            "https://archiveofourown.org/series/55",
            AO3SeriesUrls.seriesPageUrl(paged, page = 1)
        )
    }

    @Test
    fun preservesOtherQueryItemsWhenRepaging() {
        val url = "https://archiveofourown.org/series/55?view_full_work=true&page=2"
        val rebuilt = AO3SeriesUrls.seriesPageUrl(url, page = 3)
        assertTrue(rebuilt!!.contains("view_full_work=true"))
        assertTrue(rebuilt.contains("page=3"))
        assertFalse(rebuilt.contains("page=2"))
    }

    @Test
    fun resolvesRelativeSeriesPath() {
        assertEquals(
            "https://archiveofourown.org/series/777",
            AO3SeriesUrls.seriesPageUrl("/series/777", page = 1)
        )
    }

    @Test
    fun rejectsEmptyAndNonAo3() {
        assertNull(AO3SeriesUrls.seriesPageUrl("", page = 1))
        assertNull(AO3SeriesUrls.seriesPageUrl("   ", page = 1))
        assertNull(AO3SeriesUrls.seriesPageUrl("https://evil.example.com/series/1", page = 1))
    }

    @Test
    fun isSeriesUrlAcceptsAo3SeriesPaths() {
        assertTrue(AO3SeriesUrls.isSeriesUrl("https://archiveofourown.org/series/55"))
        assertTrue(AO3SeriesUrls.isSeriesUrl("https://archiveofourown.org/series/55/"))
        assertFalse(AO3SeriesUrls.isSeriesUrl("https://archiveofourown.org/works/55"))
        assertFalse(AO3SeriesUrls.isSeriesUrl("https://evil.example.com/series/55"))
    }
}
