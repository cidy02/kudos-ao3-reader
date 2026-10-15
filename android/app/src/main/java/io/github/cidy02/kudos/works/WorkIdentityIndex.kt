package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.network.ao3.AO3URLResolver
import java.util.Locale

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

    fun ao3WorkId(work: SavedWork): Long? = work.ao3WorkID?.toLong()
        ?: WorkTags.canonicalAO3WorkURL(work.sourceUrl)?.let(WorkTags::ao3WorkIdFromUrl)

    fun canonicalSourceUrl(work: SavedWork): String? {
        val id = ao3WorkId(work) ?: return work.sourceUrl.takeIf { it.isNotBlank() }
        return AO3URLResolver.canonicalWorkUrl(id)
    }

    /**
     * Find an existing local work matching the candidate by identity tiers.
     * Include Recently Deleted rows and canonicalize both sides through the shared index.
     */
    suspend fun findExisting(
        candidateSourceUrl: String,
        candidateLocalId: String? = null,
        loadWorks: suspend () -> List<SavedWork>
    ): SavedWork? {
        val works = loadWorks()
        val index = snapshot(works)
        index.existingWork(sourceUrl = candidateSourceUrl)?.let { return it }
        if (candidateSourceUrl.isNotBlank()) {
            works.firstOrNull { it.sourceUrl == candidateSourceUrl }?.let { return it }
        }
        return index.existingWork(recordId = candidateLocalId)
    }

    /** iOS user-EPUB fallback: title, author and on-disk size, after source identity. */
    internal suspend fun findImportedEpub(
        sourceUrl: String,
        title: String,
        author: String,
        sourceSize: Long,
        loadWorks: suspend () -> List<SavedWork>,
        epubSize: suspend (String) -> Long?
    ): SavedWork? {
        val works = loadWorks()
        findExisting(sourceUrl, loadWorks = { works })?.let { return it }
        fun key(value: String) = value.trim().lowercase(Locale.ROOT)
        val titleKey = key(title)
        if (titleKey.isEmpty()) return null
        val authorKey = key(author)
        return works.firstOrNull {
            key(it.title) == titleKey && key(it.author) == authorKey && epubSize(it.id) == sourceSize
        }
    }
}

/**
 * In-memory identity index over a snapshot list (Apple `WorkIdentityIndex`).
 * Strongest available tier wins: AO3 work ID → canonical source URL → record UUID.
 */
class WorkIdentitySnapshot(works: List<SavedWork>) {
    private val byRecordId = linkedMapOf<String, SavedWork>()
    private val byAo3Id = linkedMapOf<Long, SavedWork>()
    private val byCanonicalUrl = linkedMapOf<String, SavedWork>()

    init {
        works.forEach(::index)
    }

    fun index(work: SavedWork) {
        byRecordId[work.id.lowercase()] = work
        // The stored ID first, as iOS: a work with no URL was never found by it, so a restore
        // made it a second copy and its history and stars went to that copy (A52).
        (work.ao3WorkID?.toLong() ?: WorkTags.ao3WorkIdFromUrl(work.sourceUrl))?.let { byAo3Id[it] = work }
        WorkTags.canonicalAO3WorkURL(work.sourceUrl)?.let { byCanonicalUrl[it] = work }
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
