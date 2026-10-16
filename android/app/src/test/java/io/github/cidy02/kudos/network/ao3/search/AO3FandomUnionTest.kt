package io.github.cidy02.kudos.network.ao3.search

import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.*
import org.junit.Test

class AO3FandomUnionTest {
    // Ports AO3FandomUnionTests: grouped OR, singleton, empty and stable deduplication.
    @Test fun queryUsesCanonicalIDsInFirstSeenOrder() {
        assertEquals("filter_ids:(27785 OR 99117)", AO3FandomUnion.queryClause(listOf(27785, 99117)))
        assertEquals("filter_ids:27785", AO3FandomUnion.queryClause(listOf(27785)))
        assertNull(AO3FandomUnion.queryClause(emptyList()))
        assertEquals("filter_ids:(99117 OR 27785)", AO3FandomUnion.queryClause(listOf(99117, 27785, 99117)))
    }

    @Test fun onlyOfficialFeedControlsIdentifyThePage() {
        assertEquals(27785L, AO3FandomUnion.filterID("""
            <head><link rel="alternate" type="application/atom+xml" href="/tags/27785/feed.atom"></head>
        """, "Doctor Who (2005)"))
        assertEquals(27785L, AO3FandomUnion.filterID("""
            <div id="main"><div class="navigation actions module"><ul class="user navigation actions">
            <li><a href="https://archiveofourown.org/tags/27785/feed.atom">RSS Feed</a></li></ul></div></div>
        """, "Doctor Who (2005)"))
        assertNull(AO3FandomUnion.filterID("""
            <head><link rel="alternate" type="application/atom+xml" href="https://example.com/tags/17/feed.atom"></head>
            <body><p>See /tags/27785/feed.atom</p><a href="/tags/99117/feed.atom">Another feed</a></body>
        """, "Doctor Who (2005)"))
        assertNull(AO3FandomUnion.filterID("<h2>No works found</h2>", "Nothing Here"))
    }

    @Test fun sidebarFallbackKeepsYearsDecodesNamesAndRejectsOtherKinds() {
        val html = """<form id="work-filters">
            <label><input name="include_work_search[fandom_ids][]" value="99117">Doctor Who (1963) (9,958)</label>
            <label><input name="include_work_search[fandom_ids][]" value="27785">Doctor Who (2005) (61,248)</label>
            <label><input name="include_work_search[character_ids][]" value="12">A &amp; B (6)</label>
            <label><input name="exclude_work_search[fandom_ids][]" value="13">A &amp; B (6)</label>
            <label><input name="include_work_search[fandom_ids][]" value="-1">A &amp; B (6)</label>
            <label><input name="include_work_search[fandom_ids][]" value="123">A &amp; B (6)</label></form>"""
        assertEquals(27785L, AO3FandomUnion.filterID(html, "Doctor Who (2005)"))
        assertEquals(123L, AO3FandomUnion.filterID(html, "A & B"))
        assertNull(AO3FandomUnion.filterID(html, "Doctor Who"))
    }

    @Test fun unionClauseReachesSearchURLAlongsideExistingFilters() {
        val url = AO3SearchUrlBuilder().buildSearchUrl(AO3SearchFilters(
            query = "fluff ${AO3FandomUnion.queryClause(listOf(27785, 99117))}",
            excludedCategories = setOf(AO3Category.OTHER)
        )).toHttpUrl()
        assertTrue(url.queryParameter("work_search[query]")!!.contains("filter_ids:(27785 OR 99117)"))
        assertTrue(url.queryParameter("work_search[query]")!!.startsWith("fluff "))
    }
}
