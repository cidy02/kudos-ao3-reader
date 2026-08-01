package io.github.cidy02.kudos.data.preferences

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import io.github.cidy02.kudos.core.model.AppThemeSetting
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.ReaderMode
import io.github.cidy02.kudos.core.model.ReaderThemeSetting
import java.io.File
import java.nio.file.Files
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
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
}
