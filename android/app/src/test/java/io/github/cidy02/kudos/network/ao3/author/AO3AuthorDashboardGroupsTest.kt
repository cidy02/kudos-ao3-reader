package io.github.cidy02.kudos.network.ao3.author

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `AO3DashboardTests.missingGroupsAreEmptyButMalformedGroupDoesNotEraseItsSiblings` (A59). */
class AO3AuthorDashboardGroupsTest {
    private fun fixture(name: String) = listOf("src/debug/assets", "app/src/debug/assets", "android/app/src/debug/assets")
        .map { File("$it/fixtures/$name.html") }.first(File::isFile).readText()

    @Test fun missingGroupsAreEmptyButMalformedGroupDoesNotEraseItsSiblings() {
        val route = AO3AuthorRoute("Avery_Archive")
        val empty = AO3AuthorParser().parseDashboard(fixture("ao3_author_dashboard"), route)
        assertEquals(emptyList<Any>(), empty.recentWorks)
        assertEquals(emptyList<Any>(), empty.recentSeries)
        assertEquals(emptyList<Any>(), empty.recentBookmarks)

        val html = fixture("ao3_author_dashboard_demo")
        val whole = AO3AuthorParser().parseDashboard(html, route)
        assertTrue(whole.recentSeries!!.isNotEmpty())
        val partial = AO3AuthorParser().parseDashboard(html.replace(
            """<div id="user-series" class="series listbox group">""",
            """<div id="user-series" class="series listbox group"><li class='series blurb'>Unrecognized series</li>"""
        ), route)
        assertNull(partial.recentSeries)
        assertTrue(partial.recentWorks!!.isNotEmpty())
        assertTrue(partial.recentBookmarks!!.isNotEmpty())
    }
}
