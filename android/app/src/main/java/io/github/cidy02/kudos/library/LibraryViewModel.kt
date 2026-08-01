package io.github.cidy02.kudos.library

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import io.github.cidy02.kudos.works.WorkRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class LibraryViewModel(
    repository: LibraryRepository,
    private val workRepository: WorkRepository,
    private val settingsRepository: io.github.cidy02.kudos.data.preferences.SettingsRepository? = null
) : ViewModel() {
    private val searchQuery = MutableStateFlow("")
    private val filters = MutableStateFlow(LibraryFilterState())
    private val sort = MutableStateFlow(LibrarySort.RecentlyAdded)
    private val selectionMode = MutableStateFlow(false)
    private val selectedWorkIds = MutableStateFlow<Set<String>>(emptySet())

    private val libraryBase: StateFlow<LibraryUiState> = combine(
        repository.observeSnapshot(),
        searchQuery,
        filters,
        sort
    ) { snapshot, query, filters, sort ->
        LibraryQuery.buildState(snapshot, query, filters, sort)
    }.catch { throwable ->
        emit(
            LibraryUiState(
                loading = false,
                error = throwable.message ?: "Library could not be loaded."
            )
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = LibraryUiState(loading = true)
    )

    val state: StateFlow<LibraryUiState> = combine(
        libraryBase,
        selectionMode,
        selectedWorkIds
    ) { base, selecting, ids ->
        base.copy(
            selectionMode = selecting,
            selectedWorkIds = if (selecting) ids else emptySet()
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = LibraryUiState(loading = true)
    )

    fun updateSearchQuery(query: String) {
        searchQuery.value = query
    }

    fun updateSort(next: LibrarySort) {
        sort.value = next
    }

    fun toggleFavoriteOnly() {
        filters.update { it.copy(favoriteOnly = !it.favoriteOnly) }
    }

    fun setFinishedFilter(next: LibraryFinishedFilter) {
        filters.update { it.copy(finished = next) }
    }

    fun setDownloadFilter(next: LibraryDownloadFilter) {
        filters.update { it.copy(download = next) }
    }

    fun toggleUserTag(tagId: String) {
        filters.update { it.copy(userTagIds = it.userTagIds.toggle(tagId)) }
    }

    fun toggleCollection(collectionId: String) {
        filters.update { it.copy(collectionIds = it.collectionIds.toggle(collectionId)) }
    }

    fun clearFilters() {
        filters.value = LibraryFilterState()
    }

    // region Multi-select

    fun enterSelectionMode(initialWorkId: String? = null) {
        selectionMode.value = true
        selectedWorkIds.value = if (initialWorkId != null) {
            LibrarySelection.selectOnly(initialWorkId)
        } else {
            LibrarySelection.clear()
        }
    }

    fun exitSelectionMode() {
        selectionMode.value = false
        selectedWorkIds.value = LibrarySelection.clear()
    }

    fun toggleWorkSelection(workId: String) {
        if (!selectionMode.value) {
            enterSelectionMode(workId)
            return
        }
        selectedWorkIds.update { LibrarySelection.toggle(it, workId) }
    }

    fun bulkSetFavorite(favorite: Boolean) {
        val ids = selectedWorkIds.value
        if (ids.isEmpty()) return
        viewModelScope.launch {
            for (id in ids) {
                workRepository.setFavorite(id, favorite)
            }
            exitSelectionMode()
        }
    }

    fun bulkSetFinished(finished: Boolean) {
        val ids = selectedWorkIds.value
        if (ids.isEmpty()) return
        viewModelScope.launch {
            for (id in ids) {
                workRepository.setFinished(id, finished)
            }
            exitSelectionMode()
        }
    }

    fun bulkSoftDelete() {
        val ids = selectedWorkIds.value
        if (ids.isEmpty()) return
        viewModelScope.launch {
            for (id in ids) {
                workRepository.softDelete(id)
            }
            exitSelectionMode()
        }
    }

    // endregion

    // region Context-menu single-work actions

    fun toggleFavoriteOne(workId: String) {
        viewModelScope.launch {
            val work = workRepository.getWork(workId) ?: return@launch
            workRepository.setFavorite(workId, !work.isFavorite)
        }
    }

    fun toggleFinishedOne(workId: String) {
        viewModelScope.launch {
            workRepository.toggleFinished(workId)
        }
    }

    fun softDeleteOne(workId: String) {
        viewModelScope.launch {
            workRepository.softDelete(workId)
        }
    }

    /** Apple MatureRevealToggle: flip hide-mature for this device. */
    fun toggleHideMature() {
        val settings = settingsRepository ?: return
        viewModelScope.launch {
            val current = settings.snapshot()
            settings.updateHideMatureContent(!current.privacy.hideMatureContent)
        }
    }

    // endregion

    companion object {
        fun factory(
            repository: LibraryRepository,
            workRepository: WorkRepository,
            settingsRepository: io.github.cidy02.kudos.data.preferences.SettingsRepository? = null
        ): ViewModelProvider.Factory =
            viewModelFactory {
                initializer {
                    LibraryViewModel(repository, workRepository, settingsRepository)
                }
            }
    }
}

private fun Set<String>.toggle(value: String): Set<String> {
    return if (value in this) this - value else this + value
}
