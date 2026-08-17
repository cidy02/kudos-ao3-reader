package io.github.cidy02.kudos.search

import io.github.cidy02.kudos.data.local.dao.SavedSearchDao
import io.github.cidy02.kudos.data.local.entity.SavedSearchEntity
import io.github.cidy02.kudos.network.ao3.search.AO3Rating
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.network.ao3.search.AO3SearchSort
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SavedSearchRepositoryTest {
    @Test
    fun saveUpsertsEncodesFiltersAndListsNewestFirst() = runBlocking {
        val dao = FakeSavedSearchDao()
        val clock = mutableListOf(
            Instant.parse("2026-07-01T10:00:00Z"),
            Instant.parse("2026-07-01T11:00:00Z")
        )
        val repo = SavedSearchRepository(dao) {
            clock.removeAt(0)
        }

        val first = repo.save(
            name = "  Slow Burn  ",
            filters = AO3SearchFilters(query = "slow burn", sort = AO3SearchSort.KUDOS)
        )
        val second = repo.save(
            name = "Mature only",
            filters = AO3SearchFilters(rating = AO3Rating.MATURE, includeNotRated = false)
        )

        assertEquals("Slow Burn", first.name)
        assertTrue(first.filtersJson.contains("\"query\":\"slow burn\""))
        assertEquals(2, dao.store.size)

        val all = repo.getAll()
        assertEquals(listOf(second.id, first.id), all.map { it.id })
        assertEquals(
            AO3SearchFilters(query = "slow burn", sort = AO3SearchSort.KUDOS),
            repo.filtersOf(all[1])
        )
        assertEquals(
            AO3SearchFilters(rating = AO3Rating.MATURE, includeNotRated = false),
            repo.filtersOf(all[0])
        )
    }

    @Test
    fun deleteRemovesSavedSearch() = runBlocking {
        val dao = FakeSavedSearchDao()
        val tombs = FakeSyncTombstoneDao()
        val repo = SavedSearchRepository(
            dao,
            clock = { Instant.parse("2026-07-01T12:00:00Z") },
            tombstoneDao = tombs,
            uuidFactory = { "dddddddd-dddd-4ddd-8ddd-dddddddddddd" }
        )

        val saved = repo.save("Keep me", AO3SearchFilters(query = "keep"))
        assertEquals(1, repo.getAll().size)

        repo.delete(saved.id)
        assertTrue(repo.getAll().isEmpty())
        assertTrue(dao.store.isEmpty())
        assertEquals(1, tombs.store.size)
        val minted = tombs.store.values.single()
        assertEquals(saved.id.lowercase(), minted.recordID)
        assertEquals(
            io.github.cidy02.kudos.core.model.SyncTombstoneRecordType.SAVED_SEARCH,
            minted.recordTypeRaw
        )
        assertTrue(minted.signature.isNotEmpty())
    }

    @Test(expected = IllegalArgumentException::class)
    fun saveRejectsBlankName() {
        runBlocking {
            val repo = SavedSearchRepository(FakeSavedSearchDao())
            repo.save("   ", AO3SearchFilters(query = "x"))
        }
    }

    @Test(expected = IllegalArgumentException::class)
    fun saveRejectsEmptyFilters() {
        runBlocking {
            val repo = SavedSearchRepository(FakeSavedSearchDao())
            repo.save("Empty", AO3SearchFilters())
        }
    }
}

private class FakeSavedSearchDao : SavedSearchDao {
    val store = linkedMapOf<String, SavedSearchEntity>()

    override suspend fun upsert(savedSearch: SavedSearchEntity) {
        store[savedSearch.id] = savedSearch
    }

    override suspend fun getById(id: String): SavedSearchEntity? = store[id]

    override suspend fun getAll(): List<SavedSearchEntity> {
        return store.values.sortedByDescending { it.dateAdded }
    }

    override suspend fun deleteById(id: String) {
        store.remove(id)
    }
}

private class FakeSyncTombstoneDao : io.github.cidy02.kudos.data.local.dao.SyncTombstoneDao {
    val store = linkedMapOf<String, io.github.cidy02.kudos.data.local.entity.SyncTombstoneEntity>()

    override suspend fun upsert(
        tombstone: io.github.cidy02.kudos.data.local.entity.SyncTombstoneEntity
    ) {
        store[tombstone.id] = tombstone
    }

    override suspend fun upsertAll(
        tombstones: List<io.github.cidy02.kudos.data.local.entity.SyncTombstoneEntity>
    ) {
        tombstones.forEach { upsert(it) }
    }

    override suspend fun getAll() = store.values.toList()

    override suspend fun getByRecord(recordId: String, recordType: String) =
        store.values.filter { it.recordID == recordId && it.recordTypeRaw == recordType }

    override suspend fun deleteById(id: String) {
        store.remove(id)
    }

    override suspend fun deleteByRecord(recordId: String, recordType: String) {
        store.values.filter { it.recordID == recordId && it.recordTypeRaw == recordType }
            .forEach { store.remove(it.id) }
    }

    override suspend fun getBySigner(signerPublicKey: String, recordType: String) =
        store.values.filter { it.signerPublicKey == signerPublicKey && it.recordTypeRaw == recordType }

    override suspend fun deleteSavedWorkByIdentity(
        recordId: String,
        ao3WorkId: Int?,
        canonicalSourceUrl: String,
        sourceUrl: String,
        recordType: String
    ) = Unit
}
