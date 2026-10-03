package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.works.WorkRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.shareIn

class LibraryRepository(
    private val workRepository: WorkRepository,
    private val settings: Flow<KudosSettings> = flowOf(KudosSettings.Defaults),
    shareScope: CoroutineScope? = null
) {
    fun observeSavedWorks(): Flow<List<SavedWork>> = workRepository.observeSavedWorks()

    /**
     * The base set Reading Insights is computed over — deliberately wider than
     * [observeSavedWorks], which additionally requires `isProtected`.
     *
     * A work you read and then un-saved is still a work you read. iOS counts it:
     * `LibraryView.statisticsWorks` runs over every non-deleted work and filters
     * only queue-only + privacy. Reusing the saved-works flow here put the two
     * platforms on different denominators — 10 read / 5 finished / 4 of them
     * un-saved gives iOS a 50% completion rate and gave Android 17%, from the
     * same library. All nine statistics were affected.
     */
    fun observeStatisticsWorks(): Flow<List<SavedWork>> {
        return workRepository.observeLibraryWorks().map { works ->
            works.filter { !it.isQueueOnlyWork }
        }
    }

    /**
     * One shared pipeline. With a process scope this starts as soon as the
     * repository is constructed (Home reads [latestSnapshot] for its first
     * frame). Without one — unit tests — it stays cold and each collector
     * runs the pipeline itself.
     */
    private val latestSnapshotState = MutableStateFlow<LibrarySnapshot?>(null)

    private val snapshots: Flow<LibrarySnapshot> = combine(
        workRepository.observeLibraryWorks(),
        workRepository.observeLibraryIndex(),
        settings
    ) { works, index, settings ->
        LibrarySnapshot(
            items = works.map { work ->
                LibraryWorkListItem(
                    work = work,
                    userTags = index.tagsByWork[work.id].orEmpty(),
                    collections = index.collectionsByWork[work.id].orEmpty(),
                    inSavedForLater = work.id in index.savedForLaterIds
                )
            },
            userTags = index.userTags,
            collections = index.collections,
            privacy = settings.privacy,
            confirmBeforeDelete = settings.app.confirmBeforeDelete
        )
    }.distinctUntilChanged().flowOn(Dispatchers.Default).onEach { emitted ->
        latestSnapshotState.value = emitted
    }.let { upstream ->
        if (shareScope == null) {
            upstream
        } else {
            upstream.shareIn(shareScope, SharingStarted.Eagerly, replay = 1)
        }
    }

    fun observeSnapshot(): Flow<LibrarySnapshot> = snapshots

    /** Last snapshot, if the process-wide collector has already produced one. */
    fun latestSnapshot(): LibrarySnapshot? = latestSnapshotState.value

    fun observeRecentlyDeletedCount(): Flow<Int> = combine(
        workRepository.observeRecentlyDeleted(),
        workRepository.observeRecentlyDeletedCollections()
    ) { works, collections -> works.size + collections.size }
}
