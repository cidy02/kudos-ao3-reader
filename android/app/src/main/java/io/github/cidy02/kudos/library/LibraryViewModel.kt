package io.github.cidy02.kudos.library

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update

class LibraryViewModel(
    repository: LibraryRepository
) : ViewModel() {
    private val searchQuery = MutableStateFlow("")
    private val filters = MutableStateFlow(LibraryFilterState())
    private val sort = MutableStateFlow(LibrarySort.RecentlyAdded)

    val state: StateFlow<LibraryUiState> = combine(
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

    companion object {
        fun factory(repository: LibraryRepository): ViewModelProvider.Factory =
            viewModelFactory {
                initializer { LibraryViewModel(repository) }
            }
    }
}

private fun Set<String>.toggle(value: String): Set<String> {
    return if (value in this) this - value else this + value
}
