package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionFields
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionForm
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionNameAvailability
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionSaveOutcome
import io.github.cidy02.kudos.network.ao3.account.collectionNameFormatIsValid
import io.github.cidy02.kudos.network.ao3.account.reservedCollectionNames
import io.github.cidy02.kudos.network.ao3.displayMessage
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

internal data class AO3CollectionFormUiState(
    val form: AO3CollectionForm? = null,
    val loading: Boolean = false,
    val saving: Boolean = false,
    val loadError: String? = null,
    val notice: String? = null,
    val availability: AO3CollectionNameAvailability? = null,
    val deleted: Boolean = false
) {
    val canSave: Boolean get() = form != null && !saving &&
        form[AO3CollectionFields.TITLE].trim().isNotEmpty() && form[AO3CollectionFields.NAME].trim().isNotEmpty() &&
        availability != AO3CollectionNameAvailability.Taken && availability != AO3CollectionNameAvailability.Invalid
}

/** One visible form. Same-account cookie rotation preserves edits; continuations belong to their captured generation. */
internal class AO3CollectionFormState(
    private val slug: String?,
    private val repository: AO3CollectionDetailRepository,
    private val writes: AO3WriteRepository,
    private val scope: CoroutineScope
) {
    private val auth = repository.authRepository
    private val mutable = MutableStateFlow(AO3CollectionFormUiState())
    val state = mutable.asStateFlow()
    private var formGeneration: Int? = null
    private var formUsername: String? = null
    private var active = true
    private var nameJob: Job? = null
    private var nameRevision = 0
    private fun owns(generation: Int) = active && generation == auth.generation.value

    suspend fun load() {
        if (!active || state.value.loading || state.value.saving) return
        val generation = auth.generation.value
        val username = auth.username()
        if (!auth.state.value.isSignedIn) {
            mutable.value = state.value.copy(loadError = "Log in to AO3 first.")
            return
        }
        mutable.value = state.value.copy(loading = true, loadError = null)
        try {
            val result = repository.getCollectionForm(slug)
            currentCoroutineContext().ensureActive()
            if (!owns(generation)) return
            mutable.value = when (result) {
                is AO3Result.Success -> {
                    formGeneration = generation
                    formUsername = username
                    AO3CollectionFormUiState(form = result.value)
                }
                is AO3Result.Failure -> state.value.copy(loading = false, loadError = result.error.displayMessage())
            }
        } catch (_: CancellationException) {
            if (owns(generation)) mutable.value = state.value.copy(loading = false)
        }
    }

    fun change(key: String, value: String) {
        val old = state.value
        val form = old.form ?: return
        if (!active || old.saving || (key == AO3CollectionFields.NAME && slug != null)) return
        mutable.value = old.copy(form = form.changed(key, value))
        if (key == AO3CollectionFields.NAME) scheduleNameCheck(value)
    }

    private fun scheduleNameCheck(value: String) {
        nameJob?.cancel()
        val revision = ++nameRevision
        mutable.value = state.value.copy(availability = null)
        val name = value.trim()
        if (slug != null || name.isEmpty()) return
        if (!collectionNameFormatIsValid(name)) {
            mutable.value = state.value.copy(availability = AO3CollectionNameAvailability.Invalid)
            return
        }
        if (name.lowercase() in reservedCollectionNames) {
            mutable.value = state.value.copy(availability = AO3CollectionNameAvailability.Taken)
            return
        }
        nameJob = scope.launch {
            delay(600)
            val result = try { repository.collectionNameAvailable(name) }
                catch (error: CancellationException) { throw error }
                catch (_: Exception) { AO3CollectionNameAvailability.Unknown }
            currentCoroutineContext().ensureActive()
            if (active && revision == nameRevision) mutable.value = state.value.copy(availability = result)
        }
    }

    /** Only the reader's Save action calls this; a second confirmation cannot dispatch while busy. */
    suspend fun confirmSave() {
        val before = state.value
        if (!active || before.deleted || !before.canSave) return
        val form = before.form ?: return
        val generation = saveGeneration() ?: return
        mutable.value = before.copy(saving = true, notice = null, form = form.copy(generalErrors = emptyList()))
        try {
            val result = writes.saveCollection(form.copy(generalErrors = emptyList()), generation)
            currentCoroutineContext().ensureActive()
            if (!owns(generation)) return
            mutable.value = when (result) {
                is AO3Result.Failure -> failed(result.error.displayMessage())
                is AO3Result.Success -> when (val outcome = result.value) {
                    is AO3CollectionSaveOutcome.Saved -> state.value.copy(form = outcome.form, notice = outcome.message, saving = false)
                    is AO3CollectionSaveOutcome.Invalid -> state.value.copy(saving = false,
                        // Keep the exact typed buffer while taking AO3's errors and fresh form evidence.
                        form = outcome.form.copy(values = form.values),
                        // AO3's own word on the name outranks the earlier check: "Name is
                        // available" must not stay beside "Name has already been taken".
                        availability = state.value.availability.takeIf {
                            AO3CollectionFields.NAME !in outcome.form.fieldErrors
                        })
                }
            }
        } catch (_: CancellationException) {
            if (owns(generation)) mutable.value = failed("Not saved: your AO3 session changed since this form opened.")
        }
    }

    suspend fun confirmDelete(typed: String) {
        val form = state.value.form ?: return
        if (!active || slug == null || !form.allowsDelete || state.value.saving || state.value.deleted || !form.confirmsDeletion(typed)) return
        val generation = saveGeneration() ?: return
        mutable.value = state.value.copy(saving = true, notice = null)
        try {
            val result = writes.deleteCollection(slug, generation)
            currentCoroutineContext().ensureActive()
            if (!owns(generation)) return
            mutable.value = when (result) {
                is AO3Result.Success -> state.value.copy(saving = false, deleted = true)
                is AO3Result.Failure -> failed(result.error.displayMessage())
            }
        } catch (_: CancellationException) {
            if (owns(generation)) mutable.value = failed("Not deleted: your AO3 session changed since this form opened.")
        }
    }

    private fun saveGeneration(): Int? {
        val loaded = formGeneration ?: return null
        val current = auth.generation.value
        if (!auth.state.value.isSignedIn || (loaded != current &&
                !formUsername.equals(auth.username(), ignoreCase = true))) {
            mutable.value = failed("Not saved: your AO3 session changed since this form opened. Your edits are still " +
                "here, and Save works again once ${formUsername ?: "that account"} is signed in. To edit as another account, reopen the form.")
            return null
        }
        formGeneration = current
        return current
    }

    private fun failed(message: String) = state.value.copy(saving = false,
        form = state.value.form?.copy(generalErrors = listOf(message)))

    /** Cancel/back/disposal is local and retires pending probes and UI continuations. */
    fun close() { active = false; ++nameRevision; nameJob?.cancel() }
}
