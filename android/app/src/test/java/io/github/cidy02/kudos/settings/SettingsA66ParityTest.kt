package io.github.cidy02.kudos.settings

import android.app.Application
import android.content.Context
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import io.github.cidy02.kudos.works.WorkRepository
import java.nio.file.Files
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h2200dp")
class SettingsA66ParityTest {
    @get:Rule val compose = createComposeRule()
    private val root = Files.createTempDirectory("kudos-settings-a66")
    private val storeScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val repository = SettingsRepository(PreferenceDataStoreFactory.create(scope = storeScope,
        produceFile = { root.resolve("settings.preferences_pb").toFile() }))

    @After fun tearDown() { storeScope.cancel(); root.toFile().deleteRecursively() }

    @Test fun appearanceKeepsTextSizeAndOpensSpacingOnlyInCustomizeTheme() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) { SettingsAppearancePage(repository, KudosSettings.Defaults) }
        }
        for (label in listOf("Match App & Reader Theme", "Customize Theme…", "Accent colour")) {
            compose.onNodeWithText(label).assertExists()
        }
        compose.onAllNodesWithText("Reset to AO3 Red").assertCountEquals(0)
        compose.onNodeWithContentDescription("Text size, 18 pt").assertExists()
        for (label in listOf("Line height", "Letter spacing", "Word spacing", "Margin")) {
            compose.onAllNodesWithText(label).assertCountEquals(0)
        }
        compose.onNodeWithText("Customize Theme…").performClick()
        compose.waitUntil(15_000) { compose.onAllNodesWithText("Line Spacing").fetchSemanticsNodes().isNotEmpty() }
        for (label in listOf("Customize", "Line Spacing", "Character Spacing", "Word Spacing", "Margins")) {
            compose.onNodeWithText(label).assertExists()
        }
        assertFalse(runBlocking { repository.snapshot().reader.readerCustomize })
    }

    @Test fun appearanceShowsSixNamedAccentsAndWarnsBeforeCustomPicker() {
        compose.setContent {
            val current = androidx.compose.runtime.produceState(KudosSettings.Defaults) {
                repository.settings.collect { value = it }
            }.value
            KudosTheme(KudosThemeMode.Light, accentColorHex = current.app.accentColorHex) {
                SettingsAppearancePage(repository, current)
            }
        }
        compose.onNodeWithText("Accent colour").performScrollTo()
        compose.onNodeWithContentDescription("AO3 Red").assertExists().assertIsSelected()
        for (name in listOf("Plum", "Ink Blue", "Deep Teal", "Forest", "Ochre")) {
            compose.onNodeWithContentDescription(name).assertExists().assertIsNotSelected()
        }
        compose.onNodeWithContentDescription("Custom colour").assertExists().assertIsNotSelected()

        compose.onNodeWithContentDescription("Plum").performClick()
        compose.waitUntil(5_000) { runBlocking { repository.snapshot().app.accentColorHex == "#7B2D6B" } }
        compose.onNodeWithContentDescription("Plum").assertIsSelected()
        compose.onNodeWithContentDescription("AO3 Red").assertIsNotSelected()

        compose.onNodeWithContentDescription("Custom colour").performClick()
        compose.onNodeWithText("Use a Custom Colour?").assertExists()
        compose.onNodeWithText("Choose a Colour").assertExists()
        compose.onNodeWithText("Keep AO3 Red").performClick()
        compose.onAllNodesWithText("Use a Custom Colour?").assertCountEquals(0)
    }

    @Test fun downloadsUsesThePrivacyTotalIncludingCacheAndExcludingOtherFiles() = runBlocking<Unit> {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java).build()
        val works = WorkRepository(database, WorkFileStore(root))
        val scanner = LocalDataFootprintScanner(database, works, root, root.resolve("cache"))
        Files.createDirectories(root.resolve("fonts"))
        Files.write(root.resolve("fonts/local.ttf"), ByteArray(8192))
        Files.createDirectories(root.resolve("cache"))
        Files.write(root.resolve("cache/fandom-catalog.json"), ByteArray(4096))
        Files.write(root.resolve("not-a-storage-category"), ByteArray(65536))
        val expected = LocalStorageFootprint.formatted(scanner.measure().totalBytes)
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) { SettingsDownloadsPage(repository, KudosSettings.Defaults, scanner) }
        }
        compose.waitUntil(15_000) { compose.onAllNodesWithText(expected).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Storage used").assertExists()
        compose.onNodeWithText(expected).assertExists()
        // The scan completed before closing the in-memory database.
        database.close()
    }
}
