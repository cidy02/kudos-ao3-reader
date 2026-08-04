package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.network.ao3.work.WorkTagsRepository
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import java.time.Instant

class WorkAvailabilitySweep(
    private val workRepository: WorkRepository,
    private val tagsRepository: WorkTagsRepository
) {
    suspend fun sweep(): Int {
        val works = workRepository.listSavedWorks()
        var unavailableCount = 0
        for (work in works) {
            if (work.sourceUrl.isBlank() || work.ao3Unavailable) continue
            val workId = WorkTags.ao3WorkIdFromUrl(work.sourceUrl) ?: continue
            when (val result = tagsRepository.refreshTags(workId)) {
                is AO3Result.Failure -> {
                    if (result.error is AO3Error.NotFound) {
                        workRepository.upsert(work.copy(
                            ao3Unavailable = true,
                            lastAvailabilityCheck = Instant.now(),
                            lastModifiedAt = Instant.now()
                        ))
                        unavailableCount++
                    }
                }
                is AO3Result.Success -> {
                    workRepository.upsert(work.copy(lastAvailabilityCheck = Instant.now()))
                }
            }
        }
        return unavailableCount
    }
}
