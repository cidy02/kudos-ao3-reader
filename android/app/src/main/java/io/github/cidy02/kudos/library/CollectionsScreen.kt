package io.github.cidy02.kudos.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.ui.subject.ToolbarAddButton
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.app.PrivacyGate
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.ui.components.DestructiveConfirmation
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.subject.GlassCircleButton
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectWorkCardMetrics
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import io.github.cidy02.kudos.works.WorkRepository
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

/** Full Collections grid behind the Library dashboard's See All action. */
@Composable
fun CollectionsScreen(
    workRepository: WorkRepository,
    repository: LibraryRepository,
    privacyGate: PrivacyGate,
    onOpenCollection: (String) -> Unit
) {
    val tokens = LocalKudosTokens.current
    val reveal by privacyGate.state.collectAsState()
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var collections by remember { mutableStateOf<List<WorkCollection>>(emptyList()) }
    var works by remember { mutableStateOf<List<SavedWork>>(emptyList()) }
    var showCreate by remember { mutableStateOf(false) }
    var deleteCandidate by remember { mutableStateOf<WorkCollection?>(null) }
    val scope = rememberCoroutineScope()

    ProvidePushedShellChrome(
        hasSubjectHeader = true,
        trailingContent = {
            ToolbarAddButton(
                onClick = { showCreate = true },
                accessibilityName = "New Collection",
                palette = tokens.scopePalette
            )
        }
    )

    suspend fun refresh() {
        loading = true
        error = null
        try {
            val snapshot = repository.observeSnapshot().first()
            val state = LibraryQuery.buildState(
                snapshot = snapshot,
                searchQuery = "",
                filters = LibraryFilterState(),
                sort = LibrarySort.RecentlyAdded,
                reveal = reveal
            )
            collections = state.collections
            works = state.items
                .filter { it.privacyVisibility == LibraryPrivacyVisibility.Visible }
                .map { it.item.work }
        } catch (failure: Exception) {
            error = failure.message ?: "Could not load collections."
        } finally {
            loading = false
        }
    }

    LaunchedEffect(reveal) { refresh() }

    if (showCreate) {
        CollectionEditorSheet(
            workRepository = workRepository,
            existing = null,
            onDismiss = { showCreate = false },
            onSaved = { created ->
                showCreate = false
                scope.launch {
                    refresh()
                    onOpenCollection(created.id)
                }
            }
        )
    }

    DestructiveConfirmation(
        show = deleteCandidate != null,
        title = deleteCandidate?.let { "Delete “${it.name}”?" }.orEmpty(),
        text = "Kudos will move this collection to Recently Deleted for 90 days. Its works will stay in your Library.",
        confirmText = "Delete",
        confirmBeforeDelete = true,
        onConfirm = {
            val collection = deleteCandidate ?: return@DestructiveConfirmation
            deleteCandidate = null
            scope.launch {
                workRepository.softDeleteCollection(collection.id)
                refresh()
            }
        },
        onDismissRequest = { deleteCandidate = null }
    )

    Box(
        Modifier
            .fillMaxSize()
            .subjectScreenWash(tokens.scopePalette)
    ) {
        KudosRefreshBox(onRefresh = { refresh() }, modifier = Modifier.fillMaxSize()) {
            val topInset = WindowInsets.systemBars.asPaddingValues().calculateTopPadding()
            LazyVerticalGrid(
                columns = GridCells.Adaptive(SubjectWorkCardMetrics.width),
                contentPadding = PaddingValues(
                    start = 16.dp,
                    end = 16.dp,
                    top = topInset + 56.dp,
                    bottom = 16.dp
                ),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
                modifier = Modifier.fillMaxSize()
            ) {
                item(span = { GridItemSpan(maxLineSpan) }) {
                    SubjectHeaderBlock(
                        kicker = "Library",
                        title = "Collections",
                        subtitle = "${collections.size} ${if (collections.size == 1) "collection" else "collections"}",
                        palette = tokens.scopePalette
                    )
                }

                when {
                    loading -> item(span = { GridItemSpan(maxLineSpan) }) {
                        LoadingStateCard("Loading collections")
                    }
                    error != null && collections.isEmpty() -> item(span = { GridItemSpan(maxLineSpan) }) {
                        ErrorStateCard("Collections could not load", error.orEmpty())
                    }
                    collections.isEmpty() -> item(span = { GridItemSpan(maxLineSpan) }) {
                        EmptyStateCard(
                            "No collections yet",
                            "Create a collection above to group works together."
                        )
                    }
                    else -> items(collections, key = { it.id }) { collection ->
                        CollectionGridItem(
                            collection = collection,
                            works = works,
                            onOpen = { onOpenCollection(collection.id) },
                            onDelete = { deleteCandidate = collection }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun CollectionGridItem(
    collection: WorkCollection,
    works: List<SavedWork>,
    onOpen: () -> Unit,
    onDelete: () -> Unit
) {
    var menuOpen by remember(collection.id) { mutableStateOf(false) }
    Box {
        CollectionCard(
            collection = collection,
            previewWorks = works
                .filter { it.id in collection.workIds }
                .sortedByDescending { it.dateAdded },
            onClick = onOpen,
            onLongClick = { menuOpen = true }
        )
        DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
            DropdownMenuItem(
                text = { Text("Delete Collection", color = MaterialTheme.colorScheme.error) },
                leadingIcon = {
                    Icon(Icons.Outlined.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                },
                onClick = { menuOpen = false; onDelete() }
            )
        }
    }
}
