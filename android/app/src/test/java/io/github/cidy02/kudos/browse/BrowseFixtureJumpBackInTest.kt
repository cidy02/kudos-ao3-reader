package io.github.cidy02.kudos.browse

import io.github.cidy02.kudos.network.ao3.browse.AO3BrowseParser
import io.github.cidy02.kudos.network.ao3.browse.AO3Fandom
import java.io.File
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The demo serves one fandom list (`ao3_media_fandoms.html`) for every category.
 * iOS Jump Back In for the demo library is the three read fandoms on that list.
 */
class BrowseFixtureJumpBackInTest {
    @Test
    fun fixtureListsRankTheThreeIosCards() {
        val parser = AO3BrowseParser()
        val categories = parser.parseMediaCategories(html("ao3_media"))
        val fandoms = parser.parseFandomList(html("ao3_media_fandoms"))
        val inputs = categories.map { category ->
            CategoryStatsInput(id = category.name, fandoms = fandoms, hasFullList = true)
        }
        val now = Instant.parse("2026-10-03T12:00:00Z")
        val works = listOf(
            snap(
                listOf("Doctor Who (2005)", "Doctor Who"),
                added = now.minusSeconds(0),
                read = now
            ),
            snap(
                listOf("Avatar: The Last Airbender", "The Legend of Korra"),
                added = now.minusSeconds(3 * 86_400),
                read = now.minusSeconds(7 * 3_600)
            ),
            snap(
                listOf("僕のヒーローアカデミア | Boku no Hero Academia | My Hero Academia"),
                added = now.minusSeconds(9 * 86_400),
                read = now.minusSeconds(21 * 3_600)
            ),
            snap(
                listOf("Star Wars - All Media Types"),
                added = now.minusSeconds(12 * 86_400),
                read = now.minusSeconds(28 * 3_600)
            ),
            snap(
                listOf("Sherlock (TV)"),
                added = now.minusSeconds(18 * 86_400),
                read = null,
                finished = true
            ),
            snap(
                listOf("Supernatural"),
                added = now.minusSeconds(30 * 86_400),
                read = null,
                finished = false
            )
        )

        val picks = CategoryStatsCalculator.rankJumpBackIn(inputs, works)

        assertEquals(
            listOf("Doctor Who (2005)", "Doctor Who", "Sherlock (TV)"),
            picks.map { it.fandom }
        )
        assertEquals(listOf("Anime & Manga", "Anime & Manga", "Anime & Manga"), picks.map { it.categoryId })
        assertEquals(listOf(61_902, 82_114, 131_006), picks.map { it.workCount })
        assertEquals(5, fandoms.size)
        assertEquals(
            listOf("Doctor Who", "Doctor Who (2005)", "Good Omens (TV)", "Sherlock (TV)", "Supernatural"),
            fandoms.map(AO3Fandom::name)
        )
    }

    private fun snap(
        fandoms: List<String>,
        added: Instant,
        read: Instant?,
        finished: Boolean = false
    ): LibraryWorkSnapshot = LibraryWorkSnapshot(
        fandomsLower = fandoms.map { it.lowercase(java.util.Locale.US) },
        fandomsDisplay = fandoms,
        hasBeenRead = finished || read != null,
        dateAdded = added,
        lastReadDate = read
    )

    private fun html(name: String): String {
        val candidates = listOf(
            File("src/debug/assets/fixtures/$name.html"),
            File("app/src/debug/assets/fixtures/$name.html"),
            File("android/app/src/debug/assets/fixtures/$name.html"),
            File("../../KudosTests/Fixtures/$name.html"),
            File("../KudosTests/Fixtures/$name.html")
        )
        val file = candidates.firstOrNull { it.isFile }
            ?: error("Missing $name.html in ${candidates.joinToString { it.path }}")
        return file.readText()
    }
}
