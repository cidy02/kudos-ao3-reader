package io.github.cidy02.kudos.writing

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.toEntity
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class WritingWorkDeleteLibraryTest {
    @Test fun confirmedBulkDeleteLeavesEveryLibraryRecordAndEpubByteForByte() = runBlocking<Unit> {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java).allowMainThreadQueries().build()
        val files = mutableListOf<java.io.File>()
        try {
            val ids = listOf(11L, 22L, 33L)
            val bytes = io.github.cidy02.kudos.works.converters.EpubBuilder.buildEpub("Saved copies", "<p>Stay in Library.</p>")
            for (id in ids) {
                val epub = java.io.File(context.cacheDir, "bulk-copy-$id.epub"); epub.writeBytes(bytes); files += epub
                database.workDao().upsert(SavedWork(id = "local-$id", title = "Saved $id", author = "AO3_Reader",
                    sourceUrl = "https://archiveofourown.org/works/$id", isSaved = true, hasEpub = true).toEntity())
            }
            val before = ids.map { database.workDao().getById("local-$it") }
            val client = BulkRecordingClient(ids)
            val delete = io.github.cidy02.kudos.author.OwnWorksDeleteState(
                io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository(client), 7)
            delete.ask(ids.map(::bulkSummary)); delete.confirm()
            assertEquals(1, delete.state.value.confirmed)
            assertEquals(before, ids.map { database.workDao().getById("local-$it") })
            assertEquals(3, database.workDao().count())
            files.forEach { assertArrayEquals(bytes, it.readBytes()) }
        } finally { database.close(); files.forEach { it.delete() } }
    }

    @Test fun confirmedRemoteDeleteLeavesTheSavedLibraryRowAndEpubByteForByte() = runBlocking<Unit> {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java).allowMainThreadQueries().build()
        try {
            val bytes = io.github.cidy02.kudos.works.converters.EpubBuilder.buildEpub("Saved tide", "<p>My saved copy stays.</p>")
            val epub = java.io.File(java.io.File(context.filesDir, "works").apply { mkdirs() }, "local-995006.epub")
            epub.writeBytes(bytes)
            val work = SavedWork(id = "local-995006", title = "Saved tide", author = "AO3_Reader",
                sourceUrl = "https://archiveofourown.org/works/995006", isSaved = true, hasEpub = true)
            database.workDao().upsert(work.toEntity())
            val before = database.workDao().getById(work.id)
            val setup = workFormSetup(); val model = setup.model(995006).also { it.load() }
            prepareDeletePages(setup, 995006); model.prepareDelete(); model.delete()
            assertTrue(model.state.value.saved)
            assertEquals(before, database.workDao().getById(work.id)); assertEquals(1, database.workDao().count())
            assertArrayEquals(bytes, epub.readBytes())
        } finally {
            database.close()
            java.io.File(java.io.File(context.filesDir, "works"), "local-995006.epub").delete()
        }
    }
}
