package io.github.cidy02.kudos.network.ao3.search

import org.jsoup.Jsoup
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class AO3SearchParserBasicTest {
    private val parser = AO3SearchParser()

    @Test
    fun parsesSearchBlurbFields() {
        val page = parser.parseSearchPage(parserResourceText("ao3/search_basic.html"), page = 1)
        val work = page.works.first()

        assertEquals(12345L, work.id)
        assertEquals("A Test Work", work.title)
        assertEquals(listOf("alice"), work.authors)
        assertEquals(listOf("Naruto"), work.fandoms)
        assertEquals("Teen And Up Audiences", work.rating)
        assertEquals(listOf("No Archive Warnings Apply"), work.warnings)
        assertEquals(listOf("Gen"), work.categories)
        assertEquals(true, work.isComplete)
        assertEquals("25 Dec 2024", work.updatedDate)
        assertEquals(listOf("Naruto/Hinata"), work.relationships)
        assertEquals(listOf("Hinata Hyuuga"), work.characters)
        assertEquals(listOf("Fluff", "Angst", "Uncategorized"), work.freeforms)
        assertEquals("A short summary.", work.summary)
        assertEquals("English", work.language)
        assertEquals(12345, work.wordCount)
        assertEquals("5/10", work.chapters)
        assertEquals(7, work.comments)
        assertEquals(890, work.kudos)
        assertEquals(12, work.bookmarks)
        assertEquals(10111, work.hits)
    }
}

class AO3SearchParserNoResultsTest {
    @Test
    fun noResultsPageDoesNotCrash() {
        val page = AO3SearchParser().parseSearchPage(parserResourceText("ao3/search_no_results.html"), page = 2)

        assertTrue(page.works.isEmpty())
        assertEquals(2, page.currentPage)
        assertEquals(2, page.totalPages)
    }
}

class AO3SearchParserSeriesTest {
    @Test
    fun parsesSeriesMetadata() {
        val work = AO3SearchParser()
            .parseSearchPage(parserResourceText("ao3/search_series.html"), page = 1)
            .works
            .first()

        assertEquals("My Series", work.seriesTitle)
        assertEquals(2, work.seriesPosition)
        assertEquals("https://archiveofourown.org/series/777", work.seriesUrl)
        assertEquals(false, work.isComplete)
    }
}

class AO3SearchParserLockedWorkTest {
    @Test
    fun detectsRestrictedWorkMarker() {
        val work = AO3SearchParser()
            .parseSearchPage(parserResourceText("ao3/search_locked.html"), page = 1)
            .works
            .first()

        assertEquals(333L, work.id)
        assertTrue(work.isRestricted)
        assertEquals("Visible locked-work summary.", work.summary)
    }
}

class AO3SearchParserUnicodeTest {
    @Test
    fun preservesUnicodeAndDecodesEntities() {
        val work = AO3SearchParser()
            .parseSearchPage(parserResourceText("ao3/search_unicode.html"), page = 1)
            .works
            .first()

        assertEquals("Café & Moonlight", work.title)
        assertEquals(listOf("魔法の物語"), work.fandoms)
        assertEquals("Tom & Jerry meet São Paulo.", work.summary)
        assertEquals(listOf("naïve magic", "星"), work.freeforms)
    }
}

class AO3SearchParserOverloadTest {
    @Test
    fun overloadPageThrowsTypedParserError() {
        try {
            AO3SearchParser().parseSearchPage(parserResourceText("ao3/search_overload.html"), page = 1)
            fail("Expected overload parser error.")
        } catch (error: AO3SearchParseException.Overloaded) {
            assertNotNull(error.message)
        }
    }
}

class AO3WorkSummaryParserTest {
    @Test
    fun malformedBlurbWithoutWorkIdThrowsClearError() {
        val element = Jsoup.parse("<li class=\"work blurb\"><h4 class=\"heading\">No id</h4></li>")
            .selectFirst("li.work.blurb")!!

        try {
            AO3SearchParser().parseWorkSummary(element)
            fail("Expected missing structure parser error.")
        } catch (error: AO3SearchParseException.MissingRequiredStructure) {
            assertTrue(error.message!!.contains("work id"))
        }
    }

    @Test
    fun workIdFallsBackToTitleLink() {
        val element = Jsoup.parse(
            """
            <li id="bookmark_99" class="bookmark blurb group">
              <h4 class="heading"><a href="/works/98765">Bookmarked Work</a></h4>
            </li>
            """.trimIndent()
        ).selectFirst("li")!!

        val work = AO3SearchParser().parseWorkSummary(element)

        assertEquals(98765L, work.id)
        assertEquals("Bookmarked Work", work.title)
        assertFalse(work.isRestricted)
    }
}

private fun parserResourceText(path: String): String {
    val resource = Thread.currentThread().contextClassLoader?.getResource(path)
        ?: error("Missing test resource: $path")
    return resource.readText()
}
