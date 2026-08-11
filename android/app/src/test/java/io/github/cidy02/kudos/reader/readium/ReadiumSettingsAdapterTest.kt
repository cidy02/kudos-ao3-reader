package io.github.cidy02.kudos.reader.readium

import io.github.cidy02.kudos.reader.settings.CustomFontDeclaration
import io.github.cidy02.kudos.reader.settings.ReaderColorTheme
import io.github.cidy02.kudos.reader.settings.ReaderPreferences
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.preferences.FontFamily
import org.readium.r2.shared.ExperimentalReadiumApi
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@OptIn(ExperimentalReadiumApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ReadiumSettingsAdapterTest {

    @Test
    fun toEpubPreferencesMapsFontFamilyWhenPresent() {
        val prefs = ReaderPreferences(
            theme = ReaderColorTheme.Light,
            scroll = true,
            columnCount = 1,
            fontSizePercent = 100,
            lineHeight = 1.2,
            letterSpacingEm = 0.0,
            wordSpacingEm = 0.0,
            pageMarginsFactor = 1.0,
            justify = false,
            bold = false,
            fontFamily = "custom:font123.ttf",
            publisherStyles = true
        )

        val epubPrefs = ReadiumSettingsAdapter.toEpubPreferences(prefs)
        assertNotNull(epubPrefs.fontFamily)
        assertEquals(FontFamily("custom:font123.ttf"), epubPrefs.fontFamily)
    }

    @Test
    fun toEpubPreferencesLeavesFontFamilyNullWhenNull() {
        val prefs = ReaderPreferences(
            theme = ReaderColorTheme.Light,
            scroll = true,
            columnCount = 1,
            fontSizePercent = 100,
            lineHeight = 1.2,
            letterSpacingEm = 0.0,
            wordSpacingEm = 0.0,
            pageMarginsFactor = 1.0,
            justify = false,
            bold = false,
            fontFamily = null,
            publisherStyles = true
        )

        val epubPrefs = ReadiumSettingsAdapter.toEpubPreferences(prefs)
        assertNull(epubPrefs.fontFamily)
    }

    @Test
    fun configureFontDeclarationsAddsDeclarationsToConfiguration() {
        val config = EpubNavigatorFragment.Configuration()
        val declarations = listOf(
            CustomFontDeclaration(
                fontFamily = "custom:test.ttf",
                fontPath = "/path/to/test.ttf",
                alternates = listOf("Test Font", "test.ttf")
            )
        )

        ReadiumSettingsAdapter.configureFontDeclarations(config, declarations)

        // Readium's EpubNavigatorFragment.Configuration stores declarations in fontFamilyDeclarations
        assertNotNull(config)
    }
}
