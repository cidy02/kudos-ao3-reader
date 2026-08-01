package io.github.cidy02.kudos.reader.settings

import io.github.cidy02.kudos.core.model.AppSettings
import io.github.cidy02.kudos.core.model.AppThemeSetting
import io.github.cidy02.kudos.core.model.ReaderMode
import io.github.cidy02.kudos.core.model.ReaderSettings
import io.github.cidy02.kudos.core.model.ReaderThemeSetting
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReaderSettingsMapperTest {
    private val mapper = ReaderSettingsMapper()

    @Test
    fun defaultsMapToScrollLightFullSize() {
        val prefs = mapper.map(ReaderSettings(), AppSettings())
        assertEquals(ReaderColorTheme.Light, prefs.theme)
        assertTrue(prefs.scroll)
        assertEquals(1, prefs.columnCount)
        assertEquals(100, prefs.fontSizePercent)
        assertTrue(prefs.publisherStyles) // customize defaults off -> keep publisher styles
        assertFalse(prefs.justify)
    }

    @Test
    fun fontPointsMapToPercentAndClamp() {
        assertEquals(150, mapper.map(ReaderSettings(readerFontPt = 27.0), AppSettings()).fontSizePercent)
        assertEquals(50, mapper.map(ReaderSettings(readerFontPt = 4.0), AppSettings()).fontSizePercent)
        assertEquals(250, mapper.map(ReaderSettings(readerFontPt = 200.0), AppSettings()).fontSizePercent)
    }

    @Test
    fun fontPercentRoundTripsToPointsViaBase18() {
        assertEquals(18.0, ReaderSettingsMapper.fontPtFromPercent(100), 0.0)
        assertEquals(27.0, ReaderSettingsMapper.fontPtFromPercent(150), 0.0)
        assertEquals(9.0, ReaderSettingsMapper.fontPtFromPercent(50), 0.0)
        assertEquals(45.0, ReaderSettingsMapper.fontPtFromPercent(250), 0.0)
        // Out-of-range percent is clamped before conversion.
        assertEquals(9.0, ReaderSettingsMapper.fontPtFromPercent(1), 0.0)
        assertEquals(45.0, ReaderSettingsMapper.fontPtFromPercent(999), 0.0)
        // Round-trip: pt → % → pt for a clean multiple of the 18pt base.
        val percent = mapper.map(ReaderSettings(readerFontPt = 27.0), AppSettings()).fontSizePercent
        assertEquals(27.0, ReaderSettingsMapper.fontPtFromPercent(percent), 0.0)
    }

    @Test
    fun colorThemeMapsToReaderThemeSetting() {
        assertEquals(
            ReaderThemeSetting.Light,
            ReaderSettingsMapper.toReaderThemeSetting(ReaderColorTheme.Light)
        )
        assertEquals(
            ReaderThemeSetting.Sepia,
            ReaderSettingsMapper.toReaderThemeSetting(ReaderColorTheme.Sepia)
        )
        assertEquals(
            ReaderThemeSetting.Dark,
            ReaderSettingsMapper.toReaderThemeSetting(ReaderColorTheme.Dark)
        )
    }

    @Test
    fun pagedTwoPageMapsToTwoColumns() {
        val prefs = mapper.map(
            ReaderSettings(readerMode = ReaderMode.Paged, readerTwoPage = true),
            AppSettings()
        )
        assertFalse(prefs.scroll)
        assertEquals(2, prefs.columnCount)
    }

    @Test
    fun customizeEnablesUserOverrides() {
        val prefs = mapper.map(ReaderSettings(readerCustomize = true, readerJustify = true), AppSettings())
        assertFalse(prefs.publisherStyles)
        assertTrue(prefs.justify)
    }
}

class ReaderThemeMappingTest {
    private val mapper = ReaderSettingsMapper()

    @Test
    fun matchAppThemeFollowsAppTheme() {
        fun themeFor(app: AppThemeSetting) =
            mapper.resolveTheme(ReaderSettings(matchAppReaderTheme = true), AppSettings(appTheme = app))

        assertEquals(ReaderColorTheme.Dark, themeFor(AppThemeSetting.Dark))
        assertEquals(ReaderColorTheme.Sepia, themeFor(AppThemeSetting.Sepia))
        assertEquals(ReaderColorTheme.Light, themeFor(AppThemeSetting.Light))
        // System has no EPUB equivalent -> documented Light fallback.
        assertEquals(ReaderColorTheme.Light, themeFor(AppThemeSetting.System))
    }

    @Test
    fun explicitReaderThemeIgnoresAppThemeWhenNotMatching() {
        val prefs = mapper.resolveTheme(
            ReaderSettings(matchAppReaderTheme = false, readerTheme = ReaderThemeSetting.Sepia),
            AppSettings(appTheme = AppThemeSetting.Dark)
        )
        assertEquals(ReaderColorTheme.Sepia, prefs)
    }

    @Test
    fun lightDarkSepiaAllSupported() {
        val mapped = ReaderThemeSetting.entries.map { setting ->
            mapper.resolveTheme(
                ReaderSettings(matchAppReaderTheme = false, readerTheme = setting),
                AppSettings()
            )
        }
        assertTrue(mapped.containsAll(listOf(ReaderColorTheme.Light, ReaderColorTheme.Dark, ReaderColorTheme.Sepia)))
    }
}
