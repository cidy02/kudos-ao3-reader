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
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.FilterList
import androidx.compose.material.icons.outlined.UnfoldLess
import androidx.compose.material.icons.outlined.UnfoldMore
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.browse.AO3BrowseRepository
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.search.SearchFilterSheet
import io.github.cidy02.kudos.search.activeFilterCount
import io.github.cidy02.kudos.search.collectLocalTagSuggestions
import io.github.cidy02.kudos.ui.components.AO3WorkCard
import io.github.cidy02.kudos.ui.components.KudosPaginationBar
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
import io.github.cidy02.kudos.search.summaryLabels
import io.github.cidy02.kudos.search.SearchResultsHero

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun FandomWorksScreen(
    fandomName: String,
    workRepository: WorkRepository,
    onOpenWork: (AO3WorkSummary) -> Unit,
    workImporter: WorkImporter? = null,
    readingQueueRepository: ReadingQueueRepository? = null,
    repository: AO3BrowseRepository = remember { AO3BrowseRepository() }
) {
    var state by remember(fandomName) { mutableStateOf<FandomWorksState>(FandomWorksState.Loading) }
    var filters by remember { mutableStateOf(AO3SearchFilters()) }
    var showFilterSheet by remember { mutableStateOf(false) }
    var expandAllCards by remember { mutableStateOf(false) }
    val selection = rememberRemoteWorkSelection()
    var bulkBusy by remember { mutableStateOf(false) }
    var bulkStatus by remember { mutableStateOf<String?>(null) }
    
    // Guards a fast Previous/Next double-tap from letting the first (older) page's
    // response land after the second (newer) one and overwrite it.
    var loadGeneration by remember(fandomName) { mutableIntStateOf(0) }
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
    val activeFilters = remember(filters) { activeFilterCount(filters) }
    
    val context = LocalContext.current
    val autocompleteRepository = remember {
        (context.applicationContext as? io.github.cidy02.kudos.KudosApplication)?.container?.tagAutocompleteRepository
    }

    fun load(page: Int = 1) {
        state = FandomWorksState.Loading
        val generation = ++loadGeneration
        scope.launch {
            val result = when (val result = repository.worksForFandom(fandomName, page, filters)) {
                is AO3Result.Success -> FandomWorksState.Loaded(result.value)
                is AO3Result.Failure -> FandomWorksState.Error(result.error.browseMessage(), page)
            }
            if (generation == loadGeneration) state = result
        }
    }

    LaunchedEffect(fandomName, filters) { load() }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // TopAppBar is generic ("Works"); fandom name is useful context.
        KudosScreenHeader(
            title = fandomName,
            subtitle = "AO3 works for this fandom.",
            trailing = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { showFilterSheet = true }) {
                        BadgedBox(
                            badge = {
                                if (activeFilters > 0) {
                                    androidx.compose.material3.Badge {
                                        Text(activeFilters.toString())
                                    }
                                }
                            }
                        ) {
                            Icon(Icons.Outlined.FilterList, contentDescription = "Filters")
                        }
                    }
                    IconButton(onClick = { expandAllCards = !expandAllCards }) {
                        Icon(
                            imageVector = if (expandAllCards) Icons.Outlined.UnfoldLess else Icons.Outlined.UnfoldMore,
                            contentDescription = if (expandAllCards) "Collapse all" else "Expand all"
                        )
                    }
                    if (workImporter != null) {
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
            }
        )

        when (val current = state) {
            FandomWorksState.Loading -> LoadingStateCard("Loading fandom works")
            is FandomWorksState.Error -> BrowseErrorBlock(message = current.message, onRetry = { load(current.page) })
            is FandomWorksState.Loaded -> {
                if (current.page.works.isEmpty()) {
                    EmptyStateCard(
                        title = "No works found",
                        message = "AO3 returned no works for this fandom."
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
                            current.page.summary?.let { summary ->
                                SearchResultsHero(
                                    summary = summary.completing(
                                        subject = fandomName,
                                        page = current.page.currentPage,
                                        onPageCount = current.page.works.size
                                    ),
                                    filterLabels = summaryLabels(filters, excluding = fandomName),
                                    subjectCategory = summary.subjectCategory(current.page.works),
                                    onEditFilters = { showFilterSheet = true },
                                    modifier = Modifier.padding(bottom = 4.dp)
                                )
                            }
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
                            } else {
                                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                    LocalIndicatorRow(BrowseLocalIndicators.forWork(work, savedByUrl))
                                    AO3WorkCard(
                                        work = work,
                                        onOpenWork = onOpenWork,
                                        expandAll = expandAllCards
                                    )
                                }
                            }
                        }
                        item {
                            KudosPaginationBar(
                                currentPage = current.page.currentPage,
                                totalPages = current.page.totalPages,
                                onPageChange = { load(it) }
                            )
                        }
                    }
                }
            }
        }
        if (selection.isSelecting && workImporter != null) {
            RemoteWorkSelectionBar(
                state = selection,
                busy = bulkBusy,
                onSaveToLibrary = {
                    val picked = selection.selectedIn((state as? FandomWorksState.Loaded)?.page?.works.orEmpty())
                    scope.launch {
                        bulkBusy = true
                        bulkStatus = RemoteWorkBulkActions.saveToLibrary(picked, workImporter)
                        bulkBusy = false
                        selection.exit()
                    }
                },
                onSaveForLater = {
                    val queues = readingQueueRepository ?: return@RemoteWorkSelectionBar
                    val picked = selection.selectedIn((state as? FandomWorksState.Loaded)?.page?.works.orEmpty())
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

    if (showFilterSheet) {
        SearchFilterSheet(
            filters = filters,
            onFiltersChange = { filters = it },
            onApply = { showFilterSheet = false },
            onClear = { filters = AO3SearchFilters() },
            onDismiss = { showFilterSheet = false },
            localTagSuggestions = localTagSuggestions,
            autocompleteRepository = autocompleteRepository
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

private sealed interface FandomWorksState {
    data object Loading : FandomWorksState
    data class Loaded(val page: AO3SearchPage) : FandomWorksState
    data class Error(val message: String, val page: Int) : FandomWorksState
}
