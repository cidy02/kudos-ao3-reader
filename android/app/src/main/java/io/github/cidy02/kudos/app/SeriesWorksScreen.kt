package io.github.cidy02.kudos.app

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.displayMessage
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.series.AO3SeriesRepository
import io.github.cidy02.kudos.ui.components.AO3WorkCard
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.KudosPaginationBar
import io.github.cidy02.kudos.ui.components.KudosScreenHeader
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import kotlinx.coroutines.launch

/**
 * Native listing of works in an AO3 series (`/series/<id>`).
 * Uses [AO3SeriesRepository] (search-style work blurbs) — same source as
 * download-whole-series / series preservation.
 */
@Composable
fun SeriesWorksScreen(
    seriesUrl: String,
    seriesRepository: AO3SeriesRepository,
    onOpenWork: (AO3WorkSummary) -> Unit
) {
    var state by remember(seriesUrl) { mutableStateOf<SeriesWorksState>(SeriesWorksState.Loading) }
    var loadGeneration by remember(seriesUrl) { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()

    fun load(page: Int = 1) {
        state = SeriesWorksState.Loading
        val generation = ++loadGeneration
        scope.launch {
            val next = when (val result = seriesRepository.seriesPage(seriesUrl, page)) {
                is AO3Result.Success -> SeriesWorksState.Loaded(result.value)
                is AO3Result.Failure -> SeriesWorksState.Error(result.error.displayMessage(), page)
            }
            if (generation == loadGeneration) state = next
        }
    }

    LaunchedEffect(seriesUrl) { load() }

    val title = (state as? SeriesWorksState.Loaded)
        ?.page
        ?.works
        ?.firstOrNull()
        ?.seriesTitle
        ?.takeIf { it.isNotBlank() }
        ?: "Series"

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        KudosScreenHeader(
            title = title,
            subtitle = "Works in this AO3 series."
        )

        when (val current = state) {
            SeriesWorksState.Loading -> LoadingStateCard("Loading series…")
            is SeriesWorksState.Error -> ErrorStateCard(
                title = "Couldn't load series",
                message = current.message,
                primaryActionLabel = "Retry",
                onPrimaryAction = { load(current.page) }
            )
            is SeriesWorksState.Loaded -> {
                if (current.page.works.isEmpty()) {
                    EmptyStateCard(
                        title = "No works found",
                        message = "This series has no works on this page."
                    )
                } else {
                    LazyColumn(
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        contentPadding = PaddingValues(bottom = 16.dp)
                    ) {
                        item {
                            Text(
                                text = "Page ${current.page.currentPage} of ${current.page.totalPages}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            KudosPaginationBar(
                                currentPage = current.page.currentPage,
                                totalPages = current.page.totalPages,
                                onPageChange = { load(it) }
                            )
                        }
                        items(current.page.works, key = { it.id }) { work ->
                            AO3WorkCard(work = work, onOpenWork = onOpenWork)
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
    }
}

private sealed interface SeriesWorksState {
    data object Loading : SeriesWorksState
    data class Loaded(val page: AO3SearchPage) : SeriesWorksState
    data class Error(val message: String, val page: Int) : SeriesWorksState
}
