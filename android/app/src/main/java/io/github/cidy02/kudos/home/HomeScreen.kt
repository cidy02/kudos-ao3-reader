package io.github.cidy02.kudos.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
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
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.KudosScreenHeader
import io.github.cidy02.kudos.ui.components.KudosSectionHeader
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.components.MetadataChipRow
import io.github.cidy02.kudos.ui.components.StatusBadge
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
            item { LoadingStateCard("Loading your reading dashboard") }
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
    val hidden = state.hiddenByPrivacyCount.takeIf { it > 0 }?.let {
        " - $it hidden by privacy"
    }.orEmpty()
    KudosScreenHeader(
        title = "Home",
        subtitle = if (state.loading) "Loading your Library" else "${state.totalSaved} saved$hidden"
    )
}

@Composable
private fun EmptyHomeState(
    onOpenBrowse: () -> Unit,
    onOpenLibrary: () -> Unit
) {
    EmptyStateCard(
        title = "No saved works yet",
        message = "Search AO3, browse fandoms, or save a work to start building your Library.",
        primaryActionLabel = "Browse AO3",
        onPrimaryAction = onOpenBrowse,
        secondaryActionLabel = "Library",
        onSecondaryAction = onOpenLibrary
    )
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
        KudosSectionHeader(
            title = title,
            subtitle = if (items.isEmpty()) null else "${items.size} shown"
        )
        if (items.isEmpty()) {
            EmptyStateCard(
                title = "Nothing here yet",
                message = emptyMessage
            )
        } else {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                items(items, key = { "${title}-${it.item.work.id}" }) { display ->
                    HomeWorkCard(
                        display = display,
                        onOpenWork = { onOpenWork(display.item.work.id) },
                        onOpenReader = { onOpenReader(display.item.work.id) },
                        modifier = Modifier.width(300.dp)
                    )
                }
            }
        }
    }
}

@Composable
private fun HomeWorkCard(
    display: LibraryDisplayItem,
    onOpenWork: () -> Unit,
    onOpenReader: () -> Unit,
    modifier: Modifier = Modifier
) {
    val work = display.item.work
    val progress = work.readingProgressFraction()
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        modifier = modifier
            .semantics {
                contentDescription = "${work.title}, by ${work.author.ifBlank { "Anonymous" }}"
            }
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            if (display.privacyVisibility == LibraryPrivacyVisibility.Obscured) {
                StatusBadge("Mature work hidden")
                MetadataChipRow(labels = listOf(work.rating.ifBlank { "Mature content" }))
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
                MetadataChipRow(labels = work.fandomLabels(), maxItems = 3, prominent = true)
                MetadataChipRow(labels = work.homeStatusLabels(), maxItems = 7)
                progress?.let { value ->
                    LinearProgressIndicator(
                        progress = { value.toFloat() },
                        modifier = Modifier.fillMaxWidth()
                    )
                    StatusBadge("${(value * 100).roundToInt()}% read")
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

private fun SavedWork.homeStatusLabels(): List<String> {
    return listOfNotNull(
        if (hasEpub) "Downloaded" else "Not downloaded",
        if (isFavorite) "Favorite" else null,
        if (isFinished) "Finished" else null,
        if (isComplete) "Complete" else "In progress",
        rating.takeIf { it.isNotBlank() },
        wordCount.takeIf { it > 0 }?.let { "%,d words".format(it) },
        chapters.takeIf { it.isNotBlank() }?.let { "$it chapters" },
        kudos.takeIf { it > 0 }?.let { "$it kudos" }
    )
}

private fun SavedWork.fandomLabels(): List<String> {
    return workFandoms.ifEmpty { workTags }
        .filter { it.isNotBlank() }
        .take(3)
}

private const val HomeShelfLimit = 4
