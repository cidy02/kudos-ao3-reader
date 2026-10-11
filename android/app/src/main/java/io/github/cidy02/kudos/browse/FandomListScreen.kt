package io.github.cidy02.kudos.browse

import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.browse.AO3BrowseRepository
import io.github.cidy02.kudos.network.ao3.browse.AO3BrowseUrls
import io.github.cidy02.kudos.network.ao3.browse.AO3Fandom
import io.github.cidy02.kudos.network.ao3.browse.AO3MediaCategory
import io.github.cidy02.kudos.network.ao3.displayMessage
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.subject.FilterButton
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.works.WorkSearchIndex
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun FandomListScreen(
    category: AO3MediaCategory,
    onOpenFandom: (AO3Fandom) -> Unit,
    onOpenWebFallback: (String) -> Unit,
    workRepository: WorkRepository? = null,
    repository: AO3BrowseRepository = remember { AO3BrowseRepository() },
    settingsRepository: io.github.cidy02.kudos.data.preferences.SettingsRepository? = null,
    privacyGate: io.github.cidy02.kudos.app.PrivacyGate? = null
) {
    var phase by remember(category.name) { mutableStateOf<FandomListPhase>(FandomListPhase.Loading) }
    var families by remember(category.name) { mutableStateOf<List<FandomFamily>>(emptyList()) }
    var shown by remember(category.name) { mutableStateOf<List<FandomFamily>>(emptyList()) }
    var query by remember(category.name) { mutableStateOf("") }
    var debouncedQuery by remember(category.name) { mutableStateOf("") }
    var sort by remember(category.name) { mutableStateOf(FandomFamilySort.FamilyTotal) }
    var groupsVariants by remember(category.name) { mutableStateOf(true) }
    var options by remember(category.name) { mutableStateOf(FandomListFilterOptions()) }
    var showFilters by remember(category.name) { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    val palette = fandomListPalette(category.name)
    val libraryWorks by remember(workRepository) {
        workRepository?.observeLibraryWorks() ?: flowOf(emptyList())
    }.collectAsState(initial = emptyList())
    // Not a work Hide Mature hides (audit A38).
    val shownWorks = io.github.cidy02.kudos.library.rememberShownWorks(libraryWorks, settingsRepository, privacyGate)
    val library = remember(shownWorks) { FandomLibraryIndex.from(shownWorks) }
    val source = (phase as? FandomListPhase.Loaded)?.fandoms.orEmpty()

    fun webFallback() {
        AO3BrowseUrls.resolveAo3Url(category.fandomsPath)?.let(onOpenWebFallback)
            ?: onOpenWebFallback(AO3BrowseUrls.mediaIndexUrl())
    }

    suspend fun loadNow() {
        phase = FandomListPhase.Loading
        phase = when (val result = repository.fandoms(category)) {
            is AO3Result.Success -> FandomListPhase.Loaded(result.value)
            is AO3Result.Failure -> FandomListPhase.Error(result.error.displayMessage())
        }
    }

    fun open(fandom: AO3Fandom) {
        // Visit recording is the caller's job. Launching it here races that
        // write and inserts a second watermark for the same raw name.
        onOpenFandom(fandom)
    }

    LaunchedEffect(category.name) { loadNow() }

    LaunchedEffect(source, groupsVariants) {
        if (phase !is FandomListPhase.Loaded) return@LaunchedEffect
        families = withContext(Dispatchers.Default) {
            if (groupsVariants) FandomFamily.grouped(source) else FandomFamily.ungrouped(source)
        }
    }

    LaunchedEffect(query) {
        if (query.isNotBlank()) delay(120)
        debouncedQuery = query
    }

    LaunchedEffect(families, debouncedQuery, options, sort, library) {
        shown = withContext(Dispatchers.Default) {
            val needle = WorkSearchIndex.normalize(debouncedQuery.trim())
            val matched = if (needle.isEmpty()) {
                families
            } else {
                families.filter { it.searchHaystack().contains(needle) }
            }
            FandomFamily.sorted(
                FandomFamilyFilters.apply(matched, options, library),
                sort
            )
        }
    }

    val isFiltered = query.trim().isNotEmpty() || options.hasActiveFilters
    val tally = FandomListTally.text(
        totalTags = FandomFamilyFilters.tagCount(families),
        families = if (groupsVariants) families.size else null,
        shownTags = FandomFamilyFilters.tagCount(shown),
        isFiltered = isFiltered,
        sort = sort
    )
    val sections = if (sort == FandomFamilySort.Alphabetical) {
        FandomFamily.letterSections(shown)
    } else {
        emptyList()
    }
    val showIndex = sort == FandomFamilySort.Alphabetical && query.trim().isEmpty() && sections.isNotEmpty()

    // iOS 1al: a back button and the filter button over the wash, and no title: the page's
    // header block is the title. This page had kept a titled bar ("Fandoms") above it.
    io.github.cidy02.kudos.app.ProvidePushedShellChrome(
        hasSubjectHeader = true,
        trailingContent = {
            FilterButton(
                filtersActive = options.hasActiveFilters,
                onClick = { showFilters = true },
                badgeCount = options.activeFilterCount,
                onClearFilters = { options = FandomListFilterOptions() }
            )
        }
    )

    KudosRefreshBox(onRefresh = { loadNow() }, modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .subjectScreenWash(palette)
        ) {
            androidx.compose.foundation.layout.Spacer(
                Modifier.windowInsetsTopHeight(androidx.compose.foundation.layout.WindowInsets.statusBars)
            )
            androidx.compose.foundation.layout.Spacer(Modifier.height(56.dp))
            when (val current = phase) {
                FandomListPhase.Loading -> LoadingStateCard("Loading fandoms")
                is FandomListPhase.Error -> Column {
                    FandomListHeader(category, tally, palette)
                    BrowseErrorBlock(
                        message = current.message,
                        onRetry = { scope.launch { loadNow() } },
                        onWebFallback = ::webFallback,
                        title = "Couldn't load fandoms",
                        retryLabel = "Try Again"
                    )
                }
                is FandomListPhase.Loaded -> Box(modifier = Modifier.fillMaxSize()) {
                    LazyColumn(state = listState, modifier = Modifier.fillMaxSize()) {
                        item(key = "header") { FandomListHeader(category, tally, palette) }
                        item(key = "sort") {
                            FandomListSortRail(
                                sort = sort,
                                groupsVariants = groupsVariants,
                                palette = palette,
                                onSort = { sort = it },
                                onGroupsVariants = { on ->
                                    groupsVariants = on
                                    options = options.groupsVariantsChanged(on)
                                }
                            )
                        }
                        item(key = "search") {
                            // The app's own field. "Open on AO3" stays where iOS has it: on the
                            // page shown when the list cannot be read.
                            io.github.cidy02.kudos.ui.components.GlassFieldBar(
                                text = query,
                                onTextChange = { query = it },
                                placeholder = "Search ${category.name}",
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 16.dp, vertical = 10.dp),
                                leading = {
                                    Icon(androidx.compose.material.icons.Icons.Filled.Search, contentDescription = null,
                                        tint = LocalKudosTokens.current.secondaryInk,
                                        modifier = Modifier.size(18.dp))
                                }
                            )
                        }
                        if (shown.isEmpty() && isFiltered) {
                            item(key = "empty") {
                                Column(modifier = Modifier.padding(horizontal = 20.dp, vertical = 24.dp)) {
                                    Text(
                                        text = "No matching fandoms",
                                        color = LocalKudosTokens.current.primaryInk
                                    )
                                    Text(
                                        text = "No fandom in ${category.name} matches your search and filters.",
                                        color = LocalKudosTokens.current.secondaryInk,
                                        modifier = Modifier.padding(top = 6.dp)
                                    )
                                    TextButton(onClick = {
                                        query = ""
                                        options = FandomListFilterOptions()
                                    }) { Text("Clear Search and Filters") }
                                }
                            }
                        } else if (sort == FandomFamilySort.Alphabetical) {
                            sections.forEach { section ->
                                item(key = "letter-${section.letter}") {
                                    FandomLetterHeader(section.letter, section.families.size, palette)
                                }
                                items(section.families, key = { it.id }) { family ->
                                    FandomFamilyRow(
                                        family = family,
                                        sort = sort,
                                        library = library,
                                        palette = palette,
                                        onOpenFamily = { open(it) },
                                        onOpenMember = { open(it) }
                                    )
                                }
                            }
                        } else {
                            items(shown, key = { it.id }) { family ->
                                FandomFamilyRow(
                                    family = family,
                                    sort = sort,
                                    library = library,
                                    palette = palette,
                                    onOpenFamily = { open(it) },
                                    onOpenMember = { open(it) }
                                )
                            }
                        }
                    }
                    if (showIndex) {
                        FandomLetterIndex(
                            available = sections.map { it.letter }.toSet(),
                            onPick = { letter ->
                                scope.launch {
                                    val index = letterItemIndex(sections, letter)
                                    if (index >= 0) listState.scrollToItem(index)
                                }
                            },
                            modifier = Modifier.align(Alignment.CenterEnd)
                        )
                    }
                }
            }
        }
    }

    if (showFilters && phase is FandomListPhase.Loaded) {
        FandomListFilterSheet(
            options = options,
            families = families,
            groupsVariants = groupsVariants,
            library = library,
            palette = palette,
            onApply = {
                options = it
                showFilters = false
            },
            onDismiss = { showFilters = false }
        )
    }
}

/** Header, sort rail, and search occupy the first three lazy items. */
private fun letterItemIndex(sections: List<FandomFamily.LetterSection>, letter: String): Int {
    var index = 3
    for (section in sections) {
        if (section.letter == letter) return index
        index += 1 + section.families.size
    }
    return -1
}

private sealed interface FandomListPhase {
    data object Loading : FandomListPhase
    data class Loaded(val fandoms: List<AO3Fandom>) : FandomListPhase
    data class Error(val message: String) : FandomListPhase
}

/** Diacritic-insensitive, case-insensitive fold — "pokemon" matches "Pokémon". */
internal fun foldDiacritics(text: String): String {
    val decomposed = java.text.Normalizer.normalize(text, java.text.Normalizer.Form.NFD)
    return decomposed.replace(Regex("\\p{Mn}+"), "").lowercase()
}
