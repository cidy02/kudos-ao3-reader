package io.github.cidy02.kudos.browse

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
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.browse.AO3BrowseRepository
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.ui.components.AO3WorkCard
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.KudosScreenHeader
import io.github.cidy02.kudos.ui.components.KudosSectionHeader
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.components.MetadataChipRow
import io.github.cidy02.kudos.works.WorkRepository
import kotlinx.coroutines.launch

@Composable
fun FandomWorksScreen(
    fandomName: String,
    workRepository: WorkRepository,
    onOpenWork: (AO3WorkSummary) -> Unit,
    onBack: () -> Unit,
    repository: AO3BrowseRepository = remember { AO3BrowseRepository() }
) {
    var state by remember(fandomName) { mutableStateOf<FandomWorksState>(FandomWorksState.Loading) }
    val scope = rememberCoroutineScope()
    val savedWorks by workRepository.observeSavedWorks().collectAsState(initial = emptyList())
    val savedByUrl = remember(savedWorks) { BrowseLocalIndicators.index(savedWorks) }

    fun load(page: Int = 1) {
        state = FandomWorksState.Loading
        scope.launch {
            state = when (val result = repository.worksForFandom(fandomName, page)) {
                is AO3Result.Success -> FandomWorksState.Loaded(result.value)
                is AO3Result.Failure -> FandomWorksState.Error(result.error.browseMessage(), page)
            }
        }
    }

    LaunchedEffect(fandomName) { load() }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        KudosScreenHeader(
            title = fandomName,
            subtitle = "AO3 works for this fandom.",
            trailing = {
                TextButton(onClick = onBack) { Text("Back") }
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
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        item {
                            KudosSectionHeader(
                                title = "Works",
                                subtitle = "Page ${current.page.currentPage} of ${current.page.totalPages}"
                            )
                        }
                        items(current.page.works, key = { it.id }) { work ->
                            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                LocalIndicatorRow(BrowseLocalIndicators.forWork(work, savedByUrl))
                                AO3WorkCard(work = work, onOpenWork = onOpenWork)
                            }
                        }
                        item {
                            PaginationRow(page = current.page, onPage = { load(it) })
                        }
                    }
                }
            }
        }
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
        OutlinedButton(enabled = page.currentPage < page.totalPages, onClick = { onPage(page.currentPage + 1) }) {
            Text("Next")
        }
    }
}

private sealed interface FandomWorksState {
    data object Loading : FandomWorksState
    data class Loaded(val page: AO3SearchPage) : FandomWorksState
    data class Error(val message: String, val page: Int) : FandomWorksState
}
