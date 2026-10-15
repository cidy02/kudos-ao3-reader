package io.github.cidy02.kudos.network.ao3.preferences

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AO3PreferencesParserTest {
    private val parser = AO3PreferencesParser()

    @Test
    fun parsesTogglesSelectsTextAndWebLinks() {
        val snapshot = parser.parse(fixture("ao3/preferences/ios_preferences.html"))
        assertEquals("https://archiveofourown.org/users/ExampleUser/preference", snapshot.actionUrl)
        assertEquals("put", snapshot.httpMethodOverride)
        assertEquals("csrf-token-abc123==", snapshot.csrfToken)
        val toggles = snapshot.sections.flatMap { it.toggles }
        assertTrue(toggles.first { it.name == "preference[disable_share_links]" }.checked)
        assertTrue(toggles.first { it.name == "preference[disable_share_links]" }.label.contains("share buttons"))
        assertEquals(false, toggles.first { it.name == "preference[minimize_search_engines]" }.checked)
        assertTrue(toggles.first { it.name == "preference[adult]" }.checked)
        assertTrue(toggles.first { it.name == "preference[kudos_emails_off]" }.checked)
        assertEquals(listOf("Privacy", "Display", "Comments"), snapshot.sections.map { it.title })
        assertEquals("42", snapshot.selects.first { it.name == "preference[skin_id]" }.selectedValue)
        assertTrue(snapshot.selects.first { it.name == "preference[skin_id]" }.options.contains("42" to "Reversi"))
        assertEquals("America/New_York", snapshot.selects.first { it.name == "preference[time_zone]" }.selectedValue)
        assertEquals("TITLE - AUTHOR", snapshot.textFields.first { it.name == "preference[work_title_format]" }.value)
        assertTrue(snapshot.hiddenFields.contains("preference[id]" to "99"))
        assertTrue(snapshot.webLinks.contains(AO3PreferenceWebLink("Change Password",
            "https://archiveofourown.org/users/ExampleUser/change_password")))
        assertEquals(listOf("profile/edit", "pseuds", "blocked", "muted", "change_username", "change_password", "change_email"),
            snapshot.webLinks.map { it.url.substringAfter("/users/ExampleUser/") })
        assertTrue(snapshot.webLinks.none { it.url.contains("/preferences") })
    }

    @Test
    fun webLinksExcludePreferencesAndHelpAndKeepOnlyOneOfEachServedAddress() {
        val doc = org.jsoup.Jsoup.parse(fixture("ao3/preferences/ios_preferences.html"))
        doc.selectFirst("ul.navigation")!!.append("""
            <li><a href="/users/ExampleUser/preferences">Preferences</a></li>
            <li><a href="/help/preferences_privacy">Help</a></li>
            <li><a href="/users/ExampleUser/change_password">Duplicate</a></li>
            <li><a href="">Empty address</a></li>
            """)
        val links = parser.parse(doc.outerHtml()).webLinks
        assertEquals(7, links.size)
        assertEquals("Change Password", links.first { it.url.endsWith("/change_password") }.title)
    }

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

    /** Brief 3cj: where AO3 puts its "?" links, and what each is called. */
    @Test
    fun aSectionAndAFieldCarryTheirOwnHelpAndTheTitleLosesItsGlyph() {
        val snapshot = parser.parse(fixture("ao3/preferences/ao3_preferences.html"))
        val privacy = snapshot.sections.first { it.title == "Privacy" }
        assertEquals(AO3PreferenceHelpRef("Privacy Preferences", "https://archiveofourown.org/help/preferences_privacy"),
            privacy.help)
        assertEquals(AO3PreferenceHelpRef("Display Preferences", "https://archiveofourown.org/help/preferences_display"),
            snapshot.sections.first { it.title == "Display" }.help)
        // A heading without a link has none: a field's link is not lent to its section.
        assertNull(snapshot.sections.first { it.title == "Comments" }.help)
        assertEquals("Search engines",
            privacy.toggles.first { it.name == "preference[minimize_search_engines]" }.help?.title)
        // AO3 puts a text field's "?" beside its label, in the `dt`.
        assertEquals(
            AO3PreferenceHelpRef("Work Title Format", "https://archiveofourown.org/help/preferences_work_title_format"),
            snapshot.textFields.first { it.name == "preference[work_title_format]" }.help)
        assertNull(snapshot.selects.first { it.name == "preference[skin_id]" }.help)
    }

    /** AO3's labels point at a control's id. Asked by name, these rows showed "preference[skin_id]". */
    @Test
    fun aSelectAndATextFieldAreCalledWhatAO3CallsThem() {
        val snapshot = parser.parse(fixture("ao3/preferences/ao3_preferences.html"))
        assertEquals(listOf("Your site skin", "Your time zone"), snapshot.selects.map { it.label })
        assertEquals("Browser page title format",
            snapshot.textFields.first { it.name == "preference[work_title_format]" }.label)
        assertEquals("Hide my work from search engines when possible.",
            snapshot.sections.flatMap { it.toggles }.first { it.name == "preference[minimize_search_engines]" }.label)
    }

    @Test
    fun aHelpPageIsReadAsItsTopicsWithTheNoteUnderThem() {
        val content = parser.parseHelpPage(asset("ao3_help_preferences_privacy"), "https://archiveofourown.org/help/preferences_privacy")
        assertEquals("Privacy Preferences", content.title)
        assertEquals(listOf("Hide my work from search engines when possible.", "Hide the share buttons on my work.",
            "Allow others to invite me to be a co-creator."), content.entries.map { it.heading })
        assertEquals("This preference allows you to disable the one-click share buttons.\n\n" +
            "Please note that once you have posted a work online, it is always possible for a reader to copy and paste a link.",
            content.entries[1].body)
        assertEquals("For more on your preferences, check out our Preferences FAQ.", content.footer)
        assertEquals("https://archiveofourown.org/help/preferences_privacy", content.sourceUrl)
    }

    @Test
    fun aHelpPageWithoutTheListIsOneTopicAndAnEmptyOneIsNotRead() {
        val plain = parser.parseHelpPage(
            "<html><head><title>Skins Help | Archive of Our Own</title></head><body><div id='main'><p>One.</p><p>Two.</p></div></body></html>",
            "https://archiveofourown.org/help/skins")
        assertEquals("Skins Help", plain.title)
        assertEquals(listOf(AO3PreferenceHelpEntry("Skins Help", "One.\n\nTwo.")), plain.entries)
        assertNull(plain.footer)
        try {
            parser.parseHelpPage("<html><body><div id='main'></div></body></html>", "https://archiveofourown.org/help/x")
            org.junit.Assert.fail("an empty page is not help")
        } catch (_: AO3PreferencesParseException) { }
    }

    private fun asset(name: String): String = listOf("src/debug/assets", "app/src/debug/assets", "android/app/src/debug/assets")
        .map { java.io.File(it, "fixtures/$name.html") }.first { it.exists() }.readText()

    private fun fixture(path: String): String {
        val stream = requireNotNull(javaClass.classLoader.getResourceAsStream(path)) {
            "Missing test fixture: $path"
        }
        return stream.bufferedReader().use { it.readText() }
    }
}
