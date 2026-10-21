package io.github.cidy02.kudos.files

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.ReaderFontCatalog
import io.github.cidy02.kudos.backup.BackupLimits
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import java.io.File
import java.nio.file.Files
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
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
class CustomFontRepositoryTest {
    private lateinit var database: KudosDatabase
    private lateinit var fontRoot: File
    private lateinit var fontFileStore: FontFileStore
    private lateinit var settingsRepository: SettingsRepository
    private lateinit var dataStoreScope: CoroutineScope
    private lateinit var repository: CustomFontRepository

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        fontRoot = Files.createTempDirectory("kudos-fonts-test").toFile()
        fontFileStore = FontFileStore(fontRoot.toPath())
        dataStoreScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val dataStore = PreferenceDataStoreFactory.create(
            scope = dataStoreScope,
            produceFile = {
                File(fontRoot, "settings.preferences_pb")
            }
        )
        settingsRepository = SettingsRepository(dataStore)
        repository = CustomFontRepository(
            customFontDao = database.customFontDao(),
            fontFileStore = fontFileStore,
            settingsRepository = settingsRepository
        )
    }

    @After
    fun tearDown() {
        database.close()
        dataStoreScope.cancel()
        fontRoot.deleteRecursively()
    }

    @Test
    fun importWritesFileMetadataAndSelectsCustomId() = runBlocking {
        val result = repository.importFont(
            displayName = "Reader Serif",
            originalFileName = "Reader.ttf",
            bytes = validFont()
        )
        assertTrue(result.isSuccess)
        val font = result.getOrThrow()

        assertEquals("Reader Serif", font.name)
        assertTrue(font.fileName.endsWith(".ttf"))
        assertTrue(font.selectionId.startsWith("custom:"))
        assertEquals("custom:${font.fileName}", font.selectionId)

        assertTrue(fontFileStore.fontExists(font.fileName))
        assertEquals(listOf(font.fileName), repository.listImported().map { it.fileName })
        assertEquals(font.selectionId, settingsRepository.snapshot().reader.readerFontId)

        // Backup contract: selection must round-trip as custom:<fileName>
        val option = ReaderFontCatalog.options(listOf(font)).last()
        assertTrue(option.isCustom)
        assertEquals(font.selectionId, option.id)
    }

    @Test
    fun importRejectsNonFontExtension() = runBlocking {
        val result = repository.importFont(
            displayName = "Not a font",
            originalFileName = "notes.txt",
            bytes = "hello".toByteArray()
        )
        assertTrue(result.isFailure)
        assertTrue(repository.listImported().isEmpty())
        assertEquals("system", settingsRepository.snapshot().reader.readerFontId)
    }

    @Test
    fun deleteImportedRemovesFileAndResetsSelection() = runBlocking {
        val font = repository.importFont(
            displayName = "Temp",
            originalFileName = "Temp.otf",
            bytes = validFont()
        ).getOrThrow()
        assertEquals(font.selectionId, settingsRepository.snapshot().reader.readerFontId)

        repository.deleteImported(font)

        assertTrue(repository.listImported().isEmpty())
        assertFalse(fontFileStore.fontExists(font.fileName))
        assertEquals("system", settingsRepository.snapshot().reader.readerFontId)
    }

    @Test
    fun resolveExtensionOnlyAllowsTtfOtf() {
        assertEquals("ttf", CustomFontRepository.resolveExtension("A.TTF"))
        assertEquals("otf", CustomFontRepository.resolveExtension("path/My Font.otf"))
        assertEquals(null, CustomFontRepository.resolveExtension("font.woff"))
        assertEquals(null, CustomFontRepository.resolveExtension(null))
    }

    private fun validFont(): ByteArray = ApplicationProvider.getApplicationContext<Context>()
        .assets.open("readium/fonts/OpenDyslexic-Regular.otf").use { it.readBytes() }

    @Test
    fun invalidOrOversizedFontsLeaveFilesMetadataAndSelectionUntouched() = runBlocking {
        for (bytes in listOf(ByteArray(0), "not a font".toByteArray(),
            byteArrayOf(0, 1, 0, 0), ByteArray(BackupLimits.MAX_FONT_ENTRY_BYTES.toInt() + 1))) {
            val result = repository.importFont("Rejected", "font.ttf", bytes)
            assertTrue(result.isFailure)
            assertTrue(result.exceptionOrNull()!!.message!!.contains(
                "Keeping it would stop your library backup from restoring."))
            assertTrue(repository.listImported().isEmpty())
            assertEquals("system", settingsRepository.snapshot().reader.readerFontId)
            assertTrue(fontRoot.resolve("fonts").listFiles().orEmpty().isEmpty())
        }
    }

    @Test
    fun totalLimitAcceptsTheBoundaryAndRejectsTheNextFontWithoutChangingSelection() = runBlocking {
        val installed = repository.importFont("Installed", "font.otf", validFont()).getOrThrow()
        val incoming = validFont()
        // Sparse existing file avoids allocating 32 MB just to exercise the disk-size sum.
        java.io.RandomAccessFile(repository.fontPath(installed).toFile(), "rw").use {
            it.setLength(BackupLimits.MAX_TOTAL_FONT_BYTES - incoming.size)
        }
        val boundary = repository.importFont("Boundary", "font.otf", incoming).getOrThrow()
        val before = repository.listImported()
        val result = repository.importFont("Over limit", "font.otf", incoming)
        assertEquals("Your fonts would go over the 32 MB a backup can carry, " +
            "which would stop your library backup from restoring.", result.exceptionOrNull()!!.message)
        assertEquals(before, repository.listImported())
        assertEquals(boundary.selectionId, settingsRepository.snapshot().reader.readerFontId)
        assertEquals(before.size, fontRoot.resolve("fonts").listFiles()!!.size)
    }

    @Test
    fun builtInCatalogIdsMatchBackupSet() {
        assertTrue(ReaderFontCatalog.builtInIds.contains("system"))
        assertTrue(ReaderFontCatalog.builtInIds.contains("georgia"))
        assertTrue(ReaderFontCatalog.builtInIds.contains("menlo"))
        assertFalse(ReaderFontCatalog.builtInIds.any { it.startsWith("custom:") })
    }
}
