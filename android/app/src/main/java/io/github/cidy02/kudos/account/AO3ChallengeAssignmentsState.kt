package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.auth.usernameOrNull
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.account.*
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneOffset

enum class AssignmentSegment(val label: String) { Matched("Matched"), Unmatched("Unmatched"), PinchHits("Pinch hits") }
enum class AssignmentWrite(val title: String, val confirmTitle: String, val confirmButton: String) {
    Default("Report a default", "Report this default?", "Report default"),
    Claim("Claim a pinch hit", "Claim this pinch hit?", "Claim")
}
data class PendingAssignmentWrite(val kind: AssignmentWrite, val assignment: AO3SignUpAssignment)
internal data class ChallengeAssignmentsUiState(
    val pages: Map<SignUpAssignmentList, AO3AssignmentPage> = emptyMap(),
    val errors: Map<SignUpAssignmentList, String> = emptyMap(), val blocked: Set<SignUpAssignmentList> = emptySet(),
    val dueRaw: String = "", val dueZone: String = "UTC", val loading: Boolean = false, val loaded: Boolean = false,
    val failure: String? = null, val terminal: Boolean = false, val busy: Boolean = false,
    val actionError: String? = null, val picking: AssignmentWrite? = null, val pending: PendingAssignmentWrite? = null
) {
    val dueText get() = dueRaw.takeIf { it.isNotBlank() }?.let { challengeDateText(it.trim().removeSuffix(" UTC").removeSuffix(" gmt")) }
    val dueInstant: Instant? get() = runCatching {
        val raw = dueRaw.trim()
        val digits = runCatching { OffsetDateTime.parse(raw).toInstant().atOffset(ZoneOffset.UTC).toLocalDateTime() }.getOrNull()
            ?: raw.removeSuffix(" UTC").removeSuffix(" gmt").removeSuffix("Z").replace(' ', 'T').let {
                if (it.length == 10) LocalDate.parse(it).atStartOfDay() else LocalDateTime.parse(it)
            }
        digits.atZone(ZoneId.of(dueZone)).toInstant()
    }.getOrNull() // Unrecognized Rails zone names must never invent a Late badge.
    fun rows(list: SignUpAssignmentList) = pages[list]?.rows.orEmpty()
    val matched get() = rows(SignUpAssignmentList.Complete) + rows(SignUpAssignmentList.Open)
    val unmatched get() = rows(SignUpAssignmentList.Defaults)
    val claimed get() = rows(SignUpAssignmentList.PinchHits)
    val reportable get() = matched.filter { !it.fulfilled && !it.defaulted }
    fun candidates(kind: AssignmentWrite) = if (kind == AssignmentWrite.Default) reportable else unmatched
    val matchedError get() = errors[SignUpAssignmentList.Complete] ?: errors[SignUpAssignmentList.Open]
    val subtitle get() = listOfNotNull(
        if (loaded && matchedError == null) "${matched.size} matched" else null,
        if (loaded && errors[SignUpAssignmentList.Defaults] == null) "${unmatched.size} unmatched" else null,
        dueText?.let { "works due $it" }).joinToString(" · ")
    fun confirmation(write: PendingAssignmentWrite): String = if (write.kind == AssignmentWrite.Default)
        "This marks ${write.assignment.giverDisplay}'s assignment for ${write.assignment.recipientDisplay} as defaulted on AO3 and adds it to the pinch hits waiting for cover."
    else "You'll be the pinch hitter for ${write.assignment.recipientDisplay}'s gift${dueText?.let { ", due $it" }.orEmpty()}."
}

/** One opening, first pages only. Session/role/closed-state admission precedes every list read. */
internal class AO3ChallengeAssignmentsState(private val slug: String, private val owner: Boolean,
    private val maintainer: Boolean, private val knownClosed: Boolean?, private val repository: AO3CollectionDetailRepository,
    private val writes: AO3WriteRepository) {
    private val auth = repository.authRepository
    private val generation = auth.generation.value
    private var active = true
    private var attempted = false
    private var dueAttempted = false
    private var dueSucceeded = false
    private var closed = knownClosed
    private var job: Job? = null
    private val mutable = MutableStateFlow(ChallengeAssignmentsUiState())
    val state = mutable.asStateFlow()
    fun close() { active = false; job?.cancel() }
    private fun checkSession() { if (!active || auth.generation.value != generation) throw CancellationException() }
    fun dismissError() { mutable.value = state.value.copy(actionError = null) }
    fun pick(kind: AssignmentWrite?) {
        if (active && owner && !state.value.terminal && generation == auth.generation.value && !state.value.busy && !state.value.loading)
            mutable.value = state.value.copy(picking = kind)
    }
    fun select(kind: AssignmentWrite, row: AO3SignUpAssignment) {
        if (active && owner && !state.value.terminal && generation == auth.generation.value && !state.value.busy && !state.value.loading && row in state.value.candidates(kind))
            mutable.value = state.value.copy(picking = null, pending = PendingAssignmentWrite(kind, row))
    }
    fun cancel() { if (!state.value.busy) mutable.value = state.value.copy(picking = null, pending = null) }
    /** The settings form, which only the owner is served. Returns why it could not be read, if it could not. */
    private suspend fun readDue(): AO3Error? {
        if (!owner || dueAttempted) return null
        dueAttempted = true // Failed best-effort reads stay attempted for this opening.
        dueSucceeded = false
        mutable.value = state.value.copy(dueRaw = "", dueZone = "")
        val answer = repository.getChallengeSettingsForm(slug)
        checkSession()
        if (answer is AO3Result.Success) {
            dueSucceeded = true
            closed = answer.value.kind == AO3ChallengeKind.GiftExchange && !answer.value.signupOpen
            mutable.value = state.value.copy(dueRaw = answer.value.dates.getOrNull(2).orEmpty(), dueZone = answer.value.timeZoneName)
        }
        return (answer as? AO3Result.Failure)?.error
    }
    suspend fun load(refresh: Boolean = false, more: SignUpAssignmentList? = null) {
        if (!active || generation != auth.generation.value || state.value.busy || state.value.loading || state.value.terminal ||
            more == null && attempted && !refresh || more != null && more in state.value.blocked) return
        if (more != null && state.value.pages[more]?.let { it.currentPage < it.totalPages } != true) return
        attempted = true
        if (refresh && more == null && dueSucceeded) dueAttempted = false
        if (!auth.state.value.isSignedIn || !maintainer) {
            mutable.value = state.value.copy(failure = if (!auth.state.value.isSignedIn) "Sign in to AO3 to view assignments."
                else "AO3 shows assignments to collection owners and moderators after sign-ups close.", terminal = true)
            return
        }
        job = currentCoroutineContext()[Job]
        mutable.value = state.value.copy(loading = true, failure = null)
        try {
            val unread = if (closed == null) readDue() else null
            if (closed == false) {
                mutable.value = state.value.copy(failure = "AO3 shows assignments to maintainers after sign-ups close.", terminal = true)
                return
            }
            if (closed == null && owner) {
                // The owner's settings could not be read. AO3's refusal is an answer and ends it; anything
                // else (no connection, AO3 busy) is asked again by Try Again, where the first version
                // said "can't confirm" for good.
                val refused = unread == AO3Error.Forbidden || unread == AO3Error.AuthenticationRequired
                if (!refused) { attempted = false; dueAttempted = false }
                mutable.value = state.value.copy(failure = unread?.moderationMessage()
                    ?: "Kudos can't confirm that sign-ups are closed.", terminal = refused)
                return
            }
            // Closed, or a moderator, whom AO3 does not serve the settings form: the lists are asked for as
            // on iOS, and AO3's first refusal stops the rest (they are served to the same people).
            val lists = more?.let { listOf(it) } ?: SignUpAssignmentList.entries
            for (list in lists) {
                if (list in state.value.blocked) continue
                // Swift groups Complete + Open: a failed Complete stops Open for this load.
                if (more == null && list == SignUpAssignmentList.Open && state.value.errors[SignUpAssignmentList.Complete] != null) continue
                val page = if (more == null) 1 else state.value.pages[list]!!.currentPage + 1
                val answer = repository.getChallengeAssignments(slug, list, page)
                checkSession()
                when (answer) {
                    is AO3Result.Success -> {
                        val result = answer.value.copy(rows = if (more == null) answer.value.rows
                            else (state.value.rows(list) + answer.value.rows).distinctBy { it.id })
                        mutable.value = state.value.copy(pages = state.value.pages + (list to result), errors = state.value.errors - list)
                    }
                    is AO3Result.Failure -> {
                        val refused = answer.error == AO3Error.Forbidden || answer.error == AO3Error.AuthenticationRequired
                        val stopped = if (refused && more == null) lists.dropWhile { it != list } else listOf(list)
                        mutable.value = state.value.copy(
                            errors = state.value.errors + stopped.associateWith { answer.error.moderationMessage() },
                            blocked = if (refused) state.value.blocked + stopped else state.value.blocked)
                    }
                }
            }
            if (more == null) readDue()
            checkSession()
            mutable.value = state.value.copy(loaded = true)
        } finally {
            if (active) mutable.value = state.value.copy(loading = false)
            job = null
        }
    }
    suspend fun perform() {
        val write = state.value.pending ?: return
        if (!active || !owner || !maintainer || !state.value.loaded || state.value.terminal || state.value.busy || state.value.loading || generation != auth.generation.value) return
        job = currentCoroutineContext()[Job]
        mutable.value = state.value.copy(busy = true, actionError = null)
        var confirmed = false
        try {
            val answer = if (write.kind == AssignmentWrite.Claim) writes.claimPinchHit(slug, write.assignment.id,
                auth.state.value.usernameOrNull.orEmpty(), generation)
            else writes.markAssignmentDefaulted(slug, write.assignment.id, generation)
            if (!active) return
            when (answer) {
                is AO3Result.Success -> { confirmed = true; mutable.value = state.value.copy(pending = null) }
                is AO3Result.Failure -> mutable.value = state.value.copy(actionError = answer.error.moderationMessage(), pending = null,
                    terminal = answer.error == AO3Error.Forbidden || answer.error == AO3Error.AuthenticationRequired)
            }
        } catch (e: CancellationException) {
            // No POST was dispatched. Never manufacture a failure prefix for an answer already received.
        } finally {
            if (active) mutable.value = state.value.copy(busy = false)
            job = null
        }
        if (confirmed && active && generation == auth.generation.value) load(refresh = true)
    }
}
