package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.network.ao3.AO3URLResolver

/**
 * Port of Apple `WorkIdentityIndex` lookup tiers for deduping library works:
 * 1. AO3 work id (from `sourceUrl`)
 * 2. Canonical AO3 work URL
 * 3. Exact source URL
 * 4. Local UUID
 *
 * Backup restore / Replace confirmation use [snapshot] with the locked
 * order ao3WorkID → [WorkTags.canonicalAO3WorkURL] → record UUID.
 */
object WorkIdentityIndex {
    fun snapshot(works: List<SavedWork>): WorkIdentitySnapshot = WorkIdentitySnapshot(works)

    fun ao3WorkId(work: SavedWork): Long? = WorkTags.ao3WorkIdFromUrl(work.sourceUrl)

    fun canonicalSourceUrl(work: SavedWork): String? {
        val id = ao3WorkId(work) ?: return work.sourceUrl.takeIf { it.isNotBlank() }
        return AO3URLResolver.canonicalWorkUrl(id)
    }

    /**
     * Find an existing local work matching [candidate] by identity tiers.
     * [byId] and [bySourceUrl] are provided by the repository/DAO layer.
     */
    suspend fun findExisting(
        candidateSourceUrl: String,
        candidateLocalId: String? = null,
        byId: suspend (String) -> SavedWork?,
        bySourceUrl: suspend (String) -> SavedWork?
    ): SavedWork? {
        candidateLocalId?.let { id ->
            byId(id)?.let { return it }
        }
        val ao3Id = WorkTags.ao3WorkIdFromUrl(candidateSourceUrl)
        if (ao3Id != null) {
            val canonical = AO3URLResolver.canonicalWorkUrl(ao3Id)
            bySourceUrl(canonical)?.let { return it }
            // Also try common www variant if stored that way.
            bySourceUrl(canonical.replace("https://archiveofourown.org", "https://www.archiveofourown.org"))
                ?.let { return it }
        }
        if (candidateSourceUrl.isNotBlank()) {
            bySourceUrl(candidateSourceUrl)?.let { return it }
        }
        return null
    }
}

/**
 * In-memory identity index over a snapshot list (Apple `WorkIdentityIndex`).
 * Strongest available tier wins: AO3 work ID → canonical source URL → record UUID.
 */
class WorkIdentitySnapshot(works: List<SavedWork>) {
    private val byRecordId: Map<String, SavedWork> = works.associateBy { it.id.lowercase() }
    private val byAo3Id: Map<Long, SavedWork> = buildMap {
        for (work in works) {
            WorkTags.ao3WorkIdFromUrl(work.sourceUrl)?.let { put(it, work) }
        }
    }
    private val byCanonicalUrl: Map<String, SavedWork> = buildMap {
        for (work in works) {
            WorkTags.canonicalAO3WorkURL(work.sourceUrl)?.let { put(it, work) }
        }
    }

    fun existingWork(
        ao3WorkId: Long? = null,
        sourceUrl: String? = null,
        recordId: String? = null
    ): SavedWork? {
        val ao3 = ao3WorkId ?: sourceUrl?.let { WorkTags.ao3WorkIdFromUrl(it) }
        if (ao3 != null) {
            byAo3Id[ao3]?.let { return it }
        }
        val canonical = sourceUrl?.let { WorkTags.canonicalAO3WorkURL(it) }
        if (canonical != null) {
            byCanonicalUrl[canonical]?.let { return it }
        }
        if (!recordId.isNullOrBlank()) {
            byRecordId[recordId.lowercase()]?.let { return it }
        }
        return null
    }
}
