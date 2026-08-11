package io.github.cidy02.kudos.data.preferences

import android.content.Context
import androidx.datastore.preferences.preferencesDataStore

val Context.kudosSettingsDataStore by preferencesDataStore(
    name = SettingsRepository.DataStoreName
)
