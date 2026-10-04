package io.github.cidy02.kudos.library

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

/** Every queue with its work count, as the Library's dashboard and its Add to Queue dialog list them. */
internal suspend fun ReadingQueueRepository.queuePreviews(): List<LibraryQueuePreview> {
    ensureSavedForLaterQueue()
    return listQueues().map { queue ->
        LibraryQueuePreview(id = queue.id, name = queue.displayName, workCount = listWorks(queue.id).size)
    }
}

/**
 * One work into one queue. The Library's dialog, shared with Home's section lists.
 * [onManageQueues] is the "Manage queues" button; pass null where there is nowhere to go.
 */
@Composable
internal fun AddToQueueDialog(
    queues: List<LibraryQueuePreview>,
    onAdd: (queueId: String) -> Unit,
    onManageQueues: (() -> Unit)?,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add to Queue") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                if (queues.isEmpty()) {
                    Text(
                        "No queues yet. Create one from Reading Queues.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                } else {
                    queues.forEach { queue ->
                        TextButton(
                            onClick = { onAdd(queue.id) },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(queue.name, modifier = Modifier.fillMaxWidth())
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("Close") }
        },
        dismissButton = onManageQueues?.let { manage ->
            { TextButton(onClick = manage) { Text("Manage queues") } }
        }
    )
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
                                    .clickable(enabled = membershipLoaded) {
                                        val next = !isMember
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
