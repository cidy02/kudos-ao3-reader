package io.github.cidy02.kudos.update

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.longPreferencesKey
import kotlinx.coroutines.flow.first

/**
 * Device-local update-check bookkeeping. Deliberately NOT part of
 * [io.github.cidy02.kudos.data.preferences.SettingsRepository]'s
 * backup/restore surface — "when did this device last check GitHub" is not
 * portable user preference data, unlike theme/reader settings.
 */
class AppUpdatePreferences(private val dataStore: DataStore<Preferences>) {
    suspend fun lastCheckedAtMillis(): Long? {
        return dataStore.data.first()[Keys.LastCheckedAt]
    }

    suspend fun setLastCheckedAtMillis(millis: Long) {
        dataStore.edit { it[Keys.LastCheckedAt] = millis }
    }

    private object Keys {
        val LastCheckedAt = longPreferencesKey("appUpdateLastCheckedAtMillis")
    }
}
