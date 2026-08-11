package io.github.cidy02.kudos.works

import android.content.Context
import androidx.work.ListenableWorker
import androidx.work.WorkerFactory
import androidx.work.WorkerParameters

class KudosWorkerFactory(
    private val tagsRepository: io.github.cidy02.kudos.network.ao3.work.WorkTagsRepository,
    private val workRepository: io.github.cidy02.kudos.works.WorkRepository,
    private val sweep: WorkAvailabilitySweep
) : WorkerFactory() {
    override fun createWorker(
        appContext: Context,
        workerClassName: String,
        workerParameters: WorkerParameters
    ): ListenableWorker? {
        return when (workerClassName) {
            WorkTagsRefreshWorker::class.java.name ->
                WorkTagsRefreshWorker(appContext, workerParameters, tagsRepository, workRepository)
            AvailabilitySweepWorker::class.java.name ->
                AvailabilitySweepWorker(appContext, workerParameters, sweep)
            else -> null
        }
    }
}
