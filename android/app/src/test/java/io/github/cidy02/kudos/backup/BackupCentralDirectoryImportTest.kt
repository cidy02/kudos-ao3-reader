package io.github.cidy02.kudos.backup

import android.app.Application
import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.FontFileStore
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.works.converters.EpubBuilder
import java.io.ByteArrayOutputStream
import java.nio.file.Files
import java.util.zip.ZipOutputStream
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * iOS MiniZip refuses a broken central directory and a truncated ZIP64 extra
 * before anything is written. `ZipInputStream` never reads that directory, so
 * these fixtures used to restore a work.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class)
class BackupCentralDirectoryImportTest {
    private val root = Files.createTempDirectory("central-directory-import")
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
            database, files, FontFileStore(root.resolve("library")), settings, PersistenceGate()
        )
    }

    @After fun tearDown() {
        settingsScope.cancel()
        database.close()
        root.toFile().deleteRecursively()
    }

    @Test fun aRealBackupStillRestores() = runBlocking {
        repository.importV2ZipBytes(archive())
        assertEquals(1, database.workDao().getAll().size)
        assertTrue(files.workEpubExists(WORK_ID))
    }

    @Test fun aBrokenCentralDirectoryIsRefusedBeforeAnyWrite() {
        val broken = breakCentralDirectorySignature(archive())
        val error = assertThrows(BackupError.InvalidPackage::class.java) {
            runBlocking { repository.importV2ZipBytes(broken) }
        }
        assertEquals("The archive's central directory is missing or malformed.", error.message)
        runBlocking {
            assertTrue(database.workDao().getAll().isEmpty())
            assertFalse(files.workEpubExists(WORK_ID))
        }
    }

    @Test fun aTruncatedZip64ExtraIsRefusedBeforeAnyWrite() {
        val broken = saturateEpubSizes(archive(), byteArrayOf(0x01, 0x00, 0x10, 0x00))
        val error = assertThrows(BackupError.InvalidPackage::class.java) {
            runBlocking { repository.importV2ZipBytes(broken) }
        }
        assertEquals("An archive record is truncated or points outside the file.", error.message)
        runBlocking {
            assertTrue(database.workDao().getAll().isEmpty())
            assertFalse(files.workEpubExists(WORK_ID))
        }
    }

    @Test fun aSaturatedEndOfCentralDirectoryWithoutZip64IsRefusedBeforeAnyWrite() {
        val bytes = archive()
        val eocd = eocdOffset(bytes)
        writeU16(bytes, eocd + 8, 0xFFFF)
        writeU16(bytes, eocd + 10, 0xFFFF)
        val error = assertThrows(BackupError.InvalidPackage::class.java) {
            runBlocking { repository.importV2ZipBytes(bytes) }
        }
        assertEquals("The archive's central directory is missing or malformed.", error.message)
        runBlocking {
            assertTrue(database.workDao().getAll().isEmpty())
            assertFalse(files.workEpubExists(WORK_ID))
        }
    }

    @Test fun aWellFormedZip64ExtraStillRestores() = runBlocking {
        val original = archive()
        val record = epubCentralRecord(original)
        val compressed = u32(original, record + 20)
        val uncompressed = u32(original, record + 24)
        val extra = ByteArray(20)
        writeU16(extra, 0, 1)
        writeU16(extra, 2, 16)
        writeU64(extra, 4, uncompressed)
        writeU64(extra, 12, compressed)
        repository.importV2ZipBytes(saturateEpubSizes(original, extra))
        assertEquals(1, database.workDao().getAll().size)
        assertTrue(files.workEpubExists(WORK_ID))
    }

    @Test fun anEmptyArchiveIsStillAMissingManifest() {
        val output = ByteArrayOutputStream()
        ZipOutputStream(output).close()
        assertThrows(BackupError.MissingManifest::class.java) {
            BackupImporter.importV2Zip(output.toByteArray())
        }
    }

    private fun archive(): ByteArray = BackupExporter.exportV2(KudosBackupPackage(
        manifest = KudosBackupManifest(
            version = 8,
            exportedAt = "2024-01-02T03:04:05Z",
            works = listOf(BackupWork(id = WORK_ID, title = "Kept", author = "Author", hasEPUB = true, isSaved = true))
        ),
        epubFilesByWorkId = mapOf(WORK_ID to EpubBuilder.buildEpub("Kept", "<p>Kept.</p>"))
    ))

    private companion object {
        const val WORK_ID = "11111111-1111-4111-8111-111111111111"
    }
}

private fun breakCentralDirectorySignature(bytes: ByteArray): ByteArray {
    val copy = bytes.copyOf()
    val start = centralDirectoryStart(copy)
    check(copy[start] == 0x50.toByte() && copy[start + 1] == 0x4b.toByte() &&
        copy[start + 2] == 0x01.toByte() && copy[start + 3] == 0x02.toByte())
    copy[start] = copy[start].toInt().xor(0xFF).toByte()
    return copy
}

/** CEN sizes become 0xFFFFFFFF and the extra area is replaced. Local headers stay readable. */
private fun saturateEpubSizes(bytes: ByteArray, extra: ByteArray): ByteArray {
    val record = epubCentralRecord(bytes)
    val nameLength = u16(bytes, record + 28)
    val extraLength = u16(bytes, record + 30)
    val commentLength = u16(bytes, record + 32)
    val nameStart = record + 46
    val name = bytes.copyOfRange(nameStart, nameStart + nameLength)
    val commentStart = nameStart + nameLength + extraLength
    val comment = bytes.copyOfRange(commentStart, commentStart + commentLength)
    val header = bytes.copyOfRange(record, record + 46)
    writeU32(header, 20, 0xFFFFFFFFL)
    writeU32(header, 24, 0xFFFFFFFFL)
    writeU16(header, 30, extra.size)
    val oldLength = 46 + nameLength + extraLength + commentLength
    val eocd = eocdOffset(bytes)
    val before = bytes.copyOfRange(0, record)
    val restOfDirectory = bytes.copyOfRange(record + oldLength, eocd)
    val tail = bytes.copyOfRange(eocd, bytes.size)
    val replacement = header + name + extra + comment
    writeU32(tail, 12, u32(tail, 12) + (replacement.size - oldLength))
    return before + replacement + restOfDirectory + tail
}

private fun epubCentralRecord(bytes: ByteArray): Int {
    val eocd = eocdOffset(bytes)
    val count = u16(bytes, eocd + 10)
    var offset = centralDirectoryStart(bytes)
    var found = -1
    repeat(count) {
        val nameLength = u16(bytes, offset + 28)
        val extraLength = u16(bytes, offset + 30)
        val commentLength = u16(bytes, offset + 32)
        val name = bytes.copyOfRange(offset + 46, offset + 46 + nameLength).toString(Charsets.UTF_8)
        if (name.endsWith(".epub")) found = offset
        offset += 46 + nameLength + extraLength + commentLength
    }
    check(found >= 0) { "archive has no EPUB central-directory record" }
    return found
}

private fun centralDirectoryStart(bytes: ByteArray): Int {
    val eocd = eocdOffset(bytes)
    check(eocd < 20 || u32(bytes, eocd - 20) != 0x07064b50L) { "fixture unexpectedly uses a ZIP64 locator" }
    return u32(bytes, eocd + 16).toInt()
}

private fun eocdOffset(bytes: ByteArray): Int {
    var index = bytes.size - 22
    val lower = maxOf(0, bytes.size - 22 - 65536)
    while (index >= lower) {
        if (u32(bytes, index) == 0x06054b50L) return index
        index -= 1
    }
    error("no end of central directory")
}

private fun u16(bytes: ByteArray, offset: Int): Int =
    (bytes[offset].toInt() and 0xFF) or ((bytes[offset + 1].toInt() and 0xFF) shl 8)

private fun u32(bytes: ByteArray, offset: Int): Long =
    (bytes[offset].toLong() and 0xFF) or
        ((bytes[offset + 1].toLong() and 0xFF) shl 8) or
        ((bytes[offset + 2].toLong() and 0xFF) shl 16) or
        ((bytes[offset + 3].toLong() and 0xFF) shl 24)

private fun writeU16(bytes: ByteArray, offset: Int, value: Int) {
    bytes[offset] = value.toByte()
    bytes[offset + 1] = (value ushr 8).toByte()
}

private fun writeU32(bytes: ByteArray, offset: Int, value: Long) {
    bytes[offset] = value.toByte()
    bytes[offset + 1] = (value ushr 8).toByte()
    bytes[offset + 2] = (value ushr 16).toByte()
    bytes[offset + 3] = (value ushr 24).toByte()
}

private fun writeU64(bytes: ByteArray, offset: Int, value: Long) {
    var remaining = value
    repeat(8) { index ->
        bytes[offset + index] = remaining.toByte()
        remaining = remaining ushr 8
    }
}
