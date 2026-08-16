package io.github.cidy02.kudos

import android.app.Activity
import android.app.Application
import android.os.Bundle
import androidx.work.Configuration
import io.github.cidy02.kudos.app.KudosAppContainer
import io.github.cidy02.kudos.backup.TombstoneLocalMigration
import io.github.cidy02.kudos.backup.TombstoneSigning
import io.github.cidy02.kudos.works.KudosWorkerFactory
import io.github.cidy02.kudos.works.WorkAvailabilitySweep
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class KudosApplication : Application(), Configuration.Provider {
    lateinit var container: KudosAppContainer
        private set

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setWorkerFactory(
                KudosWorkerFactory(
                    tagsRepository = container.tagsRepository,
                    workRepository = container.workRepository,
                    sweep = WorkAvailabilitySweep(container.workRepository, container.tagsRepository)
                )
            )
            .build()

    /** Process-scoped IO work that outlives any single Activity/composition. */
    private val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /**
     * Started-activity counter used as a ProcessLifecycleOwner stand-in: 0→1 is
     * foreground, 1→0 is background. lifecycle-process is only a transitive
     * runtime artifact here and is not on the compile classpath, so we avoid a
     * new Gradle dependency and count activity start/stop instead.
     */
    private var startedActivityCount = 0

    override fun onCreate() {
        super.onCreate()
        TombstoneSigning.initialize(this)
        container = KudosAppContainer(this)
        container.databaseChangeTracker.start()
        // Apple PreservedWorkService launch sweep: permanently remove soft-deleted
        // works and collections past permanentDeletionScheduledAt (90-day window).
        applicationScope.launch {
            runCatching {
                TombstoneLocalMigration.runIfNeeded(
                    container.database,
                    container.settingsRepository
                )
            }
            runCatching { container.workRepository.sweepExpiredSoftDeletes() }
            runCatching { container.workRepository.sweepExpiredCollectionSoftDeletes() }
            runCatching { container.readingQueueRepository.sweepExpiredQueueSoftDeletes() }
            // Paced rebuild of stale library searchText (schema bump / pre-index / restore).
            runCatching { container.workRepository.rebuildSearchIndexIfNeeded() }
            // Opportunistic background tag refresh (404 detection).
            runCatching {
                val stale = container.workRepository.listSavedWorks()
                    .filter { it.lastUpdateCheck == null }
                    .take(5)
                for (work in stale) {
                    container.workRepository.refreshMetadata(work.id)
                }
            }
        }
        // Throttled GitHub update check (default: at most once/24h). Silent on
        // failure — a broken GitHub check must never affect app startup.
        applicationScope.launch {
            runCatching { container.appUpdateRepository.checkIfDue() }
        }

        // iOS also syncs on launch / foreground / background; the 6h WorkManager
        // job remains as the backstop when the app is never opened.
        registerActivityLifecycleCallbacks(object : ActivityLifecycleCallbacks {
            override fun onActivityStarted(activity: Activity) {
                if (startedActivityCount == 0) {
                    maybeRunFolderSync()
                }
                startedActivityCount++
            }

            override fun onActivityStopped(activity: Activity) {
                startedActivityCount = (startedActivityCount - 1).coerceAtLeast(0)
                if (startedActivityCount == 0) {
                    maybeRunFolderSync()
                }
            }

            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
            override fun onActivityResumed(activity: Activity) = Unit
            override fun onActivityPaused(activity: Activity) = Unit
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
            override fun onActivityDestroyed(activity: Activity) = Unit
        })

        scheduleWorkManagerTasks()
    }

    /**
     * Fire-and-forget folder sync when auto-sync is on and a folder is connected.
     * Mirrors FolderSyncWorker: failures are swallowed so UI / lifecycle isn't blocked.
     */
    private fun maybeRunFolderSync() {
        applicationScope.launch {
            runCatching {
                if (!container.syncRepository.isSyncEnabled()) return@runCatching
                if (container.syncRepository.getSyncFolderUri() == null) return@runCatching
                container.syncRepository.runSync()
            }
        }
    }

    private fun scheduleWorkManagerTasks() {
        val workManager = androidx.work.WorkManager.getInstance(this)

        // Availability sweeps are manual-only (AO3 networking policy: no periodic
        // full-library metadata sweeps). Cancel any previously-enqueued periodic
        // instance from older installs; AvailabilitySweepWorker remains for a
        // one-shot / manual trigger.
        workManager.cancelUniqueWork("AvailabilitySweepWorker")

        // Tag enrichment is the sanctioned background refresh path — throttle with
        // network + battery constraints (shape matches SyncRepository.scheduleWorker).
        val tagRefreshConstraints = androidx.work.Constraints.Builder()
            .setRequiredNetworkType(androidx.work.NetworkType.CONNECTED)
            .setRequiresBatteryNotLow(true)
            .build()
        val tagRefreshWork = androidx.work.PeriodicWorkRequestBuilder<io.github.cidy02.kudos.works.WorkTagsRefreshWorker>(
            1, java.util.concurrent.TimeUnit.DAYS
        )
            .setConstraints(tagRefreshConstraints)
            .build()

        // UPDATE so existing installs pick up the new network/battery constraints
        // rather than keeping an unconstrained periodic request forever.
        workManager.enqueueUniquePeriodicWork(
            "WorkTagsRefreshWorker",
            androidx.work.ExistingPeriodicWorkPolicy.UPDATE,
            tagRefreshWork
        )
    }
}
