package io.github.cidy02.kudos.works

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import java.time.Instant

class WorkTagsRefreshWorker(
    appContext: Context,
    workerParams: WorkerParameters,
    private val tagsRepository: io.github.cidy02.kudos.network.ao3.work.WorkTagsRepository,
    private val workRepository: io.github.cidy02.kudos.works.WorkRepository
) : CoroutineWorker(appContext, workerParams) {
    override suspend fun doWork(): Result {
        // Cap per run so a large library cannot become a full walk every day.
        // Oldest lastTagRefreshAttemptAt first (nulls first), matching the
        // availability-sweep batching model.
        val candidates = workRepository.listSavedWorks()
            .filter { it.needsAO3Refresh && !it.ao3Unavailable }
            .filter { WorkTags.ao3WorkIdFromUrl(it.sourceUrl) != null }
            .sortedWith(compareBy(nullsFirst()) { it.lastTagRefreshAttemptAt })
            .take(PER_RUN_LIMIT)

        var anySuccess = false
        var anyFailure = false
        for (work in candidates) {
            val workId = WorkTags.ao3WorkIdFromUrl(work.sourceUrl) ?: continue
            when (tagsRepository.refreshTags(workId)) {
                is io.github.cidy02.kudos.network.ao3.AO3Result.Failure -> {
                    anyFailure = true
                }
                is io.github.cidy02.kudos.network.ao3.AO3Result.Success -> {
                    workRepository.upsert(
                        work.copy(lastTagRefreshAttemptAt = Instant.now())
                    )
                    anySuccess = true
                }
            }
        }

        // Never re-run a whole batch because of a single 404/transient failure.
        // Retry only when the run made no progress at all (and had work to do).
        return when {
            anySuccess -> Result.success()
            anyFailure -> Result.retry()
            else -> Result.success()
        }
    }

    companion object {
        const val PER_RUN_LIMIT: Int = 150
    }
}
