package io.github.cidy02.kudos.works

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.work.WorkTagsRepository
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.file.Files
import java.time.Instant
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** iOS `LibraryView.backfillFilterMetadata` / `WorkTags` (3fr), with no AO3 traffic. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class LibraryTagBackfillTest {
    private lateinit var database: KudosDatabase
    private lateinit var files: WorkFileStore
    private lateinit var directory: File
    private lateinit var repository: WorkRepository
    private val now = Instant.parse("2026-10-16T12:00:00Z")
    private val requested = mutableListOf<String>()
    private var answer: AO3Result<AO3HttpResponse> = page()
    private var hang: CompletableDeferred<Unit>? = null
    private var onRequest: suspend (String) -> Unit = {}

    private fun page(html: String = TAGGED_PAGE) =
        AO3Result.Success(AO3HttpResponse("https://archiveofourown.org/works/555", 200, emptyMap(), html))

    @Before
    fun setUp() {
        database = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), KudosDatabase::class.java)
            .allowMainThreadQueries().build()
        directory = Files.createTempDirectory("kudos-tag-backfill").toFile()
        files = WorkFileStore(directory.toPath())
        val client = object : AO3Client {
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
                requested += url
                onRequest(url)
                hang?.let { it.complete(Unit); awaitCancellation() }
                return answer
            }
        }
        repository = WorkRepository(database, files, tagsRepository = WorkTagsRepository(client), clock = { now })
    }

    @After
    fun tearDown() {
        database.close()
        directory.deleteRecursively()
    }

    private fun bare() = SavedWork(
        title = "A work", author = "Someone", sourceUrl = "https://archiveofourown.org/works/555",
        isSaved = true, workTags = listOf("Fandom A", "Fluff", "fandom a"),
        workFreeforms = listOf("Fluff", "fandom a"),
        dateAdded = Instant.parse("2026-10-01T12:00:00Z")
    )

    private fun complete() = bare().copy(
        ao3WorkID = 555, workTagsFetched = true, workFandoms = listOf("Fandom A"),
        workWarnings = listOf("No Archive Warnings Apply"), language = "English", wordCount = 10,
        chapters = "1/1", authorIdentitiesJSON = "[{}]"
    )

    @Test
    fun theNeedsRefreshRuleIsIOSs() {
        assertFalse(complete().needsAO3Refresh(now))
        assertTrue(complete().copy(workTagsFetched = false).needsAO3Refresh(now))
        assertTrue(complete().copy(workFandoms = emptyList(), workFreeforms = emptyList()).needsAO3Refresh(now))
        assertTrue(complete().copy(workWarnings = emptyList(), language = "", wordCount = 0).needsAO3Refresh(now))
        assertTrue(complete().copy(chapters = "").needsAO3Refresh(now))
        assertTrue(complete().copy(authorIdentitiesJSON = "").needsAO3Refresh(now))
        assertFalse(complete().copy(chapters = "", lastTagRefreshAttemptAt = now.minusSeconds(3600)).needsAO3Refresh(now))
        assertTrue(complete().copy(chapters = "", lastTagRefreshAttemptAt = now.minusSeconds(90_000)).needsAO3Refresh(now))
        assertFalse(complete().copy(chapters = "", ao3Unavailable = true).needsAO3Refresh(now))
    }

    @Test
    fun oneReadFillsWhatTheFiltersUseAndTheNextPassReadsNothing() = runTest {
        val work = repository.upsert(bare())
        repository.backfillFilterMetadata(readsAO3 = true)
        assertEquals(1, requested.size)
        val filled = repository.getWork(work.id)!!
        assertTrue(filled.workTagsFetched)
        assertEquals(555, filled.ao3WorkID)
        assertEquals(listOf("Fandom A"), filled.workFandoms)
        assertEquals("a freeform that is a fandom goes", listOf("Fluff"), filled.workFreeforms)
        assertEquals(listOf("Fandom A", "Fluff"), filled.workTags)
        assertEquals("English", filled.language)
        assertEquals(1234, filled.wordCount)
        assertEquals("2/3", filled.chapters)
        assertEquals(now, filled.lastTagRefreshAttemptAt)
        assertEquals(now, filled.lastModifiedAt)

        repository.backfillFilterMetadata(readsAO3 = true)
        assertEquals(1, requested.size)
    }

    @Test
    fun aChangeMadeWhileTheWalkRunsIsKept() = runTest {
        val first = repository.upsert(bare())
        val second = repository.upsert(bare().copy(sourceUrl = "https://archiveofourown.org/works/556",
            dateAdded = Instant.parse("2026-09-01T12:00:00Z")))
        var favorited = false
        onRequest = {
            if (!favorited) {
                favorited = true
                val other = if (it.contains("/works/555?")) second.id else first.id
                repository.upsert(repository.getWork(other)!!.copy(isFavorite = true))
            }
        }
        repository.backfillFilterMetadata(readsAO3 = true)
        assertEquals(2, requested.size)
        val changed = if (requested.first().contains("/works/555?")) second.id else first.id
        assertTrue("the reader's favourite survives the walk", repository.getWork(changed)!!.isFavorite)
    }

    @Test
    fun aFailureKeepsTheStampAndTheTagsAndA404MarksTheWorkGone() = runTest {
        val work = repository.upsert(bare())
        answer = AO3Result.Failure(AO3Error.Server(503))
        repository.backfillTagsFromAO3(work)
        val failed = repository.getWork(work.id)!!
        assertEquals(now, failed.lastTagRefreshAttemptAt)
        assertEquals(bare().workTags, failed.workTags)
        assertFalse(failed.ao3Unavailable)

        answer = AO3Result.Failure(AO3Error.NotFound)
        repository.backfillTagsFromAO3(work.copy(lastTagRefreshAttemptAt = null))
        assertTrue(repository.getWork(work.id)!!.ao3Unavailable)
    }

    @Test
    fun aCancelledReadIsNoAttempt() = runTest {
        val work = repository.upsert(bare())
        val started = CompletableDeferred<Unit>().also { hang = it }
        val job = launch { repository.backfillTagsFromAO3(work) }
        started.await()
        job.cancel()
        job.join()
        assertNull(repository.getWork(work.id)!!.lastTagRefreshAttemptAt)
    }

    @Test
    fun theDemoReadsNothingAndAnUntaggedEpubGivesItsSubjects() = runTest {
        val work = repository.upsert(bare().copy(workTags = emptyList(), workFreeforms = emptyList(), hasEpub = true))
        files.writeWorkEpub(work.id, epubWithSubjects("Subject one", "Subject two"))
        repository.backfillFilterMetadata(readsAO3 = false)
        assertTrue(requested.isEmpty())
        assertEquals(listOf("Subject one", "Subject two"), repository.getWork(work.id)!!.workTags)
    }

    private fun epubWithSubjects(vararg subjects: String): ByteArray {
        val opf = """<?xml version="1.0" encoding="utf-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="2.0">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>T</dc:title>
              ${subjects.joinToString("") { "<dc:subject>$it</dc:subject>" }}</metadata>
              <manifest><item id="c" href="c.xhtml" media-type="application/xhtml+xml"/></manifest>
              <spine><itemref idref="c"/></spine>
            </package>"""
        val output = ByteArrayOutputStream()
        ZipOutputStream(output).use { zip ->
            fun entry(name: String, value: String) {
                zip.putNextEntry(ZipEntry(name)); zip.write(value.toByteArray()); zip.closeEntry()
            }
            entry("mimetype", "application/epub+zip")
            entry("META-INF/container.xml", """<container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>""")
            entry("OEBPS/content.opf", opf)
            entry("OEBPS/c.xhtml", "<html><body><p>One.</p></body></html>")
        }
        return output.toByteArray()
    }

    private companion object {
        const val TAGGED_PAGE = """<dl class="work meta group">
            <dd class="warning tags"><a class="tag">No Archive Warnings Apply</a></dd>
            <dd class="fandom tags"><a class="tag">Fandom A</a></dd>
            <dd class="freeform tags"><a class="tag">Fluff</a></dd>
            <dd class="language">English</dd><dd class="words">1,234</dd><dd class="chapters">2/3</dd>
            </dl>"""
    }
}
