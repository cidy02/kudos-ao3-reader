package io.github.cidy02.kudos.app

import android.content.Intent
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.QueueTagCrossRef
import io.github.cidy02.kudos.data.local.entity.TagEntity
import io.github.cidy02.kudos.data.local.entity.WorkEntity
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.works.WorkTags
import io.github.cidy02.kudos.works.converters.EpubBuilder
import java.time.Instant
import java.util.UUID

/**
 * Demo library seeder for screenshot testing and visual review.
 * Mirrors iOS DemoLibrary (kudos-ao3-reader/App/DemoLibrary.swift).
 */
object DemoLibrary {
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
        val seenChapters: Int? = null
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
            seenChapters = 7
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
            seenChapters = 3
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
            onDevice = false
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
        clock: () -> Instant = { Instant.now() }
    ) {
        seed(
            database = container.database,
            workRepository = container.workRepository,
            readingQueueRepository = container.readingQueueRepository,
            fileStore = container.workFileStore,
            clock = clock
        )
    }

    suspend fun seedIfRequested(
        container: KudosAppContainer,
        intent: Intent?,
        clock: () -> Instant = { Instant.now() }
    ): Boolean {
        val isRequested = intent?.getBooleanExtra("kudosDemoLibrary", false) == true ||
            intent?.getStringExtra("kudosDemoLibrary").equals("true", ignoreCase = true)
        if (!isRequested) return false
        seed(container, clock)
        return true
    }

    suspend fun seed(
        database: KudosDatabase,
        workRepository: WorkRepository,
        readingQueueRepository: ReadingQueueRepository,
        fileStore: WorkFileStore? = null,
        clock: () -> Instant = { Instant.now() }
    ) {
        val allWorks = database.workDao().getAllIncludingDeleted()
        if (allWorks.any { it.title == SAMPLES[0].title }) {
            seedRecentlyDeleted(database, workRepository, fileStore, clock)
            return
        }

        val now = clock()
        val seededWorks = mutableListOf<SavedWork>()

        for ((index, sample) in SAMPLES.withIndex()) {
            val chapterParts = sample.chapters.split("/")
            val isComplete = chapterParts.lastOrNull() != "?" &&
                chapterParts.firstOrNull() == chapterParts.lastOrNull()

            val lastReadDate = if (sample.progress != null) {
                now.minusSeconds(index.toLong() * 3_600L * 7L)
            } else {
                null
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

            val savedWork = workRepository.upsert(work)
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
        val bodyHtml = """
            <p>The city was quiet, but never dark. Streetlamps hummed along the pavement, casting sharp amber shadows across the rain-slicked stones.</p>
            <p>Footsteps echoed in the narrow alleyway between old brick buildings. A solitary breeze carried the faint scent of ozone and diesel fuel.</p>
            <p>There was a rhythm to this place that refused to sleep, keeping vigil against the stillness of the night.</p>
        """.trimIndent()
        val epubBytes = EpubBuilder.buildEpub(title, bodyHtml)
        fileStore.writeWorkEpub(workId, epubBytes)
    }
}
