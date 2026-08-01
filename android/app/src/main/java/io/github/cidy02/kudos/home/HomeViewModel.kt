package io.github.cidy02.kudos.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import io.github.cidy02.kudos.account.AccountListRepository
import io.github.cidy02.kudos.account.AccountListType
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.AO3AuthState
import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.library.LibraryRepository
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataRepository
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.works.WorkUpdateChecker
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class HomeUiState(
    val dashboard: HomeDashboardState = HomeDashboardState(),
    val subscriptions: List<AO3WorkSummary> = emptyList(),
    val subscriptionsLoading: Boolean = false,
    val isSignedIn: Boolean = false
) {
    val loading: Boolean get() = dashboard.loading
    val totalSaved: Int get() = dashboard.totalSaved
    val hiddenByPrivacyCount: Int get() = dashboard.hiddenByPrivacyCount
    val continueReading get() = dashboard.continueReading
    val recentlyUpdated get() = dashboard.recentlyUpdated
    val favorites get() = dashboard.favorites
    val recentlyOpened get() = dashboard.recentlyOpened
    val hasSavedWorks: Boolean get() = dashboard.hasSavedWorks
}

class HomeViewModel(
    private val libraryRepository: LibraryRepository,
    private val workRepository: WorkRepository,
    private val metadataRepository: AO3WorkMetadataRepository,
    private val authRepository: AO3AuthRepository,
    private val accountListRepository: AccountListRepository,
    private val updateChecker: WorkUpdateChecker = WorkUpdateChecker(
        workRepository = workRepository,
        metadataRepository = metadataRepository
    )
) : ViewModel() {

    private val subscriptions = MutableStateFlow<List<AO3WorkSummary>>(emptyList())
    private val subscriptionsLoading = MutableStateFlow(false)

    private val dashboard: StateFlow<HomeDashboardState> = libraryRepository.observeSnapshot()
        .map(HomeDashboard::buildState)
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = HomeDashboardState()
        )

    val state: StateFlow<HomeUiState> = combine(
        dashboard,
        subscriptions,
        subscriptionsLoading,
        authRepository.state
    ) { dash, subs, loading, auth ->
        HomeUiState(
            dashboard = dash,
            subscriptions = subs,
            subscriptionsLoading = loading,
            isSignedIn = auth.isSignedIn
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = HomeUiState()
    )

    init {
        viewModelScope.launch {
            runUpdateCheck()
        }
        viewModelScope.launch {
            authRepository.state.collect { auth ->
                loadSubscriptions(auth)
            }
        }
    }

    fun refresh() {
        viewModelScope.launch {
            runUpdateCheck()
            loadSubscriptions(authRepository.state.value)
        }
    }

    fun onOpenLocalWork(workId: String) {
        viewModelScope.launch {
            workRepository.markUpdateSeen(workId)
        }
    }

    private suspend fun runUpdateCheck() {
        // Snapshot current library works; upserts will refresh the dashboard flow.
        val works = workRepository.listSavedWorks()
        updateChecker.checkForUpdates(among = works)
    }

    private suspend fun loadSubscriptions(auth: AO3AuthState) {
        if (!auth.isSignedIn) {
            subscriptions.value = emptyList()
            subscriptionsLoading.value = false
            return
        }
        subscriptionsLoading.value = true
        when (val result = accountListRepository.load(AccountListType.Subscriptions, page = 1)) {
            is AO3Result.Success -> subscriptions.value = result.value.works
            is AO3Result.Failure -> {
                // Keep prior list on soft failure so a brief network blip doesn't blank the shelf.
            }
        }
        subscriptionsLoading.value = false
    }

    companion object {
        fun factory(
            libraryRepository: LibraryRepository,
            workRepository: WorkRepository,
            metadataRepository: AO3WorkMetadataRepository,
            authRepository: AO3AuthRepository,
            accountListRepository: AccountListRepository
        ): ViewModelProvider.Factory {
            return object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T {
                    return HomeViewModel(
                        libraryRepository = libraryRepository,
                        workRepository = workRepository,
                        metadataRepository = metadataRepository,
                        authRepository = authRepository,
                        accountListRepository = accountListRepository
                    ) as T
                }
            }
        }
    }
}
