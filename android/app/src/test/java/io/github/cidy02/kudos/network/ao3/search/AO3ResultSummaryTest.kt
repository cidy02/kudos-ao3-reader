package io.github.cidy02.kudos.network.ao3.search

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Pins AO3's result-count heading, the source of the results card's total.
 *
 * Every string below was copied from a live page on 2026-08-06 — the exact text
 * content of the heading element, not a tidied version — because the whole risk here
 * is that a tidied fixture hides what the real markup does.
 */
class AO3ResultSummaryTest {
    @Test
    fun aTagListReportsItsTotalTagAndRange() {
        val summary = parseResultSummary("1 - 20 of 142,322 Works in Naruto (Anime & Manga)")!!
        // 142,322, *not* 1 or 20: the total is the number attached to "Works", which
        // is why this anchors on the noun rather than on "the first number".
        assertEquals(142_322, summary.total)
        assertEquals("in Naruto (Anime & Manga)", summary.scope)
        assertEquals("Naruto (Anime & Manga)", summary.subject)
        assertEquals(1..20, summary.range)
    }

    @Test
    fun aUserListReportsItsAuthor() {
        val summary = parseResultSummary("1 - 20 of 535 Works by astolat")!!
        assertEquals(535, summary.total)
        assertEquals("astolat", summary.subject)
        assertEquals(1..20, summary.range)
    }

    @Test
    fun aSearchReportsItsTotalWithNoScopeOrRange() {
        val summary = parseResultSummary("92,495 Found")!!
        assertEquals(92_495, summary.total)
        assertNull(summary.scope)
        assertNull(summary.range)
    }

    @Test
    fun theSearchHelpLinkIsNotMistakenForAScope() {
        // The real heading is `92,495 Found <a class="help symbol question">…</a>`,
        // and its *text* is "92,495 Found  ?". Taking everything after the noun would
        // make the scope "?" and the card would read "92,495 works ?".
        val summary = parseResultSummary("92,495 Found  ?")!!
        assertEquals(92_495, summary.total)
        assertNull(summary.scope)
    }

    @Test
    fun aFilteredTagListSaysWorksFoundIn() {
        // The moment `work_search[query]` is set, AO3 changes the wording from
        // "Works in <tag>" to "Works **found** in <tag>". Browse sends a query for
        // every excluded warning and category, so this is its normal heading — and
        // without handling it the card silently loses its title exactly when a
        // filter is active.
        val summary = parseResultSummary("1 - 20 of 88,698 Works found in Naruto (Anime & Manga)")!!
        assertEquals(88_698, summary.total)
        assertEquals("Naruto (Anime & Manga)", summary.subject)
        assertEquals(1..20, summary.range)
    }

    @Test
    fun headingsWithNoCountAreNotSummaries() {
        // A zero-result search renders only "Search Results" — AO3 omits the count
        // heading entirely, so null is the normal path, not a parse failure.
        assertNull(parseResultSummary("Search Results"))
        assertNull(parseResultSummary("Works List"))
        assertNull(parseResultSummary(""))
    }

    @Test
    fun numbersElsewhereInTheHeadingAreNotReadAsARange() {
        // Only an "<a> - <b> of" sitting immediately before the count can match, so a
        // fandom whose *name* contains a range must not produce one.
        val summary = parseResultSummary("12 Works in 5 - 10 Years Later")!!
        assertEquals(12, summary.total)
        assertNull(summary.range)
        assertEquals("5 - 10 Years Later", summary.subject)
    }

    @Test
    fun aLaterPagesRangeIsReadNotAssumedToStartAtOne() {
        assertEquals(981..1000, parseResultSummary("981 - 1,000 of 142,322 Works in X")!!.range)
    }

    @Test
    fun completingFillsOnlyWhatAO3LeftOut() {
        val bare = parseResultSummary("142,327 Found")!!
        val completed = bare.completing(subject = "Naruto (Anime & Manga)", page = 1, onPageCount = 20)
        assertEquals("Naruto (Anime & Manga)", completed.subject)
        assertEquals(1..20, completed.range)

        // What AO3 actually said always wins.
        val stated = parseResultSummary("41 - 60 of 142,322 Works in Naruto (Anime & Manga)")!!
        val untouched = stated.completing(subject = "Something Else", page = 99, onPageCount = 3)
        assertEquals("Naruto (Anime & Manga)", untouched.subject)
        assertEquals(41..60, untouched.range)
    }

    @Test
    fun aShortLastPageEndsWhereItActuallyEnds() {
        // 3 works came back, so the range is 3 long — this is why the count of works
        // on the page is passed in rather than assuming a full page.
        assertEquals(41..43, parseResultSummary("43 Found")!!.completing(null, page = 3, onPageCount = 3).range)
        // And an empty page derives nothing: zero works is not "1–0".
        assertNull(parseResultSummary("0 Found")!!.completing(null, page = 1, onPageCount = 0).range)
    }
}
