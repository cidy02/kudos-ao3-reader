package io.github.cidy02.kudos.network.ao3.search

import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins Browse's endpoint. Browse asks AO3 for a tag's own works list; the Search tab
 * asks `/works/search`. Both are the same `WorkSearchForm` server-side, which is why
 * one query-item builder serves both — every parameter below was verified live on
 * `/tags/Naruto (Anime *a* Manga)/works` on 2026-08-06 and measurably changed the
 * result count there.
 */
class AO3FandomWorksUrlTest {
    private val builder = AO3SearchUrlBuilder()

    @Test
    fun aFandomBecomesAO3sOwnTagPath() {
        // `&` is written `*a*` in an AO3 tag path, not percent-encoded — AO3's own
        // convention, and the reason a naive URL builder 404s here.
        val url = builder.buildFandomWorksUrl("Naruto (Anime & Manga)", AO3SearchFilters())!!
        assertTrue(
            url,
            url.startsWith("https://archiveofourown.org/tags/Naruto%20(Anime%20*a*%20Manga)/works?")
        )
    }

    @Test
    fun everyCharacterAO3EscapesIsEscaped() {
        assertEquals("a*s*b", builder.tagPathSegment("a/b"))
        assertEquals("a*a*b", builder.tagPathSegment("a&b"))
        assertEquals("a*d*b", builder.tagPathSegment("a.b"))
        assertEquals("a*q*b", builder.tagPathSegment("a?b"))
        assertEquals("a*h*b", builder.tagPathSegment("a#b"))
        assertNull(builder.tagPathSegment("   "))
    }

    @Test
    fun browseAndSearchEmitIdenticalFilterParameters() {
        // One builder, two paths. If these ever diverge, the two screens silently
        // answer different questions about the same fandom.
        val filters = AO3SearchFilters(
            query = "found family",
            rating = AO3Rating.EXPLICIT,
            includeNotRated = false,
            warnings = setOf(AO3Warning.VIOLENCE),
            excludedFandoms = "Bleach",
            wordsFrom = "1000",
            updated = AO3Updated.WEEK,
            language = AO3Language.ENGLISH,
            sort = AO3SearchSort.KUDOS
        )
        val browse = builder.buildFandomWorksUrl("Naruto (Anime & Manga)", filters, page = 3)!!.toHttpUrl()
        val search = builder.buildSearchUrl(filters, page = 3).toHttpUrl()
        val names = (browse.queryParameterNames + search.queryParameterNames).toSet()
        for (name in names) {
            assertEquals(name, search.queryParameterValues(name), browse.queryParameterValues(name))
        }
    }

    @Test
    fun browseSendsTheFiltersTheTagPageHonours() {
        val filters = AO3SearchFilters(
            characters = "Sasuke Uchiha",
            completion = AO3Completion.COMPLETE,
            excludedAdditionalTags = "Time Travel",
            sort = AO3SearchSort.DATE_UPDATED
        )
        val url = builder.buildFandomWorksUrl("Naruto (Anime & Manga)", filters)!!.toHttpUrl()
        assertEquals("Sasuke Uchiha", url.queryParameter("work_search[character_names]"))
        assertEquals("T", url.queryParameter("work_search[complete]"))
        assertEquals("Time Travel", url.queryParameter("work_search[excluded_tag_names]"))
        assertEquals("revised_at", url.queryParameter("work_search[sort_column]"))
        assertEquals("1", url.queryParameter("page"))
    }

    @Test
    fun theFandomStaysInTheQueryAsWellAsThePath() {
        // Redundant but never wrong: the path already scopes to this tag, so
        // `fandom_names` re-selects the same works (measured — the count is
        // unchanged). Clearing it would *widen* results if the field ever held more
        // than the fandom the screen was opened for.
        val filters = AO3SearchFilters(fandom = "Naruto (Anime & Manga)")
        val url = builder.buildFandomWorksUrl("Naruto (Anime & Manga)", filters)!!.toHttpUrl()
        assertEquals("Naruto (Anime & Manga)", url.queryParameter("work_search[fandom_names]"))
    }

    @Test
    fun aBlankFandomBuildsNoUrl() {
        assertNull(builder.buildFandomWorksUrl("", AO3SearchFilters()))
        assertNull(builder.buildFandomWorksUrl("   ", AO3SearchFilters()))
    }

    @Test
    fun browseNeverSendsViewAdult() {
        val filters = AO3SearchFilters(rating = AO3Rating.EXPLICIT)
        val url = builder.buildFandomWorksUrl("Naruto", filters)!!.toHttpUrl()
        assertNull(url.queryParameter("view_adult"))
    }
}
