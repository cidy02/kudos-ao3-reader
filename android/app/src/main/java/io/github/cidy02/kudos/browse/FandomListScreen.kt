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
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
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
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.browse.AO3BrowseRepository
import io.github.cidy02.kudos.network.ao3.browse.AO3BrowseUrls
import io.github.cidy02.kudos.network.ao3.browse.AO3Fandom
import io.github.cidy02.kudos.network.ao3.browse.AO3MediaCategory
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.KudosScreenHeader
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.components.StatusBadge
import kotlinx.coroutines.launch

@Composable
fun FandomListScreen(
    category: AO3MediaCategory,
    onOpenFandom: (AO3Fandom) -> Unit,
    onOpenWebFallback: (String) -> Unit,
    onBack: () -> Unit,
    repository: AO3BrowseRepository = remember { AO3BrowseRepository() }
) {
    var state by remember(category.name) { mutableStateOf<FandomListState>(FandomListState.Loading) }
    var filter by remember(category.name) { mutableStateOf("") }
    val scope = rememberCoroutineScope()

    fun webFallback() {
        AO3BrowseUrls.resolveAo3Url(category.fandomsPath)?.let(onOpenWebFallback)
            ?: onOpenWebFallback(AO3BrowseUrls.mediaIndexUrl())
    }

    fun load() {
        state = FandomListState.Loading
        scope.launch {
            state = when (val result = repository.fandoms(category)) {
                is AO3Result.Success -> FandomListState.Loaded(result.value)
                is AO3Result.Failure -> FandomListState.Error(result.error.browseMessage())
            }
        }
    }

    LaunchedEffect(category.name) { load() }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        KudosScreenHeader(
            title = category.name,
            subtitle = "Filter AO3 fandoms in this media category.",
            trailing = {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    TextButton(onClick = onBack) { Text("Back") }
                    TextButton(onClick = ::webFallback) { Text("AO3") }
                }
            }
        )

        when (val current = state) {
            FandomListState.Loading -> LoadingStateCard("Loading fandoms")
            is FandomListState.Error -> BrowseErrorBlock(
                message = current.message,
                onRetry = ::load,
                onWebFallback = ::webFallback
            )
            is FandomListState.Loaded -> {
                val matches = current.fandoms.filter {
                    filter.isBlank() || it.name.contains(filter.trim(), ignoreCase = true)
                }
                OutlinedTextField(
                    value = filter,
                    onValueChange = { filter = it },
                    label = { Text("Filter fandoms") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                if (matches.isEmpty()) {
                    EmptyStateCard(
                        title = "No fandoms match",
                        message = "Try a broader filter or open the AO3 fallback."
                    )
                } else {
                    LazyColumn(
                        modifier = Modifier.fillMaxWidth(),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        items(matches, key = { it.name }) { fandom ->
                            FandomRow(fandom = fandom, onOpen = { onOpenFandom(fandom) })
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun FandomRow(fandom: AO3Fandom, onOpen: () -> Unit) {
    Surface(
        tonalElevation = 1.dp,
        shape = MaterialTheme.shapes.medium,
        color = MaterialTheme.colorScheme.surfaceVariant,
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = fandom.name,
                style = MaterialTheme.typography.bodyLarge,
                modifier = Modifier.weight(1f)
            )
            fandom.workCount?.let { count ->
                StatusBadge("%,d".format(count))
            }
            TextButton(onClick = onOpen) { Text("Works") }
        }
    }
}

private sealed interface FandomListState {
    data object Loading : FandomListState
    data class Loaded(val fandoms: List<AO3Fandom>) : FandomListState
    data class Error(val message: String) : FandomListState
}
