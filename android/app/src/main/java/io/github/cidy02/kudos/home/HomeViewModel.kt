package io.github.cidy02.kudos.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import io.github.cidy02.kudos.account.AccountListRepository
import io.github.cidy02.kudos.account.AccountListType
import io.github.cidy02.kudos.app.PrivacyGate
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.AO3AuthState
import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.library.LibraryRepository
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataRepository
import io.github.cidy02.kudos.works.WorkMetadataRefresh
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.works.WorkUpdateChecker
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class HomeUiState(
    val dashboard: HomeDashboardState = HomeDashboardState(),
    val subscriptions: List<AO3WorkSummary> = emptyList(),
    val subscriptionsLoading: Boolean = false,
    val subscriptionsLoadFailed: Boolean = false,
    /** Non-null only when page 1 was the whole subscriptions list. */
    val subscriptionsExactCount: Int? = null,
    val isSignedIn: Boolean = false
) {
    val loading: Boolean get() = dashboard.loading
    val totalSaved: Int get() = dashboard.totalSaved
    val hiddenByPrivacyCount: Int get() = dashboard.hiddenByPrivacyCount
    val continueReading get() = dashboard.continueReading
    val recentlyUpdated get() = dashboard.recentlyUpdated
    val favorites get() = dashboard.favorites
    val recentlyOpened get() = dashboard.recentlyOpened
    val visibleItems get() = dashboard.visibleItems
    val hideMatureContent get() = dashboard.hideMatureContent
    val confirmBeforeDelete get() = dashboard.confirmBeforeDelete
    val homeCollections get() = dashboard.homeCollections
    val hasSavedWorks: Boolean get() = dashboard.hasSavedWorks
}

class HomeViewModel(
    private val libraryRepository: LibraryRepository,
    private val workRepository: WorkRepository,
    private val metadataRepository: AO3WorkMetadataRepository,
    private val authRepository: AO3AuthRepository,
    private val accountListRepository: AccountListRepository,
    private val privacyGate: PrivacyGate = PrivacyGate(),
    private val updateChecker: WorkUpdateChecker = WorkUpdateChecker(
        workRepository = workRepository,
        metadataRepository = metadataRepository
    )
) : ViewModel() {

    private val subscriptions = MutableStateFlow<List<AO3WorkSummary>>(emptyList())
    private val subscriptionsLoading = MutableStateFlow(false)
    private val subscriptionsLoadFailed = MutableStateFlow(false)
    private val subscriptionsExactCount = MutableStateFlow<Int?>(null)
    private val metadataRefresh = WorkMetadataRefresh(workRepository, metadataRepository)

    // An empty snapshot is the pre-seed database, not a finished load. Using it as
    // the first frame composes an empty Home and then the real one. A populated
    // snapshot (normal launch) is shown immediately; otherwise the spinner stays
    // until the shared flow emits.
    private val preloadedDashboard: HomeDashboardState? =
        libraryRepository.latestSnapshot()
            ?.takeIf { it.items.isNotEmpty() }
            ?.let { HomeDashboard.buildState(it) }

    private val dashboard: StateFlow<HomeDashboardState> = combine(
        libraryRepository.observeSnapshot(),
        privacyGate.state
    ) { snapshot, revealed -> HomeDashboard.buildState(snapshot, revealed) }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = preloadedDashboard ?: HomeDashboardState()
        )

    private val subscriptionShelf = combine(
        subscriptions,
        subscriptionsLoading,
        subscriptionsLoadFailed,
        subscriptionsExactCount
    ) { works, loading, failed, exact ->
        SubscriptionShelf(works, loading, failed, exact)
    }

    val state: StateFlow<HomeUiState> = combine(
        dashboard,
        subscriptionShelf,
        authRepository.state
    ) { dash, shelf, auth ->
        HomeUiState(
            dashboard = dash,
            subscriptions = shelf.works,
            subscriptionsLoading = shelf.loading,
            subscriptionsLoadFailed = shelf.failed,
            subscriptionsExactCount = shelf.exactCount,
            isSignedIn = auth.isSignedIn
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = HomeUiState(dashboard = preloadedDashboard ?: HomeDashboardState())
    )

    init {
        viewModelScope.launch(Dispatchers.IO) {
            runUpdateCheck()
        }
        viewModelScope.launch {
            authRepository.state.collect { auth ->
                loadSubscriptions(auth)
            }
        }
    }

    private val _isRefreshing = MutableStateFlow(false)
    val isRefreshing: StateFlow<Boolean> = _isRefreshing.asStateFlow()

    fun refresh() {
        viewModelScope.launch { refreshNow() }
    }

    /**
     * Suspending variant used by the shared [KudosRefreshBox] pull gesture, which
     * owns the spinner and cancels this on navigate-away.
     */
    suspend fun refreshNow() {
        _isRefreshing.value = true
        try {
            refreshVisibleMetadata()
            runUpdateCheck()
            loadSubscriptions(authRepository.state.value)
        } finally {
            _isRefreshing.value = false
        }
    }

    /** Up to 12 Reading Now and 12 Recently Updated works. A failed fetch leaves the work as it was. */
    private suspend fun refreshVisibleMetadata() {
        val works = dashboard.value.visibleItems.map { it.item.work }
        val candidates = (
            HomeSectionKind.ReadingNow.works(works) { true }.take(12) +
                HomeSectionKind.RecentlyUpdated.works(works) { true }.take(12)
            ).distinctBy { it.id }
        for (work in candidates) {
            try {
                metadataRefresh.refresh(work)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                // One work's failure must not blank the rest of the pull.
            }
        }
    }

    fun onOpenLocalWork(workId: String) {
        viewModelScope.launch {
            workRepository.markUpdateSeen(workId)
        }
    }

    /** Session reveal for an obscured mature card (Apple `PrivacyGate.reveal`). */
    fun revealWork(workId: String, activity: androidx.fragment.app.FragmentActivity? = null) {
        privacyGate.reveal(workId, activity)
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
            subscriptionsLoadFailed.value = false
            subscriptionsExactCount.value = null
            return
        }
        subscriptionsLoading.value = true
        // Whose list this is. An answer for a session that has ended (signed out, or another
        // account by now) stayed on Home until the next load finished (audit A19-5).
        val generation = authRepository.generation.value
        try {
            val result = accountListRepository.load(AccountListType.Subscriptions, page = 1)
            if (authRepository.generation.value != generation) {
                // Not this session's answer. Still signed in (Verify Session moved the session
                // on, and the same name publishes no new state): nothing else would ask again,
                // and Home said there were no subscriptions (audit A22-4; iOS A20-6).
                val now = authRepository.state.value
                if (now.isSignedIn) loadSubscriptions(now)
                return
            }
            when (result) {
                is AO3Result.Success -> {
                    subscriptions.value = result.value.works
                    subscriptionsLoadFailed.value = false
                    subscriptionsExactCount.value =
                        if (result.value.totalPages <= 1) result.value.works.size else null
                }
                is AO3Result.Failure -> {
                    // Keep a previous page. Only an empty shelf says the load failed.
                    if (subscriptions.value.isEmpty()) subscriptionsLoadFailed.value = true
                }
            }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            if (subscriptions.value.isEmpty()) subscriptionsLoadFailed.value = true
        } finally {
            subscriptionsLoading.value = false
        }
    }

    companion object {
        fun factory(
            libraryRepository: LibraryRepository,
            workRepository: WorkRepository,
            metadataRepository: AO3WorkMetadataRepository,
            authRepository: AO3AuthRepository,
            accountListRepository: AccountListRepository,
            privacyGate: PrivacyGate = PrivacyGate()
        ): ViewModelProvider.Factory {
            return object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T {
                    return HomeViewModel(
                        libraryRepository = libraryRepository,
                        workRepository = workRepository,
                        metadataRepository = metadataRepository,
                        authRepository = authRepository,
                        accountListRepository = accountListRepository,
                        privacyGate = privacyGate
                    ) as T
                }
            }
        }
    }
}

private data class SubscriptionShelf(
    val works: List<AO3WorkSummary>,
    val loading: Boolean,
    val failed: Boolean,
    val exactCount: Int?
)
