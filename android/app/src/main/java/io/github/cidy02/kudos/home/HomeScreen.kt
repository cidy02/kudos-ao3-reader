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
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.cidy02.kudos.account.AccountListRepository
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.library.LibraryDisplayItem
import io.github.cidy02.kudos.library.LibraryPrivacyVisibility
import io.github.cidy02.kudos.library.LibraryRepository
import io.github.cidy02.kudos.library.readingProgressFraction
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataRepository
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.KudosScreenHeader
import io.github.cidy02.kudos.ui.components.KudosSectionHeader
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.components.WorkCoverCard
import io.github.cidy02.kudos.ui.components.WorkCoverCardMetrics
import io.github.cidy02.kudos.ui.components.coverCardStats
import io.github.cidy02.kudos.works.WorkRepository
import kotlin.math.roundToInt

@Composable
fun HomeScreen(
    libraryRepository: LibraryRepository,
    workRepository: WorkRepository,
    metadataRepository: AO3WorkMetadataRepository,
    authRepository: AO3AuthRepository,
    accountListRepository: AccountListRepository,
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit,
    onOpenRemoteWork: (AO3WorkSummary) -> Unit,
    onOpenSubscriptionsList: () -> Unit,
    onOpenLibrary: () -> Unit,
    onOpenBrowse: () -> Unit
) {
    val viewModel: HomeViewModel = viewModel(
        factory = HomeViewModel.factory(
            libraryRepository = libraryRepository,
            workRepository = workRepository,
            metadataRepository = metadataRepository,
            authRepository = authRepository,
            accountListRepository = accountListRepository
        )
    )
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

        // Section order matches iOS Home: Reading Now, Recently Updated,
        // Subscriptions, Favorites, Recently Opened (no Recently Added).
        item {
            HomeShelf(
                title = "Continue Reading",
                items = state.continueReading.take(HomeShelfLimit),
                emptyMessage =
                    "You're not reading anything right now. Start exploring in Browse or open something from your Library.",
                onOpenWork = { id ->
                    viewModel.onOpenLocalWork(id)
                    onOpenWork(id)
                },
                onOpenReader = { id ->
                    viewModel.onOpenLocalWork(id)
                    onOpenReader(id)
                },
                footerFor = null
            )
        }
        item {
            HomeShelf(
                title = "Recently Updated",
                items = state.recentlyUpdated.take(HomeShelfLimit),
                emptyMessage = "No recent updates from your library works yet.",
                onOpenWork = { id ->
                    viewModel.onOpenLocalWork(id)
                    onOpenWork(id)
                },
                onOpenReader = { id ->
                    viewModel.onOpenLocalWork(id)
                    onOpenReader(id)
                },
                footerFor = { work -> updateFooter(work) }
            )
        }
        item {
            SubscriptionsShelf(
                works = state.subscriptions.take(HomeShelfLimit),
                isLoading = state.subscriptionsLoading,
                isSignedIn = state.isSignedIn,
                onOpenRemoteWork = onOpenRemoteWork,
                onSeeAll = onOpenSubscriptionsList
            )
        }
        item {
            HomeShelf(
                title = "Favorites",
                items = state.favorites.take(HomeShelfLimit),
                emptyMessage = "No favorites yet. Mark works as favorites to see them here.",
                onOpenWork = onOpenWork,
                onOpenReader = onOpenReader,
                footerFor = null
            )
        }
        item {
            HomeShelf(
                title = "Recently Opened",
                items = state.recentlyOpened.take(HomeShelfLimit),
                emptyMessage = "Nothing opened recently. Start reading to see your history here.",
                onOpenWork = onOpenWork,
                onOpenReader = onOpenReader,
                footerFor = null
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
private fun HomeHeader(state: HomeUiState, modifier: Modifier = Modifier) {
    val hidden = state.hiddenByPrivacyCount.takeIf { it > 0 }?.let {
        " · $it hidden by privacy"
    }.orEmpty()
    // TopAppBar already says "Kudos"; keep saved count / privacy as context only.
    KudosScreenHeader(
        subtitle = if (state.loading) "Loading your Library" else "${state.totalSaved} saved$hidden",
        modifier = modifier
    )
}

@Composable
private fun HomeShelf(
    title: String,
    items: List<LibraryDisplayItem>,
    emptyMessage: String,
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit,
    footerFor: ((SavedWork) -> String?)?
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
                        footerOverride = footerFor?.invoke(display.item.work),
                        onOpenWork = { onOpenWork(display.item.work.id) },
                        onOpenReader = { onOpenReader(display.item.work.id) }
                    )
                }
            }
        }
    }
}

@Composable
private fun SubscriptionsShelf(
    works: List<AO3WorkSummary>,
    isLoading: Boolean,
    isSignedIn: Boolean,
    onOpenRemoteWork: (AO3WorkSummary) -> Unit,
    onSeeAll: () -> Unit
) {
    val showSkeleton = isLoading && works.isEmpty()
    val emptyMessage = if (isSignedIn) {
        "You're not subscribed to anything yet. Subscribe to works or series to see updates here."
    } else {
        "Log in to AO3 to see the works and series you subscribe to."
    }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        KudosSectionHeader(
            title = "Subscriptions",
            subtitle = when {
                showSkeleton -> "Loading…"
                works.isEmpty() -> null
                else -> "${works.size} shown"
            },
            modifier = Modifier.padding(horizontal = 16.dp),
            trailing = if (works.isNotEmpty()) {
                {
                    TextButton(onClick = onSeeAll) {
                        Text("See all")
                    }
                }
            } else {
                null
            }
        )
        when {
            showSkeleton -> {
                LoadingStateCard(
                    message = "Loading subscriptions",
                    modifier = Modifier.padding(horizontal = 16.dp)
                )
            }
            works.isEmpty() -> {
                EmptyStateCard(
                    title = "Nothing here yet",
                    message = emptyMessage,
                    modifier = Modifier.padding(horizontal = 16.dp)
                )
            }
            else -> {
                // Horizontal remote shelf (Apple AO3WorkCoverCard parity).
                LazyRow(
                    contentPadding = PaddingValues(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(WorkCoverCardMetrics.shelfSpacing)
                ) {
                    items(works, key = { "sub-${it.id}" }) { work ->
                        RemoteWorkCover(
                            work = work,
                            onOpen = { onOpenRemoteWork(work) }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun RemoteWorkCover(
    work: AO3WorkSummary,
    onOpen: () -> Unit
) {
    WorkCoverCard(
        title = work.title,
        author = work.authorText,
        fandom = work.fandoms.firstOrNull { it.isNotBlank() },
        stats = coverCardStats(
            rating = work.rating,
            chapters = work.chapters,
            isComplete = work.isComplete == true,
            wordCount = work.wordCount?.takeIf { it > 0 },
            kudos = work.kudos?.takeIf { it > 0 }
        ),
        onOpen = onOpen,
        onOpenDetails = onOpen,
        statusChips = listOfNotNull(
            if (work.isRestricted) "Restricted" else null
        ),
        contentDescription = "Open ${work.title}, by ${work.authorText}"
    )
}

@Composable
private fun HomeWorkCover(
    display: LibraryDisplayItem,
    footerOverride: String?,
    onOpenWork: () -> Unit,
    onOpenReader: () -> Unit
) {
    val work = display.item.work
    val obscured = display.privacyVisibility == LibraryPrivacyVisibility.Obscured
    val canRead = work.hasEpub && !obscured
    val progress = if (footerOverride != null) null else work.readingProgressFraction()?.toFloat()
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
        statusChips = if (obscured) {
            listOf(work.rating.ifBlank { "Mature content" })
        } else {
            listOfNotNull(
                footerOverride,
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

private fun updateFooter(work: SavedWork): String? {
    if (!work.hasUpdate) return "Updated"
    val known = work.knownChapterCount ?: return "Updated"
    val newCount = work.postedChapterCount - known
    return if (newCount > 0) "+$newCount new" else "Updated"
}

private fun SavedWork.primaryFandom(): String? {
    return workFandoms.firstOrNull { it.isNotBlank() }
        ?: workTags.firstOrNull { it.isNotBlank() }
}

private const val HomeShelfLimit = 12
