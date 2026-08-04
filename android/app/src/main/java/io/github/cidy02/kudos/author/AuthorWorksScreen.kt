package io.github.cidy02.kudos.author

import androidx.compose.material3.IconButton
import androidx.compose.material3.Icon
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.Icons
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.browse.BrowseLocalIndicator
import io.github.cidy02.kudos.browse.BrowseLocalIndicators
import io.github.cidy02.kudos.browse.browseMessage
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorWorksRepository
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.ui.components.AO3WorkCard
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.KudosScreenHeader
import io.github.cidy02.kudos.ui.components.KudosSectionHeader
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.components.MetadataChipRow
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.works.WorkImporter
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.ui.components.rememberRemoteWorkSelection
import io.github.cidy02.kudos.ui.components.SelectableRemoteWorkRow
import io.github.cidy02.kudos.ui.components.RemoteWorkSelectionBar
import io.github.cidy02.kudos.ui.components.RemoteWorkBulkActions
import kotlinx.coroutines.launch

/**
 * Simple MD3 author works list: AO3 search by creator + [AO3WorkCard] results.
 */
@Composable
fun AuthorWorksScreen(
    authorName: String,
    workRepository: WorkRepository,
    onOpenWork: (AO3WorkSummary) -> Unit,
    workImporter: WorkImporter? = null,
    readingQueueRepository: ReadingQueueRepository? = null,
    repository: AO3AuthorWorksRepository = remember { AO3AuthorWorksRepository() }
) {
    var state by remember(authorName) { mutableStateOf<AuthorWorksState>(AuthorWorksState.Loading) }
    // Guards a fast Previous/Next double-tap from letting the first (older) page's
    // response land after the second (newer) one and overwrite it.
    var loadGeneration by remember(authorName) { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    val savedWorks by workRepository.observeSavedWorks().collectAsState(initial = emptyList())
    val savedByUrl = remember(savedWorks) { BrowseLocalIndicators.index(savedWorks) }
    val selection = rememberRemoteWorkSelection()
    var bulkBusy by remember { mutableStateOf(false) }
    var bulkStatus by remember { mutableStateOf<String?>(null) }

    fun load(page: Int = 1) {
        state = AuthorWorksState.Loading
        val generation = ++loadGeneration
        scope.launch {
            val result = when (val result = repository.worksForAuthor(authorName, page)) {
                is AO3Result.Success -> AuthorWorksState.Loaded(result.value)
                is AO3Result.Failure -> AuthorWorksState.Error(result.error.browseMessage(), page)
            }
            if (generation == loadGeneration) state = result
        }
    }

    LaunchedEffect(authorName) { load() }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        KudosScreenHeader(
            title = authorName,
            subtitle = "Works by this author on AO3.",
            trailing = if (workImporter == null) null else {
                {
                    IconButton(
                        onClick = { if (selection.isSelecting) selection.exit() else selection.enter() }
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.Checklist,
                            contentDescription = if (selection.isSelecting) "Exit selection" else "Select works"
                        )
                    }
                }
            }
        )

        when (val current = state) {
            AuthorWorksState.Loading -> LoadingStateCard("Loading author works")
            is AuthorWorksState.Error -> ErrorStateCard(
                title = "Author works failed",
                message = current.message,
                primaryActionLabel = "Retry",
                onPrimaryAction = { load(current.page) }
            )
            is AuthorWorksState.Loaded -> {
                if (current.page.works.isEmpty()) {
                    EmptyStateCard(
                        title = "No works found",
                        message = "AO3 returned no works for this author."
                    )
                } else {
                    LazyColumn(
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        // weight(fill = false) so the selection bar below keeps its
                        // space when selecting, without stretching the list otherwise.
                        modifier = Modifier
                            .fillMaxWidth()
                            .weight(1f, fill = false)
                    ) {
                        item {
                            KudosSectionHeader(
                                title = "Works",
                                subtitle = "Page ${current.page.currentPage} of ${current.page.totalPages}"
                            )
                        }
                        items(current.page.works, key = { it.id }) { work ->
                            if (selection.isSelecting) {
                                SelectableRemoteWorkRow(
                                    work = work,
                                    selected = selection.isSelected(work.id),
                                    onToggle = { selection.toggle(work.id) }
                                )
                                return@items
                            }
                            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                LocalIndicatorRow(BrowseLocalIndicators.forWork(work, savedByUrl))
                                AO3WorkCard(work = work, onOpenWork = onOpenWork)
                            }
                        }
                        item {
                            PaginationRow(page = current.page, onPage = { load(it) })
                        }
                    }

                    if (selection.isSelecting && workImporter != null) {
                        RemoteWorkSelectionBar(
                            state = selection,
                            busy = bulkBusy,
                            onSaveToLibrary = {
                                val picked = selection.selectedIn(current.page.works)
                                scope.launch {
                                    bulkBusy = true
                                    bulkStatus = RemoteWorkBulkActions.saveToLibrary(picked, workImporter)
                                    bulkBusy = false
                                    selection.exit()
                                }
                            },
                            onSaveForLater = {
                                val queues = readingQueueRepository ?: return@RemoteWorkSelectionBar
                                val picked = selection.selectedIn(current.page.works)
                                scope.launch {
                                    bulkBusy = true
                                    bulkStatus = RemoteWorkBulkActions.saveForLater(picked, workImporter, queues)
                                    bulkBusy = false
                                    selection.exit()
                                }
                            }
                        )
                    }

                }
            }
        }
    }

    bulkStatus?.let { message ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { bulkStatus = null },
            title = { Text("Selection") },
            text = { Text(message) },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = { bulkStatus = null }) { Text("OK") }
            }
        )
    }
}

@Composable
private fun LocalIndicatorRow(indicator: BrowseLocalIndicator) {
    if (!indicator.any) return
    val labels = buildList {
        if (indicator.isSaved) add("Saved")
        if (indicator.hasEpub) add("Downloaded")
        if (indicator.isFavorite) add("Favorite")
        if (indicator.isFinished) add("Finished")
    }
    MetadataChipRow(labels = labels, prominent = true)
}

@Composable
private fun PaginationRow(page: AO3SearchPage, onPage: (Int) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        OutlinedButton(enabled = page.currentPage > 1, onClick = { onPage(page.currentPage - 1) }) {
            Text("Previous")
        }
        Text(
            text = "Page ${page.currentPage} of ${page.totalPages}",
            style = MaterialTheme.typography.labelLarge,
            modifier = Modifier.padding(top = 12.dp)
        )
        OutlinedButton(
            enabled = page.currentPage < page.totalPages,
            onClick = { onPage(page.currentPage + 1) }
        ) {
            Text("Next")
        }
    }
}

private sealed interface AuthorWorksState {
    data object Loading : AuthorWorksState
    data class Loaded(val page: AO3SearchPage) : AuthorWorksState
    data class Error(val message: String, val page: Int) : AuthorWorksState
}
