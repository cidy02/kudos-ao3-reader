package io.github.cidy02.kudos.data.local

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.entity.BookmarkEntity
import io.github.cidy02.kudos.data.local.entity.CollectionEntity
import io.github.cidy02.kudos.data.local.entity.CollectionWorkCrossRef
import io.github.cidy02.kudos.data.local.entity.SavedSearchEntity
import io.github.cidy02.kudos.data.local.entity.TagEntity
import io.github.cidy02.kudos.data.local.entity.WorkTagCrossRef
import io.github.cidy02.kudos.data.local.entity.toDomain
import io.github.cidy02.kudos.data.local.entity.toEntity
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class RoomDaoTest {
    private lateinit var database: KudosDatabase

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun databaseCreatesAtSchemaVersionOne() = runBlocking {
        assertEquals(1, database.openHelper.readableDatabase.version)
        assertEquals(0, database.workDao().count())
    }

    @Test
    fun workDaoInsertsAndReadsSavedWorkWithProgressFields() = runBlocking {
        val work = sampleWork().copy(
            lastSpineIndex = 4,
            lastScrollFraction = 0.42,
            readiumLocator = null,
            workWarnings = listOf("No Archive Warnings Apply"),
            workFandoms = listOf("Example Fandom"),
            comments = null,
            hits = null,
            knownChapterCount = null,
            lastUpdateCheck = null
        )

        database.workDao().upsert(work.toEntity())
        val restored = database.workDao().getById(work.id)?.toDomain()

        assertNotNull(restored)
        assertEquals(work.lastSpineIndex, restored?.lastSpineIndex)
        assertEquals(work.lastScrollFraction, restored?.lastScrollFraction ?: 0.0, 0.0)
        assertNull(restored?.readiumLocator)
        assertEquals(listOf("Example Fandom"), restored?.workFandoms)
        assertNull(restored?.knownChapterCount)
    }

    @Test
    fun tagDaoInsertsReadsAndConnectsUserTag() = runBlocking {
        val work = sampleWork(id = "work-tagged")
        val tag = TagEntity(
            id = "tag-1",
            name = "Comfort Read",
            dateCreated = Instant.parse("2026-06-26T12:00:00Z")
        )

        database.workDao().upsert(work.toEntity())
        database.tagDao().upsert(tag)
        database.tagDao().addToWork(WorkTagCrossRef(work.id, tag.id))

        assertEquals(tag, database.tagDao().getByName("Comfort Read"))
        assertEquals(listOf(tag), database.tagDao().getTagsForWork(work.id))
    }

    @Test
    fun collectionDaoPreservesWorkRelationship() = runBlocking {
        val work = sampleWork(id = "work-collection")
        val collection = CollectionEntity(
            id = "collection-1",
            name = "Weekend",
            dateAdded = Instant.parse("2026-06-26T12:10:00Z"),
            description = null,
            sortOrder = null
        )

        database.workDao().upsert(work.toEntity())
        database.collectionDao().upsert(collection)
        database.collectionDao().addWork(CollectionWorkCrossRef(collection.id, work.id))

        assertEquals(collection, database.collectionDao().getById(collection.id))
        assertEquals(listOf(work.id), database.collectionDao().getWorkIdsForCollection(collection.id))
        assertEquals(listOf(work.toEntity()), database.collectionDao().getWorksForCollection(collection.id))
    }

    @Test
    fun updatingAWorkPreservesItsTagsAndCollections() = runBlocking {
        // Regression: @Insert(REPLACE) did a DELETE+INSERT, firing ON DELETE CASCADE
        // on the cross-ref tables and silently wiping a work's tags/collections on
        // every scalar update (e.g. favoriting). @Upsert must update in place.
        val work = sampleWork(id = "work-keep-relations")
        val tag = TagEntity(
            id = "tag-keep",
            name = "Comfort Read",
            dateCreated = Instant.parse("2026-06-26T12:00:00Z")
        )
        val collection = CollectionEntity(
            id = "collection-keep",
            name = "Weekend",
            dateAdded = Instant.parse("2026-06-26T12:10:00Z"),
            description = null,
            sortOrder = null
        )

        database.workDao().upsert(work.toEntity())
        database.tagDao().upsert(tag)
        database.tagDao().addToWork(WorkTagCrossRef(work.id, tag.id))
        database.collectionDao().upsert(collection)
        database.collectionDao().addWork(CollectionWorkCrossRef(collection.id, work.id))

        // Update a scalar field on the same work id.
        database.workDao().upsert(work.copy(isFavorite = true).toEntity())

        assertEquals(true, database.workDao().getById(work.id)?.isFavorite)
        assertEquals(listOf(tag), database.tagDao().getTagsForWork(work.id))
        assertEquals(listOf(work.id), database.collectionDao().getWorkIdsForCollection(collection.id))
    }

    @Test
    fun bookmarkDaoInsertsAndReadsByUrl() = runBlocking {
        val bookmark = BookmarkEntity(
            id = "bookmark-1",
            title = "AO3",
            urlString = "https://archiveofourown.org/works/1",
            dateAdded = Instant.parse("2026-06-26T12:20:00Z")
        )

        database.bookmarkDao().upsert(bookmark)

        assertEquals(bookmark, database.bookmarkDao().getByUrl(bookmark.urlString))
    }

    @Test
    fun savedSearchUsesDateAddedField() = runBlocking {
        val dateAdded = Instant.parse("2026-06-26T12:30:00Z")
        val savedSearch = SavedSearchEntity(
            id = "search-1",
            name = "Slow Burn",
            dateAdded = dateAdded,
            filtersJson = """{"query":"slow burn"}"""
        )

        database.savedSearchDao().upsert(savedSearch)

        assertEquals(dateAdded, database.savedSearchDao().getById(savedSearch.id)?.dateAdded)
        assertEquals(listOf(savedSearch), database.savedSearchDao().getAll())
    }

    private fun sampleWork(id: String = "work-1"): SavedWork {
        return SavedWork(
            id = id,
            title = "Example Work",
            author = "Example Author",
            summary = "Summary",
            sourceUrl = "https://archiveofourown.org/works/1",
            dateAdded = Instant.parse("2026-06-26T12:00:00Z"),
            isSaved = true,
            hasEpub = false,
            rating = "Teen And Up",
            language = "English",
            wordCount = 1200,
            chapters = "1/1",
            kudos = 7,
            workTags = listOf("Fluff"),
            workTagsFetched = true
        )
    }
}
