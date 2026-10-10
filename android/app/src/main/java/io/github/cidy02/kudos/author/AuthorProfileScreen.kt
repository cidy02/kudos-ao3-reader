package io.github.cidy02.kudos.author

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.Checklist
import io.github.cidy02.kudos.ui.components.rememberRemoteWorkSelection
import io.github.cidy02.kudos.network.ao3.writing.AO3WorkFormRepository
import io.github.cidy02.kudos.writing.*
import androidx.compose.material.icons.outlined.FilterList
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.search.SearchFilterSheet
import io.github.cidy02.kudos.search.matchesSummary
import io.github.cidy02.kudos.search.refineMatchText
import io.github.cidy02.kudos.search.LocalTagSuggestions
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.account.AccountListType
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.author.*
import io.github.cidy02.kudos.network.ao3.displayMessage
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.subject.*
import io.github.cidy02.kudos.home.HomeFacts
import kotlinx.coroutines.launch

import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.ui.subject.ToolbarCircleButton

enum class AuthorTab(val label: String) {
    Works("Works"),
    Series("Series"),
    Bookmarks("Bookmarks"),
    About("About")
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun AuthorProfileScreen(
    username: String,
    initialPseud: String? = null,
    initialTab: AuthorTab = AuthorTab.Works,
    authorRepository: AO3AuthorRepository,
    onOpenWork: (AO3WorkSummary) -> Unit,
    onOpenSeries: (String) -> Unit = {},
    onOpenWeb: (String) -> Unit = {},
    isDashboard: Boolean = false,
    onOpenDashboardList: ((AccountListType) -> Unit)? = null,
    onOpenAO3Collections: (() -> Unit)? = null,
    seriesFormRepository: io.github.cidy02.kudos.network.ao3.writing.AO3SeriesFormRepository? = null,
    seriesWrites: io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository? = null,
    modifier: Modifier = Modifier,
    authRepository: AO3AuthRepository? = null,
    workFormRepository: AO3WorkFormRepository? = null,
    autocompleteRepository: io.github.cidy02.kudos.network.ao3.search.AO3TagAutocompleteRepository? = null,
    settingsRepository: io.github.cidy02.kudos.data.preferences.SettingsRepository? = null,
    workImporter: io.github.cidy02.kudos.works.WorkImporter? = null,
    readingQueueRepository: io.github.cidy02.kudos.library.ReadingQueueRepository? = null
) {
    val account by ((authRepository ?: seriesFormRepository?.auth)?.state?.collectAsState() ?: remember {
        mutableStateOf<io.github.cidy02.kudos.auth.AO3AuthState>(io.github.cidy02.kudos.auth.AO3AuthState.SignedOut) })
    val signedInUsername = (account as? io.github.cidy02.kudos.auth.AO3AuthState.SignedIn)?.username
    val ownSeriesList = isOwnWorks(signedInUsername, username)
    var editingSeries by remember(username) { mutableStateOf<Pair<AO3AuthorSeriesSummary, Boolean>?>(null) }
    var route by remember(username, initialPseud) {
        mutableStateOf(AO3AuthorRoute(username.trim(), initialPseud?.trim()?.takeIf { it.isNotBlank() }))
    }
    val sessionGeneration by (authRepository?.generation ?: authorRepository.sessionChanges).collectAsState()
    var header by remember(sessionGeneration) { mutableStateOf<AO3AuthorHeader?>(null) }
    var headerError by remember(sessionGeneration) { mutableStateOf<AO3Error?>(null) }
    var headerStale by remember(sessionGeneration) { mutableStateOf(false) }
    var tabStale by remember(sessionGeneration) { mutableStateOf(false) }
    var headerLoading by remember { mutableStateOf(true) }
    
    var tab by remember { mutableStateOf(initialTab) }
    var page by remember { mutableIntStateOf(1) }
    
    var works by remember(sessionGeneration) { mutableStateOf<AO3SearchPage?>(null) }
    var series by remember(sessionGeneration) { mutableStateOf<AO3AuthorSeriesPage?>(null) }
    var bookmarks by remember(sessionGeneration) { mutableStateOf<AO3AuthorBookmarksPage?>(null) }
    var about by remember(sessionGeneration) { mutableStateOf<AO3AuthorAbout?>(null) }
    
    var tabLoading by remember { mutableStateOf(false) }
    var tabError by remember { mutableStateOf<String?>(null) }
    
    var scopeState by remember { mutableStateOf(AO3AuthorWorksScope.Works) }
    var displayMode by remember { mutableStateOf(AuthorDisplayMode.Detailed) }
    
    var worksSort by remember(route.id, sessionGeneration) { mutableStateOf(AO3AuthorWorksSort()) }
    var worksFilters by remember(route.id, sessionGeneration) { mutableStateOf(AO3SearchFilters()) }
    var showingWorksFilters by remember(route.id, sessionGeneration) { mutableStateOf(false) }
    // Same generation fence as AuthorWorksScreen, shared by tab/page/scope/sort changes.
    var loadGeneration by remember { mutableIntStateOf(0) }
    var headerGeneration by remember { mutableIntStateOf(0) }
    var refreshingProfile by remember { mutableStateOf(false) }
    var tabTask by remember { mutableStateOf<Job?>(null) }
    var headerTask by remember { mutableStateOf<Job?>(null) }
    val scope = rememberCoroutineScope()
    val tokens = LocalKudosTokens.current

    val selection = rememberRemoteWorkSelection()
    val ownWorks = isOwnWorks(signedInUsername, route.username) && tab == AuthorTab.Works && !isDashboard &&
        scopeState != AO3AuthorWorksScope.Gifts
    var rowAction by remember(username) { mutableStateOf<Pair<AO3WorkSummary, String>?>(null) }
    var bulkModel by remember(username) { mutableStateOf<WritingBulkEditState?>(null) }
    var bulkFocus by remember(username) { mutableStateOf<String?>(null) }
    var heldDelete by remember(username) { mutableStateOf<OwnWorksDeleteState?>(null) }
    val currentDelete = remember(seriesWrites, username, sessionGeneration) { seriesWrites?.let { OwnWorksDeleteState(it, sessionGeneration) } }
    val deletes = heldDelete ?: currentDelete
    val deleteState by (deletes?.state ?: kotlinx.coroutines.flow.flowOf(OwnWorksDeleteUi())).collectAsState(initial = OwnWorksDeleteUi())
    var readingBusy by remember { mutableStateOf(false) }
    var readingStatus by remember { mutableStateOf<String?>(null) }

    fun loadHeader(bypassCache: Boolean = false, afterLoad: (() -> Unit)? = null) {
        val expectedRoute = route
        val expectedSession = sessionGeneration
        val generation = ++headerGeneration
        headerTask?.cancel()
        headerLoading = true
        headerError = null
        headerTask = scope.launch {
            try {
                val result = authorRepository.loadDashboard(expectedRoute, bypassCache)
                currentCoroutineContext().ensureActive()
                if (generation != headerGeneration || route != expectedRoute || sessionGeneration != expectedSession) return@launch
                when (result) {
                    is AO3Result.Success -> {
                        header = result.value; headerError = null; headerStale = result.isStale; tabStale = false
                        afterLoad?.invoke()
                    }
                    is AO3Result.Failure -> { header = null; headerError = result.error; headerStale = false }
                }
            } finally {
                if (generation == headerGeneration && route == expectedRoute && sessionGeneration == expectedSession) {
                    headerLoading = false
                }
            }
        }
    }

    fun loadTab(target: AuthorTab, pageNum: Int = 1, bypassCache: Boolean = false) {
        val expectedRoute = route
        val expectedScope = scopeState
        val expectedSort = worksSort
        val expectedSession = sessionGeneration
        val generation = ++loadGeneration
        tabTask?.cancel()
        tabLoading = true
        tabError = null
        page = pageNum
        if (target == AuthorTab.Works && pageNum == 1) works = null
        tabTask = scope.launch {
            fun current(): Boolean = generation == loadGeneration && route == expectedRoute &&
                sessionGeneration == expectedSession && tab == target && page == pageNum &&
                (target != AuthorTab.Works || (scopeState == expectedScope && worksSort == expectedSort))
            try {
                when (target) {
                    AuthorTab.Works -> {
                        val r = authorRepository.loadWorks(expectedRoute, pageNum, expectedScope, expectedSort, bypassCache)
                        currentCoroutineContext().ensureActive()
                        if (!current()) return@launch
                        when (r) {
                            is AO3Result.Success -> { works = r.value; tabStale = tabStale || r.isStale }
                            is AO3Result.Failure -> tabError = r.error.displayMessage()
                        }
                    }
                    AuthorTab.Series -> {
                        val r = authorRepository.loadSeries(expectedRoute, pageNum, bypassCache)
                        currentCoroutineContext().ensureActive()
                        if (!current()) return@launch
                        when (r) {
                            is AO3Result.Success -> { series = r.value; tabStale = tabStale || r.isStale }
                            is AO3Result.Failure -> tabError = r.error.displayMessage()
                        }
                    }
                    AuthorTab.Bookmarks -> {
                        val r = authorRepository.loadBookmarks(expectedRoute, pageNum, bypassCache)
                        currentCoroutineContext().ensureActive()
                        if (!current()) return@launch
                        when (r) {
                            is AO3Result.Success -> { bookmarks = r.value; tabStale = tabStale || r.isStale }
                            is AO3Result.Failure -> tabError = r.error.displayMessage()
                        }
                    }
                    AuthorTab.About -> {
                        val r = authorRepository.loadAbout(expectedRoute, bypassCache)
                        currentCoroutineContext().ensureActive()
                        if (!current()) return@launch
                        when (r) {
                            is AO3Result.Success -> { about = r.value; tabStale = tabStale || r.isStale }
                            is AO3Result.Failure -> tabError = r.error.displayMessage()
                        }
                    }
                }
            } finally { if (current()) tabLoading = false }
        }
    }

    LaunchedEffect(route.id, sessionGeneration) {
        scopeState = AO3AuthorWorksScope.Works
        tab = AuthorTab.Works
        headerStale = false; tabStale = false
        header = null; works = null; series = null; bookmarks = null; about = null
        loadHeader()
    }

    // iOS activation waits for a usable header before reading the selected index.
    // A missing/refused author must not trigger another read known to be unusable.
    LaunchedEffect(header, route.id, sessionGeneration) {
        if (!refreshingProfile && header != null && !isDashboard && works == null && !tabLoading && tabError == null && tab == AuthorTab.Works) {
            loadTab(AuthorTab.Works, 1)
        }
    }

    val shareContext = androidx.compose.ui.platform.LocalContext.current
    var showMenu by remember { mutableStateOf(false) }

    val workHue = remember(route.displayName) { HomeFacts.workHue(emptyList(), route.displayName) }
    val palette = if (ownSeriesList) tokens.scopePalette else remember(workHue, tokens.theme) { SubjectPalette.fromHue(workHue, tokens.theme) }

    LaunchedEffect(route.id, sessionGeneration, tab, scopeState) { selection.exit() }
    LaunchedEffect(deleteState.confirmed) {
        if (deleteState.confirmed > 0) { selection.exit(); heldDelete = null; loadHeader(bypassCache = true) { loadTab(tab, 1, bypassCache = true) } }
    }
    DisposableEffect(deletes) { onDispose { deletes?.close() } }
    val bulk = bulkModel
    if (bulk != null) {
        // After a saved bulk edit the list is read again from AO3, as after a row's edit and a
        // delete: the rows still showed the rating and tags from before the Save, and the kept
        // page would have gone on saying so for five minutes.
        WritingBulkEditScreen(bulk, bulkFocus, onBack = { bulkModel = null },
            onSaved = { bulkModel = null; loadHeader(bypassCache = true) { loadTab(tab, 1, bypassCache = true) } },
            autocomplete = autocompleteRepository, settings = settingsRepository)
        return
    }
    val row = rowAction
    if (row != null && workFormRepository != null && authRepository != null && seriesWrites != null) {
        WritingOwnWorkScreen(row.first, row.second, workFormRepository, authRepository, seriesWrites,
            autocompleteRepository, settingsRepository, onBack = { rowAction = null },
            onChanged = { loadHeader(bypassCache = true) { loadTab(tab, 1, bypassCache = true) } }, seriesRepository = seriesFormRepository)
        return
    }

    val edit = editingSeries
    if (edit != null && seriesFormRepository != null && seriesWrites != null) {
        val series = edit.first
        val subtitle = listOfNotNull(series.title, series.workCount?.let { "$it ${if (it == 1) "work" else "works"}" },
            series.words?.takeIf { it > 0 }?.let { "%,d words".format(it) }).joinToString(" · ")
        io.github.cidy02.kudos.writing.WritingSeriesScreen(series.id, series.title, seriesFormRepository, seriesWrites,
            onBack = { editingSeries = null }, onOpenAo3 = onOpenWeb, reorderOnly = edit.second, subtitle = subtitle,
            onChanged = { loadHeader(bypassCache = true) { loadTab(tab, 1, bypassCache = true) } })
        return
    }

    deleteState.pending?.let { pending ->
        AlertDialog(onDismissRequest = { deletes?.cancel(); heldDelete = null }, containerColor = tokens.cardFill,
            title = { Text(ownWorksDeleteTitle(pending), color = tokens.primaryInk, lineHeight = 28.sp) },
            text = { Text(ownWorksDeleteMessage(pending), color = tokens.secondaryInk, lineHeight = 22.sp) },
            confirmButton = { TextButton(onClick = { scope.launch { deletes?.confirm() } }) {
                Text("Delete on AO3", color = SubjectPalette.fromHue(0.0, tokens.theme).accent, lineHeight = 20.sp) } },
            dismissButton = { TextButton(onClick = { deletes?.cancel(); heldDelete = null }) { Text("Cancel", color = tokens.scopePalette.accent, lineHeight = 20.sp) } })
    }
    deleteState.error?.let { message ->
        AlertDialog(onDismissRequest = { deletes?.dismissError(); heldDelete = null }, containerColor = tokens.cardFill,
            title = { Text("Couldn’t delete", color = tokens.primaryInk, lineHeight = 28.sp) },
            text = { Text(message, color = tokens.secondaryInk, lineHeight = 22.sp) },
            confirmButton = { TextButton(onClick = { deletes?.dismissError(); heldDelete = null }) { Text("OK", color = tokens.scopePalette.accent, lineHeight = 20.sp) } })
    }
    ProvidePushedShellChrome(
        hasSubjectHeader = true,
        customTitle = if (selection.isSelecting) "${selection.selectedIn(works?.works.orEmpty()).size} selected" else null,
        trailingContent = {
            if (selection.isSelecting) {
                val loaded = works?.works.orEmpty()
                TextButton(onClick = { selection.toggleSelectAll(loaded.map { it.id }) }, enabled = loaded.isNotEmpty()) {
                    Text(if (loaded.isNotEmpty() && loaded.all { selection.isSelected(it.id) }) "Deselect All" else "Select All",
                        color = tokens.scopePalette.accent, lineHeight = 20.sp)
                }
                IconButton(onClick = selection::exit) { Icon(Icons.Default.Check, "Done", tint = tokens.scopePalette.accent) }
            } else if (!isDashboard && tab == AuthorTab.Works) {
                val activeCount = worksSort.activeCount + worksFilters.activeCountForRefine
                ToolbarCircleButton(onClick = { showingWorksFilters = true }, accessibilityName = "Sort and filter",
                    palette = tokens.scopePalette, isAccented = activeCount > 0,
                    badge = activeCount.takeIf { it > 0 }?.toString()) {
                    Icon(Icons.Outlined.FilterList, null)
                }
            }
            if (!selection.isSelecting && ownWorks && !works?.works.isNullOrEmpty()) {
                ToolbarCircleButton(onClick = { selection.enter() }, accessibilityName = "Select Works", palette = tokens.scopePalette) {
                    Icon(Icons.Outlined.Checklist, null)
                }
            }
            if (!selection.isSelecting) Box {
                ToolbarCircleButton(
                    onClick = { showMenu = true },
                    accessibilityName = "Menu",
                    palette = palette
                ) {
                    Icon(Icons.Default.MoreVert, contentDescription = null)
                }
                DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                    if (!isDashboard && !ownWorks && tab == AuthorTab.Works && !works?.works.isNullOrEmpty()) {
                        DropdownMenuItem(text = { Text("Select Works", color = tokens.primaryInk, lineHeight = 22.sp) },
                            onClick = { showMenu = false; selection.enter() })
                    }
                    if (isDashboard) {
                        DropdownMenuItem(
                            text = { Text("My Works") },
                            onClick = { showMenu = false; onOpenDashboardList?.invoke(AccountListType.MyWorks) }
                        )
                        DropdownMenuItem(
                            text = { Text("My Collections") },
                            onClick = { showMenu = false; onOpenAO3Collections?.invoke() }
                        )
                        DropdownMenuItem(
                            text = { Text("My Bookmarks") },
                            onClick = { showMenu = false; onOpenDashboardList?.invoke(AccountListType.Bookmarks) }
                        )
                        DropdownMenuItem(
                            text = { Text("My Subscriptions") },
                            onClick = { showMenu = false; onOpenDashboardList?.invoke(AccountListType.Subscriptions) }
                        )
                        DropdownMenuItem(
                            text = { Text("Marked for Later") },
                            onClick = { showMenu = false; onOpenDashboardList?.invoke(AccountListType.MarkedForLater) }
                        )
                        DropdownMenuItem(
                            text = { Text("My History") },
                            onClick = { showMenu = false; onOpenDashboardList?.invoke(AccountListType.History) }
                        )
                        HorizontalDivider()
                    }
                    DropdownMenuItem(
                        text = { Text("Ledger Mode") },
                        onClick = { displayMode = AuthorDisplayMode.Ledger; showMenu = false }
                    )
                    DropdownMenuItem(
                        text = { Text("Detailed Mode") },
                        onClick = { displayMode = AuthorDisplayMode.Detailed; showMenu = false }
                    )
                    HorizontalDivider()
                    DropdownMenuItem(
                        text = { Text("Open on AO3") },
                        onClick = { showMenu = false; onOpenWeb(AO3AuthorUrls.userProfileUrl(route.username) ?: "") }
                    )
                    // iOS `ShareLink(item: route.dashboardURL)`: the pseud's page when one is chosen.
                    AO3AuthorUrls.userDashboardUrl(route.username, route.pseud)?.let { profileUrl ->
                        DropdownMenuItem(
                            text = { Text("Share Profile") },
                            onClick = {
                                showMenu = false
                                val send = android.content.Intent(android.content.Intent.ACTION_SEND)
                                    .setType("text/plain")
                                    .putExtra(android.content.Intent.EXTRA_TEXT, profileUrl)
                                shareContext.startActivity(android.content.Intent.createChooser(send, null))
                            }
                        )
                    }
                }
            }
        }
    )

    if (showingWorksFilters && tab == AuthorTab.Works && !isDashboard) {
        val source = works?.works.orEmpty()
        val visible = source.count { worksFilters.matchesSummary(it) }
        SearchFilterSheet(filters = worksFilters, onFiltersChange = { worksFilters = it },
            onApply = { showingWorksFilters = false }, onDismiss = { showingWorksFilters = false },
            onClear = { worksFilters = AO3SearchFilters() }, refine = true,
            canReset = worksFilters.activeCountForRefine > 0,
            refineMatchText = refineMatchText(source.size, visible, 0),
            localTagSuggestions = LocalTagSuggestions(
                fandoms = source.flatMap { it.fandoms }.distinct(),
                characters = source.flatMap { it.characters }.distinct(),
                relationships = source.flatMap { it.relationships }.distinct(),
                freeforms = source.flatMap { it.freeforms }.distinct()),
            worksSort = worksSort, onApplyWorksSort = { next ->
                if (next != worksSort) { worksSort = next; loadTab(AuthorTab.Works, 1) }
            })
    }

    Column(modifier.fillMaxSize()) {
    io.github.cidy02.kudos.ui.components.KudosRefreshBox(onRefresh = {
        refreshingProfile = true
        try {
            loadHeader(bypassCache = true)
            headerTask?.join()
            if (headerError == null && header != null && !isDashboard) {
                loadTab(tab, 1, bypassCache = true)
                tabTask?.join()
            }
        } finally {
            if (headerTask?.isActive == true) headerTask?.cancel()
            if (tabTask?.isActive == true) tabTask?.cancel()
            refreshingProfile = false
        }
    }, modifier = Modifier.weight(1f)) {
    LazyColumn(
        modifier = Modifier
            .testTag("Author profile")
            .fillMaxSize()
            .subjectScreenWash(palette)
            .padding(horizontal = 16.dp),
        contentPadding = PaddingValues(top = 24.dp, bottom = 48.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        if (headerLoading && header == null) {
            item { LoadingStateCard("Loading author profile") }
        } else if (headerError != null && header == null) {
            if (headerError == AO3Error.NotFound) {
                item {
                    Spacer(Modifier.height(WindowInsets.statusBars.asPaddingValues().calculateTopPadding() + 56.dp))
                    EmptyStateCard(
                        title = "Author unavailable",
                        message = "AO3 could not find this user or pseud. It may have been renamed or deleted.",
                        primaryActionLabel = "Open on AO3",
                        onPrimaryAction = { onOpenWeb(route.dashboardUrl) }
                    )
                }
            } else {
                item {
                    Spacer(Modifier.height(WindowInsets.statusBars.asPaddingValues().calculateTopPadding() + 56.dp))
                    SubjectHeaderBlock(
                        kicker = if (isDashboard) "AO3 Account" else "AO3 Author",
                        title = route.displayName,
                        subtitle = route.pseud?.let { "Pseud of ${route.username}" },
                        palette = palette,
                        gutter = 0.dp
                    )
                }
                item {
                    ErrorStateCard(
                        title = "Couldn't load author",
                        message = headerError!!.displayMessage(),
                        primaryActionLabel = "Try Again",
                        onPrimaryAction = { loadHeader(bypassCache = true) }
                    )
                }
            }
        } else {
            val h = header
            if (h != null) {
                item {
                    Column(modifier = Modifier.padding(top = WindowInsets.statusBars.asPaddingValues().calculateTopPadding() + 56.dp)) {
                        if (isDashboard || ownSeriesList) {
                            SubjectHeaderBlock(
                                kicker = "AO3 Account",
                                title = if (isDashboard) route.displayName else tab.label,
                                subtitle = if (isDashboard) null else route.displayName,
                                palette = palette
                            )
                            if (isDashboard && h.pseuds.size > 1) {
                                Spacer(Modifier.size(8.dp))
                                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    item {
                                        SubjectChip(text = "All Pseuds", style = SubjectChipStyle.Pill(route.pseud == null), modifier = Modifier.clickable { route = AO3AuthorRoute(route.username, null) })
                                    }
                                    items(h.pseuds) { pseud ->
                                        SubjectChip(text = pseud.name, style = SubjectChipStyle.Pill(route.pseud.equals(pseud.route.pseud, true)), modifier = Modifier.clickable { route = pseud.route })
                                    }
                                }
                            }
                        } else {
                            AO3AuthorHero(
                                header = h,
                                route = route,
                                profileTitle = about?.profileTitle ?: "",
                                isOwnProfile = false, // Since this requires more logic, assuming false for now unless we know it's our own
                                onSubscription = onOpenWeb,
                                onModeration = { onOpenWeb(it.url) }
                            )
                        }
                    }
                }

                if (!isDashboard && h.pseuds.size > 1) {
                    item {
                        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            item {
                                SubjectChip(
                                    text = "All Pseuds",
                                    style = SubjectChipStyle.Pill(route.pseud == null),
                                    modifier = Modifier.clickable { route = AO3AuthorRoute(route.username, null) }
                                )
                            }
                            items(h.pseuds) { pseud ->
                                SubjectChip(
                                    text = pseud.name,
                                    style = SubjectChipStyle.Pill(route.pseud.equals(pseud.route.pseud, true)),
                                    modifier = Modifier.clickable { route = pseud.route }
                                )
                            }
                        }
                    }
                }

                if (!isDashboard) {
                    item {
                        SubjectSegmentedControl(
                            items = AuthorTab.entries,
                            selectedItem = tab,
                            onItemSelected = {
                                if (tab != it) { tab = it; loadTab(it, 1) }
                            },
                            labelProvider = { it.label }
                        )
                    }
                }
            }
            
            if (h != null && (headerStale || tabStale)) item {
                io.github.cidy02.kudos.ui.components.CachedAO3DataRow()
            }

            if (isDashboard && h != null) {
                // Dashboard view
                item {
                    SectionRuleHeader(title = "Fandoms")
                    if (h.fandoms.isEmpty()) {
                        Text("No fandoms listed on AO3.", color = tokens.secondaryInk)
                    } else {
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            h.fandoms.forEach { fandom ->
                                SubjectChip(text = fandom.name)
                            }
                        }
                    }
                }
                
                item {
                    SectionRuleHeader(title = "Recent works")
                    if (h.recentWorks.isNullOrEmpty()) {
                        Text("No recent works visible on AO3.", color = tokens.secondaryInk)
                    } else {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            h.recentWorks.forEach { work ->
                                AO3AuthorWorkCard(
                                    work = work,
                                    displayMode = displayMode,
                                    expandAll = false,
                                    showsPerformance = false,
                                    onOpenWork = onOpenWork
                                )
                            }
                        }
                    }
                }
                
                item {
                    SectionRuleHeader(title = "Recent series")
                    if (h.recentSeries.isNullOrEmpty()) {
                        Text("No recent series visible on AO3.", color = tokens.secondaryInk)
                    } else {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            h.recentSeries.forEach { s ->
                                AO3DashboardCompactCard(
                                    fandoms = s.fandoms,
                                    title = s.title,
                                    meta = "${s.workCount ?: 0} works",
                                    onClick = { onOpenSeries(s.url) }
                                )
                            }
                        }
                    }
                }
                
                item {
                    SectionRuleHeader(title = "Recent bookmarks")
                    if (h.recentBookmarks.isNullOrEmpty()) {
                        Text("No recent bookmarks visible on AO3.", color = tokens.secondaryInk)
                    } else {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            h.recentBookmarks.forEach { b ->
                                AO3DashboardCompactCard(
                                    fandoms = b.work?.fandoms ?: emptyList(),
                                    title = b.work?.title ?: "Bookmark",
                                    meta = "Bookmark",
                                    onClick = { b.work?.let(onOpenWork) }
                                )
                            }
                        }
                    }
                }
            } else if (!isDashboard) {
                if (tabLoading && page == 1) {
                    item { LoadingStateCard("Loading…") }
                } else if (tabError != null && page == 1) {
                    item {
                        ErrorStateCard(
                            title = "Couldn't load ${tab.label.lowercase()}",
                            message = tabError!!,
                            primaryActionLabel = "Retry",
                            onPrimaryAction = { loadTab(tab, page) }
                        )
                    }
                } else {
                    when (tab) {
                        AuthorTab.Works -> {
                            item {
                                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    items(AO3AuthorWorksScope.entries.filter { it.acceptsWorkSearch || it == AO3AuthorWorksScope.Gifts }) { scopeVal ->
                                        SubjectChip(
                                            text = scopeVal.label,
                                            style = SubjectChipStyle.Pill(scopeState == scopeVal),
                                            modifier = Modifier.clickable {
                                                if (scopeState != scopeVal) { scopeState = scopeVal; loadTab(tab, 1) }
                                            }
                                        )
                                    }
                                }
                            }
                            
                            val pageData = works
                            val visibleWorks = pageData?.works.orEmpty().filter { worksFilters.matchesSummary(it) }
                            if (selection.isSelecting) item {
                                SectionRuleHeader(if (ownWorks) "Your works" else "Works", countText = "${selection.selectedIn(pageData?.works.orEmpty()).size} / ${pageData?.works.orEmpty().size}")
                            }
                            if (pageData == null || visibleWorks.isEmpty()) {
                                item { EmptyStateCard("No works", "No works by this author are visible to you on AO3.") }
                            } else {
                                items(visibleWorks, key = { it.id }) { work ->
                                    if (selection.isSelecting) {
                                        Row(verticalAlignment = Alignment.CenterVertically) {
                                            IconButton(onClick = { selection.toggle(work.id) }) {
                                                Icon(if (selection.isSelected(work.id)) Icons.Default.Check else Icons.Outlined.Checklist,
                                                    if (selection.isSelected(work.id)) "Deselect ${work.title}" else "Select ${work.title}",
                                                    tint = tokens.scopePalette.accent)
                                            }
                                            AO3AuthorWorkCard(work, displayMode, false, ownWorks,
                                                onOpenWork = { selection.toggle(work.id) }, modifier = Modifier.weight(1f))
                                        }
                                    } else if (ownWorks && workFormRepository != null && seriesWrites != null) {
                                        OwnWorkRow(work, onAction = { action ->
                                            if (action == "delete") { heldDelete = deletes; deletes?.ask(listOf(work), multiple = false) }
                                            else rowAction = work to action
                                        }) { AO3AuthorWorkCard(work, displayMode, false, true, onOpenWork) }
                                    } else AO3AuthorWorkCard(work, displayMode, false, false, onOpenWork)
                                }
                                item {
                                    PagerRow(
                                        page = pageData.currentPage,
                                        total = pageData.totalPages,
                                        onPrev = { loadTab(AuthorTab.Works, pageData.currentPage - 1) },
                                        onNext = { loadTab(AuthorTab.Works, pageData.currentPage + 1) },
                                        loadMoreError = tabError?.takeIf { page > 1 },
                                        onRetry = { loadTab(tab, page) }
                                    )
                                }
                            }
                        }
                        AuthorTab.Series -> {
                            val pageData = series
                            if (pageData == null || pageData.series.isEmpty()) {
                                if (pageData != null && ownSeriesList) item {
                                    EmptyStateCard("You have not made a series.",
                                        "A series groups your works in reading order. Create one on AO3, then refresh this page to see it here.")
                                    SubjectFormRow("New series on AO3", showsDisclosure = true,
                                        onClick = { onOpenWeb("https://archiveofourown.org/series/new") })
                                    Text("This opens AO3 in Browse, where you can create the series.", color = tokens.secondaryInk,
                                        fontSize = 11.5.sp, lineHeight = 17.sp)
                                } else item { EmptyStateCard("No series", "No series by this author are visible to you on AO3.") }
                            } else {
                                items(pageData.series, key = { it.id }) { s ->
                                    val canEdit = signedInUsername != null && s.creatorUsernames.any { it.equals(signedInUsername, true) } &&
                                        seriesFormRepository != null && seriesWrites != null
                                    var menu by remember(s.id) { mutableStateOf(false) }
                                    val actions: (@Composable () -> Unit)? = if (!canEdit) null else {
                                        {
                                            Box {
                                                ToolbarCircleButton(onClick = { menu = true }, accessibilityName = "Actions for ${s.title}",
                                                    palette = palette) { Icon(Icons.Default.MoreVert, null) }
                                                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                                                    DropdownMenuItem(text = { Text("Edit", color = tokens.primaryInk, lineHeight = 20.sp) },
                                                        onClick = { menu = false; editingSeries = s to false })
                                                    DropdownMenuItem(text = { Text("Reorder", color = tokens.primaryInk, lineHeight = 20.sp) },
                                                        onClick = { menu = false; editingSeries = s to true })
                                                }
                                            }
                                        }
                                    }
                                    AO3SeriesRow(series = s, displayMode = displayMode, onOpenSeries = onOpenSeries,
                                        trailingContent = actions)
                                }
                                item {
                                    PagerRow(
                                        page = pageData.currentPage,
                                        total = pageData.totalPages,
                                        onPrev = { loadTab(AuthorTab.Series, pageData.currentPage - 1) },
                                        onNext = { loadTab(AuthorTab.Series, pageData.currentPage + 1) },
                                        loadMoreError = tabError?.takeIf { page > 1 },
                                        onRetry = { loadTab(tab, page) }
                                    )
                                }
                            }
                        }
                        AuthorTab.Bookmarks -> {
                            val pageData = bookmarks
                            if (pageData == null || pageData.bookmarks.isEmpty()) {
                                item { EmptyStateCard("No visible bookmarks", "No bookmarks by this author are visible to you on AO3.") }
                            } else {
                                items(pageData.bookmarks, key = { it.id }) { bm ->
                                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                        bm.work?.let { work ->
                                            AO3AuthorWorkCard(
                                                work = work,
                                                displayMode = displayMode,
                                                expandAll = false,
                                                showsPerformance = false,
                                                onOpenWork = onOpenWork
                                            )
                                        }
                                        AO3BookmarkFootnote(bookmark = bm)
                                    }
                                }
                                item {
                                    PagerRow(
                                        page = pageData.currentPage,
                                        total = pageData.totalPages,
                                        onPrev = { loadTab(AuthorTab.Bookmarks, pageData.currentPage - 1) },
                                        onNext = { loadTab(AuthorTab.Bookmarks, pageData.currentPage + 1) },
                                        loadMoreError = tabError?.takeIf { page > 1 },
                                        onRetry = { loadTab(tab, page) }
                                    )
                                }
                            }
                        }
                        AuthorTab.About -> {
                            val a = about
                            if (a == null) {
                                item { EmptyStateCard("No about", "Profile details unavailable.") }
                            } else {
                                item {
                                    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                                        if (a.profileTitle.isNotBlank()) {
                                            Text(a.profileTitle, color = tokens.primaryInk, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                                        }
                                        Text(
                                            a.bioText.ifBlank { "This user has not added a bio." },
                                            color = tokens.secondaryInk,
                                            fontSize = 15.sp
                                        )
                                        
                                        if (a.pseuds.isNotEmpty()) {
                                            SectionRuleHeader(title = "Pseuds")
                                            a.pseuds.forEach { p ->
                                                Text(
                                                    text = p.name,
                                                    color = tokens.accent,
                                                    fontSize = 15.sp,
                                                    modifier = Modifier
                                                        .fillMaxWidth()
                                                        .clickable {
                                                            if (route != p.route) route = p.route
                                                        }
                                                        .padding(vertical = 4.dp)
                                                )
                                            }
                                        }
                                        
                                        SectionRuleHeader(title = "Account")
                                        if (a.joinedDate.isNotBlank()) {
                                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                                Text("Joined", color = tokens.secondaryInk, fontSize = 15.sp)
                                                Text(a.joinedDate, color = tokens.primaryInk, fontSize = 15.sp)
                                            }
                                        }
                                        a.userId?.let {
                                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                                Text("User ID", color = tokens.secondaryInk, fontSize = 15.sp)
                                                Text(it.toString(), color = tokens.primaryInk, fontSize = 15.sp)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    }
    if (selection.isSelecting) {
        val picked = selection.selectedIn(works?.works.orEmpty())
        if (ownWorks && seriesWrites != null) OwnWorksBulkBar(picked.size, deleteState.busy,
            onEdit = { focus ->
                bulkFocus = focus
                bulkModel = WritingBulkEditState(picked.map { it.id }, seriesWrites, sessionGeneration)
            }, onDelete = { heldDelete = deletes; deletes?.ask(picked) }, modifier = Modifier.padding(16.dp).navigationBarsPadding())
        else if (workImporter != null && readingQueueRepository != null) {
            io.github.cidy02.kudos.ui.components.RemoteWorkSelectionBar(selection, readingBusy,
                onSaveToLibrary = { scope.launch { readingBusy = true
                    try { readingStatus = io.github.cidy02.kudos.ui.components.RemoteWorkBulkActions.saveToLibrary(picked, workImporter); selection.exit() }
                    finally { readingBusy = false }
                } }, onSaveForLater = { scope.launch { readingBusy = true
                    try { readingStatus = io.github.cidy02.kudos.ui.components.RemoteWorkBulkActions.saveForLater(picked, workImporter, readingQueueRepository); selection.exit() }
                    finally { readingBusy = false }
                } })
        }
    }
    readingStatus?.let { Text(it, color = tokens.secondaryInk, lineHeight = 20.sp, modifier = Modifier.padding(16.dp)) }
    }

}

@Composable
private fun PagerRow(
    page: Int, total: Int, onPrev: () -> Unit, onNext: () -> Unit,
    loadMoreError: String? = null, onRetry: () -> Unit = {}
) {
    if (loadMoreError != null) {
        val tokens = LocalKudosTokens.current
        Column(Modifier.subjectPanel()) {
            Text(loadMoreError, color = tokens.secondaryInk, fontSize = 14.sp,
                lineHeight = 20.sp, modifier = Modifier.padding(16.dp))
            SubjectFormRow("Try Loading More", onClick = onRetry)
        }
        return
    }
    if (total <= 1) return
    if (io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale()) {
        io.github.cidy02.kudos.ui.components.LargeTextPager(page, total, { if (it < page) onPrev() else onNext() }, Modifier.padding(vertical = 8.dp))
        return
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        OutlinedButton(onClick = onPrev, enabled = page > 1) { Text("Previous") }
        Text("Page $page of $total", color = LocalKudosTokens.current.secondaryInk, fontSize = 13.sp)
        OutlinedButton(onClick = onNext, enabled = page < total) { Text("Next") }
    }
}
