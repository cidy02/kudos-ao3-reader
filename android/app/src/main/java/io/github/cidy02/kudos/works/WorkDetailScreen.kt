package io.github.cidy02.kudos.works

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
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
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import kotlinx.coroutines.launch

@Composable
fun WorkDetailScreen(
    source: WorkDetailSource?,
    workRepository: WorkRepository,
    workImporter: WorkImporter,
    onOpenReader: (String) -> Unit
) {
    var state by remember(source) { mutableStateOf(WorkDetailUiState()) }
    var newTagName by remember { mutableStateOf("") }
    var newCollectionName by remember { mutableStateOf("") }
    var confirmRemove by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val uriHandler = LocalUriHandler.current

    suspend fun refreshLocal(workId: String, remote: AO3WorkSummary? = state.remote) {
        val local = workRepository.getWork(workId)
        state = state.copy(
            local = local,
            remote = remote,
            userTags = local?.let { workRepository.userTagsForWork(it.id) }.orEmpty(),
            collections = local?.let { workRepository.collectionsForWork(it.id) }.orEmpty(),
            loading = false
        )
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
                        loading = false
                    )
                } else {
                    WorkDetailUiState(remote = source.summary, loading = false)
                }
            }
            is WorkDetailSource.Ao3WorkId -> state = WorkDetailUiState(
                loading = false,
                error = "Direct AO3 work-id hydration is deferred until full Work Detail parsing."
            )
            is WorkDetailSource.RemoteUrl -> state = WorkDetailUiState(
                loading = false,
                error = "Direct AO3 URL hydration is deferred until full Work Detail parsing."
            )
            null -> state = WorkDetailUiState(
                loading = false,
                error = "Open a work from Search or Library."
            )
        }
    }

    fun runWorkAction(block: suspend () -> Unit) {
        scope.launch {
            state = state.copy(working = true, error = null)
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

    fun download() {
        runWorkAction {
            val result = state.remote?.let { workImporter.download(it) }
                ?: state.local?.let { workImporter.downloadExisting(it) }
                ?: WorkImportResult.Failure(null, AO3Error.Validation("No work selected."))
            when (result) {
                is WorkImportResult.Failure -> state = state.copy(
                    local = result.work ?: state.local,
                    error = result.error.displayMessage()
                )
                is WorkImportResult.Success -> refreshLocal(result.work.id, state.remote)
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

    if (confirmRemove) {
        AlertDialog(
            onDismissRequest = { confirmRemove = false },
            title = { Text("Remove from Library") },
            text = { Text("This removes the local record and deletes the downloaded EPUB file if present.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        val workId = state.local?.id ?: return@TextButton
                        confirmRemove = false
                        runWorkAction {
                            workRepository.removeFromLibrary(workId)
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
            CircularProgressIndicator()
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
                onOpenReader = onOpenReader
            )

            state.error?.let {
                Text(text = it, color = MaterialTheme.colorScheme.error)
            }

            SectionBlock("Summary") {
                if (state.summary.isNotBlank()) Text(state.summary) else MetadataLine("No summary available.")
            }
            SectionBlock("Details") {
                MetadataLine(state.fandoms.joinToString(", "))
                MetadataLine(
                    (listOf(state.rating) + state.warnings + state.categories)
                        .filter { it.isNotBlank() }
                        .joinToString(" - ")
                )
                MetadataLine(state.completionLabel)
                MetadataLine(state.language.takeIf { it.isNotBlank() }?.let { "Language: $it" }.orEmpty())
                MetadataLine(state.statsLine)
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
            SectionBlock("AO3 Actions") {
                DisabledActions()
            }
        }
    }
}

@Composable
private fun StatusLine(state: WorkDetailUiState) {
    val labels = listOfNotNull(
        if (state.local?.isSaved == true) "Saved" else null,
        if (state.local?.hasEpub == true) "Downloaded" else "Metadata only",
        if (state.local?.isFavorite == true) "Favorite" else null,
        if (state.local?.isFinished == true) "Finished" else null
    )
    MetadataLine(labels.joinToString(" - "))
}

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
    onOpenReader: (String) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            OutlinedButton(
                enabled = !state.working && state.local?.hasEpub == true,
                onClick = { state.local?.id?.let(onOpenReader) },
                modifier = Modifier.weight(1f)
            ) {
                Text("Read")
            }
            Button(enabled = !state.working, onClick = onDownload, modifier = Modifier.weight(1f)) {
                Text(if (state.local?.hasEpub == true) "Redownload" else "Download")
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            OutlinedButton(enabled = !state.working, onClick = onSave, modifier = Modifier.weight(1f)) {
                Text(if (state.local?.isSaved == true) "Saved" else "Save")
            }
            OutlinedButton(enabled = !state.working, onClick = onToggleFavorite, modifier = Modifier.weight(1f)) {
                Text(if (state.local?.isFavorite == true) "Unfavorite" else "Favorite")
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            OutlinedButton(enabled = !state.working, onClick = onToggleFinished, modifier = Modifier.weight(1f)) {
                Text(if (state.local?.isFinished == true) "Mark Unfinished" else "Mark Finished")
            }
            OutlinedButton(enabled = state.sourceUrl.isNotBlank(), onClick = onOpenAo3, modifier = Modifier.weight(1f)) {
                Text("Open on AO3")
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            OutlinedButton(
                enabled = !state.working && state.local?.hasEpub == true,
                onClick = onDeleteEpub,
                modifier = Modifier.weight(1f)
            ) {
                Text("Delete EPUB")
            }
            OutlinedButton(
                enabled = !state.working && state.local != null,
                onClick = onRemoveFromLibrary,
                modifier = Modifier.weight(1f)
            ) {
                Text("Remove")
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
private fun DisabledActions() {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        listOf("Kudos", "Subscribe", "Mark for Later", "AO3 Bookmark", "Comment").forEach { label ->
            OutlinedButton(enabled = false, onClick = {}) {
                Text(label)
            }
        }
    }
}

@Composable
private fun TagSection(title: String, tags: List<String>) {
    if (tags.isEmpty()) return
    SectionBlock(title) {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            tags.forEach { tag ->
                OutlinedButton(enabled = false, onClick = {}) {
                    Text(tag)
                }
            }
        }
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
    val loading: Boolean = false,
    val working: Boolean = false,
    val error: String? = null
) {
    val title: String = local?.title ?: remote?.title ?: "Work"
    val author: String = local?.author ?: remote?.authorText ?: ""
    val summary: String = local?.summary ?: remote?.summary ?: ""
    val sourceUrl: String = local?.sourceUrl ?: remote?.workUrl ?: ""
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
    val statsLine: String = listOfNotNull(
        (local?.wordCount?.takeIf { it > 0 } ?: remote?.wordCount)?.let { "%,d words".format(it) },
        (local?.chapters?.takeIf { it.isNotBlank() } ?: remote?.chapters)?.let { "$it chapters" },
        (local?.kudos?.takeIf { it > 0 } ?: remote?.kudos)?.let { "%,d kudos".format(it) },
        (local?.comments ?: remote?.comments)?.let { "%,d comments".format(it) },
        (local?.hits ?: remote?.hits)?.let { "%,d hits".format(it) }
    ).joinToString(" - ")
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
