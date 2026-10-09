package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.account.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

internal data class ChallengeSignUpsUiState(
    val rows: List<AO3ListedSignUp> = emptyList(), val loadedPages: Int = 0, val totalPages: Int = 1,
    val total: Int? = null, val closeDateText: String = "", val assignments: List<AO3SignUpAssignment>? = null,
    val matchError: String? = null, val loading: Boolean = false, val failure: String? = null,
    val terminal: Boolean = false
) {
    val hasMore get() = loadedPages > 0 && loadedPages < totalPages
    val matchNote get() = if (assignments == null) {
        "Kudos can't tell which sign-ups are matched. AO3 shows assignments to maintainers after sign-ups close." +
            matchError?.let { " $it" }.orEmpty()
    } else if (assignments.isEmpty()) "No assignments have been sent yet, so no sign-up is matched or unmatched." else null
    fun filtered(filter: SignUpFilter) = rows.filter { row -> when (filter) {
        SignUpFilter.All -> true
        SignUpFilter.Matched -> signUpMatch(row, assignments) == SignUpMatch.Matched
        SignUpFilter.Unmatched -> signUpMatch(row, assignments) == SignUpMatch.Unmatched
    } }
}

/** One visible, generation-scoped pager. Optional failures are attempts, not reasons to probe again. */
internal class AO3ChallengeSignUpsState(private val slug: String, private val viewerIsOwner: Boolean,
    private val viewerIsMaintainer: Boolean, private val repository: AO3CollectionDetailRepository) {
    private val auth = repository.authRepository
    private val generation = auth.generation.value
    private var active = true
    private var attempted = false
    private var job: Job? = null
    private val mutable = MutableStateFlow(ChallengeSignUpsUiState())
    val state = mutable.asStateFlow()
    fun close() { active = false; job?.cancel() }
    private fun checkSession() {
        if (!active || generation != auth.generation.value) throw CancellationException()
    }

    suspend fun load(refresh: Boolean = false, more: Boolean = false) {
        if (!active || generation != auth.generation.value || state.value.loading || state.value.terminal ||
            more && !state.value.hasMore || !more && attempted && !refresh) return
        attempted = true
        if (!auth.state.value.isSignedIn || !viewerIsMaintainer) {
            mutable.value = state.value.copy(failure = if (!auth.state.value.isSignedIn)
                "Log in to AO3 before using this feature." else "AO3 refused the request (HTTP 403). Wait a while before trying again.",
                terminal = true)
            return
        }
        job = currentCoroutineContext()[Job]
        mutable.value = state.value.copy(loading = true, failure = null)
        try {
            if (!more) {
                // The settings form is owner-only. Unknown/open means do not probe assignments.
                var closed = false
                if (viewerIsOwner) {
                    val result = repository.getChallengeSettingsForm(slug)
                    checkSession()
                    if (result is AO3Result.Success) {
                        val form = result.value
                        closed = form.kind == AO3ChallengeKind.GiftExchange && !form.signupOpen
                        val date = form.dates.getOrNull(1).orEmpty()
                        val text = if (!form.signupOpen) "closed" else if (date.isEmpty()) "open" else "open until ${challengeDateText(date)}"
                        mutable.value = state.value.copy(closeDateText = text)
                    }
                }
                var assignments: List<AO3SignUpAssignment>? = null
                var matchError: String? = null
                if (closed) {
                    val joined = mutableListOf<AO3SignUpAssignment>()
                    for (list in SignUpAssignmentList.entries) {
                        val result = repository.getSignUpAssignments(slug, list)
                        checkSession()
                        if (result is AO3Result.Failure) { matchError = result.error.moderationMessage(); break }
                        joined += (result as AO3Result.Success).value
                    }
                    if (matchError == null) assignments = joined
                }
                mutable.value = state.value.copy(assignments = assignments, matchError = matchError)
            }
            val pageNumber = if (more) state.value.loadedPages + 1 else 1
            val result = repository.getChallengeSignUps(slug, pageNumber)
            checkSession()
            currentCoroutineContext().ensureActive()
            when (result) {
                is AO3Result.Failure -> mutable.value = state.value.copy(failure = result.error.moderationMessage(),
                    terminal = result.error == AO3Error.Forbidden || result.error == AO3Error.AuthenticationRequired)
                is AO3Result.Success -> {
                    val page = result.value
                    var total = state.value.total
                    if (!more) {
                        total = if (page.totalPages == 1) page.rows.size else {
                            val last = repository.getChallengeSignUps(slug, page.totalPages)
                            checkSession()
                            if (last is AO3Result.Success) page.rows.size * (page.totalPages - 1) + last.value.rows.size else null
                        }
                    }
                    mutable.value = state.value.copy(rows = (if (more) state.value.rows + page.rows else page.rows).distinctBy { it.id },
                        loadedPages = page.currentPage, totalPages = page.totalPages, total = total)
                }
            }
        } catch (e: CancellationException) {
            throw e
        } finally {
            if (active) mutable.value = state.value.copy(loading = false)
            job = null
        }
    }
}
