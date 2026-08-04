package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataRepository
import io.github.cidy02.kudos.network.ao3.AO3Result
import java.time.Instant

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
                    workFandoms = md.fandoms.ifEmpty { work.workFandoms },
                    workRelationships = md.relationships.ifEmpty { work.workRelationships },
                    workCharacters = md.characters.ifEmpty { work.workCharacters },
                    workFreeforms = md.freeforms.ifEmpty { work.workFreeforms },
                    workWarnings = md.warnings.ifEmpty { work.workWarnings },
                    workCategories = md.categories.ifEmpty { work.workCategories },
                    lastModifiedAt = Instant.now()
                ))
            }
            is AO3Result.Failure -> work
        }
    }
}
