package io.github.cidy02.kudos.works

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Chat
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.Bookmark
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.CollectionsBookmark
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Explore
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Queue
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.StarBorder
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
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
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.Tag
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.AO3URLResolver
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.series.AO3SeriesRepository
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadata
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataRepository
import io.github.cidy02.kudos.network.ao3.writes.AO3BookmarkInput
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteActionKind
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteOutcome
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.components.MetadataChip
import io.github.cidy02.kudos.ui.components.MetadataChipRow
import io.github.cidy02.kudos.ui.components.StatusBadge
import io.github.cidy02.kudos.ui.components.WorkStatIcons
import io.github.cidy02.kudos.ui.components.WorkStatItem
import io.github.cidy02.kudos.ui.components.WorkStatLabel
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.launch

private enum class WorkDetailTab(val label: String) {
    Overview("Overview"),
    Tags("Tags"),
    Discussion("Discussion"),
    Library("Library")
}

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
    seriesRepository: AO3SeriesRepository = AO3SeriesRepository(),
    onLogin: () -> Unit,
    onOpenComments: (Long) -> Unit,
    onOpenReader: (String) -> Unit,
    onOpenAuthor: (String) -> Unit = {}
) {
    var state by remember(source) { mutableStateOf(WorkDetailUiState()) }
    var newTagName by remember { mutableStateOf("") }
    var confirmRemove by remember { mutableStateOf(false) }
    var bookmarkDialog by remember { mutableStateOf(false) }
    var bookmarkLoading by remember { mutableStateOf(false) }
    var bookmarkIsEdit by remember { mutableStateOf(false) }
    var bookmarkNotes by remember { mutableStateOf("") }
    var bookmarkTags by remember { mutableStateOf("") }
    var bookmarkCollections by remember { mutableStateOf("") }
    var bookmarkPrivate by remember { mutableStateOf(false) }
    var bookmarkRecommendation by remember { mutableStateOf(false) }
    var bookmarkAvailablePseuds by remember { mutableStateOf<List<io.github.cidy02.kudos.network.ao3.writes.AO3PostingPseudOption>>(emptyList()) }
    var bookmarkPseudId by remember { mutableStateOf<String?>(null) }
    var queuePickerOpen by remember { mutableStateOf(false) }
    var createQueueDraft by remember { mutableStateOf<String?>(null) }
    var availableQueues by remember { mutableStateOf<List<ReadingQueue>>(emptyList()) }
    var queueMembershipIds by remember { mutableStateOf<Set<String>>(emptySet()) }
    var includeSeriesInQueue by remember { mutableStateOf(false) }
    var collectionDialogOpen by remember { mutableStateOf(false) }
    // Add-to-Collection checklist sheet state (iOS AddToCollectionView parity).
    var allCollections by remember { mutableStateOf<List<WorkCollection>>(emptyList()) }
    var collectionMemberIds by remember { mutableStateOf<Set<String>>(emptySet()) }
    var newCollectionName by remember { mutableStateOf("") }
    var collectionDialogWorking by remember { mutableStateOf(false) }
    var chapterIndexSheetOpen by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val uriHandler = LocalUriHandler.current
    var downloadWatchJob by remember { mutableStateOf<Job?>(null) }

    suspend fun refreshLocal(workId: String, remote: AO3WorkSummary? = state.remote) {
        val local = workRepository.getWork(workId)
        state = state.copy(
            local = local,
            remote = remote,
            userTags = local?.let { workRepository.userTagsForWork(it.id) }.orEmpty(),
            collections = local?.let { workRepository.collectionsForWork(it.id) }.orEmpty(),
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
                    // Metadata page has tags/stats but not title/author/summary yet.
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
                state = if (existing != null) {
                    WorkDetailUiState(
                        local = existing,
                        remote = source.summary,
                        userTags = workRepository.userTagsForWork(existing.id),
                        collections = workRepository.collectionsForWork(existing.id),
                        inSavedForLater = readingQueueRepository.isInSavedForLater(existing.id),
                        loading = false
                    )
                } else {
                    WorkDetailUiState(remote = source.summary, loading = false)
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

    // Prefetch live Subscribe/Unsubscribe label so the menu matches AO3 before tap.
    // Re-runs when the work id changes; failures leave isSubscribed null (label stays
    // "Subscribe") rather than blocking the rest of Work Detail.
    LaunchedEffect(state.ao3WorkId, state.loading) {
        val workId = state.ao3WorkId
        if (state.loading || workId == null) return@LaunchedEffect
        when (val result = writeRepository.fetchSubscriptionState(workId)) {
            is AO3Result.Success -> {
                // Don't clobber a value already set by a completed toggle while this
                // prefetch was still in flight.
                if (state.isSubscribed == null && state.ao3WorkId == workId) {
                    state = state.copy(isSubscribed = result.value.isSubscribed)
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

    fun saveMetadataOnly() {
        val remote = state.remote ?: return
        runWorkAction {
            when (val result = workImporter.saveMetadataOnly(remote)) {
                is WorkImportResult.Failure -> state = state.copy(error = result.error.displayMessage())
                is WorkImportResult.Success -> refreshLocal(result.work.id, remote)
            }
        }
    }

    /**
     * Routes downloads through [DownloadQueue] so concurrent taps queue serially
     * instead of racing [WorkImporter]. Redownload forces past the "already has
     * EPUB" skip. Local state refreshes when the queued item terminalizes.
     */
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

        // Refresh Work Detail once this id reaches a terminal queue status.
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
                    } else {
                        null
                    }
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

    /**
     * Scrapes the AO3 series page (all pages) and hands every work to
     * [DownloadQueue] for serial download. Already-downloaded works are skipped
     * by the queue. Surfaces fetch failures in the action footer.
     */
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

    /**
     * [queueOnly] is for reading-queue adds only (see the two call sites below):
     * a not-yet-local work is localized without becoming a full Library item
     * (`markSaved = false, isQueuedForLater = true`). Every other caller keeps
     * the ordinary explicit-save behavior.
     */
    fun ensureLocalThen(queueOnly: Boolean = false, action: suspend (SavedWork) -> Unit) {
        val local = state.local
        if (local != null) {
            // A work can already be local without ever having been queued or saved
            // (e.g. reading-history tracking) - stamp isQueuedForLater here too, not
            // only on the cold-localize path below, so queue-add is consistent
            // regardless of whether this was the work's first localization.
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

    /**
     * Reading-queue adds also preserve the EPUB for offline reading (iOS parity)
     * instead of leaving the queued work metadata-only. Skips silently if there's
     * no resolvable AO3 work id (e.g. a locally-imported EPUB) or it's already
     * downloaded — `force = false` lets DownloadQueue's own dedupe skip it.
     */
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
                // A work reached here as `state.local` can be a soft-deleted match —
                // WorkIdentityIndex's lookup (used to resolve a RemoteSummary/Ao3WorkId/
                // RemoteUrl source to a local row) doesn't filter isDeleted, so tapping
                // Save on what looks like a normal AO3 work can silently be acting on a
                // hidden Recently Deleted row, still counting down to permanent removal
                // regardless. Revive first, mirroring Apple `PreservedWorkService`'s
                // "revival on any interaction, not only an explicit restore tap" — not
                // gated behind a separate confirmation, since the user's own action
                // (saving/favoriting/finishing it again) already expresses the intent
                // a Restore tap would. restoreFromRecentlyDeleted also retracts the
                // sync tombstone, which the plain field-clearing copy() below doesn't.
                if (local.isDeleted) {
                    workRepository.restoreFromRecentlyDeleted(local.id)
                }
                val updated = workRepository.upsert(
                    local.copy(
                        isSaved = !local.isSaved,
                        isDeleted = false,
                        deletedAt = null,
                        permanentDeletionScheduledAt = null,
                        lastModifiedAt = Instant.now()
                    )
                )
                refreshLocal(updated.id, state.remote)
            }
            return
        }
        // Remote-only: create a local saved record.
        saveMetadataOnly()
    }

    if (confirmRemove) {
        AlertDialog(
            onDismissRequest = { confirmRemove = false },
            title = { Text("Remove from Library") },
            text = {
                Text(
                    "This moves the work to Recently Deleted for 90 days. " +
                        "You can restore it from Library → Recently Deleted. " +
                        "After 90 days it is permanently removed (including any downloaded EPUB)."
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val workId = state.local?.id ?: return@TextButton
                        confirmRemove = false
                        runWorkAction {
                            // Soft-delete into Recently Deleted (90-day recovery).
                            workRepository.softDelete(workId)
                            state = WorkDetailUiState(remote = state.remote, loading = false)
                        }
                    }
                ) {
                    Text("Remove")
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmRemove = false }) { Text("Cancel") }
            }
        )
    }

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
                        // Read-only: write path always re-submits scraped collection_names
                        // so updates never strip AO3 membership the composer doesn't edit.
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
                                val created = readingQueueRepository.createQueue(name)
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

    // Load full collection list + current membership when the checklist opens.
    LaunchedEffect(collectionDialogOpen) {
        if (!collectionDialogOpen) return@LaunchedEffect
        newCollectionName = ""
        collectionDialogWorking = false
        try {
            allCollections = workRepository.allCollections()
                .sortedBy { it.name.lowercase() }
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
                    // Refresh work membership label after checklist edits.
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
                    // Create-new row (iOS: TextField + Add).
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
                                        val collections = workRepository.addToCollection(
                                            work.id,
                                            name
                                        )
                                        newCollectionName = ""
                                        collectionMemberIds = collections.map { it.id }.toSet()
                                        allCollections = workRepository.allCollections()
                                            .sortedBy { it.name.lowercase() }
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
                                    .clickable(
                                        enabled = !collectionDialogWorking && !state.working
                                    ) {
                                        ensureLocalThen { work ->
                                            collectionDialogWorking = true
                                            try {
                                                val collections = if (isMember) {
                                                    workRepository.removeFromCollection(
                                                        work.id,
                                                        collection.id
                                                    )
                                                } else {
                                                    workRepository.addWorkToCollection(
                                                        work.id,
                                                        collection.id
                                                    )
                                                }
                                                collectionMemberIds =
                                                    collections.map { it.id }.toSet()
                                                allCollections =
                                                    workRepository.allCollections()
                                                        .sortedBy { it.name.lowercase() }
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
        androidx.compose.material3.ModalBottomSheet(
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

    WorkDetailContent(
        state = state,
        newTagName = newTagName,
        onNewTagName = { newTagName = it },
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
            val work = state.local ?: return@WorkDetailContent
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
        onKudos = { runAo3Write { writeRepository.giveKudos(it) } },
        onSubscribe = { runAo3Write { writeRepository.toggleSubscribe(it) } },
        onMarkForLater = { runAo3Write { writeRepository.markForLater(it) } },
        onAddToSavedForLater = {
            ensureLocalThen(queueOnly = true) { work ->
                if (state.inSavedForLater) {
                    readingQueueRepository.removeFromSavedForLater(work.id)
                } else {
                    readingQueueRepository.addToSavedForLater(work.id)
                    preserveEpubForQueue(work)
                }
                refreshLocal(work.id, state.remote)
            }
        },
        onAddToQueue = {
            ensureLocalThen { work ->
                availableQueues = readingQueueRepository.listQueues()
                    .filter { it.kindRaw != ReadingQueueKind.SAVED_FOR_LATER }
                queuePickerOpen = true
                // Keep work in state after ensureLocal.
                refreshLocal(work.id, state.remote)
            }
        },
        onAddToCollection = { collectionDialogOpen = true },
        onBookmark = {
            val workId = state.ao3WorkId
            if (workId == null) {
                state = state.copy(error = "This action needs a canonical AO3 work URL.")
                return@WorkDetailContent
            }
            // Open immediately so the dialog isn't blocked on network; prefill
            // when fetchBookmarkState resolves. Fail-safe: leave create mode blank.
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
                        // Keep blank create-mode fields; surface the error if useful.
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
        onChapterIndex = { chapterIndexSheetOpen = true },
        onOpenReader = onOpenReader,
        onOpenAuthor = onOpenAuthor
    )
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun WorkDetailContent(
    state: WorkDetailUiState,
    newTagName: String,
    onNewTagName: (String) -> Unit,
    onToggleFavorite: () -> Unit,
    onToggleSaved: () -> Unit,
    onToggleFinished: () -> Unit,
    onAddTag: () -> Unit,
    onRemoveTag: (Tag) -> Unit,
    onSuggestTag: (String) -> Unit,
    onDownload: () -> Unit,
    onDownloadSeries: () -> Unit,
    onDeleteEpub: () -> Unit,
    onRemoveFromLibrary: () -> Unit,
    onOpenAo3: () -> Unit,
    onLogin: () -> Unit,
    onKudos: () -> Unit,
    onSubscribe: () -> Unit,
    onMarkForLater: () -> Unit,
    onAddToSavedForLater: () -> Unit,
    onAddToQueue: () -> Unit,
    onAddToCollection: () -> Unit,
    onBookmark: () -> Unit,
    onComments: () -> Unit,
    onChapterIndex: () -> Unit,
    onOpenReader: (String) -> Unit,
    onOpenAuthor: (String) -> Unit
) {
    var selectedTab by remember { mutableStateOf(WorkDetailTab.Overview) }
    var overflowExpanded by remember { mutableStateOf(false) }
    var chapterIndexSheetOpen by remember { mutableStateOf(false) }
    val busy = state.working || state.queuingSeries
    val local = state.local
    val isFavorite = local?.isFavorite == true
    val isSaved = local?.isSaved == true
    val hasEpub = local?.hasEpub == true
    val epubWorkId = local?.takeIf { it.hasEpub }?.id

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp, vertical = 12.dp)
    ) {
        if (state.loading) {
            LoadingStateCard("Loading work details")
            return
        }

        // Toolbar strip: favorite ★ + overflow ⋯ (app bar already provides Back).
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.End,
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(
                onClick = onToggleFavorite,
                enabled = !busy,
                modifier = Modifier.semantics {
                    contentDescription = if (isFavorite) "Unfavorite" else "Favorite"
                }
            ) {
                Icon(
                    imageVector = if (isFavorite) Icons.Filled.Star else Icons.Outlined.StarBorder,
                    contentDescription = null,
                    tint = if (isFavorite) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    }
                )
            }
            Box {
                IconButton(
                    onClick = { overflowExpanded = true },
                    modifier = Modifier.semantics { contentDescription = "More actions" }
                ) {
                    Icon(Icons.Filled.MoreVert, contentDescription = null)
                }
                DropdownMenu(
                    expanded = overflowExpanded,
                    onDismissRequest = { overflowExpanded = false }
                ) {
                    DropdownMenuItem(
                        text = { Text("Give Kudos") },
                        enabled = !busy && state.ao3WorkId != null,
                        onClick = {
                            overflowExpanded = false
                            onKudos()
                        }
                    )
                    DropdownMenuItem(
                        text = { Text("Bookmark on AO3") },
                        enabled = !busy && state.ao3WorkId != null,
                        onClick = {
                            overflowExpanded = false
                            onBookmark()
                        }
                    )
                    DropdownMenuItem(
                        text = { Text("Mark for Later (AO3)") },
                        enabled = !busy && state.ao3WorkId != null,
                        onClick = {
                            overflowExpanded = false
                            onMarkForLater()
                        }
                    )
                    DropdownMenuItem(
                        text = {
                            Text(
                                if (state.isSubscribed == true) "Unsubscribe" else "Subscribe"
                            )
                        },
                        enabled = !busy && state.ao3WorkId != null,
                        onClick = {
                            overflowExpanded = false
                            onSubscribe()
                        }
                    )
                    DropdownMenuItem(
                        text = { Text("Log in to AO3") },
                        onClick = {
                            overflowExpanded = false
                            onLogin()
                        }
                    )
                    // Local-only imports have no AO3 id — hide redownload rather
                    // than offering an action that can only fail with "No work selected."
                    if (hasEpub && state.ao3WorkId != null) {
                        DropdownMenuItem(
                            text = { Text("Redownload EPUB") },
                            enabled = !busy,
                            onClick = {
                                overflowExpanded = false
                                onDownload()
                            }
                        )
                    }
                    if (state.seriesUrl.isNotBlank()) {
                        DropdownMenuItem(
                            text = {
                                Text(
                                    if (state.queuingSeries) "Fetching series…" else "Download series"
                                )
                            },
                            enabled = !busy && state.seriesUrl.isNotBlank(),
                            onClick = {
                                overflowExpanded = false
                                onDownloadSeries()
                            }
                        )
                    }
                    if (hasEpub) {
                        DropdownMenuItem(
                            text = { Text("Delete EPUB") },
                            enabled = !busy,
                            onClick = {
                                overflowExpanded = false
                                onDeleteEpub()
                            }
                        )
                    }
                    if (local != null) {
                        DropdownMenuItem(
                            text = { Text("Remove from Library") },
                            enabled = !busy,
                            onClick = {
                                overflowExpanded = false
                                onRemoveFromLibrary()
                            }
                        )
                    }
                }
            }
        }

        WorkDetailHeaderCard(
            state = state,
            onOpenAuthor = onOpenAuthor,
            onKudos = onKudos,
            onBookmark = onBookmark,
            onChapterIndex = onChapterIndex
        )

        Spacer(Modifier.height(12.dp))

        SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
            WorkDetailTab.entries.forEachIndexed { index, tab ->
                SegmentedButton(
                    selected = selectedTab == tab,
                    onClick = { selectedTab = tab },
                    shape = SegmentedButtonDefaults.itemShape(
                        index = index,
                        count = WorkDetailTab.entries.size
                    ),
                    label = {
                        Text(
                            text = tab.label,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            style = MaterialTheme.typography.labelMedium
                        )
                    }
                )
            }
        }

        Spacer(Modifier.height(12.dp))

        state.error?.let {
            ErrorStateCard(title = "Work action failed", message = it)
            Spacer(Modifier.height(8.dp))
        }
        state.ao3Message?.let {
            StatusBadge(it)
            Spacer(Modifier.height(8.dp))
        }

        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            when (selectedTab) {
                WorkDetailTab.Overview -> OverviewTab(
                    state = state,
                    busy = busy,
                    hasEpub = hasEpub,
                    isSaved = isSaved,
                    epubWorkId = epubWorkId,
                    onOpenReader = onOpenReader,
                    onDownload = onDownload,
                    onOpenAo3 = onOpenAo3,
                    onToggleSaved = onToggleSaved,
                    onAddToSavedForLater = onAddToSavedForLater,
                    onAddToQueue = onAddToQueue,
                    onAddToCollection = onAddToCollection,
                    onToggleFinished = onToggleFinished,
                    onComments = onComments
                )
                WorkDetailTab.Tags -> TagsTab(state = state)
                WorkDetailTab.Discussion -> DiscussionTab(
                    state = state,
                    onAllComments = onComments,
                    onChapterComments = { /* Chapter id needed */ },
                    onWriteComment = onComments
                )
                WorkDetailTab.Library -> LibraryTab(
                    state = state,
                    busy = busy,
                    isSaved = isSaved,
                    hasEpub = hasEpub,
                    newTagName = newTagName,
                    onNewTagName = onNewTagName,
                    onToggleSaved = onToggleSaved,
                    onAddToSavedForLater = onAddToSavedForLater,
                    onAddToQueue = onAddToQueue,
                    onAddToCollection = onAddToCollection,
                    onToggleFinished = onToggleFinished,
                    onDownload = onDownload,
                    onAddTag = onAddTag,
                    onRemoveTag = onRemoveTag,
                    onSuggestTag = onSuggestTag
                )
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun WorkDetailHeaderCard(
    state: WorkDetailUiState,
    onOpenAuthor: (String) -> Unit,
    onKudos: () -> Unit,
    onBookmark: () -> Unit,
    onChapterIndex: () -> Unit
) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow
        ),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = state.title,
                style = MaterialTheme.typography.titleLarge,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis
            )
            AuthorLine(
                authorNames = state.tappableAuthorNames,
                displayAuthor = state.author,
                onOpenAuthor = onOpenAuthor
            )
            if (state.fandoms.isNotEmpty()) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Outlined.MenuBook,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(16.dp)
                    )
                    Text(
                        text = state.fandoms.joinToString(", "),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
            val compactStats = buildList {
                if (state.rating.isNotBlank()) {
                    add(
                        WorkStatItem(
                            text = state.rating,
                            icon = WorkStatIcons.rating
                        )
                    )
                }
                if (state.chapters.isNotBlank()) {
                    add(
                        WorkStatItem(
                            text = state.chapters,
                            icon = WorkStatIcons.chapters
                        )
                    )
                }
                if (state.completionLabel.isNotBlank()) {
                    add(
                        WorkStatItem(
                            text = state.completionLabel,
                            icon = if (state.completionLabel == "Complete") {
                                WorkStatIcons.complete
                            } else {
                                WorkStatIcons.inProgress
                            }
                        )
                    )
                }
                if (state.wordCount > 0) {
                    add(
                        WorkStatItem(
                            text = "%,d".format(state.wordCount),
                            icon = WorkStatIcons.words
                        )
                    )
                }
            }
            if (compactStats.isNotEmpty()) {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    compactStats.forEach { WorkStatLabel(item = it) }
                }
            }
            HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                TextButton(onClick = onKudos, enabled = state.ao3WorkId != null) {
                    Icon(Icons.Filled.Star, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.padding(end = 4.dp))
                    Text("Kudos")
                }
                TextButton(onClick = onBookmark, enabled = state.ao3WorkId != null) {
                    Icon(Icons.Outlined.Bookmark, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.padding(end = 4.dp))
                    Text("Bookmark")
                }
                TextButton(onClick = onChapterIndex) {
                    Icon(Icons.AutoMirrored.Outlined.MenuBook, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.padding(end = 4.dp))
                    Text("Chapter Index")
                }
            }
        }
    }
}

@Composable
private fun OverviewTab(
    state: WorkDetailUiState,
    busy: Boolean,
    hasEpub: Boolean,
    isSaved: Boolean,
    epubWorkId: String?,
    onOpenReader: (String) -> Unit,
    onDownload: () -> Unit,
    onOpenAo3: () -> Unit,
    onToggleSaved: () -> Unit,
    onAddToSavedForLater: () -> Unit,
    onAddToQueue: () -> Unit,
    onAddToCollection: () -> Unit,
    onToggleFinished: () -> Unit,
    onComments: () -> Unit
) {
    val isFinished = state.local?.isFinished == true
    val canRead = !busy && epubWorkId != null
    val canDownload = !busy && (state.remote != null || state.local != null)
    val readLabel = when {
        busy && state.queuingSeries -> "Working…"
        busy -> "Downloading…"
        hasEpub && state.local?.hasStartedReading == true -> "Continue Reading"
        hasEpub -> "Read"
        else -> "Download & Read"
    }

    SectionLabel("Summary")
    DetailCard {
        Text(
            text = state.summary.ifBlank { "No summary available." },
            style = MaterialTheme.typography.bodyLarge,
            color = if (state.summary.isBlank()) {
                MaterialTheme.colorScheme.onSurfaceVariant
            } else {
                MaterialTheme.colorScheme.onSurface
            }
        )
    }

    SectionLabel("Quick Actions")
    QuickActionsGrid(
        actions = listOf(
            QuickAction(
                label = readLabel,
                icon = Icons.AutoMirrored.Outlined.MenuBook,
                enabled = if (hasEpub) canRead else canDownload,
                onClick = {
                    if (epubWorkId != null) onOpenReader(epubWorkId) else onDownload()
                }
            ),
            QuickAction(
                label = "Open on AO3",
                icon = Icons.Outlined.Explore,
                enabled = state.sourceUrl.isNotBlank(),
                onClick = onOpenAo3
            ),
            QuickAction(
                label = if (isSaved) "Saved" else "Save",
                icon = if (isSaved) Icons.Outlined.Bookmark else Icons.Outlined.BookmarkBorder,
                enabled = !busy && (state.local != null || state.remote != null),
                emphasized = isSaved,
                onClick = onToggleSaved
            ),
            QuickAction(
                label = if (state.inSavedForLater) "Saved for Later" else "Save for Later",
                icon = Icons.Outlined.Schedule,
                enabled = !busy,
                emphasized = state.inSavedForLater,
                onClick = onAddToSavedForLater
            ),
            QuickAction(
                label = "Add to Queue",
                icon = Icons.Outlined.Queue,
                enabled = !busy,
                onClick = onAddToQueue
            ),
            QuickAction(
                label = if (state.collections.isEmpty()) "Add to Collection" else "Collection",
                icon = Icons.Outlined.CollectionsBookmark,
                enabled = !busy,
                emphasized = state.collections.isNotEmpty(),
                onClick = onAddToCollection
            ),
            QuickAction(
                label = if (isFinished) "Finished" else "Mark as Finished",
                icon = if (isFinished) Icons.Filled.CheckCircle else Icons.Outlined.CheckCircle,
                enabled = !busy,
                emphasized = isFinished,
                onClick = onToggleFinished
            ),
            QuickAction(
                label = "Comments",
                icon = Icons.AutoMirrored.Outlined.Chat,
                enabled = !busy && state.ao3WorkId != null,
                subtitle = state.commentsCount?.let { "%,d".format(it) },
                onClick = onComments
            )
        )
    )

    SectionLabel("Publication")
    MetaRowsCard(
        rows = listOfNotNull(
            state.publishedDate.takeIf { it.isNotBlank() }?.let { "Published" to it },
            state.updatedDate.takeIf { it.isNotBlank() }?.let { "Updated" to it },
            state.language.takeIf { it.isNotBlank() }?.let { "Language" to it },
            state.dateAddedLabel?.let { "Added" to it },
            // Local file imports keep sourceUrl blank — don't claim AO3 origin.
            state.sourceUrl.takeIf { it.isNotBlank() }?.let { "Source" to "Archive of Our Own" }
        )
    )

    SectionLabel("Work")
    MetaRowsCard(
        rows = listOfNotNull(
            state.rating.takeIf { it.isNotBlank() }?.let { "Rating" to it },
            state.categories.takeIf { it.isNotEmpty() }?.let {
                "Category" to it.joinToString(", ")
            },
            state.completionLabel.takeIf { it.isNotBlank() }?.let { "Status" to it },
            state.wordCount.takeIf { it > 0 }?.let { "Words" to "%,d".format(it) },
            state.chapters.takeIf { it.isNotBlank() }?.let { "Chapters" to it }
        )
    )

    SectionLabel("Stats")
    MetaRowsCard(
        rows = listOfNotNull(
            state.hitsCount?.let { "Hits" to "%,d".format(it) },
            state.kudosCount?.let { "Kudos" to "%,d".format(it) },
            state.commentsCount?.let { "Comments" to "%,d".format(it) }
        ),
        linkLabels = setOf("Comments"),
        onRowClick = { label -> if (label == "Comments") onComments() }
    )

    if (state.sourceUrl.isNotBlank()) {
        SectionLabel("Origin")
        DetailCard {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Outlined.MenuBook,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(18.dp)
                    )
                    Text(
                        text = "From Archive of Our Own.",
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
                Text(
                    text = state.sourceUrl,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier
                        .semantics { contentDescription = "Open AO3 work URL" }
                        .clickable(onClick = onOpenAo3)
                )
                if (state.seriesLine.isNotBlank()) {
                    Text(
                        text = state.seriesLine,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun TagsTab(state: WorkDetailUiState) {
    TagGroupSection("Archive Warnings", state.warnings)
    TagGroupSection("Fandoms", state.fandoms)
    TagGroupSection("Relationships", state.relationships)
    TagGroupSection("Characters", state.characters)
    TagGroupSection("Additional Tags", state.freeforms)
    if (state.warnings.isEmpty() &&
        state.fandoms.isEmpty() &&
        state.relationships.isEmpty() &&
        state.characters.isEmpty() &&
        state.freeforms.isEmpty()
    ) {
        Text(
            text = "No tags available for this work yet.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
    Text(
        text = "Tags are shown for browsing; AO3 tag search from chips can land later.",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
}

@Composable
private fun DiscussionTab(
    state: WorkDetailUiState,
    onAllComments: () -> Unit,
    onChapterComments: (Long) -> Unit,
    onWriteComment: () -> Unit
) {
    SectionLabel("Comments")
    DetailFormCard {
        DiscussionRow(
            icon = Icons.AutoMirrored.Outlined.Chat,
            title = "All Comments",
            trailing = state.commentsCount?.let { "%,d".format(it) },
            enabled = state.ao3WorkId != null,
            onClick = onAllComments,
            showDivider = true
        )
        if (state.chapters.isNotBlank() && state.chapters != "1") {
            DiscussionRow(
                icon = Icons.AutoMirrored.Outlined.MenuBook,
                title = "Chapter Comments",
                trailing = null,
                enabled = state.ao3WorkId != null,
                onClick = { /* Need chapter id, but WorkDetailUiState doesn't have it yet */ },
                showDivider = true
            )
        }
        DiscussionRow(
            icon = Icons.Outlined.Edit,
            title = "Write a Comment",
            trailing = null,
            enabled = state.ao3WorkId != null,
            onClick = onWriteComment,
            showDivider = false
        )
    }
    Text(
        text = "Comment pages load when you open them; nothing is fetched in advance.",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun LibraryTab(
    state: WorkDetailUiState,
    busy: Boolean,
    isSaved: Boolean,
    hasEpub: Boolean,
    newTagName: String,
    onNewTagName: (String) -> Unit,
    onToggleSaved: () -> Unit,
    onAddToSavedForLater: () -> Unit,
    onAddToQueue: () -> Unit,
    onAddToCollection: () -> Unit,
    onToggleFinished: () -> Unit,
    onDownload: () -> Unit,
    onAddTag: () -> Unit,
    onRemoveTag: (Tag) -> Unit,
    onSuggestTag: (String) -> Unit
) {
    val isFinished = state.local?.isFinished == true
    val inCollection = state.collections.isNotEmpty()

    SectionLabel("Status")
    DetailFormCard {
        StatusToggleRow(
            icon = if (isSaved) Icons.Outlined.Bookmark else Icons.Outlined.BookmarkBorder,
            title = if (isSaved) "Saved" else "Save",
            checked = isSaved,
            enabled = !busy,
            onClick = onToggleSaved,
            showDivider = true
        )
        StatusToggleRow(
            icon = Icons.Outlined.Schedule,
            title = "Save for Later",
            checked = state.inSavedForLater,
            enabled = !busy,
            onClick = onAddToSavedForLater,
            showDivider = true
        )
        StatusToggleRow(
            icon = Icons.Outlined.Queue,
            title = "Add to Queue",
            checked = false,
            enabled = !busy,
            onClick = onAddToQueue,
            showDivider = true
        )
        StatusToggleRow(
            icon = Icons.Outlined.CollectionsBookmark,
            title = if (inCollection) {
                "In Collection · ${state.collections.joinToString { it.name }}"
            } else {
                "Add to Collection"
            },
            checked = inCollection,
            enabled = !busy,
            onClick = onAddToCollection,
            showDivider = true
        )
        StatusToggleRow(
            icon = if (isFinished) Icons.Filled.CheckCircle else Icons.Outlined.CheckCircle,
            title = if (isFinished) "Finished" else "Mark as Finished",
            checked = isFinished,
            enabled = !busy,
            onClick = onToggleFinished,
            showDivider = false
        )
    }
    Text(
        text = statusFooter(state),
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )

    SectionLabel("Storage")
    DetailCard {
        // Download / redownload only makes sense with an AO3 work id. Local file
        // imports show status only (no dead tap that ends in "No work selected").
        val canDownloadFromAo3 = state.ao3WorkId != null
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(enabled = !busy && canDownloadFromAo3) {
                    onDownload()
                },
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = if (hasEpub) "Download" else "Download",
                style = MaterialTheme.typography.bodyLarge
            )
            Text(
                text = when {
                    busy -> "Working…"
                    hasEpub -> "Downloaded"
                    else -> "Not downloaded"
                },
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }

    SectionLabel("Activity")
    DetailCard {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            MetaRow("Added", state.dateAddedLabel ?: "—")
            MetaRow("Last Opened", state.lastOpenedLabel ?: "—")
            val progress = state.progressPercent
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text("Progress", style = MaterialTheme.typography.bodyLarge)
                Text(
                    text = if (progress != null) "$progress%" else "—",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            if (progress != null) {
                LinearProgressIndicator(
                    progress = { progress / 100f },
                    modifier = Modifier.fillMaxWidth(),
                    color = MaterialTheme.colorScheme.primary,
                    trackColor = MaterialTheme.colorScheme.surfaceContainerHighest
                )
            }
        }
    }

    SectionLabel("My Tags")
    DetailCard {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (state.userTags.isEmpty()) {
                Text(
                    text = "No tags yet — add some to organize your Library.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    state.userTags.forEach { tag ->
                        OutlinedButton(
                            enabled = !busy,
                            onClick = { onRemoveTag(tag) },
                            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp)
                        ) {
                            Text(tag.normalizedName)
                        }
                    }
                }
            }
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                OutlinedTextField(
                    value = newTagName,
                    onValueChange = onNewTagName,
                    label = { Text("Add a tag") },
                    singleLine = true,
                    modifier = Modifier.weight(1f)
                )
                TextButton(
                    enabled = !busy && newTagName.isNotBlank(),
                    onClick = onAddTag
                ) {
                    Text("Add")
                }
            }
            val suggestions = state.tagSuggestions
            if (suggestions.isNotEmpty()) {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    suggestions.forEach { suggestion ->
                        MetadataChip(
                            label = suggestion,
                            modifier = Modifier.clickable(enabled = !busy) {
                                onSuggestTag(suggestion)
                            }
                        )
                    }
                }
            }
        }
    }
    Text(
        text = "My Tags are private to your Library on this device and separate from AO3's tags.",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
}

// region Shared UI atoms

private data class QuickAction(
    val label: String,
    val icon: ImageVector,
    val enabled: Boolean = true,
    val emphasized: Boolean = false,
    val subtitle: String? = null,
    val onClick: () -> Unit
)

@Composable
private fun QuickActionsGrid(actions: List<QuickAction>) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        actions.chunked(3).forEach { row ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                row.forEach { action ->
                    QuickActionCell(
                        action = action,
                        modifier = Modifier.weight(1f)
                    )
                }
                repeat(3 - row.size) {
                    Spacer(Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun QuickActionCell(
    action: QuickAction,
    modifier: Modifier = Modifier
) {
    val contentColor = when {
        !action.enabled -> MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
        action.emphasized -> MaterialTheme.colorScheme.primary
        else -> MaterialTheme.colorScheme.primary
    }
    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow
        ),
        modifier = modifier
            .aspectRatio(1f)
            .semantics { contentDescription = action.label }
            .then(
                if (action.enabled) {
                    Modifier.clickable(onClick = action.onClick)
                } else {
                    Modifier
                }
            )
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Icon(
                imageVector = action.icon,
                contentDescription = null,
                tint = contentColor,
                modifier = Modifier.size(28.dp)
            )
            Spacer(Modifier.height(8.dp))
            Text(
                text = action.label,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            action.subtitle?.let { sub ->
                Text(
                    text = sub,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun SectionLabel(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.titleMedium,
        color = MaterialTheme.colorScheme.onSurface
    )
}

@Composable
private fun DetailCard(content: @Composable ColumnScope.() -> Unit) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow
        ),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            content = content
        )
    }
}

@Composable
private fun DetailFormCard(content: @Composable ColumnScope.() -> Unit) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow
        ),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(content = content)
    }
}

@Composable
private fun MetaRowsCard(
    rows: List<Pair<String, String>>,
    linkLabels: Set<String> = emptySet(),
    onRowClick: (String) -> Unit = {}
) {
    if (rows.isEmpty()) {
        DetailCard {
            Text(
                text = "No metadata yet.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        return
    }
    DetailCard {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            rows.forEach { (label, value) ->
                val isLink = label in linkLabels
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .then(
                            if (isLink) {
                                Modifier.clickable { onRowClick(label) }
                            } else {
                                Modifier
                            }
                        ),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.Top
                ) {
                    Text(
                        text = label,
                        style = MaterialTheme.typography.bodyLarge,
                        color = if (isLink) {
                            MaterialTheme.colorScheme.primary
                        } else {
                            MaterialTheme.colorScheme.onSurface
                        },
                        modifier = Modifier.padding(end = 12.dp)
                    )
                    Text(
                        text = value,
                        style = MaterialTheme.typography.bodyMedium,
                        color = if (isLink) {
                            MaterialTheme.colorScheme.primary
                        } else {
                            MaterialTheme.colorScheme.onSurfaceVariant
                        }
                    )
                }
            }
        }
    }
}

@Composable
private fun MetaRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(text = label, style = MaterialTheme.typography.bodyLarge)
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun TagGroupSection(title: String, tags: List<String>) {
    if (tags.isEmpty()) return
    SectionLabel(title)
    DetailCard {
        MetadataChipRow(labels = tags, maxItems = 40)
    }
}

@Composable
private fun DiscussionRow(
    icon: ImageVector,
    title: String,
    trailing: String?,
    enabled: Boolean,
    onClick: () -> Unit,
    showDivider: Boolean
) {
    Column {
        ListItem(
            headlineContent = {
                Text(
                    text = title,
                    color = if (enabled) {
                        MaterialTheme.colorScheme.onSurface
                    } else {
                        MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
                    }
                )
            },
            leadingContent = {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary
                )
            },
            trailingContent = {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    trailing?.let {
                        Text(
                            text = it,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Text(
                        text = "›",
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            },
            modifier = Modifier
                .fillMaxWidth()
                .then(if (enabled) Modifier.clickable(onClick = onClick) else Modifier),
            colors = ListItemDefaults.colors(
                containerColor = MaterialTheme.colorScheme.surfaceContainerLow
            )
        )
        if (showDivider) {
            HorizontalDivider(
                modifier = Modifier.padding(start = 16.dp),
                color = MaterialTheme.colorScheme.outlineVariant
            )
        }
    }
}

@Composable
private fun StatusToggleRow(
    icon: ImageVector,
    title: String,
    checked: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
    showDivider: Boolean
) {
    Column {
        ListItem(
            headlineContent = {
                Text(
                    text = title,
                    color = if (enabled) {
                        MaterialTheme.colorScheme.onSurface
                    } else {
                        MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
                    }
                )
            },
            leadingContent = {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary
                )
            },
            trailingContent = {
                if (checked) {
                    Icon(
                        imageVector = Icons.Filled.CheckCircle,
                        contentDescription = "On",
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(20.dp)
                    )
                }
            },
            modifier = Modifier
                .fillMaxWidth()
                .then(if (enabled) Modifier.clickable(onClick = onClick) else Modifier),
            colors = ListItemDefaults.colors(
                containerColor = MaterialTheme.colorScheme.surfaceContainerLow
            )
        )
        if (showDivider) {
            HorizontalDivider(
                modifier = Modifier.padding(start = 16.dp),
                color = MaterialTheme.colorScheme.outlineVariant
            )
        }
    }
}

private fun statusFooter(state: WorkDetailUiState): String {
    val work = state.local
        ?: return "Reading downloads this work to your device. When you finish, the file is freed unless you save or favorite it."
    return when {
        work.isSaved -> "Saved — kept on this device."
        !work.hasEpub -> "Finished. The file was freed to save space; it re-downloads when you read it again."
        work.isFinished -> "Finished."
        work.isFavorite -> "Favorited, so its file is kept when finished."
        else -> "Reading. When you finish, the file is freed unless you save or favorite it."
    }
}

/**
 * Renders author names with each non-blank, non-Anonymous author name tappable
 * so users can open that author's works list (AO3 parity).
 */
@Composable
private fun AuthorLine(
    authorNames: List<String>,
    displayAuthor: String,
    onOpenAuthor: (String) -> Unit
) {
    if (authorNames.isEmpty()) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = Icons.Outlined.Person,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(16.dp)
            )
            Text(
                text = displayAuthor.ifBlank { "Anonymous" },
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        return
    }

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = Icons.Outlined.Person,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(16.dp)
        )
        authorNames.forEachIndexed { index, name ->
            Text(
                text = name,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.primary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier
                    .semantics { contentDescription = "Open works by $name" }
                    .clickable { onOpenAuthor(name) }
            )
            if (index < authorNames.lastIndex) {
                Text(
                    text = ",",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

// endregion

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
    val inSavedForLater: Boolean = false,
    val loading: Boolean = false,
    val working: Boolean = false,
    /** True while scraping series pages before enqueue. */
    val queuingSeries: Boolean = false,
    val error: String? = null,
    val ao3Message: String? = null,
    /**
     * Live AO3 subscription state for the overflow Subscribe/Unsubscribe label.
     * `null` = not loaded yet (or unavailable when signed out / offline).
     */
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
    val completionLabel: String = when (local?.isComplete ?: remote?.isComplete) {
        true -> "Complete"
        false -> "Work in Progress"
        null -> ""
    }
    val wordCount: Int = local?.wordCount?.takeIf { it > 0 } ?: remote?.wordCount ?: 0
    val chapters: String = local?.chapters?.takeIf { it.isNotBlank() } ?: remote?.chapters ?: ""
    val commentsCount: Int? = local?.comments ?: remote?.comments
    val kudosCount: Int? = local?.kudos?.takeIf { it > 0 } ?: remote?.kudos
    val hitsCount: Int? = local?.hits ?: remote?.hits
    val publishedDate: String = remote?.publishedDate.orEmpty()
    val updatedDate: String = remote?.updatedDate.orEmpty()
    val dateAddedLabel: String? = local?.dateAdded?.let { formatInstant(it) }
    val lastOpenedLabel: String? = local?.lastReadDate?.let { formatInstant(it) }
    val progressPercent: Int? = local?.takeIf { it.hasStartedReading }?.let {
        (it.lastScrollFraction.coerceIn(0.0, 1.0) * 100).toInt()
    }
    val seriesUrl: String = local?.seriesUrl?.takeIf { it.isNotBlank() }
        ?: remote?.seriesUrl?.takeIf { !it.isNullOrBlank() }
        ?: ""
    val seriesLine: String = local?.seriesTitle?.takeIf { it.isNotBlank() }?.let { title ->
        "Series: $title" + local.seriesPosition.takeIf { it > 0 }?.let { " #$it" }.orEmpty()
    } ?: remote?.seriesTitle?.let { title ->
        "Series: $title" + remote.seriesPosition?.let { " #$it" }.orEmpty()
    }.orEmpty()

    /** Suggested chips for My Tags: fandom / relationship samples not already applied. */
    val tagSuggestions: List<String>
        get() {
            val existing = userTags.map { it.normalizedName.lowercase() }.toSet()
            return (fandoms + relationships)
                .map { it.trim() }
                .filter { it.isNotBlank() && it.lowercase() !in existing }
                .distinct()
                .take(6)
        }
}

private fun formatInstant(instant: Instant): String {
    val formatter = DateTimeFormatter
        .ofLocalizedDateTime(FormatStyle.MEDIUM)
        .withZone(ZoneId.systemDefault())
    return formatter.format(instant)
}

private fun AO3Error.displayMessage(): String {
    return when (this) {
        AO3Error.BadRequest -> "AO3 rejected the request."
        AO3Error.AuthenticationRequired -> "AO3 requires login for this work."
        AO3Error.Forbidden -> "AO3 denied access to this work."
        AO3Error.NotFound -> "AO3 could not find this work."
        is AO3Error.Http -> "AO3 returned HTTP $statusCode."
        is AO3Error.Network -> message
        is AO3Error.Overloaded -> "AO3 is busy. Try again shortly."
        is AO3Error.Parse -> message
        is AO3Error.RateLimited -> "AO3 is rate-limiting requests. Try again shortly."
        is AO3Error.Server -> "AO3 had a server problem (HTTP $statusCode)."
        is AO3Error.Validation -> message
    }
}

/**
 * Map work-page tag/stats metadata into a remote summary so Download / Save /
 * AO3 actions work when only a raw work id is known. Title/author/summary are
 * not available from [AO3WorkMetadata] yet.
 */
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
