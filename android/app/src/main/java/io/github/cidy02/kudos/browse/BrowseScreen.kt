package io.github.cidy02.kudos.browse

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.outlined.Bookmark
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.TravelExplore
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.browse.AO3BrowseRepository
import io.github.cidy02.kudos.network.ao3.browse.AO3BrowseUrls
import io.github.cidy02.kudos.network.ao3.browse.AO3Fandom
import io.github.cidy02.kudos.network.ao3.browse.AO3MediaCategory
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.KudosSectionHeader
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext

@Composable
fun BrowseScreen(
    onOpenCategory: (AO3MediaCategory) -> Unit,
    onOpenWebFallback: (String) -> Unit,
    onOpenFandom: (String) -> Unit = {},
    workRepository: WorkRepository? = null,
    repository: AO3BrowseRepository = remember { AO3BrowseRepository() }
) {
    var state by remember { mutableStateOf<BrowseCategoriesState>(BrowseCategoriesState.Loading) }
    var fandomLists by remember { mutableStateOf<Map<String, List<AO3Fandom>>>(emptyMap()) }
    val scope = rememberCoroutineScope()
    val libraryFlow = remember(workRepository) {
        workRepository?.observeLibraryWorks() ?: flowOf(emptyList())
    }
    val library by libraryFlow.collectAsState(initial = emptyList())

    // Suspending core so the shared pull-to-refresh spinner tracks the real
    // request; load() keeps the fire-and-forget shape the rest of the screen uses.
    suspend fun loadNow() {
        state = BrowseCategoriesState.Loading
        fandomLists = emptyMap()
        run {
            when (val result = repository.categories()) {
                is AO3Result.Success -> {
                    state = BrowseCategoriesState.Loaded(result.value)
                    // Background: fill fandom/work counts politely (bounded concurrency).
                    prefetchFandomLists(repository, result.value) { name, list ->
                        fandomLists = fandomLists + (name to list)
                    }
                }
                is AO3Result.Failure -> {
                    state = BrowseCategoriesState.Error(result.error.browseMessage())
                }
            }
        }
    }

    fun load() { scope.launch { loadNow() } }

    LaunchedEffect(Unit) { loadNow() }

    KudosRefreshBox(onRefresh = { loadNow() }, modifier = Modifier.fillMaxSize()) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
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
                    KudosSectionHeader(
                        title = "Browse by fandom",
                        subtitle = "Tap a category to see its fandoms.",
                        trailing = {
                            IconButton(
                                onClick = {
                                    onOpenWebFallback(AO3BrowseUrls.mediaIndexUrl())
                                }
                            ) {
                                Icon(
                                    imageVector = Icons.Outlined.TravelExplore,
                                    contentDescription = "Open AO3 website"
                                )
                            }
                        }
                    )
                    LazyColumn(
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        items(current.categories, key = { it.name }) { category ->
                            // Stats scan the full library once per category — never do that
                            // on the composition/main thread (jank on large libraries).
                            val fandomList = fandomLists[category.name]
                            val stats by produceState(
                                initialValue = CategoryStats(),
                                category,
                                fandomList,
                                library
                            ) {
                                value = withContext(Dispatchers.Default) {
                                    CategoryStatsCalculator.stats(
                                        category = category,
                                        fandomList = fandomList,
                                        library = library
                                    )
                                }
                            }
                            CategoryCard(
                                category = category,
                                stats = stats,
                                onOpen = { onOpenCategory(category) },
                                onOpenFandom = onOpenFandom
                            )
                        }
                    }
                }
            }
        }
    }
    }
}

/**
 * Prefetch each category's fandom index for card stats. Bounded so we stay polite
 * to AO3 (mirrors Apple FandomCatalog concurrency intent, in-memory only).
 * Invokes [onLoaded] as each category lands so cards fill in progressively.
 */
private suspend fun prefetchFandomLists(
    repository: AO3BrowseRepository,
    categories: List<AO3MediaCategory>,
    onLoaded: (String, List<AO3Fandom>) -> Unit
) {
    if (categories.isEmpty()) return
    val gate = Semaphore(permits = 2)
    val emitLock = Mutex()
    coroutineScope {
        categories.map { category ->
            async {
                gate.withPermit {
                    when (val result = repository.fandoms(category)) {
                        is AO3Result.Success -> {
                            emitLock.withLock {
                                onLoaded(category.name, result.value)
                            }
                        }
                        is AO3Result.Failure -> Unit
                    }
                }
            }
        }.awaitAll()
    }
}

/**
 * iOS MediaBrowserView category card: whole row is a NavigationLink — no separate Open.
 * Icon + name · stats line · optional recently-read chips · trailing chevron.
 */
@Composable
private fun CategoryCard(
    category: AO3MediaCategory,
    stats: CategoryStats,
    onOpen: () -> Unit,
    onOpenFandom: (String) -> Unit
) {
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
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Icon(
                    imageVector = CategoryStatsCalculator.iconFor(category.name),
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(22.dp)
                )
                Text(
                    text = category.name,
                    style = MaterialTheme.typography.titleMedium,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                Icon(
                    imageVector = Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            CategoryStatsLine(stats = stats)

            if (stats.recentFandoms.isNotEmpty()) {
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                RecentlyReadChips(
                    fandoms = stats.recentFandoms,
                    onOpenFandom = onOpenFandom
                )
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CategoryStatsLine(stats: CategoryStats) {
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        if (stats.fandomCount != null) {
            StatItem(
                icon = Icons.AutoMirrored.Outlined.MenuBook,
                text = "${CategoryStatsCalculator.formatCount(stats.fandomCount)} fandoms"
            )
            if (stats.workCount != null) {
                StatItem(
                    icon = Icons.Outlined.Description,
                    text = CategoryStatsCalculator.formatWorksEstimate(stats.workCount)
                )
            }
        } else {
            Text(
                text = "Counting fandoms…",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        if (stats.savedCount > 0) {
            StatItem(
                icon = Icons.Outlined.Bookmark,
                text = "${stats.savedCount} saved"
            )
        }
    }
}

@Composable
private fun StatItem(icon: ImageVector, text: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(3.dp)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(14.dp)
        )
        Text(
            text = text,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun RecentlyReadChips(
    fandoms: List<String>,
    onOpenFandom: (String) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            text = "Recently read",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            fandoms.forEach { fandom ->
                // Chip tap opens the fandom (not the whole card).
                Surface(
                    shape = MaterialTheme.shapes.small,
                    color = MaterialTheme.colorScheme.primaryContainer,
                    contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
                    modifier = Modifier.clickable { onOpenFandom(fandom) }
                ) {
                    Text(
                        text = fandom,
                        style = MaterialTheme.typography.labelMedium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp)
                    )
                }
            }
        }
    }
}

private sealed interface BrowseCategoriesState {
    data object Loading : BrowseCategoriesState
    data class Loaded(val categories: List<AO3MediaCategory>) : BrowseCategoriesState
    data class Error(val message: String) : BrowseCategoriesState
}
