package io.github.cidy02.kudos.works

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.backup.BackupPaths
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.files.WorkFileStore
import java.nio.file.Files
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Port of iOS `EqualSizeEPUBStillSyncsTests.anExistingBookGetsADigestOnReconcile`.
 * Launch backfill is what iOS runs from `PersistenceMigrationService.runIfNeeded`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class EpubDigestBackfillTest {
    private lateinit var database: KudosDatabase
    private lateinit var fileStore: WorkFileStore
    private lateinit var works: WorkRepository

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        fileStore = WorkFileStore(Files.createTempDirectory("kudos-digest-backfill"))
        works = WorkRepository(database, fileStore)
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun anExistingBookGetsADigestOnReconcile() = runTest {
        val id = "11111111-1111-4111-8111-111111111111"
        val bytes = "<p>Existing.</p>".toByteArray()
        works.upsert(SavedWork(id = id, title = "Older Book", author = "Writer", hasEpub = true))
        fileStore.writeWorkEpub(id, bytes)
        assertEquals("", works.getWork(id)!!.epubDigest)

        assertEquals(1, works.backfillEpubDigests())

        val digest = works.getWork(id)!!.epubDigest
        assertTrue(digest.isNotEmpty())
        assertEquals(BackupPaths.sha256(bytes), digest)
        assertEquals(BackupPaths.sha256(fileStore.workEpubPath(id).toFile()), digest)
    }

    @Test
    fun aDigestFilledMeanwhileIsNotOverwritten() = runTest {
        val id = "22222222-2222-4222-8222-222222222222"
        works.upsert(SavedWork(id = id, title = "Raced", author = "Writer", hasEpub = true))
        fileStore.writeWorkEpub(id, "bytes".toByteArray())
        assertEquals(1, database.workDao().fillEpubDigestIfBlank(id, "imported-wins"))
        assertEquals(0, database.workDao().fillEpubDigestIfBlank(id, "backfill-loses"))
        assertEquals("imported-wins", works.getWork(id)!!.epubDigest)
        assertEquals(0, works.backfillEpubDigests())
        assertEquals("imported-wins", works.getWork(id)!!.epubDigest)
    }

    @Test
    fun backfillStopsAfterThePassLimit() = runTest {
        val first = "33333333-3333-4333-8333-333333333333"
        val second = "44444444-4444-4444-8444-444444444444"
        works.upsert(SavedWork(id = first, title = "One", author = "Writer", hasEpub = true))
        works.upsert(SavedWork(id = second, title = "Two", author = "Writer", hasEpub = true))
        fileStore.writeWorkEpub(first, "one".toByteArray())
        fileStore.writeWorkEpub(second, "two".toByteArray())

        assertEquals(1, works.backfillEpubDigests(limit = 1))
        val filled = listOf(first, second).count { works.getWork(it)!!.epubDigest.isNotEmpty() }
        assertEquals(1, filled)
    }
}
