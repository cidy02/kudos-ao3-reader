package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.works.WorkRepository
import kotlinx.coroutines.flow.Flow

class LibraryRepository(
    private val workRepository: WorkRepository
) {
    fun observeSavedWorks(): Flow<List<SavedWork>> = workRepository.observeSavedWorks()
}
