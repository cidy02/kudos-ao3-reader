package io.github.cidy02.kudos.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
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
import io.github.cidy02.kudos.ui.components.WorkCoverCard
import io.github.cidy02.kudos.ui.components.WorkCoverCardMetrics
import io.github.cidy02.kudos.ui.components.coverCardStats
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
        contentPadding = PaddingValues(vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        item {
            HomeHeader(
                state = state,
                modifier = Modifier.padding(horizontal = 16.dp)
            )
        }

        if (state.loading) {
            item {
                LoadingStateCard(
                    message = "Loading your reading dashboard",
                    modifier = Modifier.padding(horizontal = 16.dp)
                )
            }
            return@LazyColumn
        }

        if (!state.hasSavedWorks) {
            item {
                EmptyHomeState(
                    onOpenBrowse = onOpenBrowse,
                    onOpenLibrary = onOpenLibrary,
                    modifier = Modifier.padding(horizontal = 16.dp)
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
            Row(
                modifier = Modifier.padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
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
private fun HomeHeader(state: HomeDashboardState, modifier: Modifier = Modifier) {
    val hidden = state.hiddenByPrivacyCount.takeIf { it > 0 }?.let {
        " · $it hidden by privacy"
    }.orEmpty()
    KudosScreenHeader(
        title = "Home",
        subtitle = if (state.loading) "Loading your Library" else "${state.totalSaved} saved$hidden",
        modifier = modifier
    )
}

@Composable
private fun EmptyHomeState(
    onOpenBrowse: () -> Unit,
    onOpenLibrary: () -> Unit,
    modifier: Modifier = Modifier
) {
    EmptyStateCard(
        title = "No saved works yet",
        message = "Search AO3, browse fandoms, or save a work to start building your Library.",
        primaryActionLabel = "Browse AO3",
        onPrimaryAction = onOpenBrowse,
        secondaryActionLabel = "Library",
        onSecondaryAction = onOpenLibrary,
        modifier = modifier
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
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        KudosSectionHeader(
            title = title,
            subtitle = if (items.isEmpty()) null else "${items.size} shown",
            modifier = Modifier.padding(horizontal = 16.dp)
        )
        if (items.isEmpty()) {
            EmptyStateCard(
                title = "Nothing here yet",
                message = emptyMessage,
                modifier = Modifier.padding(horizontal = 16.dp)
            )
        } else {
            LazyRow(
                contentPadding = PaddingValues(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(WorkCoverCardMetrics.shelfSpacing)
            ) {
                items(items, key = { "${title}-${it.item.work.id}" }) { display ->
                    HomeWorkCover(
                        display = display,
                        onOpenWork = { onOpenWork(display.item.work.id) },
                        onOpenReader = { onOpenReader(display.item.work.id) }
                    )
                }
            }
        }
    }
}

@Composable
private fun HomeWorkCover(
    display: LibraryDisplayItem,
    onOpenWork: () -> Unit,
    onOpenReader: () -> Unit
) {
    val work = display.item.work
    val obscured = display.privacyVisibility == LibraryPrivacyVisibility.Obscured
    val canRead = work.hasEpub && !obscured
    val progress = work.readingProgressFraction()?.toFloat()
    val progressLabel = progress?.let { value ->
        when {
            value >= 0.999f -> "Finished"
            work.isFinished -> "Finished"
            else -> "${(value * 100).roundToInt()}% · Reading"
        }
    }

    WorkCoverCard(
        title = work.title,
        author = work.author.ifBlank { "Anonymous" },
        fandom = work.primaryFandom(),
        stats = if (obscured) {
            emptyList()
        } else {
            coverCardStats(
                rating = work.rating,
                chapters = work.chapters,
                isComplete = work.isComplete,
                wordCount = work.wordCount.takeIf { it > 0 },
                kudos = work.kudos.takeIf { it > 0 }
            )
        },
        onOpen = if (canRead) onOpenReader else onOpenWork,
        onOpenDetails = onOpenWork,
        progress = if (obscured) null else progress,
        progressLabel = if (obscured) null else progressLabel,
        // Only chips that cannot live behind Details — keep the face quiet (MD3
        // progressive disclosure). Download state matters for offline trust.
        statusChips = if (obscured) {
            listOf(work.rating.ifBlank { "Mature content" })
        } else {
            listOfNotNull(
                if (!work.hasEpub) "Not downloaded" else null,
                if (work.isFavorite) "Favorite" else null
            )
        },
        obscured = obscured,
        contentDescription = if (obscured) {
            "Mature work hidden. ${work.rating.ifBlank { "Mature content" }}"
        } else {
            val action = if (canRead) "Read" else "Open details for"
            "$action ${work.title}, by ${work.author.ifBlank { "Anonymous" }}"
        }
    )
}

private fun SavedWork.primaryFandom(): String? {
    return workFandoms.firstOrNull { it.isNotBlank() }
        ?: workTags.firstOrNull { it.isNotBlank() }
}

private const val HomeShelfLimit = 12
