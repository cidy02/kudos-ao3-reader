package io.github.cidy02.kudos.app

import android.content.Context
import android.content.Intent
import androidx.room.withTransaction
import com.google.crypto.tink.subtle.Ed25519Sign
import io.github.cidy02.kudos.network.ao3.AO3URLResolver
import io.github.cidy02.kudos.account.SubscriptionWatermark
import io.github.cidy02.kudos.account.SubscriptionWatermarks
import io.github.cidy02.kudos.backup.TombstoneTrustStore
import io.github.cidy02.kudos.backup.toLowerHex
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.QueueTagCrossRef
import io.github.cidy02.kudos.data.local.entity.TagEntity
import io.github.cidy02.kudos.data.local.entity.WorkEntity
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.works.WorkTags
import io.github.cidy02.kudos.works.converters.EpubBuilder
import java.io.ByteArrayOutputStream
import java.time.Instant
import java.util.UUID
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.nio.file.Files
import java.nio.file.Path
import io.github.cidy02.kudos.files.FontFileStore
import io.github.cidy02.kudos.data.local.entity.CustomFontEntity
import io.github.cidy02.kudos.network.ao3.browse.AO3Fandom
import io.github.cidy02.kudos.network.ao3.browse.FandomCatalogCache
import io.github.cidy02.kudos.network.ao3.writing.recovery.WritingTextRecovery
import io.github.cidy02.kudos.search.SavedSearchRepository
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters

/**
 * Demo library seeder for screenshot testing and visual review.
 * Mirrors iOS DemoLibrary (kudos-ao3-reader/App/DemoLibrary.swift).
 */
object DemoLibrary {
    private val seedMutex = Mutex()

    private data class DemoQueue(
        val name: String,
        val hue: Double,
        val tags: List<String>,
        val works: List<Int>,
        val keepsWorksOffline: Boolean = true
    )

    private data class Sample(
        val title: String,
        val author: String,
        val summary: String = "",
        val fandoms: List<String>,
        val rating: String,
        val warnings: List<String> = listOf("No Archive Warnings Apply"),
        val categories: List<String> = listOf("Gen"),
        val words: Int,
        val chapters: String,
        val progress: Double? = null,
        val finished: Boolean = false,
        val favorite: Boolean = false,
        val kept: Boolean = false,
        val onDevice: Boolean = true,
        val seenChapters: Int? = null,
        val lastReadDaysAgo: Long? = null
    )

    private val SAMPLES = listOf(
        Sample(
            title = "Sodium Lights",
            author = "nine_of_wands",
            summary = "The TARDIS lands in a city that never switches its streetlamps off.",
            fandoms = listOf("Doctor Who (2005)", "Doctor Who"),
            rating = "Teen And Up Audiences",
            words = 62_004,
            chapters = "1/1",
            progress = 0.42,
            favorite = true
        ),
        Sample(
            title = "Unanswered Is Not Unread",
            author = "poknn",
            fandoms = listOf("Avatar: The Last Airbender", "The Legend of Korra"),
            rating = "Teen And Up Audiences",
            categories = listOf("M/M"),
            words = 8_970,
            chapters = "2/?",
            progress = 0.2,
            seenChapters = 1
        ),
        Sample(
            title = "Burn my heart, heed my eyes",
            author = "Kuuakuu",
            fandoms = listOf("NARUTO (Anime & Manga)"),
            rating = "Teen And Up Audiences",
            words = 4_820,
            chapters = "1/?"
        ),
        Sample(
            title = "Happy Birthday Diya!!",
            author = "runsonmatcha",
            fandoms = listOf("僕のヒーローアカデミア | Boku no Hero Academia | My Hero Academia"),
            rating = "Explicit",
            warnings = listOf("Graphic Depictions Of Violence"),
            categories = listOf("F/M"),
            words = 3_150,
            chapters = "1/1",
            progress = 0.0
        ),
        Sample(
            title = "Ashfall",
            author = "TempusFugit",
            fandoms = listOf("Star Wars - All Media Types", "Star Wars: The Clone Wars (2008) - All Media Types"),
            rating = "Mature",
            categories = listOf("M/M"),
            words = 41_780,
            chapters = "9/?",
            progress = 0.63,
            kept = true,
            seenChapters = 7,
            lastReadDaysAgo = 1
        ),
        Sample(
            title = "The Long Way Down",
            author = "velvetstatic",
            fandoms = listOf("Cyberpunk 2077 (Video Game)"),
            rating = "Mature",
            words = 84_120,
            chapters = "7/18",
            progress = 0.35
        ),
        Sample(
            title = "Lighthouse Hours",
            author = "keeper_of_lamps",
            fandoms = listOf("Sherlock (TV)"),
            rating = "General Audiences",
            words = 12_400,
            chapters = "5/5",
            finished = true
        ),
        Sample(
            title = "Paper Cranes",
            author = "origamist",
            fandoms = listOf("Haikyuu!!"),
            rating = "General Audiences",
            words = 2_210,
            chapters = "1/1"
        ),
        Sample(
            title = "Winter Garden",
            author = "frostbitten",
            fandoms = listOf("Frozen (Disney Movies)"),
            rating = "General Audiences",
            categories = listOf("F/F"),
            words = 18_020,
            chapters = "4/6",
            progress = 0.71,
            favorite = true,
            seenChapters = 3,
            lastReadDaysAgo = 30
        ),
        Sample(
            title = "What the River Keeps",
            author = "undertow",
            fandoms = listOf("Les Misérables - Victor Hugo"),
            rating = "Teen And Up Audiences",
            words = 132_500,
            chapters = "30/30",
            finished = true,
            kept = true
        ),
        Sample(
            title = "Static on Channel Nine",
            author = "lowfreq",
            fandoms = listOf("Supernatural"),
            rating = "Mature",
            words = 27_600,
            chapters = "3/?",
            onDevice = false,
            lastReadDaysAgo = 60
        ),
        Sample(
            title = "Every Door in Hades",
            author = "zagreus_fan",
            fandoms = listOf("Hades (Video Game 2018)"),
            rating = "Teen And Up Audiences",
            words = 56_300,
            chapters = "12/20",
            progress = 0.55
        ),
        Sample(
            title = "Night Market",
            author = "lanternlight",
            fandoms = listOf("呪術廻戦 | Jujutsu Kaisen (Manga)"),
            rating = "Teen And Up Audiences",
            words = 9_870,
            chapters = "2/3"
        ),
        Sample(
            title = "Stars Over Tatooine",
            author = "binarysun",
            fandoms = listOf("Star Wars - All Media Types"),
            rating = "General Audiences",
            words = 6_540,
            chapters = "1/1",
            onDevice = false
        )
    )

    suspend fun seed(
        container: KudosAppContainer,
        context: Context,
        clock: () -> Instant = { Instant.now() }
    ) {
        seed(
            database = container.database,
            workRepository = container.workRepository,
            readingQueueRepository = container.readingQueueRepository,
            fileStore = container.workFileStore,
            context = context,
            settingsRepository = container.settingsRepository,
            clock = clock
        )
    }

    suspend fun seedIfRequested(
        container: KudosAppContainer,
        context: Context,
        intent: Intent?,
        clock: () -> Instant = { Instant.now() }
    ): Boolean {
        val isRequested = intent?.getBooleanExtra("kudosDemoLibrary", false) == true ||
            intent?.getStringExtra("kudosDemoLibrary").equals("true", ignoreCase = true)
        if (!isRequested) return false
        seed(container, context, clock)
        return true
    }

    suspend fun seed(
        database: KudosDatabase,
        workRepository: WorkRepository,
        readingQueueRepository: ReadingQueueRepository,
        fileStore: WorkFileStore? = null,
        context: Context? = null,
        settingsRepository: SettingsRepository? = null,
        clock: () -> Instant = { Instant.now() }
    ) {
        seedMutex.withLock {
            // Watermarks must precede metadata enrichment's first-visit baseline.
            if (context != null) seedPreferences(context, settingsRepository)
            database.withTransaction {
                seedContents(database, workRepository, readingQueueRepository, fileStore, clock)
            }
            if (context != null) seedPrivacyData(database, context.filesDir.toPath(), context.cacheDir.toPath(), clock = clock)
        }
    }

    /** Actual local assets, additive on installed demos; never replace recovery or cached data. */
    internal suspend fun seedPrivacyData(
        database: KudosDatabase,
        filesRoot: Path,
        cacheRoot: Path,
        fontSource: Path? = null,
        clock: () -> Instant = { Instant.now() }
    ): Unit = withContext(Dispatchers.IO) {
        val paper = database.workDao().getAll().firstOrNull { it.title == "Paper Cranes" }
        val files = WorkFileStore(filesRoot)
        if (paper != null && !files.originalExists(paper.id)) {
            files.writeOriginal(paper.id, "txt", ("Paper Cranes\nby origamist\n\n" +
                "The city was quiet, but never dark. Streetlamps hummed along the pavement, casting sharp amber shadows across the rain-slicked stones.\n" +
                "Footsteps echoed in the narrow alleyway between old brick buildings. A solitary breeze carried the faint scent of ozone and diesel fuel.\n" +
                "There was a rhythm to this place that refused to sleep, keeping vigil against the stillness of the night.\n").toByteArray())
        }
        val fonts = FontFileStore(filesRoot)
        val fontName = "Privacy-demo.ttf"
        val systemFont = fontSource ?: runCatching {
            Files.newDirectoryStream(java.io.File("/system/fonts").toPath(), "*.ttf").use { fontsOnDevice ->
                fontsOnDevice.filter { Files.isRegularFile(it) }.sortedBy { it.fileName.toString() }.firstOrNull()
            }
        }.getOrNull()
        if (systemFont != null && !fonts.fontExists(fontName)) {
            val result = fonts.writeFont(fontName, Files.readAllBytes(systemFont))
            if (result is io.github.cidy02.kudos.files.FileWriteResult.Success) {
                database.customFontDao().upsert(CustomFontEntity(
                    id = UUID.nameUUIDFromBytes("privacy-demo-font".toByteArray()).toString(),
                    name = "Demo font", fileName = fontName, dateAdded = clock()))
            }
        }
        val recovery = WritingTextRecovery.inFilesDir(filesRoot)
        val key = recovery.fileURL("AO3_Reader", "work:privacy-demo", "summary")
        if (!Files.exists(key)) recovery.save("A city that never turns off its lights.", "", key)
        val cache = FandomCatalogCache(cacheRoot)
        if (!Files.exists(cacheRoot.resolve("fandom-catalog.json"))) {
            // Dated 1970: it is there to be measured, and a fresh date made Browse serve this one fandom
            // as the whole of TV Shows for a week on a launch without the demo (audit A30-9).
            cache.save(mapOf("TV Shows" to FandomCatalogCache.Entry(listOf(AO3Fandom("Doctor Who", 42)), 0L)))
        }
        val searches = SavedSearchRepository(database.savedSearchDao())
        if (searches.getAll().none { it.name == "Demo: Doctor Who" }) {
            searches.save("Demo: Doctor Who", AO3SearchFilters(fandom = "Doctor Who"))
        }
    }

    private suspend fun seedContents(
        database: KudosDatabase,
        workRepository: WorkRepository,
        readingQueueRepository: ReadingQueueRepository,
        fileStore: WorkFileStore?,
        clock: () -> Instant
    ) {
        val allWorks = database.workDao().getAllIncludingDeleted()
        if (allWorks.any { it.title == SAMPLES[0].title }) {
            // Add list fixture links to an installed demo without replacing its reading state.
            for (row in allWorks.filter { it.title in setOf("Sodium Lights", "Ashfall", "Unanswered Is Not Unread", "Burn my heart, heed my eyes") }) {
                val work = workRepository.getWork(row.id) ?: continue
                val linked = withDemoListLinks(work)
                if (linked != work) workRepository.upsert(linked)
            }
            // Upgrade an already-installed demo's old single-spine search fixture.
            allWorks.firstOrNull { it.title == "The Long Way Down" && it.hasEpub }?.let {
                writePlaceholderEpub(it.id, it.title, fileStore)
            }
            // Change only untouched old fixture dates; never replace a user's reading or undo.
            for ((index, sample) in SAMPLES.withIndex()) {
                val age = sample.lastReadDaysAgo ?: continue
                val row = allWorks.firstOrNull { it.title == sample.title } ?: continue
                val work = workRepository.getWork(row.id) ?: continue
                val originalDate = if (sample.progress == null) null else
                    work.dateAdded.plusSeconds(index.toLong() * (3 * 86_400L - 7 * 3_600L))
                if (work.lastReadDate == originalDate && work.lastScrollFraction == (sample.progress ?: 0.0) &&
                    work.readiumLocator == null && !work.keepInProgressOverride && work.isFinished == sample.finished) {
                    // Reconstruct its seed clock, so reseeding cannot keep moving the date.
                    val seededAt = work.dateAdded.plusSeconds(index.toLong() * 3 * 86_400L)
                    val changedAt = clock()
                    workRepository.upsert(work.copy(lastReadDate = seededAt.minusSeconds(age * 86_400L),
                        lastModifiedAt = changedAt, progressModifiedAt = changedAt))
                }
            }
            // Add only missing tags; keep demo row counts and every reading/user flag intact.
            for (row in allWorks) {
                val work = workRepository.getWork(row.id) ?: continue
                val tagged = withDemoAffinityTags(work)
                if (tagged != work) workRepository.upsert(tagged)
            }
            seedRecentlyDeleted(database, workRepository, fileStore, clock)
            return
        }

        val now = clock()
        val seededWorks = mutableListOf<SavedWork>()

        for ((index, sample) in SAMPLES.withIndex()) {
            val chapterParts = sample.chapters.split("/")
            val isComplete = chapterParts.lastOrNull() != "?" &&
                chapterParts.firstOrNull() == chapterParts.lastOrNull()

            val lastReadDate = when {
                sample.lastReadDaysAgo != null -> now.minusSeconds(sample.lastReadDaysAgo * 86_400L)
                sample.progress != null -> now.minusSeconds(index.toLong() * 3_600L * 7L)
                // A finished work was read: without a date it counted as never opened, and
                // Favorites' Authors, Fandoms and Tags (which rank what was read) had two rows.
                sample.finished -> now.minusSeconds((index + 12L) * 86_400L)
                else -> null
            }
            val lastSpineIndex = if (sample.progress != null) 1 else 0
            val lastScrollFraction = sample.progress ?: 0.0

            val work = SavedWork(
                title = sample.title,
                author = sample.author,
                summary = sample.summary,
                sourceUrl = "",
                dateAdded = now.minusSeconds(index.toLong() * 86_400L * 3L),
                isFavorite = sample.favorite,
                isSaved = sample.kept,
                isFinished = sample.finished,
                hasEpub = sample.onDevice,
                isComplete = isComplete,
                rating = sample.rating,
                language = "English",
                wordCount = sample.words,
                chapters = sample.chapters,
                kudos = sample.words / 40,
                hits = sample.words / 4,
                lastSpineIndex = lastSpineIndex,
                lastScrollFraction = lastScrollFraction,
                legacyReaderProgress = sample.progress,
                lastReadDate = lastReadDate,
                workWarnings = sample.warnings,
                workCategories = sample.categories,
                workFandoms = sample.fandoms,
                knownChapterCount = sample.seenChapters
            )

            if (sample.onDevice) {
                writePlaceholderEpub(work.id, work.title, fileStore)
            }

            val savedWork = workRepository.upsert(withDemoAffinityTags(withDemoListLinks(work)))
            seededWorks.add(savedWork)
        }

        val demoQueues = listOf(
            DemoQueue(
                name = "Neon reread",
                hue = 0.78,
                tags = listOf("Rereads", "Long fic"),
                works = listOf(0, 3, 5, 8, 11),
                keepsWorksOffline = true
            ),
            DemoQueue(
                name = "Slow burns",
                hue = 0.07,
                tags = listOf("Comfort", "Long fic"),
                works = listOf(1, 4, 9, 12),
                keepsWorksOffline = true
            ),
            DemoQueue(
                name = "Case fic pile",
                hue = 0.52,
                tags = emptyList(),
                works = listOf(2, 6, 10),
                keepsWorksOffline = false
            )
        )

        for (entry in demoQueues) {
            val queue = readingQueueRepository.createQueue(entry.name)
            // Colour, keep and tags have no repository setter until Edit Queue
            // is ported, so set them on the row directly (debug-only seeding).
            database.readingQueueDao().getQueueById(queue.id)?.let {
                database.readingQueueDao().upsertQueue(
                    it.copy(hue = entry.hue, keepsWorksOffline = entry.keepsWorksOffline)
                )
            }
            for (name in entry.tags) {
                val tag = database.tagDao().getByName(name)
                    ?: TagEntity(id = UUID.randomUUID().toString(), name = name, dateCreated = clock())
                        .also { database.tagDao().upsert(it) }
                database.readingLogDao().upsertQueueTag(QueueTagCrossRef(queueId = queue.id, tagId = tag.id))
            }
            for (index in entry.works) {
                if (index < seededWorks.size) {
                    readingQueueRepository.addWork(queue.id, seededWorks[index].id)
                }
            }
        }

        val savedForLater = readingQueueRepository.ensureSavedForLaterQueue()
        for (index in listOf(7, 13)) {
            if (index < seededWorks.size) {
                readingQueueRepository.addWork(savedForLater.id, seededWorks[index].id)
            }
        }

        val comfortReads = workRepository.createCollection("Comfort reads")
        val toRecommend = workRepository.createCollection("To recommend")
        // As with queues, no repository setter for colour or Show on Home yet.
        for ((id, hue, onHome) in listOf(Triple(comfortReads.id, 0.33, true), Triple(toRecommend.id, 0.62, false))) {
            database.collectionDao().getById(id)?.let {
                database.collectionDao().upsert(it.copy(hue = hue, showsOnHome = onHome))
            }
        }

        for (index in listOf(1, 4, 7)) {
            if (index < seededWorks.size) {
                workRepository.addWorkToCollection(seededWorks[index].id, comfortReads.id)
            }
        }
        for (index in listOf(0, 2)) {
            if (index < seededWorks.size) {
                workRepository.addWorkToCollection(seededWorks[index].id, toRecommend.id)
            }
        }

        seedRecentlyDeleted(database, workRepository, fileStore, clock)
    }

    private fun withDemoAffinityTags(work: SavedWork): SavedWork {
        if (work.workFreeforms.isNotEmpty() || work.workTags.isNotEmpty()) return work
        val tag = when (work.title) {
            "Sodium Lights", "Paper Cranes" -> "Slow Burn"
            // One of them read (Lighthouse Hours is finished), so the tag has a row at all.
            "Unanswered Is Not Unread", "Burn my heart, heed my eyes", "Lighthouse Hours" -> "Fix-It"
            "Winter Garden" -> "Found Family"
            "What the River Keeps" -> "Hurt/Comfort"
            else -> return work
        }
        return work.copy(workFreeforms = listOf(tag))
    }

    private fun withDemoListLinks(work: SavedWork): SavedWork = when {
        work.title == "Sodium Lights" -> work.copy(
            sourceUrl = AO3URLResolver.canonicalWorkUrl(999_000_005L),
            ao3WorkID = 999_000_005,
            seriesTitle = "My Series",
            seriesPosition = 1,
            seriesUrl = "https://archiveofourown.org/series/999",
            ao3SeriesID = 999
        )
        work.title == "Unanswered Is Not Unread" -> work.copy(
            sourceUrl = AO3URLResolver.canonicalWorkUrl(995_110L), ao3WorkID = 995_110,
            seriesTitle = "Letters Across Two Pages", seriesPosition = 1,
            seriesUrl = "https://archiveofourown.org/series/1000", ao3SeriesID = 1000
        )
        work.title == "Burn my heart, heed my eyes" -> work.copy(
            sourceUrl = AO3URLResolver.canonicalWorkUrl(995_120L), ao3WorkID = 995_120,
            seriesTitle = "The Missing Series", seriesPosition = 1,
            seriesUrl = "https://archiveofourown.org/series/1001", ao3SeriesID = 1001
        )
        work.title == "Ashfall" && work.sourceUrl.isBlank() -> work.copy(
            sourceUrl = AO3URLResolver.canonicalWorkUrl(999_000_003L),
            ao3WorkID = 999_000_003
        )
        else -> work
    }

    private suspend fun seedRecentlyDeleted(
        database: KudosDatabase,
        workRepository: WorkRepository,
        fileStore: WorkFileStore?,
        clock: () -> Instant
    ) {
        val title = "Lanterns Over Ba Sing Se"
        val all = database.workDao().getAllIncludingDeleted()
        seedHeldCopy(workRepository, fileStore, all, clock)
        if (all.any { it.title == title }) return

        val now = clock()
        val work = SavedWork(
            title = title,
            author = "paperlantern",
            summary = "",
            workFandoms = listOf("Avatar: The Last Airbender"),
            rating = "General Audiences",
            wordCount = 4_310,
            chapters = "1/1",
            isComplete = true,
            hasEpub = false,
            dateAdded = now
        )
        val saved = workRepository.upsert(work)
        workRepository.softDelete(saved.id)

        val shelf = workRepository.createCollection("Summer 2025")
        workRepository.softDeleteCollection(shelf.id)
    }

    private suspend fun seedHeldCopy(
        workRepository: WorkRepository,
        fileStore: WorkFileStore?,
        existing: List<WorkEntity>,
        clock: () -> Instant
    ) {
        val title = "Tea in the Jasmine Dragon"
        if (existing.any { it.title == title }) return

        val now = clock()
        val work = SavedWork(
            title = title,
            author = "uncle_iroh_fan",
            summary = "",
            sourceUrl = WorkTags.ao3WorkUrl(999_000_001L),
            workFandoms = listOf("Avatar: The Last Airbender"),
            rating = "General Audiences",
            wordCount = 8_120,
            chapters = "3/3",
            isComplete = true,
            isFinished = true,
            isSaved = false,
            hasEpub = true,
            dateAdded = now.minusSeconds(9L * 86_400L),
            freedAt = now.minusSeconds(2L * 86_400L)
        )
        writePlaceholderEpub(work.id, work.title, fileStore)
        workRepository.upsert(work)
    }

    private suspend fun writePlaceholderEpub(
        workId: String,
        title: String,
        fileStore: WorkFileStore?
    ) {
        if (fileStore == null) return
        if (title == "The Long Way Down") {
            fileStore.writeWorkEpub(workId, buildSearchEpub(title))
            return
        }
        val bodyHtml = """
            <p>The city was quiet, but never dark. Streetlamps hummed along the pavement, casting sharp amber shadows across the rain-slicked stones.</p>
            <p>Footsteps echoed in the narrow alleyway between old brick buildings. A solitary breeze carried the faint scent of ozone and diesel fuel.</p>
            <p>There was a rhythm to this place that refused to sleep, keeping vigil against the stillness of the night.</p>
        """.trimIndent()
        val epubBytes = EpubBuilder.buildEpub(title, bodyHtml)
        fileStore.writeWorkEpub(workId, epubBytes)
    }

    private suspend fun seedPreferences(context: Context, settingsRepository: SettingsRepository?) {
        val namespace = SubscriptionWatermarks.NAMESPACE_SUBSCRIPTIONS
        val watermarks = SubscriptionWatermarks.load(context, namespace).toMutableMap()
        // Metadata fixtures post 5, 8 and 1 chapters respectively. Never reset Mark All as Seen.
        for ((id, count) in listOf(45678901L to 3, 12345L to 5, 999000002L to 1)) {
            watermarks.putIfAbsent(id, SubscriptionWatermark(count, Instant.parse("2026-07-01T12:00:00Z").toEpochMilli()))
        }
        SubscriptionWatermarks.save(context, namespace, watermarks)

        if (settingsRepository == null) return
        val prefs = context.getSharedPreferences("kudos_demo_fixtures", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("pairedDeviceSeeded", false)) {
            // A fresh peer, never the actual device key. Only its public key survives;
            // no fixture can sign a deletion or pair another device with its private key.
            val pair = Ed25519Sign.KeyPair.newKeyPair()
            val hex = pair.publicKey.toLowerHex()
            pair.privateKey.fill(0)
            val store = TombstoneTrustStore(settingsRepository) { Instant.parse("2026-07-01T12:00:00Z") }
            if (store.trust(hex, "Demo reading tablet")) {
                // Remembers the seed even after either revoke reason removes the trust row.
                prefs.edit().putBoolean("pairedDeviceSeeded", true).apply()
            }
        }
    }

    /** Reuse the real builder's XHTML/style/container, with separate demo-only spine items. */
    private fun buildSearchEpub(title: String): ByteArray {
        val chapters = listOf(EpubBuilder.Chapter("Preface", "<p>A lantern marks the start of this original practice journey.</p>")) +
            (1..7).map { number ->
                val body = "<p>A lantern waits beside platform $number. The keeper checks the clock and records the weather.</p>" +
                    (if (number == 2 || number == 6) "<p>The compass points toward the quiet stairwell.</p>" else "") +
                    (if (number == 3) List(240) { "<p>A bell rings. A keeper writes a small note.</p>" }.joinToString("\n") else "")
                EpubBuilder.Chapter("Chapter $number", body)
            } + EpubBuilder.Chapter("Afterword", "<p>The lantern is put away. These invented notes close the practice journey.</p>")
        val entries = linkedMapOf<String, ByteArray>()
        for ((index, chapter) in chapters.withIndex()) {
            val generated = EpubBuilder.buildEpub(title, "<h1>${chapter.title}</h1>${chapter.bodyHtml}")
            ZipInputStream(generated.inputStream()).use { zip ->
                while (true) {
                    val entry = zip.nextEntry ?: break
                    val bytes = zip.readBytes()
                    if (entry.name == "OEBPS/content.html") {
                        entries["OEBPS/section-$index.xhtml"] = bytes
                    } else if (index == 0) {
                        entries[entry.name] = bytes
                    }
                }
            }
        }
        val manifest = chapters.indices.joinToString("\n") {
            "<item id=\"section-$it\" href=\"section-$it.xhtml\" media-type=\"application/xhtml+xml\"/>"
        }
        val spine = chapters.indices.joinToString("\n") { "<itemref idref=\"section-$it\"/>" }
        entries["OEBPS/content.opf"] = entries.getValue("OEBPS/content.opf").toString(Charsets.UTF_8)
            .replace("<item id=\"content\" href=\"content.html\" media-type=\"application/xhtml+xml\"/>", manifest +
                "\n<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>")
            .replace("<itemref idref=\"content\"/>", spine).toByteArray(Charsets.UTF_8)
        val navPoints = chapters.mapIndexed { index, chapter ->
            "<navPoint id=\"section-$index\" playOrder=\"${index + 1}\"><navLabel><text>${chapter.title}</text></navLabel>" +
                "<content src=\"section-$index.xhtml\"/></navPoint>"
        }.joinToString("\n")
        entries["OEBPS/toc.ncx"] = entries.getValue("OEBPS/toc.ncx").toString(Charsets.UTF_8)
            .replace(Regex("<navMap>[\\s\\S]*?</navMap>"), "<navMap>$navPoints</navMap>").toByteArray(Charsets.UTF_8)
        val links = chapters.mapIndexed { index, chapter ->
            "<li><a href=\"section-$index.xhtml\">${chapter.title}</a></li>"
        }.joinToString("\n")
        entries["OEBPS/nav.xhtml"] = ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>" +
            "<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\">" +
            "<head><title>Contents</title></head><body><nav epub:type=\"toc\"><ol>$links</ol></nav></body></html>")
            .toByteArray(Charsets.UTF_8)
        return ByteArrayOutputStream().use { output ->
            ZipOutputStream(output).use { zip ->
                // EPUB requires mimetype first and uncompressed, as in EpubBuilder.
                val mime = entries.remove("mimetype")!!
                zip.putNextEntry(ZipEntry("mimetype").apply {
                    method = ZipEntry.STORED
                    size = mime.size.toLong()
                    crc = CRC32().apply { update(mime) }.value
                })
                zip.write(mime)
                zip.closeEntry()
                for ((name, bytes) in entries) {
                    zip.putNextEntry(ZipEntry(name))
                    zip.write(bytes)
                    zip.closeEntry()
                }
            }
            output.toByteArray()
        }
    }
}
