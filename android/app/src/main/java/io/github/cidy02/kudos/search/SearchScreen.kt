package io.github.cidy02.kudos.search

import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.flowOf
import io.github.cidy02.kudos.library.LibraryPrivacyVisibility
import io.github.cidy02.kudos.library.LibraryPrivacy
import io.github.cidy02.kudos.core.model.PrivacySettings
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.outlined.CollectionsBookmark
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Label
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.cidy02.kudos.app.LocalSearchExit
import io.github.cidy02.kudos.app.LocalShellOverlayState
import io.github.cidy02.kudos.core.model.SavedSearch
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.library.readingProgressFraction
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.browse.FandomCatalogCache
import io.github.cidy02.kudos.network.ao3.displayMessage
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3SearchRepository
import io.github.cidy02.kudos.network.ao3.search.AO3SearchSort
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.ui.components.SensitiveWorkRow
import io.github.cidy02.kudos.ui.components.DestructiveConfirmation
import io.github.cidy02.kudos.ui.components.GlassFieldBar
import io.github.cidy02.kudos.ui.components.KudosPaginationBar
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.ui.components.RemoteWorkSelectionBar
import io.github.cidy02.kudos.ui.components.RemoteWorkBulkActions
import io.github.cidy02.kudos.ui.components.SelectableRemoteWorkRow
import io.github.cidy02.kudos.ui.components.WorkBulkActionBar
import io.github.cidy02.kudos.ui.components.rememberRemoteWorkSelection
import io.github.cidy02.kudos.ui.subject.FilterButton
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.ToolbarCircleButton
import io.github.cidy02.kudos.ui.subject.compactCount
import io.github.cidy02.kudos.ui.subject.subjectPanel
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import io.github.cidy02.kudos.works.CanonicalWork
import io.github.cidy02.kudos.works.DownloadQueue
import io.github.cidy02.kudos.works.WorkImporter
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.works.WorkTags
import kotlinx.coroutines.launch
import androidx.compose.runtime.rememberCoroutineScope

sealed interface SearchUiState {
    data object Idle : SearchUiState
    data object Loading : SearchUiState
    data class Results(val page: AO3SearchPage, val works: List<CanonicalWork>) : SearchUiState
    data class Error(
        val error: AO3Error,
        val page: Int,
        val stale: Results? = null
    ) : SearchUiState
}

@Composable
fun SearchScreen(
    onOpenWork: (AO3WorkSummary) -> Unit,
    repository: AO3SearchRepository = remember { AO3SearchRepository() },
    savedSearchRepository: SavedSearchRepository? = null,
    workRepository: WorkRepository? = null,
    settingsRepository: SettingsRepository? = null,
    privacyGate: io.github.cidy02.kudos.app.PrivacyGate = io.github.cidy02.kudos.app.PrivacyGate(),
    onOpenUrl: ((String) -> Unit)? = null,
    fandomCatalogCache: FandomCatalogCache? = null,
    workImporter: WorkImporter? = null,
    queueRepository: ReadingQueueRepository? = null,
    downloadQueue: DownloadQueue? = null,
    onOpenCollection: (String) -> Unit = {},
    onFilterLibraryFandom: (String) -> Unit = {},
    onFilterLibraryTag: (String) -> Unit = {}
) {
    val viewModel: SearchViewModel = viewModel(
        factory = SearchViewModel.factory(
            repository, savedSearchRepository, workRepository,
            hiddenWorks = combine(
                settingsRepository?.settings?.map { it.privacy } ?: flowOf(PrivacySettings()),
                privacyGate.state
            ) { privacy, reveal ->
                { work: SavedWork ->
                    LibraryPrivacy.visibility(work, privacy, reveal) == LibraryPrivacyVisibility.Hidden
                }
            }
        )
    )
    // The Library's blur, for the matches that come from the reader's own library. Until the
    // setting has been read the default applies, which blurs.
    val privacy by remember(settingsRepository) {
        settingsRepository?.settings?.map { it.privacy } ?: flowOf(PrivacySettings())
    }.collectAsState(initial = PrivacySettings())
    val reveal by privacyGate.state.collectAsState()
    val activity = LocalContext.current as? androidx.fragment.app.FragmentActivity
    val filters by viewModel.filters.collectAsState()
    val state by viewModel.state.collectAsState()
    val savedSearches by viewModel.savedSearches.collectAsState()
    val localMatches by viewModel.localMatches.collectAsState()
    val isPaging by viewModel.isPaging.collectAsState()

    val remoteSelection = rememberRemoteWorkSelection()
    var localSelecting by remember { mutableStateOf(false) }
    var localSelection by remember { mutableStateOf<Set<String>>(emptySet()) }
    var showFilterSheet by remember { mutableStateOf(false) }
    var showSaveSheet by remember { mutableStateOf(false) }
    var saveName by remember { mutableStateOf("") }
    var pendingDeleteSearch by remember { mutableStateOf<SavedSearch?>(null) }
    var expandAllCards by remember { mutableStateOf(false) }
    var moreExpanded by remember { mutableStateOf(false) }
    var bulkBusy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val exitSearch = LocalSearchExit.current
    val overlay = LocalShellOverlayState.current
    val activeFilters = remember(filters) { activeFilterCount(filters) }
    val query = filters.query.trim()
    val showsLocal = state is SearchUiState.Idle && query.isNotEmpty()

    // Search is a destination in the navigation bar, so the bar stays, as on every tab. It
    // hides only while works are being selected, as in the Library.
    val selecting = remoteSelection.isSelecting || localSelecting
    DisposableEffect(selecting) {
        overlay.hidesTabBar = selecting
        onDispose { overlay.hidesTabBar = false }
    }

    LaunchedEffect(fandomCatalogCache) {
        val loaded = fandomCatalogCache?.load().orEmpty()
        viewModel.setCatalogFandoms(loaded.values.flatMap { it.fandoms })
    }
    LaunchedEffect(showsLocal) {
        if (!showsLocal) {
            localSelecting = false
            localSelection = emptySet()
        }
    }

    val savedWorks by (workRepository?.observeSavedWorks()
        ?: kotlinx.coroutines.flow.emptyFlow<List<SavedWork>>())
        .collectAsState(initial = emptyList())
    var userTagNames by remember { mutableStateOf<List<String>>(emptyList()) }
    LaunchedEffect(workRepository) {
        userTagNames = workRepository?.allUserTags()?.map { it.normalizedName }.orEmpty()
    }
    val localTagSuggestions = remember(savedWorks, userTagNames) {
        collectLocalTagSuggestions(savedWorks, userTagNames)
    }

    fun leaveSelection() {
        remoteSelection.exit()
        localSelecting = false
        localSelection = emptySet()
    }

    val tagRequestTick by SearchTagRequests.tick.collectAsState()
    LaunchedEffect(tagRequestTick) {
        SearchTagRequests.take()?.let { request ->
            leaveSelection()
            viewModel.searchTag(request.field, request.value, request.isFreshTabJump)
        }
    }

    fun goBack() {
        if (remoteSelection.isSelecting) {
            remoteSelection.exit()
            return
        }
        if (localSelecting) {
            localSelecting = false
            localSelection = emptySet()
            return
        }
        if (!viewModel.goBack()) exitSearch?.invoke()
    }

    BackHandler(enabled = !showFilterSheet && !showSaveSheet) { goBack() }

    fun submitQuery() {
        val url = SearchUrlEntry.normalize(filters.query)
        if (url != null && onOpenUrl != null) {
            onOpenUrl(url)
            viewModel.updateFilters(filters.copy(query = ""))
            return
        }
        leaveSelection()
        viewModel.runSearch()
    }

    fun commitSavedSearch() {
        val name = saveName.trim()
        if (name.isEmpty()) return
        viewModel.saveCurrentSearch(name)
        showSaveSheet = false
        saveName = ""
    }

    DestructiveConfirmation(
        show = pendingDeleteSearch != null,
        title = "Delete saved search?",
        text = "This will permanently remove “${pendingDeleteSearch?.name}” from your device.",
        confirmBeforeDelete = true,
        onConfirm = {
            val id = pendingDeleteSearch?.id ?: return@DestructiveConfirmation
            pendingDeleteSearch = null
            viewModel.deleteSavedSearch(id)
        },
        onDismissRequest = { pendingDeleteSearch = null }
    )

    val errorState = state as? SearchUiState.Error
    val resultsState = (state as? SearchUiState.Results) ?: errorState?.stale
    val resultsPalette = resultsPalette(resultsState, filters)
    val selectingRemote = remoteSelection.isSelecting && resultsState != null
    val selectingLocal = localSelecting && showsLocal

    Column(
        modifier = Modifier
            .fillMaxSize()
            .then(
                if (resultsState != null && resultsPalette != null) {
                    Modifier.subjectScreenWash(resultsPalette, 600.dp)
                } else {
                    Modifier
                }
            )
    ) {
        SearchChrome(
            filters = filters,
            activeFilters = activeFilters,
            query = filters.query,
            onQueryChange = { viewModel.updateFilters(filters.copy(query = it)) },
            onClearQuery = { viewModel.clearQuery() },
            onSubmit = ::submitQuery,
            onBack = ::goBack,
            onOpenFilters = { showFilterSheet = true },
            onClearFilters = {
                leaveSelection()
                viewModel.clearFilters()
            },
            showMore = (resultsState != null && resultsState.works.isNotEmpty()) ||
                (showsLocal && localMatches.works.isNotEmpty()),
            moreExpanded = moreExpanded,
            onMoreExpanded = { moreExpanded = it },
            expandAllCards = expandAllCards,
            showExpand = resultsState != null && resultsState.works.isNotEmpty(),
            onToggleExpand = { expandAllCards = !expandAllCards },
            onSelect = {
                if (resultsState != null && resultsState.works.isNotEmpty()) {
                    remoteSelection.enter()
                } else {
                    localSelecting = true
                    localSelection = emptySet()
                }
            },
            selectionTitle = when {
                selectingRemote -> selectionTitle(remoteSelection.count)
                selectingLocal -> selectionTitle(localSelection.size)
                else -> null
            },
            allSelected = when {
                selectingRemote -> {
                    val works = resultsState?.works.orEmpty()
                    works.isNotEmpty() && remoteSelection.count == works.size
                }
                selectingLocal -> localMatches.works.isNotEmpty() &&
                    localSelection.size == localMatches.works.size
                else -> false
            },
            onToggleSelectAll = {
                if (selectingRemote && resultsState != null) {
                    remoteSelection.toggleSelectAll(resultsState.works.map { it.remote.id })
                } else if (selectingLocal) {
                    localSelection = if (localSelection.size == localMatches.works.size) {
                        emptySet()
                    } else {
                        localMatches.works.mapTo(linkedSetOf()) { it.id }
                    }
                }
            }
        )

        Box(Modifier.weight(1f).fillMaxWidth()) {
            when {
                showsLocal -> LocalMatchesList(
                    query = query,
                    matches = localMatches,
                    isObscured = { work ->
                        LibraryPrivacy.visibility(work, privacy, reveal) == LibraryPrivacyVisibility.Obscured
                    },
                    onReveal = { id -> privacyGate.reveal(id, activity) },
                    selecting = localSelecting,
                    selection = localSelection,
                    onToggle = { id ->
                        localSelection = if (id in localSelection) localSelection - id else localSelection + id
                    },
                    onSelect = { id ->
                        localSelecting = true
                        localSelection = setOf(id)
                    },
                    onOpenWork = { onOpenWork(it.toRemoteSummary()) },
                    onSearchAo3 = {
                        leaveSelection()
                        viewModel.runSearch()
                    },
                    onSearchFandom = { name ->
                        leaveSelection()
                        viewModel.searchFandom(name)
                    },
                    onFilterLibraryFandom = onFilterLibraryFandom,
                    onFilterLibraryTag = onFilterLibraryTag,
                    onOpenCollection = onOpenCollection
                )
                state is SearchUiState.Loading -> SearchSkeletonList()
                resultsState != null -> {
                    Box(Modifier.fillMaxSize()) {
                        if (resultsState.works.isEmpty()) {
                            Column(Modifier.fillMaxSize()) {
                                SearchResultsHeader(
                                    filters = filters,
                                    page = resultsState.page,
                                    onPageCount = 0,
                                    isPaging = isPaging,
                                    onSortSelected = { sort ->
                                        val next = filters.copy(sort = sort)
                                        viewModel.updateFilters(next)
                                        viewModel.runSearch(searchFilters = next)
                                    },
                                    onPage = { viewModel.loadPage(it) }
                                )
                                if (errorState == null) {
                                    SearchEmpty(query = filters.query)
                                } else {
                                    SearchFailed(
                                        message = errorState.error.displayMessage(),
                                        onRetry = { viewModel.retry() }
                                    )
                                }
                            }
                        } else {
                            SearchResultsList(
                                works = resultsState.works,
                                page = resultsState.page,
                                filters = filters,
                                expandAll = expandAllCards,
                                isPaging = isPaging,
                                selecting = remoteSelection.isSelecting,
                                isSelected = { remoteSelection.isSelected(it) },
                                onToggleSelection = { remoteSelection.toggle(it) },
                                onOpenWork = onOpenWork,
                                onPage = {
                                    remoteSelection.exit()
                                    viewModel.loadPage(it)
                                },
                                onTagClick = { field, tag ->
                                    remoteSelection.exit()
                                    viewModel.searchTag(field, tag)
                                },
                                onSortSelected = { sort ->
                                    remoteSelection.exit()
                                    val next = filters.copy(sort = sort)
                                    viewModel.updateFilters(next)
                                    viewModel.runSearch(searchFilters = next)
                                },
                                onRefresh = { viewModel.refreshCurrentPage() }
                            )
                        }
                        if (errorState != null && resultsState.works.isNotEmpty()) {
                            Box(
                                modifier = Modifier
                                    .fillMaxSize()
                                    .background(
                                        LocalKudosTokens.current.background.copy(alpha = 0.92f)
                                    )
                                    .clickable(onClick = {}),
                                contentAlignment = Alignment.Center
                            ) {
                                SearchFailed(
                                    message = errorState.error.displayMessage(),
                                    onRetry = { viewModel.retry() }
                                )
                            }
                        }
                    }
                }
                errorState != null -> SearchFailed(
                    message = errorState.error.displayMessage(),
                    onRetry = { viewModel.retry() }
                )
                savedSearches.isNotEmpty() -> SavedSearchesList(
                    savedSearches = savedSearches,
                    subtitleFor = { saved ->
                        savedSearchRepository?.filtersOf(saved)?.let(::savedSearchSubtitle)
                    },
                    onRun = {
                        leaveSelection()
                        viewModel.runSavedSearch(it)
                    },
                    onDelete = { pendingDeleteSearch = it }
                )
                else -> SearchPrompt()
            }
        }

        if (selectingLocal && workRepository != null) {
            val selectedWorks = localMatches.works.filter { it.id in localSelection }
            WorkBulkActionBar(
                selectedWorks = selectedWorks,
                workRepository = workRepository,
                queueRepository = queueRepository,
                downloadQueue = downloadQueue,
                onDeleted = {
                    localSelecting = false
                    localSelection = emptySet()
                },
                onDone = {
                    localSelecting = false
                    localSelection = emptySet()
                }
            )
        }
        if (selectingRemote && workImporter != null && resultsState != null) {
            RemoteWorkSelectionBar(
                state = remoteSelection,
                busy = bulkBusy,
                onSaveToLibrary = {
                    val picked = remoteSelection.selectedIn(resultsState.works.map { it.remote })
                    scope.launch {
                        bulkBusy = true
                        RemoteWorkBulkActions.saveToLibrary(picked, workImporter)
                        bulkBusy = false
                        remoteSelection.exit()
                    }
                },
                onSaveForLater = {
                    val queues = queueRepository ?: return@RemoteWorkSelectionBar
                    val picked = remoteSelection.selectedIn(resultsState.works.map { it.remote })
                    scope.launch {
                        bulkBusy = true
                        RemoteWorkBulkActions.saveForLater(picked, workImporter, queues)
                        bulkBusy = false
                        remoteSelection.exit()
                    }
                }
            )
        }
    }

    val context = LocalContext.current
    val autocompleteRepository = remember {
        (context.applicationContext as? io.github.cidy02.kudos.KudosApplication)
            ?.container?.tagAutocompleteRepository
    }
    if (showFilterSheet) {
        SearchFilterSheet(
            localTagSuggestions = localTagSuggestions,
            filters = filters,
            onFiltersChange = { viewModel.updateFilters(it) },
            onApply = {
                showFilterSheet = false
                leaveSelection()
                viewModel.runSearch(page = 1, searchFilters = filters)
            },
            onClear = { viewModel.clearFilters() },
            onDismiss = { showFilterSheet = false },
            onSave = if (savedSearchRepository != null) {
                {
                    showFilterSheet = false
                    saveName = defaultSavedSearchName(filters)
                    showSaveSheet = true
                }
            } else {
                null
            },
            autocompleteRepository = autocompleteRepository
        )
    }
    if (showSaveSheet) {
        SaveSearchSheet(
            filters = filters,
            name = saveName,
            onNameChange = { saveName = it },
            onSave = ::commitSavedSearch,
            onDismiss = {
                showSaveSheet = false
                saveName = ""
            }
        )
    }
}

private fun selectionTitle(count: Int): String =
    if (count == 0) "Select Works" else "$count Selected"

@Composable
private fun resultsPalette(results: SearchUiState.Results?, filters: AO3SearchFilters): SubjectPalette? {
    if (results == null) return null
    val tokens = LocalKudosTokens.current
    val subject = results.page.summary
        ?.completing(
            subject = filters.searchSubject().text,
            page = results.page.currentPage,
            onPageCount = results.works.size
        )
        ?.subject
    return if (subject.isNullOrBlank()) {
        tokens.scopePalette
    } else {
        SubjectPalette.fromHue(HomeFacts.coverHue(subject), tokens.theme)
    }
}

@Composable
private fun SearchChrome(
    filters: AO3SearchFilters,
    activeFilters: Int,
    query: String,
    onQueryChange: (String) -> Unit,
    onClearQuery: () -> Unit,
    onSubmit: () -> Unit,
    onBack: () -> Unit,
    onOpenFilters: () -> Unit,
    onClearFilters: () -> Unit,
    showMore: Boolean,
    moreExpanded: Boolean,
    onMoreExpanded: (Boolean) -> Unit,
    expandAllCards: Boolean,
    showExpand: Boolean,
    onToggleExpand: () -> Unit,
    onSelect: () -> Unit,
    selectionTitle: String?,
    allSelected: Boolean,
    onToggleSelectAll: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        ToolbarCircleButton(onClick = onBack, accessibilityName = "Back") {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
        }
        if (selectionTitle != null) {
            Text(
                text = selectionTitle,
                modifier = Modifier
                    .weight(1f)
                    .padding(horizontal = 8.dp),
                color = tokens.primaryInk,
                fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            TextButton(onClick = onToggleSelectAll) {
                Text(if (allSelected) "Deselect All" else "Select All")
            }
        } else {
            GlassFieldBar(
                text = query,
                onTextChange = onQueryChange,
                placeholder = "Library and AO3",
                onSubmit = onSubmit,
                modifier = Modifier.weight(1f),
                leading = {
                    Icon(
                        imageVector = Icons.Outlined.Search,
                        contentDescription = null,
                        tint = tokens.secondaryInk,
                        modifier = Modifier.size(14.dp)
                    )
                },
                trailing = {
                    if (query.isNotEmpty()) {
                        IconButton(onClick = onClearQuery, modifier = Modifier.size(28.dp)) {
                            Icon(
                                imageVector = Icons.Filled.Cancel,
                                contentDescription = "Clear",
                                tint = tokens.secondaryInk,
                                modifier = Modifier.size(14.dp)
                            )
                        }
                    }
                }
            )
            FilterButton(
                filtersActive = filters.hasActiveFilters,
                onClick = onOpenFilters,
                badgeCount = activeFilters,
                onClearFilters = onClearFilters
            )
            if (showMore) {
                Box {
                    IconButton(onClick = { onMoreExpanded(true) }) {
                        Icon(
                            imageVector = Icons.Filled.MoreVert,
                            contentDescription = "More",
                            tint = tokens.primaryInk
                        )
                    }
                    DropdownMenu(expanded = moreExpanded, onDismissRequest = { onMoreExpanded(false) }) {
                        DropdownMenuItem(
                            text = { Text("Select") },
                            onClick = {
                                onMoreExpanded(false)
                                onSelect()
                            }
                        )
                        if (showExpand) {
                            DropdownMenuItem(
                                text = { Text(if (expandAllCards) "Collapse All Cards" else "Expand All Cards") },
                                onClick = {
                                    onMoreExpanded(false)
                                    onToggleExpand()
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SearchPrompt() {
    val tokens = LocalKudosTokens.current
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            imageVector = Icons.Outlined.Search,
            contentDescription = null,
            tint = tokens.secondaryInk,
            modifier = Modifier.size(40.dp)
        )
        Text(
            text = "Search Kudos",
            color = tokens.primaryInk,
            fontSize = 20.sp,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(top = 8.dp)
        )
        Text(
            text = "Search your Library or AO3 by title, author, or tag. " +
                "You can browse fandoms and categories in the Browse tab.",
            color = tokens.secondaryInk,
            fontSize = 15.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 6.dp)
        )
    }
}

@Composable
private fun SearchFailed(message: String, onRetry: () -> Unit) {
    val tokens = LocalKudosTokens.current
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = "Search failed",
            color = tokens.primaryInk,
            fontSize = 20.sp,
            fontWeight = FontWeight.SemiBold
        )
        Text(
            text = message,
            color = tokens.secondaryInk,
            fontSize = 15.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 6.dp)
        )
        TextButton(onClick = onRetry, modifier = Modifier.padding(top = 8.dp)) {
            Text("Try Again")
        }
    }
}

@Composable
private fun SearchEmpty(query: String) {
    val tokens = LocalKudosTokens.current
    val detail = query.trim().let { text ->
        if (text.isEmpty()) "No results." else "No results for “$text”."
    }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 32.dp, vertical = 48.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text("No Results", color = tokens.primaryInk, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
        Text(detail, color = tokens.secondaryInk, fontSize = 15.sp, textAlign = TextAlign.Center)
    }
}

@Composable
private fun SearchSkeletonList() {
    val tokens = LocalKudosTokens.current
    val bar = tokens.glassFill(0.18)
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        repeat(7) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .subjectPanel()
                    .padding(horizontal = 14.dp, vertical = 14.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Box(Modifier.fillMaxWidth(0.72f).height(16.dp).background(bar, RoundedCornerShape(4.dp)))
                Box(Modifier.fillMaxWidth(0.42f).height(12.dp).background(bar, RoundedCornerShape(4.dp)))
                Box(Modifier.fillMaxWidth().height(12.dp).background(bar, RoundedCornerShape(4.dp)))
            }
        }
    }
}

@Composable
private fun SavedSearchesList(
    savedSearches: List<SavedSearch>,
    subtitleFor: (SavedSearch) -> String?,
    onRun: (SavedSearch) -> Unit,
    onDelete: (SavedSearch) -> Unit
) {
    val tokens = LocalKudosTokens.current
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        item {
            SectionRuleHeader(title = "Saved Searches", modifier = Modifier.padding(top = 8.dp))
        }
        items(savedSearches, key = { it.id }) { saved ->
            val subtitle = subtitleFor(saved)
            Row(
                modifier = Modifier
                    .padding(horizontal = 16.dp)
                    .fillMaxWidth()
                    .subjectPanel()
                    .clickable { onRun(saved) }
                    .padding(horizontal = 14.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(saved.name, color = tokens.primaryInk, fontSize = 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (!subtitle.isNullOrBlank()) {
                        Text(
                            subtitle,
                            color = tokens.secondaryInk,
                            fontSize = 12.sp,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
                IconButton(onClick = { onDelete(saved) }) {
                    Icon(Icons.Outlined.Delete, contentDescription = "Delete saved search", tint = tokens.secondaryInk)
                }
            }
        }
        item {
            Text(
                text = "Search above for works in your Library or on AO3. " +
                    "To explore by fandom, use the Browse tab.",
                color = tokens.secondaryInk,
                fontSize = 12.sp,
                modifier = Modifier.padding(horizontal = SubjectMetrics.gutter, vertical = 8.dp)
            )
        }
    }
}

@Composable
private fun LocalMatchesList(
    query: String,
    matches: SearchLocalMatches,
    isObscured: (SavedWork) -> Boolean,
    onReveal: (String) -> Unit,
    selecting: Boolean,
    selection: Set<String>,
    onToggle: (String) -> Unit,
    onSelect: (String) -> Unit,
    onOpenWork: (SavedWork) -> Unit,
    onSearchAo3: () -> Unit,
    onSearchFandom: (String) -> Unit,
    onFilterLibraryFandom: (String) -> Unit,
    onFilterLibraryTag: (String) -> Unit,
    onOpenCollection: (String) -> Unit
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        item {
            SectionRuleHeader(title = "Archive of Our Own", modifier = Modifier.padding(top = 8.dp))
            MatchRow(
                icon = Icons.Outlined.Search,
                title = "Search AO3 for “$query”",
                onClick = onSearchAo3
            )
        }
        if (matches.works.isNotEmpty()) {
            item { SectionRuleHeader(title = "In Your Library", modifier = Modifier.padding(top = 8.dp)) }
            items(matches.works, key = { it.id }) { work ->
                val selected = work.id in selection
                SensitiveWorkRow(
                    work = work,
                    onOpenWork = { onOpenWork(work) },
                    selected = selecting && selected,
                    selecting = selecting,
                    // A library match is the reader's own library: the Library's blur applies
                    // (audit A18-4; iOS draws these with the row that blurs itself).
                    obscured = isObscured(work),
                    onReveal = { onReveal(work.id) },
                    onSelect = { onToggle(work.id) },
                    onLongClick = { onSelect(work.id) },
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)
                )
            }
        }
        if (matches.libraryFandoms.isNotEmpty()) {
            item {
                SectionRuleHeader(title = "Fandoms in Your Library", modifier = Modifier.padding(top = 8.dp))
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    matches.libraryFandoms.forEach { fandom ->
                        MatchRow(
                            icon = Icons.AutoMirrored.Outlined.MenuBook,
                            title = fandom,
                            onClick = { onFilterLibraryFandom(fandom) }
                        )
                    }
                }
            }
        }
        if (matches.ao3Fandoms.isNotEmpty()) {
            item {
                SectionRuleHeader(title = "Fandoms on AO3", modifier = Modifier.padding(top = 8.dp))
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    matches.ao3Fandoms.forEach { fandom ->
                        MatchRow(
                            icon = Icons.AutoMirrored.Outlined.MenuBook,
                            title = fandom.name,
                            trailing = fandom.workCount?.compactCount(),
                            onClick = { onSearchFandom(fandom.name) }
                        )
                    }
                }
            }
        }
        if (matches.tags.isNotEmpty()) {
            item {
                SectionRuleHeader(title = "Your Tags", modifier = Modifier.padding(top = 8.dp))
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    matches.tags.forEach { tag ->
                        MatchRow(
                            icon = Icons.Outlined.Label,
                            title = tag.name,
                            onClick = { onFilterLibraryTag(tag.name) }
                        )
                    }
                }
            }
        }
        if (matches.collections.isNotEmpty()) {
            item {
                SectionRuleHeader(title = "Collections", modifier = Modifier.padding(top = 8.dp))
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    matches.collections.forEach { collection ->
                        MatchRow(
                            icon = Icons.Outlined.CollectionsBookmark,
                            title = collection.name,
                            onClick = { onOpenCollection(collection.id) }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun MatchRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    onClick: () -> Unit,
    trailing: String? = null
) {
    val tokens = LocalKudosTokens.current
    Row(
        modifier = Modifier
            .padding(horizontal = 16.dp)
            .fillMaxWidth()
            .subjectPanel()
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Icon(icon, contentDescription = null, tint = tokens.secondaryInk, modifier = Modifier.size(18.dp))
        Text(
            text = title,
            color = tokens.primaryInk,
            fontSize = 16.sp,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f)
        )
        if (trailing != null) {
            Text(trailing, color = tokens.secondaryInk, fontSize = 12.sp)
        }
    }
}

@Composable
private fun SearchResultsHeader(
    filters: AO3SearchFilters,
    page: AO3SearchPage,
    onPageCount: Int,
    isPaging: Boolean,
    onSortSelected: (AO3SearchSort) -> Unit,
    onPage: (Int) -> Unit
) {
    val subject = filters.searchSubject()
    Column(Modifier.fillMaxWidth().padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        page.summary?.let { summary ->
            SearchResultsHero(
                summary = summary.completing(
                    subject = subject.text,
                    page = page.currentPage,
                    onPageCount = onPageCount
                ),
                filterLabels = summaryLabels(filters, excluding = subject.text),
                presentation = SearchHeroPresentation.SubjectPage,
                currentPage = page.currentPage,
                totalPages = page.totalPages,
                sort = filters.sort,
                onSortSelected = onSortSelected
            )
        }
        if (page.totalPages > 1) {
            KudosPaginationBar(
                currentPage = page.currentPage,
                totalPages = page.totalPages,
                onPageChange = onPage,
                enabled = !isPaging,
                modifier = Modifier.padding(horizontal = 8.dp)
            )
        }
    }
}

@Composable
private fun SearchResultsList(
    works: List<CanonicalWork>,
    page: AO3SearchPage,
    filters: AO3SearchFilters,
    expandAll: Boolean,
    isPaging: Boolean,
    selecting: Boolean,
    isSelected: (Long) -> Boolean,
    onToggleSelection: (Long) -> Unit,
    onOpenWork: (AO3WorkSummary) -> Unit,
    onPage: (Int) -> Unit,
    onTagClick: (SearchSubjectField, String) -> Unit,
    onSortSelected: (AO3SearchSort) -> Unit,
    onRefresh: suspend () -> Unit
) {
    val listState = rememberLazyListState()
    LaunchedEffect(page.currentPage) {
        listState.animateScrollToItem(0)
    }
    KudosRefreshBox(onRefresh = onRefresh, modifier = Modifier.fillMaxSize()) {
        LazyColumn(
            state = listState,
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                SearchResultsHeader(
                    filters = filters,
                    page = page,
                    onPageCount = works.size,
                    isPaging = isPaging,
                    onSortSelected = onSortSelected,
                    onPage = onPage
                )
            }
            items(works, key = { it.id }) { work ->
                if (selecting) {
                    SelectableRemoteWorkRow(
                        work = work.remote,
                        selected = isSelected(work.remote.id),
                        onToggle = { onToggleSelection(work.remote.id) },
                        modifier = Modifier.padding(horizontal = 16.dp)
                    )
                } else {
                    SensitiveWorkRow(
                        work = work.remote,
                        onOpenWork = onOpenWork,
                        expandAll = expandAll,
                        onTagSearch = onTagClick,
                        modifier = Modifier.padding(horizontal = 16.dp)
                    )
                }
            }
            if (page.totalPages > 1) {
                item {
                    KudosPaginationBar(
                        currentPage = page.currentPage,
                        totalPages = page.totalPages,
                        onPageChange = onPage,
                        enabled = !isPaging,
                        modifier = Modifier.padding(horizontal = 8.dp)
                    )
                }
            }
        }
    }
}

private fun SavedWork.toRemoteSummary(): AO3WorkSummary {
    return AO3WorkSummary(
        id = WorkTags.ao3WorkIdFromUrl(sourceUrl) ?: 0,
        title = title,
        authors = author.split(",").map { it.trim() }.filter { it.isNotEmpty() },
        fandoms = workFandoms,
        rating = rating,
        warnings = workWarnings,
        categories = workCategories,
        relationships = workRelationships,
        characters = workCharacters,
        freeforms = workFreeforms,
        language = language,
        wordCount = wordCount,
        chapters = chapters,
        kudos = kudos,
        comments = comments,
        hits = hits
    )
}
