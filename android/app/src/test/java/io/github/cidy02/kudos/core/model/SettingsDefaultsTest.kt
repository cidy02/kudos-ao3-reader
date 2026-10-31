package io.github.cidy02.kudos.core.model

import io.github.cidy02.kudos.backup.BackupJson
import io.github.cidy02.kudos.backup.BackupSettingsPayload
import io.github.cidy02.kudos.backup.BackupValidator
import io.github.cidy02.kudos.backup.toBackupSettingsPayload
import kotlinx.serialization.encodeToString
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
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
        assertEquals("#821019", defaults.app.accentColorHex)
        assertNull(defaults.app.storedAccentColorHex)
        assertNull(defaults.app.chosenAccentColorHex)
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
        assertNull(backup.accentColorHex)
        assertEquals(settings, backup.toSettings())
    }

    @Test
    fun backupCaptureOmitsUnchosenAccentAndPreservesChosenAccent() {
        val unchosenPayload = BackupSettings.fromSettings(KudosSettings.Defaults).toBackupSettingsPayload()
        assertNull(unchosenPayload.accentColorHex)
        val unchosenJson = BackupJson.encodeToString(unchosenPayload)
        assertFalse(unchosenJson.contains("accentColorHex"))

        val chosen = KudosSettings.Defaults.copy(
            app = KudosSettings.Defaults.app.copy(
                accentColorHex = "#2468AC",
                storedAccentColorHex = "#2468AC"
            )
        )
        val chosenPayload = BackupSettings.fromSettings(chosen).toBackupSettingsPayload()
        assertEquals("#2468AC", chosenPayload.accentColorHex)
        val chosenJson = BackupJson.encodeToString(chosenPayload)
        assertTrue(chosenJson.contains("\"accentColorHex\":\"#2468AC\"") || chosenJson.contains("\"accentColorHex\": \"#2468AC\""))

        // Legacy #990000 maps to #821019 in memory while preserving raw storedAccentColorHex for restore skip.
        val legacySettings = BackupSettings(accentColorHex = "#990000").toSettings()
        assertEquals("#821019", legacySettings.app.accentColorHex)
        assertEquals("#990000", legacySettings.app.storedAccentColorHex)

        assertNull(
            BackupValidator.normalizeSettings(
                BackupSettingsPayload(accentColorHex = null),
                availableFontFileNames = emptySet()
            ).accentColorHex
        )
        assertNull(
            BackupValidator.normalizeSettings(
                BackupSettingsPayload(accentColorHex = "not-a-hex"),
                availableFontFileNames = emptySet()
            ).accentColorHex
        )
        assertEquals(
            "#2468AC",
            BackupValidator.normalizeSettings(
                BackupSettingsPayload(accentColorHex = "#2468AC"),
                availableFontFileNames = emptySet()
            ).accentColorHex
        )
    }
}
