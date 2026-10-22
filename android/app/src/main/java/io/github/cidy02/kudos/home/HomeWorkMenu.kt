package io.github.cidy02.kudos.home

import io.github.cidy02.kudos.ui.components.workDeletionMessage

import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
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
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkDownloadAction
import io.github.cidy02.kudos.core.model.WorkDownloadSemantics
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.ui.components.DestructiveConfirmation
import io.github.cidy02.kudos.works.DownloadQueue
import io.github.cidy02.kudos.works.WorkImporter
import io.github.cidy02.kudos.works.RebuildOriginalDialog
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.works.WorkTags
import kotlinx.coroutines.launch

/** Dialog targets shared by the long-press menu and the select-mode bulk bar. */
class HomeWorkController {
    var queueTargets by mutableStateOf<List<SavedWork>>(emptyList())
    var collectionTargets by mutableStateOf<List<SavedWork>>(emptyList())
    var tagTargets by mutableStateOf<List<SavedWork>>(emptyList())
    var deleteTargets by mutableStateOf<List<SavedWork>>(emptyList())
    var deletingSelection by mutableStateOf(false)
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
    var rebuildOpen by remember(work.id) { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    if (rebuildOpen && workImporter != null) {
        RebuildOriginalDialog(work, workImporter, onRebuilt = {
            scope.launch { controller.onChanged() }
        }, onDismiss = { rebuildOpen = false })
    }
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
                // Read and Work Details in this menu opened a work the blur was hiding, past
                // the reveal and its device check (audit A19-6, the same on iOS).
                onLongClick = { if (!obscured) menuOpen = true }
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
                    rebuildOpen = true
                }
            }
            MenuItem("Work Details") {
                menuOpen = false
                onDetails(work)
            }
            MenuItem("Delete", destructive = true) {
                menuOpen = false
                controller.deletingSelection = false
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
        if (fresh.hasEpub) {
            downloadQueue?.showInstantDownload(fresh.id)
        } else {
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
    onDeleted: () -> Unit,
    workImporter: WorkImporter? = null
) {
    val scope = rememberCoroutineScope()
    if (controller.queueTargets.isNotEmpty()) {
        io.github.cidy02.kudos.library.QueueMembershipDialog(
            works = controller.queueTargets, repository = queueRepository, importer = workImporter,
            onChanged = { scope.launch { controller.onChanged() } },
            onDismiss = { controller.queueTargets = emptyList() })
    }
    if (controller.collectionTargets.isNotEmpty()) {
        io.github.cidy02.kudos.ui.components.AddSelectionToCollectionDialog(
            selectedWorks = controller.collectionTargets, workRepository = workRepository,
            onAdded = { scope.launch { controller.onChanged() } },
            onDismiss = { controller.collectionTargets = emptyList() })
    }
    if (controller.tagTargets.isNotEmpty()) {
        io.github.cidy02.kudos.library.WorkBulkTagSheet(
            workRepository = workRepository, workIds = controller.tagTargets.map { it.id },
            palette = io.github.cidy02.kudos.ui.subject.LocalKudosTokens.current.scopePalette,
            onDismiss = { controller.tagTargets = emptyList() })
    }
    DestructiveConfirmation(
        show = controller.deleteTargets.isNotEmpty(),
        title = if (controller.deleteTargets.size == 1) {
            "Delete this work?"
        } else {
            "Delete ${controller.deleteTargets.size} works?"
        },
        text = workDeletionMessage(controller.deleteTargets),
        confirmText = "Delete",
        confirmBeforeDelete = controller.deletingSelection || confirmBeforeDelete,
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
