package io.github.cidy02.kudos.works

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.Tag
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.AO3URLResolver
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadata
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataRepository
import io.github.cidy02.kudos.network.ao3.writes.AO3BookmarkInput
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteOutcome
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.components.MetadataChipRow
import io.github.cidy02.kudos.ui.components.StatusBadge
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
    metadataRepository: AO3WorkMetadataRepository? = null,
    onLogin: () -> Unit,
    onOpenComments: (Long) -> Unit,
    onOpenReader: (String) -> Unit
) {
    var state by remember(source) { mutableStateOf(WorkDetailUiState()) }
    var newTagName by remember { mutableStateOf("") }
    var newCollectionName by remember { mutableStateOf("") }
    var confirmRemove by remember { mutableStateOf(false) }
    var bookmarkDialog by remember { mutableStateOf(false) }
    var bookmarkNotes by remember { mutableStateOf("") }
    var bookmarkTags by remember { mutableStateOf("") }
    var bookmarkPrivate by remember { mutableStateOf(false) }
    var bookmarkRecommendation by remember { mutableStateOf(false) }
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

    fun ensureLocalThen(action: suspend (SavedWork) -> Unit) {
        val local = state.local
        if (local != null) {
            runWorkAction { action(local) }
            return
        }
        val remote = state.remote ?: return
        runWorkAction {
            when (val result = workImporter.saveMetadataOnly(remote)) {
                is WorkImportResult.Failure -> state = state.copy(error = result.error.displayMessage())
                is WorkImportResult.Success -> action(result.work)
            }
        }
    }

    fun handleWriteResult(result: AO3Result<AO3WriteOutcome>) {
        state = when (result) {
            is AO3Result.Success -> state.copy(ao3Message = result.value.message)
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
            onDismissRequest = { bookmarkDialog = false },
            title = { Text("AO3 Bookmark") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = bookmarkNotes,
                        onValueChange = { bookmarkNotes = it },
                        label = { Text("Notes") },
                        minLines = 3
                    )
                    OutlinedTextField(
                        value = bookmarkTags,
                        onValueChange = { bookmarkTags = it },
                        label = { Text("Tags, comma-separated") },
                        singleLine = true
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Checkbox(checked = bookmarkPrivate, onCheckedChange = { bookmarkPrivate = it })
                        Text("Private")
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Checkbox(
                            checked = bookmarkRecommendation,
                            onCheckedChange = { bookmarkRecommendation = it }
                        )
                        Text("Recommendation")
                    }
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        bookmarkDialog = false
                        val input = AO3BookmarkInput(
                            notes = bookmarkNotes,
                            tags = bookmarkTags,
                            isPrivate = bookmarkPrivate,
                            isRecommendation = bookmarkRecommendation
                        )
                        runAo3Write { writeRepository.createBookmark(it, input) }
                    }
                ) {
                    Text("Create")
                }
            },
            dismissButton = {
                TextButton(onClick = { bookmarkDialog = false }) { Text("Cancel") }
            }
        )
    }

    WorkDetailContent(
        state = state,
        newTagName = newTagName,
        onNewTagName = { newTagName = it },
        newCollectionName = newCollectionName,
        onNewCollectionName = { newCollectionName = it },
        onSave = ::saveMetadataOnly,
        onDownload = ::download,
        onToggleFavorite = {
            ensureLocalThen { work ->
                val updated = workRepository.toggleFavorite(work.id)
                if (updated != null) refreshLocal(updated.id, state.remote)
            }
        },
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
        onAddCollection = {
            ensureLocalThen { work ->
                if (newCollectionName.isNotBlank()) {
                    val collections = workRepository.addToCollection(work.id, newCollectionName)
                    newCollectionName = ""
                    state = state.copy(local = workRepository.getWork(work.id), collections = collections)
                }
            }
        },
        onRemoveCollection = { collection ->
            val work = state.local ?: return@WorkDetailContent
            runWorkAction {
                val collections = workRepository.removeFromCollection(work.id, collection.id)
                state = state.copy(collections = collections)
            }
        },
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
        onKudos = {
            runAo3Write { writeRepository.giveKudos(it) }
        },
        onSubscribe = {
            runAo3Write { writeRepository.toggleSubscribe(it) }
        },
        onMarkForLater = {
            runAo3Write { writeRepository.markForLater(it) }
        },
        onAddToSavedForLater = {
            ensureLocalThen { work ->
                if (state.inSavedForLater) {
                    readingQueueRepository.removeFromSavedForLater(work.id)
                } else {
                    readingQueueRepository.addToSavedForLater(work.id)
                }
                refreshLocal(work.id, state.remote)
            }
        },
        onBookmark = { bookmarkDialog = true },
        onComments = {
            state.ao3WorkId?.let(onOpenComments)
                ?: run { state = state.copy(error = "This action needs a canonical AO3 work URL.") }
        },
        onOpenReader = onOpenReader
    )
}

@Composable
private fun WorkDetailContent(
    state: WorkDetailUiState,
    newTagName: String,
    onNewTagName: (String) -> Unit,
    newCollectionName: String,
    onNewCollectionName: (String) -> Unit,
    onSave: () -> Unit,
    onDownload: () -> Unit,
    onToggleFavorite: () -> Unit,
    onToggleFinished: () -> Unit,
    onAddTag: () -> Unit,
    onRemoveTag: (Tag) -> Unit,
    onAddCollection: () -> Unit,
    onRemoveCollection: (WorkCollection) -> Unit,
    onDeleteEpub: () -> Unit,
    onRemoveFromLibrary: () -> Unit,
    onOpenAo3: () -> Unit,
    onLogin: () -> Unit,
    onKudos: () -> Unit,
    onSubscribe: () -> Unit,
    onMarkForLater: () -> Unit,
    onAddToSavedForLater: () -> Unit,
    onBookmark: () -> Unit,
    onComments: () -> Unit,
    onOpenReader: (String) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        if (state.loading) {
            LoadingStateCard("Loading work details")
        } else {
            Text(
                text = state.title,
                style = MaterialTheme.typography.headlineSmall,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis
            )
            MetadataLine("by ${state.author.ifBlank { "Anonymous" }}")
            StatusLine(state)
            ActionButtons(
                state = state,
                onSave = onSave,
                onDownload = onDownload,
                onToggleFavorite = onToggleFavorite,
                onToggleFinished = onToggleFinished,
                onDeleteEpub = onDeleteEpub,
                onRemoveFromLibrary = onRemoveFromLibrary,
                onOpenAo3 = onOpenAo3,
                onOpenReader = onOpenReader,
                onAddToSavedForLater = onAddToSavedForLater,
                onLogin = onLogin,
                onKudos = onKudos,
                onSubscribe = onSubscribe,
                onMarkForLater = onMarkForLater,
                onBookmark = onBookmark,
                onComments = onComments
            )

            state.error?.let {
                ErrorStateCard(
                    title = "Work action failed",
                    message = it
                )
            }
            state.ao3Message?.let {
                StatusBadge(it)
            }

            SectionBlock("Summary") {
                if (state.summary.isNotBlank()) Text(state.summary) else MetadataLine("No summary available.")
            }
            SectionBlock("Details") {
                MetadataChipRow(labels = state.fandoms, maxItems = 6, prominent = true)
                MetadataChipRow(
                    labels = (listOf(state.rating) + state.warnings + state.categories)
                        .filter { it.isNotBlank() },
                    maxItems = 8
                )
                MetadataLine(state.completionLabel)
                MetadataLine(state.language.takeIf { it.isNotBlank() }?.let { "Language: $it" }.orEmpty())
                MetadataChipRow(labels = state.statsLabels)
                MetadataLine(state.seriesLine)
                MetadataLine(state.sourceUrl)
            }
            TagSection("Relationships", state.relationships)
            TagSection("Characters", state.characters)
            TagSection("Additional Tags", state.freeforms)
            LocalTagEditor(
                tags = state.userTags,
                newTagName = newTagName,
                onNewTagName = onNewTagName,
                enabled = !state.working,
                onAdd = onAddTag,
                onRemove = onRemoveTag
            )
            CollectionEditor(
                collections = state.collections,
                newCollectionName = newCollectionName,
                onNewCollectionName = onNewCollectionName,
                enabled = !state.working,
                onAdd = onAddCollection,
                onRemove = onRemoveCollection
            )
        }
    }
}

@Composable
private fun StatusLine(state: WorkDetailUiState) {
    val labels = listOfNotNull(
        if (state.local?.isSaved == true) "Saved" else null,
        if (state.local?.hasEpub == true) "Downloaded" else "Metadata only",
        if (state.local?.isFavorite == true) "Favorite" else null,
        if (state.local?.isFinished == true) "Finished" else null,
        if (state.inSavedForLater) "Saved for Later" else null
    )
    MetadataChipRow(labels = labels, prominent = true)
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ActionButtons(
    state: WorkDetailUiState,
    onSave: () -> Unit,
    onDownload: () -> Unit,
    onToggleFavorite: () -> Unit,
    onToggleFinished: () -> Unit,
    onDeleteEpub: () -> Unit,
    onRemoveFromLibrary: () -> Unit,
    onOpenAo3: () -> Unit,
    onOpenReader: (String) -> Unit,
    onAddToSavedForLater: () -> Unit,
    onLogin: () -> Unit,
    onKudos: () -> Unit,
    onSubscribe: () -> Unit,
    onMarkForLater: () -> Unit,
    onBookmark: () -> Unit,
    onComments: () -> Unit
) {
    val busy = state.working
    val local = state.local
    val epubWorkId = local?.takeIf { it.hasEpub }?.id
    val hasEpub = epubWorkId != null
    val isSaved = local?.isSaved == true
    val canDownload = !busy && (state.remote != null || local != null)
    val canRead = !busy && epubWorkId != null
    val showSaveToLibrary = !isSaved && state.remote != null
    val ao3Enabled = !busy && state.ao3WorkId != null
    val dangerColor = MaterialTheme.colorScheme.error

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        // 1. Primary open / download / save
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            if (epubWorkId != null) {
                Button(
                    enabled = canRead,
                    onClick = { onOpenReader(epubWorkId) },
                    modifier = Modifier.weight(1f)
                ) {
                    Text("Read")
                }
            } else {
                Button(
                    enabled = canDownload,
                    onClick = onDownload,
                    modifier = Modifier.weight(1f)
                ) {
                    Text("Download EPUB")
                }
                if (showSaveToLibrary) {
                    FilledTonalButton(
                        enabled = !busy,
                        onClick = onSave,
                        modifier = Modifier.weight(1f)
                    ) {
                        Text("Save to Library")
                    }
                }
            }
        }
        // Saved-but-no-epub already covered; hasEpub + unsaved is rare (history-only) —
        // still offer Save when a remote blurb is available.
        if (hasEpub && showSaveToLibrary) {
            FilledTonalButton(
                enabled = !busy,
                onClick = onSave,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Save to Library")
            }
        }

        // 2. Local library toggles + open on web
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            OutlinedButton(enabled = !busy, onClick = onToggleFavorite) {
                Text(if (local?.isFavorite == true) "Unfavorite" else "Favorite")
            }
            OutlinedButton(enabled = !busy, onClick = onToggleFinished) {
                Text(if (local?.isFinished == true) "Mark Unfinished" else "Mark Finished")
            }
            OutlinedButton(enabled = !busy, onClick = onAddToSavedForLater) {
                Text(if (state.inSavedForLater) "Remove Saved for Later" else "Saved for Later")
            }
            OutlinedButton(enabled = state.sourceUrl.isNotBlank(), onClick = onOpenAo3) {
                Text("Open on AO3")
            }
            if (hasEpub) {
                // Secondary redownload; primary CTA stays Read.
                OutlinedButton(enabled = canDownload, onClick = onDownload) {
                    Text("Redownload")
                }
            }
        }

        // 3. AO3 account actions
        Text(
            text = "On AO3",
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        if (state.ao3WorkId == null) {
            MetadataLine("AO3 social actions need a canonical work URL.")
        }
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            AssistChip(
                enabled = ao3Enabled,
                onClick = onKudos,
                label = { Text("Kudos") }
            )
            AssistChip(
                enabled = ao3Enabled,
                onClick = onSubscribe,
                label = { Text("Subscribe") }
            )
            AssistChip(
                enabled = ao3Enabled,
                onClick = onMarkForLater,
                label = { Text("Mark for Later") }
            )
            AssistChip(
                enabled = ao3Enabled,
                onClick = onBookmark,
                label = { Text("Bookmark") }
            )
            AssistChip(
                enabled = ao3Enabled,
                onClick = onComments,
                label = { Text("Comments") }
            )
            AssistChip(
                onClick = onLogin,
                label = { Text("Log in to AO3") }
            )
        }

        // 4. Danger zone — destructive last
        if (local != null) {
            Text(
                text = "Danger zone",
                style = MaterialTheme.typography.titleSmall,
                color = dangerColor
            )
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                if (hasEpub) {
                    TextButton(
                        enabled = !busy,
                        onClick = onDeleteEpub
                    ) {
                        Text("Delete EPUB", color = dangerColor)
                    }
                }
                TextButton(
                    enabled = !busy,
                    onClick = onRemoveFromLibrary
                ) {
                    Text("Remove from Library", color = dangerColor)
                }
            }
        }
    }
}

@Composable
private fun LocalTagEditor(
    tags: List<Tag>,
    newTagName: String,
    onNewTagName: (String) -> Unit,
    enabled: Boolean,
    onAdd: () -> Unit,
    onRemove: (Tag) -> Unit
) {
    SectionBlock("User Tags") {
        if (tags.isEmpty()) MetadataLine("No user tags.")
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            tags.forEach { tag ->
                OutlinedButton(enabled = enabled, onClick = { onRemove(tag) }) {
                    Text(tag.normalizedName)
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            OutlinedTextField(
                value = newTagName,
                onValueChange = onNewTagName,
                label = { Text("Add tag") },
                singleLine = true,
                modifier = Modifier.weight(1f)
            )
            Button(enabled = enabled && newTagName.isNotBlank(), onClick = onAdd) {
                Text("Add")
            }
        }
    }
}

@Composable
private fun CollectionEditor(
    collections: List<WorkCollection>,
    newCollectionName: String,
    onNewCollectionName: (String) -> Unit,
    enabled: Boolean,
    onAdd: () -> Unit,
    onRemove: (WorkCollection) -> Unit
) {
    SectionBlock("Collections") {
        if (collections.isEmpty()) MetadataLine("No collections.")
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            collections.forEach { collection ->
                OutlinedButton(enabled = enabled, onClick = { onRemove(collection) }) {
                    Text(collection.name)
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            OutlinedTextField(
                value = newCollectionName,
                onValueChange = onNewCollectionName,
                label = { Text("Add collection") },
                singleLine = true,
                modifier = Modifier.weight(1f)
            )
            Button(enabled = enabled && newCollectionName.isNotBlank(), onClick = onAdd) {
                Text("Add")
            }
        }
    }
}

@Composable
private fun TagSection(title: String, tags: List<String>) {
    if (tags.isEmpty()) return
    SectionBlock(title) {
        MetadataChipRow(labels = tags, maxItems = 24)
    }
}

@Composable
private fun SectionBlock(title: String, content: @Composable () -> Unit) {
    HorizontalDivider()
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(text = title, style = MaterialTheme.typography.titleMedium)
        content()
    }
}

@Composable
private fun MetadataLine(text: String) {
    if (text.isBlank()) return
    Text(
        text = text,
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
}

private data class WorkDetailUiState(
    val local: SavedWork? = null,
    val remote: AO3WorkSummary? = null,
    val userTags: List<Tag> = emptyList(),
    val collections: List<WorkCollection> = emptyList(),
    val inSavedForLater: Boolean = false,
    val loading: Boolean = false,
    val working: Boolean = false,
    val error: String? = null,
    val ao3Message: String? = null
) {
    val title: String = local?.title ?: remote?.title ?: "Work"
    val author: String = local?.author ?: remote?.authorText ?: ""
    val summary: String = local?.summary ?: remote?.summary ?: ""
    val sourceUrl: String = local?.sourceUrl ?: remote?.workUrl ?: ""
    val ao3WorkId: Long? = WorkTags.ao3WorkIdFromUrl(sourceUrl)
    val fandoms: List<String> = local?.workFandoms?.takeIf { it.isNotEmpty() } ?: remote?.fandoms.orEmpty()
    val rating: String = local?.rating ?: remote?.rating ?: ""
    val warnings: List<String> = local?.workWarnings?.takeIf { it.isNotEmpty() } ?: remote?.warnings.orEmpty()
    val categories: List<String> = local?.workCategories?.takeIf { it.isNotEmpty() } ?: remote?.categories.orEmpty()
    val relationships: List<String> = local?.workRelationships?.takeIf { it.isNotEmpty() } ?: remote?.relationships.orEmpty()
    val characters: List<String> = local?.workCharacters?.takeIf { it.isNotEmpty() } ?: remote?.characters.orEmpty()
    val freeforms: List<String> = local?.workFreeforms?.takeIf { it.isNotEmpty() } ?: remote?.freeforms.orEmpty()
    val language: String = local?.language ?: remote?.language ?: ""
    val completionLabel: String = when (local?.isComplete ?: remote?.isComplete) {
        true -> "Complete"
        false -> "Work in Progress"
        null -> ""
    }
    val statsLabels: List<String> = listOfNotNull(
        (local?.wordCount?.takeIf { it > 0 } ?: remote?.wordCount)?.let { "%,d words".format(it) },
        (local?.chapters?.takeIf { it.isNotBlank() } ?: remote?.chapters)?.let { "$it chapters" },
        (local?.kudos?.takeIf { it > 0 } ?: remote?.kudos)?.let { "%,d kudos".format(it) },
        (local?.comments ?: remote?.comments)?.let { "%,d comments".format(it) },
        (local?.hits ?: remote?.hits)?.let { "%,d hits".format(it) }
    )
    val seriesLine: String = local?.seriesTitle?.takeIf { it.isNotBlank() }?.let { title ->
        "Series: $title" + local.seriesPosition.takeIf { it > 0 }?.let { " #$it" }.orEmpty()
    } ?: remote?.seriesTitle?.let { title ->
        "Series: $title" + remote.seriesPosition?.let { " #$it" }.orEmpty()
    }.orEmpty()
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
