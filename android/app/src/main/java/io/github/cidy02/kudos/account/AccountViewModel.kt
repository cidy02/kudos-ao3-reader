package io.github.cidy02.kudos.account

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.AO3AuthState
import io.github.cidy02.kudos.auth.usernameOrNull
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorRepository
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorRoute
import io.github.cidy02.kudos.works.CanonicalWorkMerge
import io.github.cidy02.kudos.works.WorkRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import kotlinx.coroutines.ensureActive
import io.github.cidy02.kudos.network.ao3.displayMessage

/**
 * Inline Writing → Series pane: loads the signed-in user's own series via the
 * author-profile series parser (iOS `syncProfileTab(.series)` parity).
 */
class AccountSeriesViewModel(
    private val username: String,
    private val authorRepository: AO3AuthorRepository
) : ViewModel() {
    private val mutableState = MutableStateFlow<AccountSeriesUiState>(AccountSeriesUiState.Loading)
    val uiState: StateFlow<AccountSeriesUiState> = mutableState

    init {
        load(1)
    }

    fun load(page: Int) {
        viewModelScope.launch {
            mutableState.value = AccountSeriesUiState.Loading
            val route = AO3AuthorRoute(username)
            mutableState.value = when (val result = authorRepository.loadSeries(route, page)) {
                is AO3Result.Success -> AccountSeriesUiState.Loaded(result.value)
                is AO3Result.Failure -> {
                    if (result.error == AO3Error.AuthenticationRequired) {
                        AccountSeriesUiState.AuthRequired
                    } else {
                        AccountSeriesUiState.Failed(result.error.displayMessage())
                    }
                }
            }
        }
    }

    companion object {
        fun factory(
            username: String,
            authorRepository: AO3AuthorRepository
        ): ViewModelProvider.Factory {
            return object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T {
                    return AccountSeriesViewModel(username, authorRepository) as T
                }
            }
        }
    }
}

sealed interface AccountSeriesUiState {
    data object Loading : AccountSeriesUiState
    data object AuthRequired : AccountSeriesUiState
    data class Loaded(
        val page: io.github.cidy02.kudos.network.ao3.author.AO3AuthorSeriesPage
    ) : AccountSeriesUiState
    data class Failed(val message: String) : AccountSeriesUiState
}

class AccountViewModel(
    private val authRepository: AO3AuthRepository,
    private val authorRepository: AO3AuthorRepository? = null,
    private val countsCache: AO3AccountListCountsCache? = null,
    private val listRepository: AccountListRepository? = null
) : ViewModel() {
    private val headerFlow = MutableStateFlow<io.github.cidy02.kudos.network.ao3.author.AO3AuthorHeader?>(null)
    private val countsFlow = MutableStateFlow<Map<String, AO3AccountListCountsCache.Count>>(emptyMap())

    val uiState: StateFlow<AccountUiState> = combine(
        authRepository.state,
        authRepository.sessionHealth,
        headerFlow,
        countsFlow
    ) { authState, sessionHealth, header, counts ->
        AccountUiState(
            authState = authState,
            sessionHealth = sessionHealth,
            header = header,
            counts = counts
        )
    }.stateIn(
        viewModelScope,
        SharingStarted.WhileSubscribed(5_000),
        AccountUiState()
    )

    init {
        viewModelScope.launch {
            authRepository.restoreSession()
            authRepository.state.collect { auth ->
                val username = auth.usernameOrNull
                if (username != null) {
                    refreshHeader(username)
                    refreshCounts(username)
                    if (countsCache?.get(AccountListType.Subscriptions, username) == null && listRepository != null) {
                        listRepository.load(AccountListType.Subscriptions, 1)
                        refreshCounts(username)
                    }
                }
            }
        }
    }

    private fun refreshHeader(username: String) {
        val repo = authorRepository ?: return
        viewModelScope.launch {
            when (val result = repo.loadDashboard(AO3AuthorRoute(username))) {
                is AO3Result.Success -> headerFlow.value = result.value
                is AO3Result.Failure -> Unit
            }
        }
    }

    private fun refreshCounts(username: String) {
        val cache = countsCache ?: return
        val map = mutableMapOf<String, AO3AccountListCountsCache.Count>()
        for (entry in AccountListType.hubEntries) {
            // Sealed-class data-object singletons can be JVM-null during class
            // init when the companion's hubEntries list is accessed early in a
            // coroutine dispatch.  Guard defensively — the cache is best-effort.
            @Suppress("SENSELESS_COMPARISON")
            if (entry == null) continue
            cache.get(entry, username)?.let { map[entry.listKey] = it }
        }
        countsFlow.value = map
    }

    fun logout() {
        viewModelScope.launch { authRepository.logout() }
    }

    fun verifySession() {
        viewModelScope.launch { authRepository.verifySession() }
    }

    companion object {
        fun factory(
            authRepository: AO3AuthRepository,
            authorRepository: AO3AuthorRepository? = null,
            countsCache: AO3AccountListCountsCache? = null,
            listRepository: AccountListRepository? = null
        ): ViewModelProvider.Factory {
            return object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T {
                    return AccountViewModel(authRepository, authorRepository, countsCache, listRepository) as T
                }
            }
        }
    }
}

class AccountListViewModel(
    private val type: AccountListType,
    private val repository: AccountListRepository,
    private val workRepository: WorkRepository
) : ViewModel() {
    private val mutableState = MutableStateFlow<AccountListUiState>(AccountListUiState.Loading)
    val uiState: StateFlow<AccountListUiState> = combine(
        mutableState,
        workRepository.observeLibraryWorks()
    ) { state, local ->
        if (state is AccountListUiState.Loaded) {
            state.copy(
                canonicalWorks = CanonicalWorkMerge.remoteLed(state.page.works, local)
            )
        } else {
            state
        }
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = AccountListUiState.Loading
    )

    init {
        load(1)
    }

    fun load(page: Int) {
        viewModelScope.launch {
            mutableState.value = AccountListUiState.Loading
            val result = repository.load(type, page)
            mutableState.value = when (result) {
                is AO3Result.Success -> {
                    // Update the counts cache whenever a list page is loaded (Item 9).
                    val username = repository.authRepository.username()
                    if (username != null) {
                        repository.countsCache?.put(
                            type,
                            username,
                            AO3AccountListCountsCache.Count(
                                itemsOnPage = result.value.works.size,
                                totalPages = result.value.totalPages
                            )
                        )
                    }
                    AccountListUiState.Loaded(result.value)
                }
                is AO3Result.Failure -> {
                    if (result.error == AO3Error.AuthenticationRequired) {
                        AccountListUiState.AuthRequired
                    } else {
                        AccountListUiState.Failed(result.error.displayMessage())
                    }
                }
            }
        }
    }

    companion object {
        fun factory(
            type: AccountListType,
            repository: AccountListRepository,
            workRepository: WorkRepository
        ): ViewModelProvider.Factory {
            return object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T {
                    return AccountListViewModel(type, repository, workRepository) as T
                }
            }
        }
    }
}

class AO3CollectionsViewModel(
    private val repository: AccountListRepository
) : ViewModel() {
    private val mutableState = MutableStateFlow<AO3CollectionsUiState>(AO3CollectionsUiState.Loading)
    private val boundSession = MutableStateFlow<Int?>(null)
    private val mutableFilters = MutableStateFlow(AO3CollectionsFilter())
    val filters: StateFlow<AO3CollectionsFilter> = mutableFilters
    private var loadJob: Job? = null
    private var loadGeneration = 0
    private var visible = false
    private var requestedPage = 1
    private val auth get() = repository.authRepository

    // Hide old rows in the same state emission that observes a session change.
    val uiState: StateFlow<AO3CollectionsUiState> = combine(
        mutableState, boundSession, auth.generation, auth.state
    ) { state, bound, generation, authState ->
        when {
            authState !is AO3AuthState.SignedIn ->
                AO3CollectionsUiState.AuthRequired
            bound != generation -> AO3CollectionsUiState.Loading
            else -> state
        }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), AO3CollectionsUiState.Loading)

    init {
        viewModelScope.launch {
            combine(auth.generation, auth.state) { generation, state -> generation to state }
                .collect { (generation, state) ->
                    if (boundSession.value != generation) {
                        cancelLoad()
                        mutableState.value = AO3CollectionsUiState.Loading
                        requestedPage = 1
                        boundSession.value = generation
                    }
                    if (visible && state is AO3AuthState.SignedIn &&
                        mutableState.value == AO3CollectionsUiState.Loading && loadJob?.isActive != true
                    ) load()
                }
        }
    }

    fun onAppear() {
        visible = true
        if (auth.state.value !is AO3AuthState.SignedIn) return
        if (boundSession.value != auth.generation.value) {
            cancelLoad()
            mutableState.value = AO3CollectionsUiState.Loading
            requestedPage = 1
            boundSession.value = auth.generation.value
        }
        val state = mutableState.value
        if (state is AO3CollectionsUiState.Loaded) {
            if (filters.value.needsWholeIndex && state.wholeIndex == null) startLoad(wholeOnly = true)
        } else if (loadJob?.isActive != true) load()
    }

    fun onDisappear() {
        visible = false
        cancelLoad()
    }

    fun setFilters(filter: AO3CollectionsFilter) {
        val previous = mutableFilters.value
        if (filter == previous) return
        mutableFilters.value = filter
        val state = mutableState.value as? AO3CollectionsUiState.Loaded ?: return
        if (!filter.needsWholeIndex) {
            cancelLoad()
            mutableState.value = state.copy(wholeIndexLoading = false, wholeIndexError = null)
        } else if (!previous.needsWholeIndex && state.wholeIndex == null &&
            loadJob?.isActive != true && visible
        ) {
            startLoad(wholeOnly = true)
        }
    }

    fun clearFilters() = setFilters(AO3CollectionsFilter())

    fun load() {
        val state = mutableState.value as? AO3CollectionsUiState.Loaded
        startLoad(wholeOnly = filters.value.needsWholeIndex && state != null)
    }

    fun loadPage(page: Int) {
        if (filters.value.needsWholeIndex) return
        requestedPage = page.coerceAtLeast(1)
        startLoad()
    }

    fun dismissPageError() {
        val state = mutableState.value as? AO3CollectionsUiState.Loaded ?: return
        mutableState.value = state.copy(pageError = null)
    }

    /** Awaited by KudosRefreshBox; cancellation of its composition also cancels this load. */
    suspend fun refresh() {
        val state = mutableState.value as? AO3CollectionsUiState.Loaded
        requestedPage = AO3CollectionsWholeIndex.refreshPage(
            state?.currentPage ?: requestedPage, filters.value.needsWholeIndex
        )
        if (state != null) mutableState.value = state.copy(
            wholeIndex = null, wholeIndexPartialNote = null, wholeIndexError = null
        )
        val job = startLoad()
        try {
            job.join()
        } finally {
            if (!currentCoroutineContext().isActive) job.cancel()
        }
    }

    private fun cancelLoad() {
        loadGeneration += 1
        loadJob?.cancel()
    }

    private fun startLoad(wholeOnly: Boolean = false): Job {
        val previousJob = loadJob
        cancelLoad()
        val generation = loadGeneration
        val session = auth.generation.value
        val previousState = mutableState.value as? AO3CollectionsUiState.Loaded
        val page = requestedPage
        val job = viewModelScope.launch {
            // Join a cancelled predecessor before issuing another page request.
            previousJob?.join()
            if (!visible || auth.state.value !is AO3AuthState.SignedIn ||
                auth.username() == null || session != auth.generation.value
            ) return@launch
            boundSession.value = session
            try {
                if (!wholeOnly) {
                    mutableState.value = AO3CollectionsUiState.Loading
                    when (val result = repository.loadCollectionsIndex(page)) {
                        is AO3Result.Success -> {
                            currentCoroutineContext().ensureActive()
                            if (generation != loadGeneration || session != auth.generation.value) return@launch
                            val index = result.value
                            requestedPage = index.currentPage
                            mutableState.value = AO3CollectionsUiState.Loaded(
                                index.collections, index.currentPage, index.totalPages.coerceAtLeast(1)
                            )
                        }
                        is AO3Result.Failure -> {
                            if (generation != loadGeneration || session != auth.generation.value) return@launch
                            mutableState.value = if (result.error == AO3Error.AuthenticationRequired) {
                                AO3CollectionsUiState.AuthRequired
                            } else if (!filters.value.needsWholeIndex && previousState != null &&
                                previousState.collections.isNotEmpty()
                            ) {
                                previousState.copy(pageError = result.error.displayMessage())
                            } else AO3CollectionsUiState.Failed(result.error.displayMessage())
                            return@launch
                        }
                    }
                }
                if (filters.value.needsWholeIndex) loadWholeIndex(generation, session)
            } finally {
                if (generation == loadGeneration) {
                    val state = mutableState.value as? AO3CollectionsUiState.Loaded
                    if (state?.wholeIndexLoading == true) {
                        mutableState.value = state.copy(wholeIndexLoading = false)
                    }
                }
            }
        }
        loadJob = job
        return job
    }

    private suspend fun loadWholeIndex(generation: Int, session: Int) {
        val state = mutableState.value as? AO3CollectionsUiState.Loaded ?: return
        if (state.wholeIndex != null) return
        mutableState.value = state.copy(wholeIndexLoading = true, wholeIndexError = null)
        val reuse = AO3CollectionsWholeIndex.canReusePageOne(
            state.currentPage, boundSession.value == session, listIsLoaded = true
        )
        val accumulated = if (reuse) state.collections.toMutableList() else mutableListOf()
        var page = if (reuse) 2 else 1
        var totalPages = if (reuse) state.totalPages else 1
        var lastPageWasEmpty = false
        while (page <= totalPages.coerceIn(1, AO3CollectionsWholeIndex.maximumPages)) {
            currentCoroutineContext().ensureActive()
            if (generation != loadGeneration || session != auth.generation.value ||
                !filters.value.needsWholeIndex
            ) return
            when (val result = repository.loadCollectionsIndex(page)) {
                is AO3Result.Failure -> {
                    if (generation != loadGeneration || session != auth.generation.value) return
                    mutableState.value = if (result.error == AO3Error.AuthenticationRequired) {
                        AO3CollectionsUiState.AuthRequired
                    } else state.copy(wholeIndexError = result.error.displayMessage())
                    return
                }
                is AO3Result.Success -> {
                    currentCoroutineContext().ensureActive()
                    val index = result.value
                    if (!AO3CollectionsWholeIndex.append(
                            index, accumulated, generation, loadGeneration, session, auth.generation.value
                        )) return
                    totalPages = maxOf(totalPages, index.currentPage, index.totalPages)
                    lastPageWasEmpty = index.collections.isEmpty()
                    page = AO3CollectionsWholeIndex.nextPage(page, totalPages, lastPageWasEmpty) ?: break
                }
            }
        }
        if (generation != loadGeneration || session != auth.generation.value ||
            !filters.value.needsWholeIndex
        ) return
        mutableState.value = state.copy(
            wholeIndex = accumulated.toList(),
            wholeIndexPartialNote = AO3CollectionsWholeIndex.partialNote(totalPages, lastPageWasEmpty)
        )
    }

    companion object {
        fun factory(repository: AccountListRepository): ViewModelProvider.Factory {
            return object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T {
                    return AO3CollectionsViewModel(repository) as T
                }
            }
        }
    }
}
