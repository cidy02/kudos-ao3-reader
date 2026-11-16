package io.github.cidy02.kudos.app

import android.content.SharedPreferences
import io.github.cidy02.kudos.account.AO3AccountListCountsCache
import io.github.cidy02.kudos.account.AccountListType
import io.github.cidy02.kudos.auth.AO3AuthState
import io.github.cidy02.kudos.author.AuthorOverview
import io.github.cidy02.kudos.author.AuthorSeeAll
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorHeader
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorRoute
import io.github.cidy02.kudos.network.ao3.writing.recovery.WritingTextRecovery
import java.util.Locale
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

internal fun normalizeWritingTabAccount(username: String?): String? {
    val trimmed = username?.trim()?.lowercase(Locale.ROOT) ?: return null
    return trimmed.ifEmpty { null }
}

/**
 * Pure rule for whether the Writing tab appears in the navigation bar (A-513 / iOS T-513).
 *
 * The Writing tab is shown only when a signed-in AO3 account has at least one work,
 * series, or draft, or Kudos holds a local draft scoped to this account. Partial counts
 * or weak lower bounds are unknown, never zero. Offline or before the account answers,
 * the stored last-known answer is used (never guessing `true` for an unseen account).
 * Once shown during an app run, the tab is never removed while the app remains open;
 * signing out removes it, and switching accounts re-decides without an intermediate sign-out.
 */
data class WritingTabRule(
    val isSignedIn: Boolean,
    val workCount: Int? = null,
    val seriesCount: Int? = null,
    val draftCount: Int? = null,
    val hasLocalDrafts: Boolean = false,
    val lastKnownWrites: Boolean = false,
    val alreadyShownThisRun: Boolean = false
) {
    val showsWritingTab: Boolean
        get() {
            if (!isSignedIn) return false
            if (alreadyShownThisRun) return true
            if (hasLocalDrafts) return true
            if ((workCount ?: 0) > 0 || (seriesCount ?: 0) > 0 || (draftCount ?: 0) > 0) return true
            if (workCount == 0 && seriesCount == 0 && draftCount == 0) return false
            return lastKnownWrites
        }
}

interface WritingTabStateStore {
    fun lastKnownWrites(username: String?): Boolean
    fun setLastKnownWrites(writes: Boolean, username: String?)
}

class MemoryWritingTabStateStore : WritingTabStateStore {
    private val lock = Any()
    private val values = mutableMapOf<String, Boolean>()

    override fun lastKnownWrites(username: String?): Boolean {
        val normalized = normalizeWritingTabAccount(username) ?: return false
        synchronized(lock) {
            return values[normalized] ?: false
        }
    }

    override fun setLastKnownWrites(writes: Boolean, username: String?) {
        val normalized = normalizeWritingTabAccount(username) ?: return
        synchronized(lock) {
            values[normalized] = writes
        }
    }
}

class SharedPreferencesWritingTabStateStore(
    private val preferences: SharedPreferences
) : WritingTabStateStore {
    override fun lastKnownWrites(username: String?): Boolean {
        val normalized = normalizeWritingTabAccount(username) ?: return false
        return preferences.getBoolean(keyFor(normalized), false)
    }

    override fun setLastKnownWrites(writes: Boolean, username: String?) {
        val normalized = normalizeWritingTabAccount(username) ?: return
        preferences.edit().putBoolean(keyFor(normalized), writes).apply()
    }

    private fun keyFor(normalizedUsername: String): String = "$KEY_PREFIX$normalizedUsername"

    companion object {
        private const val KEY_PREFIX = "writes:"
    }
}

object WritingTabEvents {
    sealed interface Payload {
        data class AuthChanged(
            val isSignedIn: Boolean,
            val username: String?,
            val authenticationScope: String?
        ) : Payload

        data class CountsChanged(val authenticationScope: String) : Payload

        data class DashboardLoaded(
            val header: AO3AuthorHeader,
            val route: AO3AuthorRoute
        ) : Payload

        data class DraftSaved(val username: String?) : Payload
    }

    private val listeners = CopyOnWriteArrayList<(Payload) -> Unit>()

    fun register(listener: (Payload) -> Unit): () -> Unit {
        listeners += listener
        return { listeners -= listener }
    }

    fun notifyAuthChanged(isSignedIn: Boolean, username: String?, authenticationScope: String?) {
        dispatch(Payload.AuthChanged(isSignedIn, username, authenticationScope))
    }

    fun notifyCountsChanged(authenticationScope: String) {
        dispatch(Payload.CountsChanged(authenticationScope))
    }

    fun notifyDashboardLoaded(header: AO3AuthorHeader, route: AO3AuthorRoute) {
        dispatch(Payload.DashboardLoaded(header, route))
    }

    fun notifyDraftSaved(username: String? = null) {
        dispatch(Payload.DraftSaved(username))
    }

    private fun dispatch(payload: Payload) {
        for (listener in listeners) {
            listener(payload)
        }
    }
}

/**
 * Coordinates the Writing tab visibility rule, per-account persistence, restored/deep-linked
 * Writing route fallback, and account-switching re-evaluation (port of iOS T-513 in `AppRouter`).
 */
class WritingTabController(
    private val writingStateStore: WritingTabStateStore = MemoryWritingTabStateStore(),
    private val recoveryStore: WritingTextRecovery? = null,
    private val countsCache: AO3AccountListCountsCache? = null,
    private val cachedHeaderForUser: (String) -> AO3AuthorHeader? = { null },
    initialSelection: String = Routes.Home,
    subscribeEvents: Boolean = true
) {
    private val lock = Any()
    private val mutableShowsWritingTab = MutableStateFlow(false)
    val showsWritingTabFlow: StateFlow<Boolean> = mutableShowsWritingTab.asStateFlow()
    val showsWritingTab: Boolean get() = mutableShowsWritingTab.value

    private val mutableSelection = MutableStateFlow(initialSelection)
    val selectionFlow: StateFlow<String> = mutableSelection.asStateFlow()
    var selection: String
        get() = mutableSelection.value
        set(value) {
            synchronized(lock) {
                mutableSelection.value = value
                if (value != Routes.Home && value != Routes.Writing) {
                    restoredWritingSelection = false
                }
            }
        }

    private val mutableIsPresentingAccount = MutableStateFlow(false)
    val isPresentingAccountFlow: StateFlow<Boolean> = mutableIsPresentingAccount.asStateFlow()
    var isPresentingAccount: Boolean
        get() = mutableIsPresentingAccount.value
        set(value) {
            synchronized(lock) {
                mutableIsPresentingAccount.value = value
            }
        }

    private val mutablePendingWritingRoute = MutableStateFlow<WritingRoute?>(null)
    val pendingWritingRouteFlow: StateFlow<WritingRoute?> = mutablePendingWritingRoute.asStateFlow()
    var pendingWritingRoute: WritingRoute?
        get() = mutablePendingWritingRoute.value
        set(value) {
            synchronized(lock) {
                mutablePendingWritingRoute.value = value
            }
        }

    private val mutablePendingAccountRoute = MutableStateFlow<AccountSheetRoute?>(null)
    var pendingAccountRoute: AccountSheetRoute?
        get() = mutablePendingAccountRoute.value
        set(value) {
            synchronized(lock) {
                mutablePendingAccountRoute.value = value
            }
        }

    private val mutablePendingLibraryAO3Route = MutableStateFlow<LibraryAO3Route?>(null)
    var pendingLibraryAO3Route: LibraryAO3Route?
        get() = mutablePendingLibraryAO3Route.value
        set(value) {
            synchronized(lock) {
                mutablePendingLibraryAO3Route.value = value
            }
        }

    private val mutableReturnToWritingRequest = MutableStateFlow(0)
    val returnToWritingRequestFlow: StateFlow<Int> = mutableReturnToWritingRequest.asStateFlow()

    private var activeUsername: String? = null
    private var evaluatedAccount: String? = null
    private var activeAuthenticationScope: String? = null
    private var restoredWritingSelection = false
    private var lastObservedAuth: Pair<AO3AuthState, Int>? = null
    private var unregisterEvents: (() -> Unit)? = null
    private var unregisterCacheListener: (() -> Unit)? = null

    init {
        if (subscribeEvents) {
            unregisterEvents = WritingTabEvents.register(::handlePayload)
        }
        if (countsCache != null) {
            val cacheListener: (String) -> Unit = { scope ->
                handlePayload(WritingTabEvents.Payload.CountsChanged(scope))
            }
            countsCache.addWritingCountListener(cacheListener)
            unregisterCacheListener = { countsCache.removeWritingCountListener(cacheListener) }
        }
    }

    fun close() {
        unregisterEvents?.invoke()
        unregisterEvents = null
        unregisterCacheListener?.invoke()
        unregisterCacheListener = null
    }

    fun topLevelDestinations(): List<TopLevelDestination> =
        Routes.topLevelDestinations(showsWriting = showsWritingTab)

    fun onShellStateChanged(currentRoute: String?, isPresentingAccount: Boolean) {
        synchronized(lock) {
            mutableIsPresentingAccount.value = isPresentingAccount
            if (Routes.isShellRoot(currentRoute, showsWriting = showsWritingTab)) {
                mutableSelection.value = currentRoute ?: Routes.Home
                if (currentRoute != Routes.Home && currentRoute != Routes.Writing) {
                    restoredWritingSelection = false
                }
            }
        }
    }

    fun onAuthStateChanged(authState: AO3AuthState, generation: Int) {
        synchronized(lock) {
            val key = authState to generation
            if (lastObservedAuth == key) return
            lastObservedAuth = key
        }
        when (authState) {
            is AO3AuthState.SignedIn -> handlePayload(
                WritingTabEvents.Payload.AuthChanged(
                    isSignedIn = true,
                    username = authState.username,
                    authenticationScope = AO3AccountListCountsCache.scope(authState.username, generation)
                )
            )
            is AO3AuthState.SignedOut,
            is AO3AuthState.Expired,
            is AO3AuthState.Error -> handlePayload(
                WritingTabEvents.Payload.AuthChanged(
                    isSignedIn = false,
                    username = null,
                    authenticationScope = null
                )
            )
            AO3AuthState.Restoring,
            AO3AuthState.SigningIn -> Unit
        }
    }

    fun restoreSelection(rawRoute: String?) {
        synchronized(lock) {
            val wantsWriting = rawRoute == Routes.Writing
            val restored = Routes.restoredSelection(rawRoute, showsWriting = showsWritingTab)
            mutableSelection.value = restored.tabRoute
            mutableIsPresentingAccount.value = restored.presentsAccount
            restoredWritingSelection = wantsWriting && !showsWritingTab
        }
    }

    fun noteRestoredWritingSelection() {
        synchronized(lock) {
            if (!showsWritingTab) {
                restoredWritingSelection = true
                mutableSelection.value = Routes.Home
            }
        }
    }

    fun openPendingWritingRoute(route: WritingRoute) {
        synchronized(lock) {
            mutablePendingWritingRoute.value = route
            if (showsWritingTab) {
                mutableSelection.value = Routes.Writing
                mutableReturnToWritingRequest.value += 1
            } else {
                mutableSelection.value = Routes.Home
            }
        }
    }

    fun openLegacyAccountRoute(route: LegacyAccountRoute) {
        synchronized(lock) {
            when (val dest = route.destination) {
                is LegacyAccountDestination.Account -> {
                    mutablePendingAccountRoute.value = dest.route
                    mutableIsPresentingAccount.value = true
                }
                is LegacyAccountDestination.Writing -> {
                    mutablePendingWritingRoute.value = dest.route
                    mutableSelection.value = if (showsWritingTab) Routes.Writing else Routes.Home
                }
                is LegacyAccountDestination.Library -> {
                    mutablePendingLibraryAO3Route.value = dest.route
                    mutableSelection.value = Routes.Library
                }
            }
        }
    }

    fun consumePendingWritingRoute(): WritingRoute? {
        synchronized(lock) {
            val route = mutablePendingWritingRoute.value
            mutablePendingWritingRoute.value = null
            return route
        }
    }

    fun consumeReturnToWritingRequest() {
        synchronized(lock) {
            mutableReturnToWritingRequest.value = 0
        }
    }

    fun evaluateWritingTab(
        isSignedIn: Boolean,
        username: String? = null,
        workCount: Int? = null,
        seriesCount: Int? = null,
        draftCount: Int? = null,
        hasLocalDrafts: Boolean? = null
    ): Boolean {
        synchronized(lock) {
            val effectiveUsername = username ?: activeUsername
            val normalizedUser = normalizeWritingTabAccount(effectiveUsername)
            val accountSwitched = isSignedIn &&
                evaluatedAccount != null &&
                normalizedUser != evaluatedAccount
            evaluatedAccount = if (isSignedIn) normalizedUser else null
            if (accountSwitched) {
                restoredWritingSelection = false
                mutablePendingWritingRoute.value = null
                mutableReturnToWritingRequest.value = 0
            }
            val resolvedHasLocalDrafts = if (isSignedIn) {
                hasLocalDrafts ?: (recoveryStore?.hasLocalDrafts(effectiveUsername) == true)
            } else {
                false
            }
            if (isSignedIn) {
                if (resolvedHasLocalDrafts || (workCount ?: 0) > 0 || (seriesCount ?: 0) > 0 || (draftCount ?: 0) > 0) {
                    writingStateStore.setLastKnownWrites(true, effectiveUsername)
                } else if (workCount == 0 && seriesCount == 0 && draftCount == 0) {
                    writingStateStore.setLastKnownWrites(false, effectiveUsername)
                }
            }
            val rule = WritingTabRule(
                isSignedIn = isSignedIn,
                workCount = workCount,
                seriesCount = seriesCount,
                draftCount = draftCount,
                hasLocalDrafts = resolvedHasLocalDrafts,
                lastKnownWrites = writingStateStore.lastKnownWrites(effectiveUsername),
                alreadyShownThisRun = if (accountSwitched) false else showsWritingTab
            )
            return applyWritingTabRuleLocked(rule)
        }
    }

    fun evaluateWritingTab(rule: WritingTabRule): Boolean {
        synchronized(lock) {
            return applyWritingTabRuleLocked(rule)
        }
    }

    fun evaluateWritingTab(
        header: AO3AuthorHeader,
        route: AO3AuthorRoute,
        username: String? = null,
        isSignedIn: Boolean
    ): Boolean {
        val effectiveUsername = username ?: route.username
        if (isSignedIn && !route.username.equals(effectiveUsername, ignoreCase = true)) {
            return showsWritingTab
        }
        // A header with no count but a recent work or series is still proof of writing;
        // an empty list without a count proves nothing (unknown, never zero).
        val rawWorkCount = AuthorOverview.listCount(header, route, AuthorSeeAll.Works)
            ?: header.recentWorks?.takeIf { it.isNotEmpty() }?.size
        val rawSeriesCount = AuthorOverview.listCount(header, route, AuthorSeeAll.Series)
            ?: header.recentSeries?.takeIf { it.isNotEmpty() }?.size
        // A pseud's zero counts never disprove writing across the whole account.
        val workCount = if (route.pseud == null) rawWorkCount else rawWorkCount?.takeIf { it > 0 }
        val seriesCount = if (route.pseud == null) rawSeriesCount else rawSeriesCount?.takeIf { it > 0 }
        val draftCount = header.draftsListCount()
        return evaluateWritingTab(
            isSignedIn = isSignedIn,
            username = effectiveUsername,
            workCount = workCount,
            seriesCount = seriesCount,
            draftCount = draftCount,
            hasLocalDrafts = recoveryStore?.hasLocalDrafts(effectiveUsername)
        )
    }

    fun noteDraftSaved(username: String? = null) {
        val effectiveUsername = synchronized(lock) { username ?: activeUsername }
        writingStateStore.setLastKnownWrites(true, effectiveUsername)
        evaluateWritingTab(
            isSignedIn = true,
            username = effectiveUsername,
            draftCount = 1,
            hasLocalDrafts = true
        )
    }

    /**
     * Shows the Writing tab for the current session without writing to persistent
     * account preferences (used by DEBUG screenshot/navigation routes).
     */
    fun revealWritingTabForSession() {
        synchronized(lock) {
            mutableShowsWritingTab.value = true
        }
    }

    private fun applyWritingTabRuleLocked(rule: WritingTabRule): Boolean {
        val next = rule.showsWritingTab
        if (next) {
            mutableShowsWritingTab.value = true
            if ((restoredWritingSelection || mutablePendingWritingRoute.value != null) &&
                mutableSelection.value == Routes.Home &&
                !mutableIsPresentingAccount.value
            ) {
                mutableSelection.value = Routes.Writing
                mutableReturnToWritingRequest.value += 1
            }
            restoredWritingSelection = false
        } else {
            // Move selection off Writing before hiding the tab so no frame holds a hidden tab.
            if (mutableSelection.value == Routes.Writing) {
                mutableSelection.value = Routes.Home
            }
            mutableShowsWritingTab.value = false
            if (!rule.isSignedIn) {
                restoredWritingSelection = false
            }
        }
        return next
    }

    private fun handlePayload(payload: WritingTabEvents.Payload) {
        when (payload) {
            is WritingTabEvents.Payload.AuthChanged -> {
                synchronized(lock) {
                    activeUsername = if (payload.isSignedIn) payload.username else null
                    activeAuthenticationScope = if (payload.isSignedIn) payload.authenticationScope else null
                }
                if (!payload.isSignedIn) {
                    evaluateWritingTab(isSignedIn = false)
                    return
                }
                val scope = payload.authenticationScope
                val username = payload.username
                val cachedWorkCount = scope?.let { countsCache?.get(AccountListType.MyWorks, it)?.knownCount }
                val cachedSeriesCount = scope?.let { countsCache?.get(AO3AccountListCountsCache.SERIES, it)?.knownCount }
                val cachedDraftCount = scope?.let { countsCache?.get(AO3AccountListCountsCache.DRAFTS, it)?.knownCount }
                val cachedHeader = username?.let(cachedHeaderForUser)
                val headerRoute = username?.let { AO3AuthorRoute(it) }
                val workCount = cachedWorkCount
                    ?: cachedHeader?.let { header ->
                        headerRoute?.let { route ->
                            AuthorOverview.listCount(header, route, AuthorSeeAll.Works)
                                ?: header.recentWorks?.takeIf { it.isNotEmpty() }?.size
                        }
                    }
                val seriesCount = cachedSeriesCount
                    ?: cachedHeader?.let { header ->
                        headerRoute?.let { route ->
                            AuthorOverview.listCount(header, route, AuthorSeeAll.Series)
                                ?: header.recentSeries?.takeIf { it.isNotEmpty() }?.size
                        }
                    }
                val draftCount = cachedDraftCount ?: cachedHeader?.draftsListCount()
                evaluateWritingTab(
                    isSignedIn = true,
                    username = username,
                    workCount = workCount,
                    seriesCount = seriesCount,
                    draftCount = draftCount,
                    hasLocalDrafts = recoveryStore?.hasLocalDrafts(username)
                )
            }
            is WritingTabEvents.Payload.CountsChanged -> {
                val (username, scope) = synchronized(lock) {
                    val user = activeUsername ?: return
                    val activeScope = activeAuthenticationScope ?: payload.authenticationScope
                    if (activeScope != payload.authenticationScope) return
                    user to activeScope
                }
                val workCount = countsCache?.get(AccountListType.MyWorks, scope)?.knownCount
                val seriesCount = countsCache?.get(AO3AccountListCountsCache.SERIES, scope)?.knownCount
                val draftCount = countsCache?.get(AO3AccountListCountsCache.DRAFTS, scope)?.knownCount
                evaluateWritingTab(
                    isSignedIn = true,
                    username = username,
                    workCount = workCount,
                    seriesCount = seriesCount,
                    draftCount = draftCount,
                    hasLocalDrafts = recoveryStore?.hasLocalDrafts(username)
                )
            }
            is WritingTabEvents.Payload.DashboardLoaded -> {
                val username = synchronized(lock) { activeUsername } ?: return
                if (!payload.route.username.equals(username, ignoreCase = true)) return
                evaluateWritingTab(
                    header = payload.header,
                    route = payload.route,
                    username = username,
                    isSignedIn = true
                )
            }
            is WritingTabEvents.Payload.DraftSaved -> {
                val currentActive = synchronized(lock) { activeUsername }
                if (payload.username != null && currentActive != null &&
                    normalizeWritingTabAccount(payload.username) != normalizeWritingTabAccount(currentActive)
                ) {
                    return
                }
                val targetUser = payload.username ?: currentActive ?: return
                noteDraftSaved(targetUser)
            }
        }
    }
}
