package io.github.cidy02.kudos.network.ao3.preferences

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AO3PreferencesParserTest {
    private val parser = AO3PreferencesParser()

    @Test
    fun capturesHelpUrlNearToggleLabelFromFixture() {
        val snapshot = parser.parse(fixture("ao3/preferences/ao3_preferences.html"))
        val toggle = snapshot.sections
            .flatMap { it.toggles }
            .first { it.name == "preference[minimize_search_engines]" }

        assertEquals(
            "https://archiveofourown.org/help/preferences_privacy",
            toggle.helpUrl
        )
    }

    @Test
    fun toggleWithoutNearbyHelpLinkYieldsNullHelpUrl() {
        val snapshot = parser.parse(fixture("ao3/preferences/ao3_preferences.html"))
        val toggle = snapshot.sections
            .flatMap { it.toggles }
            .first { it.name == "preference[disable_share_links]" }

        assertNull(toggle.helpUrl)
    }

    @Test
    fun parsesSectionsAndCsrfFromFixture() {
        val snapshot = parser.parse(fixture("ao3/preferences/ao3_preferences.html"))
        assertEquals("csrf-token-abc123==", snapshot.csrfToken)
        // Section heading text may include the help "?" glyph when AO3 puts the
        // help anchor inside h4.heading; match by prefix rather than exact title.
        assertTrue(
            snapshot.sections.any {
                it.title.trim().startsWith("Privacy", ignoreCase = true)
            }
        )
        assertTrue(snapshot.sections.flatMap { it.toggles }.isNotEmpty())
        assertNotNull(snapshot.actionUrl)
    }

    private fun fixture(path: String): String {
        val stream = requireNotNull(javaClass.classLoader.getResourceAsStream(path)) {
            "Missing test fixture: $path"
        }
        return stream.bufferedReader().use { it.readText() }
    }
}
