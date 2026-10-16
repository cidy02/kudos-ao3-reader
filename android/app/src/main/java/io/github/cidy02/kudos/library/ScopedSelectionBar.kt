package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.works.finishedActionLabel
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.DriveFileMove
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.RemoveCircleOutline
import androidx.compose.material.icons.outlined.Sell
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.ui.components.AddSelectionToCollectionDialog
import io.github.cidy02.kudos.ui.components.QueuePickerDialog
import io.github.cidy02.kudos.ui.components.setWorksDownloaded
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.works.DownloadQueue
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.works.WorkTags
import kotlinx.coroutines.launch

/** What iOS `ScopedRemovalBulkActionBar` decides, kept apart from the drawing. */
internal object SelectionActions {
    /** iOS `missingCopies`: selected works with no copy on this device that AO3 could give back. */
    fun missingCopies(works: List<SavedWork>): List<SavedWork> =
        works.filter { !it.hasEpub && WorkTags.ao3WorkIdFromUrl(it.sourceUrl) != null }

    fun removeTitle(count: Int): String = "Remove $count work${if (count == 1) "" else "s"}?"

    fun removeMessage(scopeName: String): String =
        "Kudos will remove the selected works from this $scopeName. They will stay in your Library."
}

/**
 * iOS `ScopedRemovalBulkActionBar`: what a selection can do on one queue's or one collection's
 * page. The first action is removal from that queue or collection, which deletes nothing, so
 * it has its own words. A queue's bar (artboard 1bg) puts its four up front: Download, Move
 * to, Tag, Remove, and the rest under More. A collection's keeps Remove and an Actions menu.
 */
@Composable
internal fun ScopedSelectionBar(
    selectedWorks: List<SavedWork>,
    removeLabel: String,
    scopeName: String,
    workRepository: WorkRepository,
    queueRepository: ReadingQueueRepository?,
    downloadQueue: DownloadQueue?,
    palette: SubjectPalette,
    /** The queue whose page this is: Move to leaves it, and it is not a place to move to. */
    currentQueueId: String? = null,
    /** Removes every selected work from this queue or collection. Called once it is confirmed. */
    onRemove: suspend () -> Unit,
    /** A page that already asks about a removal in its own way: Remove calls this instead. */
    onRequestRemove: (() -> Unit)? = null,
    /** Something about the works changed: read the page again. */
    onChanged: () -> Unit,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
    workImporter: io.github.cidy02.kudos.works.WorkImporter? = null
) {
    val tokens = LocalKudosTokens.current
    val scope = rememberCoroutineScope()
    var confirmRemove by remember { mutableStateOf(false) }
    var menuOpen by remember { mutableStateOf(false) }
    var addingToQueue by remember { mutableStateOf(false) }
    var movingToQueue by remember { mutableStateOf(false) }
    var addingToCollection by remember { mutableStateOf(false) }
    var tagging by remember { mutableStateOf(false) }

    val hasSelection = selectedWorks.isNotEmpty()
    val missing = SelectionActions.missingCopies(selectedWorks)
    val allFavorited = hasSelection && selectedWorks.all { it.isFavorite }
    var laterLoaded by remember { mutableStateOf(false) }
    var laterIds by remember { mutableStateOf(emptySet<String>()) }
    suspend fun reloadLater() {
        laterLoaded = false
        laterIds = selectedWorks.filter { queueRepository?.isInSavedForLater(it.id) == true }.map { it.id }.toSet()
        laterLoaded = true
    }
    LaunchedEffect(selectedWorks, queueRepository) { reloadLater() }
    val allLater = hasSelection && selectedWorks.all { it.id in laterIds }
    val allFinished = hasSelection && selectedWorks.all { it.isFinished }
    val allDownloaded = hasSelection && selectedWorks.all { it.isDownloaded }
    val queuePage = currentQueueId != null

    fun act(change: suspend () -> Unit) {
        scope.launch {
            change()
            reloadLater()
            onChanged()
        }
    }
    // One after another, through the download queue: never a burst at AO3 (iOS `bulkDownload`).
    fun downloadMissing() {
        missing.forEach { work ->
            WorkTags.ao3WorkIdFromUrl(work.sourceUrl)?.let { id ->
                downloadQueue?.enqueueLocal(id, work.title, work.sourceUrl, force = false)
            }
        }
        onChanged()
    }

    // Opaque, as the Library's own selection bar: over glass the rows behind showed through
    // the labels.
    Surface(
        modifier = modifier.fillMaxWidth(),
        tonalElevation = 6.dp,
        shadowElevation = 8.dp
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 8.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (queuePage) {
                BarAction("Download", Icons.Outlined.Download, hasSelection && missing.isNotEmpty() && downloadQueue != null,
                    palette.accent) { downloadMissing() }
                BarAction("Move to", Icons.AutoMirrored.Outlined.DriveFileMove, hasSelection && queueRepository != null,
                    palette.accent) { movingToQueue = true }
                BarAction("Tag", Icons.Outlined.Sell, hasSelection, palette.accent) { tagging = true }
                BarAction("Remove", Icons.Outlined.RemoveCircleOutline, hasSelection, MaterialTheme.colorScheme.error,
                    spoken = removeLabel) { onRequestRemove?.invoke() ?: run { confirmRemove = true } }
            } else {
                TextButton(onClick = { onRequestRemove?.invoke() ?: run { confirmRemove = true } }, enabled = hasSelection) {
                    Text(removeLabel, color = if (hasSelection) MaterialTheme.colorScheme.error else tokens.tertiaryInk,
                        fontWeight = FontWeight.SemiBold)
                }
            }
            Box {
                if (queuePage) {
                    BarAction("More", Icons.Filled.MoreVert, hasSelection, palette.accent) { menuOpen = true }
                } else {
                    TextButton(onClick = { menuOpen = true }, enabled = hasSelection) { Text("Actions", color = palette.accent) }
                }
                DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                    fun item(label: String, enabled: Boolean = true, action: () -> Unit) = Triple(label, enabled, action)
                    // The Library's five, in iOS's order, then what this page adds.
                    val items = buildList {
                        add(item(if (allDownloaded) "Remove Download" else "Download") {
                            act { setWorksDownloaded(selectedWorks, !allDownloaded, workRepository, downloadQueue) }
                        })
                        add(item(if (allFavorited) "Unfavorite" else "Favorite") {
                            act { selectedWorks.forEach { workRepository.setFavorite(it.id, !allFavorited) } }
                        })
                        if (queueRepository != null) {
                            add(item(if (allLater) "Remove from Saved for Later" else "Save for Later", laterLoaded) {
                                act { selectedWorks.forEach {
                                    if (allLater) queueRepository.removeFromSavedForLater(it.id)
                                    else queueRepository.addToSavedForLater(it.id)
                                } }
                            })
                            add(item("Add to Queue") { addingToQueue = true })
                        }
                        add(item("Add to Collection") { addingToCollection = true })
                        if (!queuePage) {
                            if (queueRepository != null) add(item("Move to Queue") { addingToQueue = false; movingToQueue = true })
                            add(item("Tag") { tagging = true })
                            add(item("Download missing copies", missing.isNotEmpty() && downloadQueue != null) { downloadMissing() })
                        }
                        add(item(finishedActionLabel(allFinished)) {
                            act { selectedWorks.forEach { workRepository.setFinished(it.id, !allFinished) } }
                        })
                    }
                    items.forEach { (label, enabled, action) ->
                        DropdownMenuItem(text = { Text(label) }, enabled = enabled, onClick = { menuOpen = false; action() })
                    }
                }
            }
            if (!queuePage) {
                IconButton(onClick = onDone) { Icon(Icons.Filled.Check, contentDescription = "Done", tint = palette.accent) }
            }
        }
    }

    if (confirmRemove) {
        AlertDialog(
            onDismissRequest = { confirmRemove = false },
            title = { Text(SelectionActions.removeTitle(selectedWorks.size)) },
            text = { Text(SelectionActions.removeMessage(scopeName)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmRemove = false
                    scope.launch {
                        onRemove()
                        onDone()
                    }
                }) { Text("Remove", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirmRemove = false }) { Text("Cancel") } }
        )
    }
    if (addingToQueue) {
        QueueMembershipDialog(works = selectedWorks, repository = queueRepository, importer = workImporter,
            onChanged = onChanged, onDismiss = { addingToQueue = false })
    }

    if (movingToQueue) {
        // Closing the picker without choosing moves nothing (iOS counts memberships to know).
        QueuePickerDialog(
            title = "Move to Queue",
            queueRepository = queueRepository,
            excludeQueueId = currentQueueId,
            onPick = { queue ->
                movingToQueue = false
                scope.launch {
                    val ids = selectedWorks.map { it.id }
                    if (currentQueueId != null) {
                        queueRepository?.moveWorks(currentQueueId, queue.id, ids)
                    } else {
                        // From a collection: the works join the queue, then leave this collection.
                        ids.forEach { runCatching { queueRepository?.addWork(queue.id, it) } }
                        onRemove()
                    }
                    // The moved rows have left this list; the selection went with them.
                    onDone()
                }
            },
            onDismiss = { movingToQueue = false }
        )
    }
    if (addingToCollection) {
        AddSelectionToCollectionDialog(
            selectedWorks = selectedWorks,
            workRepository = workRepository,
            onAdded = onChanged,
            onDismiss = { addingToCollection = false }
        )
    }
    if (tagging) {
        WorkBulkTagSheet(
            workRepository = workRepository,
            workIds = selectedWorks.map { it.id },
            palette = palette,
            onDismiss = { tagging = false; onChanged() }
        )
    }
}

/** An icon over its word, as iOS's bar labels its four. */
@Composable
private fun BarAction(
    label: String,
    icon: ImageVector,
    enabled: Boolean,
    tint: androidx.compose.ui.graphics.Color,
    spoken: String = label,
    onClick: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    val color = if (enabled) tint else tokens.tertiaryInk
    TextButton(onClick = onClick, enabled = enabled,
        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 6.dp, vertical = 2.dp)) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(icon, contentDescription = spoken.takeIf { it != label }, tint = color)
            Text(label, color = color, fontSize = 11.sp, maxLines = 1)
        }
    }
}
