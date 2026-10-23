package io.github.cidy02.kudos.backup

import android.app.Application
import android.content.Context
import android.net.Uri
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.FontFileStore
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.works.prepareDocumentImports
import io.github.cidy02.kudos.works.converters.EpubBuilder
import java.io.File
import java.nio.file.Files
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
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
@Config(sdk = [35], application = Application::class)
class PickedBackupImportTest {
    @get:Rule val compose = createComposeRule()
    private val root = Files.createTempDirectory("picked-backup-test")
    private val settingsScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private lateinit var database: KudosDatabase
    private lateinit var settings: SettingsRepository
    private lateinit var repository: BackupRepository
    private lateinit var works: WorkRepository
    private lateinit var files: WorkFileStore
    private lateinit var uri: Uri
    private var dismissed = false

    @Before fun setUp() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java).build()
        files = WorkFileStore(root.resolve("library"))
        settings = SettingsRepository(PreferenceDataStoreFactory.create(scope = settingsScope,
            produceFile = { root.resolve("settings.preferences_pb").toFile() }))
        repository = BackupRepository(database, files, FontFileStore(root.resolve("library")), settings, PersistenceGate())
        works = WorkRepository(database, files)
        val bytes = BackupExporter.exportV2(KudosBackupPackage(
            manifest = KudosBackupManifest(version = 8, exportedAt = "2024-01-02T03:04:05Z", works = listOf(
                BackupWork(id = WorkId, title = "Backed-up story", author = "Author", hasEPUB = true,
                    isSaved = true, isFavorite = true, lastSpineIndex = 2, lastScrollFraction = 0.4)
            )),
            epubFilesByWorkId = mapOf(WorkId to EpubBuilder.buildEpub("Backed-up story", "<p>Original prose.</p>"))
        ))
        // The manifest, not the name, must choose the backup route.
        uri = Uri.fromFile(File(root.toFile(), "renamed.zip").also { it.writeBytes(bytes) })
        val preparation = prepareDocumentImports(context, listOf(uri))
        assertTrue(preparation.imports.isEmpty())
        assertTrue(preparation.failures.toString(), preparation.failures.isEmpty())
        assertEquals(listOf(uri), preparation.backups)
    }

    @After fun tearDown() {
        settingsScope.cancel()
        database.close()
        root.toFile().deleteRecursively()
    }

    private fun showIncomingBackup() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                BackupScreen(repository, settings, database, works,
                    incomingUri = uri, importOnly = true, onIncomingHandled = { dismissed = true })
            }
        }
        compose.waitUntil(10_000) {
            compose.onAllNodesWithText("Library records").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithText("Import Backup").assertExists()
        compose.onNodeWithText("Library records").assertExists()
        runBlocking { assertTrue(database.workDao().getAll().isEmpty()) }
    }

    @Test fun pickedBackupOpensReviewAndCancelChangesNothing() {
        showIncomingBackup()
        compose.onNodeWithText("Cancel").performClick()
        compose.runOnIdle { assertTrue(dismissed) }
        runBlocking {
            assertTrue(database.workDao().getAll().isEmpty())
            assertFalse(files.workEpubExists(WorkId))
        }
    }

    @Test fun pickedBackupMergeRestoresFlagsAndProgressInsteadOfImportingAStandaloneBook() {
        showIncomingBackup()
        compose.onNodeWithText("Merge").performScrollTo().performClick()
        compose.waitUntil(10_000) {
            compose.onAllNodesWithText("OK").fetchSemanticsNodes().isNotEmpty()
        }
        runBlocking {
            val work = works.getWork(WorkId)!!
            assertEquals("Backed-up story", work.title)
            assertTrue(work.isFavorite)
            assertEquals(2, work.lastSpineIndex)
            assertEquals(0.4, work.lastScrollFraction, 0.00001)
            assertTrue(files.workEpubExists(WorkId))
            assertEquals(1, database.workDao().getAll().size)
        }
        compose.onNodeWithText("OK").performClick()
        compose.runOnIdle { assertTrue(dismissed) }
    }

    companion object {
        private const val WorkId = "00000000-0000-0000-0000-000000000001"
    }
}
