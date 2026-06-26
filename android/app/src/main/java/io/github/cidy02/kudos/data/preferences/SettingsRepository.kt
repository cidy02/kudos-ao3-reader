package io.github.cidy02.kudos.data.preferences

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.doublePreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import io.github.cidy02.kudos.core.model.AppSettings
import io.github.cidy02.kudos.core.model.AppThemeSetting
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.MatureContentMode
import io.github.cidy02.kudos.core.model.PrivacySettings
import io.github.cidy02.kudos.core.model.ReaderMode
import io.github.cidy02.kudos.core.model.ReaderSettings
import io.github.cidy02.kudos.core.model.ReaderThemeSetting
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

class SettingsRepository(
    private val dataStore: DataStore<Preferences>
) {
    val settings: Flow<KudosSettings> = dataStore.data.map(::settingsFromPreferences)

    suspend fun snapshot(): KudosSettings {
        return settings.first()
    }

    suspend fun updateReaderMode(mode: ReaderMode) {
        dataStore.edit { it[Keys.ReaderMode] = mode.storageValue }
    }

    suspend fun updateAppTheme(theme: AppThemeSetting) {
        dataStore.edit { it[Keys.AppTheme] = theme.storageValue }
    }

    suspend fun updateReaderTheme(theme: ReaderThemeSetting) {
        dataStore.edit { it[Keys.ReaderTheme] = theme.storageValue }
    }

    suspend fun updateMatureContentMode(mode: MatureContentMode) {
        dataStore.edit { it[Keys.MatureContentMode] = mode.storageValue }
    }

    suspend fun updateAccentColor(hex: String) {
        dataStore.edit { it[Keys.AccentColorHex] = hex }
    }

    suspend fun resetToDefaults() {
        dataStore.edit { it.clear() }
    }

    private fun settingsFromPreferences(preferences: Preferences): KudosSettings {
        val defaults = KudosSettings.Defaults
        return KudosSettings(
            reader = ReaderSettings(
                readerFontId = preferences[Keys.ReaderFontId]
                    ?: defaults.reader.readerFontId,
                readerMode = ReaderMode.fromStorage(preferences[Keys.ReaderMode]),
                readerTwoPage = preferences[Keys.ReaderTwoPage]
                    ?: defaults.reader.readerTwoPage,
                readerCustomize = preferences[Keys.ReaderCustomize]
                    ?: defaults.reader.readerCustomize,
                readerBoldText = preferences[Keys.ReaderBoldText]
                    ?: defaults.reader.readerBoldText,
                readerFontPt = preferences[Keys.ReaderFontPt]
                    ?: defaults.reader.readerFontPt,
                readerLineHeight = preferences[Keys.ReaderLineHeight]
                    ?: defaults.reader.readerLineHeight,
                readerLetterSpacing = preferences[Keys.ReaderLetterSpacing]
                    ?: defaults.reader.readerLetterSpacing,
                readerWordSpacing = preferences[Keys.ReaderWordSpacing]
                    ?: defaults.reader.readerWordSpacing,
                readerMargin = preferences[Keys.ReaderMargin]
                    ?: defaults.reader.readerMargin,
                readerJustify = preferences[Keys.ReaderJustify]
                    ?: defaults.reader.readerJustify,
                readerTheme = ReaderThemeSetting.fromStorage(preferences[Keys.ReaderTheme]),
                matchAppReaderTheme = preferences[Keys.MatchAppReaderTheme]
                    ?: defaults.reader.matchAppReaderTheme
            ),
            app = AppSettings(
                confirmBeforeDelete = preferences[Keys.ConfirmBeforeDelete]
                    ?: defaults.app.confirmBeforeDelete,
                appTheme = AppThemeSetting.fromStorage(preferences[Keys.AppTheme]),
                accentColorHex = preferences[Keys.AccentColorHex]
                    ?: defaults.app.accentColorHex
            ),
            privacy = PrivacySettings(
                hideMatureContent = preferences[Keys.HideMatureContent]
                    ?: defaults.privacy.hideMatureContent,
                matureContentMode = MatureContentMode.fromStorage(
                    preferences[Keys.MatureContentMode]
                ),
                requireBiometricToReveal = preferences[Keys.RequireBiometricToReveal]
                    ?: defaults.privacy.requireBiometricToReveal
            )
        )
    }

    private object Keys {
        val ReaderFontId = stringPreferencesKey("readerFontID")
        val ReaderMode = stringPreferencesKey("readerMode")
        val ReaderTwoPage = booleanPreferencesKey("readerTwoPage")
        val ReaderCustomize = booleanPreferencesKey("readerCustomize")
        val ReaderBoldText = booleanPreferencesKey("readerBoldText")
        val ReaderFontPt = doublePreferencesKey("readerFontPt")
        val ReaderLineHeight = doublePreferencesKey("readerLineHeight")
        val ReaderLetterSpacing = doublePreferencesKey("readerLetterSpacing")
        val ReaderWordSpacing = doublePreferencesKey("readerWordSpacing")
        val ReaderMargin = doublePreferencesKey("readerMargin")
        val ReaderJustify = booleanPreferencesKey("readerJustify")
        val ConfirmBeforeDelete = booleanPreferencesKey("confirmBeforeDelete")
        val HideMatureContent = booleanPreferencesKey("hideMatureContent")
        val MatureContentMode = stringPreferencesKey("matureContentMode")
        val RequireBiometricToReveal = booleanPreferencesKey("requireBiometricToReveal")
        val AppTheme = stringPreferencesKey("appTheme")
        val ReaderTheme = stringPreferencesKey("readerTheme")
        val MatchAppReaderTheme = booleanPreferencesKey("matchAppReaderTheme")
        val AccentColorHex = stringPreferencesKey("accentColorHex")
    }

    companion object {
        const val DataStoreName = "kudos_settings"
    }
}
