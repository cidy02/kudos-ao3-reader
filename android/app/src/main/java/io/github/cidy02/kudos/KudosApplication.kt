package io.github.cidy02.kudos

import android.app.Application
import io.github.cidy02.kudos.app.KudosAppContainer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class KudosApplication : Application() {
    lateinit var container: KudosAppContainer
        private set

    /** Process-scoped IO work that outlives any single Activity/composition. */
    private val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onCreate() {
        super.onCreate()
        container = KudosAppContainer(this)
        // Apple PreservedWorkService launch sweep: permanently remove soft-deleted
        // works and collections past permanentDeletionScheduledAt (90-day window).
        applicationScope.launch {
            runCatching { container.workRepository.sweepExpiredSoftDeletes() }
            runCatching { container.workRepository.sweepExpiredCollectionSoftDeletes() }
            runCatching { container.readingQueueRepository.sweepExpiredQueueSoftDeletes() }
            // Paced rebuild of stale library searchText (schema bump / pre-index / restore).
            runCatching { container.workRepository.rebuildSearchIndexIfNeeded() }
        }
        // Throttled GitHub update check (default: at most once/24h). Silent on
        // failure — a broken GitHub check must never affect app startup.
        applicationScope.launch {
            runCatching { container.appUpdateRepository.checkIfDue() }
        }
    }
}
