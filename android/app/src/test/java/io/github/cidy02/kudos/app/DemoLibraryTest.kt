package io.github.cidy02.kudos.app

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.works.WorkRepository
import java.nio.file.Files
import java.nio.file.Path
import java.time.Instant
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class DemoLibraryTest {
    private lateinit var database: KudosDatabase
    private lateinit var workRepository: WorkRepository
    private lateinit var queueRepository: ReadingQueueRepository
    private lateinit var fileStore: WorkFileStore
    private lateinit var tempDir: Path
    private val fixedNow = Instant.parse("2026-07-31T12:00:00Z")

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        tempDir = Files.createTempDirectory("kudos-demo-test")
        fileStore = WorkFileStore(tempDir)
        workRepository = WorkRepository(
            database = database,
            fileStore = fileStore,
            clock = { fixedNow }
        )
        queueRepository = ReadingQueueRepository(
            database = database,
            clock = { fixedNow }
        )
    }

    @After
    fun tearDown() {
        database.close()
        tempDir.toFile().deleteRecursively()
    }

    @Test
    fun seedPopulatesExpectedWorksQueuesCollectionsAndIsIdempotent() = runTest {
        DemoLibrary.seed(
            database = database,
            workRepository = workRepository,
            readingQueueRepository = queueRepository,
            fileStore = fileStore,
            clock = { fixedNow }
        )

        // Work counts: 14 samples + 1 held copy + 1 soft-deleted = 16 total
        val allWorks = database.workDao().getAllIncludingDeleted()
        assertEquals(16, allWorks.size)

        // 15 active works (14 samples + 1 held copy)
        val activeWorks = database.workDao().getAll()
        assertEquals(15, activeWorks.size)

        // 1 soft-deleted work ("Lanterns Over Ba Sing Se")
        val deletedWorks = database.workDao().getDeleted()
        assertEquals(1, deletedWorks.size)
        assertEquals("Lanterns Over Ba Sing Se", deletedWorks.first().title)

        // Held copy ("Tea in the Jasmine Dragon")
        val heldWork = allWorks.firstOrNull { it.title == "Tea in the Jasmine Dragon" }
        assertNotNull(heldWork)
        assertTrue(heldWork!!.isFinished)
        assertFalse(heldWork.isSaved)
        assertTrue(heldWork.hasEpub)
        assertTrue(fileStore.workEpubExists(heldWork.id))

        // First sample work ("Sodium Lights")
        val sodiumLights = allWorks.firstOrNull { it.title == "Sodium Lights" }
        assertNotNull(sodiumLights)
        assertEquals("nine_of_wands", sodiumLights!!.author)
        assertEquals(62_004, sodiumLights.wordCount)
        assertEquals("1/1", sodiumLights.chapters)
        assertTrue(sodiumLights.isComplete)
        assertEquals(1550, sodiumLights.kudos) // 62004 / 40
        assertEquals(15501, sodiumLights.hits) // 62004 / 4
        assertTrue(sodiumLights.isFavorite)
        assertEquals(0.42, sodiumLights.lastScrollFraction, 0.0)
        assertEquals(1, sodiumLights.lastSpineIndex)
        assertTrue(sodiumLights.hasEpub)
        assertTrue(fileStore.workEpubExists(sodiumLights.id))

        // Off-device works (samples 10 and 13)
        val channelNine = allWorks.firstOrNull { it.title == "Static on Channel Nine" }
        assertNotNull(channelNine)
        assertFalse(channelNine!!.hasEpub)
        assertFalse(fileStore.workEpubExists(channelNine.id))

        val tatooine = allWorks.firstOrNull { it.title == "Stars Over Tatooine" }
        assertNotNull(tatooine)
        assertFalse(tatooine!!.hasEpub)
        assertFalse(fileStore.workEpubExists(tatooine.id))

        // Queues: 3 custom + 1 Saved for Later = 4 queues
        val queues = queueRepository.listQueues()
        assertEquals(4, queues.size)

        val neonReread = queues.firstOrNull { it.name == "Neon reread" }
        assertNotNull(neonReread)
        val neonWorks = queueRepository.listWorks(neonReread!!.id)
        assertEquals(5, neonWorks.size)
        assertEquals(
            listOf("Sodium Lights", "Happy Birthday Diya!!", "The Long Way Down", "Winter Garden", "Every Door in Hades"),
            neonWorks.map { it.title }
        )

        val slowBurns = queues.firstOrNull { it.name == "Slow burns" }
        assertNotNull(slowBurns)
        val slowWorks = queueRepository.listWorks(slowBurns!!.id)
        assertEquals(4, slowWorks.size)
        assertEquals(
            listOf("Unanswered Is Not Unread", "Ashfall", "What the River Keeps", "Night Market"),
            slowWorks.map { it.title }
        )

        val caseFic = queues.firstOrNull { it.name == "Case fic pile" }
        assertNotNull(caseFic)
        val caseWorks = queueRepository.listWorks(caseFic!!.id)
        assertEquals(3, caseWorks.size)
        assertEquals(
            listOf("Burn my heart, heed my eyes", "Lighthouse Hours", "Static on Channel Nine"),
            caseWorks.map { it.title }
        )

        val savedForLater = queues.firstOrNull { it.kindRaw == ReadingQueueKind.SAVED_FOR_LATER }
        assertNotNull(savedForLater)
        val savedWorks = queueRepository.listWorks(savedForLater!!.id)
        assertEquals(2, savedWorks.size)
        assertEquals(
            listOf("Paper Cranes", "Stars Over Tatooine"),
            savedWorks.map { it.title }
        )

        // Collections: 2 active collections
        val collections = workRepository.allCollections()
        assertEquals(2, collections.size)
        val comfortReads = collections.firstOrNull { it.name == "Comfort reads" }
        assertNotNull(comfortReads)
        assertEquals(3, comfortReads!!.workIds.size)

        val toRecommend = collections.firstOrNull { it.name == "To recommend" }
        assertNotNull(toRecommend)
        assertEquals(2, toRecommend!!.workIds.size)

        // Soft-deleted collection ("Summer 2025")
        val deletedCollections = workRepository.listRecentlyDeletedCollections()
        assertEquals(1, deletedCollections.size)
        assertEquals("Summer 2025", deletedCollections.first().name)

        // Second run - idempotency test: running it twice must add nothing
        DemoLibrary.seed(
            database = database,
            workRepository = workRepository,
            readingQueueRepository = queueRepository,
            fileStore = fileStore,
            clock = { fixedNow }
        )

        val allWorksAfterSecondSeed = database.workDao().getAllIncludingDeleted()
        assertEquals(16, allWorksAfterSecondSeed.size)

        val queuesAfterSecondSeed = queueRepository.listQueues()
        assertEquals(4, queuesAfterSecondSeed.size)

        assertEquals(5, queueRepository.listWorks(neonReread.id).size)
        assertEquals(4, queueRepository.listWorks(slowBurns.id).size)
        assertEquals(3, queueRepository.listWorks(caseFic.id).size)
        assertEquals(2, queueRepository.listWorks(savedForLater.id).size)

        assertEquals(2, workRepository.allCollections().size)
        assertEquals(1, workRepository.listRecentlyDeletedCollections().size)
    }
}
