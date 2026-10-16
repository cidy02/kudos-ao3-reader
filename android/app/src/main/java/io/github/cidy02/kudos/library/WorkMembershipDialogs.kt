package io.github.cidy02.kudos.library

import androidx.compose.ui.semantics.Role
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.works.WorkRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.ensureActive

/** Every queue with its work count, as the Library's dashboard and its Add to Queue dialog list them. */
internal suspend fun ReadingQueueRepository.queuePreviews(): List<LibraryQueuePreview> {
    ensureSavedForLaterQueue()
    return listQueues().map { queue ->
        LibraryQueuePreview(id = queue.id, name = queue.displayName, workCount = listWorks(queue.id).size)
    }
}

/**
 * Checklist of existing shelves plus create-new (iOS AddToCollectionView). The Library's dialog,
 * shared with Home's section lists. Membership is tracked locally because the Library snapshot
 * only re-emits when the works Flow changes, not on cross-ref-only membership toggles.
 * [scope] is the caller's screen scope, so a write outlives the dialog.
 */
@Composable
internal fun AddToCollectionDialog(
    workId: String,
    collections: List<WorkCollection>,
    workRepository: WorkRepository,
    scope: CoroutineScope,
    onSetMembership: (collectionId: String, member: Boolean) -> Unit,
    onDismiss: () -> Unit
) {
    var newName by remember(workId) { mutableStateOf("") }
    var memberIds by remember(workId) { mutableStateOf<Set<String>>(emptySet()) }
    var membershipLoaded by remember(workId) { mutableStateOf(false) }
    LaunchedEffect(workId) {
        membershipLoaded = false
        memberIds = runCatching {
            workRepository.collectionsForWork(workId).map { it.id }.toSet()
        }.getOrDefault(emptySet())
        membershipLoaded = true
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add to Collection") },
        text = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 420.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    OutlinedTextField(
                        value = newName,
                        onValueChange = { newName = it },
                        label = { Text("New collection") },
                        singleLine = true,
                        modifier = Modifier.weight(1f)
                    )
                    TextButton(
                        enabled = newName.trim().isNotEmpty(),
                        onClick = {
                            val name = newName.trim()
                            if (name.isEmpty()) return@TextButton
                            newName = ""
                            // Create-or-match by name and attach; update local
                            // checklist from the returned membership list.
                            scope.launch {
                                val updated = runCatching {
                                    workRepository.addToCollection(workId, name)
                                }.getOrDefault(emptyList())
                                memberIds = updated.map { it.id }.toSet()
                            }
                        }
                    ) { Text("Add") }
                }
                if (collections.isEmpty()) {
                    Text(
                        "No collections yet. Create one above to start grouping works.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                } else {
                    Text(
                        text = "Collections",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    collections
                        .sortedBy { it.name.lowercase() }
                        .forEach { collection ->
                            val isMember = collection.id in memberIds
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    // One control with a state TalkBack can say (audit A13).
                                    .toggleable(value = isMember, enabled = membershipLoaded, role = Role.Checkbox) { next ->
                                        memberIds = if (next) {
                                            memberIds + collection.id
                                        } else {
                                            memberIds - collection.id
                                        }
                                        onSetMembership(collection.id, next)
                                    }
                                    .padding(vertical = 2.dp),
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Checkbox(
                                    checked = isMember,
                                    onCheckedChange = null,
                                    enabled = membershipLoaded
                                )
                                Text(
                                    text = collection.name,
                                    style = MaterialTheme.typography.bodyLarge,
                                    modifier = Modifier.weight(1f)
                                )
                                Text(
                                    text = collection.workIds.size.toString(),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("Done") }
        }
    )
}

/** Library and bulk selection use the existing queue form; Work Detail remains additive-only. */
@Composable
internal fun QueueMembershipDialog(
    works: List<io.github.cidy02.kudos.core.model.SavedWork>,
    repository: ReadingQueueRepository?,
    importer: io.github.cidy02.kudos.works.WorkImporter? = null,
    onChanged: () -> Unit = {},
    onDismiss: () -> Unit
) {
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    var queues by remember { mutableStateOf(emptyList<io.github.cidy02.kudos.core.model.ReadingQueue>()) }
    var members by remember { mutableStateOf(emptySet<String>()) }
    var name by remember { mutableStateOf("") }
    var working by remember { mutableStateOf(true) }
    var includeSeries by remember { mutableStateOf(false) }
    var preserving by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf<SeriesPreservationResult?>(null) }
    var seriesJob by remember { mutableStateOf<kotlinx.coroutines.Job?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    val series = works.map { it.seriesUrl }.filter { it.isNotBlank() }.distinct()
    suspend fun reload() {
        val repo = repository ?: return
        repo.ensureSavedForLaterQueue()
        queues = repo.listQueues()
        members = queues.filter { queue ->
            val ids = repo.listWorks(queue.id).map { it.membership.workID }.toSet()
            works.isNotEmpty() && works.all { it.id in ids }
        }.map { it.id }.toSet()
    }
    fun change(action: suspend () -> Unit) {
        working = true
        scope.launch {
            try { action(); reload(); onChanged() } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled } catch (failure: Exception) { error = failure.message ?: "Could not change queue membership." } finally { working = false }
        }
    }
    LaunchedEffect(works.map { it.id }) { change {} }
    io.github.cidy02.kudos.works.detail.WorkDetailQueueForm(
        queues, members, name, working || works.isEmpty() || repository == null, series.isNotEmpty() && importer != null,
        includeSeries, false, null, preserving, result,
        onName = { name = it },
        onCreate = { change {
            val queue = repository!!.createQueue(name.trim())
            name = ""
            works.forEach { repository.addWork(queue.id, it.id) }
        } },
        onAdd = { queue -> change {
            val remove = queue.id in members
            works.forEach { work ->
                if (remove) repository!!.removeWork(queue.id, work.id)
                else repository!!.addWork(queue.id, work.id)
            }
        } },
        onIncludeSeries = { includeSeries = it },
        onPreserve = {
            val targets = queues.filter { it.id in members }
            if (!preserving && importer != null && repository != null && targets.isNotEmpty()) {
                preserving = true
                seriesJob = scope.launch {
                    try {
                        val seriesRepository = io.github.cidy02.kudos.network.ao3.series.AO3SeriesRepository()
                        for (url in series) {
                            kotlinx.coroutines.currentCoroutineContext().ensureActive()
                            result = repository.preserveSeries(url, targets, seriesRepository, importer,
                                progress = { result = it })
                        }
                        reload(); onChanged()
                    } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled } catch (failure: Exception) { error = failure.message ?: "Could not add the series." } finally { preserving = false }
                }
            }
        },
        onCancel = { seriesJob?.cancel(); preserving = false },
        onClose = { if (!working) { seriesJob?.cancel(); onDismiss() } },
        registerShellChrome = false
    )
    error?.let { message ->
        AlertDialog(onDismissRequest = { error = null }, title = { Text("Queue membership") },
            text = { Text(message) }, confirmButton = { TextButton(onClick = { error = null }) { Text("OK") } })
    }
}
