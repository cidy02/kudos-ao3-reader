package io.github.cidy02.kudos.search

import io.github.cidy02.kudos.core.model.SavedSearch
import io.github.cidy02.kudos.data.local.dao.SavedSearchDao
import io.github.cidy02.kudos.data.local.entity.SavedSearchEntity
import io.github.cidy02.kudos.data.local.entity.toDomain
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import java.time.Instant
import java.util.UUID

/**
 * Persist named AO3 searches (query + full [AO3SearchFilters]) via [SavedSearchDao].
 */
class SavedSearchRepository(
    private val dao: SavedSearchDao,
    private val clock: () -> Instant = Instant::now
) {
    suspend fun getAll(): List<SavedSearch> {
        return dao.getAll().map { it.toDomain() }
    }

    /**
     * Upserts a new saved search for the given filter set.
     * @throws IllegalArgumentException when [name] is blank or [filters] is not searchable.
     */
    suspend fun save(name: String, filters: AO3SearchFilters): SavedSearch {
        val trimmed = name.trim()
        require(trimmed.isNotEmpty()) { "Saved search name must not be blank." }
        require(filters.isSearchable) { "Cannot save an empty search." }

        val entity = SavedSearchEntity(
            id = UUID.randomUUID().toString(),
            name = trimmed,
            dateAdded = clock(),
            filtersJson = SearchFiltersCodec.encode(filters)
        )
        dao.upsert(entity)
        return entity.toDomain()
    }

    suspend fun delete(id: String) {
        dao.deleteById(id)
    }

    fun filtersOf(saved: SavedSearch): AO3SearchFilters {
        return SearchFiltersCodec.decode(saved.filtersJson)
    }
}
