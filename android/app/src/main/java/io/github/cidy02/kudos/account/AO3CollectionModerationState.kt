package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.account.*
import io.github.cidy02.kudos.network.ao3.displayMessage
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

internal enum class ModerationAction(val verb: String, val confirms: Boolean) {
    Approve("approve", false), Reject("reject", true), Accept("accept", false), Decline("decline", true),
    Reveal("reveal", true), Unanon("un-anon", true)
}

/** iOS UserFacingError/AO3Error copy for this port; AO3's validation/refusal text stays authoritative. */
internal fun AO3Error.moderationMessage(): String = when (this) {
    AO3Error.Forbidden -> "AO3 refused the request (HTTP 403). Wait a while before trying again."
    AO3Error.NotFound -> "That work or page couldn't be found (it may be restricted)."
    AO3Error.AuthenticationRequired -> "Your AO3 session expired. Please log in again."
    AO3Error.BadRequest -> "AO3 returned an unexpected response (HTTP 400)."
    is AO3Error.RateLimited -> "AO3 is rate-limiting requests. Wait a moment and try again."
    is AO3Error.Server -> "AO3 had a server problem (HTTP $statusCode). Try again shortly."
    is AO3Error.Http -> "AO3 returned an unexpected response (HTTP $statusCode)."
    is AO3Error.Parse -> "AO3's page format wasn't what the app expected."
    is AO3Error.Network -> when {
        offline -> "You're offline. Connect to the internet and try again."
        cause is java.net.SocketTimeoutException -> "AO3 took too long to answer. Try again."
        cause is javax.net.ssl.SSLException -> "Couldn't make a secure connection to AO3."
        else -> "Couldn't reach AO3. Check your connection and try again."
    }
    is AO3Error.Validation, is AO3Error.Overloaded -> displayMessage()
}

internal data class ModerationDecision(val action: ModerationAction, val id: Int = 0, val name: String = "") {
    val title get() = when (action) {
        ModerationAction.Reject -> "Reject this work?"
        ModerationAction.Decline -> "Decline $name?"
        ModerationAction.Reveal -> "Reveal this collection?"
        ModerationAction.Unanon -> "Remove anonymity?"
        else -> ""
    }
    val message get() = when (action) {
        ModerationAction.Reject -> "This rejects “$name” from the collection. The work stays on AO3, and its creator receives no reason or email."
        ModerationAction.Decline -> "This removes $name's membership request. They will need to apply again."
        ModerationAction.Reveal -> "Unrevealed works and their creators become visible to everyone. You can't undo this in Kudos."
        ModerationAction.Unanon -> "Creators become visible to everyone instead of only maintainers. You can't undo this in Kudos."
        else -> ""
    }
    val button get() = when (action) {
        ModerationAction.Reject -> "Reject"
        ModerationAction.Decline -> "Decline"
        ModerationAction.Reveal -> "Reveal"
        ModerationAction.Unanon -> "Remove Anonymity"
        else -> ""
    }
    val isReveal get() = action == ModerationAction.Reveal || action == ModerationAction.Unanon
}

internal data class ModerationUiState(
    val data: AO3CollectionModeration? = null,
    val loading: Boolean = false,
    val paging: Boolean = false,
    val failure: String? = null,
    val actionError: String? = null,
    val revealError: String? = null,
    val inFlight: ModerationDecision? = null,
    val pending: ModerationDecision? = null
) {
    val busy get() = loading || paging || inFlight != null
}

/** One visible hub, bound to its opening session; never changes library/Room records. */
internal class AO3CollectionModerationState(
    private val slug: String,
    val viewerIsOwner: Boolean,
    private val repository: AO3CollectionDetailRepository,
    private val writes: AO3WriteRepository
) {
    private val auth = repository.authRepository
    private val generation = auth.generation.value
    private var loadGeneration = 0
    private val mutable = MutableStateFlow(ModerationUiState())
    val state = mutable.asStateFlow()
    private fun ownsSession() = generation == auth.generation.value && auth.state.value.isSignedIn
    val showsReveal get() = viewerIsOwner && state.value.data?.unrevealed == true
    val showsUnanon get() = viewerIsOwner && state.value.data?.anonymous == true

    suspend fun load() {
        if (state.value.inFlight != null) return
        if (!ownsSession()) {
            if (generation == auth.generation.value) mutable.value = ModerationUiState(failure = "Log in to AO3 before using this feature.")
            return
        }
        val request = ++loadGeneration
        mutable.value = ModerationUiState(loading = true)
        try {
            val result = repository.getModeration(slug)
            currentCoroutineContext().ensureActive()
            if (!ownsSession() || request != loadGeneration) return
            mutable.value = when (result) {
                is AO3Result.Success -> ModerationUiState(data = result.value)
                is AO3Result.Failure -> ModerationUiState(failure = result.error.moderationMessage())
            }
        } catch (error: CancellationException) { throw error }
    }

    suspend fun loadPage(page: Int) {
        if (!ownsSession() || state.value.busy || state.value.pending != null) return
        val request = ++loadGeneration
        mutable.value = state.value.copy(paging = true)
        val result = repository.getCollectionItems(slug, AO3CollectionItemTab.Unreviewed, page)
        currentCoroutineContext().ensureActive()
        if (!ownsSession() || request != loadGeneration) return
        mutable.value = when (result) {
            is AO3Result.Success -> state.value.copy(paging = false, data = state.value.data?.copy(queue = result.value))
            is AO3Result.Failure -> state.value.copy(paging = false, actionError = "Couldn't load that page: ${result.error.moderationMessage()}")
        }
    }

    suspend fun choose(decision: ModerationDecision) {
        if (!canDecide(decision)) return
        if (decision.action.confirms) mutable.value = state.value.copy(pending = decision)
        else perform(decision)
    }

    fun cancel() { mutable.value = state.value.copy(pending = null) }
    fun dismissError() { mutable.value = state.value.copy(actionError = null) }
    suspend fun confirm() {
        val decision = state.value.pending ?: return
        mutable.value = state.value.copy(pending = null)
        if (canDecide(decision)) perform(decision)
    }

    private fun canDecide(decision: ModerationDecision): Boolean {
        if (!ownsSession() || state.value.busy || state.value.pending != null) return false
        return when (decision.action) {
            ModerationAction.Reveal -> showsReveal
            ModerationAction.Unanon -> showsUnanon
            ModerationAction.Approve, ModerationAction.Reject -> state.value.data?.queue?.items?.any { it.id == decision.id } == true
            ModerationAction.Accept, ModerationAction.Decline -> state.value.data?.requests?.any { it.id == decision.id } == true
        }
    }

    private suspend fun perform(decision: ModerationDecision) {
        ++loadGeneration
        mutable.value = state.value.copy(inFlight = decision,
            actionError = if (decision.isReveal) state.value.actionError else null,
            revealError = if (decision.isReveal) null else state.value.revealError)
        try {
            val result = when (decision.action) {
                ModerationAction.Approve, ModerationAction.Reject -> writes.updateCollectionItems(slug,
                    listOf(AO3CollectionItemDraft(decision.id, moderatorApproval =
                        if (decision.action == ModerationAction.Approve) AO3CollectionItemApproval.Approved else AO3CollectionItemApproval.Rejected)), generation)
                ModerationAction.Accept, ModerationAction.Decline -> writes.decideCollectionMember(slug, decision.id,
                    decision.action == ModerationAction.Accept, generation)
                ModerationAction.Reveal, ModerationAction.Unanon -> writes.revealCollection(slug,
                    decision.action == ModerationAction.Unanon, generation)
            }
            currentCoroutineContext().ensureActive()
            if (!ownsSession()) return
            val previous = state.value
            mutable.value = previous.copy(inFlight = null)
            when (result) {
                is AO3Result.Failure -> {
                    val error = result.error.moderationMessage()
                    mutable.value = if (decision.isReveal) state.value.copy(revealError = error)
                        else state.value.copy(actionError = "Failed to ${decision.action.verb}: $error")
                }
                is AO3Result.Success -> {
                    val data = previous.data ?: return
                    when (decision.action) {
                        ModerationAction.Approve, ModerationAction.Reject -> {
                            val queue = data.queue.copy(items = data.queue.items.filterNot { it.id == decision.id })
                            mutable.value = state.value.copy(data = data.copy(queue = queue))
                            if (queue.items.isEmpty() && queue.totalPages > 1) loadPage(
                                if (queue.currentPage < queue.totalPages) queue.currentPage else maxOf(1, queue.currentPage - 1))
                        }
                        ModerationAction.Accept, ModerationAction.Decline -> mutable.value = state.value.copy(
                            data = data.copy(requests = data.requests.filterNot { it.id == decision.id }))
                        ModerationAction.Reveal, ModerationAction.Unanon -> load()
                    }
                }
            }
        } catch (_: CancellationException) {
            // Old session/screen continuations never install a response or an error.
        }
    }
}
