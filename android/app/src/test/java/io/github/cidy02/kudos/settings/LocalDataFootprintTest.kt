package io.github.cidy02.kudos.settings

import android.app.Application
import android.content.Context
import android.os.Looper
import android.system.Os
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.app.DemoLibrary
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.files.FontFileStore
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.network.ao3.browse.AO3Fandom
import io.github.cidy02.kudos.network.ao3.browse.FandomCatalogCache
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.network.ao3.writing.recovery.WritingTextRecovery
import io.github.cidy02.kudos.search.SavedSearchRepository
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.works.converters.EpubBuilder
import java.nio.file.Files
import java.nio.file.Path
import java.util.Locale
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class)
class LocalDataFootprintTest {
    private lateinit var database: KudosDatabase
    private lateinit var files: WorkFileStore
    private lateinit var works: WorkRepository
    private lateinit var scanner: LocalDataFootprintScanner
    private val root = Files.createTempDirectory("kudos-footprint")
    private val cacheRoot = root.resolve("cache")
    private val queryThreads = CopyOnWriteArrayList<Thread>()

    @Before fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            // No allowMainThreadQueries: measuring from the main test thread must dispatch IO.
            .setQueryCallback({ _, _ -> queryThreads.add(Thread.currentThread()) }, { it.run() }).build()
        files = WorkFileStore(root)
        works = WorkRepository(database, files)
        scanner = LocalDataFootprintScanner(database, works, root, cacheRoot)
    }

    @After fun tearDown() { database.close(); root.toFile().deleteRecursively() }

    private suspend fun work(kept: Boolean = false, positioned: Boolean = false): SavedWork {
        val row = SavedWork(id = UUID.randomUUID().toString(), title = "Measured work", author = "reader",
            sourceUrl = "https://archiveofourown.org/works/123", isSaved = kept, hasEpub = true,
            lastSpineIndex = if (positioned) 2 else 0)
        files.writeWorkEpub(row.id, EpubBuilder.buildEpub(row.title, "<p>A real local chapter.</p>"))
        return works.upsert(row)
    }

    private fun allocated(path: Path): Long {
        val logical = Files.size(path)
        return runCatching {
            val stat = Os.stat(path.toString())
            if (stat.st_blksize > 0 && stat.st_blocks >= 0) stat.st_blocks * 512L else logical
        }.getOrDefault(logical)
    }

    @Test fun measuresEveryCategoryAndRealRowsWithTheIosSubtractionRule() = runBlocking<Unit> {
        val kept = work(kept = true)
        val reading = work(positioned = true)
        files.writeOriginal(kept.id, "txt", "An original chapter before EPUB conversion.".toByteArray())
        FontFileStore(root).writeFont("Local.otf", byteArrayOf(79, 84, 84, 79, 1, 2, 3, 4))
        val draftFile = withContext(Dispatchers.IO) {
            val recovery = WritingTextRecovery.inFilesDir(root)
            val path = recovery.fileURL("reader", "work:123", "summary")
            recovery.save("An unpublished summary.", "", path)
            path
        }
        val cache = FandomCatalogCache(cacheRoot)
        cache.save(mapOf("TV" to FandomCatalogCache.Entry(listOf(AO3Fandom("Doctor Who", 42)), 1)))
        val collection = works.createCollection("Live shelf")
        val deleted = works.createCollection("Deleted shelf")
        works.softDeleteCollection(deleted.id)
        SavedSearchRepository(database.savedSearchDao()).save("Named search", AO3SearchFilters(query = "city"))
        val measured = scanner.measure()
        val readingBytes = Files.size(files.workEpubPath(reading.id))
        assertEquals(readingBytes, measured.readingCopyBytes)
        assertEquals((allocated(files.workEpubPath(kept.id)) + allocated(files.workEpubPath(reading.id)) - readingBytes)
            .coerceAtLeast(0), measured.downloadedWorkBytes)
        assertEquals(allocated(files.originalFile(kept.id)!!), measured.preservedOriginalBytes)
        assertEquals(allocated(root.resolve("fonts/Local.otf")), measured.importedFontBytes)
        assertEquals(allocated(draftFile), measured.draftRecoveryBytes)
        assertEquals(allocated(cacheRoot.resolve("fandom-catalog.json")), measured.cacheBytes)
        assertEquals(1, measured.readingPositions)
        assertEquals(1, measured.localCollections)
        assertEquals(1, measured.savedSearches)
        assertNotNull(database.collectionDao().getById(collection.id))
        assertTrue(queryThreads.isNotEmpty())
        assertTrue(queryThreads.none { it == Looper.getMainLooper().thread })
    }

    @Test fun addingFilesChangesEachFigureAndHiddenFilesAndUnrelatedCachesDoNotCount() = runBlocking<Unit> {
        val first = scanner.measure()
        val kept = work(kept = true)
        assertTrue(scanner.measure().downloadedWorkBytes > first.downloadedWorkBytes)
        work()
        val second = scanner.measure()
        assertTrue(second.readingCopyBytes > first.readingCopyBytes)
        files.writeOriginal(kept.id, "txt", "Kept original".toByteArray())
        assertTrue(scanner.measure().preservedOriginalBytes > first.preservedOriginalBytes)
        FontFileStore(root).writeFont("Test.ttf", "Font bytes for a filesystem measurement".toByteArray())
        assertTrue(scanner.measure().importedFontBytes > first.importedFontBytes)
        withContext(Dispatchers.IO) {
            val recovery = WritingTextRecovery.inFilesDir(root)
            recovery.save("Draft", "", recovery.fileURL("reader", "work:123", "notes"))
        }
        assertTrue(scanner.measure().draftRecoveryBytes > first.draftRecoveryBytes)
        FandomCatalogCache(cacheRoot).save(mapOf("TV" to FandomCatalogCache.Entry(listOf(AO3Fandom("Doctor Who")), 1)))
        val beforeHidden = scanner.measure()
        assertTrue(beforeHidden.cacheBytes > first.cacheBytes)
        Files.write(root.resolve("works/.hidden"), ByteArray(800))
        Files.createDirectories(root.resolve("fonts/.scratch"))
        Files.write(root.resolve("fonts/.scratch/ignored.ttf"), ByteArray(800))
        Files.write(cacheRoot.resolve("voice-pack.tmp"), ByteArray(800))
        Files.createDirectories(cacheRoot.resolve("comment_threads"))
        Files.write(cacheRoot.resolve("comment_threads/anon_work_123_p1.json"), "{}".toByteArray())
        assertEquals(beforeHidden, scanner.measure())
        work(positioned = true)
        works.createCollection("New shelf")
        SavedSearchRepository(database.savedSearchDao()).save("New search", AO3SearchFilters(query = "city"))
        val withRecords = scanner.measure()
        assertEquals(first.readingPositions + 1, withRecords.readingPositions)
        assertEquals(first.localCollections + 1, withRecords.localCollections)
        assertEquals(first.savedSearches + 1, withRecords.savedSearches)
    }

    @Test fun hidesOnlyIosConditionalRowsAtZeroAndFormatsCountsAndDecimalBytes() {
        val zero = LocalStorageFootprint(0, 0, 0, 0, 0, 0, 0, 0, 0)
        assertEquals(listOf("Downloaded works", "Draft recovery", "Caches"), zero.sizeRows().map { it.first })
        assertEquals(listOf("Downloaded works", "Works you're reading", "Original files kept", "Imported fonts", "Draft recovery", "Caches"),
            zero.copy(readingCopyBytes = 1, preservedOriginalBytes = 1, importedFontBytes = 1).sizeRows().map { it.first })
        val previous = Locale.getDefault()
        try {
            Locale.setDefault(Locale.US)
            assertEquals("0 bytes", LocalStorageFootprint.formatted(-1))
            assertEquals("1 byte", LocalStorageFootprint.formatted(1))
            assertEquals("1 KB", LocalStorageFootprint.formatted(1_000))
            assertEquals("1.5 MB", LocalStorageFootprint.formatted(1_500_000))
            assertEquals("1 work", countLabel(1, "work"))
            assertEquals("0 works", countLabel(0, "work"))
            assertEquals("2 Positions", countLabel(2, "Position"))
        } finally { Locale.setDefault(previous) }
    }

    @Test fun demoSelectionReallyGivesEveryMeasuredCategoryANonzeroValueAndReseedingPreservesIt() = runBlocking<Unit> {
        DemoLibrary.seed(database, works, ReadingQueueRepository(database), files)
        // A real filesystem font entry is supplied to the seeder on JVMs without /system/fonts;
        // the device demo copies an existing system TTF, never downloads or invents a font.
        val source = Files.write(root.resolve("test-font.ttf"), "Filesystem font fixture".toByteArray())
        DemoLibrary.seedPrivacyData(database, root, cacheRoot, fontSource = source)
        val measured = scanner.measure()
        assertTrue(measured.sizeRows().size == 6)
        assertTrue(measured.sizeRows().all { it.second > 0 })
        assertTrue(measured.readingPositions > 0)
        assertTrue(measured.localCollections > 0)
        assertTrue(measured.savedSearches > 0)
        val active = works.observeLibraryWorks().first()
        assertTrue(active.any { it.title == "Tea in the Jasmine Dragon" && it.hasEpub && !it.isDownloaded })
        assertTrue(active.any { it.title == "Ashfall" && it.isDownloaded })
        DemoLibrary.seedPrivacyData(database, root, cacheRoot, fontSource = source)
        assertEquals(measured, scanner.measure())
    }
}
