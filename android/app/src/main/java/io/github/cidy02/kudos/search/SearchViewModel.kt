package io.github.cidy02.kudos.search

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import io.github.cidy02.kudos.core.model.SavedSearch
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.Tag
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.browse.AO3Fandom
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3SearchRepository
import io.github.cidy02.kudos.works.CanonicalWork
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.works.WorkTags
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.transformLatest
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class SearchViewModel(
    private val repository: AO3SearchRepository,
    private val savedSearchRepository: SavedSearchRepository? = null,
    private val workRepository: WorkRepository? = null,
    /**
     * Which saved works Hide mode is leaving out of lists right now. Search listed them
     * anyway, with their title and summary, and listed a fandom that only one of them
     * carries (audit A19-3; iOS `PrivacyGate.isHidden`, as Home applies it).
     */
    hiddenWorks: Flow<(SavedWork) -> Boolean> = flowOf({ false })
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

    private val _isPaging = MutableStateFlow(false)
    val isPaging: StateFlow<Boolean> = _isPaging.asStateFlow()

    private val catalog = MutableStateFlow<List<AO3Fandom>>(emptyList())
    private val userTags = MutableStateFlow<List<Tag>>(emptyList())
    private val collections = MutableStateFlow<List<WorkCollection>>(emptyList())

    private var lastFilters = AO3SearchFilters()
    private var searchGeneration = 0
    private var requestedPage: Int? = null
    private var loadJob: Job? = null
    private val filterHistory = ArrayDeque<FilterHistoryEntry>()

    private val savedWorks: Flow<List<SavedWork>> =
        workRepository?.observeSavedWorks() ?: flowOf(emptyList())

    /**
     * Live on-device matches. An empty query clears at once so the idle screen
     * does not lag a debounce; any other keystroke waits 150ms, and a newer
     * one cancels the wait.
     */
    val localMatches: StateFlow<SearchLocalMatches> = combine(
        _filters.map { it.query.trim() }.distinctUntilChanged().transformLatest { query ->
            if (query.isEmpty()) emit("") else {
                delay(150)
                emit(query)
            }
        },
        combine(savedWorks, hiddenWorks) { works, isHidden -> works.filterNot(isHidden) },
        userTags,
        collections,
        catalog
    ) { query, works, tags, cols, fandoms ->
        computeSearchLocalMatches(query, works, tags, cols, fandoms)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), SearchLocalMatches())

    init {
        refreshSavedSearches()
        val repo = workRepository
        if (repo != null) {
            viewModelScope.launch {
                savedWorks.collect {
                    userTags.value = runCatching { repo.allUserTags() }.getOrDefault(emptyList())
                    collections.value = runCatching { repo.allCollections() }.getOrDefault(emptyList())
                }
            }
        }
    }

    fun setCatalogFandoms(fandoms: List<AO3Fandom>) {
        catalog.value = fandoms
    }

    fun updateFilters(newFilters: AO3SearchFilters) {
        _filters.value = newFilters
    }

    fun runSearch(page: Int = 1, searchFilters: AO3SearchFilters = _filters.value) {
        if (!searchFilters.isSearchable) {
            searchGeneration++
            loadJob?.cancel()
            _isPaging.value = false
            _state.value = SearchUiState.Idle
            return
        }
        launchSearch(page, searchFilters, keepResults = false)
    }

    fun loadPage(page: Int) {
        val current = _state.value as? SearchUiState.Results ?: return
        if (page == current.page.currentPage || page < 1 || page > current.page.totalPages) return
        if (_filters.value != lastFilters) {
            runSearch()
            return
        }
        _selectedWorkIds.value = emptySet()
        launchSearch(page, lastFilters, keepResults = true)
    }

    /**
     * Re-runs the current page and suspends until it completes, so the shared
     * pull-to-refresh spinner tracks the real request instead of clearing
     * instantly. [runSearch] launches into `viewModelScope` and returns at once,
     * which is right for a typed query but wrong for a pull gesture.
     */
    suspend fun refreshCurrentPage() {
        val page = when (val current = _state.value) {
            is SearchUiState.Error -> current.page
            is SearchUiState.Results -> current.page.currentPage
            else -> return
        }
        val searchFilters = lastFilters
        if (!searchFilters.isSearchable) return
        val stale = when (val current = _state.value) {
            is SearchUiState.Results -> current
            is SearchUiState.Error -> current.stale
            else -> null
        }
        loadJob?.cancel()
        val generation = ++searchGeneration
        _isPaging.value = stale != null
        val result = fetch(searchFilters, page, stale)
        if (generation == searchGeneration) {
            _isPaging.value = false
            if (result is SearchUiState.Results) requestedPage = null
            _state.value = result
        }
    }

    fun retry() {
        val error = _state.value as? SearchUiState.Error ?: return
        val page = searchRetryPage(requestedPage, error.page, error.stale != null)
        if (page == null) {
            runSearch(1, lastFilters)
        } else if (error.stale != null) {
            _state.value = error.stale
            launchSearch(page, lastFilters, keepResults = true)
        } else {
            launchSearch(page, lastFilters, keepResults = false)
        }
    }

    fun clearFilters() {
        filterHistory.clear()
        val cleared = clearedFiltersPreservingQuery(_filters.value)
        _filters.value = cleared
        if (cleared.isSearchable) {
            runSearch(1, cleared)
        } else {
            searchGeneration++
            loadJob?.cancel()
            _isPaging.value = false
            lastFilters = cleared
            _state.value = SearchUiState.Idle
        }
    }

    fun clearQuery() {
        val next = _filters.value.copy(query = "")
        _filters.value = next
        if (!next.hasActiveFilters) {
            searchGeneration++
            loadJob?.cancel()
            filterHistory.clear()
            _isPaging.value = false
            lastFilters = next
            _state.value = SearchUiState.Idle
        }
    }

    /**
     * Back through a tag drill-down, then from results to the idle search.
     * Returns false when Search is already idle so the shell can leave the tab.
     */
    fun goBack(): Boolean {
        val previous = filterHistory.removeLastOrNull()
        if (previous != null) {
            loadJob?.cancel()
            searchGeneration++
            _isPaging.value = false
            requestedPage = null
            _selectedWorkIds.value = emptySet()
            lastFilters = previous.filters
            _filters.value = previous.filters
            _state.value = SearchUiState.Results(previous.page, previous.works)
            return true
        }
        if (_state.value !is SearchUiState.Idle) {
            returnToIdle()
            return true
        }
        return false
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
        filterHistory.clear()
        _filters.value = restored
        runSearch(1, restored)
    }

    fun searchTag(field: SearchSubjectField, tag: String, isFreshTabJump: Boolean = false) {
        if (isFreshTabJump) filterHistory.clear() else pushCurrentResults()
        val next = tagSearchFilters(field, tag)
        _filters.value = next
        runSearch(1, next)
    }

    fun searchFandom(name: String) {
        val next = withIncludedFandom(_filters.value, name)
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

    private fun returnToIdle() {
        loadJob?.cancel()
        searchGeneration++
        _isPaging.value = false
        filterHistory.clear()
        requestedPage = null
        _selectedWorkIds.value = emptySet()
        val cleared = AO3SearchFilters()
        _filters.value = cleared
        lastFilters = cleared
        _state.value = SearchUiState.Idle
    }

    private fun pushCurrentResults() {
        val current = _state.value as? SearchUiState.Results ?: return
        if (!lastFilters.isSearchable && !_filters.value.isSearchable) return
        filterHistory.addLast(
            FilterHistoryEntry(
                filters = lastFilters,
                page = current.page,
                works = current.works
            )
        )
    }

    private fun launchSearch(page: Int, searchFilters: AO3SearchFilters, keepResults: Boolean) {
        lastFilters = searchFilters
        requestedPage = page
        val stale = if (keepResults) _state.value as? SearchUiState.Results else null
        if (stale == null) {
            _state.value = SearchUiState.Loading
            _isPaging.value = false
        } else {
            _isPaging.value = true
        }
        loadJob?.cancel()
        val generation = ++searchGeneration
        loadJob = viewModelScope.launch {
            val result = fetch(searchFilters, page, stale)
            if (generation != searchGeneration) return@launch
            _isPaging.value = false
            if (result is SearchUiState.Results) requestedPage = null
            _state.value = result
        }
    }

    private suspend fun fetch(
        searchFilters: AO3SearchFilters,
        page: Int,
        stale: SearchUiState.Results?
    ): SearchUiState {
        return when (val res = repository.search(searchFilters, page)) {
            is AO3Result.Success -> {
                val localWorks = workRepository?.listSavedWorks().orEmpty()
                val merged = res.value.works.map { remote ->
                    val local = localWorks.find { WorkTags.ao3WorkIdFromUrl(it.sourceUrl) == remote.id }
                    CanonicalWork(local = local, remote = remote)
                }
                SearchUiState.Results(res.value, merged)
            }
            is AO3Result.Failure -> SearchUiState.Error(res.error, page, stale)
        }
    }

    private data class FilterHistoryEntry(
        val filters: AO3SearchFilters,
        val page: AO3SearchPage,
        val works: List<CanonicalWork>
    )

    companion object {
        fun factory(
            repository: AO3SearchRepository,
            savedSearchRepository: SavedSearchRepository? = null,
            workRepository: WorkRepository? = null,
            hiddenWorks: Flow<(SavedWork) -> Boolean> = flowOf({ false })
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                SearchViewModel(repository, savedSearchRepository, workRepository, hiddenWorks)
            }
        }
    }
}
