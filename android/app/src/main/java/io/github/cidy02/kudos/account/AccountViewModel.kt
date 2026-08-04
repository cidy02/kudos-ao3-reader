package io.github.cidy02.kudos.account

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import io.github.cidy02.kudos.auth.AO3AuthRepository
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
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class AccountViewModel(
    private val authRepository: AO3AuthRepository,
    private val authorRepository: AO3AuthorRepository? = null,
    private val countsCache: AO3AccountListCountsCache? = null
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
            val auth = authRepository.state.first()
            val username = auth.usernameOrNull
            if (username != null) {
                refreshHeader(username)
                refreshCounts(username)
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
        AccountListType.hubEntries.forEach { type ->
            cache.get(type, username)?.let { map[type.listKey] = it }
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
            countsCache: AO3AccountListCountsCache? = null
        ): ViewModelProvider.Factory {
            return object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T {
                    return AccountViewModel(authRepository, authorRepository, countsCache) as T
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
        workRepository.observeSavedWorks()
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
    private val mutableState = kotlinx.coroutines.flow.MutableStateFlow<AO3CollectionsUiState>(
        AO3CollectionsUiState.Loading
    )
    val uiState: StateFlow<AO3CollectionsUiState> = mutableState

    init {
        load()
    }

    fun load() {
        viewModelScope.launch {
            mutableState.value = AO3CollectionsUiState.Loading
            mutableState.value = when (val result = repository.loadCollections()) {
                is AO3Result.Success -> AO3CollectionsUiState.Loaded(result.value)
                is AO3Result.Failure -> {
                    if (result.error == AO3Error.AuthenticationRequired) {
                        AO3CollectionsUiState.AuthRequired
                    } else {
                        AO3CollectionsUiState.Failed(result.error.displayMessage())
                    }
                }
            }
        }
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

internal fun AO3Error.displayMessage(): String {
    return when (this) {
        AO3Error.BadRequest -> "AO3 rejected the request."
        AO3Error.AuthenticationRequired -> "Log in to AO3 again."
        AO3Error.Forbidden -> "AO3 denied access to this account page."
        AO3Error.NotFound -> "AO3 could not find this account page."
        is AO3Error.Http -> "AO3 returned HTTP $statusCode."
        is AO3Error.Network -> message
        is AO3Error.Overloaded -> "AO3 is busy. Try again shortly."
        is AO3Error.Parse -> message
        is AO3Error.RateLimited -> "AO3 is rate-limiting requests. Try again shortly."
        is AO3Error.Server -> "AO3 had a server problem (HTTP $statusCode)."
        is AO3Error.Validation -> message
    }
}
