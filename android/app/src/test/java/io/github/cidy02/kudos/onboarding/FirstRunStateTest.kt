package io.github.cidy02.kudos.onboarding

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.emptyPreferences
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.support.ChangelogEntry
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class FirstRunStateTest {
    private val preferences = object : DataStore<Preferences> {
        override val data = MutableStateFlow(emptyPreferences())
        override suspend fun updateData(transform: suspend (Preferences) -> Preferences): Preferences =
            transform(data.value).also { data.value = it }
    }
    private val store = SettingsRepository(preferences)
    private val releases = listOf(
        ChangelogEntry("3.0", "Third"), ChangelogEntry("2.0", "Second"), ChangelogEntry("1.0", "First")
    )

    @Test
    fun welcomeThenOptionalSyncAndTemporarySkipReappearsNextLaunch() = runBlocking {
        var state = store.firstRunState.first()
        assertFalse(state.welcomeCompleted)
        assertFalse(state.showsSync(false))
        store.setHasCompletedOnboarding(true)
        state = store.firstRunState.first()
        assertTrue(state.welcomeCompleted)
        assertTrue(state.showsSync(false))
        // Unticked Not Now makes no store writes; only the session flag changes.
        assertFalse(state.showsSync(true))
        val nextLaunch = SettingsRepository(preferences).firstRunState.first()
        assertTrue(nextLaunch.showsSync(false))
        assertFalse(nextLaunch.syncConfigured)
        assertFalse(nextLaunch.syncPermanentlyDismissed)
    }

    @Test
    fun permanentSkipAndSuccessfulSetupSurviveRelaunch() = runBlocking {
        store.setHasCompletedOnboarding(true)
        store.setHasPermanentlyDismissedSyncFolderOnboarding(true)
        assertFalse(SettingsRepository(preferences).firstRunState.first().showsSync(false))
        store.setHasPermanentlyDismissedSyncFolderOnboarding(false)
        store.setHasConfiguredSyncFolder(true)
        assertFalse(SettingsRepository(preferences).firstRunState.first().showsSync(false))
        // Disconnecting does not undo the historic configured flag.
        store.updateSyncIsEnabled(false)
        store.updateSyncFolderUri(null)
        assertFalse(store.firstRunState.first().showsSync(false))
    }

    @Test
    fun folderConnectedInSettingsSuppressesOfferWithoutHistoricFlag() = runBlocking {
        store.setHasCompletedOnboarding(true)
        store.updateSyncFolderUri("content://example/tree/library")
        assertTrue(store.firstRunState.first().showsSync(false))
        store.updateSyncIsEnabled(true)
        val state = store.firstRunState.first()
        assertFalse(state.syncConfigured)
        assertTrue(state.syncConnected)
        assertFalse(state.showsSync(false))
    }

    @Test
    fun firstChangelogReadSeedsVersionWithoutShowingNotes() = runBlocking {
        assertNull(store.lastSeenChangelogVersion.first())
        assertEquals(emptyList<ChangelogEntry>(), store.unseenChangelogEntries("1.0", releases))
        assertEquals("1.0", store.lastSeenChangelogVersion.first())
        assertEquals(emptyList<ChangelogEntry>(), store.unseenChangelogEntries("1.0", releases))
    }

    @Test
    fun updateShowsUnseenNewestFirstAndOnlyDoneRemembersVersion() = runBlocking {
        store.markChangelogSeen("1.0")
        assertEquals(releases.take(2), store.unseenChangelogEntries("3.0", releases))
        // Dismiss/Back only drops the UI list, without markChangelogSeen.
        assertEquals("1.0", store.lastSeenChangelogVersion.first())
        assertEquals(releases.take(2),
            SettingsRepository(preferences).unseenChangelogEntries("3.0", releases))
        store.markChangelogSeen("3.0")
        assertEquals(emptyList<ChangelogEntry>(),
            SettingsRepository(preferences).unseenChangelogEntries("3.0", releases))
    }

    @Test
    fun unknownPreviousVersionShowsAllAndNoNewerEntryShowsNothing() = runBlocking {
        store.markChangelogSeen("old-with-no-entry")
        assertEquals(releases, store.unseenChangelogEntries("3.0", releases))
        store.markChangelogSeen("3.0")
        assertEquals(emptyList<ChangelogEntry>(), store.unseenChangelogEntries("3.1", releases))
        // iOS also leaves lastSeen untouched if a build has no newer entry.
        assertEquals("3.0", store.lastSeenChangelogVersion.first())
    }

    @Test
    fun replacingBackupSettingsDoesNotResetWelcomeSkipOrSeenVersion() = runBlocking {
        store.setHasCompletedOnboarding(true)
        store.setHasPermanentlyDismissedSyncFolderOnboarding(true)
        store.markChangelogSeen("3.0")
        store.replaceAll(KudosSettings.Defaults)
        val state = store.firstRunState.first()
        assertTrue(state.welcomeCompleted)
        assertTrue(state.syncPermanentlyDismissed)
        assertEquals("3.0", store.lastSeenChangelogVersion.first())
    }

    @Test
    fun allPreviewRoutesRequireDebugAndDemoAndResolveTheirScreen() {
        val routes = mapOf(
            "nav:welcome" to FirstRunDemoScreen.Welcome,
            "nav:sync-onboarding" to FirstRunDemoScreen.SyncOnboarding,
            "nav:whats-new" to FirstRunDemoScreen.WhatsNew,
            "nav:login" to FirstRunDemoScreen.Login
        )
        routes.forEach { (route, screen) ->
            assertEquals(screen, firstRunDemoScreen(route, debug = true, demo = true))
            assertNull(firstRunDemoScreen(route, debug = false, demo = true))
            assertNull(firstRunDemoScreen(route, debug = true, demo = false))
        }
        assertNull(firstRunDemoScreen("nav:library", debug = true, demo = true))
        assertNull(firstRunDemoScreen(null, debug = true, demo = true))
    }
}
