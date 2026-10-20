package io.github.cidy02.kudos.author

import io.github.cidy02.kudos.ui.components.rememberStoredChoice
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.Person
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
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
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
/** iOS's grouped section: a plain heading over one panel of rows. */
@Composable
private fun AuthorAboutSection(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column {
        Text(title, color = LocalKudosTokens.current.secondaryInk, fontSize = 15.sp, lineHeight = 21.sp,
            modifier = Modifier.padding(start = 4.dp, bottom = 8.dp).semantics { heading() })
        Column(Modifier.fillMaxWidth().subjectPanel(), content = content)
    }
}

@Composable
fun AuthorProfileScreen(
    username: String,
    initialPseud: String? = null,
    initialTab: AuthorTab = AuthorTab.Works,
    authorRepository: AO3AuthorRepository,
    onOpenWork: (AO3WorkSummary) -> Unit,
    onOpenAbout: (AO3AuthorRoute) -> Unit,
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
    readingQueueRepository: io.github.cidy02.kudos.library.ReadingQueueRepository? = null,
    /** Opens the new-work form. Offered on the reader's own Works and Dashboard, as iOS's "+". */
    onNewWork: (() -> Unit)? = null,
    onOpenAuthor: (AO3AuthorRoute) -> Unit = {}
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
    // The account's own totals, for the line under "Works" (iOS 1u). Asked once per opening.
    var stats by remember(route, sessionGeneration) { mutableStateOf<io.github.cidy02.kudos.network.ao3.author.AO3UserStats?>(null) }
    var statsAsked by remember(route, sessionGeneration) { mutableStateOf(false) }
    var headerError by remember(sessionGeneration) { mutableStateOf<AO3Error?>(null) }
    var headerStale by remember(sessionGeneration) { mutableStateOf(false) }
    var tabStale by remember(sessionGeneration) { mutableStateOf(false) }
    var headerLoading by remember { mutableStateOf(true) }
    
    var expandAll by remember(route.id, sessionGeneration) { mutableStateOf(false) }
    var expandsFandoms by remember(route.id, sessionGeneration) { mutableStateOf(false) }
    var tab by remember { mutableStateOf(initialTab) }
    var page by remember { mutableIntStateOf(1) }
    
    var works by remember(sessionGeneration) { mutableStateOf<AO3SearchPage?>(null) }
    var series by remember(sessionGeneration) { mutableStateOf<AO3AuthorSeriesPage?>(null) }
    var bookmarks by remember(sessionGeneration) { mutableStateOf<AO3AuthorBookmarksPage?>(null) }
    var about by remember(sessionGeneration) { mutableStateOf<AO3AuthorAbout?>(null) }
    
    var tabLoading by remember { mutableStateOf(false) }
    var tabError by remember { mutableStateOf<String?>(null) }
    
    var scopeState by remember { mutableStateOf(AO3AuthorWorksScope.Works) }
    // iOS `AO3AuthorFandomFilterSection`: one of the author's fandoms, from the list AO3 prints
    // beside the plain works list. Android read that list and never offered it.
    var selectedFandom by remember(route.id, sessionGeneration) {
        mutableStateOf<io.github.cidy02.kudos.network.ao3.author.AO3AuthorFandom?>(null) }
    // iOS `authorProfile.displayMode`: the ledger first, and the choice kept. It opened on
    // the detailed card and forgot.
    var displayMode by rememberStoredChoice("authorProfile.displayMode", AuthorDisplayMode.Ledger)
    
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
    // Subscribe and Unsubscribe on an author's page (iOS `toggleSubscription`). The button opened
    // the form's submit address in the web view, where it does nothing.
    var subscriptionBusy by remember { mutableStateOf(false) }
    var confirmingUnsubscribe by remember(route.id, sessionGeneration) {
        mutableStateOf<io.github.cidy02.kudos.network.ao3.author.AO3AuthorSubscriptionForm?>(null) }
    var profileMessage by remember(route.id, sessionGeneration) { mutableStateOf<String?>(null) }
    // Mute and Block (iOS `beginModeration`, `confirmPendingModeration`): AO3's own confirm page,
    // read on the tap and shown as a dialog. The buttons used to open that page in the web view.
    var moderationBusy by remember { mutableStateOf(false) }
    var pendingModeration by remember(route.id, sessionGeneration) {
        mutableStateOf<io.github.cidy02.kudos.network.ao3.author.AO3AuthorModerationForm?>(null) }

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
        val expectedFandom = selectedFandom.takeIf { expectedScope == AO3AuthorWorksScope.Works }
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
                (target != AuthorTab.Works || (scopeState == expectedScope && worksSort == expectedSort &&
                    selectedFandom.takeIf { expectedScope == AO3AuthorWorksScope.Works } == expectedFandom))
            try {
                when (target) {
                    AuthorTab.Works -> {
                        val r = if (expectedFandom != null)
                            authorRepository.loadFandomWorks(expectedFandom, pageNum, expectedSort, bypassCache)
                        else authorRepository.loadWorks(expectedRoute, pageNum, expectedScope, expectedSort, bypassCache)
                        currentCoroutineContext().ensureActive()
                        if (!current()) return@launch
                        when (r) {
                            is AO3Result.Success -> {
                                val rows = if (pageNum > 1) works?.works.orEmpty() + r.value.works else r.value.works
                                works = r.value.copy(works = rows.distinctBy { it.id })
                                tabStale = tabStale || r.isStale
                            }
                            is AO3Result.Failure -> tabError = r.error.displayMessage()
                        }
                    }
                    AuthorTab.Series -> {
                        val r = authorRepository.loadSeries(expectedRoute, pageNum, bypassCache)
                        currentCoroutineContext().ensureActive()
                        if (!current()) return@launch
                        when (r) {
                            is AO3Result.Success -> {
                                val rows = if (pageNum > 1) series?.series.orEmpty() + r.value.series else r.value.series
                                series = r.value.copy(series = rows.distinctBy { it.id })
                                tabStale = tabStale || r.isStale
                            }
                            is AO3Result.Failure -> tabError = r.error.displayMessage()
                        }
                    }
                    AuthorTab.Bookmarks -> {
                        val r = authorRepository.loadBookmarks(expectedRoute, pageNum, bypassCache)
                        currentCoroutineContext().ensureActive()
                        if (!current()) return@launch
                        when (r) {
                            is AO3Result.Success -> {
                                val rows = if (pageNum > 1) bookmarks?.bookmarks.orEmpty() + r.value.bookmarks else r.value.bookmarks
                                bookmarks = r.value.copy(bookmarks = rows.distinctBy { it.id })
                                tabStale = tabStale || r.isStale
                            }
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
        // The tab the page was opened on. This said Works, and it runs on the first
        // composition too, so the account's Series row opened the reader's works.
        tab = initialTab
        headerStale = false; tabStale = false
        header = null; works = null; series = null; bookmarks = null; about = null
        loadHeader()
    }

    fun submitSubscription(form: io.github.cidy02.kudos.network.ao3.author.AO3AuthorSubscriptionForm) {
        val writes = seriesWrites ?: return
        if (subscriptionBusy || headerLoading) return
        val expectedRoute = route
        val expectedSession = sessionGeneration
        subscriptionBusy = true
        scope.launch {
            val result = try {
                writes.submitAuthorSubscription(form, expectedSession)
            } catch (cancelled: kotlinx.coroutines.CancellationException) {
                // The session changed before anything was sent, or the screen went: nothing to say.
                currentCoroutineContext().ensureActive()
                null
            } finally {
                subscriptionBusy = false
            }
            if (result == null || route != expectedRoute || sessionGeneration != expectedSession) return@launch
            when (result) {
                is AO3Result.Success -> {
                    profileMessage = result.value.message
                    // Every kept page of this account shows the old button, the pseuds' too.
                    io.github.cidy02.kudos.network.ao3.AO3PageCache.shared.removeAuthorDashboards(expectedRoute.username,
                        io.github.cidy02.kudos.network.ao3.AO3PageCache.Scope(signedInUsername, expectedSession))
                    loadHeader(bypassCache = true)
                }
                is AO3Result.Failure -> profileMessage = result.error.displayMessage()
            }
        }
    }

    // One fence for the two steps of a mute or a block: the session and the page they began on.
    fun moderation(step: suspend (io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository, Int) -> Unit) {
        val writes = seriesWrites ?: return
        if (moderationBusy) return
        val expectedSession = sessionGeneration
        moderationBusy = true
        scope.launch {
            try {
                step(writes, expectedSession)
            } catch (cancelled: kotlinx.coroutines.CancellationException) {
                // The session changed before anything was sent, or the screen went: nothing to say.
                currentCoroutineContext().ensureActive()
            } finally {
                moderationBusy = false
            }
        }
    }

    fun beginModeration(action: io.github.cidy02.kudos.network.ao3.author.AO3AuthorWebAction) {
        val expectedRoute = route
        moderation { writes, session ->
            val result = writes.loadAuthorModerationForm(action, expectedRoute.username, session)
            if (route != expectedRoute || sessionGeneration != session) return@moderation
            when (result) {
                is AO3Result.Success -> pendingModeration = result.value
                is AO3Result.Failure -> profileMessage = result.error.displayMessage()
            }
        }
    }

    fun confirmModeration(form: io.github.cidy02.kudos.network.ao3.author.AO3AuthorModerationForm) {
        val expectedRoute = route
        moderation { writes, session ->
            val result = writes.submitAuthorModeration(form, session)
            if (route != expectedRoute || sessionGeneration != session) return@moderation
            when (result) {
                is AO3Result.Success -> {
                    profileMessage = result.value.message
                    // Every kept page of this account shows the old buttons, the pseuds' too.
                    io.github.cidy02.kudos.network.ao3.AO3PageCache.shared.removeAuthorDashboards(expectedRoute.username,
                        io.github.cidy02.kudos.network.ao3.AO3PageCache.Scope(signedInUsername, session))
                    loadHeader(bypassCache = true)
                }
                is AO3Result.Failure -> profileMessage = result.error.displayMessage()
            }
        }
    }

    // iOS `loadOwnStats`: silent when it fails (the line keeps what it had), and nothing is
    // shown from a reader or a page that has changed since it was asked for.
    suspend fun loadOwnStats(bypassCache: Boolean = false) {
        val expectedRoute = route
        val expectedSession = sessionGeneration
        val loaded = (authorRepository.loadOwnStats(expectedRoute, bypassCache) as? AO3Result.Success)?.value ?: return
        if (route == expectedRoute && sessionGeneration == expectedSession && !loaded.isEmpty) stats = loaded
    }
    // A confirmed write to the writer's own works: the header and the list are read past the
    // cache, and then the totals, which a deleted or edited work is no longer in as it was.
    fun reloadAfterWorksWrite() = loadHeader(bypassCache = true) {
        loadTab(tab, 1, bypassCache = true)
        scope.launch { tabTask?.join(); loadOwnStats(bypassCache = true) }
    }
    // After the header and the list, as iOS: the figures are no reason to hold either up.
    LaunchedEffect(route, sessionGeneration, header != null && works != null) {
        if (header != null && works != null && !statsAsked) { statsAsked = true; loadOwnStats() }
    }

    // iOS activation waits for a usable header before reading the selected index.
    // A missing/refused author must not trigger another read known to be unusable.
    LaunchedEffect(header, route.id, sessionGeneration) {
        val loaded = when (tab) {
            AuthorTab.Works -> works; AuthorTab.Series -> series
            AuthorTab.Bookmarks -> bookmarks; AuthorTab.About -> about
        } != null
        if (!refreshingProfile && header != null && !isDashboard && !loaded && !tabLoading && tabError == null) loadTab(tab, 1)
    }

    val shareContext = androidx.compose.ui.platform.LocalContext.current
    var showMenu by remember { mutableStateOf(false) }

    val workHue = remember(route.displayName) { HomeFacts.workHue(emptyList(), route.displayName) }
    val palette = if (ownSeriesList) tokens.scopePalette else remember(workHue, tokens.theme) { SubjectPalette.fromHue(workHue, tokens.theme) }

    LaunchedEffect(route.id, sessionGeneration, tab, scopeState) { selection.exit() }
    LaunchedEffect(deleteState.confirmed) {
        if (deleteState.confirmed > 0) { selection.exit(); heldDelete = null; reloadAfterWorksWrite() }
    }
    DisposableEffect(deletes) { onDispose { deletes?.close() } }
    val bulk = bulkModel
    if (bulk != null) {
        // After a saved bulk edit the list is read again from AO3, as after a row's edit and a
        // delete: the rows still showed the rating and tags from before the Save, and the kept
        // page would have gone on saying so for five minutes.
        WritingBulkEditScreen(bulk, bulkFocus, onBack = { bulkModel = null },
            onSaved = { bulkModel = null; reloadAfterWorksWrite() },
            autocomplete = autocompleteRepository, settings = settingsRepository, saveScope = scope)
        return
    }
    val row = rowAction
    if (row != null && workFormRepository != null && authRepository != null && seriesWrites != null) {
        WritingOwnWorkScreen(row.first, row.second, workFormRepository, authRepository, seriesWrites,
            autocompleteRepository, settingsRepository, onBack = { rowAction = null },
            onChanged = { reloadAfterWorksWrite() }, seriesRepository = seriesFormRepository, loadedWorks = works?.works.orEmpty())
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
            if (!selection.isSelecting && onNewWork != null && isOwnWorks(signedInUsername, route.username) &&
                (isDashboard || tab == AuthorTab.Works)) {
                io.github.cidy02.kudos.ui.subject.ToolbarAddButton(onClick = onNewWork, accessibilityName = "New Work",
                    palette = tokens.scopePalette)
            }
            if (!selection.isSelecting && ownWorks && !works?.works.isNullOrEmpty()) {
                ToolbarCircleButton(onClick = { selection.enter() }, accessibilityName = "Select Works", palette = tokens.scopePalette) {
                    Icon(Icons.Outlined.Checklist, null)
                }
            }
            if (!selection.isSelecting) Box {
                ToolbarCircleButton(
                    onClick = { showMenu = true },
                    accessibilityName = "More",
                    palette = palette
                ) {
                    Icon(Icons.Default.MoreVert, contentDescription = null)
                }
                DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false },
                    // The app's card colour and ink, as its other menus: Material's own fell through
                    // in OLED (A37 F12).
                    containerColor = tokens.cardFill) {
                    io.github.cidy02.kudos.ui.components.MatureWorkMenuItem { showMenu = false }
                    if (!isDashboard && !ownWorks && tab == AuthorTab.Works && !works?.works.isNullOrEmpty()) {
                        DropdownMenuItem(text = { Text("Select Works", color = tokens.primaryInk, lineHeight = 22.sp) },
                            onClick = { showMenu = false; selection.enter() })
                    }
                    if (isDashboard) {
                        DropdownMenuItem(text = { Text("About", color = tokens.primaryInk, lineHeight = 22.sp) },
                            onClick = { showMenu = false; onOpenAbout(route) })
                        DropdownMenuItem(
                            text = { Text("My Works", color = tokens.primaryInk, lineHeight = 22.sp) },
                            onClick = { showMenu = false; onOpenDashboardList?.invoke(AccountListType.MyWorks) }
                        )
                        DropdownMenuItem(
                            text = { Text("My Collections", color = tokens.primaryInk, lineHeight = 22.sp) },
                            onClick = { showMenu = false; onOpenAO3Collections?.invoke() }
                        )
                        DropdownMenuItem(
                            text = { Text("My Bookmarks", color = tokens.primaryInk, lineHeight = 22.sp) },
                            onClick = { showMenu = false; onOpenDashboardList?.invoke(AccountListType.Bookmarks) }
                        )
                        DropdownMenuItem(
                            text = { Text("My Subscriptions", color = tokens.primaryInk, lineHeight = 22.sp) },
                            onClick = { showMenu = false; onOpenDashboardList?.invoke(AccountListType.Subscriptions) }
                        )
                        DropdownMenuItem(
                            text = { Text("Marked for Later", color = tokens.primaryInk, lineHeight = 22.sp) },
                            onClick = { showMenu = false; onOpenDashboardList?.invoke(AccountListType.MarkedForLater) }
                        )
                        DropdownMenuItem(
                            text = { Text("My History", color = tokens.primaryInk, lineHeight = 22.sp) },
                            onClick = { showMenu = false; onOpenDashboardList?.invoke(AccountListType.History) }
                        )
                        HorizontalDivider()
                    }
                    DropdownMenuItem(
                        text = { Text("Ledger Mode", color = tokens.primaryInk, lineHeight = 22.sp) },
                        onClick = { displayMode = AuthorDisplayMode.Ledger; showMenu = false }
                    )
                    DropdownMenuItem(
                        text = { Text("Detailed Mode", color = tokens.primaryInk, lineHeight = 22.sp) },
                        onClick = { displayMode = AuthorDisplayMode.Detailed; showMenu = false }
                    )
                    if (isDashboard || tab != AuthorTab.About) DropdownMenuItem(
                        text = { Text(if (expandAll) "Collapse All" else "Expand All", color = tokens.primaryInk, lineHeight = 22.sp) },
                        onClick = { showMenu = false; expandAll = !expandAll }
                    )
                    HorizontalDivider()
                    DropdownMenuItem(
                        text = { Text("Open on AO3", color = tokens.primaryInk, lineHeight = 22.sp) },
                        onClick = { showMenu = false; onOpenWeb(AO3AuthorUrls.userDashboardUrl(route.username, route.pseud) ?: "") }
                    )
                    // iOS `ShareLink(item: route.dashboardURL)`: the pseud's page when one is chosen.
                    AO3AuthorUrls.userDashboardUrl(route.username, route.pseud)?.let { profileUrl ->
                        DropdownMenuItem(
                            text = { Text("Share Profile", color = tokens.primaryInk, lineHeight = 22.sp) },
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
        SearchFilterSheet(fandomContext = AO3SearchFilters.commaSeparatedValues(worksFilters.fandom),
            filters = worksFilters, onFiltersChange = { worksFilters = it },
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

    confirmingUnsubscribe?.let { form ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { confirmingUnsubscribe = null },
            title = { Text("Unsubscribe from ${route.username}?") },
            text = { Text("Unsubscribing here applies to the whole AO3 account, not only this pseud.") },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = { confirmingUnsubscribe = null; submitSubscription(form) }) {
                    Text("Unsubscribe", color = androidx.compose.material3.MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                androidx.compose.material3.TextButton(onClick = { confirmingUnsubscribe = null }) { Text("Cancel") }
            }
        )
    }
    pendingModeration?.let { form ->
        // AO3's own words: its heading, its notice, and what its two buttons say.
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { pendingModeration = null },
            title = { Text(form.title) },
            text = {
                androidx.compose.foundation.layout.Column(
                    Modifier.verticalScroll(androidx.compose.foundation.rememberScrollState())
                ) { Text(form.message) }
            },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = { pendingModeration = null; confirmModeration(form) }) {
                    Text(form.submitLabel, color = if (form.kind.isUndo) androidx.compose.ui.graphics.Color.Unspecified
                        else androidx.compose.material3.MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                androidx.compose.material3.TextButton(onClick = { pendingModeration = null }) { Text(form.cancelLabel) }
            }
        )
    }
    profileMessage?.let { message ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { profileMessage = null },
            title = { Text("AO3 Profile") },
            text = { Text(message) },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = { profileMessage = null }) { Text("OK") }
            }
        )
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
                loadOwnStats(bypassCache = true)
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
            item {
                // Below the bar like every other state of this page: it sat under the back button.
                Spacer(Modifier.height(WindowInsets.statusBars.asPaddingValues().calculateTopPadding() + 56.dp))
                LoadingStateCard("Loading author profile")
            }
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
                                subtitle = when {
                                    isDashboard -> null
                                    // The plain list only: under "In collections", or narrowed to
                                    // complete works, AO3's count is of a different list.
                                    tab == AuthorTab.Works && scopeState == AO3AuthorWorksScope.Works && route.pseud == null &&
                                        selectedFandom == null &&
                                        worksSort.completion == io.github.cidy02.kudos.network.ao3.author.AO3AuthorWorksCompletion.Any ->
                                        ownWorksLine(route.displayName, works?.summary?.total, stats)
                                    else -> route.displayName
                                },
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
                                // iOS `isOwnProfile`. It was always false, so your own page, reached from
                                // a byline, offered to subscribe to, mute and block yourself.
                                isOwnProfile = signedInUsername?.equals(route.username, ignoreCase = true) == true,
                                onSubscription = { form ->
                                    when {
                                        seriesWrites == null -> onOpenWeb(form.actionUrl)
                                        // Leaving is asked first; joining is done at once (iOS).
                                        form.isSubscribed -> confirmingUnsubscribe = form
                                        else -> submitSubscription(form)
                                    }
                                },
                                // And while the page reloads after one: the button still holds the
                                // old form, and a tap resent it (A50 F2).
                                subscriptionBusy = subscriptionBusy || headerLoading,
                                moderationBusy = moderationBusy,
                                onModeration = { action ->
                                    if (seriesWrites == null) onOpenWeb(action.url) else beginModeration(action)
                                }
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
                            (if (expandsFandoms) h.fandoms else h.fandoms.take(5)).forEach { fandom ->
                                val name = io.github.cidy02.kudos.browse.FandomDisplayName.bareTitle(fandom.name)
                                val count = fandom.workCount?.let { " (${it.compactCount()})" }.orEmpty()
                                SubjectChip(text = name + count, style = SubjectChipStyle.Pill(false),
                                    modifier = Modifier.heightIn(min = 44.dp).clickable(enabled = fandom.url.isNotBlank()) {
                                        onOpenWeb(fandom.url)
                                    })
                            }
                            if (h.fandoms.size > 5) SubjectChip(
                                text = if (expandsFandoms) "Collapse" else "Expand",
                                modifier = Modifier.heightIn(min = 44.dp).clickable { expandsFandoms = !expandsFandoms })
                        }
                    }
                }
                
                item {
                    SectionRuleHeader(title = "Recent works")
                    if (h.recentWorks == null) {
                        Text("Couldn't read recent works. Open the full list to try again.", color = tokens.secondaryInk)
                    } else if (h.recentWorks.isEmpty()) {
                        Text("No recent works visible on AO3.", color = tokens.secondaryInk)
                    } else {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            h.recentWorks.forEach { work ->
                                AO3AuthorWorkCard(
                                    work = work,
                                    displayMode = displayMode,
                                    expandAll = expandAll,
                                    // iOS: the account's own dashboard carries them too.
                                    showsPerformance = isOwnWorks(signedInUsername, route.username),
                                    onOpenWork = onOpenWork
                                )
                            }
                        }
                    }
                    // iOS 1y: each section's "See all" sits below its cards, and stays when
                    // there are none or they could not be read.
                    onOpenDashboardList?.let { open -> DashboardSeeAll("works") { open(AccountListType.MyWorks) } }
                }
                
                item {
                    SectionRuleHeader(title = "Recent series")
                    if (h.recentSeries == null) {
                        Text("Couldn't read recent series. Open the full list to try again.", color = tokens.secondaryInk)
                    } else if (h.recentSeries.isEmpty()) {
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
                    DashboardSeeAll("series") {
                        onOpenSeries("https://archiveofourown.org/users/${route.username}/series")
                    }
                }
                
                item {
                    SectionRuleHeader(title = "Recent bookmarks")
                    if (h.recentBookmarks == null) {
                        Text("Couldn't read recent bookmarks. Open the full list to try again.", color = tokens.secondaryInk)
                    } else if (h.recentBookmarks.isEmpty()) {
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
                    onOpenDashboardList?.let { open -> DashboardSeeAll("bookmarks") { open(AccountListType.Bookmarks) } }
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
                            // Only over the plain list: AO3 offers the facet there alone, and "In
                            // collections" and Gifts would show fandoms that do not describe them.
                            val fandoms = header?.fandoms.orEmpty()
                            if (scopeState == AO3AuthorWorksScope.Works && fandoms.isNotEmpty()) item {
                                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    SectionRuleHeader("Fandom")
                                    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                        item {
                                            SubjectChip(text = "All", style = SubjectChipStyle.Pill(selectedFandom == null),
                                                modifier = Modifier.clickable {
                                                    if (selectedFandom != null) { selection.exit(); selectedFandom = null; loadTab(tab, 1) }
                                                })
                                        }
                                        items(fandoms, key = { it.url }) { fandom ->
                                            val count = fandom.workCount?.let { " (${it.compactCount()})" }.orEmpty()
                                            SubjectChip(text = io.github.cidy02.kudos.browse.FandomDisplayName.bareTitle(fandom.name) + count,
                                                style = SubjectChipStyle.Pill(selectedFandom == fandom),
                                                modifier = Modifier.clickable {
                                                    if (selectedFandom != fandom) { selection.exit(); selectedFandom = fandom; loadTab(tab, 1) }
                                                })
                                        }
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
                                        AO3AuthorWorkCard(work, displayMode, expandAll, ownWorks,
                                            onOpenWork = { selection.toggle(work.id) },
                                            selecting = true, selected = selection.isSelected(work.id))
                                    } else if (ownWorks && workFormRepository != null && seriesWrites != null) {
                                        OwnWorkRow(work, onAction = { action ->
                                            if (action == "delete") { heldDelete = deletes; deletes?.ask(listOf(work), multiple = false) }
                                            else rowAction = work to action
                                        }) { AO3AuthorWorkCard(work, displayMode, expandAll, true, onOpenWork) }
                                    } else AO3AuthorWorkCard(work, displayMode, expandAll, false, onOpenWork)
                                }
                                item {
                                    AuthorLoadMoreRow(
                                        page = pageData.currentPage,
                                        total = pageData.totalPages,
                                        loading = tabLoading,
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
                                val tally = seriesTallyParts(pageData.series, pageData.totalPages > 1)
                                if (tally.isNotEmpty()) item {
                                    Text(tally.joinToString(" · "), color = tokens.secondaryInk,
                                        fontSize = 12.sp, lineHeight = 18.sp)
                                }
                                items(pageData.series, key = { it.id }) { s ->
                                    val canEdit = io.github.cidy02.kudos.network.ao3.author.isSeriesCreator(s.creatorUsernames, signedInUsername) &&
                                        seriesFormRepository != null && seriesWrites != null
                                    var menu by remember(s.id) { mutableStateOf(false) }
                                    val actions: (@Composable () -> Unit)? = if (!canEdit) null else {
                                        {
                                            Box {
                                                ToolbarCircleButton(onClick = { menu = true }, accessibilityName = "Actions for ${s.title}",
                                                    palette = palette) { Icon(Icons.Default.MoreVert, null) }
                                                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }, containerColor = tokens.cardFill) {
                                                    DropdownMenuItem(text = { Text("Edit", color = tokens.primaryInk, lineHeight = 20.sp) },
                                                        onClick = { menu = false; editingSeries = s to false })
                                                    DropdownMenuItem(text = { Text("Reorder", color = tokens.primaryInk, lineHeight = 20.sp) },
                                                        onClick = { menu = false; editingSeries = s to true })
                                                }
                                            }
                                        }
                                    }
                                    AO3SeriesRow(series = s, displayMode = displayMode, onOpenSeries = onOpenSeries,
                                        onOpenAuthor = onOpenAuthor,
                                        trailingContent = actions)
                                }
                                item {
                                    AuthorLoadMoreRow(
                                        page = pageData.currentPage,
                                        total = pageData.totalPages,
                                        loading = tabLoading,
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
                                    // iOS: the note, the tags, Rec and the day are in the work's
                                    // card, as on the reader's own Bookmarks. They sat loose
                                    // under it here.
                                    bm.work?.let { work ->
                                        AO3AuthorWorkCard(
                                            work = work,
                                            displayMode = displayMode,
                                            expandAll = expandAll,
                                            showsPerformance = false,
                                            onOpenWork = onOpenWork,
                                            bookmark = bm.asLedgerBookmark()
                                        )
                                    } ?: AO3BookmarkFootnote(bookmark = bm)
                                }
                                item {
                                    AuthorLoadMoreRow(
                                        page = pageData.currentPage,
                                        total = pageData.totalPages,
                                        loading = tabLoading,
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
                                // iOS's three sections, each a heading over a panel. They were loose
                                // lines under a second copy of the profile's title, which the header
                                // already shows, and the bio was one grey paragraph without its links.
                                item {
                                    AuthorAboutSection("Bio") {
                                        if (a.bioHtml.isBlank()) {
                                            Text("This user has not added a bio.", color = tokens.secondaryInk,
                                                fontSize = 15.sp, modifier = Modifier.padding(14.dp))
                                        } else {
                                            io.github.cidy02.kudos.ui.components.AO3RichText(
                                                a.bioHtml, onOpenAo3 = onOpenWeb, modifier = Modifier.padding(14.dp))
                                        }
                                    }
                                }
                                if (a.pseuds.isNotEmpty()) item {
                                    AuthorAboutSection("Pseuds") {
                                        a.pseuds.forEachIndexed { index, p ->
                                            if (index > 0) SubjectRowSeparator()
                                            val current = route.pseud.equals(p.route.pseud, true)
                                            SubjectFormRow(
                                                p.name,
                                                leadingIcon = Icons.Outlined.Person,
                                                onClick = { if (!current) route = p.route },
                                                trailing = if (current) { {
                                                    Icon(Icons.Filled.Check, "Selected", tint = LocalSubjectPalette.current.accent,
                                                        modifier = Modifier.size(18.dp))
                                                } } else null
                                            )
                                        }
                                    }
                                }
                                val facts = listOfNotNull(
                                    route.pseud?.let { "Selected Pseud" to it },
                                    a.joinedDate.takeIf { it.isNotBlank() }?.let { "Joined" to it },
                                    a.userId?.let { "User ID" to "%,d".format(it) }
                                )
                                if (facts.isNotEmpty()) item {
                                    AuthorAboutSection("Account") {
                                        facts.forEachIndexed { index, (label, value) ->
                                            if (index > 0) SubjectRowSeparator()
                                            SubjectFormRow(label, value = value)
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
    }
    if (!ownWorks && workImporter != null) {
        io.github.cidy02.kudos.ui.components.RemoteWorkSelectionActions(
            selection, works?.works.orEmpty(), workImporter, readingQueueRepository)
    }

    }

}

@Composable
internal fun AuthorLoadMoreRow(
    page: Int, total: Int, loading: Boolean, onNext: () -> Unit,
    loadMoreError: String? = null, onRetry: () -> Unit = onNext
) {
    if (loadMoreError != null) {
        val tokens = LocalKudosTokens.current
        Column(Modifier.subjectPanel()) {
            Text(loadMoreError, color = tokens.secondaryInk, fontSize = 14.sp,
                lineHeight = 20.sp, modifier = Modifier.padding(16.dp))
            TextButton(onClick = onRetry, enabled = !loading) { Text("Try Loading More") }
        }
    } else if (page < total || loading) {
        TextButton(onClick = onNext, enabled = !loading, modifier = Modifier.fillMaxWidth()) {
            Text(if (loading) "Loading…" else "Load More")
            Spacer(Modifier.weight(1f))
            Text("Page $page of $total", color = LocalKudosTokens.current.secondaryInk, fontSize = 13.sp)
        }
    }
}

/**
 * iOS 1u's line under the writer's own Works: "12 works · 248,400 words · 3,812 kudos". The
 * count is AO3's own heading for the list; without it the line is the name alone, and without
 * the totals it is the count and the name, as it was before they were read.
 */
internal fun ownWorksLine(name: String, count: Int?, stats: io.github.cidy02.kudos.network.ao3.author.AO3UserStats?): String {
    if (count == null) return name
    fun figure(value: Int) = java.text.NumberFormat.getIntegerInstance().format(value)
    val parts = listOfNotNull("${figure(count)} ${if (count == 1) "work" else "works"}",
        stats?.wordCount?.let { "${figure(it)} words" }, stats?.kudos?.let { "${figure(it)} kudos" })
    return if (parts.size > 1) parts.joinToString(" · ") else "${parts[0]} · $name"
}

/** iOS `AuthorDashboardSections.seeAll`: the way from a dashboard section to its whole list. */
@Composable
private fun DashboardSeeAll(what: String, onClick: () -> Unit) {
    TextButton(onClick = onClick) {
        Text("See all $what", color = LocalKudosTokens.current.scopePalette.accent, fontWeight = FontWeight.Medium)
    }
}

/** iOS AuthorProfileView.seriesTallyParts; sums apply only to the displayed series page. */
internal fun seriesTallyParts(
    series: List<io.github.cidy02.kudos.network.ao3.author.AO3AuthorSeriesSummary>, isPartial: Boolean
): List<String> {
    fun count(value: Long) = String.format(java.util.Locale.US, "%,d", value)
    val parts = buildList {
        val works = series.mapNotNull { it.workCount }
        if (works.isNotEmpty()) {
            val total = works.sumOf { it.toLong() }
            add("${count(total)} ${if (total == 1L) "work" else "works"}")
        }
        val words = series.mapNotNull { it.words }
        if (words.isNotEmpty()) add("${count(words.sumOf { it.toLong() })} words")
    }
    return if (isPartial && parts.isNotEmpty())
        listOf("${parts.joinToString(", ")} in the ${count(series.size.toLong())} loaded series") else parts
}
