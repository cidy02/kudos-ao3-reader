package io.github.cidy02.kudos.core.model

import org.junit.Assert.assertEquals
import org.junit.Test

class SettingsDefaultsTest {
    @Test
    fun defaultsMatchSettingsContract() {
        val defaults = KudosSettings.Defaults

        assertEquals("system", defaults.reader.readerFontId)
        assertEquals(ReaderMode.Scroll, defaults.reader.readerMode)
        assertEquals(false, defaults.reader.readerTwoPage)
        assertEquals(false, defaults.reader.readerCustomize)
        assertEquals(false, defaults.reader.readerBoldText)
        assertEquals(18.0, defaults.reader.readerFontPt, 0.0)
        assertEquals(1.65, defaults.reader.readerLineHeight, 0.0)
        assertEquals(0.0, defaults.reader.readerLetterSpacing, 0.0)
        assertEquals(0.0, defaults.reader.readerWordSpacing, 0.0)
        assertEquals(28.0, defaults.reader.readerMargin, 0.0)
        assertEquals(false, defaults.reader.readerJustify)
        assertEquals(true, defaults.app.confirmBeforeDelete)
        assertEquals(true, defaults.privacy.hideMatureContent)
        assertEquals(MatureContentMode.Obscure, defaults.privacy.matureContentMode)
        assertEquals(false, defaults.privacy.requireBiometricToReveal)
        assertEquals(AppThemeSetting.Light, defaults.app.appTheme)
        assertEquals(ReaderThemeSetting.Light, defaults.reader.readerTheme)
        assertEquals(true, defaults.reader.matchAppReaderTheme)
        assertEquals("#990000", defaults.app.accentColorHex)
    }

    @Test
    fun enumMappingsUseContractStorageValues() {
        assertEquals(ReaderMode.Scroll, ReaderMode.fromStorage("scroll"))
        assertEquals(ReaderMode.Paged, ReaderMode.fromStorage("paged"))
        assertEquals(ReaderMode.Scroll, ReaderMode.fromStorage("unknown"))

        assertEquals(AppThemeSetting.Light, AppThemeSetting.fromStorage("light"))
        assertEquals(AppThemeSetting.Sepia, AppThemeSetting.fromStorage("sepia"))
        assertEquals(AppThemeSetting.Dark, AppThemeSetting.fromStorage("dark"))
        assertEquals(AppThemeSetting.System, AppThemeSetting.fromStorage("system"))
        assertEquals(AppThemeSetting.Light, AppThemeSetting.fromStorage(null))

        assertEquals(ReaderThemeSetting.Light, ReaderThemeSetting.fromStorage("light"))
        assertEquals(ReaderThemeSetting.Sepia, ReaderThemeSetting.fromStorage("sepia"))
        assertEquals(ReaderThemeSetting.Dark, ReaderThemeSetting.fromStorage("dark"))
        assertEquals(ReaderThemeSetting.Light, ReaderThemeSetting.fromStorage("system"))

        assertEquals(MatureContentMode.Obscure, MatureContentMode.fromStorage("obscure"))
        assertEquals(MatureContentMode.Hide, MatureContentMode.fromStorage("hide"))
        assertEquals(MatureContentMode.Obscure, MatureContentMode.fromStorage("show"))
    }

    @Test
    fun backupSettingsRoundTripsContractFieldNames() {
        val settings = KudosSettings.Defaults.copy(
            reader = KudosSettings.Defaults.reader.copy(
                readerMode = ReaderMode.Paged,
                readerTheme = ReaderThemeSetting.Sepia
            ),
            privacy = KudosSettings.Defaults.privacy.copy(
                matureContentMode = MatureContentMode.Hide
            )
        )

        val backup = BackupSettings.fromSettings(settings)

        assertEquals("system", backup.readerFontID)
        assertEquals("paged", backup.readerMode)
        assertEquals("sepia", backup.readerTheme)
        assertEquals("hide", backup.matureContentMode)
        assertEquals(settings, backup.toSettings())
    }
}
