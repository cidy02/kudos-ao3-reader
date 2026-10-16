package io.github.cidy02.kudos.browse

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.UnfoldLess
import androidx.compose.material.icons.outlined.UnfoldMore
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.network.ao3.browse.AO3BrowseRepository
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.search.SearchFilterSheet
import io.github.cidy02.kudos.search.activeFilterCount
import io.github.cidy02.kudos.search.collectLocalTagSuggestions
import io.github.cidy02.kudos.ui.components.SensitiveWorkRow
import io.github.cidy02.kudos.ui.components.KudosPaginationBar
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.KudosSectionHeader
import io.github.cidy02.kudos.ui.subject.FilterButton
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.ToolbarCircleButton
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.components.MetadataChipRow
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.works.WorkImporter
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.ui.components.rememberRemoteWorkSelection
import io.github.cidy02.kudos.ui.components.SelectableRemoteWorkRow
import io.github.cidy02.kudos.ui.components.RemoteWorkSelectionBar
import io.github.cidy02.kudos.ui.components.RemoteWorkBulkActions
import kotlinx.coroutines.launch
import io.github.cidy02.kudos.search.summaryLabels
import io.github.cidy02.kudos.search.SearchResultsHero
import io.github.cidy02.kudos.network.ao3.displayMessage

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun FandomWorksScreen(
    fandomName: String,
    workRepository: WorkRepository,
    onOpenWork: (AO3WorkSummary) -> Unit,
    workImporter: WorkImporter? = null,
    readingQueueRepository: ReadingQueueRepository? = null,
    repository: AO3BrowseRepository = remember { AO3BrowseRepository() },
    settingsRepository: io.github.cidy02.kudos.data.preferences.SettingsRepository? = null,
    privacyGate: io.github.cidy02.kudos.app.PrivacyGate? = null,
    /** Any tag's works (a tag tapped in a work's text), worded for a tag: iOS's `TagWorksView`
     *  is this page too. It had a page of its own of the old design (3eb). */
    isTag: Boolean = false,
    includedFandoms: List<String> = listOf(fandomName)
) {
    var state by remember(fandomName) { mutableStateOf<FandomWorksState>(FandomWorksState.Loading) }
    // The *browse* baseline, not a bare AO3SearchFilters(): AO3's tag listing has no
    // relevance ordering, so RELEVANCE would send no sort_column, AO3 would sort by
    // revised_at, and the sheet would sit there claiming "Best Match".
    var filters by remember { mutableStateOf(AO3BrowseRepository.browseBaseline()) }
    // The filters the page on screen was asked for. The sheet edits `filters` itself, so closing
    // it without Apply left edits that the next page then sent: page 7 of a filter nobody
    // applied (audit A20-3, the same on iOS).
    var loadedFilters by remember { mutableStateOf(filters) }
    var showFilterSheet by remember { mutableStateOf(false) }
    var showMenu by remember { mutableStateOf(false) }
    var expandAllCards by remember { mutableStateOf(false) }
    val selection = rememberRemoteWorkSelection()
    var bulkBusy by remember { mutableStateOf(false) }
    var bulkStatus by remember { mutableStateOf<String?>(null) }
    
    // Guards a fast Previous/Next double-tap from letting the first (older) page's
    // response land after the second (newer) one and overwrite it.
    var loadGeneration by remember(fandomName) { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    // The badge on a result you already have, and the filter's tag suggestions, are drawn from
    // the Library: not from a work Hide Mature hides (audit A38; iOS leaves it out of the pairing).
    val allSavedWorks by workRepository.observeSavedWorks().collectAsState(initial = emptyList())
    val savedWorks = io.github.cidy02.kudos.library.rememberShownWorks(allSavedWorks, settingsRepository, privacyGate)
    var userTagNames by remember { mutableStateOf<List<String>>(emptyList()) }
    LaunchedEffect(workRepository) {
        userTagNames = workRepository.allUserTags().map { it.normalizedName }
    }
    val localTagSuggestions = remember(savedWorks, userTagNames) {
        collectLocalTagSuggestions(savedWorks, userTagNames)
    }
    val savedByUrl = remember(savedWorks) { BrowseLocalIndicators.index(savedWorks) }
    val browseDefault = remember { AO3BrowseRepository.browseBaseline() }
    val activeFilters = remember(filters) { activeFilterCount(filters) }
    val narrowed = filters != browseDefault
    val palette = fandomListPalette(fandomName)
    
    val context = LocalContext.current
    val autocompleteRepository = remember {
        (context.applicationContext as? io.github.cidy02.kudos.KudosApplication)?.container?.tagAutocompleteRepository
    }

    suspend fun fetch(page: Int, with: AO3SearchFilters) =
        if (isTag) repository.worksForTag(fandomName, page, with) else repository.worksForFandoms(includedFandoms, page, with)

    fun load(page: Int = 1) {
        loadedFilters = filters
        state = FandomWorksState.Loading
        val generation = ++loadGeneration
        scope.launch {
            val result = when (val result = fetch(page, filters)) {
                is AO3Result.Success -> FandomWorksState.Loaded(result.value)
                is AO3Result.Failure -> FandomWorksState.Error(result.error.displayMessage(), page)
            }
            if (generation == loadGeneration) state = result
        }
    }

    /**
     * Pull to refresh: the page on screen again, with the filters it was asked for, and it stays
     * there until the answer is in. iOS's list of a fandom's works can be pulled; this could not.
     */
    suspend fun refresh() {
        val page = (state as? FandomWorksState.Loaded)?.page?.currentPage ?: return
        val generation = ++loadGeneration
        val result = when (val result = fetch(page, loadedFilters)) {
            is AO3Result.Success -> FandomWorksState.Loaded(result.value)
            is AO3Result.Failure -> FandomWorksState.Error(result.error.displayMessage(), page)
        }
        if (generation == loadGeneration) state = result
    }

    LaunchedEffect(fandomName) { load() }

    ProvidePushedShellChrome(
        hasSubjectHeader = true,
        trailingContent = {
            FilterButton(
                filtersActive = narrowed,
                onClick = { showFilterSheet = true },
                badgeCount = if (narrowed) activeFilters else 0,
                onClearFilters = { filters = browseDefault; load() }
            )
            Box {
                ToolbarCircleButton(
                    onClick = { showMenu = true },
                    accessibilityName = "More",
                    palette = palette
                ) {
                    Icon(Icons.Default.MoreVert, contentDescription = null)
                }
                DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                    if (workImporter != null) {
                        DropdownMenuItem(
                            text = { Text(if (selection.isSelecting) "Exit selection" else "Select") },
                            leadingIcon = { Icon(Icons.Outlined.Checklist, contentDescription = null) },
                            onClick = {
                                showMenu = false
                                if (selection.isSelecting) selection.exit() else selection.enter()
                            }
                        )
                    }
                    DropdownMenuItem(
                        text = { Text(if (expandAllCards) "Collapse All" else "Expand All") },
                        leadingIcon = {
                            Icon(
                                if (expandAllCards) Icons.Outlined.UnfoldLess else Icons.Outlined.UnfoldMore,
                                contentDescription = null
                            )
                        },
                        onClick = {
                            showMenu = false
                            expandAllCards = !expandAllCards
                        }
                    )
                }
            }
        }
    )

    Column(
        modifier = Modifier
            .fillMaxSize()
            .subjectScreenWash(palette)
    ) {
        Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
        Spacer(Modifier.height(56.dp))
        // Until the works are in, the fandom names the page. Then the results' own head does,
        // as iOS's Browse page (spec 1k): there were two heads, this one over the old card.
        if ((state as? FandomWorksState.Loaded)?.page?.summary == null) {
            SubjectHeaderBlock(
                kicker = "Browse",
                title = fandomName,
                palette = palette
            )
        }

        when (val current = state) {
            FandomWorksState.Loading -> LoadingStateCard(
                "Loading fandom works",
                Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
            )
            is FandomWorksState.Error -> BrowseErrorBlock(
                message = current.message,
                onRetry = { load(current.page) },
                title = "Couldn't load works",
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
            )
            is FandomWorksState.Loaded -> {
                if (current.page.works.isEmpty()) {
                    EmptyStateCard(
                        title = if (narrowed) "No matching works" else "No works found",
                        message = if (narrowed) {
                            if (isTag) "No works with this tag match your filters." else "No works in this fandom match your filters."
                        } else {
                            "AO3 has no works for this ${if (isTag) "tag" else "fandom"} right now."
                        },
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                        primaryActionLabel = if (narrowed) "Clear Filters" else null,
                        onPrimaryAction = if (narrowed) {
                            { filters = browseDefault; load() }
                        } else {
                            null
                        }
                    )
                } else {
                    io.github.cidy02.kudos.ui.components.KudosRefreshBox(
                        onRefresh = { refresh() },
                        // weight(fill = false) so the selection bar below keeps its
                        // space when selecting, without stretching the list otherwise.
                        modifier = Modifier
                            .fillMaxWidth()
                            .weight(1f, fill = false)
                    ) {
                        // No side padding on the list: the results' head carries its own margins,
                        // as on Search; the pagers and rows take theirs.
                        LazyColumn(
                            verticalArrangement = Arrangement.spacedBy(12.dp),
                            contentPadding = PaddingValues(vertical = 12.dp),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            item {
                                current.page.summary?.let { summary ->
                                    SearchResultsHero(
                                        summary = summary.completing(
                                            subject = fandomName,
                                            page = current.page.currentPage,
                                            onPageCount = current.page.works.size
                                        ),
                                        filterLabels = summaryLabels(filters, excluding = fandomName),
                                        subjectCategory = summary.subjectCategory(current.page.works),
                                        onEditFilters = { showFilterSheet = true },
                                        // iOS: the page's own head, with the sort beside the
                                        // subject; a tag listing has no Best Match.
                                        presentation = io.github.cidy02.kudos.search.SearchHeroPresentation.SubjectPage,
                                        currentPage = current.page.currentPage,
                                        totalPages = current.page.totalPages,
                                        sort = filters.sort,
                                        sortOptions = io.github.cidy02.kudos.network.ao3.search.AO3SearchSort.entries
                                            .filter { it != io.github.cidy02.kudos.network.ao3.search.AO3SearchSort.RELEVANCE },
                                        onSortSelected = { sort -> filters = filters.withSort(sort); load() },
                                        modifier = Modifier.padding(bottom = 4.dp)
                                    )
                                }
                                // Above the results as well as below, matching Apple:
                                // the pager was reachable only after scrolling the
                                // whole page, so changing page meant reading to the
                                // bottom of one you had already decided to leave.
                                KudosPaginationBar(
                                    currentPage = current.page.currentPage,
                                    totalPages = current.page.totalPages,
                                    onPageChange = { load(it) },
                                    modifier = Modifier.padding(horizontal = 16.dp)
                                )
                            }
                            items(current.page.works, key = { it.id }) { work ->
                                if (selection.isSelecting) {
                                    SelectableRemoteWorkRow(
                                        work = work,
                                        selected = selection.isSelected(work.id),
                                        onToggle = { selection.toggle(work.id) },
                                        modifier = Modifier.padding(horizontal = 16.dp)
                                    )
                                } else {
                                    Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                        LocalIndicatorRow(BrowseLocalIndicators.forWork(work, savedByUrl))
                                        SensitiveWorkRow(
                                            work = work,
                                            onOpenWork = onOpenWork,
                                            expandAll = expandAllCards,
                                            ledger = true
                                        )
                                    }
                                }
                            }
                            item {
                                KudosPaginationBar(
                                    currentPage = current.page.currentPage,
                                    totalPages = current.page.totalPages,
                                    onPageChange = { load(it) },
                                    modifier = Modifier.padding(horizontal = 16.dp)
                                )
                            }
                        }
                    }
                }
            }
        }
        if (selection.isSelecting && workImporter != null) {
            RemoteWorkSelectionBar(
                state = selection,
                busy = bulkBusy,
                onSaveToLibrary = {
                    val picked = selection.selectedIn((state as? FandomWorksState.Loaded)?.page?.works.orEmpty())
                    scope.launch {
                        bulkBusy = true
                        bulkStatus = RemoteWorkBulkActions.saveToLibrary(picked, workImporter)
                        bulkBusy = false
                        selection.exit()
                    }
                },
                onSaveForLater = {
                    val queues = readingQueueRepository ?: return@RemoteWorkSelectionBar
                    val picked = selection.selectedIn((state as? FandomWorksState.Loaded)?.page?.works.orEmpty())
                    scope.launch {
                        bulkBusy = true
                        bulkStatus = RemoteWorkBulkActions.saveForLater(picked, workImporter, queues)
                        bulkBusy = false
                        selection.exit()
                    }
                }
            )
        }
    }


    bulkStatus?.let { message ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { bulkStatus = null },
            title = { Text("Selection") },
            text = { Text(message) },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = { bulkStatus = null }) { Text("OK") }
            }
        )
    }

    if (showFilterSheet) {
        SearchFilterSheet(
            filters = filters,
            allowsRelevanceSort = false,
            showFandomPicker = false,
            canReset = narrowed,
            onFiltersChange = { filters = it },
            onApply = { showFilterSheet = false; load() },
            onClear = { filters = AO3BrowseRepository.browseBaseline(); load() },
            onDismiss = { showFilterSheet = false; filters = loadedFilters },
            localTagSuggestions = localTagSuggestions,
            autocompleteRepository = autocompleteRepository,
            opensHalfHeight = true
        )
    }
}

@Composable
private fun LocalIndicatorRow(indicator: BrowseLocalIndicator) {
    if (!indicator.any) return
    val labels = buildList {
        // isSaved ("kept permanently") is a finer distinction than hasEpub ("file is
        // present") that belongs on Work Detail's own toggle, not a scan-list chip —
        // showing both here read as a stale duplicate "Downloaded" after the isSaved
        // wording rename (both used to say different things: "Saved" vs "Downloaded").
        if (indicator.isDownloaded) add("Downloaded")
        if (indicator.isFavorite) add("Favorite")
        if (indicator.isFinished) add("Finished")
    }
    MetadataChipRow(labels = labels, prominent = true)
}

private sealed interface FandomWorksState {
    data object Loading : FandomWorksState
    data class Loaded(val page: AO3SearchPage) : FandomWorksState
    data class Error(val message: String, val page: Int) : FandomWorksState
}
