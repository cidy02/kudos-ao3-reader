package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.core.model.SavedWork
import kotlinx.coroutines.ensureActive
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataRepository

/**
 * Manual full-metadata re-sync for an already-saved work, without re-downloading
 * the EPUB (iOS `WorkMetadataRefresh`). Distinct from
 * [WorkRepository.refreshMetadata], which only re-pulls tag groups: this also
 * refreshes chapters/word count/kudos/comments/hits.
 *
 * Tags are **unioned**, never replaced, so a tag AO3 has since dropped stays on
 * the local record (same rule as [WorkMetadataMerger]). A 404 marks the last copy;
 * inconclusive failures leave availability untouched — refresh never deletes.
 */
class WorkMetadataRefresh(
    private val workRepository: WorkRepository,
    private val metadataRepository: AO3WorkMetadataRepository
) {
    /** Explicit visible-page refresh only; identities deduplicate before any request. */
    suspend fun refresh(works: List<SavedWork>) {
        for (work in works.distinctBy { WorkIdentityIndex.ao3WorkId(it) ?: it.id }) {
            kotlinx.coroutines.currentCoroutineContext().ensureActive()
            var failed = false
            refresh(work) { failed = it != AO3Error.NotFound }
            // A refused/rate-limited/offline page is no invitation to try every later work.
            if (failed) break
        }
    }

    suspend fun refresh(original: SavedWork): SavedWork = refresh(original) {}

    private suspend fun refresh(original: SavedWork, onFailure: (AO3Error) -> Unit): SavedWork {
        val initial = workRepository.getWork(original.id) ?: return original
        if (initial.isDeleted) return initial
        val workId = WorkIdentityIndex.ao3WorkId(initial) ?: return initial
        val result = metadataRepository.fetch(workId)
        if (result is AO3Result.Failure) onFailure(result.error)
        // Refresh can outlive a flag/progress edit or deletion. Merge metadata onto the latest row.
        val current = workRepository.getWork(initial.id) ?: return initial
        if (current.isDeleted) return current
        val recoveredId = workId.takeIf { it in 1..Int.MAX_VALUE.toLong() }?.toInt()
        val work = if (current.ao3WorkID == null && recoveredId != null) current.copy(ao3WorkID = recoveredId) else current
        return when (result) {
            is AO3Result.Success -> {
                val md = result.value
                workRepository.upsert(work.copy(
                    title = md.title.ifBlank { work.title },
                    author = md.authors.takeIf { it.isNotEmpty() }?.joinToString(", ") ?: work.author,
                    authorIdentitiesJSON = md.authorIdentitiesJSON.ifBlank { work.authorIdentitiesJSON },
                    rating = md.rating.ifBlank { work.rating },
                    chapters = md.chapters.ifBlank { work.chapters },
                    datePublished = md.datePublished.ifBlank { work.datePublished },
                    dateUpdated = md.dateUpdated.ifBlank { work.dateUpdated },
                    isComplete = md.isComplete ?: work.isComplete,
                    language = md.language.ifBlank { work.language },
                    wordCount = md.words ?: work.wordCount,
                    kudos = md.kudos ?: work.kudos,
                    comments = md.comments ?: work.comments,
                    hits = md.hits ?: work.hits,
                    workFandoms = union(work.workFandoms, md.fandoms),
                    workRelationships = union(work.workRelationships, md.relationships),
                    workCharacters = union(work.workCharacters, md.characters),
                    workFreeforms = union(work.workFreeforms, md.freeforms),
                    workWarnings = union(work.workWarnings, md.warnings),
                    workCategories = union(work.workCategories, md.categories),
                    // A successful fetch proves the work is back on AO3.
                    ao3Unavailable = false,
                    lastAvailabilityCheck = workRepository.currentInstant(),
                    lastModifiedAt = workRepository.currentInstant(),
                    hasGivenKudos = work.hasGivenKudos || md.kudosGivenByCurrentUser
                ))
            }
            is AO3Result.Failure -> {
                if (result.error == AO3Error.NotFound) {
                    workRepository.upsert(work.copy(
                        ao3Unavailable = true,
                        lastAvailabilityCheck = workRepository.currentInstant(),
                        lastModifiedAt = if (!work.ao3Unavailable) workRepository.currentInstant() else work.lastModifiedAt
                    ))
                } else if (work !== current) {
                    // The ID read from the source URL is kept even when AO3 could not be reached.
                    workRepository.upsert(work)
                } else work
            }
        }
    }

    private fun union(existing: List<String>, incoming: List<String>): List<String> =
        (existing + incoming).dedupeFirstSeen()
}
