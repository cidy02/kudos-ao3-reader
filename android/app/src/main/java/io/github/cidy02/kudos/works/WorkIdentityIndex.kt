package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.network.ao3.AO3URLResolver

/**
 * Port of Apple `WorkIdentityIndex` lookup tiers for deduping library works:
 * 1. AO3 work id (from `sourceUrl`)
 * 2. Canonical AO3 work URL
 * 3. Exact source URL
 * 4. Local UUID
 */
object WorkIdentityIndex {
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
