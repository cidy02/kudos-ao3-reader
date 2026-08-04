package io.github.cidy02.kudos.search

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import io.github.cidy02.kudos.core.model.SavedSearch
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3SearchRepository
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.works.CanonicalWork
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.works.WorkTags
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class SearchViewModel(
    private val repository: AO3SearchRepository,
    private val savedSearchRepository: SavedSearchRepository? = null,
    private val workRepository: WorkRepository? = null
) : ViewModel() {

    private val _filters = MutableStateFlow(AO3SearchFilters())
    val filters: StateFlow<AO3SearchFilters> = _filters.asStateFlow()

    private val _state = MutableStateFlow<SearchUiState>(SearchUiState.Idle)
    val state: StateFlow<SearchUiState> = _state.asStateFlow()

    private val _savedSearches = MutableStateFlow<List<SavedSearch>>(emptyList())
    val savedSearches: StateFlow<List<SavedSearch>> = _savedSearches.asStateFlow()

    private val _selectionMode = MutableStateFlow(false)
    val selectionMode: StateFlow<Boolean> = _selectionMode.asStateFlow()

    private val _selectedWorkIds = MutableStateFlow<Set<Long>>(emptySet())
    val selectedWorkIds: StateFlow<Set<Long>> = _selectedWorkIds.asStateFlow()

    private var lastFilters = AO3SearchFilters()
    private var searchGeneration = 0

    val localMatches: StateFlow<List<CanonicalWork>> = combine(
        _filters.map { it.query },
        workRepository?.observeSavedWorks() ?: kotlinx.coroutines.flow.flowOf(emptyList())
    ) { query, works ->
        val trimmed = query.trim()
        if (trimmed.length < 2) emptyList()
        else {
            val terms = io.github.cidy02.kudos.works.WorkSearchIndex.terms(trimmed)
            works.filter { work ->
                io.github.cidy02.kudos.works.WorkSearchIndex.matches(work, terms)
            }.map { CanonicalWork(local = it, remote = it.toRemoteSummary()) }
        }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    init {
        refreshSavedSearches()
    }

    fun updateFilters(newFilters: AO3SearchFilters) {
        _filters.value = newFilters
    }

    fun runSearch(page: Int = 1, searchFilters: AO3SearchFilters = _filters.value) {
        if (!searchFilters.isSearchable) {
            _state.value = SearchUiState.Idle
            return
        }

        lastFilters = searchFilters
        _state.value = SearchUiState.Loading
        val generation = ++searchGeneration
        viewModelScope.launch {
            val result = when (val res = repository.search(searchFilters, page)) {
                is AO3Result.Success -> {
                    val localWorks = workRepository?.listSavedWorks().orEmpty()
                    val merged = res.value.works.map { remote ->
                        val local = localWorks.find { WorkTags.ao3WorkIdFromUrl(it.sourceUrl) == remote.id }
                        CanonicalWork(local = local, remote = remote)
                    }
                    SearchUiState.Results(res.value, merged)
                }
                is AO3Result.Failure -> SearchUiState.Error(res.error, page)
            }
            if (generation == searchGeneration) _state.value = result
        }
    }

    fun retry() {
        val page = when (val current = _state.value) {
            is SearchUiState.Error -> current.page
            is SearchUiState.Results -> current.page.currentPage
            else -> 1
        }
        runSearch(page, lastFilters)
    }

    fun clearFilters() {
        _filters.value = clearedFiltersPreservingQuery(_filters.value)
        if (_state.value !is SearchUiState.Idle) runSearch()
    }

    fun refreshSavedSearches() {
        val repo = savedSearchRepository ?: return
        viewModelScope.launch {
            _savedSearches.value = repo.getAll()
        }
    }

    fun saveCurrentSearch(name: String) {
        val repo = savedSearchRepository ?: return
        val filters = _filters.value
        if (name.isBlank() || !filters.isSearchable) return
        viewModelScope.launch {
            repo.save(name, filters)
            refreshSavedSearches()
        }
    }

    fun deleteSavedSearch(id: String) {
        val repo = savedSearchRepository ?: return
        viewModelScope.launch {
            repo.delete(id)
            refreshSavedSearches()
        }
    }

    fun runSavedSearch(saved: SavedSearch) {
        val repo = savedSearchRepository ?: return
        val restored = repo.filtersOf(saved)
        _filters.value = restored
        runSearch(1, restored)
    }

    fun searchTag(tag: String) {
        val next = AO3SearchFilters(additionalTags = tag)
        _filters.value = next
        runSearch(1, next)
    }

    fun enterSelectionMode() {
        _selectionMode.value = true
        _selectedWorkIds.value = emptySet()
    }

    fun exitSelectionMode() {
        _selectionMode.value = false
        _selectedWorkIds.value = emptySet()
    }

    fun toggleWorkSelection(workId: Long) {
        _selectedWorkIds.update { current ->
            if (workId in current) current - workId else current + workId
        }
    }

    companion object {
        fun factory(
            repository: AO3SearchRepository,
            savedSearchRepository: SavedSearchRepository? = null,
            workRepository: WorkRepository? = null
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                SearchViewModel(repository, savedSearchRepository, workRepository)
            }
        }
    }
}

private fun SavedWork.toRemoteSummary(): AO3WorkSummary {
    return AO3WorkSummary(
        id = WorkTags.ao3WorkIdFromUrl(sourceUrl) ?: 0,
        title = title,
        authors = author.split(",").map { it.trim() },
        fandoms = workFandoms,
        rating = rating,
        warnings = workWarnings,
        categories = workCategories,
        relationships = workRelationships,
        characters = workCharacters,
        freeforms = workFreeforms,
        language = language,
        wordCount = wordCount,
        chapters = chapters,
        kudos = kudos,
        comments = comments,
        hits = hits
    )
}
