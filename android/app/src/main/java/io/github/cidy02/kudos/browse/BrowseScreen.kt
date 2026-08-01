package io.github.cidy02.kudos.browse

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.browse.AO3BrowseRepository
import io.github.cidy02.kudos.network.ao3.browse.AO3BrowseUrls
import io.github.cidy02.kudos.network.ao3.browse.AO3MediaCategory
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.components.MetadataChipRow
import kotlinx.coroutines.launch

@Composable
fun BrowseScreen(
    onOpenCategory: (AO3MediaCategory) -> Unit,
    onOpenWebFallback: (String) -> Unit,
    repository: AO3BrowseRepository = remember { AO3BrowseRepository() }
) {
    var state by remember { mutableStateOf<BrowseCategoriesState>(BrowseCategoriesState.Loading) }
    val scope = rememberCoroutineScope()

    fun load() {
        state = BrowseCategoriesState.Loading
        scope.launch {
            state = when (val result = repository.categories()) {
                is AO3Result.Success -> BrowseCategoriesState.Loaded(result.value)
                is AO3Result.Failure -> BrowseCategoriesState.Error(result.error.browseMessage())
            }
        }
    }

    LaunchedEffect(Unit) { load() }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // TopAppBar already says "Browse". Match iOS: category cards are tappable;
        // website fallback is a text action, not a per-card Open button.
        Text(
            text = "Browse fandoms from AO3. Tap a category to see its fandoms.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        TextButton(onClick = { onOpenWebFallback(AO3BrowseUrls.mediaIndexUrl()) }) {
            Text("Open AO3 Website")
        }

        when (val current = state) {
            BrowseCategoriesState.Loading -> LoadingStateCard("Loading AO3 media categories")
            is BrowseCategoriesState.Error -> BrowseErrorBlock(
                message = current.message,
                onRetry = ::load,
                onWebFallback = { onOpenWebFallback(AO3BrowseUrls.mediaIndexUrl()) }
            )
            is BrowseCategoriesState.Loaded -> {
                if (current.categories.isEmpty()) {
                    EmptyStateCard(
                        title = "No fandom categories",
                        message = "AO3 did not return any fandom categories."
                    )
                } else {
                    Text(
                        text = "Browse by fandom",
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.primary
                    )
                    LazyColumn(
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        items(current.categories, key = { it.name }) { category ->
                            CategoryCard(category = category, onOpen = { onOpenCategory(category) })
                        }
                    }
                }
            }
        }
    }
}

/**
 * iOS MediaBrowserView category card: whole row is a NavigationLink — no separate Open.
 */
@Composable
private fun CategoryCard(category: AO3MediaCategory, onOpen: () -> Unit) {
    Card(
        onClick = onOpen,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow
        ),
        modifier = Modifier
            .fillMaxWidth()
            .semantics {
                contentDescription = "${category.name}. Open fandoms."
            }
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = category.name,
                style = MaterialTheme.typography.titleMedium
            )
            if (category.featuredFandoms.isNotEmpty()) {
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                MetadataChipRow(
                    labels = category.featuredFandoms.take(4),
                    maxItems = 4,
                    prominent = true
                )
            }
        }
    }
}

private sealed interface BrowseCategoriesState {
    data object Loading : BrowseCategoriesState
    data class Loaded(val categories: List<AO3MediaCategory>) : BrowseCategoriesState
    data class Error(val message: String) : BrowseCategoriesState
}
