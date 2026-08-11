package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataRepository
import io.github.cidy02.kudos.network.ao3.AO3Result
import java.time.Instant

/**
 * Manual full-metadata re-sync for an already-saved work, without re-downloading
 * the EPUB (iOS `WorkMetadataRefresh`). Distinct from
 * [WorkRepository.refreshMetadata], which only re-pulls tag groups: this also
 * refreshes chapters/word count/kudos/comments/hits.
 *
 * Tags are **unioned**, never replaced, so a tag AO3 has since dropped stays on
 * the local record (same rule as [WorkMetadataMerger]). A failed fetch returns
 * the work untouched — refresh never deletes.
 */
class WorkMetadataRefresh(
    private val workRepository: WorkRepository,
    private val metadataRepository: AO3WorkMetadataRepository
) {
    suspend fun refresh(work: SavedWork): SavedWork {
        val workId = WorkTags.ao3WorkIdFromUrl(work.sourceUrl) ?: return work
        return when (val result = metadataRepository.fetch(workId)) {
            is AO3Result.Success -> {
                val md = result.value
                workRepository.upsert(work.copy(
                    chapters = md.chapters.ifBlank { work.chapters },
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
                    lastAvailabilityCheck = Instant.now(),
                    lastModifiedAt = Instant.now()
                ))
            }
            is AO3Result.Failure -> work
        }
    }

    private fun union(existing: List<String>, incoming: List<String>): List<String> =
        (existing + incoming).dedupeFirstSeen()
}
