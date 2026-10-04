package io.github.cidy02.kudos.backup

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.toEntity
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.FontFileStore
import io.github.cidy02.kudos.files.WorkFileStore
import java.io.ByteArrayInputStream
import java.nio.file.Files
import java.time.Instant
import java.util.zip.ZipInputStream
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The original file of a converted import, and the record of its conversion, through a backup
 * (iOS `Originals/`, `KudosBackupService.restore`). It is often the last copy of the work there
 * is, and a backup that drops it is not a backup of it.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class OriginalsRoundTripTest {
    private val devices = mutableListOf<Device>()

    @After
    fun tearDown() = devices.forEach(Device::close)

    @Test
    fun aBackupCarriesAnOriginalAndItsRecordToAnEmptyLibrary() = runTest {
        val archive = deviceWithAnOriginal().repository.exportV2ZipBytes()

        // In the archive under iOS's names: the work's id in capitals.
        assertEquals(
            setOf("Originals/${WORK.uppercase()}.pdf", "Originals/${WORK.uppercase()}.conversion.json"),
            entryNames(archive).filter { it.startsWith("Originals/") }.toSet()
        )

        val target = device()
        target.repository.importV2ZipBytes(archive)

        val (extension, bytes) = target.workFiles.readOriginal(WORK)!!
        assertEquals("pdf", extension)
        assertArrayEquals(PDF, bytes)
        assertArrayEquals(RECORD, target.workFiles.readConversionRecord(WORK))
    }

    @Test
    fun anArchivesOriginalNeverGoesOverOrBesideOneAlreadyHere() = runTest {
        val archive = deviceWithAnOriginal().repository.exportV2ZipBytes()
        // The file the reader imported on this device, of another kind.
        val target = device().apply {
            seedWork(WORK)
            workFiles.writeOriginal(WORK, "html", HTML)
        }

        target.repository.importV2ZipBytes(archive)

        val (extension, bytes) = target.workFiles.readOriginal(WORK)!!
        assertEquals("html", extension)
        assertArrayEquals(HTML, bytes)
        assertNull("a record comes only with the original it describes", target.workFiles.readConversionRecord(WORK))
    }

    @Test
    fun anOriginalFollowsItsWorkToTheIdItHasHere() = runTest {
        val archive = deviceWithAnOriginal().repository.exportV2ZipBytes()
        // The same AO3 work, saved here under another id.
        val target = device().apply { seedWork(WORK_HERE) }

        target.repository.importV2ZipBytes(archive)

        assertArrayEquals(PDF, target.workFiles.readOriginal(WORK_HERE)?.second)
        assertNull(target.workFiles.readOriginal(WORK))
    }

    @Test
    fun aFileInOriginalsThatIosWouldNotHaveWrittenIsIgnored() {
        val archive = BackupExporter.exportV2(
            KudosBackupPackage(
                manifest = KudosBackupManifest(
                    version = BackupVersion.CURRENT,
                    exportedAt = "2026-01-15T12:00:00Z",
                    exportedBy = BackupExportedBy(
                        platform = "ios",
                        appVersion = "test",
                        schemaVersion = BackupVersion.CURRENT
                    ),
                    settings = BackupSettingsPayload()
                ),
                originalFilesByName = mapOf(
                    "${WORK.uppercase()}.pdf" to PDF,
                    "readme.txt" to "not a work's file".toByteArray()
                )
            )
        )

        assertEquals(setOf("${WORK.uppercase()}.pdf"), BackupImporter.importV2Zip(archive).originalFilesByName.keys)
    }

    @Test
    fun theConversionRecordIsNotMistakenForTheOriginal() = runTest {
        val files = device().workFiles
        files.writeConversionRecord(WORK, RECORD)
        assertFalse("the record alone is not an original", files.originalExists(WORK))

        files.writeOriginal(WORK, "pdf", PDF)
        files.writeConversionRecord(WORK, RECORD)
        assertArrayEquals(PDF, files.readOriginal(WORK)?.second)

        // The record goes with the original it describes.
        files.deleteOriginal(WORK)
        assertFalse(files.originalExists(WORK))
        assertNull(files.readConversionRecord(WORK))
    }

    private suspend fun deviceWithAnOriginal() = device().apply {
        seedWork(WORK)
        workFiles.writeOriginal(WORK, "pdf", PDF)
        workFiles.writeConversionRecord(WORK, RECORD)
    }

    private fun device() = Device().also(devices::add)

    private fun entryNames(archive: ByteArray): List<String> =
        ZipInputStream(ByteArrayInputStream(archive)).use { zip ->
            generateSequence { zip.nextEntry }.map { it.name }.toList()
        }

    private class Device : AutoCloseable {
        private val context = ApplicationProvider.getApplicationContext<Context>()
        private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        private val root = Files.createTempDirectory("kudos-originals")
        val database: KudosDatabase = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        val workFiles = WorkFileStore(root)
        val repository = BackupRepository(
            database = database,
            workFileStore = workFiles,
            fontFileStore = FontFileStore(root),
            settingsRepository = SettingsRepository(
                PreferenceDataStoreFactory.create(
                    scope = scope,
                    produceFile = { root.resolve("settings.preferences_pb").toFile() }
                )
            ),
            persistenceGate = PersistenceGate(),
            clock = { Instant.parse("2026-01-15T12:00:00Z") },
            appVersion = "test"
        )

        suspend fun seedWork(id: String) {
            database.workDao().upsert(
                SavedWork(
                    id = id,
                    title = "Imported from a PDF",
                    author = "Author",
                    sourceUrl = "https://archiveofourown.org/works/777",
                    dateAdded = Instant.parse("2026-01-01T00:00:00Z"),
                    isSaved = true
                ).toEntity()
            )
        }

        override fun close() {
            database.close()
            scope.cancel()
            root.toFile().deleteRecursively()
        }
    }

    private companion object {
        const val WORK = "5b00abcd-0000-4000-8000-00000000000a"
        const val WORK_HERE = "5b00abcd-0000-4000-8000-00000000000b"
        val PDF = "%PDF-1.7 the original".toByteArray()
        val HTML = "<html><body>imported here</body></html>".toByteArray()
        val RECORD = """{"converterVersion":4,"format":"pdf","originalFileName":"story.pdf","convertedAt":0}""".toByteArray()
    }
}
