package io.github.cidy02.kudos.backup

import androidx.room.InvalidationTracker
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class DatabaseChangeTracker(
    private val database: KudosDatabase,
    private val settingsRepository: SettingsRepository,
    private val appScope: CoroutineScope
) {
    private val observer = object : InvalidationTracker.Observer(
        "works",
        "reading_queues",
        "reading_queue_memberships",
        "annotations",
        "collections",
        "collection_work_cross_refs",
        "sync_tombstones"
    ) {
        override fun onInvalidated(tables: Set<String>) {
            appScope.launch(Dispatchers.IO) {
                settingsRepository.updateSyncHasPendingChanges(true)
            }
        }
    }

    fun start() {
        database.invalidationTracker.addObserver(observer)
    }
}
