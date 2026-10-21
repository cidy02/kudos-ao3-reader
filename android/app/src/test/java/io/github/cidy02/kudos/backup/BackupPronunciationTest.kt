package io.github.cidy02.kudos.backup

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.FontFileStore
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.reader.speech.KokoroPronunciationStore
import java.nio.file.Files
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class BackupPronunciationTest {
    private val root = Files.createTempDirectory("kudos-pronunciation-backup").toFile()
    private val settingsScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private lateinit var database: KudosDatabase
    private lateinit var repository: BackupRepository
    private val store = KokoroPronunciationStore(root)
    private val exportedAt = Instant.parse("2026-06-01T00:00:00Z")
    private val iosJson = """{
        "version":8,"exportedAt":"2026-06-01T00:00:00Z","works":[],
        "pronunciations":{
            "global":{"Anna":"ˈænə","anna":"ˈɑnə"},
            "fandoms":{"Haikyū!!":{"Tobio":"tˈoʊbioʊ"}},
            "works":{"42":{"Sam":"sæm"}}
        }
    }"""

    @Before fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java).allowMainThreadQueries().build()
        val settings = SettingsRepository(PreferenceDataStoreFactory.create(scope = settingsScope,
            produceFile = { root.resolve("settings.preferences_pb") }))
        repository = BackupRepository(database, WorkFileStore(root.toPath()), FontFileStore(root.toPath()),
            settings, PersistenceGate(), clock = { exportedAt })
    }

    @After fun cleanUp() { database.close(); settingsScope.cancel(); root.deleteRecursively() }

    @Test fun iosShapedManifestRestoresIntoTheFileAndExportsBackFieldForField() = runTest {
        val incoming = BackupImporter.decodeManifest(iosJson.toByteArray())
        repository.importPackage(KudosBackupPackage(incoming))
        assertEquals(incoming.pronunciations, store.load().corrections())
        val exported = BackupImporter.importV2Zip(repository.exportV2ZipBytes()).manifest
        val outgoing = Json.parseToJsonElement(BackupJson.encodeToString(exported)).jsonObject
        assertEquals(8, exported.version)
        assertEquals(Json.parseToJsonElement(iosJson).jsonObject["pronunciations"], outgoing["pronunciations"])
        assertFalse(outgoing["pronunciations"]!!.jsonObject.containsKey("version"))
    }

    @Test fun androidStoreExportsAnIosPayloadAndRestoresThroughTheZipPath() = runTest {
        val expected = KokoroPronunciationStore.Document(global = mapOf("Nico" to "nˈikoʊ"),
            fandoms = mapOf("LOTR" to mapOf("Sam" to "sæm")), works = mapOf("42" to mapOf("Sam" to "sɑm")))
        store.save(expected)
        val bytes = repository.exportV2ZipBytes()
        val manifest = BackupImporter.importV2Zip(bytes).manifest
        assertEquals(expected.corrections(), manifest.pronunciations)
        store.save(KokoroPronunciationStore.Document())
        repository.importV2ZipBytes(bytes)
        assertEquals(expected, store.load())
    }

    @Test fun everyRestoreModeMergesArchiveWinsAndKeepsLocalOnlyWordsInEveryScope() = runTest {
        val incoming = BackupImporter.decodeManifest(iosJson.toByteArray())
        for (mode in BackupImportMode.entries) {
            val local = KokoroPronunciationStore.Document(
                global = mapOf("Anna" to "old", "Local" to "kept"),
                fandoms = mapOf("Haikyū!!" to mapOf("Tobio" to "old", "Local" to "kept")),
                works = mapOf("42" to mapOf("Sam" to "old", "Local" to "kept")))
            store.save(local)
            repository.importPackage(KudosBackupPackage(incoming), mode)
            assertEquals(mode.name, local.corrections().merging(incoming.pronunciations), store.load().corrections())
        }
    }

    @Test fun missingOrEmptyCorrectionsInOldBackupsNeverClearTheStoreEvenInReplace() = runTest {
        store.setOverride("Anna", "ˈænə")
        val original = store.load()
        for (version in 1..8) {
            val incoming = BackupImporter.decodeManifest(
                """{"version":$version,"exportedAt":"2026-06-01T00:00:00Z"}""".toByteArray())
            repository.importPackage(KudosBackupPackage(incoming), BackupImportMode.REPLACE_LIBRARY)
            assertEquals(original, store.load())
        }
    }

    @Test fun malformedCorrectionsDoNotBlockExportPreviewOrImportAndAreKeptWithWarnings() = runTest {
        val malformed = "{not valid JSON"
        store.file.writeText(malformed)
        val result = repository.exportV2Zip()
        assertTrue(result.pronunciationsUnreadable)
        assertTrue(result.toUserMessage().contains(PRONUNCIATIONS_EXPORT_WARNING))
        val outgoing = BackupImporter.importV2Zip(result.bytes).manifest
        assertEquals(io.github.cidy02.kudos.reader.speech.PronunciationCorrections(), outgoing.pronunciations)
        assertFalse(BackupJson.encodeToString(outgoing).contains("pronunciationsUnreadable"))
        assertEquals(0, repository.previewImport(KudosBackupPackage(outgoing)).fileWorkCount)

        for (mode in BackupImportMode.entries) {
            val summary = repository.importV2ZipBytes(result.bytes, mode)
            assertFalse(summary.pronunciationsRestoreFailed)
            assertTrue(summary.pronunciationsUnreadable)
            assertTrue(summary.toUserMessage().contains("local pronunciation corrections could not be read; their file was kept"))
            assertEquals(malformed, store.file.readText())
        }
    }

    @Test fun malformedLocalCorrectionsDoNotBlockLibraryRestoreButIncomingCorrectionsNeedRetry() = runTest {
        val malformed = "{not valid JSON"
        val incoming = BackupImporter.decodeManifest(iosJson.toByteArray())
        val work = BackupWork(id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", title = "Restored work",
            author = "Author", dateAdded = exportedAt.toString())
        store.file.writeText(malformed)
        for (mode in BackupImportMode.entries) {
            val summary = repository.importPackage(KudosBackupPackage(incoming.copy(works = listOf(work))), mode)
            assertTrue(summary.pronunciationsRestoreFailed)
            assertTrue(summary.pronunciationsUnreadable)
            assertEquals("Restored work", database.workDao().getById(work.id)!!.title)
            assertEquals(malformed, store.file.readText())
        }
    }
}
