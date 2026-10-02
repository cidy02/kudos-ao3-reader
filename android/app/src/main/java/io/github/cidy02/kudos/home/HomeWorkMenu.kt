package io.github.cidy02.kudos.home

import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.core.model.WorkDownloadAction
import io.github.cidy02.kudos.core.model.WorkDownloadSemantics
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.ui.components.DestructiveConfirmation
import io.github.cidy02.kudos.works.DownloadQueue
import io.github.cidy02.kudos.works.WorkImportResult
import io.github.cidy02.kudos.works.WorkImporter
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.works.WorkTags
import kotlinx.coroutines.launch

/** Dialog targets shared by the long-press menu and the select-mode bulk bar. */
class HomeWorkController {
    var queueTargets by mutableStateOf<List<SavedWork>>(emptyList())
    var collectionTargets by mutableStateOf<List<SavedWork>>(emptyList())
    var tagTargets by mutableStateOf<List<SavedWork>>(emptyList())
    var deleteTargets by mutableStateOf<List<SavedWork>>(emptyList())
    var message by mutableStateOf<String?>(null)
    var onChanged: suspend () -> Unit = {}
}

/**
 * Long-press menu for one local work, with iOS `LocalWorkContextMenuModifier` items.
 * Select is omitted when [allowSelect] is false (collections and subscription cards).
 */
@Composable
fun HomeLocalWorkFrame(
    work: SavedWork,
    obscured: Boolean,
    allowSelect: Boolean,
    isSelecting: Boolean,
    controller: HomeWorkController,
    workRepository: WorkRepository,
    queueRepository: ReadingQueueRepository?,
    downloadQueue: DownloadQueue?,
    workImporter: WorkImporter?,
    onOpen: (SavedWork) -> Unit,
    onDetails: (SavedWork) -> Unit,
    onComments: (Long) -> Unit,
    onReveal: (SavedWork) -> Unit,
    onToggleSelected: (SavedWork) -> Unit,
    onEnterSelect: (SavedWork) -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    var menuOpen by remember(work.id) { mutableStateOf(false) }
    var canRebuild by remember(work.id) { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(menuOpen, work.id) {
        if (menuOpen && workImporter != null) {
            canRebuild = runCatching { workImporter.canRebuildFromOriginal(work) }.getOrDefault(false)
        }
    }
    val ao3Id = WorkTags.ao3WorkIdFromUrl(work.sourceUrl)
    val downloadAction = WorkDownloadSemantics.action(
        hasEpub = work.hasEpub,
        isDownloaded = work.isDownloaded,
        hasAo3WorkId = work.hasAo3WorkId,
        keptBy = work.keptOfflineBy
    )
    Box(modifier) {
        Box(
            Modifier.combinedClickable(
                onClick = {
                    when {
                        isSelecting -> onToggleSelected(work)
                        obscured -> onReveal(work)
                        else -> onOpen(work)
                    }
                },
                onLongClick = { menuOpen = true }
            )
        ) {
            content()
        }
        DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
            MenuItem("Read") {
                menuOpen = false
                onOpen(work)
            }
            if (ao3Id != null) {
                MenuItem("Comments") {
                    menuOpen = false
                    onComments(ao3Id)
                }
            }
            if (allowSelect) {
                MenuItem("Select") {
                    menuOpen = false
                    onEnterSelect(work)
                }
            }
            if (downloadAction != null) {
                val label = when (downloadAction) {
                    WorkDownloadAction.Download -> "Download"
                    WorkDownloadAction.RemoveDownload -> "Remove Download"
                    is WorkDownloadAction.KeptBy -> "Kept Offline by ${downloadAction.name}"
                }
                MenuItem(label, enabled = downloadAction !is WorkDownloadAction.KeptBy) {
                    menuOpen = false
                    scope.launch { applyDownload(work, workRepository, downloadQueue, keep = downloadAction is WorkDownloadAction.Download) }
                }
            }
            MenuItem(if (work.isFavorite) "Unfavorite" else "Favorite") {
                menuOpen = false
                scope.launch { workRepository.setFavorite(work.id, !work.isFavorite) }
            }
            MenuItem(if (work.isQueuedForLater) "Remove from Saved for Later" else "Save for Later") {
                menuOpen = false
                scope.launch {
                    if (work.isQueuedForLater) {
                        queueRepository?.removeFromSavedForLater(work.id)
                    } else {
                        queueRepository?.addToSavedForLater(work.id)
                    }
                    controller.onChanged()
                }
            }
            MenuItem("Add to Queue") {
                menuOpen = false
                controller.queueTargets = listOf(work)
            }
            MenuItem(if (work.isFinished) "Mark as Still Reading" else "Mark as Finished") {
                menuOpen = false
                scope.launch { workRepository.setFinished(work.id, !work.isFinished) }
            }
            MenuItem("Add to Collection") {
                menuOpen = false
                controller.collectionTargets = listOf(work)
            }
            if (canRebuild && workImporter != null) {
                MenuItem("Rebuild from Original") {
                    menuOpen = false
                    scope.launch {
                        when (workImporter.rebuildFromOriginal(work)) {
                            is WorkImportResult.Success -> Unit
                            is WorkImportResult.Failure ->
                                controller.message = "Couldn't rebuild this work from its original file."
                        }
                    }
                }
            }
            MenuItem("Work Details") {
                menuOpen = false
                onDetails(work)
            }
            MenuItem("Delete", destructive = true) {
                menuOpen = false
                controller.deleteTargets = listOf(work)
            }
        }
    }
}

suspend fun applyDownload(
    work: SavedWork,
    workRepository: WorkRepository,
    downloadQueue: DownloadQueue?,
    keep: Boolean
) {
    val fresh = workRepository.getWork(work.id) ?: work
    val action = WorkDownloadSemantics.action(
        hasEpub = fresh.hasEpub,
        isDownloaded = fresh.isDownloaded,
        hasAo3WorkId = fresh.hasAo3WorkId,
        keptBy = fresh.keptOfflineBy
    ) ?: return
    if (keep) {
        workRepository.setSaved(fresh.id, true)
        if (!fresh.hasEpub) {
            val ao3Id = WorkTags.ao3WorkIdFromUrl(fresh.sourceUrl) ?: return
            downloadQueue?.enqueueLocal(ao3Id, fresh.title, fresh.sourceUrl, force = true)
        }
    } else if (action == WorkDownloadAction.RemoveDownload) {
        workRepository.setSaved(fresh.id, false)
    }
}

@Composable
fun HomeWorkDialogs(
    controller: HomeWorkController,
    workRepository: WorkRepository,
    queueRepository: ReadingQueueRepository?,
    confirmBeforeDelete: Boolean,
    onDeleted: () -> Unit
) {
    val scope = rememberCoroutineScope()
    if (controller.queueTargets.isNotEmpty()) {
        QueueDialog(
            onDismiss = { controller.queueTargets = emptyList() },
            queueRepository = queueRepository,
            onPick = { queue ->
                val targets = controller.queueTargets
                controller.queueTargets = emptyList()
                scope.launch {
                    targets.forEach { target ->
                        runCatching { queueRepository?.addWork(queue.id, target.id) }
                    }
                    controller.onChanged()
                }
            }
        )
    }
    if (controller.collectionTargets.isNotEmpty()) {
        CollectionDialog(
            onDismiss = { controller.collectionTargets = emptyList() },
            workRepository = workRepository,
            onPick = { name ->
                val targets = controller.collectionTargets
                controller.collectionTargets = emptyList()
                scope.launch {
                    targets.forEach { target ->
                        runCatching { workRepository.addToCollection(target.id, name) }
                    }
                }
            }
        )
    }
    if (controller.tagTargets.isNotEmpty()) {
        TagDialog(
            onDismiss = { controller.tagTargets = emptyList() },
            onApply = { name ->
                val targets = controller.tagTargets
                controller.tagTargets = emptyList()
                scope.launch {
                    targets.forEach { target ->
                        runCatching { workRepository.addUserTag(target.id, name) }
                    }
                }
            }
        )
    }
    DestructiveConfirmation(
        show = controller.deleteTargets.isNotEmpty(),
        title = if (controller.deleteTargets.size == 1) {
            "Delete this work?"
        } else {
            "Delete ${controller.deleteTargets.size} works?"
        },
        text = "Selected works move to Recently Deleted for 90 days.",
        confirmText = "Delete",
        confirmBeforeDelete = confirmBeforeDelete,
        onConfirm = {
            val targets = controller.deleteTargets
            controller.deleteTargets = emptyList()
            scope.launch {
                targets.forEach { workRepository.softDelete(it.id) }
                onDeleted()
            }
        },
        onDismissRequest = { controller.deleteTargets = emptyList() }
    )
    val note = controller.message
    if (note != null) {
        AlertDialog(
            onDismissRequest = { controller.message = null },
            text = { Text(note) },
            confirmButton = {
                TextButton(onClick = { controller.message = null }) { Text("OK") }
            }
        )
    }
}

@Composable
private fun QueueDialog(
    queueRepository: ReadingQueueRepository?,
    onDismiss: () -> Unit,
    onPick: (ReadingQueue) -> Unit
) {
    var queues by remember { mutableStateOf<List<ReadingQueue>?>(null) }
    LaunchedEffect(queueRepository) {
        queues = queueRepository?.listQueues().orEmpty()
            .filter { it.kindRaw == ReadingQueueKind.CUSTOM && !it.isDeleted }
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add to Queue") },
        text = {
            Column(Modifier.heightIn(max = 320.dp).verticalScroll(rememberScrollState())) {
                val loaded = queues
                when {
                    loaded == null -> Text("Loading…")
                    loaded.isEmpty() -> Text("No custom queues yet. Use + on Home to make one.")
                    else -> loaded.forEach { queue ->
                        TextButton(onClick = { onPick(queue) }, modifier = Modifier.fillMaxWidth()) {
                            Text(queue.displayName, modifier = Modifier.fillMaxWidth())
                        }
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Close") } }
    )
}

@Composable
private fun CollectionDialog(
    workRepository: WorkRepository,
    onDismiss: () -> Unit,
    onPick: (String) -> Unit
) {
    var name by remember { mutableStateOf("") }
    var collections by remember { mutableStateOf<List<WorkCollection>?>(null) }
    LaunchedEffect(Unit) { collections = runCatching { workRepository.allCollections() }.getOrDefault(emptyList()) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add to Collection") },
        text = {
            Column(Modifier.heightIn(max = 320.dp).verticalScroll(rememberScrollState())) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("New or existing collection") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                collections.orEmpty().filter { !it.isDeleted }.forEach { collection ->
                    TextButton(onClick = { onPick(collection.name) }, modifier = Modifier.fillMaxWidth()) {
                        Text(collection.name, modifier = Modifier.fillMaxWidth())
                    }
                }
            }
        },
        confirmButton = {
            TextButton(enabled = name.isNotBlank(), onClick = { onPick(name.trim()) }) { Text("Add") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } }
    )
}

@Composable
private fun TagDialog(onDismiss: () -> Unit, onApply: (String) -> Unit) {
    var name by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Tag") },
        text = {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text("Tag name") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
        },
        confirmButton = {
            TextButton(enabled = name.isNotBlank(), onClick = { onApply(name.trim()) }) { Text("Add") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } }
    )
}

@Composable
private fun MenuItem(
    label: String,
    destructive: Boolean = false,
    enabled: Boolean = true,
    onClick: () -> Unit
) {
    DropdownMenuItem(
        text = {
            Text(label, color = if (destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface)
        },
        onClick = onClick,
        enabled = enabled
    )
}
