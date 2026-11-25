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
            val authenticationScope: String?,
            val generation: Int? = null
        ) : Payload

        data class CountsChanged(val authenticationScope: String) : Payload

        data class DashboardLoaded(
            val header: AO3AuthorHeader,
            val route: AO3AuthorRoute,
            val generation: Int? = null
        ) : Payload

        data class DraftSaved(
            val username: String?,
            val generation: Int? = null
        ) : Payload
    }

    private val listeners = CopyOnWriteArrayList<(Payload) -> Unit>()

    fun register(listener: (Payload) -> Unit): () -> Unit {
        listeners += listener
        return { listeners -= listener }
    }

    fun notifyAuthChanged(
        isSignedIn: Boolean,
        username: String?,
        authenticationScope: String?,
        generation: Int? = null
    ) {
        dispatch(Payload.AuthChanged(isSignedIn, username, authenticationScope, generation))
    }

    fun notifyCountsChanged(authenticationScope: String) {
        dispatch(Payload.CountsChanged(authenticationScope))
    }

    fun notifyDashboardLoaded(
        header: AO3AuthorHeader,
        route: AO3AuthorRoute,
        generation: Int? = null
    ) {
        dispatch(Payload.DashboardLoaded(header, route, generation))
    }

    fun notifyDraftSaved(username: String? = null, generation: Int? = null) {
        dispatch(Payload.DraftSaved(username, generation))
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
    subscribeEvents: Boolean = true
) {
    private data class EvaluationTarget(
        val epoch: Long,
        val username: String?,
        val generation: Int?,
        val activeScope: String?,
        val queryScope: String?
    )

    private data class HeaderWritingCounts(
        val workCount: Int?,
        val seriesCount: Int?,
        val draftCount: Int?
    )

    private val lock = Any()
    private val mutableShowsWritingTab = MutableStateFlow(false)
    val showsWritingTabFlow: StateFlow<Boolean> = mutableShowsWritingTab.asStateFlow()
    val showsWritingTab: Boolean get() = mutableShowsWritingTab.value

    private val mutableReturnToWritingRequest = MutableStateFlow(0)
    val returnToWritingRequestFlow: StateFlow<Int> = mutableReturnToWritingRequest.asStateFlow()

    private var currentRoute: String = Routes.Home
    private var isPresentingAccount = false
    private var pendingWritingRouteValue: WritingRoute? = null
    val pendingWritingRoute: WritingRoute?
        get() = synchronized(lock) { pendingWritingRouteValue }

    private var activeUsername: String? = null
    private var activeGeneration: Int? = null
    private var activeAuthenticationScope: String? = null
    private var authEpoch: Long = 0L
    private var evaluatedAccount: String? = null
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
            this.isPresentingAccount = isPresentingAccount
            if (currentRoute != null) {
                this.currentRoute = currentRoute
                if (currentRoute != Routes.Home && currentRoute != Routes.Writing) {
                    restoredWritingSelection = false
                    pendingWritingRouteValue = null
                    mutableReturnToWritingRequest.value = 0
                }
            }
        }
    }

    fun onAuthStateChanged(authState: AO3AuthState, generation: Int) {
        val target = synchronized(lock) {
            val key = authState to generation
            if (lastObservedAuth == key) return
            lastObservedAuth = key
            when (authState) {
                is AO3AuthState.SignedIn -> beginAuthLocked(
                    isSignedIn = true,
                    username = authState.username,
                    authenticationScope = AO3AccountListCountsCache.scope(authState.username, generation),
                    generation = generation
                )
                is AO3AuthState.SignedOut,
                is AO3AuthState.Expired,
                is AO3AuthState.Error -> beginAuthLocked(
                    isSignedIn = false,
                    username = null,
                    authenticationScope = null,
                    generation = null
                )
                AO3AuthState.Restoring,
                AO3AuthState.SigningIn -> null
            }
        }
        if (target != null) {
            finishSignedInAuthEvaluation(target)
        }
    }

    fun noteRestoredWritingSelection() {
        synchronized(lock) {
            if (!showsWritingTab) {
                restoredWritingSelection = true
                currentRoute = Routes.Home
            }
        }
    }

    fun openPendingWritingRoute(route: WritingRoute) {
        synchronized(lock) {
            pendingWritingRouteValue = route
            currentRoute = Routes.Home
            if (showsWritingTab) {
                mutableReturnToWritingRequest.value += 1
            }
        }
    }

    fun consumePendingWritingRoute(): WritingRoute? {
        synchronized(lock) {
            val route = pendingWritingRouteValue
            pendingWritingRouteValue = null
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
        val (effectiveUsername, capturedEpoch) = synchronized(lock) {
            (username ?: activeUsername) to authEpoch
        }
        val resolvedHasLocalDrafts = if (isSignedIn) {
            hasLocalDrafts ?: (recoveryStore?.hasLocalDrafts(effectiveUsername) == true)
        } else {
            false
        }
        synchronized(lock) {
            if (hasLocalDrafts == null && isSignedIn && authEpoch != capturedEpoch) {
                return showsWritingTab
            }
            return evaluateWritingTabLocked(
                isSignedIn = isSignedIn,
                username = effectiveUsername,
                workCount = workCount,
                seriesCount = seriesCount,
                draftCount = draftCount,
                hasLocalDrafts = resolvedHasLocalDrafts
            )
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
        val counts = headerWritingCounts(header, route)
        return evaluateWritingTab(
            isSignedIn = isSignedIn,
            username = effectiveUsername,
            workCount = counts.workCount,
            seriesCount = counts.seriesCount,
            draftCount = counts.draftCount,
            hasLocalDrafts = null
        )
    }

    fun noteDraftSaved(username: String? = null, generation: Int? = null) {
        synchronized(lock) {
            val currentActive = activeUsername ?: return
            if (username != null &&
                normalizeWritingTabAccount(username) != normalizeWritingTabAccount(currentActive)
            ) {
                return
            }
            if (generation != null && activeGeneration != null && generation != activeGeneration) {
                return
            }
            evaluateWritingTabLocked(
                isSignedIn = true,
                username = currentActive,
                workCount = null,
                seriesCount = null,
                draftCount = 1,
                hasLocalDrafts = true
            )
        }
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

    private fun beginAuthLocked(
        isSignedIn: Boolean,
        username: String?,
        authenticationScope: String?,
        generation: Int?
    ): EvaluationTarget? {
        authEpoch += 1
        if (!isSignedIn) {
            activeUsername = null
            activeGeneration = null
            activeAuthenticationScope = null
            evaluateWritingTabLocked(
                isSignedIn = false,
                username = null,
                workCount = null,
                seriesCount = null,
                draftCount = null,
                hasLocalDrafts = false
            )
            return null
        }
        activeUsername = username
        activeGeneration = generation
        activeAuthenticationScope = authenticationScope
        return EvaluationTarget(
            epoch = authEpoch,
            username = username,
            generation = generation,
            activeScope = authenticationScope,
            queryScope = authenticationScope
        )
    }

    private fun isCurrentLocked(target: EvaluationTarget): Boolean =
        authEpoch == target.epoch &&
            activeGeneration == target.generation &&
            activeAuthenticationScope == target.activeScope &&
            normalizeWritingTabAccount(activeUsername) == normalizeWritingTabAccount(target.username)

    private fun finishSignedInAuthEvaluation(target: EvaluationTarget) {
        val scope = target.queryScope
        val username = target.username
        val cachedWorkCount = scope?.let { countsCache?.get(AccountListType.MyWorks, it)?.knownCount }
        val cachedSeriesCount = scope?.let { countsCache?.get(AO3AccountListCountsCache.SERIES, it)?.knownCount }
        val cachedDraftCount = scope?.let { countsCache?.get(AO3AccountListCountsCache.DRAFTS, it)?.knownCount }
        val cachedHeader = username?.let(cachedHeaderForUser)
        val headerRoute = username?.let { AO3AuthorRoute(it) }
        val headerCounts = if (cachedHeader != null && headerRoute != null) {
            headerWritingCounts(cachedHeader, headerRoute)
        } else {
            null
        }
        val workCount = cachedWorkCount ?: headerCounts?.workCount
        val seriesCount = cachedSeriesCount ?: headerCounts?.seriesCount
        val draftCount = cachedDraftCount ?: headerCounts?.draftCount
        val hasLocalDrafts = recoveryStore?.hasLocalDrafts(username) == true
        synchronized(lock) {
            if (!isCurrentLocked(target)) return
            evaluateWritingTabLocked(
                isSignedIn = true,
                username = username,
                workCount = workCount,
                seriesCount = seriesCount,
                draftCount = draftCount,
                hasLocalDrafts = hasLocalDrafts
            )
        }
    }

    private fun headerWritingCounts(header: AO3AuthorHeader, route: AO3AuthorRoute): HeaderWritingCounts {
        // A header with no count but a recent work or series is still proof of writing;
        // an empty list without a count proves nothing (unknown, never zero).
        val rawWorkCount = AuthorOverview.listCount(header, route, AuthorSeeAll.Works)
            ?: header.recentWorks?.takeIf { it.isNotEmpty() }?.size
        val rawSeriesCount = AuthorOverview.listCount(header, route, AuthorSeeAll.Series)
            ?: header.recentSeries?.takeIf { it.isNotEmpty() }?.size
        // A pseud's zero counts never disprove writing across the whole account.
        val workCount = if (route.pseud == null) rawWorkCount else rawWorkCount?.takeIf { it > 0 }
        val seriesCount = if (route.pseud == null) rawSeriesCount else rawSeriesCount?.takeIf { it > 0 }
        val rawDraftCount = header.draftsListCount()
        val draftCount = if (route.pseud == null) rawDraftCount else rawDraftCount?.takeIf { it > 0 }
        return HeaderWritingCounts(workCount = workCount, seriesCount = seriesCount, draftCount = draftCount)
    }

    private fun evaluateWritingTabLocked(
        isSignedIn: Boolean,
        username: String?,
        workCount: Int?,
        seriesCount: Int?,
        draftCount: Int?,
        hasLocalDrafts: Boolean
    ): Boolean {
        val normalizedUser = normalizeWritingTabAccount(username)
        val accountSwitched = isSignedIn &&
            evaluatedAccount != null &&
            normalizedUser != evaluatedAccount
        evaluatedAccount = if (isSignedIn) normalizedUser else null
        if (accountSwitched) {
            restoredWritingSelection = false
            pendingWritingRouteValue = null
            mutableReturnToWritingRequest.value = 0
        }
        if (isSignedIn) {
            if (hasLocalDrafts || (workCount ?: 0) > 0 || (seriesCount ?: 0) > 0 || (draftCount ?: 0) > 0) {
                writingStateStore.setLastKnownWrites(true, username)
            } else if (workCount == 0 && seriesCount == 0 && draftCount == 0) {
                writingStateStore.setLastKnownWrites(false, username)
            }
        }
        val rule = WritingTabRule(
            isSignedIn = isSignedIn,
            workCount = workCount,
            seriesCount = seriesCount,
            draftCount = draftCount,
            hasLocalDrafts = hasLocalDrafts,
            lastKnownWrites = writingStateStore.lastKnownWrites(username),
            alreadyShownThisRun = if (accountSwitched) false else showsWritingTab
        )
        return applyWritingTabRuleLocked(rule)
    }

    private fun applyWritingTabRuleLocked(rule: WritingTabRule): Boolean {
        val next = rule.showsWritingTab
        if (next) {
            mutableShowsWritingTab.value = true
            if ((restoredWritingSelection || pendingWritingRouteValue != null) &&
                currentRoute == Routes.Home &&
                !isPresentingAccount
            ) {
                mutableReturnToWritingRequest.value += 1
            } else {
                pendingWritingRouteValue = null
            }
            restoredWritingSelection = false
        } else {
            mutableShowsWritingTab.value = false
            if (!rule.isSignedIn) {
                restoredWritingSelection = false
                pendingWritingRouteValue = null
                mutableReturnToWritingRequest.value = 0
            }
        }
        return next
    }

    private fun handlePayload(payload: WritingTabEvents.Payload) {
        when (payload) {
            is WritingTabEvents.Payload.AuthChanged -> {
                val target = synchronized(lock) {
                    lastObservedAuth = null
                    beginAuthLocked(
                        isSignedIn = payload.isSignedIn,
                        username = payload.username,
                        authenticationScope = payload.authenticationScope,
                        generation = payload.generation
                    )
                }
                if (target != null) {
                    finishSignedInAuthEvaluation(target)
                }
            }
            is WritingTabEvents.Payload.CountsChanged -> {
                val target = synchronized(lock) {
                    val user = activeUsername ?: return
                    val queryScope = activeAuthenticationScope ?: payload.authenticationScope
                    if (!queryScope.equals(payload.authenticationScope, ignoreCase = true)) return
                    EvaluationTarget(
                        epoch = authEpoch,
                        username = user,
                        generation = activeGeneration,
                        activeScope = activeAuthenticationScope,
                        queryScope = queryScope
                    )
                }
                val scope = target.queryScope ?: return
                val workCount = countsCache?.get(AccountListType.MyWorks, scope)?.knownCount
                val seriesCount = countsCache?.get(AO3AccountListCountsCache.SERIES, scope)?.knownCount
                val draftCount = countsCache?.get(AO3AccountListCountsCache.DRAFTS, scope)?.knownCount
                val hasLocalDrafts = recoveryStore?.hasLocalDrafts(target.username) == true
                synchronized(lock) {
                    if (!isCurrentLocked(target)) return
                    evaluateWritingTabLocked(
                        isSignedIn = true,
                        username = target.username,
                        workCount = workCount,
                        seriesCount = seriesCount,
                        draftCount = draftCount,
                        hasLocalDrafts = hasLocalDrafts
                    )
                }
            }
            is WritingTabEvents.Payload.DashboardLoaded -> {
                val target = synchronized(lock) {
                    val user = activeUsername ?: return
                    if (!payload.route.username.equals(user, ignoreCase = true)) return
                    if (payload.generation != null && activeGeneration != null &&
                        payload.generation != activeGeneration
                    ) {
                        return
                    }
                    EvaluationTarget(
                        epoch = authEpoch,
                        username = user,
                        generation = activeGeneration,
                        activeScope = activeAuthenticationScope,
                        queryScope = activeAuthenticationScope
                    )
                }
                val counts = headerWritingCounts(payload.header, payload.route)
                val hasLocalDrafts = recoveryStore?.hasLocalDrafts(target.username) == true
                synchronized(lock) {
                    if (!isCurrentLocked(target)) return
                    evaluateWritingTabLocked(
                        isSignedIn = true,
                        username = target.username,
                        workCount = counts.workCount,
                        seriesCount = counts.seriesCount,
                        draftCount = counts.draftCount,
                        hasLocalDrafts = hasLocalDrafts
                    )
                }
            }
            is WritingTabEvents.Payload.DraftSaved -> {
                noteDraftSaved(payload.username, payload.generation)
            }
        }
    }
}
