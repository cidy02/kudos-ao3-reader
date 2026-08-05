package io.github.cidy02.kudos.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.FilterList
import androidx.compose.material.icons.outlined.UnfoldLess
import androidx.compose.material.icons.outlined.UnfoldMore
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.app.PrivacyGate
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.library.LibraryCardActions
import io.github.cidy02.kudos.library.LibraryCarouselCard
import io.github.cidy02.kudos.library.LibraryDisplayItem
import io.github.cidy02.kudos.library.LibraryFilterPanel
import io.github.cidy02.kudos.library.LibraryFilterState
import io.github.cidy02.kudos.library.LibraryPrivacy
import io.github.cidy02.kudos.library.LibraryPrivacyVisibility
import io.github.cidy02.kudos.library.LibraryQuery
import io.github.cidy02.kudos.library.LibraryRepository
import io.github.cidy02.kudos.library.LibrarySort
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.ui.components.KudosScreenHeader
import io.github.cidy02.kudos.works.WorkMetadataRefresh
import io.github.cidy02.kudos.works.WorkRepository

/**
 * The full, vertically scrolling list behind a Home section's "See all"
 * (iOS `HomeSectionListView`).
 *
 * Reuses Library's card and filter panel rather than being a route into Library
 * itself, for the reason iOS gives: **with no filter set the section's own
 * ordering is kept**, so opening "Reading Now" in full doesn't silently re-sort
 * it by Library's default and destroy what the section means.
 */
@Composable
fun HomeSectionListScreen(
    kind: HomeSectionKind,
    repository: LibraryRepository,
    workRepository: WorkRepository,
    privacyGate: PrivacyGate,
    metadataRefresh: WorkMetadataRefresh?,
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit,
    onOpenComments: (Long) -> Unit = {}
) {
    val snapshot by repository.observeSnapshot().collectAsState(initial = null)
    val privacyState by privacyGate.state.collectAsState()
    val activity = androidx.compose.ui.platform.LocalContext.current
        as? androidx.fragment.app.FragmentActivity

    var filters by remember { mutableStateOf(LibraryFilterState()) }
    var showFilters by remember { mutableStateOf(false) }
    var expandAll by remember { mutableStateOf(false) }

    // Privacy is resolved the same way Library resolves it, so a work hidden on
    // the dashboard stays hidden here.
    val displayItems: List<LibraryDisplayItem> = remember(snapshot, privacyState) {
        val current = snapshot ?: return@remember emptyList()
        current.items.mapNotNull { item ->
            when (val visibility = LibraryPrivacy.visibility(item.work, current.privacy)) {
                LibraryPrivacyVisibility.Hidden -> null
                else -> LibraryDisplayItem(item, visibility)
            }
        }
    }
    val byId = remember(displayItems) { displayItems.associateBy { it.item.work.id } }

    // Section membership + ordering come from the shared HomeSectionKind rules,
    // so this page and the dashboard carousel can never disagree.
    val sectionItems: List<LibraryDisplayItem> = remember(displayItems, kind) {
        kind.works(displayItems.map { it.item.work }) { true }
            .mapNotNull { byId[it.id] }
    }

    // filterOnly, never apply(): filtering must not re-sort the section.
    val visibleItems = remember(sectionItems, filters) {
        if (filters.hasActiveFilters) LibraryQuery.filterOnly(sectionItems, filters = filters) else sectionItems
    }

    val cardActions = LibraryCardActions(
        onOpenWork = onOpenWork,
        onOpenReader = onOpenReader,
        onToggleFavorite = {},
        onToggleFinished = {},
        onRemove = {},
        onSetSaved = { _, _ -> },
        onSelect = {},
        onReveal = { id -> privacyGate.reveal(id, activity) },
        onAddToQueue = {},
        onAddToCollection = {},
        onOpenComments = onOpenComments
    )

    KudosRefreshBox(
        onRefresh = {
            val refresher = metadataRefresh ?: return@KudosRefreshBox
            for (display in visibleItems) {
                refresher.refresh(display.item.work)
            }
        },
        modifier = Modifier.fillMaxSize()
    ) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                KudosScreenHeader(
                    title = kind.title,
                    subtitle = "${sectionItems.size} works",
                    trailing = {
                        androidx.compose.foundation.layout.Row {
                            IconButton(onClick = { showFilters = true }) {
                                BadgedBox(
                                    badge = {
                                        if (filters.hasActiveFilters) {
                                            androidx.compose.material3.Badge { Text("!") }
                                        }
                                    }
                                ) {
                                    Icon(Icons.Outlined.FilterList, contentDescription = "Filter this section")
                                }
                            }
                            IconButton(onClick = { expandAll = !expandAll }) {
                                Icon(
                                    imageVector = if (expandAll) Icons.Outlined.UnfoldLess else Icons.Outlined.UnfoldMore,
                                    contentDescription = if (expandAll) "Collapse all" else "Expand all"
                                )
                            }
                        }
                    }
                )
            }

            when {
                sectionItems.isEmpty() -> item {
                    EmptyStateCard(title = "Nothing here yet", message = kind.emptyMessage)
                }
                // Section has works, but the active filters hid them all.
                visibleItems.isEmpty() -> item {
                    EmptyStateCard(
                        title = "No matching works",
                        message = "No works in this section match the current filters.",
                        primaryActionLabel = "Clear Filters",
                        onPrimaryAction = { filters = LibraryFilterState() }
                    )
                }
                else -> items(visibleItems, key = { it.item.work.id }) { display ->
                    LibraryCarouselCard(
                        display = display,
                        showProgress = true,
                        footerOverride = null,
                        actions = cardActions,
                        modifier = Modifier.fillMaxSize()
                    )
                }
            }
        }
    }

    if (showFilters) {
        LibraryFilterPanel(
            filters = filters,
            sort = LibrarySort.RecentlyAdded,
            userTags = snapshot?.userTags.orEmpty(),
            collections = snapshot?.collections.orEmpty(),
            onFiltersChange = { filters = it },
            // Sort is intentionally not offered: the section defines its own order.
            onSortChange = {},
            onApply = { showFilters = false },
            onClear = { filters = LibraryFilterState() },
            onDismiss = { showFilters = false }
        )
    }
}
