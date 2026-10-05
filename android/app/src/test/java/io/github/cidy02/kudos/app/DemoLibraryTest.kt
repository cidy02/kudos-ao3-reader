package io.github.cidy02.kudos.app

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.core.model.MatureContentMode
import io.github.cidy02.kudos.core.model.PrivacySettings
import io.github.cidy02.kudos.account.AccountListType
import io.github.cidy02.kudos.account.visibleEntries
import io.github.cidy02.kudos.account.SubscriptionWatermarks
import io.github.cidy02.kudos.backup.KeyRevocationReason
import io.github.cidy02.kudos.backup.KeyRevocationService
import io.github.cidy02.kudos.backup.TombstoneSigning
import io.github.cidy02.kudos.backup.TombstoneTrustStore
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.library.LibraryFilterState
import io.github.cidy02.kudos.library.LibraryQuery
import io.github.cidy02.kudos.library.LibraryRepository
import io.github.cidy02.kudos.library.LibrarySort
import io.github.cidy02.kudos.library.LibraryPrivacy
import io.github.cidy02.kudos.library.LibraryPrivacyVisibility
import io.github.cidy02.kudos.network.ao3.DemoNetworkRoutes
import io.github.cidy02.kudos.network.ao3.account.AO3AccountParser
import io.github.cidy02.kudos.network.ao3.search.AO3SearchParser
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataParser
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.reader.ReaderSectionBuilder
import io.github.cidy02.kudos.reader.ReaderSectionKind
import io.github.cidy02.kudos.reader.storyChapterCount
import io.github.cidy02.kudos.works.converters.EpubBuilder
import io.github.cidy02.kudos.works.CanonicalWorkMerge
import java.nio.file.Files
import java.nio.file.Path
import java.time.Instant
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
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
import org.jsoup.Jsoup
import org.jsoup.parser.Parser

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class DemoLibraryTest {
    private lateinit var database: KudosDatabase
    private lateinit var workRepository: WorkRepository
    private lateinit var queueRepository: ReadingQueueRepository
    private lateinit var fileStore: WorkFileStore
    private lateinit var tempDir: Path
    private lateinit var context: Context
    private lateinit var settingsRepository: SettingsRepository
    private lateinit var settingsScope: CoroutineScope
    private val fixedNow = Instant.parse("2026-07-31T12:00:00Z")

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        context.getSharedPreferences("ao3_subscription_watermarks", Context.MODE_PRIVATE).edit().clear().commit()
        context.getSharedPreferences("kudos_demo_fixtures", Context.MODE_PRIVATE).edit().clear().commit()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        tempDir = Files.createTempDirectory("kudos-demo-test")
        settingsScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        settingsRepository = SettingsRepository(PreferenceDataStoreFactory.create(
            scope = settingsScope,
            produceFile = { tempDir.resolve("settings.preferences_pb").toFile() }
        ))
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
        settingsScope.cancel()
        TombstoneSigning.resetForTests()
        context.getSharedPreferences("ao3_subscription_watermarks", Context.MODE_PRIVATE).edit().clear().commit()
        context.getSharedPreferences("kudos_demo_fixtures", Context.MODE_PRIVATE).edit().clear().commit()
        tempDir.toFile().deleteRecursively()
    }

    @Test
    fun demoListLinksUpgradeExistingRowsAndKeepReadingState() = runTest {
        DemoLibrary.seed(database, workRepository, queueRepository, fileStore, clock = { fixedNow })
        val rows = database.workDao().getAll()
        val sodium = workRepository.getWork(rows.single { it.title == "Sodium Lights" }.id)!!
        val ashfall = workRepository.getWork(rows.single { it.title == "Ashfall" }.id)!!
        assertEquals("My Series", sodium.seriesTitle)
        assertEquals(1, sodium.seriesPosition)
        assertEquals(999, sodium.ao3SeriesID)
        assertEquals("https://archiveofourown.org/series/999", sodium.seriesUrl)
        val fixture = DemoNetworkRoutes.fixtureName("/series/999")!!
        val html = context.assets.open("fixtures/$fixture.html").bufferedReader().use { it.readText() }
        val first = AO3SearchParser().parseSearchPage(html, 1).works.first()
        assertEquals(sodium.title, first.title)
        assertEquals(sodium.seriesUrl, first.seriesUrl)
        assertEquals(sodium.seriesPosition, first.seriesPosition)
        assertEquals("https://archiveofourown.org/works/999000003", ashfall.sourceUrl)
        assertEquals(999000003, ashfall.ao3WorkID)

        // Emulate 3aj's installed demo, with later reading changes that must survive the upgrade.
        val oldSodium = workRepository.upsert(sodium.copy(
            seriesTitle = "", seriesPosition = 0, seriesUrl = "", ao3SeriesID = null,
            lastScrollFraction = 0.87, legacyReaderProgress = 0.87, isFavorite = false
        ))
        val oldAshfall = workRepository.upsert(ashfall.copy(
            sourceUrl = "", ao3WorkID = null, isFinished = true, knownChapterCount = 9
        ))
        DemoLibrary.seed(database, workRepository, queueRepository, fileStore, clock = { fixedNow })
        val linkedSodium = workRepository.getWork(sodium.id)!!
        val linkedAshfall = workRepository.getWork(ashfall.id)!!
        assertEquals(oldSodium.copy(
            seriesTitle = sodium.seriesTitle, seriesPosition = sodium.seriesPosition,
            seriesUrl = sodium.seriesUrl, ao3SeriesID = sodium.ao3SeriesID,
            searchText = sodium.searchText // The repository rebuilds its derived series search text.
        ), linkedSodium)
        assertEquals(oldAshfall.copy(
            sourceUrl = ashfall.sourceUrl, ao3WorkID = ashfall.ao3WorkID, hasAo3WorkId = true
        ), linkedAshfall)
        DemoLibrary.seed(database, workRepository, queueRepository, fileStore, clock = { fixedNow })
        assertEquals(linkedSodium, workRepository.getWork(sodium.id))
        assertEquals(linkedAshfall, workRepository.getWork(ashfall.id))
        assertEquals(16, database.workDao().getAllIncludingDeleted().size)
        assertEquals(4, queueRepository.listQueues().size)
    }

    @Test
    fun demoBookmarkPairsWithTheMatureLibraryWorkAndBlursUntilRevealed() = runTest {
        DemoLibrary.seed(database, workRepository, queueRepository, fileStore, clock = { fixedNow })
        val local = database.workDao().getAll().map { workRepository.getWork(it.id)!! }
        val path = "/users/AO3_Reader/bookmarks"
        val fixture = DemoNetworkRoutes.fixtureName(path)!!
        val html = context.assets.open("fixtures/$fixture.html").bufferedReader().use { it.readText() }
        val page = AO3AccountParser().parseAccountList(html, 1, AccountListType.Bookmarks)
        val paired = CanonicalWorkMerge.remoteLed(page.works, local).single { it.local != null }
        val work = paired.local!!
        assertEquals("Ashfall", work.title)
        assertEquals("Mature", work.rating)
        assertEquals(999000003L, paired.remote.id)
        assertEquals(work.chapters, paired.remote.chapters)
        assertEquals(work.wordCount, paired.remote.wordCount)
        assertTrue(work.hasEpub && work.isSaved && work.hasAo3WorkId)
        assertTrue(fileStore.workEpubExists(work.id))
        assertEquals(7, work.knownChapterCount)
        assertEquals(0.63, work.lastScrollFraction, 0.0)
        val privacy = PrivacySettings(hideMatureContent = true, matureContentMode = MatureContentMode.Obscure)
        val visible = visibleEntries(listOf(paired), privacy, PrivacyRevealState()).single()
        assertEquals(work.id, visible.local!!.id)
        assertEquals(LibraryPrivacyVisibility.Obscured, LibraryPrivacy.visibility(work, privacy))
        assertEquals(LibraryPrivacyVisibility.Visible, LibraryPrivacy.visibility(
            work, privacy, PrivacyRevealState(revealedIds = setOf(work.id))
        ))
        assertTrue(page.bookmarkDetails.any { it.id == 503L })
    }

    @Test
    fun searchFixtureHasSeparateChaptersAndOriginalSearchTermsEvenOnAnExistingDemo() = runTest {
        DemoLibrary.seed(database, workRepository, queueRepository, fileStore, clock = { fixedNow })
        val works = database.workDao().getAll()
        val journey = works.single { it.title == "The Long Way Down" }
        val sodium = works.single { it.title == "Sodium Lights" }
        assertEquals("7/18", journey.chapters)

        fun verifySearchEpub() {
            ZipFile(fileStore.workEpubPath(journey.id).toFile()).use { zip ->
                fun text(name: String) = zip.getInputStream(zip.getEntry(name)).bufferedReader().use { it.readText() }
                assertEquals("mimetype", zip.entries().nextElement().name)
                assertEquals(ZipEntry.STORED, zip.getEntry("mimetype").method)
                val opf = Jsoup.parse(text("OEBPS/content.opf"), "", Parser.xmlParser())
                val hrefs = opf.select("spine itemref").map { ref ->
                    opf.selectFirst("manifest item[id=${ref.attr("idref")}]")!!.attr("href")
                }
                assertEquals(9, hrefs.size)
                val nav = Jsoup.parse(text("OEBPS/nav.xhtml"), "", Parser.xmlParser()).select("nav a")
                assertEquals(hrefs, nav.map { it.attr("href") })
                val ncx = Jsoup.parse(text("OEBPS/toc.ncx"), "", Parser.xmlParser())
                assertEquals(hrefs, ncx.select("navPoint content").map { it.attr("src") })
                val sections = ReaderSectionBuilder.build(
                    nav.mapIndexed { index, link -> ReaderSectionBuilder.RawTOCEntry(link.text(), index) }, hrefs
                )
                assertEquals(7, sections.storyChapterCount)
                assertEquals(ReaderSectionKind.PREFACE, sections.first().kind)
                assertEquals(ReaderSectionKind.AFTERWORD, sections.last().kind)
                assertEquals((1..7).toList(), sections.filter { it.kind == ReaderSectionKind.CHAPTER }.map { it.storyChapterIndex })
                val bodies = hrefs.map { Jsoup.parse(text("OEBPS/$it")).body().text().lowercase() }
                assertTrue(bodies.all { Regex("\\blantern\\b").containsMatchIn(it) })
                assertEquals(listOf(2, 6), bodies.indices.filter { Regex("\\bcompass\\b").containsMatchIn(bodies[it]) })
                assertTrue(Regex("\\ba\\b").findAll(bodies[3]).count() > 200)
            }
        }
        verifySearchEpub()
        ZipFile(fileStore.workEpubPath(sodium.id).toFile()).use { zip ->
            val opf = zip.getInputStream(zip.getEntry("OEBPS/content.opf")).bufferedReader().use { it.readText() }
            assertEquals(1, Jsoup.parse(opf, "", Parser.xmlParser()).select("spine itemref").size)
        }
        // An emulator that already has the old demo must gain the fixture too.
        fileStore.writeWorkEpub(journey.id, EpubBuilder.buildEpub(journey.title, "<p>Old demo.</p>"))
        DemoLibrary.seed(database, workRepository, queueRepository, fileStore, clock = { fixedNow })
        verifySearchEpub()
        assertEquals(journey.lastSpineIndex, database.workDao().getAll().single { it.id == journey.id }.lastSpineIndex)
    }

    @Test
    fun subscriptionFixturesHaveTwoUnreadWorksAndOneSeenWorkAndKeepMarkAllSeen() = runTest {
        DemoLibrary.seed(database, workRepository, queueRepository, fileStore, context, settingsRepository, { fixedNow })
        val works = listOf(
            Triple(45678901L, "ao3_demo_subscription_pink", "5/?"),
            Triple(12345L, "ao3_demo_subscription_another", "8/12"),
            Triple(999000002L, "ao3_demo_subscription_cranes", "1/1")
        ).map { (id, fixture, chapters) ->
            val html = context.assets.open("fixtures/$fixture.html").bufferedReader().use { it.readText() }
            val metadata = AO3WorkMetadataParser().parse(html)
            assertEquals(chapters, metadata.chapters)
            AO3WorkSummary(id, fixture, emptyList(), metadata.fandoms, metadata.rating, metadata.warnings, metadata.categories,
                chapters = metadata.chapters)
        }
        val namespace = SubscriptionWatermarks.NAMESPACE_SUBSCRIPTIONS
        val watermarks = SubscriptionWatermarks.baseline(context, namespace, works)
        assertEquals(listOf(2, 3, 0), works.map { SubscriptionWatermarks.newChapterCount(it, watermarks) })
        SubscriptionWatermarks.markAllSeen(context, namespace, works)
        DemoLibrary.seed(database, workRepository, queueRepository, fileStore, context, settingsRepository, { fixedNow })
        val after = SubscriptionWatermarks.load(context, namespace)
        assertEquals(listOf(0, 0, 0), works.map { SubscriptionWatermarks.newChapterCount(it, after) })
    }

    @Test
    fun pairedDemoDeviceIsDisposableAndRevokeSurvivesReseedingForBothReasons() = runTest {
        for (reason in KeyRevocationReason.entries) {
            context.getSharedPreferences("kudos_demo_fixtures", Context.MODE_PRIVATE).edit().clear().commit()
            DemoLibrary.seed(database, workRepository, queueRepository, fileStore, context, settingsRepository, { fixedNow })
            val trustStore = TombstoneTrustStore(settingsRepository) { fixedNow }
            val device = trustStore.trustedDevices().single()
            assertEquals("Demo reading tablet", device.label)
            assertEquals(Instant.parse("2026-07-01T12:00:00Z"), device.trustedAt)
            assertNotNull(TombstoneSigning.normalizePublicKeyHex(device.publicKeyHex))
            assertFalse(TombstoneSigning.isOwnPublicKey(device.publicKeyHex))
            assertTrue(trustStore.isTrusted(device.publicKeyHex))
            assertTrue(java.time.Duration.between(device.trustedAt, fixedNow) > trustStore.undoWindow)
            DemoLibrary.seed(database, workRepository, queueRepository, fileStore, context, settingsRepository, { fixedNow })
            assertEquals(listOf(device), trustStore.trustedDevices())
            val revocation = KeyRevocationService(trustStore, database, workRepository)
            assertEquals(0, revocation.worksDeletedByCount(device.publicKeyHex))
            assertTrue(revocation.revoke(device.publicKeyHex, reason))
            assertEquals(0, revocation.restoreWorksDeletedBy(device.publicKeyHex))
            assertFalse(trustStore.isTrusted(device.publicKeyHex))
            assertEquals(reason == KeyRevocationReason.STOLEN_OR_COMPROMISED,
                device.publicKeyHex in settingsRepository.revokedTombstonePublicKeysSnapshot())
            DemoLibrary.seed(database, workRepository, queueRepository, fileStore, context, settingsRepository, { fixedNow })
            assertTrue(trustStore.trustedDevices().isEmpty())
        }
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

    @Test
    fun demoLibraryShelfCountsMatchIos() = runTest {
        DemoLibrary.seed(
            database = database,
            workRepository = workRepository,
            readingQueueRepository = queueRepository,
            fileStore = fileStore,
            clock = { fixedNow }
        )

        val libraryRepository = LibraryRepository(workRepository)
        val snapshot = libraryRepository.observeSnapshot().first()
        val state = LibraryQuery.buildState(
            snapshot = snapshot,
            searchQuery = "",
            filters = LibraryFilterState(),
            sort = LibrarySort.RecentlyAdded
        )

        // Reading Now 3, Saved for Later 2, Finished 2: iOS rules (LibrarySectionKind.swift) on a fresh demo seed
        assertEquals(3, state.continueReading.size)
        assertEquals(2, state.savedForLater.size)
        assertEquals(2, state.finished.size)

        assertEquals(
            listOf("Sodium Lights", "Ashfall", "Winter Garden"),
            state.continueReading.map { it.item.work.title }
        )
        assertEquals(
            listOf("Paper Cranes", "Stars Over Tatooine"),
            state.savedForLater.map { it.item.work.title }
        )
        assertTrue(state.finished.any { it.item.work.title == "Tea in the Jasmine Dragon" })
        // Lighthouse Hours is finished but held only by the Case fic pile queue (queue-only).
        assertTrue(state.finished.none { it.item.work.title == "Lighthouse Hours" })
        assertTrue(state.finished.any { it.item.work.title == "What the River Keeps" })
    }
}
