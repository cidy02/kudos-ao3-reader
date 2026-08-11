package io.github.cidy02.kudos.backup

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import io.github.cidy02.kudos.KudosApplication

class FolderSyncWorker(
    appContext: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(appContext, workerParams) {
    override suspend fun doWork(): Result {
        val application = applicationContext as KudosApplication
        val syncRepository = application.container.syncRepository

        return when (syncRepository.runSync()) {
            is SyncResult.Success -> Result.success()
            // Another lifecycle/manual run already covers this window.
            is SyncResult.SkippedAlreadyRunning -> Result.success()
            // SAF IO failures (e.g. permission revoked) are unlikely to be transient;
            // don't retry endlessly, just wait for the next scheduled run.
            is SyncResult.Error -> Result.failure()
        }
    }
}
