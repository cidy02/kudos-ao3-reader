package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionParticipant
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionParticipantRole
import io.github.cidy02.kudos.network.ao3.displayMessage
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

internal data class AO3CollectionMaintainersUiState(
    val participants: List<AO3CollectionParticipant> = emptyList(),
    val loading: Boolean = false,
    val loaded: Boolean = false,
    val loadError: String? = null,
    val username: String = "",
    val role: AO3CollectionParticipantRole = AO3CollectionParticipantRole.Moderator,
    val inviting: Boolean = false,
    val leaving: Boolean = false,
    val inviteError: String? = null,
    val notice: String? = null,
    val leaveError: String? = null,
    val dialog: Dialog? = null,
    val left: Boolean = false
) {
    enum class Dialog { LastOwner, Owner, Moderator }
    val owners get() = participants.filter { it.role == AO3CollectionParticipantRole.Owner.title }
    val moderators get() = participants.filter { it.role == AO3CollectionParticipantRole.Moderator.title }
    val busy get() = loading || inviting || leaving || left
}

/** One visible screen and captured session. No lookup, background job, or optimistic participant edit. */
internal class AO3CollectionMaintainersState(
    private val slug: String,
    private val repository: AO3CollectionDetailRepository,
    private val writes: AO3WriteRepository
) {
    private val auth = repository.authRepository
    private val generation = auth.generation.value
    private val reader = auth.username()?.trim().orEmpty()
    private var active = true
    private val mutable = MutableStateFlow(AO3CollectionMaintainersUiState())
    val state = mutable.asStateFlow()
    val currentParticipant get() = state.value.participants.firstOrNull { reader.isNotEmpty() && it.pseud.equals(reader, true) }
    val isOwner get() = currentParticipant?.role == AO3CollectionParticipantRole.Owner.title
    fun isReader(pseud: String) = reader.isNotEmpty() && pseud.equals(reader, true)
    private fun ownsSession() = active && generation == auth.generation.value && auth.state.value.isSignedIn
    fun close() { active = false }

    fun changeUsername(value: String) {
        if (ownsSession()) mutable.value = state.value.copy(username = value)
    }
    fun chooseRole(role: AO3CollectionParticipantRole) {
        if (ownsSession() && role in listOf(AO3CollectionParticipantRole.Moderator, AO3CollectionParticipantRole.Owner))
            mutable.value = state.value.copy(role = role)
    }

    suspend fun load() {
        if (!ownsSession() || state.value.busy) return
        mutable.value = state.value.copy(loading = true, loadError = null, dialog = null)
        try {
            val result = repository.getCollectionParticipants(slug)
            currentCoroutineContext().ensureActive()
            if (!ownsSession()) return
            mutable.value = when (result) {
                is AO3Result.Success -> state.value.copy(participants = result.value, loading = false, loaded = true)
                is AO3Result.Failure -> state.value.copy(loading = false, loadError = result.error.displayMessage())
            }
        } catch (error: CancellationException) { throw error }
    }

    suspend fun invite() {
        val username = state.value.username.trim()
        if (!ownsSession() || state.value.busy || !state.value.loaded || username.isEmpty()) return
        mutable.value = state.value.copy(inviting = true, inviteError = null, notice = null)
        try {
            val result = writes.inviteMaintainer(slug, username, generation)
            currentCoroutineContext().ensureActive()
            if (!ownsSession()) return
            when (result) {
                is AO3Result.Success -> {
                    mutable.value = state.value.copy(inviting = false, username = "", notice = "Invitation sent to $username.")
                    load()
                }
                is AO3Result.Failure -> mutable.value = state.value.copy(inviting = false, inviteError = result.error.displayMessage())
            }
        } catch (_: CancellationException) { /* Departed screens/sessions never receive a write result. */ }
    }

    fun leaveTap() {
        if (!ownsSession() || state.value.busy || !state.value.loaded) return
        mutable.value = state.value.copy(dialog = when {
            isOwner && state.value.owners.size <= 1 -> AO3CollectionMaintainersUiState.Dialog.LastOwner
            isOwner -> AO3CollectionMaintainersUiState.Dialog.Owner
            else -> AO3CollectionMaintainersUiState.Dialog.Moderator
        })
    }
    fun cancelDialog() { mutable.value = state.value.copy(dialog = null) }

    suspend fun confirmLeave() {
        if (!ownsSession() || state.value.busy || state.value.dialog !in listOf(
                AO3CollectionMaintainersUiState.Dialog.Owner, AO3CollectionMaintainersUiState.Dialog.Moderator)) return
        if (isOwner && state.value.owners.size <= 1) {
            mutable.value = state.value.copy(dialog = AO3CollectionMaintainersUiState.Dialog.LastOwner)
            return
        }
        val participant = currentParticipant
        if (participant == null) {
            mutable.value = state.value.copy(dialog = null, leaveError = "Could not identify your maintainer record.")
            return
        }
        mutable.value = state.value.copy(dialog = null, leaving = true, leaveError = null)
        try {
            val result = writes.leaveCollection(slug, participant.id, generation)
            currentCoroutineContext().ensureActive()
            if (!ownsSession()) return
            mutable.value = when (result) {
                is AO3Result.Success -> state.value.copy(left = true)
                is AO3Result.Failure -> state.value.copy(leaving = false, leaveError = result.error.displayMessage())
            }
        } catch (_: CancellationException) { /* The POST may finish; its stale response cannot change this screen. */ }
    }
}
