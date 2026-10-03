package io.github.cidy02.kudos.library

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectAmber
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectKicker
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.SwipeAction
import io.github.cidy02.kudos.ui.subject.SwipeActionRow
import io.github.cidy02.kudos.ui.subject.ToolbarCircleButton
import io.github.cidy02.kudos.ui.subject.WorkSelectionBubble
import io.github.cidy02.kudos.ui.subject.subjectPanel
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import io.github.cidy02.kudos.works.WorkRepository
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/**
 * Artboard **1bj** — Recently Deleted recovery window, redesigned to match iOS.
 */
data class RecentlyDeletedEntry(
    val id: String,
    val kicker: String,
    val noun: String,
    val title: String,
    val detail: String,
    val daysRemaining: Int,
    val isHeldCopy: Boolean,
    val deleteTitle: String,
    val deleteLabel: String
)

data class RecentlyDeletedUiState(
    val loading: Boolean = true,
    val deletedEntries: List<RecentlyDeletedEntry> = emptyList(),
    val heldEntries: List<RecentlyDeletedEntry> = emptyList(),
    val rawWorks: Map<String, SavedWork> = emptyMap(),
    val rawCollections: Map<String, WorkCollection> = emptyMap(),
    val rawQueues: Map<String, ReadingQueue> = emptyMap(),
    val queueWorkCounts: Map<String, Int> = emptyMap(),
    val error: String? = null
) {
    val allEntries: List<RecentlyDeletedEntry>
        get() = (deletedEntries + heldEntries).sortedBy { it.daysRemaining }
}

class RecentlyDeletedViewModel(
    private val workRepository: WorkRepository,
    private val queueRepository: ReadingQueueRepository? = null
) : ViewModel() {
    private val queueTick = MutableStateFlow(0)
    // iOS: .dateTime.day().month(.abbreviated) in the user's locale ("Oct 2" in en-US).
    private val dateFormatter = DateTimeFormatter.ofPattern(
        android.text.format.DateFormat.getBestDateTimePattern(Locale.getDefault(), "dMMM"),
        Locale.getDefault()
    )

    val state: StateFlow<RecentlyDeletedUiState> = combine(
        workRepository.observeRecentlyDeleted(),
        workRepository.observeRecentlyDeletedCollections(),
        workRepository.observeHeldCopies(),
        queueTick
    ) { works, collections, heldCopies, _ ->
        val queues = queueRepository?.listRecentlyDeletedQueues().orEmpty()
        // ReadingQueue carries no count; a deleted queue keeps its memberships until purged.
        val queueWorkCounts = queues.associate { it.id to (queueRepository?.listWorks(it.id)?.size ?: 0) }
        val now = Instant.now()

        val deletedWorkEntries = works.map { work ->
            RecentlyDeletedEntry(
                id = work.id,
                kicker = if (work.hasEpub) "Downloaded work" else "Work",
                noun = "work",
                title = work.title,
                detail = workDetail(work),
                daysRemaining = daysRemaining(work.permanentDeletionScheduledAt, now),
                isHeldCopy = false,
                deleteTitle = "Delete “${work.title}” permanently?",
                deleteLabel = "Delete Permanently"
            )
        }

        val deletedCollectionEntries = collections.map { collection ->
            RecentlyDeletedEntry(
                id = collection.id,
                kicker = "Local collection",
                noun = "collection",
                title = collection.name,
                detail = containerDetail(collection.workIds.size, collection.deletedAt, dateFormatter),
                daysRemaining = daysRemaining(collection.permanentDeletionScheduledAt, now),
                isHeldCopy = false,
                deleteTitle = "Delete “${collection.name}” permanently?",
                deleteLabel = "Delete Permanently"
            )
        }

        val deletedQueueEntries = queues.map { queue ->
            RecentlyDeletedEntry(
                id = queue.id,
                kicker = "Reading queue",
                noun = "reading queue",
                title = queue.displayName,
                detail = containerDetail(queueWorkCounts[queue.id] ?: 0, queue.deletedAt, dateFormatter),
                daysRemaining = daysRemaining(queue.permanentDeletionScheduledAt, now),
                isHeldCopy = false,
                deleteTitle = "Delete “${queue.displayName}” permanently?",
                deleteLabel = "Delete Permanently"
            )
        }

        val heldEntries = heldCopies.map { work ->
            val expires = work.freedAt?.plus(WorkRepository.FREED_COPY_WINDOW)
            RecentlyDeletedEntry(
                id = work.id,
                kicker = "Finished work",
                noun = "work",
                title = work.title,
                detail = workDetail(work),
                daysRemaining = daysRemaining(expires, now),
                isHeldCopy = true,
                deleteTitle = "Remove the copy of “${work.title}”?",
                deleteLabel = "Remove Copy"
            )
        }.sortedBy { it.daysRemaining }

        val allDeleted = (deletedWorkEntries + deletedCollectionEntries + deletedQueueEntries)
            .sortedBy { it.daysRemaining }

        RecentlyDeletedUiState(
            loading = false,
            deletedEntries = allDeleted,
            heldEntries = heldEntries,
            rawWorks = (works + heldCopies).associateBy { it.id },
            rawCollections = collections.associateBy { it.id },
            rawQueues = queues.associateBy { it.id },
            queueWorkCounts = queueWorkCounts
        )
    }
        .catch { throwable ->
            emit(
                RecentlyDeletedUiState(
                    loading = false,
                    error = throwable.message ?: "Recently Deleted could not be loaded."
                )
            )
        }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = RecentlyDeletedUiState(loading = true)
        )

    fun restore(entry: RecentlyDeletedEntry, onDone: (Boolean) -> Unit) {
        viewModelScope.launch {
            val success = runCatching {
                when {
                    entry.isHeldCopy -> {
                        workRepository.restoreHeldCopy(entry.id)
                        true
                    }
                    entry.noun == "work" -> {
                        workRepository.restoreFromRecentlyDeleted(entry.id) != null
                    }
                    entry.noun == "collection" -> {
                        workRepository.restoreCollectionFromRecentlyDeleted(entry.id) != null
                    }
                    entry.noun == "reading queue" -> {
                        queueRepository?.restoreQueueFromRecentlyDeleted(entry.id)
                        queueTick.value += 1
                        true
                    }
                    else -> false
                }
            }.getOrDefault(false)
            onDone(success)
        }
    }

    fun deletePermanently(entry: RecentlyDeletedEntry) {
        viewModelScope.launch {
            when {
                entry.isHeldCopy -> workRepository.freeHeldCopy(entry.id)
                entry.noun == "work" -> workRepository.hardDelete(entry.id)
                entry.noun == "collection" -> workRepository.hardDeleteCollection(entry.id)
                entry.noun == "reading queue" -> {
                    queueRepository?.hardDeleteQueue(entry.id)
                    queueTick.value += 1
                }
            }
        }
    }

    fun bulkRestore(entries: List<RecentlyDeletedEntry>, onFinished: (List<RecentlyDeletedEntry>) -> Unit) {
        viewModelScope.launch {
            val failed = mutableListOf<RecentlyDeletedEntry>()
            for (entry in entries) {
                val ok = runCatching {
                    when {
                        entry.isHeldCopy -> {
                            workRepository.restoreHeldCopy(entry.id)
                            true
                        }
                        entry.noun == "work" -> workRepository.restoreFromRecentlyDeleted(entry.id) != null
                        entry.noun == "collection" -> workRepository.restoreCollectionFromRecentlyDeleted(entry.id) != null
                        entry.noun == "reading queue" -> {
                            queueRepository?.restoreQueueFromRecentlyDeleted(entry.id)
                            true
                        }
                        else -> false
                    }
                }.getOrDefault(false)
                if (!ok) failed.add(entry)
            }
            if (entries.any { it.noun == "reading queue" }) {
                queueTick.value += 1
            }
            onFinished(failed)
        }
    }

    fun bulkDelete(entries: List<RecentlyDeletedEntry>) {
        viewModelScope.launch {
            for (entry in entries) {
                when {
                    entry.isHeldCopy -> workRepository.freeHeldCopy(entry.id)
                    entry.noun == "work" -> workRepository.hardDelete(entry.id)
                    entry.noun == "collection" -> workRepository.hardDeleteCollection(entry.id)
                    entry.noun == "reading queue" -> queueRepository?.hardDeleteQueue(entry.id)
                }
            }
            if (entries.any { it.noun == "reading queue" }) {
                queueTick.value += 1
            }
        }
    }

    fun deleteAllPermanently() {
        viewModelScope.launch {
            workRepository.hardDeleteAllPending()
            val queues = queueRepository?.listRecentlyDeletedQueues().orEmpty()
            for (queue in queues) {
                queueRepository?.hardDeleteQueue(queue.id)
            }
            val currentHeld = state.value.heldEntries
            for (held in currentHeld) {
                workRepository.freeHeldCopy(held.id)
            }
            queueTick.value += 1
        }
    }

    suspend fun getWorkAnnotationCounts(workId: String): Pair<Int, Int> =
        workRepository.getAnnotationCounts(workId)

    companion object {
        fun factory(
            workRepository: WorkRepository,
            queueRepository: ReadingQueueRepository? = null
        ): ViewModelProvider.Factory =
            viewModelFactory {
                initializer { RecentlyDeletedViewModel(workRepository, queueRepository) }
            }
    }
}

@Composable
fun RecentlyDeletedScreen(
    workRepository: WorkRepository,
    queueRepository: ReadingQueueRepository? = null,
    settingsRepository: SettingsRepository? = null
) {
    val viewModel: RecentlyDeletedViewModel = viewModel(
        factory = RecentlyDeletedViewModel.factory(workRepository, queueRepository)
    )
    val state by viewModel.state.collectAsState()
    val tokens = LocalKudosTokens.current
    val palette = tokens.scopePalette
    val scope = rememberCoroutineScope()

    var isSelecting by remember { mutableStateOf(false) }
    var selection by remember { mutableStateOf<Set<String>>(emptySet()) }
    var menuOpen by remember { mutableStateOf(false) }

    var pendingSingleDelete by remember { mutableStateOf<RecentlyDeletedEntry?>(null) }
    var pendingSingleMessage by remember { mutableStateOf<String?>(null) }
    var confirmingDeleteAll by remember { mutableStateOf(false) }
    var pendingBulkDelete by remember { mutableStateOf<List<RecentlyDeletedEntry>?>(null) }
    var restoreFailureMessage by remember { mutableStateOf<String?>(null) }

    val allEntries = state.allEntries
    val allSelected = allEntries.isNotEmpty() && allEntries.all { it.id in selection }

    ProvidePushedShellChrome(
        hasSubjectHeader = true,
        hideTabBar = isSelecting,
        customTitle = if (isSelecting) "${selection.size} selected" else null,
        trailingContent = {
            if (isSelecting) {
                TextButton(
                    onClick = {
                        selection = if (allSelected) emptySet() else allEntries.map { it.id }.toSet()
                    }
                ) {
                    Text(
                        text = if (allSelected) "Deselect All" else "Select All",
                        color = palette.accent,
                        fontWeight = FontWeight.SemiBold
                    )
                }
            } else if (allEntries.isNotEmpty()) {
                Box {
                    ToolbarCircleButton(
                        onClick = { menuOpen = true },
                        accessibilityName = "More actions"
                    ) {
                        Icon(Icons.Filled.MoreVert, contentDescription = null, tint = tokens.primaryInk)
                    }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        DropdownMenuItem(
                            text = { Text("Select") },
                            leadingIcon = {
                                Icon(Icons.AutoMirrored.Filled.List, contentDescription = null)
                            },
                            onClick = {
                                menuOpen = false
                                isSelecting = true
                                selection = emptySet()
                            }
                        )
                    }
                }
            }
        }
    )

    fun exitSelectMode() {
        isSelecting = false
        selection = emptySet()
    }

    fun promptSingleDelete(entry: RecentlyDeletedEntry) {
        scope.launch {
            val message = when {
                entry.isHeldCopy -> {
                    "Kudos removes this work's copy from your device now. The work stays in your " +
                        "reading history, and you can download it again from AO3."
                }
                entry.noun == "work" -> {
                    val work = state.rawWorks[entry.id]
                    val (highlights, bookmarks) = viewModel.getWorkAnnotationCounts(entry.id)
                    val place = if (work?.isFinished == true) null else {
                        val title = HomeFacts.locatorTitle(work?.readiumLocator)
                        when {
                            !title.isNullOrBlank() -> title
                            work != null && work.lastScrollFraction > 0.0 ->
                                "${(work.lastScrollFraction * 100.0).toInt()}%"
                            else -> null
                        }
                    }
                    workDeletionMessage(
                        hasDownload = work?.hasEpub ?: true,
                        place = place,
                        highlights = highlights,
                        bookmarks = bookmarks
                    )
                }
                entry.noun == "collection" -> {
                    val count = state.rawCollections[entry.id]?.workIds?.size ?: 0
                    containerDeletionMessage(count)
                }
                entry.noun == "reading queue" -> {
                    val count = state.queueWorkCounts[entry.id] ?: 0
                    containerDeletionMessage(count)
                }
                else -> "Kudos removes this item from your device. You can't undo this."
            }
            pendingSingleMessage = message
            pendingSingleDelete = entry
        }
    }

    Box(
        Modifier
            .fillMaxSize()
            .subjectScreenWash(palette)
    ) {
        if (state.loading) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                LoadingStateCard("Loading Recently Deleted")
            }
            return@Box
        }

        state.error?.let { err ->
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                ErrorStateCard(title = "Recently Deleted could not load", message = err)
            }
            return@Box
        }

        if (allEntries.isEmpty()) {
            Box(
                Modifier
                    .fillMaxSize()
                    .padding(horizontal = 24.dp),
                contentAlignment = Alignment.Center
            ) {
                EmptyStateCard(
                    title = "Recently Deleted",
                    message = "Items you delete stay here for 90 days. Copies of works you finish " +
                        "without keeping them stay for 60 days."
                )
            }
            return@Box
        }

        val topInset = WindowInsets.systemBars.asPaddingValues().calculateTopPadding()
        val bottomInset = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = 16.dp,
                end = 16.dp,
                top = topInset + 56.dp,
                bottom = bottomInset + (if (isSelecting) 80.dp else 24.dp)
            ),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            item {
                SubjectHeaderBlock(
                    kicker = "Library",
                    title = "Recently Deleted",
                    subtitle = "${allEntries.size} item${if (allEntries.size == 1) "" else "s"}",
                    palette = palette,
                    modifier = Modifier.padding(bottom = 6.dp)
                )
            }

            item {
                Text(
                    text = "Deleting an item here removes only the copy in Kudos, including its download, your progress, " +
                        "and your notes. The work stays on AO3.",
                    fontSize = 12.5.sp,
                    color = tokens.secondaryInk,
                    modifier = Modifier
                        .fillMaxWidth()
                        .subjectPanel()
                        .padding(horizontal = 14.dp, vertical = 12.dp)
                )
            }

            if (state.deletedEntries.isNotEmpty()) {
                item {
                    SectionRuleHeader(
                        title = "Deleted",
                        count = state.deletedEntries.size,
                        modifier = Modifier.padding(top = 8.dp)
                    )
                    Text(
                        text = "Kept for 90 days, then removed for good.",
                        fontSize = 11.5.sp,
                        color = tokens.secondaryInk,
                        modifier = Modifier.padding(start = 6.dp, top = 4.dp, bottom = 4.dp)
                    )
                }

                items(state.deletedEntries, key = { it.id }) { entry ->
                    RecentlyDeletedRow(
                        entry = entry,
                        palette = palette,
                        isSelecting = isSelecting,
                        isSelected = entry.id in selection,
                        onToggleSelection = {
                            selection = if (entry.id in selection) {
                                selection - entry.id
                            } else {
                                selection + entry.id
                            }
                        },
                        onRestore = {
                            viewModel.restore(entry) { success ->
                                if (!success) {
                                    restoreFailureMessage = restoreFailureText(listOf(entry))
                                }
                            }
                        },
                        onDeletePermanently = { promptSingleDelete(entry) }
                    )
                }
            }

            if (state.heldEntries.isNotEmpty()) {
                item {
                    SectionRuleHeader(
                        title = "Finished, not kept",
                        count = state.heldEntries.size,
                        modifier = Modifier.padding(top = 10.dp)
                    )
                    Text(
                        text = "Works you finished without downloading, favoriting or queuing them. " +
                            "Their copies stay here for 60 days so you can still read them offline, then they're removed. " +
                            "The works stay in your reading history.",
                        fontSize = 11.5.sp,
                        color = tokens.secondaryInk,
                        modifier = Modifier.padding(start = 6.dp, top = 4.dp, bottom = 4.dp)
                    )
                }

                items(state.heldEntries, key = { "held-${it.id}" }) { entry ->
                    RecentlyDeletedRow(
                        entry = entry,
                        palette = palette,
                        isSelecting = isSelecting,
                        isSelected = entry.id in selection,
                        onToggleSelection = {
                            selection = if (entry.id in selection) {
                                selection - entry.id
                            } else {
                                selection + entry.id
                            }
                        },
                        onRestore = {
                            viewModel.restore(entry) { success ->
                                if (!success) {
                                    restoreFailureMessage = restoreFailureText(listOf(entry))
                                }
                            }
                        },
                        onDeletePermanently = { promptSingleDelete(entry) }
                    )
                }
            }

            if (!isSelecting) {
                item {
                    Spacer(Modifier.padding(top = 12.dp))
                    OutlinedButton(
                        onClick = { confirmingDeleteAll = true },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 4.dp),
                        shape = CircleShape,
                        border = ButtonDefaults.outlinedButtonBorder.copy(
                            brush = androidx.compose.ui.graphics.SolidColor(Color(0xFFE53935).copy(alpha = 0.42f))
                        ),
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = Color(0xFFE53935))
                    ) {
                        Icon(
                            imageVector = Icons.Filled.Delete,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp)
                        )
                        Spacer(Modifier.padding(end = 8.dp))
                        Text(
                            text = "Delete All Permanently",
                            fontSize = 14.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
            }
        }

        if (isSelecting) {
            val chosen = allEntries.filter { it.id in selection }
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .align(Alignment.BottomCenter),
                color = tokens.background.copy(alpha = 0.95f),
                shadowElevation = 8.dp
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp)
                        .padding(bottom = bottomInset),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    TextButton(
                        onClick = {
                            viewModel.bulkRestore(chosen) { failed ->
                                if (failed.isNotEmpty()) {
                                    restoreFailureMessage = restoreFailureText(failed)
                                }
                                exitSelectMode()
                            }
                        },
                        enabled = chosen.isNotEmpty()
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.Refresh,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp)
                        )
                        Spacer(Modifier.padding(end = 6.dp))
                        Text("Restore")
                    }

                    Spacer(Modifier.weight(1f))

                    TextButton(
                        onClick = { pendingBulkDelete = chosen },
                        enabled = chosen.isNotEmpty(),
                        colors = ButtonDefaults.textButtonColors(
                            contentColor = Color(0xFFE53935)
                        )
                    ) {
                        Icon(
                            imageVector = Icons.Filled.Delete,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp)
                        )
                        Spacer(Modifier.padding(end = 6.dp))
                        Text("Delete Permanently")
                    }

                    Spacer(Modifier.weight(1f))

                    IconButton(onClick = ::exitSelectMode) {
                        Icon(
                            imageVector = Icons.Filled.Check,
                            contentDescription = "Done",
                            tint = tokens.primaryInk
                        )
                    }
                }
            }
        }
    }

    pendingSingleDelete?.let { entry ->
        AlertDialog(
            onDismissRequest = {
                pendingSingleDelete = null
                pendingSingleMessage = null
            },
            title = { Text(entry.deleteTitle) },
            text = { Text(pendingSingleMessage.orEmpty()) },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.deletePermanently(entry)
                        pendingSingleDelete = null
                        pendingSingleMessage = null
                    },
                    colors = ButtonDefaults.textButtonColors(contentColor = Color(0xFFE53935))
                ) {
                    Text(entry.deleteLabel)
                }
            },
            dismissButton = {
                TextButton(
                    onClick = {
                        pendingSingleDelete = null
                        pendingSingleMessage = null
                    }
                ) {
                    Text("Cancel")
                }
            }
        )
    }

    if (confirmingDeleteAll) {
        AlertDialog(
            onDismissRequest = { confirmingDeleteAll = false },
            title = {
                Text(if (allEntries.size == 1) "Delete 1 item permanently?" else "Delete all ${allEntries.size} items permanently?")
            },
            text = {
                Text(
                    "Kudos will permanently remove every item here and any download, progress, or notes " +
                        "stored with it, and the copies of finished works. The works stay on AO3. " +
                        "You can't undo this."
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmingDeleteAll = false
                        viewModel.deleteAllPermanently()
                    },
                    colors = ButtonDefaults.textButtonColors(contentColor = Color(0xFFE53935))
                ) {
                    Text("Delete All Permanently")
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmingDeleteAll = false }) {
                    Text("Cancel")
                }
            }
        )
    }

    pendingBulkDelete?.let { chosen ->
        AlertDialog(
            onDismissRequest = { pendingBulkDelete = null },
            title = { Text(bulkDeleteTitle(chosen.size)) },
            text = {
                Text(
                    "Kudos will permanently remove each item and any download, progress, or notes stored with it. " +
                        "The works stay on AO3. You can't undo this."
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.bulkDelete(chosen)
                        pendingBulkDelete = null
                        exitSelectMode()
                    },
                    colors = ButtonDefaults.textButtonColors(contentColor = Color(0xFFE53935))
                ) {
                    Text("Delete Permanently")
                }
            },
            dismissButton = {
                TextButton(onClick = { pendingBulkDelete = null }) {
                    Text("Cancel")
                }
            }
        )
    }

    restoreFailureMessage?.let { msg ->
        AlertDialog(
            onDismissRequest = { restoreFailureMessage = null },
            title = { Text("Couldn't Restore") },
            text = { Text(msg) },
            confirmButton = {
                TextButton(onClick = { restoreFailureMessage = null }) {
                    Text("OK")
                }
            }
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun RecentlyDeletedRow(
    entry: RecentlyDeletedEntry,
    palette: SubjectPalette,
    isSelecting: Boolean,
    isSelected: Boolean,
    onToggleSelection: () -> Unit,
    onRestore: () -> Unit,
    onDeletePermanently: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    val shape = RoundedCornerShape(16.dp)
    var menuOpen by remember { mutableStateOf(false) }

    val content: @Composable () -> Unit = {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(shape)
                .background(palette.rowWash)
                .border(if (isSelected) 2.dp else 0.5.dp, if (isSelected) tokens.accent else palette.rowBorder, shape)
                .combinedClickable(
                    onClick = if (isSelecting) onToggleSelection else { {} },
                    onLongClick = if (!isSelecting) { { menuOpen = true } } else null
                )
                .padding(horizontal = 14.dp, vertical = 12.dp)
                .semantics {
                    contentDescription = "${entry.title}, ${entry.kicker}, ${entry.detail}, ${entry.daysRemaining} days left"
                },
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                SubjectKicker(
                    text = entry.kicker,
                    palette = palette,
                    ruleWidth = SubjectMetrics.kickerRuleWidth,
                    ruleSpacing = 5.dp
                )
                Text(
                    text = entry.title,
                    color = tokens.primaryInk,
                    fontSize = 16.5.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                if (entry.detail.isNotEmpty()) {
                    Text(
                        text = entry.detail,
                        color = tokens.secondaryInk,
                        fontSize = 11.5.sp,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }

            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(1.dp)
            ) {
                Text(
                    text = "${entry.daysRemaining}d",
                    color = if (isUrgent(entry.daysRemaining)) SubjectAmber else tokens.primaryInk,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold,
                    style = TextStyle(fontFeatureSettings = "tnum")
                )
                Text(
                    text = "LEFT",
                    color = tokens.secondaryInk,
                    fontSize = 9.sp
                )
            }

            if (isSelecting) {
                WorkSelectionBubble(isSelected = isSelected, accent = palette.accent)
            }

            DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                DropdownMenuItem(
                    text = { Text("Restore") },
                    leadingIcon = { Icon(Icons.Outlined.Refresh, contentDescription = null) },
                    onClick = {
                        menuOpen = false
                        onRestore()
                    }
                )
                DropdownMenuItem(
                    text = { Text(entry.deleteLabel, color = Color(0xFFE53935)) },
                    leadingIcon = { Icon(Icons.Outlined.Delete, contentDescription = null, tint = Color(0xFFE53935)) },
                    onClick = {
                        menuOpen = false
                        onDeletePermanently()
                    }
                )
            }
        }
    }

    if (isSelecting) {
        content()
    } else {
        SwipeActionRow(
            leading = emptyList(),
            trailing = listOf(
                SwipeAction(
                    label = if (entry.isHeldCopy) "Remove" else "Delete",
                    icon = Icons.Filled.Delete,
                    color = Color(0xFFE53935),
                    onClick = onDeletePermanently
                ),
                SwipeAction(
                    label = "Restore",
                    icon = Icons.Outlined.Refresh,
                    color = palette.accent,
                    onClick = onRestore
                )
            )
        ) {
            content()
        }
    }
}

private fun daysRemaining(scheduled: Instant?, now: Instant = Instant.now()): Int =
    if (scheduled == null) 0 else daysRemainingUntil(scheduled, now).toInt()

/** Whole days left, rounded up (89 days 1 hour shows 90); 0 once due. */
internal fun daysRemainingUntil(scheduled: Instant, now: Instant = Instant.now()): Long {
    val millis = scheduled.toEpochMilli() - now.toEpochMilli()
    if (millis <= 0L) return 0L
    val dayMillis = ChronoUnit.DAYS.duration.toMillis()
    return (millis + dayMillis - 1L) / dayMillis
}

private fun isUrgent(daysRemaining: Int): Boolean = daysRemaining < 7

// iOS SavedWork.readingState (Models.swift:580): finished wins, then no file means freed.
private fun stateWord(work: SavedWork): String = when {
    work.isFinished -> "finished"
    !work.hasEpub -> "read, file freed"
    work.hasStartedReading -> "part-read"
    else -> "unread"
}

private fun workDetail(work: SavedWork): String {
    val parts = mutableListOf<String>()
    if (work.author.isNotBlank()) parts.add(work.author)
    if (work.wordCount > 0) parts.add(String.format(Locale.US, "%,d words", work.wordCount))
    parts.add(stateWord(work))
    return parts.joinToString(" · ")
}

private fun containerDetail(count: Int, deletedAt: Instant?, formatter: DateTimeFormatter): String {
    val noun = if (count == 1) "1 work" else "$count works"
    if (deletedAt == null) return noun
    val dateStr = formatter.format(deletedAt.atZone(ZoneId.systemDefault()))
    return "$noun · deleted $dateStr"
}

private fun workDeletionMessage(
    hasDownload: Boolean,
    place: String?,
    highlights: Int,
    bookmarks: Int
): String {
    val parts = mutableListOf<String>()
    if (hasDownload) parts.add("the download")
    if (!place.isNullOrBlank()) {
        val formattedPlace = if (place.startsWith("Ch ")) "chapter " + place.removePrefix("Ch ") else place
        parts.add("your place at $formattedPlace")
    }
    if (highlights > 0) parts.add("your $highlights highlight${if (highlights == 1) "" else "s"}")
    if (bookmarks > 0) parts.add("your $bookmarks bookmark${if (bookmarks == 1) "" else "s"}")
    if (parts.isEmpty()) {
        return "Kudos removes this item from your device. You can't undo this."
    }
    val last = parts.removeAt(parts.size - 1)
    val list = if (parts.isEmpty()) last else parts.joinToString(", ") + " and " + last
    return "Kudos removes $list from this device. You can't undo this."
}

private fun containerDeletionMessage(workCount: Int): String {
    val works = when (workCount) {
        0 -> "It holds no works."
        1 -> "The 1 work in it stays in your Library."
        else -> "The $workCount works in it stay in your Library."
    }
    return "$works You can't undo this."
}

private fun bulkDeleteTitle(count: Int): String =
    if (count == 1) "Delete 1 item permanently?" else "Delete $count items permanently?"

private fun restoreFailureText(failed: List<RecentlyDeletedEntry>): String {
    val what = if (failed.size == 1) "the restored ${failed[0].noun}" else "${failed.size} of the restored items"
    val still = if (failed.size == 1) "It is" else "They are"
    return "Kudos could not save $what. $still still scheduled for permanent deletion, so try again."
}
