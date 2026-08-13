package io.github.cidy02.kudos.data.preferences

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import io.github.cidy02.kudos.core.model.AppThemeSetting
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.MatureContentMode
import io.github.cidy02.kudos.core.model.ReaderMode
import io.github.cidy02.kudos.core.model.ReaderThemeSetting
import java.io.File
import java.nio.file.Files
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SettingsRepositoryTest {
    private val tempDir = Files.createTempDirectory("kudos-settings-test").toFile()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val repository = SettingsRepository(
        PreferenceDataStoreFactory.create(
            scope = scope,
            produceFile = { File(tempDir, "settings.preferences_pb") }
        )
    )

    @After
    fun tearDown() {
        scope.cancel()
        tempDir.deleteRecursively()
    }

    @Test
    fun snapshotReturnsContractDefaults() = runBlocking {
        assertEquals(KudosSettings.Defaults, repository.snapshot())
    }

    @Test
    fun updatesPersistMappedEnumValues() = runBlocking {
        repository.updateReaderMode(ReaderMode.Paged)
        repository.updateAppTheme(AppThemeSetting.Dark)

        val settings = repository.snapshot()

        assertEquals(ReaderMode.Paged, settings.reader.readerMode)
        assertEquals(AppThemeSetting.Dark, settings.app.appTheme)
    }

    @Test
    fun readerDisplayPrefsPersistAcrossSnapshot() = runBlocking {
        // Mirrors deferred-3a: display sheet font % → pt (150% of 18pt base) + theme.
        repository.updateReaderFontPt(27.0)
        repository.updateReaderTheme(ReaderThemeSetting.Sepia)
        repository.updateMatchAppReaderTheme(false)
        repository.updateReaderCustomize(true)

        val settings = repository.snapshot()

        assertEquals(27.0, settings.reader.readerFontPt, 0.0)
        assertEquals(ReaderThemeSetting.Sepia, settings.reader.readerTheme)
        assertFalse(settings.reader.matchAppReaderTheme)
        assertTrue(settings.reader.readerCustomize)
    }

    @Test
    fun privacyAndAppBooleanUpdatersRoundTrip() = runBlocking {
        repository.updateHideMatureContent(false)
        repository.updateMatureContentMode(MatureContentMode.Hide)
        repository.updateRequireBiometricToReveal(true)
        repository.updateConfirmBeforeDelete(false)
        repository.updateAccentColor("#0B57D0")

        val settings = repository.snapshot()

        assertFalse(settings.privacy.hideMatureContent)
        assertEquals(MatureContentMode.Hide, settings.privacy.matureContentMode)
        assertTrue(settings.privacy.requireBiometricToReveal)
        assertFalse(settings.app.confirmBeforeDelete)
        assertEquals("#0B57D0", settings.app.accentColorHex)
    }

    @Test
    fun readerLayoutUpdatersRoundTrip() = runBlocking {
        repository.updateReaderJustify(true)
        repository.updateReaderMargin(36.0)
        repository.updateReaderLineHeight(1.8)
        repository.updateReaderFontId("system")
        repository.updateReaderBoldText(true)
        repository.updateReaderTwoPage(true)
        repository.updateAppTheme(AppThemeSetting.System)

        val settings = repository.snapshot()

        assertTrue(settings.reader.readerJustify)
        assertEquals(36.0, settings.reader.readerMargin, 0.0)
        assertEquals(1.8, settings.reader.readerLineHeight, 0.0)
        assertEquals("system", settings.reader.readerFontId)
        assertTrue(settings.reader.readerBoldText)
        assertTrue(settings.reader.readerTwoPage)
        assertEquals(AppThemeSetting.System, settings.app.appTheme)
    }

    @Test
    fun resetToDefaultsClearsPreviousUpdates() = runBlocking {
        repository.updateHideMatureContent(false)
        repository.updateReaderJustify(true)
        repository.updateReaderFontPt(22.0)
        repository.resetToDefaults()

        assertEquals(KudosSettings.Defaults, repository.snapshot())
    }

    @Test
    fun testM21_RestoreRetainsLocalFontSelection() = runBlocking {
        repository.updateReaderFontId("local-font-uuid")
        
        val settings = KudosSettings.Defaults.copy(
            reader = KudosSettings.Defaults.reader.copy(
                readerFontId = "attacker-font-uuid"
            )
        )
        repository.replaceAll(settings)
        
        val afterRestore = repository.snapshot()
        assertEquals("local-font-uuid", afterRestore.reader.readerFontId)
    }

    @Test
    fun hasCompletedOnboardingDefaultsFalseAndRoundTrips() = runBlocking {
        assertFalse(repository.hasCompletedOnboarding.first())

        repository.setHasCompletedOnboarding(true)
        assertTrue(repository.hasCompletedOnboarding.first())

        repository.setHasCompletedOnboarding(false)
        assertFalse(repository.hasCompletedOnboarding.first())
    }
}
