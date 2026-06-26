package io.github.cidy02.kudos.search

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
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
import kotlinx.coroutines.launch

@Composable
fun SearchScreen(
    onOpenWork: (AO3WorkSummary) -> Unit,
    repository: AO3SearchRepository = remember { AO3SearchRepository() }
) {
    var query by remember { mutableStateOf("") }
    var sort by remember { mutableStateOf(AO3SearchSort.RELEVANCE) }
    var state by remember { mutableStateOf<SearchUiState>(SearchUiState.Idle) }
    var lastFilters by remember { mutableStateOf(AO3SearchFilters()) }
    val scope = rememberCoroutineScope()

    fun runSearch(page: Int = 1) {
        val filters = AO3SearchFilters(query = query, sort = sort)
        if (!filters.isSearchable) {
            state = SearchUiState.Idle
            return
        }

        lastFilters = filters
        state = SearchUiState.Loading
        scope.launch {
            state = when (val result = repository.search(filters, page)) {
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

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                label = { Text("Query") },
                singleLine = true,
                modifier = Modifier.weight(1f)
            )
            Button(
                enabled = state !is SearchUiState.Loading &&
                    AO3SearchFilters(query = query, sort = sort).isSearchable,
                onClick = { runSearch() }
            ) {
                Text("Search")
            }
        }

        SearchOptionsRow(
            selectedSort = sort,
            onSortSelected = { sort = it }
        )

        when (val current = state) {
            SearchUiState.Idle -> Unit
            SearchUiState.Loading -> {
                CircularProgressIndicator()
            }
            is SearchUiState.Error -> {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        text = current.error.displayMessage(),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.error
                    )
                    OutlinedButton(onClick = ::retry) {
                        Text("Retry")
                    }
                }
            }
            is SearchUiState.Results -> {
                if (current.page.works.isEmpty()) {
                    Text(
                        text = "No works found.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
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
}

@Composable
private fun SearchOptionsRow(
    selectedSort: AO3SearchSort,
    onSortSelected: (AO3SearchSort) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }

    Row(
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        OutlinedButton(onClick = { expanded = true }) {
            Text(selectedSort.title)
        }
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false }
        ) {
            AO3SearchSort.entries.forEach { sort ->
                DropdownMenuItem(
                    text = { Text(sort.title) },
                    onClick = {
                        onSortSelected(sort)
                        expanded = false
                    }
                )
            }
        }
        OutlinedButton(
            enabled = false,
            onClick = {}
        ) {
            Text("Filters")
        }
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
