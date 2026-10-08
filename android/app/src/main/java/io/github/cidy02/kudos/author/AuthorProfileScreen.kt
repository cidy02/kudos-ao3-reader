package io.github.cidy02.kudos.author

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.account.AccountListType
import io.github.cidy02.kudos.network.ao3.AO3Result
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AuthorProfileScreen(
    username: String,
    initialPseud: String? = null,
    authorRepository: AO3AuthorRepository,
    onOpenWork: (AO3WorkSummary) -> Unit,
    onOpenSeries: (String) -> Unit = {},
    onOpenWeb: (String) -> Unit = {},
    isDashboard: Boolean = false,
    onOpenDashboardList: ((AccountListType) -> Unit)? = null,
    onOpenAO3Collections: (() -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    var route by remember(username, initialPseud) {
        mutableStateOf(AO3AuthorRoute(username.trim(), initialPseud?.trim()?.takeIf { it.isNotBlank() }))
    }
    var header by remember { mutableStateOf<AO3AuthorHeader?>(null) }
    var headerError by remember { mutableStateOf<String?>(null) }
    var headerLoading by remember { mutableStateOf(true) }
    
    var tab by remember { mutableStateOf(AuthorTab.Works) }
    var page by remember { mutableIntStateOf(1) }
    
    var works by remember { mutableStateOf<AO3SearchPage?>(null) }
    var series by remember { mutableStateOf<AO3AuthorSeriesPage?>(null) }
    var bookmarks by remember { mutableStateOf<AO3AuthorBookmarksPage?>(null) }
    var about by remember { mutableStateOf<AO3AuthorAbout?>(null) }
    
    var tabLoading by remember { mutableStateOf(false) }
    var tabError by remember { mutableStateOf<String?>(null) }
    
    var scopeState by remember { mutableStateOf(AO3AuthorWorksScope.Works) }
    var displayMode by remember { mutableStateOf(AuthorDisplayMode.Detailed) }
    
    val scope = rememberCoroutineScope()
    val tokens = LocalKudosTokens.current

    fun loadHeader() {
        headerLoading = true
        headerError = null
        scope.launch {
            when (val result = authorRepository.loadDashboard(route)) {
                is AO3Result.Success -> {
                    header = result.value
                    headerError = null
                }
                is AO3Result.Failure -> {
                    headerError = result.error.displayMessage()
                }
            }
            headerLoading = false
        }
    }

    fun loadTab(target: AuthorTab, pageNum: Int = 1) {
        tabLoading = true
        tabError = null
        page = pageNum
        scope.launch {
            when (target) {
                AuthorTab.Works -> when (val r = authorRepository.loadWorks(route, pageNum, scopeState)) {
                    is AO3Result.Success -> works = r.value
                    is AO3Result.Failure -> tabError = r.error.displayMessage()
                }
                AuthorTab.Series -> when (val r = authorRepository.loadSeries(route, pageNum)) {
                    is AO3Result.Success -> series = r.value
                    is AO3Result.Failure -> tabError = r.error.displayMessage()
                }
                AuthorTab.Bookmarks -> when (val r = authorRepository.loadBookmarks(route, pageNum)) {
                    is AO3Result.Success -> bookmarks = r.value
                    is AO3Result.Failure -> tabError = r.error.displayMessage()
                }
                AuthorTab.About -> when (val r = authorRepository.loadAbout(route)) {
                    is AO3Result.Success -> about = r.value
                    is AO3Result.Failure -> tabError = r.error.displayMessage()
                }
            }
            tabLoading = false
        }
    }

    LaunchedEffect(route.id, scopeState) {
        loadHeader()
        if (!isDashboard) {
            loadTab(tab, 1)
        }
    }
    
    var showMenu by remember { mutableStateOf(false) }

    val workHue = remember(route.displayName) { HomeFacts.workHue(emptyList(), route.displayName) }
    val palette = remember(workHue, tokens.theme) { SubjectPalette.fromHue(workHue, tokens.theme) }

    ProvidePushedShellChrome(
        hasSubjectHeader = true,
        trailingContent = {
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
                }
            }
        }
    )

    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .subjectScreenWash(palette = SubjectPalette.fromHue(HomeFacts.workHue(emptyList(), route.displayName), tokens.theme))
            .padding(horizontal = 16.dp),
        contentPadding = PaddingValues(top = 24.dp, bottom = 48.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        if (headerLoading && header == null) {
            item { LoadingStateCard("Loading author profile") }
        } else if (headerError != null && header == null) {
            item {
                ErrorStateCard(
                    title = "Couldn't load author",
                    message = headerError!!,
                    primaryActionLabel = "Try Again",
                    onPrimaryAction = { loadHeader() }
                )
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
                                tab = it
                                loadTab(it, 1)
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
                                                scopeState = scopeVal
                                                loadTab(tab, 1)
                                            }
                                        )
                                    }
                                }
                            }
                            
                            val pageData = works
                            if (pageData == null || pageData.works.isEmpty()) {
                                item { EmptyStateCard("No works", "No works by this author are visible to you on AO3.") }
                            } else {
                                items(pageData.works, key = { it.id }) { work ->
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
                                        onNext = { loadTab(AuthorTab.Works, pageData.currentPage + 1) }
                                    )
                                }
                            }
                        }
                        AuthorTab.Series -> {
                            val pageData = series
                            if (pageData == null || pageData.series.isEmpty()) {
                                item { EmptyStateCard("No series", "No series by this author are visible to you on AO3.") }
                            } else {
                                items(pageData.series, key = { it.id }) { s ->
                                    AO3SeriesRow(
                                        series = s,
                                        displayMode = displayMode,
                                        onOpenSeries = onOpenSeries
                                    )
                                }
                                item {
                                    PagerRow(
                                        page = pageData.currentPage,
                                        total = pageData.totalPages,
                                        onPrev = { loadTab(AuthorTab.Series, pageData.currentPage - 1) },
                                        onNext = { loadTab(AuthorTab.Series, pageData.currentPage + 1) }
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
                                        onNext = { loadTab(AuthorTab.Bookmarks, pageData.currentPage + 1) }
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
                                                            route = p.route
                                                            tab = AuthorTab.Works
                                                            loadTab(AuthorTab.Works, 1)
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
private fun PagerRow(page: Int, total: Int, onPrev: () -> Unit, onNext: () -> Unit) {
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
