package io.github.cidy02.kudos.reader

import android.app.Application
import android.content.Context
import android.net.Uri
import androidx.activity.compose.LocalActivityResultRegistryOwner
import androidx.activity.result.ActivityResultRegistry
import androidx.activity.result.ActivityResultRegistryOwner
import androidx.activity.result.contract.ActivityResultContract
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.core.app.ActivityOptionsCompat
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.emptyPreferences
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.CustomFontRepository
import io.github.cidy02.kudos.files.FontFileStore
import io.github.cidy02.kudos.reader.settings.ReaderPreferences
import java.io.File
import java.nio.file.Files
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h1200dp")
class ReaderFontSectionTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var database: KudosDatabase
    private lateinit var root: File
    private lateinit var fonts: CustomFontRepository
    private lateinit var context: Context
    private val dataStore = object : DataStore<Preferences> {
        override val data = MutableStateFlow(emptyPreferences())
        override suspend fun updateData(transform: suspend (Preferences) -> Preferences): Preferences =
            transform(data.value).also { data.value = it }
    }
    private val settings = SettingsRepository(dataStore)
    private var selection = emptyList<Uri>()
    private var pickerLaunches = 0
    private val registry = object : ActivityResultRegistry() {
        override fun <I, O> onLaunch(requestCode: Int, contract: ActivityResultContract<I, O>,
            input: I, options: ActivityOptionsCompat?) {
            pickerLaunches++
            dispatchResult(requestCode, selection)
        }
    }

    @Before fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java).allowMainThreadQueries().build()
        root = Files.createTempDirectory("reader-font-section").toFile()
        fonts = CustomFontRepository(database.customFontDao(), FontFileStore(root.toPath()), settings)
    }

    @After fun tearDown() {
        database.close()
        root.deleteRecursively()
    }

    private fun showReaderFonts() {
        compose.setContent {
            val saved by settings.settings.collectAsState(initial = KudosSettings.Defaults)
            val scope = rememberCoroutineScope()
            val owner = object : ActivityResultRegistryOwner { override val activityResultRegistry = registry }
            CompositionLocalProvider(LocalActivityResultRegistryOwner provides owner) {
                MaterialTheme {
                    ReaderDisplaySheet(
                        preferences = ReaderPreferences(fontFamily = saved.reader.readerFontId),
                        settingsRepository = settings, customFontRepository = fonts,
                        keepScreenAwake = false, onFontSizeChange = {}, onThemeChange = {},
                        onFontFamilyChange = { id -> scope.launch { settings.updateReaderFontId(id ?: "system") } }
                    )
                }
            }
        }
    }

    private fun file(name: String, bytes: ByteArray) = Uri.fromFile(File(root, name).apply { writeBytes(bytes) })
    private fun validFont() = context.assets.open("readium/fonts/OpenDyslexic-Regular.otf").use { it.readBytes() }

    @Test fun readerListsSelectsImportsAndDeletesFontsThroughTheSettingsRepository() {
        val installed = runBlocking { fonts.importFont("Imported serif", "serif.otf", validFont()).getOrThrow() }
        runBlocking { settings.updateReaderFontId("system") }
        showReaderFonts()
        compose.onNodeWithText("Imported serif").performScrollTo().performClick()
        compose.waitUntil(5_000) { runBlocking { settings.snapshot().reader.readerFontId == installed.selectionId } }
        selection = listOf(file("New font.otf", validFont()))
        compose.onNodeWithContentDescription("Import font (.ttf / .otf)").performScrollTo().performClick()
        compose.waitUntil(5_000) { runBlocking { fonts.listImported().size == 2 } }
        compose.onNodeWithText("New font").performScrollTo().assertExists()
        val added = runBlocking { fonts.listImported().first { it.name == "New font" } }
        assertEquals(added.selectionId, runBlocking { settings.snapshot().reader.readerFontId })
        compose.onNodeWithContentDescription("Delete New font").performScrollTo().performClick()
        compose.waitUntil(5_000) { runBlocking { fonts.listImported().size == 1 && settings.snapshot().reader.readerFontId == "system" } }
        assertFalse(Files.exists(fonts.fontPath(added)))
        compose.onNodeWithText("System").performScrollTo().assertExists()
        assertEquals(1, pickerLaunches)
    }

    @Test fun readerImportKeepsExistingFontsAndExplainsRejectedFilesIncludingPartialSuccess() {
        val installed = runBlocking { fonts.importFont("Kept", "kept.otf", validFont()).getOrThrow() }
        showReaderFonts()
        selection = listOf(file("bad.otf", byteArrayOf(1, 2, 3)), file("unsupported.woff", validFont()))
        compose.onNodeWithContentDescription("Import font (.ttf / .otf)").performScrollTo().performClick()
        compose.waitUntil(5_000) {
            compose.onAllNodesWithText("Only .ttf and .otf font files are supported.", substring = true)
                .fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithText("Keeping it would stop your library backup from restoring.", substring = true)
            .performScrollTo().assertExists()
        compose.onNodeWithText("Only .ttf and .otf font files are supported.", substring = true).assertExists()
        assertEquals(listOf(installed.copy(dateAdded = installed.dateAdded.truncatedTo(ChronoUnit.MILLIS))),
            runBlocking { fonts.listImported() })
        assertEquals(installed.selectionId, runBlocking { settings.snapshot().reader.readerFontId })
        selection = listOf(file("Good.otf", validFont()), file("bad.otf", byteArrayOf(1)))
        compose.onNodeWithContentDescription("Import font (.ttf / .otf)").performScrollTo().performClick()
        compose.waitUntil(5_000) { runBlocking { fonts.listImported().size == 2 } }
        compose.waitUntil(5_000) {
            compose.onAllNodesWithText("Imported 1 fonts", substring = true).fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithText("Imported 1 fonts", substring = true).performScrollTo().assertExists()
        compose.onNodeWithText("Keeping it would stop your library backup from restoring.", substring = true).assertExists()
    }
}
