package io.github.cidy02.kudos.search

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
import androidx.compose.material.icons.outlined.FilterList
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.InputChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3SearchRepository
import io.github.cidy02.kudos.network.ao3.search.AO3SearchSort
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.ui.components.AO3WorkCard
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.KudosSectionHeader
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import kotlinx.coroutines.launch

@Composable
fun SearchScreen(
    onOpenWork: (AO3WorkSummary) -> Unit,
    repository: AO3SearchRepository = remember { AO3SearchRepository() }
) {
    var filters by remember { mutableStateOf(AO3SearchFilters()) }
    var showFilterSheet by remember { mutableStateOf(false) }
    var state by remember { mutableStateOf<SearchUiState>(SearchUiState.Idle) }
    var lastFilters by remember { mutableStateOf(AO3SearchFilters()) }
    val scope = rememberCoroutineScope()
    val activeChips = remember(filters) { activeFilterChips(filters) }

    fun runSearch(page: Int = 1, searchFilters: AO3SearchFilters = filters) {
        if (!searchFilters.isSearchable) {
            state = SearchUiState.Idle
            return
        }

        lastFilters = searchFilters
        state = SearchUiState.Loading
        scope.launch {
            state = when (val result = repository.search(searchFilters, page)) {
                is AO3Result.Success -> SearchUiState.Results(result.value)
                is AO3Result.Failure -> SearchUiState.Error(result.error, page)
            }
        }
    }

    fun retry() {
        val page = when (val current = state) {
            is SearchUiState.Error -> current.page
            is SearchUiState.Results -> current.page.currentPage
            else -> 1
        }
        state = SearchUiState.Loading
        scope.launch {
            state = when (val result = repository.search(lastFilters, page)) {
                is AO3Result.Success -> SearchUiState.Results(result.value)
                is AO3Result.Failure -> SearchUiState.Error(result.error, page)
            }
        }
    }

    fun clearFilters() {
        filters = clearedFiltersPreservingQuery(filters)
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
            onSortSelected = { filters = filters.copy(sort = it) },
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
            SearchUiState.Idle -> EmptyStateCard(
                title = "Search AO3 works",
                message = "Enter a title, tag, author, or phrase — or open Filters for rating, " +
                    "warnings, tags, and more. Search runs only when you press Search or Apply."
            )
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
            filters = filters,
            onFiltersChange = { filters = it },
            onApply = {
                showFilterSheet = false
                runSearch(page = 1, searchFilters = filters)
            },
            onClear = ::clearFilters,
            onDismiss = { showFilterSheet = false }
        )
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
