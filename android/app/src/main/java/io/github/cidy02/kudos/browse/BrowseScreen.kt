package io.github.cidy02.kudos.browse

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.browse.AO3BrowseRepository
import io.github.cidy02.kudos.network.ao3.browse.AO3BrowseUrls
import io.github.cidy02.kudos.network.ao3.browse.AO3MediaCategory
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
            .padding(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(
                text = "Browse by fandom",
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.weight(1f)
            )
            OutlinedButton(onClick = { onOpenWebFallback(AO3BrowseUrls.mediaIndexUrl()) }) {
                Text("Open on AO3")
            }
        }

        when (val current = state) {
            BrowseCategoriesState.Loading -> CircularProgressIndicator()
            is BrowseCategoriesState.Error -> BrowseErrorBlock(
                message = current.message,
                onRetry = ::load,
                onWebFallback = { onOpenWebFallback(AO3BrowseUrls.mediaIndexUrl()) }
            )
            is BrowseCategoriesState.Loaded -> {
                if (current.categories.isEmpty()) {
                    Text(
                        text = "No fandom categories available.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                } else {
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

@Composable
private fun CategoryCard(category: AO3MediaCategory, onOpen: () -> Unit) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(text = category.name, style = MaterialTheme.typography.titleMedium)
            if (category.featuredFandoms.isNotEmpty()) {
                Text(
                    text = category.featuredFandoms.take(4).joinToString(", "),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            }
            Row {
                Text(
                    text = "Browse fandoms",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f)
                )
                Button(onClick = onOpen) { Text("Open") }
            }
        }
    }
}

private sealed interface BrowseCategoriesState {
    data object Loading : BrowseCategoriesState
    data class Loaded(val categories: List<AO3MediaCategory>) : BrowseCategoriesState
    data class Error(val message: String) : BrowseCategoriesState
}
