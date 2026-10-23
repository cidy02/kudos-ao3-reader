package io.github.cidy02.kudos.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.works.WorkImportResult
import io.github.cidy02.kudos.works.WorkImporter
import io.github.cidy02.kudos.network.ao3.AO3Error
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.library.QueueMembershipDialog

/**
 * Selection state shared by every **remote** work list — Search results,
 * Browse's fandom and tag pages, and an author's works tab (iOS
 * `RemoteWorkSelection`).
 *
 * The parity checklist counts this once per surface (Phase 4 item 10, Phase 6
 * item 7, Phase 11 item 5) and explicitly warns against implementing it three
 * times "with drifting behavior". One state holder, one action bar, three hosts.
 *
 * Library keeps its own selection: it selects local `SavedWork` ids and offers
 * favourite/finished/remove actions that make no sense for a work that isn't
 * saved yet. These are genuinely different surfaces, not duplication.
 */
@Stable
class RemoteWorkSelectionState internal constructor(
    isSelecting: Boolean = false,
    selected: Set<Long> = emptySet()
) {
    var isSelecting by mutableStateOf(isSelecting)
        private set

    var selected by mutableStateOf(selected)
        private set

    val count: Int get() = selected.size
    val hasSelection: Boolean get() = selected.isNotEmpty()

    fun isSelected(workId: Long): Boolean = workId in selected

    fun enter(initial: Long? = null) {
        isSelecting = true
        selected = initial?.let { setOf(it) } ?: emptySet()
    }

    fun exit() {
        isSelecting = false
        selected = emptySet()
    }

    fun toggle(workId: Long) {
        selected = if (workId in selected) selected - workId else selected + workId
    }

    /** Select All, or Deselect All once every id in [workIds] is chosen. Stays in selection. */
    fun toggleSelectAll(workIds: Collection<Long>) {
        val ids = workIds.toSet()
        val all = ids.isNotEmpty() && ids.all { it in selected }
        selected = if (all) selected - ids else selected + ids
    }

    /** The selected summaries, in the host's current display order. */
    fun selectedIn(results: List<AO3WorkSummary>): List<AO3WorkSummary> =
        results.filter { it.id in selected }

    internal companion object {
        val Saver: Saver<RemoteWorkSelectionState, Any> = Saver(
            save = { listOf(it.isSelecting, it.selected.toList()) },
            restore = {
                @Suppress("UNCHECKED_CAST")
                val parts = it as List<Any>
                RemoteWorkSelectionState(
                    isSelecting = parts[0] as Boolean,
                    selected = (parts[1] as List<Long>).toSet()
                )
            }
        )
    }
}

/** Survives configuration change and process death, like the list under it. */
@Composable
fun rememberRemoteWorkSelection(): RemoteWorkSelectionState =
    rememberSaveable(saver = RemoteWorkSelectionState.Saver) { RemoteWorkSelectionState() }

/**
 * Bottom contextual action bar shown while selecting, matching Library's
 * existing selection bar so the two read as one product (per the cross-platform
 * UI bridge: Material expression of shared intent, not a literal iOS toolbar).
 */
@Composable
fun RemoteWorkSelectionBar(
    state: RemoteWorkSelectionState,
    busy: Boolean,
    onSaveToLibrary: () -> Unit,
    onSaveForLater: () -> Unit,
    onAddToCollection: () -> Unit,
    onAddToQueue: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        tonalElevation = 3.dp,
        color = MaterialTheme.colorScheme.surfaceContainerHigh
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 8.dp)
                .semantics {
                    contentDescription = if (state.hasSelection) {
                        "${state.count} works selected"
                    } else {
                        "Selecting works, none selected yet"
                    }
                },
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = if (state.hasSelection) "${state.count} selected" else "Select works",
                style = MaterialTheme.typography.labelLarge
            )
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Box {
                    var menu by remember { mutableStateOf(false) }
                    TextButton(onClick = { menu = true }, enabled = state.hasSelection && !busy) { Text("Actions") }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        listOf("Download" to onSaveToLibrary, "Save for Later" to onSaveForLater,
                            "Add to Collection" to onAddToCollection, "Add to Queue" to onAddToQueue).forEach { (label, action) ->
                            DropdownMenuItem(text = { Text(label) }, onClick = { menu = false; action() })
                        }
                    }
                }
                TextButton(onClick = state::exit, enabled = !busy) { Text("Cancel") }
            }
        }
    }
}

/** Host-owned batch, error and membership sheets; they survive leaving selection. */
@Composable
fun RemoteWorkSelectionActions(
    state: RemoteWorkSelectionState,
    works: List<AO3WorkSummary>,
    importer: WorkImporter,
    queues: ReadingQueueRepository?
) {
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var queueWorks by remember { mutableStateOf<List<SavedWork>>(emptyList()) }
    var collectionWorks by remember { mutableStateOf<List<SavedWork>>(emptyList()) }
    fun run(action: suspend (List<AO3WorkSummary>) -> RemoteWorkBulkActions.Result) {
        if (busy) return
        val picked = state.selectedIn(works)
        busy = true
        scope.launch {
            try {
                val result = action(picked)
                if (result.allSucceeded) state.exit() else error = result.message
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: Exception) { error = failure.message ?: "The action couldn't be completed." }
            finally { busy = false }
        }
    }
    if (state.isSelecting) RemoteWorkSelectionBar(state, busy,
        onSaveToLibrary = { run { RemoteWorkBulkActions.saveToLibrary(it, importer) } },
        onSaveForLater = { queues?.let { repository -> run { RemoteWorkBulkActions.saveForLater(it, importer, repository) } } },
        onAddToCollection = { run { picked ->
            RemoteWorkBulkActions.resolve(picked, importer) { collectionWorks = it }
        } },
        onAddToQueue = { if (queues != null) run { picked ->
            RemoteWorkBulkActions.resolve(picked, importer) { queueWorks = it }
        } }
    )
    if (queueWorks.isNotEmpty()) QueueMembershipDialog(queueWorks, queues, importer,
        onDismiss = { queueWorks = emptyList() })
    if (collectionWorks.isNotEmpty()) AddSelectionToCollectionDialog(collectionWorks, importer.workRepository,
        onAdded = {}, onDismiss = { collectionWorks = emptyList() })
    error?.let { message ->
        AlertDialog(onDismissRequest = { error = null }, title = { Text("Action Failed") },
            text = { Text(message) }, confirmButton = { TextButton(onClick = { error = null }) { Text("OK") } })
    }
}

/**
 * Bulk actions for remote summaries (iOS `RemoteWorkBulkActions`).
 *
 * Explicit Download obtains one EPUB per missing work, sequentially. Listing
 * metadata is sufficient; do not read each work page before its download.
 */
object RemoteWorkBulkActions {

    data class Result(val added: Int, val failed: Int) {
        val allSucceeded: Boolean get() = added > 0 && failed == 0
        val message: String get() = when {
            added == 0 && failed == 0 -> "Nothing selected."
            failed == 0 -> "Added $added to your Library."
            added == 0 -> "Couldn't add $failed. Check your connection and try again."
            else -> "Added $added. $failed couldn't be added."
        }
    }

    suspend fun saveToLibrary(
        works: List<AO3WorkSummary>,
        importer: WorkImporter
    ): Result = apply(works) { summary ->
        when (val result = importer.prepareForReading(summary)) {
            is WorkImportResult.Failure -> result
            is WorkImportResult.Success -> {
                importer.workRepository.setSaved(result.work.id, true)
                WorkImportResult.Success(importer.workRepository.getWork(result.work.id) ?: result.work)
            }
        }
    }

    suspend fun saveForLater(
        works: List<AO3WorkSummary>,
        importer: WorkImporter,
        queues: ReadingQueueRepository
    ): Result = apply(works) { summary ->
        val result = importer.saveMetadataOnly(summary, markSaved = false, isQueuedForLater = true, enrichMetadata = false)
        if (result is WorkImportResult.Success) {
            queues.addToSavedForLater(result.work.id)
        }
        result
    }

    suspend fun resolve(
        works: List<AO3WorkSummary>,
        importer: WorkImporter,
        onResolved: (List<SavedWork>) -> Unit
    ): Result {
        val resolved = mutableListOf<SavedWork>()
        val result = apply(works) { summary ->
            importer.saveMetadataOnly(summary, markSaved = false, enrichMetadata = false).also {
                if (it is WorkImportResult.Success) resolved += it.work
            }
        }
        if (resolved.isNotEmpty()) onResolved(resolved)
        return result
    }

    private suspend fun apply(
        works: List<AO3WorkSummary>,
        action: suspend (AO3WorkSummary) -> WorkImportResult
    ): Result {
        var added = 0
        var failed = 0
        for (summary in works) {
            currentCoroutineContext().ensureActive()
            val result = try { action(summary) } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) { null }
            if (result is WorkImportResult.Success) added++ else failed++
            // A missing work does not prevent the next one; a block/outage does.
            if (result !is WorkImportResult.Success &&
                (result !is WorkImportResult.Failure || result.error != AO3Error.NotFound)) {
                failed = works.size - added
                break
            }
        }
        return Result(added, failed)
    }
}

/**
 * One selectable row for a remote result, shared by all four host surfaces so a
 * selected work looks and behaves identically wherever it is selected.
 * Promoted out of `SearchScreen`, which was the only surface that had it.
 */
@Composable
fun SelectableRemoteWorkRow(
    work: AO3WorkSummary,
    selected: Boolean,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier,
    expandAll: Boolean = false
) {
    SensitiveWorkRow(work = work, onOpenWork = { onToggle() }, modifier = modifier,
        ledger = true, selecting = true, selected = selected, selectionAllowsDetails = true,
        expandAll = expandAll, onLongClick = onToggle)
}
