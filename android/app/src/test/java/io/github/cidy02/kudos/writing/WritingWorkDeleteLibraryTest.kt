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
