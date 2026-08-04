package io.github.cidy02.kudos.browse

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.FilterList
import androidx.compose.material.icons.outlined.UnfoldLess
import androidx.compose.material.icons.outlined.UnfoldMore
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3SearchRepository
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.search.SearchFilterSheet
import io.github.cidy02.kudos.search.activeFilterChips
import io.github.cidy02.kudos.search.collectLocalTagSuggestions
import io.github.cidy02.kudos.ui.components.AO3WorkCard
import io.github.cidy02.kudos.ui.components.EmptyStateCard
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

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun TagWorksScreen(
    tagName: String,
    workRepository: WorkRepository,
    onOpenWork: (AO3WorkSummary) -> Unit,
    workImporter: WorkImporter? = null,
    readingQueueRepository: ReadingQueueRepository? = null,
    repository: AO3SearchRepository = remember { AO3SearchRepository() }
) {
    var state by remember(tagName) { mutableStateOf<TagWorksState>(TagWorksState.Loading) }
    var filters by remember { mutableStateOf(AO3SearchFilters()) }
    var refine by remember { mutableStateOf("") }
    var showFilterSheet by remember { mutableStateOf(false) }
    var expandAllCards by remember { mutableStateOf(false) }
    val selection = rememberRemoteWorkSelection()
    var bulkBusy by remember { mutableStateOf(false) }
    var bulkStatus by remember { mutableStateOf<String?>(null) }
    
    var loadGeneration by remember(tagName) { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    val savedWorks by workRepository.observeSavedWorks().collectAsState(initial = emptyList())
    var userTagNames by remember { mutableStateOf<List<String>>(emptyList()) }
    LaunchedEffect(workRepository) {
        userTagNames = workRepository.allUserTags().map { it.normalizedName }
    }
    val localTagSuggestions = remember(savedWorks, userTagNames) {
        collectLocalTagSuggestions(savedWorks, userTagNames)
    }
    val savedByUrl = remember(savedWorks) { BrowseLocalIndicators.index(savedWorks) }
    val activeChips = remember(filters) { activeFilterChips(filters) }

    fun load(page: Int = 1) {
        state = TagWorksState.Loading
        val generation = ++loadGeneration
        scope.launch {
            // General "tag works" uses the query-free additionalTags field in AO3 search
            // (or query "tag:TagName" if we wanted to be broad, but Apple usually
            // pins to a specific tag field).
            val searchFilters = filters.copy(additionalTags = tagName)
            val result = when (val result = repository.search(searchFilters, page)) {
                is AO3Result.Success -> TagWorksState.Loaded(result.value)
                is AO3Result.Failure -> TagWorksState.Error(result.error.toString(), page)
            }
            if (generation == loadGeneration) state = result
        }
    }

    LaunchedEffect(tagName, filters) { load() }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        KudosScreenHeader(
            title = tagName,
            subtitle = "AO3 works for this tag.",
            trailing = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { showFilterSheet = true }) {
                        BadgedBox(
                            badge = {
                                if (activeChips.isNotEmpty()) {
                                    androidx.compose.material3.Badge {
                                        Text(activeChips.size.toString())
                                    }
                                }
                            }
                        ) {
                            Icon(Icons.Outlined.FilterList, contentDescription = "Filters")
                        }
                    }
                    if (workImporter != null) {
                        IconButton(onClick = { if (selection.isSelecting) selection.exit() else selection.enter() }) {
                            Icon(
                                imageVector = Icons.Outlined.Checklist,
                                contentDescription = if (selection.isSelecting) "Exit selection" else "Select works"
                            )
                        }
                    }
                    IconButton(onClick = { expandAllCards = !expandAllCards }) {
                        Icon(
                            imageVector = if (expandAllCards) Icons.Outlined.UnfoldLess else Icons.Outlined.UnfoldMore,
                            contentDescription = if (expandAllCards) "Collapse all" else "Expand all"
                        )
                    }
                }
            }
        )

        OutlinedTextField(
            value = refine,
            onValueChange = { refine = it },
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text("Refine results") },
            singleLine = true,
            trailingIcon = {
                if (refine.isNotEmpty()) {
                    IconButton(onClick = { refine = "" }) {
                        Icon(Icons.Default.Clear, "Clear")
                    }
                }
            }
        )

        when (val current = state) {
            TagWorksState.Loading -> LoadingStateCard("Loading works")
            is TagWorksState.Error -> ErrorBlock(message = current.message, onRetry = { load(current.page) })
            is TagWorksState.Loaded -> {
                val filteredWorks = if (refine.isBlank()) {
                    current.page.works
                } else {
                    val terms = io.github.cidy02.kudos.works.WorkSearchIndex.terms(refine)
                    current.page.works.filter { work ->
                        val haystack = io.github.cidy02.kudos.works.WorkSearchIndex.normalize(
                            work.title + " " + work.authorText + " " + work.fandoms.joinToString(" ") + " " + work.freeforms.joinToString(" ")
                        )
                        terms.all { haystack.contains(it) }
                    }
                }

                if (filteredWorks.isEmpty() && current.page.works.isNotEmpty()) {
                    EmptyStateCard(
                        title = "No matches",
                        message = "No works on this page match your refinement.",
                        primaryActionLabel = "Clear refine",
                        onPrimaryAction = { refine = "" }
                    )
                } else if (current.page.works.isEmpty()) {
                    EmptyStateCard(
                        title = "No works found",
                        message = "AO3 returned no works for this tag."
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
                        items(filteredWorks, key = { it.id }) { work ->
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
                                AO3WorkCard(
                                    work = work,
                                    onOpenWork = onOpenWork,
                                    expandAll = expandAllCards
                                )
                            }
                        }
                        item {
                            TagPaginationRow(page = current.page, onPage = { load(it) })
                        }
                    }

                    if (selection.isSelecting && workImporter != null) {
                        RemoteWorkSelectionBar(
                            state = selection,
                            busy = bulkBusy,
                            onSaveToLibrary = {
                                val picked = selection.selectedIn(filteredWorks)
                                scope.launch {
                                    bulkBusy = true
                                    bulkStatus = RemoteWorkBulkActions.saveToLibrary(picked, workImporter)
                                    bulkBusy = false
                                    selection.exit()
                                }
                            },
                            onSaveForLater = {
                                val queues = readingQueueRepository ?: return@RemoteWorkSelectionBar
                                val picked = selection.selectedIn(filteredWorks)
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

    if (showFilterSheet) {
        SearchFilterSheet(
            filters = filters,
            onFiltersChange = { filters = it },
            onApply = { showFilterSheet = false },
            onClear = { filters = AO3SearchFilters() },
            onDismiss = { showFilterSheet = false },
            localTagSuggestions = localTagSuggestions
        )
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
private fun TagPaginationRow(page: AO3SearchPage, onPage: (Int) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        OutlinedButton(enabled = page.currentPage > 1, onClick = { onPage(page.currentPage - 1) }) {
            Text("Previous")
        }
        Text(
            text = "Page ${page.currentPage} of ${page.totalPages}",
            style = MaterialTheme.typography.labelLarge,
            modifier = Modifier.padding(top = 12.dp)
        )
        OutlinedButton(enabled = page.currentPage < page.totalPages, onClick = { onPage(page.currentPage + 1) }) {
            Text("Next")
        }
    }
}

@Composable
private fun ErrorBlock(message: String, onRetry: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(message, color = MaterialTheme.colorScheme.error)
        OutlinedButton(onClick = onRetry) { Text("Retry") }
    }
}

private sealed interface TagWorksState {
    data object Loading : TagWorksState
    data class Loaded(val page: AO3SearchPage) : TagWorksState
    data class Error(val message: String, val page: Int) : TagWorksState
}
