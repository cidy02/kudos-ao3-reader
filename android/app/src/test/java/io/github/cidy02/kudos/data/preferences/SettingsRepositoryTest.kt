package io.github.cidy02.kudos.data.preferences

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import io.github.cidy02.kudos.core.model.AppThemeSetting
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.ReaderMode
import java.io.File
import java.nio.file.Files
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
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
}
