package io.github.cidy02.kudos.author

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
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
    authRepository: AO3AuthRepository? = null
) {
    val account by (seriesFormRepository?.auth?.state?.collectAsState() ?: remember {
        mutableStateOf<io.github.cidy02.kudos.auth.AO3AuthState>(io.github.cidy02.kudos.auth.AO3AuthState.SignedOut) })
    val signedInUsername = (account as? io.github.cidy02.kudos.auth.AO3AuthState.SignedIn)?.username
    val ownSeriesList = signedInUsername?.equals(username, true) == true
    var editingSeries by remember(username) { mutableStateOf<Pair<AO3AuthorSeriesSummary, Boolean>?>(null) }
    var route by remember(username, initialPseud) {
        mutableStateOf(AO3AuthorRoute(username.trim(), initialPseud?.trim()?.takeIf { it.isNotBlank() }))
    }
    var header by remember { mutableStateOf<AO3AuthorHeader?>(null) }
    var headerError by remember { mutableStateOf<AO3Error?>(null) }
    var headerLoading by remember { mutableStateOf(true) }
    
    var tab by remember { mutableStateOf(initialTab) }
    var page by remember { mutableIntStateOf(1) }
    
    var works by remember { mutableStateOf<AO3SearchPage?>(null) }
    var series by remember { mutableStateOf<AO3AuthorSeriesPage?>(null) }
    var bookmarks by remember { mutableStateOf<AO3AuthorBookmarksPage?>(null) }
    var about by remember { mutableStateOf<AO3AuthorAbout?>(null) }
    
    var tabLoading by remember { mutableStateOf(false) }
    var tabError by remember { mutableStateOf<String?>(null) }
    
    var scopeState by remember { mutableStateOf(AO3AuthorWorksScope.Works) }
    var displayMode by remember { mutableStateOf(AuthorDisplayMode.Detailed) }
    
    val sessionGeneration by (authRepository?.generation ?: kotlinx.coroutines.flow.flowOf(0)).collectAsState(initial = 0)
    var worksSort by remember(route.id, sessionGeneration) { mutableStateOf(AO3AuthorWorksSort()) }
    var worksFilters by remember(route.id, sessionGeneration) { mutableStateOf(AO3SearchFilters()) }
    var showingWorksFilters by remember(route.id, sessionGeneration) { mutableStateOf(false) }
    // Same generation fence as AuthorWorksScreen, shared by tab/page/scope/sort changes.
    var loadGeneration by remember { mutableIntStateOf(0) }
    var headerGeneration by remember { mutableIntStateOf(0) }
    var tabTask by remember { mutableStateOf<Job?>(null) }
    var headerTask by remember { mutableStateOf<Job?>(null) }
    val scope = rememberCoroutineScope()
    val tokens = LocalKudosTokens.current

    fun loadHeader() {
        val expectedRoute = route
        val expectedSession = sessionGeneration
        val generation = ++headerGeneration
        headerTask?.cancel()
        headerLoading = true
        headerError = null
        headerTask = scope.launch {
            val result = authorRepository.loadDashboard(expectedRoute)
            currentCoroutineContext().ensureActive()
            if (generation != headerGeneration || route != expectedRoute || sessionGeneration != expectedSession) return@launch
            when (result) {
                is AO3Result.Success -> { header = result.value; headerError = null }
                is AO3Result.Failure -> headerError = result.error
            }
            headerLoading = false
        }
    }

    fun loadTab(target: AuthorTab, pageNum: Int = 1) {
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
            when (target) {
                AuthorTab.Works -> {
                    val r = authorRepository.loadWorks(expectedRoute, pageNum, expectedScope, expectedSort)
                    currentCoroutineContext().ensureActive()
                    if (!current()) return@launch
                    when (r) {
                        is AO3Result.Success -> works = r.value
                        is AO3Result.Failure -> tabError = r.error.displayMessage()
                    }
                }
                AuthorTab.Series -> {
                    val r = authorRepository.loadSeries(expectedRoute, pageNum)
                    currentCoroutineContext().ensureActive()
                    if (!current()) return@launch
                    when (r) {
                        is AO3Result.Success -> series = r.value
                        is AO3Result.Failure -> tabError = r.error.displayMessage()
                    }
                }
                AuthorTab.Bookmarks -> {
                    val r = authorRepository.loadBookmarks(expectedRoute, pageNum)
                    currentCoroutineContext().ensureActive()
                    if (!current()) return@launch
                    when (r) {
                        is AO3Result.Success -> bookmarks = r.value
                        is AO3Result.Failure -> tabError = r.error.displayMessage()
                    }
                }
                AuthorTab.About -> {
                    val r = authorRepository.loadAbout(expectedRoute)
                    currentCoroutineContext().ensureActive()
                    if (!current()) return@launch
                    when (r) {
                        is AO3Result.Success -> about = r.value
                        is AO3Result.Failure -> tabError = r.error.displayMessage()
                    }
                }
            }
            tabLoading = false
        }
    }

    LaunchedEffect(route.id, sessionGeneration) {
        scopeState = AO3AuthorWorksScope.Works
        tab = AuthorTab.Works
        header = null; works = null; series = null; bookmarks = null; about = null
        loadHeader()
    }

    // iOS activation waits for a usable header before reading the selected index.
    // A missing/refused author must not trigger another read known to be unusable.
    LaunchedEffect(header, route.id, sessionGeneration) {
        if (header != null && !isDashboard && works == null && tab == AuthorTab.Works) {
            loadTab(AuthorTab.Works, 1)
        }
    }

    val shareContext = androidx.compose.ui.platform.LocalContext.current
    var showMenu by remember { mutableStateOf(false) }

    val workHue = remember(route.displayName) { HomeFacts.workHue(emptyList(), route.displayName) }
    val palette = remember(workHue, tokens.theme) { SubjectPalette.fromHue(workHue, tokens.theme) }

    val edit = editingSeries
    if (edit != null && seriesFormRepository != null && seriesWrites != null) {
        val series = edit.first
        val subtitle = listOfNotNull(series.title, series.workCount?.let { "$it ${if (it == 1) "work" else "works"}" },
            series.words?.takeIf { it > 0 }?.let { "%,d words".format(it) }).joinToString(" · ")
        io.github.cidy02.kudos.writing.WritingSeriesScreen(series.id, series.title, seriesFormRepository, seriesWrites,
            onBack = { editingSeries = null }, onOpenAo3 = onOpenWeb, reorderOnly = edit.second, subtitle = subtitle)
        return
    }

    ProvidePushedShellChrome(
        hasSubjectHeader = true,
        trailingContent = {
            if (!isDashboard && tab == AuthorTab.Works) {
                val activeCount = worksSort.activeCount + worksFilters.activeCountForRefine
                ToolbarCircleButton(onClick = { showingWorksFilters = true }, accessibilityName = "Sort and filter",
                    palette = tokens.scopePalette, isAccented = activeCount > 0,
                    badge = activeCount.takeIf { it > 0 }?.toString()) {
                    Icon(Icons.Outlined.FilterList, null)
                }
            }
            Box {
                ToolbarCircleButton(
                    onClick = { showMenu = true },
                    accessibilityName = "Menu",
                    palette = palette
                ) {
                    Icon(Icons.Default.MoreVert, contentDescription = null)
                }
                DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
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

    LazyColumn(
        modifier = modifier
            .testTag("Author profile")
            .fillMaxSize()
            .subjectScreenWash(palette = SubjectPalette.fromHue(HomeFacts.workHue(emptyList(), route.displayName), tokens.theme))
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
                        onPrimaryAction = { loadHeader() }
                    )
                }
            }
        } else {
            val h = header
            if (h != null) {
                item {
                    Column(modifier = Modifier.padding(top = WindowInsets.statusBars.asPaddingValues().calculateTopPadding() + 56.dp)) {
                        if (isDashboard) {
                            SubjectHeaderBlock(
                                kicker = "AO3 Account",
                                title = route.displayName,
                                subtitle = null,
                                palette = SubjectPalette.fromHue(HomeFacts.workHue(emptyList(), route.displayName), tokens.theme)
                            )
                            if (h.pseuds.size > 1) {
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
                            if (pageData == null || visibleWorks.isEmpty()) {
                                item { EmptyStateCard("No works", "No works by this author are visible to you on AO3.") }
                            } else {
                                items(visibleWorks, key = { it.id }) { work ->
                                    AO3AuthorWorkCard(
                                        work = work,
                                        displayMode = displayMode,
                                        expandAll = false,
                                        showsPerformance = false, // on own profile it could be true
                                        onOpenWork = onOpenWork
                                    )
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
