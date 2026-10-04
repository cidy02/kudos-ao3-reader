package io.github.cidy02.kudos.settings

import android.text.format.Formatter
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ListAlt
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material.icons.outlined.RemoveCircleOutline
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.ui.components.DestructiveConfirmation
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.works.WorkRepository
import java.io.File
import java.text.NumberFormat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Settings › Reading Queues › Queue Storage (iOS `ReadingQueueStorageView`): what the queues
 * keep on this device, and the way to take a work out of them.
 */
@Composable
fun QueueStorageScreen(
    workRepository: WorkRepository,
    readingQueueRepository: ReadingQueueRepository,
    settingsRepository: SettingsRepository,
    workFileStore: WorkFileStore
) {
    val settings by settingsRepository.settings.collectAsState(initial = KudosSettings.Defaults)
    val works by workRepository.observeSavedWorks().collectAsState(initial = emptyList())
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val tokens = LocalKudosTokens.current

    var fileSizes by remember { mutableStateOf<Map<String, Long>>(emptyMap()) }
    var savedForLaterIds by remember { mutableStateOf<Set<String>>(emptySet()) }
    var pendingQueueRemoval by remember { mutableStateOf<SavedWork?>(null) }

    val queuedWorks = QueueStorageLogic.queuedWorks(works)
    val preservedWorks = remember(queuedWorks) {
        QueueStorageLogic.preservedWorks(queuedWorks) { id ->
            File(workFileStore.workEpubPath(id).toString()).exists()
        }
    }
    val queueOnlyWorks = QueueStorageLogic.queueOnlyWorks(queuedWorks)

    LaunchedEffect(preservedWorks) {
        withContext(Dispatchers.IO) {
            fileSizes = preservedWorks.associate { work ->
                work.id to File(workFileStore.workEpubPath(work.id).toString()).length()
            }
        }
        savedForLaterIds = workRepository.savedForLaterWorkIds()
    }

    val preservedByteCount = preservedWorks.sumOf { fileSizes[it.id] ?: 0L }

    SettingsPage(title = "Queue Storage") {
        item {
            SettingsSection(footnote = null, label = "Summary") {
                SubjectFormRow("Queued Works", value = queuedWorks.size.formatted())
                SubjectRowSeparator()
                SubjectFormRow("Queue-only Works", value = queueOnlyWorks.size.formatted())
                SubjectRowSeparator()
                SubjectFormRow("Preserved EPUBs", value = preservedWorks.size.formatted())
                SubjectRowSeparator()
                SubjectFormRow(
                    "Preserved Storage",
                    value = Formatter.formatFileSize(context, preservedByteCount)
                )
            }
        }
        item {
            SettingsSection(
                label = "Preserved EPUBs",
                footnote = "Removing a work here takes it out of its queues. It stays in Kudos if " +
                    "you saved or favorited it, but a work kept only by queues is removed when " +
                    "its last queue is gone."
            ) {
                if (preservedWorks.isEmpty()) {
                    Text(
                        text = "None of your queued works is downloaded on this device.",
                        modifier = Modifier.padding(horizontal = 13.dp, vertical = 12.dp),
                        color = tokens.secondaryInk,
                        fontSize = 15.sp
                    )
                } else {
                    // ponytail: the rows are drawn at once inside the one panel, not lazily.
                    // Fine for the few hundred a queue holds; make each row its own list item
                    // if a library with thousands of queued downloads ever shows it.
                    preservedWorks.forEachIndexed { index, work ->
                        if (index > 0) SubjectRowSeparator()
                        PreservedWorkRow(
                            work = work,
                            inSavedForLater = work.id in savedForLaterIds,
                            size = Formatter.formatFileSize(context, fileSizes[work.id] ?: 0L),
                            onRemove = { pendingQueueRemoval = work },
                            // These are already on the device because a queue keeps them.
                            // This keeps the file after they leave their queues.
                            onKeepDownload = { scope.launch { workRepository.setSaved(work.id, true) } }
                        )
                    }
                }
            }
        }
    }

    pendingQueueRemoval?.let { work ->
        DestructiveConfirmation(
            show = true,
            title = "Remove from reading queues?",
            text = if (work.isSaved || work.isFavorite) {
                "Kudos will remove the work from its reading queues. It will stay in your Library."
            } else {
                "Kudos will remove this work if it isn't in another queue, because you haven't " +
                    "saved or favorited it."
            },
            confirmText = if (work.isQueueOnlyWork) "Remove Queues & Delete" else "Remove from Queues",
            onConfirm = {
                scope.launch {
                    readingQueueRepository.removeFromAllQueuesAndDeleteIfQueueOnly(work.id)
                }
                pendingQueueRemoval = null
            },
            onDismissRequest = { pendingQueueRemoval = null },
            confirmBeforeDelete = settings.app.confirmBeforeDelete
        )
    }
}

/** One downloaded queued work: swipe to remove it from its queues, or hold for the menu. */
@OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
@Composable
private fun PreservedWorkRow(
    work: SavedWork,
    inSavedForLater: Boolean,
    size: String,
    onRemove: () -> Unit,
    onKeepDownload: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    var showsMenu by remember { mutableStateOf(false) }
    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            if (value == SwipeToDismissBoxValue.EndToStart) onRemove()
            false
        }
    )
    // At rest the row is part of the panel and shows its glass. Only while it is being
    // swiped does it need a ground of its own, to cover the red behind it.
    val swiping = dismissState.dismissDirection == SwipeToDismissBoxValue.EndToStart
    SwipeToDismissBox(
        state = dismissState,
        enableDismissFromStartToEnd = false,
        backgroundContent = {
            if (swiping) {
                Row(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(MaterialTheme.colorScheme.error)
                        .padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.End
                ) {
                    Icon(
                        Icons.Outlined.RemoveCircleOutline,
                        contentDescription = "Remove from Queues",
                        tint = MaterialTheme.colorScheme.onError
                    )
                }
            }
        }
    ) {
        Box {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .then(if (swiping) Modifier.background(tokens.background) else Modifier)
                    .combinedClickable(onClick = {}, onLongClick = { showsMenu = true })
                    .padding(horizontal = 13.dp, vertical = 12.dp),
                verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Icon(
                    imageVector = if (inSavedForLater) Icons.Filled.Schedule else Icons.AutoMirrored.Outlined.ListAlt,
                    contentDescription = null,
                    modifier = Modifier.size(24.dp),
                    tint = tokens.accent
                )
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        text = work.title,
                        color = tokens.primaryInk,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                    if (work.author.isNotEmpty()) {
                        Text(work.author, color = tokens.secondaryInk, fontSize = 12.sp)
                    }
                    Text(size, color = tokens.secondaryInk, fontSize = 11.sp)
                }
                if (work.isQueueOnlyWork) {
                    Text(
                        text = "Queue",
                        modifier = Modifier
                            .background(tokens.glassStroke(0.13), RoundedCornerShape(50))
                            .padding(horizontal = 8.dp, vertical = 4.dp),
                        color = tokens.secondaryInk,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                }
            }
            DropdownMenu(expanded = showsMenu, onDismissRequest = { showsMenu = false }) {
                if (!work.isSaved) {
                    DropdownMenuItem(
                        text = { Text("Keep Download") },
                        leadingIcon = { Icon(Icons.Outlined.PushPin, contentDescription = null) },
                        onClick = {
                            showsMenu = false
                            onKeepDownload()
                        }
                    )
                }
                DropdownMenuItem(
                    text = { Text("Remove from Reading Queues") },
                    leadingIcon = { Icon(Icons.Outlined.RemoveCircleOutline, contentDescription = null) },
                    onClick = {
                        showsMenu = false
                        onRemove()
                    }
                )
            }
        }
    }
}

private fun Int.formatted(): String = NumberFormat.getIntegerInstance().format(this)

// QueueStorageLogic for the JUnit test
object QueueStorageLogic {
    fun queuedWorks(works: List<SavedWork>): List<SavedWork> {
        return works.filter { it.isQueuedForLater }
    }
    fun preservedWorks(queuedWorks: List<SavedWork>, fileExists: (String) -> Boolean): List<SavedWork> {
        return queuedWorks.filter { it.hasEpub && fileExists(it.id) }
    }
    fun queueOnlyWorks(queuedWorks: List<SavedWork>): List<SavedWork> {
        return queuedWorks.filter { it.isQueueOnlyWork }
    }
}
