package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.works.WorkRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map

class LibraryRepository(
    private val workRepository: WorkRepository,
    private val settings: Flow<KudosSettings> = flowOf(KudosSettings.Defaults)
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

    fun observeSnapshot(): Flow<LibrarySnapshot> {
        return combine(workRepository.observeSavedWorks(), settings) { works, settings ->
            val items = works.map { work ->
                LibraryWorkListItem(
                    work = work,
                    userTags = workRepository.userTagsForWork(work.id),
                    collections = workRepository.collectionsForWork(work.id)
                )
            }
            LibrarySnapshot(
                items = items,
                userTags = workRepository.allUserTags(),
                collections = workRepository.allCollections(),
                privacy = settings.privacy,
                confirmBeforeDelete = settings.app.confirmBeforeDelete
            )
        }
    }
}
