package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.core.model.AppSettings
import io.github.cidy02.kudos.core.model.AppThemeSetting
import io.github.cidy02.kudos.core.model.ReaderSettings
import io.github.cidy02.kudos.core.model.ReaderThemeSetting
import io.github.cidy02.kudos.reader.settings.ReaderColorTheme
import io.github.cidy02.kudos.reader.settings.ReaderSettingsMapper
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Fix 3: OLED must survive backup normalize and map to an OLED reader theme.
 * The validator used to allowlist only light/sepia/dark(+system for app), so
 * an Android→Android restore of "oled" was rewritten to the default "light".
 */
class BackupOledThemeTest {

    @Test
    fun normalizeSettingsPreservesOledAppAndReaderThemes() {
        val payload = BackupSettingsPayload(
            appTheme = "oled",
            readerTheme = "oled"
        )
        val normalized = BackupValidator.normalizeSettings(payload, availableFontFileNames = emptySet())
        assertEquals("oled", normalized.appTheme)
        assertEquals("oled", normalized.readerTheme)
    }

    @Test
    fun mapperMapsAppOledToReaderOledNotDark() {
        val theme = ReaderSettingsMapper().resolveTheme(
            ReaderSettings(matchAppReaderTheme = true),
            AppSettings(appTheme = AppThemeSetting.Oled)
        )
        assertEquals(ReaderColorTheme.Oled, theme)
    }

    @Test
    fun mapperMapsExplicitReaderOledToOled() {
        val theme = ReaderSettingsMapper().resolveTheme(
            ReaderSettings(
                matchAppReaderTheme = false,
                readerTheme = ReaderThemeSetting.Oled
            ),
            AppSettings(appTheme = AppThemeSetting.Light)
        )
        assertEquals(ReaderColorTheme.Oled, theme)
    }
}
