package io.github.cidy02.kudos.library

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkDownloadAction
import io.github.cidy02.kudos.ui.components.setWorksDownloaded
import io.github.cidy02.kudos.ui.components.workDeletionMessage
import io.github.cidy02.kudos.works.DownloadQueue
import io.github.cidy02.kudos.works.RebuildOriginalDialog
import io.github.cidy02.kudos.works.WorkImporter
import io.github.cidy02.kudos.network.ao3.displayMessage
import io.github.cidy02.kudos.works.WorkRepository
import kotlinx.coroutines.launch

/** The Library's work actions on a queue/collection page, with the same pickers and dialogs. */
@Composable
internal fun scopedWorkActions(
    workRepository: WorkRepository,
    queueRepository: ReadingQueueRepository?,
    downloadQueue: DownloadQueue?,
    importer: WorkImporter?,
    confirmBeforeDelete: Boolean,
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit,
    onOpenComments: (Long) -> Unit,
    onSelect: (String) -> Unit,
    onReveal: (String) -> Unit,
    onChanged: () -> Unit
): LibraryCardActions {
    val scope = rememberCoroutineScope()
    var queueWork by remember { mutableStateOf<String?>(null) }
    var collectionWork by remember { mutableStateOf<String?>(null) }
    var deleteWork by remember { mutableStateOf<SavedWork?>(null) }
    var rebuildWork by remember { mutableStateOf<SavedWork?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    fun change(action: suspend () -> Unit) {
        scope.launch {
            try { action(); onChanged() } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled } catch (failure: Exception) { error = failure.message ?: "Could not change this work." }
        }
    }
    queueWork?.let { id ->
        val work = workRepositoryWork(id, workRepository)
        if (work != null) QueueMembershipDialog(
            works = listOf(work),
            repository = queueRepository, importer = importer,
            onChanged = onChanged,
            onDismiss = { queueWork = null }
        )
    }
    collectionWork?.let { id ->
        var collections by remember(id) { mutableStateOf(emptyList<io.github.cidy02.kudos.core.model.WorkCollection>()) }
        androidx.compose.runtime.LaunchedEffect(id) { collections = workRepository.allCollections() }
        AddToCollectionDialog(id, collections, workRepository, scope,
            onSetMembership = { collectionId, member -> change {
                if (member) workRepository.addWorkToCollection(id, collectionId)
                else workRepository.removeFromCollection(id, collectionId)
            } }, onDismiss = { collectionWork = null })
    }
    deleteWork?.let { work ->
        io.github.cidy02.kudos.ui.components.DestructiveConfirmation(
            show = true, title = "Delete this work?", text = workDeletionMessage(listOf(work)),
            confirmText = "Delete", confirmBeforeDelete = confirmBeforeDelete,
            onConfirm = { deleteWork = null; change { workRepository.softDelete(work.id) } },
            onDismissRequest = { deleteWork = null }
        )
    }
    rebuildWork?.let { work ->
        importer?.let { RebuildOriginalDialog(work, it, onDismiss = { rebuildWork = null; onChanged() }) }
    }
    error?.let { message ->
        AlertDialog(onDismissRequest = { error = null }, title = { Text("Work actions") },
            text = { Text(message) }, confirmButton = { TextButton(onClick = { error = null }) { Text("OK") } })
    }
    return LibraryCardActions(
        onOpenWork = onOpenWork, onOpenReader = { id -> change {
            val work = workRepository.getWork(id)
            if (work != null && importer != null) {
                when (val result = importer.prepareForReading(work)) {
                    is io.github.cidy02.kudos.works.WorkImportResult.Success -> onOpenReader(result.work.id)
                    is io.github.cidy02.kudos.works.WorkImportResult.Failure -> error = result.error.displayMessage()
                }
            } else if (work?.hasEpub == true) onOpenReader(id) else onOpenWork(id)
        } }, onOpenComments = onOpenComments,
        canReadWithoutCopy = importer != null,
        isInSavedForLater = { queueRepository?.isInSavedForLater(it) == true },
        onSelect = onSelect, onReveal = onReveal,
        onToggleFavorite = { change { workRepository.toggleFavorite(it) } },
        onToggleFinished = { change { workRepository.toggleFinished(it) } },
        onToggleSavedForLater = { id, _ -> change {
            queueRepository?.let { queues ->
                if (queues.isInSavedForLater(id)) queues.removeFromSavedForLater(id)
                else queues.addToSavedForLater(id)
            }
        } },
        onRemove = { id -> change { deleteWork = workRepository.getWork(id) } },
        onDownloadAction = { id, action -> change {
            workRepository.getWork(id)?.let { work ->
                setWorksDownloaded(listOf(work), action == WorkDownloadAction.Download, workRepository, downloadQueue)
            }
        } },
        onAddToQueue = { queueWork = it }, onAddToCollection = { collectionWork = it },
        canRebuildFromOriginal = { importer?.canRebuildFromOriginal(it) == true },
        onRebuildFromOriginal = { rebuildWork = it }
    )
}

@Composable
private fun workRepositoryWork(id: String, repository: WorkRepository): SavedWork? {
    var work by remember(id) { mutableStateOf<SavedWork?>(null) }
    androidx.compose.runtime.LaunchedEffect(id) { work = repository.getWork(id) }
    return work
}
