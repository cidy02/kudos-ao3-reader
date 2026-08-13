package io.github.cidy02.kudos.data.preferences

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.MatureContentMode
import io.github.cidy02.kudos.core.model.PrivacySettings
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class SettingsRepositoryPrivacyTest {
    @get:Rule val tmpFolder: TemporaryFolder = TemporaryFolder.builder().assureDeletion().build()

    @Test
    fun testPrivacyStricterOf() = runTest {
        val dataStore = PreferenceDataStoreFactory.create(produceFile = { File(tmpFolder.root, "test.preferences_pb") })
        val repo = SettingsRepository(dataStore)
        
        // Start with strict settings
        val initialSettings = KudosSettings(
            privacy = PrivacySettings(
                hideMatureContent = true,
                matureContentMode = MatureContentMode.Hide,
                requireBiometricToReveal = true
            )
        )
        repo.replaceAll(initialSettings)
        
        // Try to relax them with incoming backup
        val relaxedSettings = KudosSettings(
            privacy = PrivacySettings(
                hideMatureContent = false,
                matureContentMode = MatureContentMode.Obscure,
                requireBiometricToReveal = false
            )
        )
        repo.replaceAll(relaxedSettings)
        
        val current = repo.settings.first()
        assertTrue(current.privacy.hideMatureContent)
        assertEquals(MatureContentMode.Hide, current.privacy.matureContentMode)
        assertTrue(current.privacy.requireBiometricToReveal)
    }
}
