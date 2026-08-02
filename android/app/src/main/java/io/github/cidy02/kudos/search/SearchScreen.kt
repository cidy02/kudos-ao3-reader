package io.github.cidy02.kudos.search

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.BookmarkAdd
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.FilterList
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
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
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.core.model.SavedSearch
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3SearchRepository
import io.github.cidy02.kudos.network.ao3.search.AO3SearchSort
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.ui.components.AO3WorkCard
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.KudosSectionHeader
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import kotlinx.coroutines.launch

@Composable
fun SearchScreen(
    onOpenWork: (AO3WorkSummary) -> Unit,
    repository: AO3SearchRepository = remember { AO3SearchRepository() },
    savedSearchRepository: SavedSearchRepository? = null,
    workRepository: WorkRepository? = null
) {
    val works by (workRepository?.observeSavedWorks() ?: kotlinx.coroutines.flow.flowOf(emptyList()))
        .collectAsState(initial = emptyList())
    var userTagNames by remember { mutableStateOf<List<String>>(emptyList()) }
    LaunchedEffect(workRepository) {
        userTagNames = workRepository?.allUserTags()?.map { it.normalizedName }.orEmpty()
    }
    val localTagSuggestions = remember(works, userTagNames) {
        collectLocalTagSuggestions(works, userTagNames)
    }
    var filters by remember { mutableStateOf(AO3SearchFilters()) }
    var showFilterSheet by remember { mutableStateOf(false) }
    var showSaveDialog by remember { mutableStateOf(false) }
    var saveName by remember { mutableStateOf("") }
    var state by remember { mutableStateOf<SearchUiState>(SearchUiState.Idle) }
    var lastFilters by remember { mutableStateOf(AO3SearchFilters()) }
    var savedSearches by remember { mutableStateOf<List<SavedSearch>>(emptyList()) }
    // Guards against an older in-flight search/retry overwriting a newer one's result
    // (e.g. Search, then immediately Sort, then immediately Search again) — only the
    // launch that's still current when it resolves is allowed to write `state`.
    var searchGeneration by remember { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    val activeChips = remember(filters) { activeFilterChips(filters) }

    fun refreshSavedSearches() {
        val repo = savedSearchRepository ?: return
        scope.launch {
            savedSearches = repo.getAll()
        }
    }

    LaunchedEffect(savedSearchRepository) {
        refreshSavedSearches()
    }

    fun runSearch(page: Int = 1, searchFilters: AO3SearchFilters = filters) {
        if (!searchFilters.isSearchable) {
            state = SearchUiState.Idle
            return
        }

        lastFilters = searchFilters
        state = SearchUiState.Loading
        val generation = ++searchGeneration
        scope.launch {
            val result = when (val result = repository.search(searchFilters, page)) {
                is AO3Result.Success -> SearchUiState.Results(result.value)
                is AO3Result.Failure -> SearchUiState.Error(result.error, page)
            }
            if (generation == searchGeneration) state = result
        }
    }

    fun retry() {
        val page = when (val current = state) {
            is SearchUiState.Error -> current.page
            is SearchUiState.Results -> current.page.currentPage
            else -> 1
        }
        state = SearchUiState.Loading
        val generation = ++searchGeneration
        scope.launch {
            val result = when (val result = repository.search(lastFilters, page)) {
                is AO3Result.Success -> SearchUiState.Results(result.value)
                is AO3Result.Failure -> SearchUiState.Error(result.error, page)
            }
            if (generation == searchGeneration) state = result
        }
    }

    fun clearFilters() {
        filters = clearedFiltersPreservingQuery(filters)
        // Clearing filters must also clear what's on screen — this only updated the
        // filter state before, leaving stale Results/Error visible until the user
        // manually searched again.
        if (state !is SearchUiState.Idle) runSearch()
    }

    fun presentSaveDialog() {
        if (savedSearchRepository == null || !filters.isSearchable) return
        saveName = defaultSavedSearchName(filters)
        showSaveDialog = true
    }

    fun commitSavedSearch() {
        val repo = savedSearchRepository ?: return
        val name = saveName.trim()
        if (name.isEmpty() || !filters.isSearchable) return
        scope.launch {
            repo.save(name, filters)
            savedSearches = repo.getAll()
            showSaveDialog = false
            saveName = ""
        }
    }

    fun runSaved(saved: SavedSearch) {
        val repo = savedSearchRepository ?: return
        val restored = repo.filtersOf(saved)
        filters = restored
        runSearch(page = 1, searchFilters = restored)
    }

    fun deleteSaved(id: String) {
        val repo = savedSearchRepository ?: return
        scope.launch {
            repo.delete(id)
            savedSearches = repo.getAll()
        }
    }

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
                onValueChange = { filters = filters.copy(query = it) },
                label = { Text("Query") },
                singleLine = true,
                modifier = Modifier.weight(1f)
            )
            if (savedSearchRepository != null) {
                IconButton(
                    enabled = filters.isSearchable,
                    onClick = ::presentSaveDialog
                ) {
                    Icon(
                        imageVector = Icons.Outlined.BookmarkAdd,
                        contentDescription = "Save search"
                    )
                }
            }
            Button(
                enabled = state !is SearchUiState.Loading && filters.isSearchable,
                onClick = { runSearch() }
            ) {
                Text("Search")
            }
        }

        SearchControlsRow(
            filters = filters,
            activeChipCount = activeChips.size,
            onSortSelected = {
                filters = filters.copy(sort = it)
                // Otherwise the visible results/pagination stay under the old sort
                // until the user notices and taps Search again.
                if (state !is SearchUiState.Idle) runSearch()
            },
            onOpenFilters = { showFilterSheet = true },
            onClearFilters = ::clearFilters
        )

        if (activeChips.isNotEmpty()) {
            ActiveFilterChipRow(
                chips = activeChips,
                onClear = ::clearFilters
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
                        onRun = ::runSaved,
                        onDelete = ::deleteSaved,
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
                    onPrimaryAction = ::retry
                )
            }
            is SearchUiState.Results -> {
                if (current.page.works.isEmpty()) {
                    EmptyStateCard(
                        title = "No works found",
                        message = "AO3 returned no works for this query. Try broader terms or fewer filters."
                    )
                } else {
                    SearchResultsList(
                        page = current.page,
                        onOpenWork = onOpenWork,
                        onPage = { runSearch(it) },
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        }
    }

    if (showFilterSheet) {
        SearchFilterSheet(
                    localTagSuggestions = localTagSuggestions,
            filters = filters,
            onFiltersChange = { filters = it },
            onApply = {
                showFilterSheet = false
                runSearch(page = 1, searchFilters = filters)
            },
            onClear = ::clearFilters,
            onDismiss = { showFilterSheet = false },
            onSave = if (savedSearchRepository != null) {
                {
                    showFilterSheet = false
                    presentSaveDialog()
                }
            } else {
                null
            }
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
    onDelete: (String) -> Unit,
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
                onDelete = { onDelete(saved.id) }
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
    onSortSelected: (AO3SearchSort) -> Unit,
    onOpenFilters: () -> Unit,
    onClearFilters: () -> Unit
) {
    var sortExpanded by remember { mutableStateOf(false) }

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
    page: AO3SearchPage,
    onOpenWork: (AO3WorkSummary) -> Unit,
    onPage: (Int) -> Unit,
    modifier: Modifier = Modifier
) {
    LazyColumn(
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = modifier.fillMaxWidth()
    ) {
        item {
            KudosSectionHeader(
                title = "Results",
                subtitle = "Page ${page.currentPage} of ${page.totalPages}"
            )
        }
        items(page.works, key = { it.id }) { work ->
            AO3WorkCard(work = work, onOpenWork = onOpenWork)
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedButton(
                    enabled = page.currentPage > 1,
                    onClick = { onPage(page.currentPage - 1) }
                ) {
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
    }
}

private sealed interface SearchUiState {
    data object Idle : SearchUiState
    data object Loading : SearchUiState
    data class Results(val page: AO3SearchPage) : SearchUiState
    data class Error(val error: AO3Error, val page: Int) : SearchUiState
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
