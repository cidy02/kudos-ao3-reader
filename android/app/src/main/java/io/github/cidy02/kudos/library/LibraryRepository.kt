package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.works.WorkRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flowOf

class LibraryRepository(
    private val workRepository: WorkRepository,
    private val settings: Flow<KudosSettings> = flowOf(KudosSettings.Defaults)
) {
    fun observeSavedWorks(): Flow<List<SavedWork>> = workRepository.observeSavedWorks()

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
                privacy = settings.privacy
            )
        }
    }
}
