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

    /**
     * First-launch onboarding gate (iOS `@AppStorage("hasCompletedOnboarding")`).
     * Device-local only — not part of [KudosSettings] / backup restore, so a
     * restored backup never re-triggers the welcome screen on an already-used device.
     */
    val hasCompletedOnboarding: Flow<Boolean> = dataStore.data.map { prefs ->
        prefs[Keys.HasCompletedOnboarding] ?: false
    }

    suspend fun snapshot(): KudosSettings {
        return settings.first()
    }

    suspend fun setHasCompletedOnboarding(completed: Boolean) {
        dataStore.edit { it[Keys.HasCompletedOnboarding] = completed }
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

    /** Persist reader font size in points (settings-contract field). */
    suspend fun updateReaderFontPt(fontPt: Double) {
        dataStore.edit { it[Keys.ReaderFontPt] = fontPt }
    }

    /**
     * When true, [ReaderSettingsMapper] prefers app theme over [updateReaderTheme].
     * Display-sheet theme picks must set this false so the choice survives reopen.
     */
    suspend fun updateMatchAppReaderTheme(match: Boolean) {
        dataStore.edit { it[Keys.MatchAppReaderTheme] = match }
    }

    /**
     * When true, reader applies user style overrides (`publisherStyles = false`).
     * Display-sheet font/theme changes set this true.
     */
    suspend fun updateReaderCustomize(customize: Boolean) {
        dataStore.edit { it[Keys.ReaderCustomize] = customize }
    }

    suspend fun updateMatureContentMode(mode: MatureContentMode) {
        dataStore.edit { it[Keys.MatureContentMode] = mode.storageValue }
    }

    suspend fun updateHideMatureContent(hide: Boolean) {
        dataStore.edit { it[Keys.HideMatureContent] = hide }
    }

    suspend fun updateRequireBiometricToReveal(require: Boolean) {
        dataStore.edit { it[Keys.RequireBiometricToReveal] = require }
    }

    suspend fun updateConfirmBeforeDelete(confirm: Boolean) {
        dataStore.edit { it[Keys.ConfirmBeforeDelete] = confirm }
    }

    suspend fun updateReaderJustify(justify: Boolean) {
        dataStore.edit { it[Keys.ReaderJustify] = justify }
    }

    suspend fun updateReaderMargin(margin: Double) {
        dataStore.edit { it[Keys.ReaderMargin] = margin }
    }

    suspend fun updateReaderLineHeight(lineHeight: Double) {
        dataStore.edit { it[Keys.ReaderLineHeight] = lineHeight }
    }

    suspend fun updateReaderFontId(fontId: String) {
        dataStore.edit { it[Keys.ReaderFontId] = fontId }
    }

    suspend fun updateReaderBoldText(bold: Boolean) {
        dataStore.edit { it[Keys.ReaderBoldText] = bold }
    }

    suspend fun updateReaderTwoPage(twoPage: Boolean) {
        dataStore.edit { it[Keys.ReaderTwoPage] = twoPage }
    }

    suspend fun updateReaderLetterSpacing(em: Double) {
        dataStore.edit { it[Keys.ReaderLetterSpacing] = em }
    }

    suspend fun updateReaderWordSpacing(em: Double) {
        dataStore.edit { it[Keys.ReaderWordSpacing] = em }
    }

    suspend fun updateAccentColor(hex: String) {
        dataStore.edit { it[Keys.AccentColorHex] = hex }
    }

    suspend fun resetToDefaults() {
        dataStore.edit { it.clear() }
    }

    /** Replace all preference keys from a full settings snapshot (backup restore). */
    suspend fun replaceAll(settings: KudosSettings) {
        dataStore.edit { prefs ->
            prefs[Keys.ReaderFontId] = settings.reader.readerFontId
            prefs[Keys.ReaderMode] = settings.reader.readerMode.storageValue
            prefs[Keys.ReaderTwoPage] = settings.reader.readerTwoPage
            prefs[Keys.ReaderCustomize] = settings.reader.readerCustomize
            prefs[Keys.ReaderBoldText] = settings.reader.readerBoldText
            prefs[Keys.ReaderFontPt] = settings.reader.readerFontPt
            prefs[Keys.ReaderLineHeight] = settings.reader.readerLineHeight
            prefs[Keys.ReaderLetterSpacing] = settings.reader.readerLetterSpacing
            prefs[Keys.ReaderWordSpacing] = settings.reader.readerWordSpacing
            prefs[Keys.ReaderMargin] = settings.reader.readerMargin
            prefs[Keys.ReaderJustify] = settings.reader.readerJustify
            prefs[Keys.ConfirmBeforeDelete] = settings.app.confirmBeforeDelete
            prefs[Keys.HideMatureContent] = settings.privacy.hideMatureContent
            prefs[Keys.MatureContentMode] = settings.privacy.matureContentMode.storageValue
            prefs[Keys.RequireBiometricToReveal] = settings.privacy.requireBiometricToReveal
            prefs[Keys.AppTheme] = settings.app.appTheme.storageValue
            prefs[Keys.ReaderTheme] = settings.reader.readerTheme.storageValue
            prefs[Keys.MatchAppReaderTheme] = settings.reader.matchAppReaderTheme
            prefs[Keys.AccentColorHex] = settings.app.accentColorHex
        }
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
        /** Device-local first-launch flag; not included in backup-compatible settings. */
        val HasCompletedOnboarding = booleanPreferencesKey("hasCompletedOnboarding")
    }

    companion object {
        const val DataStoreName = "kudos_settings"
    }
}
