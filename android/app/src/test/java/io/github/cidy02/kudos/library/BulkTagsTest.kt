package io.github.cidy02.kudos.library

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.Tag
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.works.WorkRepository
import java.nio.file.Files
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Brief 3ck: your own tags across a selection of works (iOS `WorkBulkTagSheet`). */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class BulkTagsTest {
    private lateinit var database: KudosDatabase
    private lateinit var works: WorkRepository
    private val ids = listOf("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
        "cccccccc-cccc-4ccc-8ccc-cccccccccccc")

    @Before fun setUp() {
        database = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), KudosDatabase::class.java)
            .allowMainThreadQueries().build()
        works = WorkRepository(database = database, fileStore = WorkFileStore(Files.createTempDirectory("kudos-bulk-tags")))
    }

    @After fun tearDown() { database.close() }

    private suspend fun seed() = ids.forEach { works.upsert(SavedWork(id = it, title = "Work $it", author = "a", isSaved = true)) }
    private suspend fun names(id: String) = works.userTagsForWork(id).map { it.name }.sorted()
    private suspend fun coverage(selection: List<String> = ids) =
        BulkTags.coverage(works.allUserTags(), works.userTagIdsByWork(selection)).let { shared ->
            shared.all.associate { it.name to shared.coverage.getValue(it.id) }
        }

    @Test fun aTagIsOnEveryWorkOnSomeOrOnNone() {
        val comfort = Tag(id = "c", name = "Comfort")
        val long = Tag(id = "l", name = "Long")
        val none = Tag(id = "n", name = "Unused")
        val shared = BulkTags.coverage(listOf(comfort, long, none), listOf(setOf("c", "l"), setOf("c"), setOf("c")))
        assertEquals(mapOf("c" to TagCoverage.All, "l" to TagCoverage.Some, "n" to TagCoverage.None), shared.coverage)
        assertEquals("on every selected work", BulkTags.spoken(TagCoverage.All, "work"))
        assertEquals("on some selected works", BulkTags.spoken(TagCoverage.Some, "work"))
        assertEquals("not applied", BulkTags.spoken(TagCoverage.None, "work"))
    }

    @Test fun aTapPutsATagOnTheRestAndOnlyATagOnEveryWorkComesOff() = runTest {
        seed()
        works.addUserTag(ids[0], "Comfort")
        assertEquals(mapOf("Comfort" to TagCoverage.Some), coverage())

        // "Some" adds: the direction that cannot lose a tag already put on a work.
        works.toggleUserTag(ids, "Comfort")
        assertEquals(mapOf("Comfort" to TagCoverage.All), coverage())
        assertEquals(listOf("Comfort"), names(ids[2]))

        works.toggleUserTag(ids, "comfort")
        assertEquals(mapOf("Comfort" to TagCoverage.None), coverage())
        assertEquals(emptyList<String>(), names(ids[0]))
        assertEquals("the tag itself stays for next time", listOf("Comfort"), works.allUserTags().map { it.name })
    }

    @Test fun aNewNameIsMadeOnceAndOnlyTheSelectionIsTouched() = runTest {
        seed()
        works.toggleUserTag(ids.take(2), "  Reread ")
        works.toggleUserTag(ids.take(2), "REREAD")
        works.toggleUserTag(ids.take(1), "Reread")
        assertEquals(listOf("Reread"), works.allUserTags().map { it.name })
        assertEquals(listOf("Reread"), names(ids[0]))
        assertEquals(emptyList<String>(), names(ids[1]))
        assertEquals("a work outside the selection is never touched", emptyList<String>(), names(ids[2]))

        works.toggleUserTag(emptyList(), "Nothing")
        works.toggleUserTag(ids, "   ")
        assertEquals(listOf("Reread"), works.allUserTags().map { it.name })
    }
}
