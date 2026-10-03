package io.github.cidy02.kudos.works

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.StarBorder
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.Tag
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.core.model.WorkDownloadAction
import io.github.cidy02.kudos.core.model.WorkDownloadSemantics
import io.github.cidy02.kudos.core.model.readingProgress
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.AO3URLResolver
import io.github.cidy02.kudos.network.ao3.displayMessage
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.series.AO3SeriesRepository
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadata
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataRepository
import io.github.cidy02.kudos.network.ao3.writes.AO3BookmarkInput
import io.github.cidy02.kudos.network.ao3.writes.AO3PostingPseudOption
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteActionKind
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteOutcome
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.ui.components.DestructiveConfirmation
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.components.StatusBadge
import io.github.cidy02.kudos.ui.components.workCardZoomDestination
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.ToolbarCircleButton
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import io.github.cidy02.kudos.works.detail.WorkDetailAo3ActionChips
import io.github.cidy02.kudos.works.detail.WorkDetailArchiveStatsStrip
import io.github.cidy02.kudos.works.detail.WorkDetailCommentsSection
import io.github.cidy02.kudos.works.detail.WorkDetailFactsCard
import io.github.cidy02.kudos.works.detail.WorkDetailFigureStrip
import io.github.cidy02.kudos.works.detail.WorkDetailIdentityHeader
import io.github.cidy02.kudos.works.detail.WorkDetailMyCopyRow
import io.github.cidy02.kudos.works.detail.WorkDetailMyCopySheet
import io.github.cidy02.kudos.works.detail.WorkDetailPageActions
import io.github.cidy02.kudos.works.detail.WorkDetailResumeCard
import io.github.cidy02.kudos.works.detail.WorkDetailSeriesSection
import io.github.cidy02.kudos.works.detail.WorkDetailSummarySection
import io.github.cidy02.kudos.works.detail.WorkDetailTagSections
import io.github.cidy02.kudos.works.detail.WorkQueueLine
import java.time.Instant
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.launch

@Composable
fun WorkDetailScreen(
    source: WorkDetailSource?,
    workRepository: WorkRepository,
    workImporter: WorkImporter,
    downloadQueue: DownloadQueue,
    writeRepository: AO3WriteRepository,
    readingQueueRepository: ReadingQueueRepository,
    postingPseudStore: io.github.cidy02.kudos.auth.AO3PostingPseudStore? = null,
    metadataRepository: AO3WorkMetadataRepository? = null,
    settingsRepository: SettingsRepository? = null,
    seriesRepository: AO3SeriesRepository = AO3SeriesRepository(),
    onLogin: () -> Unit,
    onOpenComments: (Long) -> Unit,
    onOpenReader: (String) -> Unit,
    onOpenAuthor: (String) -> Unit = {},
    onOpenSeries: (String) -> Unit = {}
) {
    var state by remember(source) { mutableStateOf(WorkDetailUiState()) }
    var newTagName by remember { mutableStateOf("") }
    var confirmRemove by remember { mutableStateOf(false) }
    var showingMyCopy by remember { mutableStateOf(false) }
    var bookmarkDialog by remember { mutableStateOf(false) }
    var bookmarkLoading by remember { mutableStateOf(false) }
    var bookmarkIsEdit by remember { mutableStateOf(false) }
    var bookmarkNotes by remember { mutableStateOf("") }
    var bookmarkTags by remember { mutableStateOf("") }
    var bookmarkCollections by remember { mutableStateOf("") }
    var bookmarkPrivate by remember { mutableStateOf(false) }
    var bookmarkRecommendation by remember { mutableStateOf(false) }
    var bookmarkAvailablePseuds by remember { mutableStateOf<List<AO3PostingPseudOption>>(emptyList()) }
    var bookmarkPseudId by remember { mutableStateOf<String?>(null) }
    var queuePickerOpen by remember { mutableStateOf(false) }
    var createQueueDraft by remember { mutableStateOf<String?>(null) }
    var availableQueues by remember { mutableStateOf<List<ReadingQueue>>(emptyList()) }
    var includeSeriesInQueue by remember { mutableStateOf(false) }
    var checkingSeriesPreview by remember { mutableStateOf(false) }
    var seriesPrompt by remember { mutableStateOf<io.github.cidy02.kudos.library.SeriesPreservationPrompt?>(null) }
    var preservingSeries by remember { mutableStateOf(false) }
    var seriesResult by remember { mutableStateOf<io.github.cidy02.kudos.library.SeriesPreservationResult?>(null) }
    var collectionDialogOpen by remember { mutableStateOf(false) }
    var allCollections by remember { mutableStateOf<List<WorkCollection>>(emptyList()) }
    var collectionMemberIds by remember { mutableStateOf<Set<String>>(emptySet()) }
    var newCollectionName by remember { mutableStateOf("") }
    var collectionDialogWorking by remember { mutableStateOf(false) }
    var chapterIndexSheetOpen by remember { mutableStateOf(false) }
    var canRebuild by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val uriHandler = LocalUriHandler.current
    var downloadWatchJob by remember { mutableStateOf<Job?>(null) }
    val settingsState = settingsRepository?.settings?.collectAsState(initial = KudosSettings.Defaults)
    val settings = settingsState?.value ?: KudosSettings.Defaults

    val downloadingItems by downloadQueue.items.collectAsState(initial = emptyList())
    val isDownloading = remember(downloadingItems, state.ao3WorkId) {
        state.ao3WorkId?.let { id ->
            downloadingItems.any { it.ao3WorkId == id && it.status == DownloadQueueStatus.Downloading }
        } ?: false
    }

    suspend fun refreshLocal(workId: String, remote: AO3WorkSummary? = state.remote) {
        val local = workRepository.getWork(workId)
        canRebuild = local?.let { workImporter.canRebuildFromOriginal(it) } ?: false
        val liveQueues = runCatching {
            readingQueueRepository.listQueues().filter { it.kindRaw != ReadingQueueKind.SAVED_FOR_LATER }
        }.getOrDefault(emptyList())
        val queueLines = liveQueues.mapNotNull { q ->
            val items = readingQueueRepository.listWorks(q.id)
            val idx = items.indexOfFirst { it.membership.workID == workId }
            if (idx >= 0) {
                WorkQueueLine(
                    queueId = q.id,
                    name = q.displayName,
                    position = "#${idx + 1} of ${items.size}"
                )
            } else null
        }.sortedBy { it.name }

        state = state.copy(
            local = local,
            remote = remote,
            userTags = local?.let { workRepository.userTagsForWork(it.id) }.orEmpty(),
            collections = local?.let { workRepository.collectionsForWork(it.id) }.orEmpty(),
            queueMemberships = queueLines,
            inSavedForLater = readingQueueRepository.isInSavedForLater(workId),
            loading = false,
            error = null
        )
    }

    suspend fun hydrateFromAo3WorkId(workId: Long) {
        val canonical = AO3URLResolver.canonicalWorkUrl(workId)
        val existing = WorkIdentityIndex.findExisting(
            candidateSourceUrl = canonical,
            byId = { workRepository.getWork(it) },
            bySourceUrl = { workRepository.findBySourceUrl(it) }
        )
        if (existing != null) {
            refreshLocal(existing.id, remote = null)
            return
        }

        val repo = metadataRepository
        if (repo == null) {
            state = WorkDetailUiState(
                loading = false,
                error = "Couldn't open AO3 work #$workId. Open it from Search, Browse, or Library " +
                    "instead, or open it on AO3 from a listing that includes full blurb metadata."
            )
            return
        }

        when (val result = repo.fetch(workId)) {
            is AO3Result.Success -> {
                val remote = result.value.toRemoteSummary(workId)
                state = WorkDetailUiState(
                    remote = remote,
                    loading = false,
                    ao3Message = "Loaded tags and stats from AO3. Title and summary need a full work page parse."
                )
            }
            is AO3Result.Failure -> {
                state = WorkDetailUiState(
                    loading = false,
                    error = "Couldn't load AO3 work #$workId: ${result.error.displayMessage()} " +
                        "Open it from Search, Browse, or Library when possible."
                )
            }
        }
    }

    LaunchedEffect(source) {
        state = WorkDetailUiState(loading = true)
        when (source) {
            is WorkDetailSource.LocalWork -> refreshLocal(source.workId, remote = null)
            is WorkDetailSource.RemoteSummary -> {
                val existing = workRepository.findBySourceUrl(source.summary.workUrl)
                if (existing != null) {
                    refreshLocal(existing.id, remote = source.summary)
                } else {
                    state = WorkDetailUiState(remote = source.summary, loading = false)
                }
            }
            is WorkDetailSource.Ao3WorkId -> hydrateFromAo3WorkId(source.workId)
            is WorkDetailSource.RemoteUrl -> {
                val workId = WorkTags.ao3WorkIdFromUrl(source.url)
                if (workId != null) {
                    hydrateFromAo3WorkId(workId)
                } else {
                    state = WorkDetailUiState(
                        loading = false,
                        error = "This AO3 link isn't a work URL Kudos can open yet. " +
                            "Try opening the work from Search, Browse, or Library."
                    )
                }
            }
            null -> state = WorkDetailUiState(
                loading = false,
                error = "Open a work from Search or Library."
            )
        }
    }

    // Prefetch live Subscribe/Unsubscribe and Bookmark states so the actions match AO3.
    LaunchedEffect(state.ao3WorkId, state.loading) {
        val workId = state.ao3WorkId
        if (state.loading || workId == null) return@LaunchedEffect
        when (val result = writeRepository.fetchSubscriptionState(workId)) {
            is AO3Result.Success -> {
                if (state.isSubscribed == null && state.ao3WorkId == workId) {
                    state = state.copy(isSubscribed = result.value.isSubscribed)
                }
            }
            is AO3Result.Failure -> Unit
        }
        when (val bResult = writeRepository.fetchBookmarkState(workId)) {
            is AO3Result.Success -> {
                if (state.ao3WorkId == workId) {
                    bookmarkIsEdit = bResult.value.exists
                }
            }
            is AO3Result.Failure -> Unit
        }
    }

    fun runWorkAction(block: suspend () -> Unit) {
        scope.launch {
            state = state.copy(working = true, error = null, ao3Message = null)
            block()
            state = state.copy(working = false)
        }
    }

    fun download() {
        val remote = state.remote
        val local = state.local
        val ao3Id = remote?.id
            ?: local?.let { WorkTags.ao3WorkIdFromUrl(it.sourceUrl) }
            ?: state.ao3WorkId
        if (ao3Id == null) {
            state = state.copy(error = "No work selected.")
            return
        }

        val force = local?.hasEpub == true
        if (remote != null) {
            downloadQueue.enqueue(remote, force = force)
        } else if (local != null) {
            downloadQueue.enqueueLocal(
                ao3WorkId = ao3Id,
                title = local.title,
                sourceUrl = local.sourceUrl,
                force = force
            )
        } else {
            state = state.copy(error = "No work selected.")
            return
        }

        state = state.copy(
            error = null,
            ao3Message = if (force) "Queued redownload." else "Queued for download."
        )

        downloadWatchJob?.cancel()
        downloadWatchJob = scope.launch {
            val terminal = downloadQueue.items
                .mapNotNull { list -> list.firstOrNull { it.ao3WorkId == ao3Id } }
                .first {
                    it.status == DownloadQueueStatus.Done ||
                        it.status == DownloadQueueStatus.Skipped ||
                        it.status == DownloadQueueStatus.Failed
                }
            when (terminal.status) {
                DownloadQueueStatus.Done,
                DownloadQueueStatus.Skipped -> {
                    val sourceUrl = remote?.workUrl ?: local?.sourceUrl
                    val refreshed = if (sourceUrl != null) {
                        WorkIdentityIndex.findExisting(
                            candidateSourceUrl = sourceUrl,
                            byId = { workRepository.getWork(it) },
                            bySourceUrl = { workRepository.findBySourceUrl(it) }
                        )
                    } else null
                    if (refreshed != null) {
                        refreshLocal(refreshed.id, remote)
                    } else if (terminal.status == DownloadQueueStatus.Skipped) {
                        state = state.copy(ao3Message = "Already downloaded.")
                    }
                }
                DownloadQueueStatus.Failed -> {
                    state = state.copy(
                        ao3Message = null,
                        error = "Download failed for \"${terminal.title}\"."
                    )
                }
                DownloadQueueStatus.Queued,
                DownloadQueueStatus.Downloading -> Unit
            }
        }
    }

    fun downloadSeries() {
        val seriesUrl = state.seriesUrl
        if (seriesUrl.isBlank()) {
            state = state.copy(error = "No series URL for this work.")
            return
        }
        scope.launch {
            state = state.copy(queuingSeries = true, error = null, ao3Message = null)
            when (val result = downloadQueue.enqueueSeries(seriesUrl)) {
                is AO3Result.Failure -> {
                    state = state.copy(
                        queuingSeries = false,
                        error = "Couldn't load the series from AO3: ${result.error.displayMessage()}"
                    )
                }
                is AO3Result.Success -> {
                    val count = result.value
                    state = state.copy(
                        queuingSeries = false,
                        ao3Message = if (count == 0) {
                            "No works found on that series page."
                        } else {
                            "Queued $count series work${if (count == 1) "" else "s"} for download."
                        }
                    )
                }
            }
        }
    }

    fun ensureLocalThen(queueOnly: Boolean = false, action: suspend (SavedWork) -> Unit) {
        val local = state.local
        if (local != null) {
            if (queueOnly && !local.isQueuedForLater) {
                runWorkAction {
                    val updated = local.copy(isQueuedForLater = true, lastModifiedAt = Instant.now())
                    action(workRepository.upsert(updated))
                }
            } else {
                runWorkAction { action(local) }
            }
            return
        }
        val remote = state.remote ?: return
        runWorkAction {
            when (
                val result = workImporter.saveMetadataOnly(
                    remote,
                    markSaved = !queueOnly,
                    isQueuedForLater = queueOnly
                )
            ) {
                is WorkImportResult.Failure -> state = state.copy(error = result.error.displayMessage())
                is WorkImportResult.Success -> action(result.work)
            }
        }
    }

    fun preserveEpubForQueue(work: SavedWork) {
        if (work.hasEpub) return
        val ao3Id = WorkTags.ao3WorkIdFromUrl(work.sourceUrl) ?: return
        downloadQueue.enqueueLocal(
            ao3WorkId = ao3Id,
            title = work.title,
            sourceUrl = work.sourceUrl,
            force = false
        )
    }

    fun handleWriteResult(result: AO3Result<AO3WriteOutcome>) {
        state = when (result) {
            is AO3Result.Success -> {
                val subscribedAfter = when (result.value.kind) {
                    AO3WriteActionKind.Subscribe -> true
                    AO3WriteActionKind.Unsubscribe -> false
                    else -> state.isSubscribed
                }
                state.copy(
                    ao3Message = result.value.message,
                    isSubscribed = subscribedAfter
                )
            }
            is AO3Result.Failure -> state.copy(error = result.error.displayMessage())
        }
    }

    fun runAo3Write(action: suspend (Long) -> AO3Result<AO3WriteOutcome>) {
        val workId = state.ao3WorkId ?: run {
            state = state.copy(error = "This action needs a canonical AO3 work URL.")
            return
        }
        runWorkAction {
            handleWriteResult(action(workId))
        }
    }

    fun toggleSaved() {
        val local = state.local
        if (local != null) {
            runWorkAction {
                if (local.isDeleted) {
                    workRepository.restoreFromRecentlyDeleted(local.id)
                }
                val active = workRepository.getWork(local.id) ?: local
                when (
                    WorkDownloadSemantics.action(
                        active.hasEpub,
                        active.isDownloaded,
                        active.hasAo3WorkId,
                        active.keptOfflineBy
                    )
                ) {
                    WorkDownloadAction.RemoveDownload -> {
                        workRepository.setSaved(active.id, false)?.let {
                            refreshLocal(it.id, state.remote)
                        }
                    }
                    WorkDownloadAction.Download -> {
                        val kept = workRepository.setSaved(active.id, true) ?: active
                        refreshLocal(kept.id, state.remote)
                        if (!kept.hasEpub) download()
                    }
                    is WorkDownloadAction.KeptBy, null -> Unit
                }
            }
            return
        }
        download()
    }

    DestructiveConfirmation(
        show = confirmRemove,
        title = "Remove from Library",
        text = "This moves the work to Recently Deleted for 90 days. You can restore it from Library → Recently Deleted. After 90 days it is permanently removed (including any downloaded EPUB).",
        confirmText = "Remove",
        confirmBeforeDelete = settings.app.confirmBeforeDelete,
        onConfirm = {
            val workId = state.local?.id ?: return@DestructiveConfirmation
            confirmRemove = false
            runWorkAction {
                workRepository.softDelete(workId)
                state = WorkDetailUiState(remote = state.remote, loading = false)
            }
        },
        onDismissRequest = { confirmRemove = false }
    )

    if (bookmarkDialog) {
        AlertDialog(
            onDismissRequest = { if (!bookmarkLoading) bookmarkDialog = false },
            title = { Text(if (bookmarkIsEdit) "Edit Bookmark" else "AO3 Bookmark") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (bookmarkLoading) {
                        Text(
                            text = "Loading bookmark…",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    OutlinedTextField(
                        value = bookmarkNotes,
                        onValueChange = { bookmarkNotes = it },
                        label = { Text("Notes") },
                        minLines = 3,
                        enabled = !bookmarkLoading
                    )
                    OutlinedTextField(
                        value = bookmarkTags,
                        onValueChange = { bookmarkTags = it },
                        label = { Text("Tags, comma-separated") },
                        singleLine = true,
                        enabled = !bookmarkLoading
                    )
                    if (bookmarkCollections.isNotBlank()) {
                        Text(
                            text = "AO3 collections: $bookmarkCollections",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }

                    if (bookmarkAvailablePseuds.size > 1) {
                        var pseudExpanded by remember { mutableStateOf(false) }
                        val currentPseud = bookmarkAvailablePseuds.find { it.id == bookmarkPseudId }
                        Box {
                            OutlinedButton(
                                onClick = { pseudExpanded = true },
                                enabled = !bookmarkLoading,
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text("Posting as: ${currentPseud?.name ?: "Default"}")
                            }
                            DropdownMenu(
                                expanded = pseudExpanded,
                                onDismissRequest = { pseudExpanded = false }
                            ) {
                                bookmarkAvailablePseuds.forEach { option ->
                                    DropdownMenuItem(
                                        text = { Text(option.name) },
                                        onClick = {
                                            bookmarkPseudId = option.id
                                            pseudExpanded = false
                                        }
                                    )
                                }
                            }
                        }
                    }

                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Checkbox(
                            checked = bookmarkPrivate,
                            onCheckedChange = { bookmarkPrivate = it },
                            enabled = !bookmarkLoading
                        )
                        Text("Private")
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Checkbox(
                            checked = bookmarkRecommendation,
                            onCheckedChange = { bookmarkRecommendation = it },
                            enabled = !bookmarkLoading
                        )
                        Text("Recommendation")
                    }
                }
            },
            confirmButton = {
                TextButton(
                    enabled = !bookmarkLoading,
                    onClick = {
                        bookmarkDialog = false
                        val input = AO3BookmarkInput(
                            notes = bookmarkNotes,
                            tags = bookmarkTags,
                            isPrivate = bookmarkPrivate,
                            isRecommendation = bookmarkRecommendation,
                            pseudId = bookmarkPseudId
                        )
                        runAo3Write { writeRepository.createBookmark(it, input, postingPseudStore) }
                    }
                ) {
                    Text(if (bookmarkIsEdit) "Save" else "Create")
                }
            },
            dismissButton = {
                TextButton(
                    enabled = !bookmarkLoading,
                    onClick = { bookmarkDialog = false }
                ) { Text("Cancel") }
            }
        )
    }

    if (queuePickerOpen) {
        if (createQueueDraft != null) {
            AlertDialog(
                onDismissRequest = { createQueueDraft = null },
                title = { Text("New Queue") },
                text = {
                    OutlinedTextField(
                        value = createQueueDraft!!,
                        onValueChange = { createQueueDraft = it },
                        label = { Text("Queue name") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                },
                confirmButton = {
                    TextButton(
                        enabled = createQueueDraft!!.trim().isNotEmpty() && !state.working,
                        onClick = {
                            val name = createQueueDraft!!.trim()
                            createQueueDraft = null
                            runWorkAction {
                                readingQueueRepository.createQueue(name)
                                availableQueues = readingQueueRepository.listQueues()
                                    .filter { it.kindRaw != ReadingQueueKind.SAVED_FOR_LATER }
                            }
                        }
                    ) { Text("Create") }
                },
                dismissButton = {
                    TextButton(onClick = { createQueueDraft = null }) { Text("Cancel") }
                }
            )
        }

        AlertDialog(
            onDismissRequest = { queuePickerOpen = false },
            title = { Text("Add to Queue") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    TextButton(
                        onClick = { createQueueDraft = "" },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(Icons.Default.Add, contentDescription = null)
                        Spacer(Modifier.size(8.dp))
                        Text("Create New Queue", modifier = Modifier.weight(1f))
                    }
                    HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))

                    if (state.seriesUrl.isNotBlank()) {
                        HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { includeSeriesInQueue = !includeSeriesInQueue }
                                .padding(vertical = 8.dp)
                        ) {
                            Text("Also add works from this AO3 series", modifier = Modifier.weight(1f))
                            Switch(
                                checked = includeSeriesInQueue,
                                onCheckedChange = { includeSeriesInQueue = it }
                            )
                        }
                        if (includeSeriesInQueue) {
                            if (checkingSeriesPreview) {
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                                    Text("Checking series size…", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            } else if (seriesPrompt != null) {
                                Text(seriesPrompt!!.message, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                OutlinedButton(
                                    onClick = {
                                        if (preservingSeries) return@OutlinedButton
                                        preservingSeries = true
                                        seriesResult = null
                                        scope.launch {
                                            seriesResult = readingQueueRepository.preserveSeries(
                                                seriesUrl = state.seriesUrl,
                                                targetQueues = availableQueues,
                                                seriesRepository = seriesRepository,
                                                workImporter = workImporter,
                                                enqueueDownload = { s -> downloadQueue.enqueue(s, force = false) }
                                            )
                                            preservingSeries = false
                                        }
                                    },
                                    enabled = !preservingSeries && availableQueues.isNotEmpty(),
                                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp)
                                ) {
                                    if (preservingSeries) {
                                        CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                                        Spacer(Modifier.size(8.dp))
                                    }
                                    Text("Add Series to Selected Queues")
                                }
                                if (seriesResult != null) {
                                    val parts = seriesResult!!.summaryParts("added")
                                    val text = if (parts.isEmpty()) "Done." else parts.joinToString(", ")
                                    Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }
                    }

                    if (availableQueues.isEmpty()) {
                        Text(
                            text = "No reading queues yet. Create one from Library → Reading Queues.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    } else {
                        availableQueues.forEach { queue ->
                            TextButton(
                                onClick = {
                                    queuePickerOpen = false
                                    ensureLocalThen(queueOnly = true) { work ->
                                        readingQueueRepository.addWork(queue.id, work.id)
                                        preserveEpubForQueue(work)
                                        state = state.copy(
                                            ao3Message = "Added to ${queue.displayName}."
                                        )
                                        refreshLocal(work.id, state.remote)
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
            confirmButton = {
                TextButton(onClick = { queuePickerOpen = false }) { Text("Close") }
            }
        )
    }

    LaunchedEffect(includeSeriesInQueue) {
        if (includeSeriesInQueue && state.seriesUrl.isNotBlank()) {
            checkingSeriesPreview = true
            try {
                val page = when (val result = seriesRepository.seriesPage(state.seriesUrl)) {
                    is AO3Result.Success -> result.value
                    is AO3Result.Failure -> null
                }
                seriesPrompt = io.github.cidy02.kudos.library.SeriesPreservationPrompt(preview = page, threshold = 5, previewFailed = page == null)
            } catch (_: Exception) {
                seriesPrompt = io.github.cidy02.kudos.library.SeriesPreservationPrompt(preview = null, threshold = 5, previewFailed = true)
            }
            checkingSeriesPreview = false
        } else {
            seriesPrompt = null
            seriesResult = null
        }
    }

    LaunchedEffect(collectionDialogOpen) {
        if (!collectionDialogOpen) return@LaunchedEffect
        newCollectionName = ""
        collectionDialogWorking = false
        try {
            allCollections = workRepository.allCollections().sortedBy { it.name.lowercase() }
            val localId = state.local?.id
            collectionMemberIds = if (localId != null) {
                workRepository.collectionsForWork(localId).map { it.id }.toSet()
            } else {
                state.collections.map { it.id }.toSet()
            }
        } catch (_: Exception) {
            allCollections = emptyList()
            collectionMemberIds = state.collections.map { it.id }.toSet()
        }
    }

    if (collectionDialogOpen) {
        AlertDialog(
            onDismissRequest = {
                if (!collectionDialogWorking) {
                    collectionDialogOpen = false
                    val localId = state.local?.id
                    if (localId != null) {
                        scope.launch {
                            state = state.copy(
                                collections = workRepository.collectionsForWork(localId)
                            )
                        }
                    }
                }
            },
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
                            value = newCollectionName,
                            onValueChange = { newCollectionName = it },
                            label = { Text("New collection") },
                            singleLine = true,
                            enabled = !collectionDialogWorking && !state.working,
                            modifier = Modifier.weight(1f)
                        )
                        TextButton(
                            enabled = newCollectionName.trim().isNotEmpty() &&
                                !collectionDialogWorking &&
                                !state.working,
                            onClick = {
                                val name = newCollectionName.trim()
                                if (name.isEmpty()) return@TextButton
                                ensureLocalThen { work ->
                                    collectionDialogWorking = true
                                    try {
                                        val collections = workRepository.addToCollection(work.id, name)
                                        newCollectionName = ""
                                        collectionMemberIds = collections.map { it.id }.toSet()
                                        allCollections = workRepository.allCollections().sortedBy { it.name.lowercase() }
                                        state = state.copy(
                                            local = workRepository.getWork(work.id),
                                            collections = collections,
                                            ao3Message = "Added to collection."
                                        )
                                    } finally {
                                        collectionDialogWorking = false
                                    }
                                }
                            }
                        ) {
                            Text("Add")
                        }
                    }

                    if (allCollections.isEmpty()) {
                        Text(
                            text = "No collections yet. Create one above to start grouping works.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    } else {
                        Text(
                            text = "Collections",
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        allCollections.forEach { collection ->
                            val isMember = collection.id in collectionMemberIds
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable(enabled = !collectionDialogWorking && !state.working) {
                                        ensureLocalThen { work ->
                                            collectionDialogWorking = true
                                            try {
                                                val collections = if (isMember) {
                                                    workRepository.removeFromCollection(work.id, collection.id)
                                                } else {
                                                    workRepository.addWorkToCollection(work.id, collection.id)
                                                }
                                                collectionMemberIds = collections.map { it.id }.toSet()
                                                allCollections = workRepository.allCollections().sortedBy { it.name.lowercase() }
                                                state = state.copy(
                                                    local = workRepository.getWork(work.id),
                                                    collections = collections
                                                )
                                            } finally {
                                                collectionDialogWorking = false
                                            }
                                        }
                                    }
                                    .padding(vertical = 2.dp),
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Checkbox(
                                    checked = isMember,
                                    onCheckedChange = null,
                                    enabled = !collectionDialogWorking && !state.working
                                )
                                Text(
                                    text = collection.name,
                                    style = MaterialTheme.typography.bodyLarge,
                                    modifier = Modifier.weight(1f)
                                )
                                Text(
                                    text = when (val count = collection.workIds.size) {
                                        0 -> "0"
                                        else -> count.toString()
                                    },
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(
                    enabled = !collectionDialogWorking,
                    onClick = {
                        collectionDialogOpen = false
                        val localId = state.local?.id
                        if (localId != null) {
                            scope.launch {
                                state = state.copy(
                                    collections = workRepository.collectionsForWork(localId)
                                )
                            }
                        }
                    }
                ) {
                    Text("Done")
                }
            }
        )
    }

    @OptIn(ExperimentalMaterial3Api::class)
    if (chapterIndexSheetOpen) {
        ModalBottomSheet(
            onDismissRequest = { chapterIndexSheetOpen = false }
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(24.dp)
                    .navigationBarsPadding(),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Text("Chapter Index", style = MaterialTheme.typography.titleLarge)
                if (state.ao3WorkId != null) {
                    val navigateUrl = "https://archiveofourown.org/works/${state.ao3WorkId}/navigate"
                    Button(onClick = {
                        chapterIndexSheetOpen = false
                        uriHandler.openUri(navigateUrl)
                    }, modifier = Modifier.fillMaxWidth()) {
                        Text("Open Chapter Index on AO3")
                    }
                } else {
                    Text("Chapter Index is not available for local-only works.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Spacer(modifier = Modifier.height(32.dp))
            }
        }
    }

    if (showingMyCopy) {
        val tokens = LocalKudosTokens.current
        val workHue = remember(state.fandoms, state.title) {
            HomeFacts.workHue(state.fandoms, state.title)
        }
        val palette = remember(workHue, tokens.theme) {
            SubjectPalette.fromHue(workHue, tokens.theme)
        }

        WorkDetailMyCopySheet(
            work = state.local,
            remote = state.remote,
            userTags = state.userTags,
            collections = state.collections,
            queueMemberships = state.queueMemberships,
            inSavedForLater = state.inSavedForLater,
            isWorking = state.working || state.queuingSeries,
            canRebuildFromOriginal = canRebuild,
            palette = palette,
            newTagName = newTagName,
            onNewTagName = { newTagName = it },
            onAddTag = {
                ensureLocalThen { work ->
                    if (newTagName.isNotBlank()) {
                        val tags = workRepository.addUserTag(work.id, newTagName)
                        newTagName = ""
                        state = state.copy(local = workRepository.getWork(work.id), userTags = tags)
                    }
                }
            },
            onRemoveTag = { tag ->
                val work = state.local ?: return@WorkDetailMyCopySheet
                runWorkAction {
                    val tags = workRepository.removeUserTag(work.id, tag.id)
                    state = state.copy(userTags = tags)
                }
            },
            onSuggestTag = { suggestion ->
                ensureLocalThen { work ->
                    val tags = workRepository.addUserTag(work.id, suggestion)
                    state = state.copy(local = workRepository.getWork(work.id), userTags = tags)
                }
            },
            onToggleSaved = ::toggleSaved,
            onToggleSavedForLater = {
                ensureLocalThen(queueOnly = true) { work ->
                    if (state.inSavedForLater) {
                        readingQueueRepository.removeFromSavedForLater(work.id)
                        val stillThere = workRepository.getWork(work.id)
                        if (stillThere == null || stillThere.isDeleted) {
                            state = state.copy(
                                local = null,
                                inSavedForLater = false,
                                loading = false,
                                ao3Message = "Removed from Saved for Later."
                            )
                        } else {
                            refreshLocal(stillThere.id, state.remote)
                            state = state.copy(ao3Message = "Removed from Saved for Later.")
                        }
                    } else {
                        readingQueueRepository.addToSavedForLater(work.id)
                        preserveEpubForQueue(work)
                        refreshLocal(work.id, state.remote)
                    }
                }
            },
            onToggleFinished = {
                ensureLocalThen { work ->
                    val updated = workRepository.toggleFinished(work.id)
                    if (updated != null) refreshLocal(updated.id, state.remote)
                }
            },
            onAddToQueue = {
                queuePickerOpen = true
                scope.launch {
                    availableQueues = readingQueueRepository.listQueues()
                        .filter { it.kindRaw != ReadingQueueKind.SAVED_FOR_LATER }
                }
            },
            onAddToCollection = { collectionDialogOpen = true },
            onRebuildFromOriginal = {
                val work = state.local
                if (work != null) {
                    scope.launch {
                        state = state.copy(working = true)
                        workImporter.rebuildFromOriginal(work)
                        refreshLocal(work.id, state.remote)
                        state = state.copy(working = false)
                    }
                }
            },
            onDismiss = { showingMyCopy = false }
        )
    }

    WorkDetailContent(
        state = state,
        isDownloading = isDownloading,
        isBookmarked = bookmarkIsEdit,
        onToggleFavorite = {
            ensureLocalThen { work ->
                val updated = workRepository.toggleFavorite(work.id)
                if (updated != null) refreshLocal(updated.id, state.remote)
            }
        },
        onToggleSaved = ::toggleSaved,
        onToggleFinished = {
            ensureLocalThen { work ->
                val updated = workRepository.toggleFinished(work.id)
                if (updated != null) refreshLocal(updated.id, state.remote)
            }
        },
        onDownload = ::download,
        onDownloadSeries = ::downloadSeries,
        onDeleteEpub = {
            val work = state.local ?: return@WorkDetailContent
            runWorkAction {
                val updated = workRepository.deleteLocalEpub(work.id)
                if (updated != null) refreshLocal(updated.id, state.remote)
            }
        },
        onRemoveFromLibrary = { confirmRemove = true },
        onOpenAo3 = {
            state.sourceUrl.takeIf { it.isNotBlank() }?.let(uriHandler::openUri)
        },
        onLogin = onLogin,
        onRebuildFromOriginal = {
            val work = state.local
            if (work != null) {
                scope.launch {
                    state = state.copy(working = true)
                    workImporter.rebuildFromOriginal(work)
                    refreshLocal(work.id, state.remote)
                    state = state.copy(working = false)
                }
            }
        },
        canRebuildFromOriginal = canRebuild,
        onRefreshMetadata = {
            val work = state.local
            val repo = metadataRepository
            if (work != null && repo != null) {
                scope.launch {
                    state = state.copy(working = true)
                    WorkMetadataRefresh(workRepository, repo).refresh(work)
                    refreshLocal(work.id, state.remote)
                    state = state.copy(working = false)
                }
            }
        },
        onKudos = {
            val ao3Id = state.ao3WorkId ?: return@WorkDetailContent
            runWorkAction {
                val result = writeRepository.giveKudos(ao3Id)
                handleWriteResult(result)
                if (result is AO3Result.Success) {
                    val local = state.local
                    if (local != null) {
                        val updated = workRepository.upsert(
                            local.copy(hasGivenKudos = true, lastModifiedAt = Instant.now())
                        )
                        refreshLocal(updated.id, state.remote)
                    }
                }
            }
        },
        onSubscribe = { runAo3Write { writeRepository.toggleSubscribe(it) } },
        onMarkForLater = { runAo3Write { writeRepository.markForLater(it) } },
        onAddToSavedForLater = {
            ensureLocalThen(queueOnly = true) { work ->
                if (state.inSavedForLater) {
                    readingQueueRepository.removeFromSavedForLater(work.id)
                    val stillThere = workRepository.getWork(work.id)
                    if (stillThere == null || stillThere.isDeleted) {
                        state = state.copy(
                            local = null,
                            inSavedForLater = false,
                            loading = false,
                            ao3Message = "Removed from Saved for Later."
                        )
                    } else {
                        refreshLocal(stillThere.id, state.remote)
                        state = state.copy(ao3Message = "Removed from Saved for Later.")
                    }
                } else {
                    readingQueueRepository.addToSavedForLater(work.id)
                    preserveEpubForQueue(work)
                    refreshLocal(work.id, state.remote)
                }
            }
        },
        onAddToQueue = {
            queuePickerOpen = true
            scope.launch {
                availableQueues = readingQueueRepository.listQueues()
                    .filter { it.kindRaw != ReadingQueueKind.SAVED_FOR_LATER }
            }
        },
        onAddToCollection = { collectionDialogOpen = true },
        onBookmark = {
            val workId = state.ao3WorkId
            if (workId == null) {
                state = state.copy(error = "This action needs a canonical AO3 work URL.")
                return@WorkDetailContent
            }
            bookmarkNotes = ""
            bookmarkTags = ""
            bookmarkCollections = ""
            bookmarkPrivate = false
            bookmarkRecommendation = false
            bookmarkPseudId = null
            bookmarkAvailablePseuds = emptyList()
            bookmarkIsEdit = false
            bookmarkLoading = true
            bookmarkDialog = true
            scope.launch {
                when (val result = writeRepository.fetchBookmarkState(workId)) {
                    is AO3Result.Success -> {
                        val bookmarkState = result.value
                        bookmarkIsEdit = bookmarkState.exists
                        bookmarkNotes = bookmarkState.input.notes
                        bookmarkTags = bookmarkState.input.tags
                        bookmarkCollections = bookmarkState.collectionNames
                        bookmarkPrivate = bookmarkState.input.isPrivate
                        bookmarkRecommendation = bookmarkState.input.isRecommendation
                        bookmarkAvailablePseuds = bookmarkState.availablePseuds
                        bookmarkPseudId = bookmarkState.input.pseudId
                    }
                    is AO3Result.Failure -> {
                        if (result.error is AO3Error.AuthenticationRequired) {
                            state = state.copy(error = result.error.displayMessage())
                        }
                    }
                }
                bookmarkLoading = false
            }
        },
        onComments = {
            state.ao3WorkId?.let(onOpenComments)
                ?: run { state = state.copy(error = "This action needs a canonical AO3 work URL.") }
        },
        onResumeClick = {
            val epubWorkId = state.local?.takeIf { it.hasEpub }?.id
            if (epubWorkId != null) {
                onOpenReader(epubWorkId)
            } else {
                download()
            }
        },
        onOpenAuthor = onOpenAuthor,
        onOpenSeries = onOpenSeries,
        onOpenMyCopy = { showingMyCopy = true }
    )
}

@Composable
private fun WorkDetailContent(
    state: WorkDetailUiState,
    isDownloading: Boolean,
    isBookmarked: Boolean,
    onToggleFavorite: () -> Unit,
    onToggleSaved: () -> Unit,
    onToggleFinished: () -> Unit,
    onDownload: () -> Unit,
    onDownloadSeries: () -> Unit,
    onDeleteEpub: () -> Unit,
    onRemoveFromLibrary: () -> Unit,
    onOpenAo3: () -> Unit,
    onLogin: () -> Unit,
    onRebuildFromOriginal: () -> Unit,
    canRebuildFromOriginal: Boolean,
    onRefreshMetadata: () -> Unit,
    onKudos: () -> Unit,
    onSubscribe: () -> Unit,
    onMarkForLater: () -> Unit,
    onAddToSavedForLater: () -> Unit,
    onAddToQueue: () -> Unit,
    onAddToCollection: () -> Unit,
    onBookmark: () -> Unit,
    onComments: () -> Unit,
    onResumeClick: () -> Unit,
    onOpenAuthor: (String) -> Unit,
    onOpenSeries: (String) -> Unit,
    onOpenMyCopy: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    val context = LocalContext.current
    val workHue = remember(state.fandoms, state.title) {
        HomeFacts.workHue(state.fandoms, state.title)
    }
    val palette = remember(workHue, tokens.theme) {
        SubjectPalette.fromHue(workHue, tokens.theme)
    }

    val busy = state.working || state.queuingSeries
    val local = state.local
    val isFavorite = local?.isFavorite == true
    var menuExpanded by remember { mutableStateOf(false) }

    ProvidePushedShellChrome(
        hasSubjectHeader = true,
        trailingContent = {
            ToolbarCircleButton(
                onClick = onToggleFavorite,
                accessibilityName = if (isFavorite) "Unfavorite" else "Favorite",
                palette = palette
            ) {
                Icon(
                    imageVector = if (isFavorite) Icons.Filled.Star else Icons.Outlined.StarBorder,
                    contentDescription = null,
                    tint = if (isFavorite) Color(0xFFFFCC00) else tokens.secondaryInk, // iOS: .yellow
                    modifier = Modifier.size(18.dp)
                )
            }

            Box {
                ToolbarCircleButton(
                    onClick = { menuExpanded = true },
                    accessibilityName = "More actions",
                    palette = palette
                ) {
                    Icon(
                        imageVector = Icons.Filled.MoreVert,
                        contentDescription = null,
                        tint = tokens.secondaryInk,
                        modifier = Modifier.size(18.dp)
                    )
                }

                DropdownMenu(
                    expanded = menuExpanded,
                    onDismissRequest = { menuExpanded = false }
                ) {
                    DropdownMenuItem(
                        text = { Text("Add to Queue") },
                        enabled = !busy,
                        onClick = {
                            menuExpanded = false
                            onAddToQueue()
                        }
                    )
                    DropdownMenuItem(
                        text = { Text("Add to Collection") },
                        enabled = !busy,
                        onClick = {
                            menuExpanded = false
                            onAddToCollection()
                        }
                    )
                    DropdownMenuItem(
                        text = {
                            Text(if (state.inSavedForLater) "Remove from Later" else "Save for Later")
                        },
                        enabled = !busy,
                        onClick = {
                            menuExpanded = false
                            onAddToSavedForLater()
                        }
                    )

                    val downloadAction = local?.let {
                        WorkDownloadSemantics.action(
                            it.hasEpub,
                            it.isDownloaded,
                            it.hasAo3WorkId,
                            it.keptOfflineBy
                        )
                    } ?: state.remote?.let { WorkDownloadAction.Download }

                    val downloadLabel = downloadActionLabel(downloadAction, local?.isDownloaded == true)
                    DropdownMenuItem(
                        text = { Text(downloadLabel) },
                        enabled = !busy && downloadAction !is WorkDownloadAction.KeptBy,
                        onClick = {
                            menuExpanded = false
                            onToggleSaved()
                        }
                    )

                    if (state.sourceUrl.isNotBlank()) {
                        HorizontalDivider()
                        DropdownMenuItem(
                            text = { Text("Share") },
                            onClick = {
                                menuExpanded = false
                                shareWork(context, state.title, state.sourceUrl)
                            }
                        )
                        DropdownMenuItem(
                            text = { Text("Open on AO3") },
                            onClick = {
                                menuExpanded = false
                                onOpenAo3()
                            }
                        )
                    }

                    if (state.ao3WorkId != null) {
                        HorizontalDivider()
                        DropdownMenuItem(
                            text = { Text("Give Kudos") },
                            enabled = !busy,
                            onClick = {
                                menuExpanded = false
                                onKudos()
                            }
                        )
                        DropdownMenuItem(
                            text = { Text("Comments") },
                            onClick = {
                                menuExpanded = false
                                onComments()
                            }
                        )
                        DropdownMenuItem(
                            text = { Text(if (isBookmarked) "Edit Bookmark on AO3" else "Bookmark on AO3") },
                            enabled = !busy,
                            onClick = {
                                menuExpanded = false
                                onBookmark()
                            }
                        )
                        DropdownMenuItem(
                            text = { Text("Mark for Later (AO3)") },
                            enabled = !busy,
                            onClick = {
                                menuExpanded = false
                                onMarkForLater()
                            }
                        )
                        DropdownMenuItem(
                            text = {
                                Text(if (state.isSubscribed == true) "Unsubscribe" else "Subscribe")
                            },
                            enabled = !busy,
                            onClick = {
                                menuExpanded = false
                                onSubscribe()
                            }
                        )
                    }

                    if (canRebuildFromOriginal) {
                        HorizontalDivider()
                        DropdownMenuItem(
                            text = { Text("Rebuild from Original") },
                            enabled = !busy,
                            onClick = {
                                menuExpanded = false
                                onRebuildFromOriginal()
                            }
                        )
                    }

                    if (local != null && state.ao3WorkId != null) {
                        DropdownMenuItem(
                            text = { Text("Refresh Metadata") },
                            enabled = !busy,
                            onClick = {
                                menuExpanded = false
                                onRefreshMetadata()
                            }
                        )
                    }

                    DropdownMenuItem(
                        text = { Text("Log in to AO3") },
                        onClick = {
                            menuExpanded = false
                            onLogin()
                        }
                    )

                    if (local?.hasEpub == true && state.ao3WorkId != null) {
                        DropdownMenuItem(
                            text = { Text("Redownload EPUB") },
                            enabled = !busy,
                            onClick = {
                                menuExpanded = false
                                onDownload()
                            }
                        )
                    }

                    if (state.seriesUrl.isNotBlank()) {
                        DropdownMenuItem(
                            text = {
                                Text(if (state.queuingSeries) "Fetching series…" else "Download series")
                            },
                            enabled = !busy,
                            onClick = {
                                menuExpanded = false
                                onDownloadSeries()
                            }
                        )
                    }

                    if (local?.hasEpub == true) {
                        DropdownMenuItem(
                            text = { Text("Delete EPUB") },
                            enabled = !busy,
                            onClick = {
                                menuExpanded = false
                                onDeleteEpub()
                            }
                        )
                    }

                    if (local != null) {
                        HorizontalDivider()
                        DropdownMenuItem(
                            text = { Text("Remove from Library") },
                            enabled = !busy,
                            onClick = {
                                menuExpanded = false
                                onRemoveFromLibrary()
                            }
                        )
                    }
                }
            }
        }
    )

    if (state.loading) {
        LoadingStateCard("Loading work details")
        return
    }

    KudosRefreshBox(
        onRefresh = {
            if (state.ao3WorkId != null) {
                onRefreshMetadata()
            }
        },
        modifier = Modifier.fillMaxSize()
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .subjectScreenWash(palette, washHeight = 620.dp)
                .verticalScroll(rememberScrollState())
                .let { if (state.ao3WorkId != null) it.workCardZoomDestination(state.ao3WorkId) else it }
        ) {
            Spacer(Modifier.height(WindowInsets.systemBars.asPaddingValues().calculateTopPadding() + 56.dp))

            // 1. Identity Header: Kicker (fandom), 32sp title, tappable author byline
            WorkDetailIdentityHeader(
                title = state.title,
                author = state.author,
                authorNames = state.tappableAuthorNames,
                fandoms = state.fandoms,
                palette = palette,
                onOpenAuthor = onOpenAuthor
            )

            Spacer(Modifier.height(16.dp))

            // 2. Figure Strip: Rating, Warnings, Category, Complete
            WorkDetailFigureStrip(
                rating = state.rating,
                warnings = state.warnings,
                categories = state.categories,
                chapters = state.chapters,
                isComplete = state.local?.isComplete ?: state.remote?.isComplete,
                palette = palette
            )

            Spacer(Modifier.height(14.dp))

            // 3. Resume Card: Progress ring, primary/secondary reading labels, 42dp play button
            val actionTitle = when {
                busy -> "Opening…"
                (state.local?.hasStartedReading == true) && !(state.local.isFinished) -> "Continue Reading"
                else -> "Read"
            }
            val readingProgress = if (state.local?.hasStartedReading == true) {
                state.local.readingProgress ?: 0.0
            } else null

            WorkDetailResumeCard(
                actionTitle = actionTitle,
                isBusy = state.working,
                isDownloading = isDownloading,
                readingProgress = readingProgress,
                savedPositionTitle = HomeFacts.locatorTitle(state.local?.readiumLocator),
                lastReadDate = state.local?.lastReadDate,
                palette = palette,
                onClick = onResumeClick
            )

            // 4. Status section: Transient feedback
            state.error?.let {
                Spacer(Modifier.height(12.dp))
                Box(modifier = Modifier.padding(horizontal = SubjectMetrics.panelGutter)) {
                    ErrorStateCard(title = "Work action failed", message = it)
                }
            }
            state.ao3Message?.let {
                Spacer(Modifier.height(8.dp))
                Box(modifier = Modifier.padding(horizontal = SubjectMetrics.panelGutter)) {
                    StatusBadge(it)
                }
            }
            if (state.local?.ao3Unavailable == true) {
                Spacer(Modifier.height(8.dp))
                Box(modifier = Modifier.padding(horizontal = SubjectMetrics.panelGutter)) {
                    StatusBadge("Unavailable on AO3 (Last Copy)")
                }
            }

            Spacer(Modifier.height(20.dp))

            // 5. Summary Section: Serif 16sp font with 8-line collapse
            WorkDetailSummarySection(
                summary = state.summary,
                palette = palette
            )

            // 6. ON AO3 Chips: Kudos, Subscribe, Bookmark, Mark for Later
            if (state.ao3WorkId != null) {
                Spacer(Modifier.height(20.dp))
                WorkDetailAo3ActionChips(
                    kudosCount = state.kudosCount,
                    hasGivenKudos = state.local?.hasGivenKudos == true,
                    isSubscribed = state.isSubscribed,
                    isBookmarked = isBookmarked,
                    isWorking = busy,
                    palette = palette,
                    onKudos = onKudos,
                    onSubscribe = onSubscribe,
                    onBookmark = onBookmark,
                    onMarkForLater = onMarkForLater
                )
            }

            // 7. Categorized Tag Clusters: Warnings, Fandoms, Relationships [tinted], Characters, Freeforms
            Spacer(Modifier.height(20.dp))
            WorkDetailTagSections(
                warnings = state.warnings,
                fandoms = state.fandoms,
                relationships = state.relationships,
                characters = state.characters,
                freeforms = state.freeforms,
                palette = palette
            )

            // 8. Facts Card: Outlined card with Series, Language · Words, Updated, Published
            Spacer(Modifier.height(24.dp))
            WorkDetailFactsCard(
                seriesTitle = state.local?.seriesTitle?.takeIf { it.isNotBlank() } ?: state.remote?.seriesTitle.orEmpty(),
                seriesPosition = state.local?.seriesPosition?.takeIf { it > 0 } ?: state.remote?.seriesPosition ?: 0,
                seriesUrl = state.seriesUrl,
                language = state.language,
                wordCount = state.wordCount,
                updatedDate = state.updatedDate,
                publishedDate = state.publishedDate,
                onOpenSeries = onOpenSeries
            )

            // 9. Archive Stats Strip: Kudos, Comments (highlighted), Bookmarks, Hits
            Spacer(Modifier.height(16.dp))
            WorkDetailArchiveStatsStrip(
                kudosCount = state.kudosCount,
                commentsCount = state.commentsCount,
                bookmarksCount = state.local?.bookmarks ?: state.remote?.bookmarks,
                hitsCount = state.hitsCount,
                palette = palette,
                hasAO3Work = state.ao3WorkId != null,
                onComments = onComments
            )

            // 10. Comments Section: All comments, Chapter comments, Write a comment
            if (state.ao3WorkId != null) {
                Spacer(Modifier.height(24.dp))
                WorkDetailCommentsSection(
                    commentsCount = state.commentsCount,
                    chapters = state.chapters,
                    onAllComments = onComments,
                    onChapterComments = onComments,
                    onWriteComment = onComments
                )
            }

            // 11. Page Actions: "Mark as Finished" / "Finished", "Open on AO3"
            Spacer(Modifier.height(20.dp))
            WorkDetailPageActions(
                isFinished = state.local?.isFinished == true,
                hasSourceUrl = state.sourceUrl.isNotBlank(),
                isWorking = busy,
                onToggleFinished = onToggleFinished,
                onOpenAo3 = onOpenAo3
            )

            // 12. Series Section
            val hasSeries = state.seriesUrl.isNotBlank() ||
                (state.local?.seriesTitle?.isNotBlank() == true) ||
                (state.remote?.seriesTitle?.isNotBlank() == true)
            if (hasSeries) {
                Spacer(Modifier.height(20.dp))
                WorkDetailSeriesSection(
                    seriesTitle = state.local?.seriesTitle?.takeIf { it.isNotBlank() } ?: state.remote?.seriesTitle.orEmpty(),
                    seriesPosition = state.local?.seriesPosition?.takeIf { it > 0 } ?: state.remote?.seriesPosition ?: 0,
                    seriesUrl = state.seriesUrl,
                    queuingSeries = state.queuingSeries,
                    onDownloadSeries = onDownloadSeries,
                    onOpenSeries = onOpenSeries
                )
            }

            // 13. My Copy Row: Entry to local device state sheet
            Spacer(Modifier.height(20.dp))
            WorkDetailMyCopyRow(
                summary = state.myCopySummary,
                onClick = onOpenMyCopy
            )

            Spacer(Modifier.height(36.dp))
        }
    }
}

private fun downloadActionLabel(action: WorkDownloadAction?, downloaded: Boolean): String = when (action) {
    WorkDownloadAction.Download -> "Download"
    WorkDownloadAction.RemoveDownload -> "Remove Download"
    is WorkDownloadAction.KeptBy -> "Kept Offline by ${action.name}"
    null -> if (downloaded) "Downloaded" else "Download"
}

private fun shareWork(context: Context, title: String, url: String) {
    val sendIntent = Intent().apply {
        this.action = Intent.ACTION_SEND
        putExtra(Intent.EXTRA_SUBJECT, title)
        putExtra(Intent.EXTRA_TEXT, "$title\n$url")
        type = "text/plain"
    }
    val shareIntent = Intent.createChooser(sendIntent, "Share Work")
    context.startActivity(shareIntent)
}

/**
 * Prefer discrete remote author list; fall back to splitting a local "A, B" string.
 * Anonymous / blank names are not tappable.
 */
internal fun resolveTappableAuthorNames(
    remoteAuthors: List<String>?,
    localAuthor: String?
): List<String> {
    val fromRemote = remoteAuthors.orEmpty()
        .map { it.trim() }
        .filter { it.isNotEmpty() && !it.equals("Anonymous", ignoreCase = true) }
    if (fromRemote.isNotEmpty()) return fromRemote

    val local = localAuthor?.trim().orEmpty()
    if (local.isEmpty() || local.equals("Anonymous", ignoreCase = true)) return emptyList()
    return local.split(",")
        .map { it.trim() }
        .filter { it.isNotEmpty() && !it.equals("Anonymous", ignoreCase = true) }
}

private data class WorkDetailUiState(
    val local: SavedWork? = null,
    val remote: AO3WorkSummary? = null,
    val userTags: List<Tag> = emptyList(),
    val collections: List<WorkCollection> = emptyList(),
    val queueMemberships: List<WorkQueueLine> = emptyList(),
    val inSavedForLater: Boolean = false,
    val loading: Boolean = false,
    val working: Boolean = false,
    val queuingSeries: Boolean = false,
    val error: String? = null,
    val ao3Message: String? = null,
    val isSubscribed: Boolean? = null
) {
    val title: String = local?.title ?: remote?.title ?: "Work"
    val author: String = local?.author ?: remote?.authorText ?: ""
    val tappableAuthorNames: List<String> =
        resolveTappableAuthorNames(remote?.authors, local?.author)
    val summary: String = local?.summary ?: remote?.summary ?: ""
    val sourceUrl: String = local?.sourceUrl ?: remote?.workUrl ?: ""
    val ao3WorkId: Long? = WorkTags.ao3WorkIdFromUrl(sourceUrl)
    val fandoms: List<String> = local?.workFandoms?.takeIf { it.isNotEmpty() }
        ?: remote?.fandoms.orEmpty()
    val rating: String = local?.rating ?: remote?.rating ?: ""
    val warnings: List<String> = local?.workWarnings?.takeIf { it.isNotEmpty() }
        ?: remote?.warnings.orEmpty()
    val categories: List<String> = local?.workCategories?.takeIf { it.isNotEmpty() }
        ?: remote?.categories.orEmpty()
    val relationships: List<String> = local?.workRelationships?.takeIf { it.isNotEmpty() }
        ?: remote?.relationships.orEmpty()
    val characters: List<String> = local?.workCharacters?.takeIf { it.isNotEmpty() }
        ?: remote?.characters.orEmpty()
    val freeforms: List<String> = local?.workFreeforms?.takeIf { it.isNotEmpty() }
        ?: remote?.freeforms.orEmpty()
    val language: String = local?.language ?: remote?.language ?: ""
    val wordCount: Int = local?.wordCount?.takeIf { it > 0 } ?: remote?.wordCount ?: 0
    val chapters: String = local?.chapters?.takeIf { it.isNotBlank() } ?: remote?.chapters ?: ""
    val commentsCount: Int? = local?.comments ?: remote?.comments
    val kudosCount: Int? = local?.kudos?.takeIf { it > 0 } ?: remote?.kudos
    val hitsCount: Int? = local?.hits ?: remote?.hits
    val publishedDate: String = remote?.publishedDate.orEmpty()
    val updatedDate: String = remote?.updatedDate.orEmpty()
    val seriesUrl: String = local?.seriesUrl?.takeIf { it.isNotBlank() }
        ?: remote?.seriesUrl?.takeIf { !it.isNullOrBlank() }
        ?: ""

    val myCopySummary: String
        get() {
            val segments = mutableListOf<String>()
            if (local?.isDownloaded == true) {
                segments.add("Downloaded")
            }
            val queueCount = queueMemberships.size
            if (queueCount > 0) {
                segments.add("$queueCount " + if (queueCount == 1) "queue" else "queues")
            }
            val collectionCount = collections.size
            if (collectionCount > 0) {
                segments.add("$collectionCount " + if (collectionCount == 1) "collection" else "collections")
            }
            val tagCount = userTags.size
            if (tagCount > 0) {
                segments.add("$tagCount " + if (tagCount == 1) "tag" else "tags")
            }
            if (segments.isEmpty()) {
                return "You haven't saved anything on this device yet"
            }
            return segments.joinToString(" · ")
        }
}

private fun AO3WorkMetadata.toRemoteSummary(workId: Long): AO3WorkSummary {
    return AO3WorkSummary(
        id = workId,
        title = "AO3 Work $workId",
        authors = emptyList(),
        fandoms = fandoms,
        rating = "",
        warnings = warnings,
        categories = categories,
        relationships = relationships,
        characters = characters,
        freeforms = freeforms,
        language = language,
        wordCount = words,
        chapters = chapters,
        kudos = kudos,
        comments = comments,
        hits = hits
    )
}
