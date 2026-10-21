package io.github.cidy02.kudos.backup

import android.app.Application
import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.CacheStaging
import io.github.cidy02.kudos.files.FontFileStore
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.works.converters.EpubBuilder
import java.io.File
import java.nio.file.Files
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * EPUB package checks and backup font validation stage in the directory the
 * repository was given (the app cache in production) and delete that file
 * before returning, including when the font is not loadable.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class)
class BackupCacheStagingTest {
    private val root = Files.createTempDirectory("backup-cache-staging")
    private val cache = Files.createTempDirectory("backup-cache-dir").toFile()
    private val settingsScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private lateinit var database: KudosDatabase
    private lateinit var files: WorkFileStore
    private lateinit var repository: BackupRepository

    @Before fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        files = WorkFileStore(root.resolve("library"))
        val settings = SettingsRepository(PreferenceDataStoreFactory.create(
            scope = settingsScope,
            produceFile = { root.resolve("settings.preferences_pb").toFile() }
        ))
        repository = BackupRepository(
            database, files, FontFileStore(root.resolve("library")), settings, PersistenceGate(),
            cacheDirectory = cache
        )
    }

    @After fun tearDown() {
        settingsScope.cancel()
        database.close()
        root.toFile().deleteRecursively()
        cache.deleteRecursively()
    }

    @Test fun aRestoredEpubIsStagedInTheCacheAndRemoved() = runBlocking {
        val seen = mutableListOf<File>()
        withContext(CacheStaging.Probe(seen)) {
            repository.importV2ZipBytes(archive())
        }
        assertEquals(1, database.workDao().getAll().size)
        assertTrue(files.workEpubExists(WORK_ID))
        assertTrue(seen.isNotEmpty())
        seen.forEach { staged ->
            assertEquals(cache.canonicalFile, staged.parentFile.canonicalFile)
            assertFalse(staged.exists())
        }
    }

    @Test fun fontValidationIsStagedInTheCacheAndRemoved() = runBlocking {
        val seen = mutableListOf<File>()
        withContext(CacheStaging.Probe(seen)) {
            runCatching { repository.importV2ZipBytes(fontArchive()) }
        }
        val staged = seen.single()
        assertEquals(cache.canonicalFile, staged.parentFile.canonicalFile)
        assertFalse(staged.exists())
    }

    private fun archive(): ByteArray = BackupExporter.exportV2(KudosBackupPackage(
        manifest = KudosBackupManifest(
            version = 8,
            exportedAt = "2024-01-02T03:04:05Z",
            works = listOf(BackupWork(id = WORK_ID, title = "Kept", author = "Author", hasEPUB = true, isSaved = true))
        ),
        epubFilesByWorkId = mapOf(WORK_ID to EpubBuilder.buildEpub("Kept", "<p>Kept.</p>"))
    ))

    private fun fontArchive(): ByteArray = BackupExporter.exportV2(KudosBackupPackage(
        manifest = KudosBackupManifest(
            version = 8,
            exportedAt = "2024-01-02T03:04:05Z",
            fonts = listOf(BackupFont(name = "Reader", fileName = "Reader.ttf", dateAdded = "2024-01-02T03:04:05Z"))
        ),
        fontFilesByFileName = mapOf("Reader.ttf" to minimalSfnt())
    ))

    /**
     * Big-endian sfnt that passes [BackupFontValidator]'s structure check, so validation
     * reaches the temp file. Eight tables, directory ending at 140, cmap version 0,
     * head magic 0x5F0F3CF5.
     */
    private fun minimalSfnt(): ByteArray {
        val out = ByteArray(166)
        fun u16(at: Int, value: Int) {
            out[at] = (value ushr 8).toByte()
            out[at + 1] = value.toByte()
        }
        fun u32(at: Int, value: Long) {
            out[at] = (value ushr 24).toByte()
            out[at + 1] = (value ushr 16).toByte()
            out[at + 2] = (value ushr 8).toByte()
            out[at + 3] = value.toByte()
        }
        u32(0, 0x00010000)
        u16(4, 8)
        listOf(
            "cmap" to (140 to 4),
            "head" to (144 to 16),
            "hhea" to (160 to 1),
            "hmtx" to (161 to 1),
            "maxp" to (162 to 1),
            "name" to (163 to 1),
            "glyf" to (164 to 1),
            "loca" to (165 to 1)
        ).forEachIndexed { index, (tag, place) ->
            val entry = 12 + index * 16
            tag.toByteArray(Charsets.US_ASCII).copyInto(out, entry)
            u32(entry + 8, place.first.toLong())
            u32(entry + 12, place.second.toLong())
        }
        u32(156, 0x5F0F3CF5)
        return out
    }

    private companion object {
        const val WORK_ID = "22222222-2222-4222-8222-222222222222"
    }
}
