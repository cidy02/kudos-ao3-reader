package io.github.cidy02.kudos.works

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

class AvailabilitySweepWorker(
    appContext: Context,
    workerParams: WorkerParameters,
    private val sweep: WorkAvailabilitySweep
) : CoroutineWorker(appContext, workerParams) {
    override suspend fun doWork(): Result {
        sweep.sweep()
        return Result.success()
    }
}
