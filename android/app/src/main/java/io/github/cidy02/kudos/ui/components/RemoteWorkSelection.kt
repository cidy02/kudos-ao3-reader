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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.works.WorkImportResult
import io.github.cidy02.kudos.works.WorkImporter

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
                TextButton(onClick = onSaveForLater, enabled = state.hasSelection && !busy) {
                    Text("Save for Later")
                }
                TextButton(onClick = onSaveToLibrary, enabled = state.hasSelection && !busy) {
                    Text("Save")
                }
                TextButton(onClick = state::exit, enabled = !busy) { Text("Cancel") }
            }
        }
    }
}

/**
 * Bulk actions for remote summaries (iOS `RemoteWorkBulkActions`).
 *
 * A remote result is only a search-page blurb, so each one is first resolved
 * into a real local record via [WorkImporter.saveMetadataOnly] — metadata only,
 * no EPUB download, which is what makes bulk-selecting 20 results reasonable.
 * Failures are per-work so one dead link doesn't sink the batch.
 */
object RemoteWorkBulkActions {

    suspend fun saveToLibrary(
        works: List<AO3WorkSummary>,
        importer: WorkImporter
    ): String = apply(works) { importer.saveMetadataOnly(it, markSaved = true) }

    suspend fun saveForLater(
        works: List<AO3WorkSummary>,
        importer: WorkImporter,
        queues: ReadingQueueRepository
    ): String = apply(works) { summary ->
        val result = importer.saveMetadataOnly(summary, markSaved = false, isQueuedForLater = true)
        if (result is WorkImportResult.Success) {
            queues.addToSavedForLater(result.work.id)
        }
        result
    }

    private suspend fun apply(
        works: List<AO3WorkSummary>,
        action: suspend (AO3WorkSummary) -> WorkImportResult
    ): String {
        if (works.isEmpty()) return "Nothing selected."
        var added = 0
        var failed = 0
        for (summary in works) {
            val result = runCatching { action(summary) }.getOrNull()
            if (result is WorkImportResult.Success) added++ else failed++
        }
        return when {
            failed == 0 -> "Added $added to your Library."
            added == 0 -> "Couldn't add ${works.size}. Check your connection and try again."
            else -> "Added $added. $failed couldn't be added."
        }
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
    modifier: Modifier = Modifier
) {
    androidx.compose.material3.Card(
        onClick = onToggle,
        colors = androidx.compose.material3.CardDefaults.cardColors(
            containerColor = if (selected) {
                MaterialTheme.colorScheme.primaryContainer
            } else {
                MaterialTheme.colorScheme.surfaceContainerLow
            }
        ),
        modifier = modifier
            .fillMaxWidth()
            .semantics { contentDescription = if (selected) "${work.title}, selected" else work.title }
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            androidx.compose.material3.Checkbox(checked = selected, onCheckedChange = { onToggle() })
            androidx.compose.foundation.layout.Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = work.title,
                    style = MaterialTheme.typography.titleMedium,
                    maxLines = 1,
                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis
                )
                Text(
                    text = work.authorText,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}
