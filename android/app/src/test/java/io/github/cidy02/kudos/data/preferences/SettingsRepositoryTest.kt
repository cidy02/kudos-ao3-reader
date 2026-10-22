package io.github.cidy02.kudos.data.preferences

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import io.github.cidy02.kudos.library.FavoriteScope
import io.github.cidy02.kudos.library.FavoritePreferences
import io.github.cidy02.kudos.library.ReadingAffinities
import io.github.cidy02.kudos.library.LibraryHistoryGrouping
import io.github.cidy02.kudos.core.model.BackupSettings
import io.github.cidy02.kudos.backup.BackupJson
import io.github.cidy02.kudos.backup.toBackupSettingsPayload
import kotlinx.serialization.encodeToString
import io.github.cidy02.kudos.core.model.AppThemeSetting
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.MatureContentMode
import io.github.cidy02.kudos.core.model.ReaderMode
import io.github.cidy02.kudos.core.model.ReaderThemeSetting
import io.github.cidy02.kudos.reader.settings.ReaderSpeechPreferences
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
    private val dataStore = PreferenceDataStoreFactory.create(
        scope = scope, produceFile = { File(tempDir, "settings.preferences_pb") })
    private val repository = SettingsRepository(dataStore)

    @Test fun accountShortcutsUseIosEncodingAndSurviveBackupRestore() = runBlocking<Unit> {
        val store = io.github.cidy02.kudos.account.AccountShortcutStore
        val inbox = io.github.cidy02.kudos.account.AccountShortcut.Inbox
        val drafts = io.github.cidy02.kudos.account.AccountShortcut.Drafts
        assertEquals("account.shortcuts", store.key)
        assertEquals(listOf("dashboard", "subscriptions", "works", "bookmarks", "collections", "history"),
            store.defaults.map { it.id })
        assertEquals(store.defaults, repository.accountShortcuts.first())
        val before = BackupJson.encodeToString(BackupSettings.fromSettings(repository.snapshot()).toBackupSettingsPayload())
        repository.updateAccountShortcuts(listOf(inbox, drafts))
        assertEquals("inbox,drafts", dataStore.data.first()[stringPreferencesKey(store.key)])
        assertEquals(listOf(inbox, drafts), SettingsRepository(dataStore).accountShortcuts.first())
        assertEquals(before, BackupJson.encodeToString(BackupSettings.fromSettings(repository.snapshot()).toBackupSettingsPayload()))
        assertFalse(before.contains("account.shortcuts"))
        repository.replaceAll(KudosSettings.Defaults)
        assertEquals(listOf(inbox, drafts), repository.accountShortcuts.first())
        for (raw in listOf("", "future", ",future,,")) {
            dataStore.edit { it[stringPreferencesKey(store.key)] = raw }
            assertEquals(store.defaults, repository.accountShortcuts.first())
        }
        // Series is a shortcut since 3gn, as on iOS; it was the unknown example here before.
        dataStore.edit { it[stringPreferencesKey(store.key)] = "series" }
        assertEquals(listOf(io.github.cidy02.kudos.account.AccountShortcut.Series), repository.accountShortcuts.first())
        dataStore.edit { it[stringPreferencesKey(store.key)] = "future,inbox,drafts,Inbox, drafts,inbox" }
        assertEquals(listOf(inbox, drafts, inbox), repository.accountShortcuts.first())
        dataStore.edit { it.remove(stringPreferencesKey(store.key)) }
        assertEquals(store.defaults, repository.accountShortcuts.first())
        for (shortcut in io.github.cidy02.kudos.account.AccountShortcut.entries) {
            repository.updateAccountShortcuts(listOf(shortcut))
            assertEquals(listOf(shortcut), repository.accountShortcuts.first())
        }
        // An explicit empty choice stays empty (stored as "none", as iOS since T-371); a value
        // never written, or an empty one, is still the defaults.
        repository.updateAccountShortcuts(emptyList())
        assertEquals(emptyList<io.github.cidy02.kudos.account.AccountShortcut>(), repository.accountShortcuts.first())
        assertEquals("none", dataStore.data.first()[stringPreferencesKey(store.key)])
        dataStore.edit { it[stringPreferencesKey(store.key)] = "" }
        assertEquals(store.defaults, repository.accountShortcuts.first())
    }

    @Test fun resetThemeRestoresIosDefaultsAndPreservesTextSizeThemeAndOtherSettings() = runBlocking {
        repository.updateReaderFontPt(27.0)
        repository.updateReaderMode(ReaderMode.Paged)
        repository.updateReaderTheme(ReaderThemeSetting.Sepia)
        repository.updateAppTheme(AppThemeSetting.Dark)
        repository.updateAccentColor("#123456")
        repository.updateReaderCustomize(true)
        repository.updateReaderBoldText(true)
        repository.updateReaderFontId("georgia")
        repository.updateReaderLineHeight(2.4)
        repository.updateReaderLetterSpacing(0.12)
        repository.updateReaderWordSpacing(0.6)
        repository.updateReaderMargin(64.0)
        repository.updateReaderJustify(true)
        val before = repository.snapshot()
        repository.resetReaderTheme()
        val after = SettingsRepository(dataStore).snapshot()
        // CustomizeThemeView.reset, ReaderStyle.swift:236–252: 1.65 / 28 / zero spacing.
        assertEquals(before.copy(reader = before.reader.copy(
            readerCustomize = false, readerBoldText = false, readerFontId = "system",
            readerLineHeight = 1.65, readerLetterSpacing = 0.0, readerWordSpacing = 0.0,
            readerMargin = 28.0, readerJustify = false)), after)
    }

    @Test fun themeSwatchesRespectTheAppReaderLink() = runBlocking {
        repository.updateEffectiveReaderTheme(ReaderThemeSetting.Oled)
        assertEquals(AppThemeSetting.Oled, repository.snapshot().app.appTheme)
        assertTrue(repository.snapshot().reader.matchAppReaderTheme)
        repository.updateMatchAppReaderTheme(false)
        repository.updateEffectiveReaderTheme(ReaderThemeSetting.Sepia)
        assertEquals(AppThemeSetting.Oled, repository.snapshot().app.appTheme)
        assertEquals(ReaderThemeSetting.Sepia, repository.snapshot().reader.readerTheme)
        assertFalse(repository.snapshot().reader.matchAppReaderTheme)
    }

    @After
    fun tearDown() {
        scope.cancel()
        tempDir.deleteRecursively()
    }

    @Test fun favoriteScopeOrderAndTagsFilterStayOnDeviceAndSurviveBackupRestore() = runBlocking {
        assertEquals(FavoritePreferences(), repository.favoritePreferences.first())
        val before = BackupJson.encodeToString(BackupSettings.fromSettings(repository.snapshot()).toBackupSettingsPayload())
        for (scope in FavoriteScope.entries) {
            repository.updateFavoriteScope(scope)
            assertEquals(scope, SettingsRepository(dataStore).favoritePreferences.first().scope)
            assertEquals(scope.id, dataStore.data.first()[stringPreferencesKey("library.favorites.scope")])
        }
        repository.updateFavoriteOrder(ReadingAffinities.Order.MostTime)
        repository.updateTagsUnreadOnly(true)
        assertEquals(before, BackupJson.encodeToString(BackupSettings.fromSettings(repository.snapshot()).toBackupSettingsPayload()))
        assertFalse(before.contains("library.favorites"))
        repository.replaceAll(KudosSettings.Defaults)
        assertEquals(FavoritePreferences(FavoriteScope.Tags, ReadingAffinities.Order.MostTime, true),
            repository.favoritePreferences.first())
        dataStore.edit {
            it[stringPreferencesKey("library.favorites.scope")] = "unknown"
            it[stringPreferencesKey("library.favorites.order")] = "unknown"
        }
        assertEquals(FavoritePreferences(tagsUnreadOnly = true), repository.favoritePreferences.first())
    }

    @Test fun historyGroupingIsDeviceLocalDefaultsToTimeAndSurvivesRestore() = runBlocking {
        assertEquals(LibraryHistoryGrouping.Time, repository.historyGrouping.first())
        val originalBackup = BackupJson.encodeToString(BackupSettings.fromSettings(repository.snapshot()).toBackupSettingsPayload())
        for (grouping in LibraryHistoryGrouping.entries) {
            repository.updateHistoryGrouping(grouping)
            assertEquals(grouping, SettingsRepository(dataStore).historyGrouping.first())
            assertEquals(grouping.id, dataStore.data.first()[stringPreferencesKey("library.history.grouping")])
            assertEquals(originalBackup, BackupJson.encodeToString(BackupSettings.fromSettings(repository.snapshot()).toBackupSettingsPayload()))
        }
        assertFalse(originalBackup.contains("grouping", ignoreCase = true))
        repository.replaceAll(KudosSettings.Defaults)
        assertEquals(LibraryHistoryGrouping.Flat, repository.historyGrouping.first())
        dataStore.edit { it[stringPreferencesKey("library.history.grouping")] = "unknown" }
        assertEquals(LibraryHistoryGrouping.Time, repository.historyGrouping.first())
    }

    @Test fun writingRecentTagsRoundTripCapDedupeAndStayOutOfBackupSettings() = runBlocking {
        for (kind in listOf("fandom", "relationship", "character", "freeform")) {
            repeat(21) { repository.recordWritingTag(kind, "tag-$it") }
            val names = repository.recentWritingTags.first().getValue(kind)
            assertEquals(20, names.size)
            assertEquals("tag-20", names.first()); assertEquals("tag-1", names.last())
        }
        val secondEditor = SettingsRepository(dataStore)
        secondEditor.recordWritingTag("freeform", "\u0085 Fluff \u00a0")
        repository.recordWritingTag("freeform", "Angst")
        secondEditor.recordWritingTag("freeform", "fluff")
        assertEquals(listOf("fluff", "Angst"), repository.recentWritingTags.first().getValue("freeform").take(2))
        val beforeIgnored = repository.recentWritingTags.first()
        repository.recordWritingTag("tag", "Ignored")
        repository.recordWritingTag("fandom", "\u0085 ")
        assertEquals(beforeIgnored, repository.recentWritingTags.first())
        // No key in KudosSettings/backup DTO; restore writes only its existing field allowlist.
        assertEquals(KudosSettings.Defaults, repository.snapshot())
        repository.replaceAll(KudosSettings.Defaults)
        assertEquals(beforeIgnored, secondEditor.recentWritingTags.first())
        assertEquals(KudosSettings.Defaults, repository.snapshot())
        val raw = dataStore.data.first()[stringPreferencesKey("writing.recentTags.v1")]!!
        assertTrue(raw.startsWith("{\"byKind\":"))
        assertTrue(raw.contains("fluff"))
    }

    @Test fun malformedRecentWritingJsonIsEmptyAndCanBeRepairedByAnAdd() = runBlocking {
        dataStore.edit { it[stringPreferencesKey("writing.recentTags.v1")] = "bad JSON" }
        assertTrue(repository.recentWritingTags.first().isEmpty())
        repository.recordWritingTag("character", "星")
        assertEquals(mapOf("character" to listOf("星")), repository.recentWritingTags.first())
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
        repository.updateKeepsWorksYouRead(true)

        val settings = repository.snapshot()

        assertFalse(settings.privacy.hideMatureContent)
        assertEquals(MatureContentMode.Hide, settings.privacy.matureContentMode)
        assertTrue(settings.privacy.requireBiometricToReveal)
        assertFalse(settings.app.confirmBeforeDelete)
        assertEquals("#0B57D0", settings.app.accentColorHex)
        assertTrue(settings.app.keepsWorksYouRead)
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

    @Test
    fun speechEngineAndPitchRoundTripClampNormalizeResetAndStayOutOfBackupSettings() = runBlocking {
        assertEquals(ReaderSpeechPreferences(), repository.speechPreferences.first())
        val backupBefore = BackupJson.encodeToString(
            BackupSettings.fromSettings(repository.snapshot()).toBackupSettingsPayload()
        )

        repository.updateSpeechPitch(1.15f)
        repository.updateSpeechEngine("kokoro")
        val saved = SettingsRepository(dataStore).speechPreferences.first()
        assertEquals(1.15f, saved.pitch, 0f)
        assertEquals("kokoro", saved.engine)

        val applied = saved.applyTo(io.github.cidy02.kudos.reader.settings.ReaderPreferences())
        assertEquals(1.15f, applied.speechPitch, 0f)
        assertEquals("kokoro", applied.speechEngine)

        // Clamping and engine normalization match iOS ReaderSpeechPreferences.
        repository.updateSpeechPitch(0.2f)
        assertEquals(0.75f, repository.speechPreferences.first().pitch, 0f)
        repository.updateSpeechPitch(1.9f)
        assertEquals(1.25f, repository.speechPreferences.first().pitch, 0f)
        repository.updateSpeechPitch(Float.NaN)
        assertEquals(1.0f, repository.speechPreferences.first().pitch, 0f)

        repository.updateSpeechEngine("device")
        assertEquals("system", repository.speechPreferences.first().engine)
        repository.updateSpeechEngine("unknown-future-engine")
        assertEquals("", repository.speechPreferences.first().engine)

        // Speech preferences stay device-local (excluded from KudosBackupSettings, as on iOS).
        repository.updateSpeechPitch(0.85f)
        repository.updateSpeechEngine("system")
        assertEquals(
            backupBefore,
            BackupJson.encodeToString(BackupSettings.fromSettings(repository.snapshot()).toBackupSettingsPayload())
        )
        repository.replaceAll(KudosSettings.Defaults)
        assertEquals(0.85f, repository.speechPreferences.first().pitch, 0f)
        assertEquals("system", repository.speechPreferences.first().engine)

        repository.resetSpeechPreferences()
        assertEquals(ReaderSpeechPreferences(), repository.speechPreferences.first())
    }
}
