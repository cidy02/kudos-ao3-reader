package io.github.cidy02.kudos.browse

import androidx.compose.foundation.clickable
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.browse.AO3BrowseRepository
import io.github.cidy02.kudos.network.ao3.browse.AO3BrowseUrls
import io.github.cidy02.kudos.network.ao3.browse.AO3Fandom
import io.github.cidy02.kudos.network.ao3.browse.AO3MediaCategory
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.components.StatusBadge
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import io.github.cidy02.kudos.network.ao3.displayMessage

@Composable
fun FandomListScreen(
    category: AO3MediaCategory,
    onOpenFandom: (AO3Fandom) -> Unit,
    onOpenWebFallback: (String) -> Unit,
    repository: AO3BrowseRepository = remember { AO3BrowseRepository() }
) {
    var state by remember(category.name) { mutableStateOf<FandomListState>(FandomListState.Loading) }
    var filter by remember(category.name) { mutableStateOf("") }
    var debouncedFilter by remember(category.name) { mutableStateOf("") }
    val scope = rememberCoroutineScope()

    // 120ms debounce, matching iOS's normalized fandom filter, so fast typing doesn't
    // recompute the match list (and, on a big category, re-render it) every keystroke.
    LaunchedEffect(filter) {
        delay(120)
        debouncedFilter = filter
    }

    fun webFallback() {
        AO3BrowseUrls.resolveAo3Url(category.fandomsPath)?.let(onOpenWebFallback)
            ?: onOpenWebFallback(AO3BrowseUrls.mediaIndexUrl())
    }

    fun load() {
        state = FandomListState.Loading
        scope.launch {
            state = when (val result = repository.fandoms(category)) {
                // Surface the biggest fandoms first; the AO3 index page arrives alphabetical.
                is AO3Result.Success -> FandomListState.Loaded(
                    result.value.sortedByDescending { it.workCount ?: 0 }
                )
                is AO3Result.Failure -> FandomListState.Error(result.error.displayMessage())
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
        Text(
            text = category.name,
            style = MaterialTheme.typography.titleLarge
        )
        Text(
            text = "Tap a fandom to browse its works.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        TextButton(onClick = ::webFallback) { Text("Open on AO3") }

        when (val current = state) {
            FandomListState.Loading -> LoadingStateCard("Loading fandoms")
            is FandomListState.Error -> BrowseErrorBlock(
                message = current.message,
                onRetry = ::load,
                onWebFallback = ::webFallback
            )
            is FandomListState.Loaded -> {
                val normalizedFilter = remember(debouncedFilter) { foldDiacritics(debouncedFilter.trim()) }
                val matches = remember(current.fandoms, normalizedFilter) {
                    if (normalizedFilter.isBlank()) {
                        current.fandoms
                    } else {
                        current.fandoms.filter { foldDiacritics(it.name).contains(normalizedFilter) }
                    }
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

/** Whole-row tap opens works — no separate Works button (iOS FandomListView). */
@Composable
private fun FandomRow(fandom: AO3Fandom, onOpen: () -> Unit) {
    Surface(
        tonalElevation = 1.dp,
        shape = MaterialTheme.shapes.medium,
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onOpen)
            .semantics {
                contentDescription = buildString {
                    append(fandom.name)
                    fandom.workCount?.let { append(", $it works") }
                    append(". Open works.")
                }
            }
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 14.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = fandom.name,
                style = MaterialTheme.typography.bodyLarge,
                modifier = Modifier.weight(1f)
            )
            fandom.workCount?.let { count ->
                StatusBadge("%,d".format(count))
            }
        }
    }
}

private sealed interface FandomListState {
    data object Loading : FandomListState
    data class Loaded(val fandoms: List<AO3Fandom>) : FandomListState
    data class Error(val message: String) : FandomListState
}

/** Diacritic-insensitive, case-insensitive fold — "pokemon" matches "Pokémon". */
internal fun foldDiacritics(text: String): String {
    val decomposed = java.text.Normalizer.normalize(text, java.text.Normalizer.Form.NFD)
    return decomposed.replace(Regex("\\p{Mn}+"), "").lowercase()
}
