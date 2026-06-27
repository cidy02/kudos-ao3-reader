package io.github.cidy02.kudos.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.library.LibraryDisplayItem
import io.github.cidy02.kudos.library.LibraryPrivacyVisibility
import io.github.cidy02.kudos.library.LibraryRepository
import io.github.cidy02.kudos.library.readingProgressFraction
import kotlin.math.roundToInt

@Composable
fun HomeScreen(
    repository: LibraryRepository,
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit,
    onOpenLibrary: () -> Unit,
    onOpenBrowse: () -> Unit
) {
    val viewModel: HomeViewModel = viewModel(factory = HomeViewModel.factory(repository))
    val state by viewModel.state.collectAsState()

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp)
    ) {
        item { HomeHeader(state) }

        if (state.loading) {
            item { HomeLoadingState() }
            return@LazyColumn
        }

        if (!state.hasSavedWorks) {
            item {
                EmptyHomeState(
                    onOpenBrowse = onOpenBrowse,
                    onOpenLibrary = onOpenLibrary
                )
            }
            return@LazyColumn
        }

        item {
            HomeShelf(
                title = "Continue Reading",
                items = state.continueReading.take(HomeShelfLimit),
                emptyMessage = "Nothing is in progress. Open a downloaded work to start reading.",
                onOpenWork = onOpenWork,
                onOpenReader = onOpenReader
            )
        }
        item {
            HomeShelf(
                title = "Favorites",
                items = state.favorites.take(HomeShelfLimit),
                emptyMessage = "Favorite works will appear here.",
                onOpenWork = onOpenWork,
                onOpenReader = onOpenReader
            )
        }
        item {
            HomeShelf(
                title = "Recently Opened",
                items = state.recentlyOpened.take(HomeShelfLimit),
                emptyMessage = "Works appear here after you read them.",
                onOpenWork = onOpenWork,
                onOpenReader = onOpenReader
            )
        }
        item {
            HomeShelf(
                title = "Recently Added",
                items = state.recentlyAdded.take(HomeShelfLimit),
                emptyMessage = "Saved works will appear here.",
                onOpenWork = onOpenWork,
                onOpenReader = onOpenReader
            )
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedButton(onClick = onOpenLibrary) {
                    Text("Library")
                }
                OutlinedButton(onClick = onOpenBrowse) {
                    Text("Browse")
                }
            }
        }
    }
}

@Composable
private fun HomeHeader(state: HomeDashboardState) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(text = "Home", style = MaterialTheme.typography.headlineMedium)
        val hidden = state.hiddenByPrivacyCount.takeIf { it > 0 }?.let {
            " - $it hidden by privacy"
        }.orEmpty()
        Text(
            text = if (state.loading) "Loading your Library" else "${state.totalSaved} saved$hidden",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun HomeLoadingState() {
    Row(
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        CircularProgressIndicator()
        Text("Loading your reading dashboard")
    }
}

@Composable
private fun EmptyHomeState(
    onOpenBrowse: () -> Unit,
    onOpenLibrary: () -> Unit
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(text = "No saved works yet", style = MaterialTheme.typography.titleMedium)
            Text(
                text = "Search AO3, browse fandoms, or save a work to start building your Library.",
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Button(onClick = onOpenBrowse) {
                    Text("Browse AO3")
                }
                OutlinedButton(onClick = onOpenLibrary) {
                    Text("Library")
                }
            }
        }
    }
}

@Composable
private fun HomeShelf(
    title: String,
    items: List<LibraryDisplayItem>,
    emptyMessage: String,
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(text = title, style = MaterialTheme.typography.titleLarge)
        if (items.isEmpty()) {
            Text(
                text = emptyMessage,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
            items.forEach { display ->
                HomeWorkCard(
                    display = display,
                    onOpenWork = { onOpenWork(display.item.work.id) },
                    onOpenReader = { onOpenReader(display.item.work.id) }
                )
            }
        }
    }
}

@Composable
private fun HomeWorkCard(
    display: LibraryDisplayItem,
    onOpenWork: () -> Unit,
    onOpenReader: () -> Unit
) {
    val work = display.item.work
    val progress = work.readingProgressFraction()
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        modifier = Modifier
            .fillMaxWidth()
            .semantics {
                contentDescription = "${work.title}, by ${work.author.ifBlank { "Anonymous" }}"
            }
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            if (display.privacyVisibility == LibraryPrivacyVisibility.Obscured) {
                Text(text = "Mature work hidden", style = MaterialTheme.typography.titleMedium)
                Text(
                    text = work.rating.ifBlank { "Mature content" },
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                Text(
                    text = work.title,
                    style = MaterialTheme.typography.titleMedium,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = "by ${work.author.ifBlank { "Anonymous" }}",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                work.fandomLine()?.let { MetadataLine(it) }
                MetadataLine(work.homeStatusLine())
                progress?.let { value ->
                    LinearProgressIndicator(
                        progress = { value.toFloat() },
                        modifier = Modifier.fillMaxWidth()
                    )
                    MetadataLine("${(value * 100).roundToInt()}% read")
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = onOpenWork) {
                    Text("Details")
                }
                if (work.hasEpub && display.privacyVisibility == LibraryPrivacyVisibility.Visible) {
                    Button(onClick = onOpenReader) {
                        Text("Read")
                    }
                }
            }
        }
    }
}

@Composable
private fun MetadataLine(value: String) {
    if (value.isBlank()) return
    Text(
        text = value,
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        maxLines = 2,
        overflow = TextOverflow.Ellipsis
    )
}

private fun SavedWork.homeStatusLine(): String {
    return listOfNotNull(
        if (hasEpub) "Downloaded" else "Not downloaded",
        if (isFavorite) "Favorite" else null,
        if (isFinished) "Finished" else null,
        if (isComplete) "Complete" else "In progress",
        rating.takeIf { it.isNotBlank() },
        wordCount.takeIf { it > 0 }?.let { "%,d words".format(it) },
        chapters.takeIf { it.isNotBlank() }?.let { "$it chapters" },
        kudos.takeIf { it > 0 }?.let { "$it kudos" }
    ).joinToString(" - ")
}

private fun SavedWork.fandomLine(): String? {
    val fandoms = workFandoms.ifEmpty { workTags }
        .filter { it.isNotBlank() }
        .take(3)
    return fandoms.takeIf { it.isNotEmpty() }?.joinToString(", ")
}

private const val HomeShelfLimit = 4
