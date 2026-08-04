package io.github.cidy02.kudos.search

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.BookmarkAdd
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.FilterList
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.UnfoldLess
import androidx.compose.material.icons.outlined.UnfoldMore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.InputChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.cidy02.kudos.core.model.SavedSearch
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3SearchRepository
import io.github.cidy02.kudos.network.ao3.search.AO3SearchSort
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.ui.components.AO3WorkCard
import io.github.cidy02.kudos.ui.components.DestructiveConfirmation
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.KudosSectionHeader
import io.github.cidy02.kudos.ui.components.KudosPaginationBar
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import kotlinx.coroutines.launch

sealed interface SearchUiState {
    data object Idle : SearchUiState
    data object Loading : SearchUiState
    data class Results(val page: AO3SearchPage, val works: List<io.github.cidy02.kudos.works.CanonicalWork>) : SearchUiState
    data class Error(val error: AO3Error, val page: Int) : SearchUiState
}

@Composable
fun SearchScreen(
    onOpenWork: (AO3WorkSummary) -> Unit,
    repository: AO3SearchRepository = remember { AO3SearchRepository() },
    savedSearchRepository: SavedSearchRepository? = null,
    workRepository: WorkRepository? = null,
    settingsRepository: SettingsRepository? = null
) {
    val viewModel: SearchViewModel = viewModel(
        factory = SearchViewModel.factory(repository, savedSearchRepository, workRepository)
    )
    val settingsState = settingsRepository?.settings?.collectAsState(initial = KudosSettings.Defaults)
    val settings = settingsState?.value ?: KudosSettings.Defaults
    val filters by viewModel.filters.collectAsState()
    val state by viewModel.state.collectAsState()
    val savedSearches by viewModel.savedSearches.collectAsState()
    val localMatches by viewModel.localMatches.collectAsState()
    val selectionMode by viewModel.selectionMode.collectAsState()
    val selectedWorkIds by viewModel.selectedWorkIds.collectAsState()

    var showFilterSheet by remember { mutableStateOf(false) }
    var showSaveDialog by remember { mutableStateOf(false) }
    var saveName by remember { mutableStateOf("") }
    var pendingDeleteSearch by remember { mutableStateOf<SavedSearch?>(null) }
    
    // Batch seed for result cards (Expand all / Collapse all). Individual cards
    // keep their own local expand state after the seed — matching iOS.
    var expandAllCards by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val activeChips = remember(filters) { activeFilterChips(filters) }

    fun commitSavedSearch() {
        val name = saveName.trim()
        if (name.isEmpty()) return
        viewModel.saveCurrentSearch(name)
        showSaveDialog = false
        saveName = ""
    }

    DestructiveConfirmation(
        show = pendingDeleteSearch != null,
        title = "Delete saved search?",
        text = "This will permanently remove “${pendingDeleteSearch?.name}” from your device.",
        confirmBeforeDelete = true, // Always confirm for saved searches
        onConfirm = {
            val id = pendingDeleteSearch?.id ?: return@DestructiveConfirmation
            pendingDeleteSearch = null
            viewModel.deleteSavedSearch(id)
        },
        onDismissRequest = { pendingDeleteSearch = null }
    )

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth()
        ) {
            OutlinedTextField(
                value = filters.query,
                onValueChange = { viewModel.updateFilters(filters.copy(query = it)) },
                label = { Text("Query") },
                singleLine = true,
                modifier = Modifier.weight(1f)
            )
            if (savedSearchRepository != null) {
                IconButton(
                    enabled = filters.isSearchable,
                    onClick = {
                        saveName = defaultSavedSearchName(filters)
                        showSaveDialog = true
                    }
                ) {
                    Icon(
                        imageVector = Icons.Outlined.BookmarkAdd,
                        contentDescription = "Save search"
                    )
                }
            }
            Button(
                enabled = state !is SearchUiState.Loading && filters.isSearchable,
                onClick = { viewModel.runSearch() }
            ) {
                Text("Search")
            }
        }

        SearchControlsRow(
            filters = filters,
            activeChipCount = activeChips.size,
            expandAllCards = expandAllCards,
            selectionMode = selectionMode,
            onToggleExpandAll = { expandAllCards = !expandAllCards },
            onToggleSelectionMode = {
                if (selectionMode) viewModel.exitSelectionMode() else viewModel.enterSelectionMode()
            },
            onSortSelected = {
                viewModel.updateFilters(filters.copy(sort = it))
                if (state !is SearchUiState.Idle) viewModel.runSearch()
            },
            onOpenFilters = { showFilterSheet = true },
            onClearFilters = { viewModel.clearFilters() }
        )

        if (activeChips.isNotEmpty()) {
            ActiveFilterChipRow(
                chips = activeChips,
                onClear = { viewModel.clearFilters() }
            )
        }

        if (state is SearchUiState.Idle && filters.query.trim().length >= 2) {
            LocalFirstResultsList(
                localMatches = localMatches,
                query = filters.query,
                onOpenWork = onOpenWork,
                onSearchAo3 = { viewModel.runSearch() },
                onTagClick = { viewModel.searchTag(it) }
            )
        }

        when (val current = state) {
            SearchUiState.Idle -> {
                if (savedSearches.isNotEmpty()) {
                    SavedSearchesList(
                        savedSearches = savedSearches,
                        subtitleFor = { saved ->
                            savedSearchRepository
                                ?.filtersOf(saved)
                                ?.let(::savedSearchSubtitle)
                        },
                        onRun = { viewModel.runSavedSearch(it) },
                        onDelete = { pendingDeleteSearch = it },
                        modifier = Modifier.weight(1f)
                    )
                } else {
                    EmptyStateCard(
                        title = "Search AO3 works",
                        message = "Enter a title, tag, author, or phrase — or open Filters for rating, " +
                            "warnings, tags, and more. Save a searchable filter set to re-run later."
                    )
                }
            }
            SearchUiState.Loading -> LoadingStateCard("Searching AO3")
            is SearchUiState.Error -> {
                ErrorStateCard(
                    title = "AO3 search failed",
                    message = current.error.displayMessage(),
                    primaryActionLabel = "Retry",
                    onPrimaryAction = { viewModel.retry() }
                )
            }
            is SearchUiState.Results -> {
                if (current.works.isEmpty()) {
                    EmptyStateCard(
                        title = "No works found",
                        message = "AO3 returned no works for this query. Try broader terms or fewer filters."
                    )
                } else {
                    SearchResultsList(
                        onRefresh = { viewModel.refreshCurrentPage() },
                        works = current.works,
                        page = current.page.currentPage,
                        totalPages = current.page.totalPages,
                        expandAll = expandAllCards,
                        selectionMode = selectionMode,
                        selectedWorkIds = selectedWorkIds,
                        onToggleSelection = { viewModel.toggleWorkSelection(it) },
                        onOpenWork = onOpenWork,
                        onPage = { viewModel.runSearch(it) },
                        onTagClick = { viewModel.searchTag(it) },
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        }
    }

    val context = LocalContext.current
    val autocompleteRepository = remember {
        (context.applicationContext as? io.github.cidy02.kudos.KudosApplication)?.container?.tagAutocompleteRepository
    }

    if (showFilterSheet) {
        SearchFilterSheet(
            localTagSuggestions = LocalTagSuggestions(),
            filters = filters,
            onFiltersChange = { viewModel.updateFilters(it) },
            onApply = {
                showFilterSheet = false
                viewModel.runSearch(page = 1, searchFilters = filters)
            },
            onClear = { viewModel.clearFilters() },
            onDismiss = { showFilterSheet = false },
            onSave = if (savedSearchRepository != null) {
                {
                    showFilterSheet = false
                    saveName = defaultSavedSearchName(filters)
                    showSaveDialog = true
                }
            } else {
                null
            },
            autocompleteRepository = autocompleteRepository
        )
    }

    if (showSaveDialog) {
        AlertDialog(
            onDismissRequest = {
                showSaveDialog = false
                saveName = ""
            },
            title = { Text("Save Search") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Save the current search and its filters to re-run later.")
                    OutlinedTextField(
                        value = saveName,
                        onValueChange = { saveName = it },
                        label = { Text("Name") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            },
            confirmButton = {
                TextButton(
                    enabled = saveName.trim().isNotEmpty() && filters.isSearchable,
                    onClick = ::commitSavedSearch
                ) {
                    Text("Save")
                }
            },
            dismissButton = {
                TextButton(
                    onClick = {
                        showSaveDialog = false
                        saveName = ""
                    }
                ) {
                    Text("Cancel")
                }
            }
        )
    }
}

@Composable
private fun SavedSearchesList(
    savedSearches: List<SavedSearch>,
    subtitleFor: (SavedSearch) -> String?,
    onRun: (SavedSearch) -> Unit,
    onDelete: (SavedSearch) -> Unit,
    modifier: Modifier = Modifier
) {
    LazyColumn(
        verticalArrangement = Arrangement.spacedBy(10.dp),
        modifier = modifier.fillMaxWidth()
    ) {
        item {
            KudosSectionHeader(
                title = "Saved Searches",
                subtitle = "Tap to re-run. Search AO3 above or open Filters."
            )
        }
        items(savedSearches, key = { it.id }) { saved ->
            SavedSearchRow(
                saved = saved,
                subtitle = subtitleFor(saved),
                onRun = { onRun(saved) },
                onDelete = { onDelete(saved) }
            )
        }
    }
}

@Composable
private fun SavedSearchRow(
    saved: SavedSearch,
    subtitle: String?,
    onRun: () -> Unit,
    onDelete: () -> Unit
) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow
        ),
        shape = MaterialTheme.shapes.medium,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onRun)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Text(
                    text = saved.name,
                    style = MaterialTheme.typography.titleMedium
                )
                if (!subtitle.isNullOrBlank()) {
                    Text(
                        text = subtitle,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1
                    )
                }
            }
            IconButton(onClick = onDelete) {
                Icon(
                    imageVector = Icons.Outlined.Delete,
                    contentDescription = "Delete saved search"
                )
            }
        }
    }
}

@Composable
private fun SearchControlsRow(
    filters: AO3SearchFilters,
    activeChipCount: Int,
    expandAllCards: Boolean,
    selectionMode: Boolean,
    onToggleExpandAll: () -> Unit,
    onToggleSelectionMode: () -> Unit,
    onSortSelected: (AO3SearchSort) -> Unit,
    onOpenFilters: () -> Unit,
    onClearFilters: () -> Unit
) {
    var sortExpanded by remember { mutableStateOf(false) }
    var moreExpanded by remember { mutableStateOf(false) }

    Row(
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth()
    ) {
        OutlinedButton(onClick = onOpenFilters) {
            BadgedBox(
                badge = {
                    if (activeChipCount > 0) {
                        Badge { Text(activeChipCount.coerceAtMost(99).toString()) }
                    }
                }
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = Icons.Outlined.FilterList,
                        contentDescription = null
                    )
                    Text("Filters")
                }
            }
        }

        OutlinedButton(onClick = { sortExpanded = true }) {
            Text("Sort: ${filters.sort.title}")
        }
        DropdownMenu(
            expanded = sortExpanded,
            onDismissRequest = { sortExpanded = false }
        ) {
            AO3SearchSort.entries.forEach { sort ->
                DropdownMenuItem(
                    text = { Text(sort.title) },
                    onClick = {
                        onSortSelected(sort)
                        sortExpanded = false
                    }
                )
            }
        }

        if (filters.hasActiveFilters) {
            TextButton(onClick = onClearFilters) {
                Text("Clear")
            }
        }

        Spacer(Modifier.weight(1f))

        Box {
            IconButton(onClick = { moreExpanded = true }) {
                Icon(
                    imageVector = Icons.Outlined.MoreVert,
                    contentDescription = "More search options"
                )
            }
            DropdownMenu(
                expanded = moreExpanded,
                onDismissRequest = { moreExpanded = false }
            ) {
                DropdownMenuItem(
                    text = {
                        Text(if (selectionMode) "Exit Selection" else "Select Works")
                    },
                    leadingIcon = {
                        Icon(
                            imageVector = Icons.Outlined.Checklist,
                            contentDescription = null
                        )
                    },
                    onClick = {
                        moreExpanded = false
                        onToggleSelectionMode()
                    }
                )
                DropdownMenuItem(
                    text = {
                        Text(if (expandAllCards) "Collapse all" else "Expand all")
                    },
                    leadingIcon = {
                        Icon(
                            imageVector = if (expandAllCards) {
                                Icons.Outlined.UnfoldLess
                            } else {
                                Icons.Outlined.UnfoldMore
                            },
                            contentDescription = null
                        )
                    },
                    onClick = {
                        moreExpanded = false
                        onToggleExpandAll()
                    }
                )
            }
        }
    }
}

@Composable
private fun ActiveFilterChipRow(
    chips: List<String>,
    onClear: () -> Unit
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
    ) {
        chips.forEach { label ->
            InputChip(
                selected = true,
                onClick = { /* summary only; edit via Filters sheet */ },
                label = { Text(label, maxLines = 1) }
            )
        }
        FilterChip(
            selected = false,
            onClick = onClear,
            label = { Text("Clear all") }
        )
    }
}

@Composable
private fun SearchResultsList(
    works: List<io.github.cidy02.kudos.works.CanonicalWork>,
    page: Int,
    totalPages: Int,
    expandAll: Boolean,
    selectionMode: Boolean,
    selectedWorkIds: Set<Long>,
    onToggleSelection: (Long) -> Unit,
    onOpenWork: (AO3WorkSummary) -> Unit,
    onPage: (Int) -> Unit,
    onTagClick: (String) -> Unit,
    onRefresh: suspend () -> Unit,
    modifier: Modifier = Modifier
) {
    KudosRefreshBox(onRefresh = onRefresh, modifier = Modifier.fillMaxWidth()) {
    LazyColumn(
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = modifier.fillMaxWidth()
    ) {
        item {
            KudosSectionHeader(
                title = "Results",
                subtitle = "Page $page of $totalPages"
            )
        }
        items(works, key = { it.id }) { work ->
            if (selectionMode) {
                SelectableRemoteWorkRow(
                    work = work.remote,
                    selected = work.remote.id in selectedWorkIds,
                    onToggle = { onToggleSelection(work.remote.id) }
                )
            } else if (work.local != null) {
                io.github.cidy02.kudos.library.LibraryCarouselCard(
                    display = io.github.cidy02.kudos.library.LibraryDisplayItem(
                        item = io.github.cidy02.kudos.library.LibraryWorkListItem(
                            work = work.local,
                            userTags = emptyList(),
                            collections = emptyList()
                        )
                    ),
                    showProgress = true,
                    footerOverride = null,
                    actions = io.github.cidy02.kudos.library.LibraryCardActions(
                        onOpenWork = { onOpenWork(work.remote) },
                        onOpenReader = { onOpenWork(work.remote) },
                        onToggleFavorite = { },
                        onToggleFinished = { },
                        onRemove = { },
                        onSetSaved = { _, _ -> },
                        onSelect = { },
                        onReveal = { },
                        onAddToQueue = { },
                        onAddToCollection = { },
                        onOpenComments = { }
                    )
                )
            } else {
                AO3WorkCard(
                    work = work.remote,
                    onOpenWork = onOpenWork,
                    expandAll = expandAll,
                    onTagClick = onTagClick
                )
            }
        }
        item {
            KudosPaginationBar(
                currentPage = page,
                totalPages = totalPages,
                onPageChange = onPage,
                enabled = true
            )
        }
    }
    }
}

@Composable
private fun SelectableRemoteWorkRow(
    work: AO3WorkSummary,
    selected: Boolean,
    onToggle: () -> Unit
) {
    Card(
        onClick = onToggle,
        colors = CardDefaults.cardColors(
            containerColor = if (selected) MaterialTheme.colorScheme.primaryContainer 
                             else MaterialTheme.colorScheme.surfaceContainerLow
        ),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Checkbox(checked = selected, onCheckedChange = { onToggle() })
            Column(modifier = Modifier.weight(1f)) {
                Text(text = work.title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(text = work.authorText, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun LocalFirstResultsList(
    localMatches: List<io.github.cidy02.kudos.works.CanonicalWork>,
    query: String,
    onOpenWork: (AO3WorkSummary) -> Unit,
    onSearchAo3: () -> Unit,
    onTagClick: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    LazyColumn(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        if (localMatches.isNotEmpty()) {
            item {
                KudosSectionHeader(
                    title = "Library matches",
                    subtitle = if (localMatches.size == 1) "1 work" else "${localMatches.size} works"
                )
            }
            items(localMatches, key = { it.local!!.id }) { match ->
                AO3WorkCard(
                    work = match.remote,
                    onOpenWork = onOpenWork,
                    onTagClick = onTagClick
                )
            }
            item {
                HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
            }
        }
        item {
            Button(
                onClick = onSearchAo3,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Search AO3 for \"$query\"")
            }
        }
    }
}

private fun io.github.cidy02.kudos.core.model.SavedWork.toRemoteSummary(): AO3WorkSummary {
    return AO3WorkSummary(
        id = io.github.cidy02.kudos.works.WorkTags.ao3WorkIdFromUrl(sourceUrl) ?: 0,
        title = title,
        authors = author.split(",").map { it.trim() },
        fandoms = workFandoms,
        rating = rating,
        warnings = workWarnings,
        categories = workCategories,
        relationships = workRelationships,
        characters = workCharacters,
        freeforms = workFreeforms,
        language = language,
        wordCount = wordCount,
        chapters = chapters,
        kudos = kudos,
        comments = comments,
        hits = hits
    )
}

private fun AO3Error.displayMessage(): String {
    return when (this) {
        AO3Error.BadRequest -> "AO3 rejected that search."
        AO3Error.AuthenticationRequired -> "AO3 requires login for that page."
        AO3Error.Forbidden -> "AO3 denied access to that page."
        AO3Error.NotFound -> "AO3 could not find that page."
        is AO3Error.Http -> "AO3 returned HTTP $statusCode."
        is AO3Error.Network -> message
        is AO3Error.Overloaded -> "AO3 is busy. Try again shortly."
        is AO3Error.Parse -> message
        is AO3Error.RateLimited -> "AO3 is rate-limiting requests. Try again shortly."
        is AO3Error.Server -> "AO3 had a server problem (HTTP $statusCode)."
        is AO3Error.Validation -> message
    }
}
