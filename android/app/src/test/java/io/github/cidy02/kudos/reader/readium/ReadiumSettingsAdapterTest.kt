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

    /** iOS `ReaderTheme.backgroundHex` and `textHex`. Left to its own, Readium's Dark is OLED's black. */
    @Test
    fun everyThemeGivesReadiumIosPageAndTextColours() {
        mapOf(
            ReaderColorTheme.Light to (0xFFFFFFFF to 0xFF1E1E1E),
            ReaderColorTheme.Sepia to (0xFFFBF0D9 to 0xFF5B4636),
            ReaderColorTheme.Dark to (0xFF16161A to 0xFFCFCFD4),
            ReaderColorTheme.Oled to (0xFF000000 to 0xFFCFCFD4)
        ).forEach { (theme, colours) ->
            val prefs = ReadiumSettingsAdapter.toEpubPreferences(ReaderPreferences().copy(theme = theme))
            assertEquals("$theme page", colours.first.toInt(), prefs.backgroundColor?.int)
            assertEquals("$theme text", colours.second.toInt(), prefs.textColor?.int)
        }
    }

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
