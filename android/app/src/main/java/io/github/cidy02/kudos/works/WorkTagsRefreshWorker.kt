package io.github.cidy02.kudos.works

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

class WorkTagsRefreshWorker(
    appContext: Context,
    workerParams: WorkerParameters,
    private val tagsRepository: io.github.cidy02.kudos.network.ao3.work.WorkTagsRepository,
    private val workRepository: io.github.cidy02.kudos.works.WorkRepository
) : CoroutineWorker(appContext, workerParams) {
    override suspend fun doWork(): Result {
        val works = workRepository.listSavedWorks()
        var anyFailures = false
        for (work in works) {
            if (work.needsAO3Refresh && !work.ao3Unavailable) {
                val workId = WorkTags.ao3WorkIdFromUrl(work.sourceUrl) ?: continue
                when (tagsRepository.refreshTags(workId)) {
                    is io.github.cidy02.kudos.network.ao3.AO3Result.Failure -> {
                        anyFailures = true
                    }
                    is io.github.cidy02.kudos.network.ao3.AO3Result.Success -> {
                        // Assuming the refreshTags logic saves it or we save it here
                        workRepository.upsert(work.copy(lastTagRefreshAttemptAt = java.time.Instant.now()))
                    }
                }
            }
        }
        return if (anyFailures) Result.retry() else Result.success()
    }
}
