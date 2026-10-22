package io.github.cidy02.kudos

import android.app.Activity
import android.app.Application
import android.os.Bundle
import androidx.work.Configuration
import coil3.ImageLoader
import coil3.SingletonImageLoader
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import io.github.cidy02.kudos.app.KudosAppContainer
import io.github.cidy02.kudos.backup.TombstoneLocalMigration
import io.github.cidy02.kudos.backup.TombstoneSigning
import io.github.cidy02.kudos.network.ao3.DemoNetwork
import io.github.cidy02.kudos.network.ao3.installDemoNetworkBlock
import io.github.cidy02.kudos.works.KudosWorkerFactory
import io.github.cidy02.kudos.works.WorkAvailabilitySweep
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient

class KudosApplication : Application(), Configuration.Provider {
    lateinit var container: KudosAppContainer
        private set

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setWorkerFactory(
                KudosWorkerFactory(
                    sweep = WorkAvailabilitySweep(container.workRepository, container.tagsRepository)
                )
            )
            .build()

    /** Process-scoped IO work that outlives any single Activity/composition. */
    private val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** Debug seed and other startup work that must not block the first frame. */
    fun launchIo(block: suspend () -> Unit) {
        applicationScope.launch { block() }
    }

    /**
     * Started-activity counter used as a ProcessLifecycleOwner stand-in: 0→1 is
     * foreground, 1→0 is background. lifecycle-process is only a transitive
     * runtime artifact here and is not on the compile classpath, so we avoid a
     * new Gradle dependency and count activity start/stop instead.
     */
    private var startedActivityCount = 0

    override fun onCreate() {
        super.onCreate()
        installImageLoader()
        TombstoneSigning.initialize(this)
        container = KudosAppContainer(this, applicationScope)
        // Start the library snapshot before the first frame so Home does not
        // open on an empty loading state and then recompute it.
        container.libraryRepository
        container.databaseChangeTracker.start()
        // Apple PreservedWorkService launch sweep: permanently remove soft-deleted
        // works and collections past permanentDeletionScheduledAt (90-day window).
        applicationScope.launch {
            runCatching { container.backupRepository.recoverInterruptedReplace() }
            runCatching {
                TombstoneLocalMigration.runIfNeeded(
                    container.database,
                    container.settingsRepository
                )
            }
            // Behind the persistence gate, so a restore or a sync never has records or files
            // swept from under it (A56, iOS `sweepExpiredIsANoOpWhileTheOperationGateIsHeld`).
            container.persistenceGate.withLock {
                runCatching { container.workRepository.sweepExpiredSoftDeletes() }
                runCatching { container.workRepository.sweepExpiredCollectionSoftDeletes() }
                runCatching { container.readingQueueRepository.sweepExpiredQueueSoftDeletes() }
                runCatching { container.workRepository.sweepHeldCopies() }
                runCatching { container.readingQueueRepository.normalizeAllQueuedWorks() }
                runCatching { container.workRepository.repairMissingEpubFlags() }
            }
            // Paced rebuild of stale library searchText (schema bump / pre-index / restore).
            runCatching { container.workRepository.rebuildSearchIndexIfNeeded() }
            // No AO3 read here: iOS reads nothing at launch but the session check, and this
            // also ran in a process only a background worker had started. The Library's own
            // backfill reads what a work lacks while it is open (DECISIONS 2026-10-16).
        }
        // Throttled GitHub update check (default: at most once/24h). Silent on
        // failure — a broken GitHub check must never affect app startup.
        applicationScope.launch {
            runCatching {
                // The demo asks nothing of the network, GitHub included (audit A18-6).
                DemoNetwork.awaitLaunchDecision()
                if (DemoNetwork.isActive) return@runCatching
                container.appUpdateRepository.checkIfDue()
            }
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
     * Coil's default OkHttp stack has no demo block. Register ours first; Coil
     * still appends its decoders after the user registry. WebView is left alone.
     */
    private fun installImageLoader() {
        val client = OkHttpClient.Builder().installDemoNetworkBlock().build()
        try {
            SingletonImageLoader.setSafe { context ->
                ImageLoader.Builder(context)
                    .components {
                        add(OkHttpNetworkFetcherFactory(client))
                    }
                    .build()
            }
        } catch (_: IllegalStateException) {
            // Already installed in this process (a second Application in tests).
        }
    }

    /**
     * Fire-and-forget folder sync when auto-sync is on and a folder is connected.
     * Mirrors FolderSyncWorker: failures are swallowed so UI / lifecycle isn't blocked.
     */
    private fun maybeRunFolderSync() {
        applicationScope.launch {
            runCatching {
                container.syncRepository.runAutoSync()
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

        // Nor is tag enrichment a background job: iOS refreshes tags only while the Library
        // is open. The daily worker read up to 150 works from AO3 a day, by a "needs refresh"
        // test that was only a 24-hour gap, and kept nothing it read (DECISIONS 2026-10-16).
        workManager.cancelUniqueWork("WorkTagsRefreshWorker")
    }
}
