package io.github.cidy02.kudos.works

import android.content.Context
import androidx.work.ListenableWorker
import androidx.work.WorkerFactory
import androidx.work.WorkerParameters

class KudosWorkerFactory(
    private val sweep: WorkAvailabilitySweep
) : WorkerFactory() {
    override fun createWorker(
        appContext: Context,
        workerClassName: String,
        workerParameters: WorkerParameters
    ): ListenableWorker? {
        return when (workerClassName) {
            AvailabilitySweepWorker::class.java.name ->
                AvailabilitySweepWorker(appContext, workerParameters, sweep)
            else -> null
        }
    }
}
