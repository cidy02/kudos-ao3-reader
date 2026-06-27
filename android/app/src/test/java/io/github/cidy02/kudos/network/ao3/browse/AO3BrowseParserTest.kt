package io.github.cidy02.kudos.network.ao3.browse

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

private fun fixture(path: String): String {
    val stream = AO3BrowseParserTest::class.java.classLoader!!.getResourceAsStream(path)
        ?: error("Missing fixture: $path")
    return stream.bufferedReader().use { it.readText() }
}

class AO3BrowseParserTest {
    private val parser = AO3BrowseParser()

    @Test
    fun parsesMediaCategoriesWithFeaturedFandoms() {
        val categories = parser.parseMediaCategories(fixture("ao3/browse/categories.html"))

        assertEquals(2, categories.size)
        val anime = categories.first()
        assertEquals("Anime & Manga", anime.name)
        assertEquals("/media/Anime%20*a*%20Manga/fandoms", anime.fandomsPath)
        assertEquals(listOf("Naruto", "Bleach"), anime.featuredFandoms)
        assertEquals("TV Shows", categories[1].name)
    }

    @Test
    fun parsesFandomListWithCountsAndDedupesFirstSeen() {
        val fandoms = parser.parseFandomList(fixture("ao3/browse/fandom_list.html"))

        // Naruto appears twice in the fixture; first-seen wins, dupes dropped.
        assertEquals(listOf("Naruto", "Bleach", "Example Fandom"), fandoms.map { it.name })
        assertEquals(12345, fandoms.first().workCount)
        assertEquals(42, fandoms[2].workCount)
    }

    @Test
    fun overloadPageThrowsTypedError() {
        try {
            parser.parseMediaCategories(fixture("ao3/browse/overload.html"))
            fail("Expected overload error.")
        } catch (_: AO3BrowseParseException.Overloaded) {
            // expected
        }
    }

    @Test
    fun emptyCategoryThrowsMissingStructure() {
        try {
            parser.parseFandomList(fixture("ao3/browse/empty_category.html"))
            fail("Expected missing-structure error.")
        } catch (error: AO3BrowseParseException.MissingRequiredStructure) {
            assertTrue(error.message!!.isNotBlank())
        }
    }

    @Test
    fun changedMarkupThrowsMissingStructureNotEmptyList() {
        try {
            parser.parseMediaCategories(fixture("ao3/browse/parser_changed.html"))
            fail("Expected missing-structure error for changed markup.")
        } catch (_: AO3BrowseParseException.MissingRequiredStructure) {
            // expected — a parser break must not look like "no categories".
        }
    }
}
