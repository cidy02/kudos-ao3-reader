package io.github.cidy02.kudos.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.outlined.Bookmark
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.CollectionsBookmark
import androidx.compose.material.icons.outlined.Queue
import androidx.compose.material.icons.outlined.RemoveCircleOutline
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.works.WorkRepository
import kotlinx.coroutines.launch

/**
 * The bulk-action bar for a single Reading Queue's or Collection's selection mode.
 * Shaped like [WorkBulkActionBar] (an icon row of secondary actions plus an
 * overflow menu), but the primary action is scoped membership removal rather than
 * a library-wide soft-delete — removing works from one queue/collection doesn't
 * delete or unsave them, so it gets its own confirmation copy and calls back into
 * [onRemove] (the caller's own scoped-removal loop) instead of
 * `workRepository.softDelete`.
 */
@Composable
fun ScopedRemovalBulkActionBar(
    selectedWorks: List<SavedWork>,
    workRepository: WorkRepository,
    queueRepository: ReadingQueueRepository?,
    /** e.g. "Remove from Queue" / "Remove from Collection". */
    removeLabel: String,
    /** e.g. "queue" / "collection" — used in the confirmation copy. */
    scopeName: String,
    onRemove: suspend () -> Unit,
    onDone: () -> Unit = {},
    modifier: Modifier = Modifier
) {
    val scope = rememberCoroutineScope()
    var confirmRemove by remember { mutableStateOf(false) }
    var showingAddToQueue by remember { mutableStateOf(false) }
    var showingAddToCollection by remember { mutableStateOf(false) }
    var overflowExpanded by remember { mutableStateOf(false) }

    val hasSelection = selectedWorks.isNotEmpty()
    val allFavorited = hasSelection && selectedWorks.all { it.isFavorite }
    val allSaved = hasSelection && selectedWorks.all { it.isSaved }
    val allFinished = hasSelection && selectedWorks.all { it.isFinished }

    Surface(
        tonalElevation = 6.dp,
        shadowElevation = 8.dp,
        modifier = modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { confirmRemove = true }, enabled = hasSelection) {
                    Icon(Icons.Outlined.RemoveCircleOutline, removeLabel)
                }
                IconButton(onClick = {
                    scope.launch {
                        val target = !allFavorited
                        selectedWorks.forEach { workRepository.setFavorite(it.id, target) }
                        onDone()
                    }
                }, enabled = hasSelection) {
                    Icon(Icons.Outlined.Star, "Favorite")
                }
                IconButton(onClick = {
                    scope.launch {
                        val target = !allSaved
                        selectedWorks.forEach { workRepository.setSaved(it.id, target) }
                        onDone()
                    }
                }, enabled = hasSelection) {
                    Icon(Icons.Outlined.Bookmark, "Save")
                }
                IconButton(onClick = { showingAddToQueue = true }, enabled = hasSelection) {
                    Icon(Icons.Outlined.Queue, "Add to Queue")
                }
                IconButton(onClick = { showingAddToCollection = true }, enabled = hasSelection) {
                    Icon(Icons.Outlined.CollectionsBookmark, "Add to Collection")
                }
                IconButton(onClick = {
                    scope.launch {
                        val target = !allFinished
                        selectedWorks.forEach { workRepository.setFinished(it.id, target) }
                        onDone()
                    }
                }, enabled = hasSelection) {
                    Icon(Icons.Outlined.CheckCircle, "Mark Finished")
                }
            }

            Row(verticalAlignment = Alignment.CenterVertically) {
                Box {
                    IconButton(onClick = { overflowExpanded = true }, enabled = hasSelection) {
                        Icon(Icons.Default.MoreVert, "More actions")
                    }
                    DropdownMenu(
                        expanded = overflowExpanded,
                        onDismissRequest = { overflowExpanded = false }
                    ) {
                        DropdownMenuItem(
                            text = { Text("Unfavorite") },
                            onClick = {
                                overflowExpanded = false
                                scope.launch {
                                    selectedWorks.forEach { workRepository.setFavorite(it.id, false) }
                                    onDone()
                                }
                            }
                        )
                        DropdownMenuItem(
                            text = { Text("Unsave") },
                            onClick = {
                                overflowExpanded = false
                                scope.launch {
                                    selectedWorks.forEach { workRepository.setSaved(it.id, false) }
                                    onDone()
                                }
                            }
                        )
                        DropdownMenuItem(
                            text = { Text("Mark Unfinished") },
                            onClick = {
                                overflowExpanded = false
                                scope.launch {
                                    selectedWorks.forEach { workRepository.setFinished(it.id, false) }
                                    onDone()
                                }
                            }
                        )
                        HorizontalDivider()
                        DropdownMenuItem(
                            text = { Text(removeLabel, color = MaterialTheme.colorScheme.error) },
                            onClick = {
                                overflowExpanded = false
                                confirmRemove = true
                            }
                        )
                    }
                }
                TextButton(onClick = onDone) {
                    Text("Cancel")
                }
            }
        }
    }

    DestructiveConfirmation(
        show = confirmRemove,
        title = if (selectedWorks.size == 1) "$removeLabel?" else "$removeLabel (${selectedWorks.size})?",
        text = "The selected works will no longer be in this $scopeName. They stay in your Library either way.",
        confirmText = "Remove",
        confirmBeforeDelete = true,
        onConfirm = {
            confirmRemove = false
            scope.launch {
                onRemove()
                onDone()
            }
        },
        onDismissRequest = { confirmRemove = false }
    )

    if (showingAddToQueue) {
        var queues by remember { mutableStateOf<List<ReadingQueue>?>(null) }
        LaunchedEffect(Unit) {
            queues = queueRepository?.listQueues() ?: emptyList()
        }
        AlertDialog(
            onDismissRequest = { showingAddToQueue = false },
            title = { Text("Add Selection to Queue") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    if (queues == null) {
                        Text("Loading...", style = MaterialTheme.typography.bodyMedium)
                    } else if (queues!!.isEmpty()) {
                        Text("No custom queues yet.", style = MaterialTheme.typography.bodyMedium)
                    } else {
                        queues!!.forEach { queue ->
                            TextButton(
                                onClick = {
                                    showingAddToQueue = false
                                    scope.launch {
                                        selectedWorks.forEach { runCatching { queueRepository?.addWork(queue.id, it.id) } }
                                        onDone()
                                    }
                                },
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text(queue.displayName, modifier = Modifier.fillMaxWidth())
                            }
                        }
                    }
                }
            },
            confirmButton = { TextButton(onClick = { showingAddToQueue = false }) { Text("Close") } }
        )
    }

    if (showingAddToCollection) {
        var newName by remember { mutableStateOf("") }
        var collections by remember { mutableStateOf<List<WorkCollection>?>(null) }
        LaunchedEffect(Unit) {
            collections = workRepository.allCollections()
        }
        AlertDialog(
            onDismissRequest = { showingAddToCollection = false },
            title = { Text("Add Selection to Collection") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = newName,
                        onValueChange = { newName = it },
                        label = { Text("New or existing collection") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                    if (collections != null && collections!!.isNotEmpty()) {
                        Text("Existing collections:", style = MaterialTheme.typography.labelMedium)
                        collections!!.forEach { col ->
                            TextButton(
                                onClick = {
                                    showingAddToCollection = false
                                    scope.launch {
                                        selectedWorks.forEach { runCatching { workRepository.addToCollection(it.id, col.name) } }
                                        onDone()
                                    }
                                },
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text(col.name, modifier = Modifier.fillMaxWidth())
                            }
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(
                    enabled = newName.trim().isNotEmpty(),
                    onClick = {
                        val name = newName.trim()
                        showingAddToCollection = false
                        scope.launch {
                            selectedWorks.forEach { runCatching { workRepository.addToCollection(it.id, name) } }
                            onDone()
                        }
                    }
                ) { Text("Add") }
            },
            dismissButton = { TextButton(onClick = { showingAddToCollection = false }) { Text("Cancel") } }
        )
    }
}
