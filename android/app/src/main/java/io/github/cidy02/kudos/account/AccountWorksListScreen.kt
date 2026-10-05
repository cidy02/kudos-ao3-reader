package io.github.cidy02.kudos.account

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.outlined.AccessTime
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.NotificationsOff
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.key
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.fragment.app.FragmentActivity
import io.github.cidy02.kudos.app.PrivacyGate
import io.github.cidy02.kudos.app.PrivacyRevealState
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.PrivacySettings
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.author.AO3BookmarkFootnote
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.library.LibraryPrivacy
import io.github.cidy02.kudos.library.LibraryPrivacyVisibility
import io.github.cidy02.kudos.core.model.readingProgress
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.network.ao3.account.AO3ReadingEntry
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorBookmark
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.search.SearchFilterSheet
import io.github.cidy02.kudos.search.collectLocalTagSuggestions
import io.github.cidy02.kudos.search.includesAccountWork
import io.github.cidy02.kudos.search.hasPostedChapterCount
import io.github.cidy02.kudos.search.isSubscriptionIndexOnly
import io.github.cidy02.kudos.search.refineMatchText
import io.github.cidy02.kudos.ui.components.DestructiveConfirmation
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.KudosPaginationBar
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.account.AO3NamedSubscription
import io.github.cidy02.kudos.network.ao3.account.AO3NamedSubscriptionsScope
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.components.SensitiveWorkRow
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.FilterButton
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectChip
import io.github.cidy02.kudos.ui.subject.SubjectChipStyle
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.subjectPanel
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import io.github.cidy02.kudos.works.CanonicalWork
import io.github.cidy02.kudos.works.WorkRepository
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository

/**
 * Top-level screen for AO3 Account Work Lists (Marked for Later, Bookmarks, History, Subscriptions, Collections).
 * Mirrors iOS AO3AccountWorksList.swift.
 */
@Composable
fun AccountWorksListScreen(
    type: AccountListType,
    repository: AccountListRepository,
    writeRepository: AO3WriteRepository,
    workRepository: WorkRepository,
    settingsRepository: SettingsRepository,
    privacyGate: PrivacyGate,
    onLogin: () -> Unit,
    onOpenWork: (AO3WorkSummary) -> Unit,
    onOpenSeries: (String) -> Unit,
    onOpenAuthor: (String) -> Unit,
    modifier: Modifier = Modifier,
    viewModel: AccountListViewModel = viewModel(
        key = type.listKey,
        factory = AccountListViewModel.factory(type, repository, workRepository)
    )
) {
    val state by viewModel.uiState.collectAsState()
    val tokens = LocalKudosTokens.current
    // The reader's accent, or Sepia's own brown: iOS `theme.scopePalette`. This was
    // `fromHue(210.0)`; a hue is a 0 to 1 fraction, so 210 wrapped to red whatever the accent.
    val palette = tokens.scopePalette

    var expandAll by remember { mutableStateOf(false) }
    val settings by settingsRepository.settings.collectAsState(initial = KudosSettings.Defaults)
    val reveal by privacyGate.state.collectAsState()
    val context = LocalContext.current
    val activity = context as? FragmentActivity
    val authState by repository.authRepository.state.collectAsState()
    var showMenu by remember { mutableStateOf(false) }
    var showingFilters by remember(type) { mutableStateOf(false) }
    var filters by remember(type) { mutableStateOf(AO3SearchFilters()) }
    var subscriptionsScope by remember(type) { mutableStateOf("works") }
    var subscriptionsPage by remember(type, subscriptionsScope) { mutableStateOf(1) }
    val generation by repository.authRepository.generation.collectAsState()
    LaunchedEffect(viewModel, generation) { viewModel.ensureSessionLoaded() }
    val namedScope = AO3NamedSubscriptionsScope.entries.firstOrNull { it.parameter == subscriptionsScope }
    val namedLoader = remember(repository, namedScope, subscriptionsPage, generation) {
        namedScope?.let { NamedSubscriptionsLoader(repository, it, subscriptionsPage) }
    }
    var subscriptionWatermarks by remember(type) {
        mutableStateOf(SubscriptionWatermarks.load(context, SubscriptionWatermarks.NAMESPACE_SUBSCRIPTIONS))
    }
    val loaded = state as? AccountListUiState.Loaded
    val pageWorks = loaded?.page?.works.orEmpty()
    val unsubscribeState = remember(writeRepository, generation) {
        SubscriptionUnsubscribeState(writeRepository, repository.authRepository)
    }
    var enrichedSubscriptions by remember(type, pageWorks, authState) {
        mutableStateOf(emptyMap<Long, AO3WorkSummary>())
    }
    val enricher = remember(context) {
        (context.applicationContext as? io.github.cidy02.kudos.KudosApplication)
            ?.container?.sparseWorkEnricher
    }
    // iOS enriches only the loaded subscriptions page, after it is on screen. Reuse the
    // rows' memoised anonymous lookup, sequentially; changing page/session cancels the walk.
    LaunchedEffect(type, pageWorks, authState, subscriptionsScope) {
        if (type == AccountListType.Subscriptions && subscriptionsScope == "works" && authState.isSignedIn) {
            for (work in pageWorks) {
                val known = enricher?.enrich(work) ?: work
                currentCoroutineContext().ensureActive()
                enrichedSubscriptions = enrichedSubscriptions + (work.id to known)
                if (known.hasPostedChapterCount()) {
                    subscriptionWatermarks = SubscriptionWatermarks.baseline(
                        context, SubscriptionWatermarks.NAMESPACE_SUBSCRIPTIONS, listOf(known)
                    )
                }
            }
        }
    }
    val refinedWorks = remember(loaded?.canonicalWorks, filters, enrichedSubscriptions, type) {
        loaded?.canonicalWorks.orEmpty().mapNotNull { entry ->
            val subscriptions = type == AccountListType.Subscriptions
            val known = if (subscriptions) enrichedSubscriptions[entry.remote.id] ?: entry.remote else entry.remote
            if (filters.includesAccountWork(known, subscriptions)) entry.copy(remote = known) else null
        }
    }
    val works = remember(refinedWorks, settings.privacy, reveal) {
        visibleEntries(refinedWorks, settings.privacy, reveal)
    }
    val hasWorks = authState.isSignedIn && pageWorks.isNotEmpty() &&
        (type != AccountListType.Subscriptions || subscriptionsScope == "works")
    val hasNewChapters = type == AccountListType.Subscriptions && works.any {
        SubscriptionWatermarks.newChapterCount(it.remote, subscriptionWatermarks) > 0
    }

    ProvidePushedShellChrome(
        hasSubjectHeader = true,
        trailingContent = {
            if (settings.privacy.hideMatureContent || hasWorks) {
                Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    if (hasWorks) {
                        FilterButton(
                            filtersActive = filters.hasActiveFilters,
                            onClick = { showingFilters = true },
                            onClearFilters = { filters = AO3SearchFilters() }
                        )
                    }
                    Box {
                        IconButton(onClick = { showMenu = true }) {
                            Icon(imageVector = Icons.Default.MoreVert, contentDescription = "More actions")
                        }
                        DropdownMenu(
                            expanded = showMenu,
                            onDismissRequest = { showMenu = false }
                        ) {
                            // iOS's MatureRevealToggle: present only while Hide mature content is on.
                            if (settings.privacy.hideMatureContent) {
                                DropdownMenuItem(
                                    text = { Text(if (reveal.revealAll) "Hide mature" else "Show mature") },
                                    leadingIcon = {
                                        Icon(
                                            if (reveal.revealAll) Icons.Filled.VisibilityOff else Icons.Filled.Visibility,
                                            contentDescription = null
                                        )
                                    },
                                    onClick = {
                                        showMenu = false
                                        privacyGate.toggleRevealAll(activity)
                                    }
                                )
                            }
                            // These lists have fixed layouts on iOS. Android's other lists draw
                            // detailed cards; there is no account display-mode setting to switch.
                            if (hasWorks && type != AccountListType.MarkedForLater && type != AccountListType.Subscriptions) {
                                DropdownMenuItem(
                                    text = { Text(if (expandAll) "Collapse All" else "Expand All") },
                                    onClick = {
                                        showMenu = false
                                        expandAll = !expandAll
                                    }
                                )
                            }
                            if (hasWorks && hasNewChapters) {
                                DropdownMenuItem(
                                    text = { Text("Mark All as Seen") },
                                    leadingIcon = { Icon(Icons.Outlined.NotificationsOff, contentDescription = null) },
                                    onClick = {
                                        showMenu = false
                                        subscriptionWatermarks = SubscriptionWatermarks.markAllSeen(
                                            context,
                                            SubscriptionWatermarks.NAMESPACE_SUBSCRIPTIONS,
                                            works.map { it.remote }.filter { it.hasPostedChapterCount() }
                                        )
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
    )

    Box(
        modifier = modifier
            .fillMaxSize()
            .subjectScreenWash(palette = palette)
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            Spacer(modifier = Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
            Spacer(modifier = Modifier.height(56.dp))

            if (type == AccountListType.Subscriptions) {
                val rowPrivacy = remember(settings.privacy, reveal, activity) {
                    PairedRowPrivacy(
                        isObscured = { LibraryPrivacy.visibility(it, settings.privacy, reveal) == LibraryPrivacyVisibility.Obscured },
                        reveal = { privacyGate.reveal(it.id, activity) }
                    )
                }
                CompositionLocalProvider(LocalPairedRowPrivacy provides rowPrivacy) {
                    SubscriptionsBrowser(
                        works = works,
                        watermarks = subscriptionWatermarks,
                        scope = subscriptionsScope,
                        onScopeChange = { subscriptionsScope = it },
                        onUnsubscribeWork = { viewModel.removeSubscription(it.remote.id, loaded?.page?.currentPage ?: 1) },
                        unsubscribePaths = loaded?.page?.unsubscribePaths.orEmpty(),
                        unsubscribeState = unsubscribeState,
                        currentPage = loaded?.page?.currentPage ?: 1,
                        totalPages = loaded?.page?.totalPages ?: 1,
                        expandAll = expandAll,
                        palette = palette,
                        onLoadPage = viewModel::load,
                        onOpenWork = onOpenWork,
                        worksState = state,
                        namedLoader = namedLoader,
                        namedScope = namedScope,
                        onNamedPageChange = { subscriptionsPage = it },
                        onLogin = onLogin,
                        onOpenSeries = onOpenSeries,
                        onOpenAuthor = onOpenAuthor
                    )
                }
            } else when (val current = state) {
                AccountListUiState.Loading -> {
                    Box(modifier = Modifier.padding(SubjectMetrics.accountGutter)) {
                        LoadingStateCard("Loading ${type.title}")
                    }
                }
                AccountListUiState.AuthRequired -> {
                    Box(modifier = Modifier.padding(SubjectMetrics.accountGutter)) {
                        EmptyStateCard(
                            title = "AO3 session required",
                            message = "Your AO3 session needs to be refreshed.",
                            primaryActionLabel = "Log In Again",
                            onPrimaryAction = onLogin
                        )
                    }
                }
                is AccountListUiState.Failed -> {
                    Box(modifier = Modifier.padding(SubjectMetrics.accountGutter)) {
                        ErrorStateCard(
                            title = "Could not load ${type.title}",
                            message = current.message,
                            primaryActionLabel = "Retry",
                            onPrimaryAction = { viewModel.load(1) }
                        )
                    }
                }
                is AccountListUiState.Loaded -> {
                    if (current.canonicalWorks.isEmpty() && current.page.works.isEmpty()) {
                        Box(modifier = Modifier.padding(SubjectMetrics.accountGutter)) {
                            EmptyStateCard(
                                title = type.emptyTitle,
                                message = type.emptyMessage
                            )
                        }
                    } else {
                        val rowPrivacy = remember(settings.privacy, reveal, activity) {
                            PairedRowPrivacy(
                                isObscured = {
                                    LibraryPrivacy.visibility(it, settings.privacy, reveal) ==
                                        LibraryPrivacyVisibility.Obscured
                                },
                                reveal = { privacyGate.reveal(it.id, activity) }
                            )
                        }
                        CompositionLocalProvider(LocalPairedRowPrivacy provides rowPrivacy) {
                            when (type) {
                                AccountListType.MarkedForLater -> {
                                    MarkedForLaterBrowser(
                                        works = works,
                                        currentPage = current.page.currentPage,
                                        totalPages = current.page.totalPages,
                                        expandAll = expandAll,
                                        palette = palette,
                                        onLoadPage = viewModel::load,
                                        onOpenWork = onOpenWork
                                    )
                                }
                                AccountListType.Bookmarks -> {
                                    BookmarksBrowser(
                                        works = works,
                                        bookmarks = current.page.bookmarkDetails,
                                        currentPage = current.page.currentPage,
                                        totalPages = current.page.totalPages,
                                        expandAll = expandAll,
                                        palette = palette,
                                        onLoadPage = viewModel::load,
                                        onOpenWork = onOpenWork
                                    )
                                }
                                AccountListType.History -> {
                                    HistoryBrowser(
                                        works = works,
                                        readings = current.page.readingEntries,
                                        currentPage = current.page.currentPage,
                                        totalPages = current.page.totalPages,
                                        expandAll = expandAll,
                                        palette = palette,
                                        onLoadPage = viewModel::load,
                                        onOpenWork = onOpenWork
                                    )
                                }
                                else -> {
                                    GenericAccountWorksBrowser(
                                        type = type,
                                        works = works,
                                        currentPage = current.page.currentPage,
                                        totalPages = current.page.totalPages,
                                        expandAll = expandAll,
                                        palette = palette,
                                        onLoadPage = viewModel::load,
                                        onOpenWork = onOpenWork
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    if (showingFilters) {
        val pending = if (type == AccountListType.Subscriptions && filters.hasActiveFilters) {
            works.count { it.remote.isSubscriptionIndexOnly() }
        } else 0
        SearchFilterSheet(
            filters = filters,
            onFiltersChange = { filters = it },
            onApply = { showingFilters = false },
            onClear = { filters = AO3SearchFilters() },
            onDismiss = { showingFilters = false },
            localTagSuggestions = collectLocalTagSuggestions(loaded?.canonicalWorks.orEmpty().mapNotNull { it.local }),
            refine = true,
            refineMatchText = if (pageWorks.isEmpty()) null else refineMatchText(pageWorks.size, works.size - pending, pending)
        )
    }
}

// region 1. Marked for Later Browser

@Composable
private fun MarkedForLaterBrowser(
    works: List<CanonicalWork>,
    currentPage: Int,
    totalPages: Int,
    expandAll: Boolean,
    palette: SubjectPalette,
    onLoadPage: (Int) -> Unit,
    onOpenWork: (AO3WorkSummary) -> Unit
) {
    val context = LocalContext.current
    var watermarks by remember {
        mutableStateOf(SubscriptionWatermarks.load(context, SubscriptionWatermarks.NAMESPACE_MARKED_FOR_LATER))
    }

    LaunchedEffect(works) {
        watermarks = SubscriptionWatermarks.baseline(
            context,
            SubscriptionWatermarks.NAMESPACE_MARKED_FOR_LATER,
            works.map { it.remote }
        )
    }

    var filter by remember { mutableStateOf("all") }
    var unmarkedIds by remember { mutableStateOf(setOf<Long>()) }

    val activeWorks = remember(works, unmarkedIds) {
        works.filter { it.remote.id !in unmarkedIds }
    }

    val updatedWorks = remember(activeWorks, watermarks) {
        activeWorks.filter { SubscriptionWatermarks.newChapterCount(it.remote, watermarks) > 0 }
    }

    val downloadedWorks = remember(activeWorks) {
        activeWorks.filter { it.local?.isDownloaded == true }
    }

    val displayedWorks = when (filter) {
        "updated" -> updatedWorks
        "downloaded" -> downloadedWorks
        else -> activeWorks
    }

    val subtitle = buildString {
        append(if (displayedWorks.size == 1) "1 work" else "${displayedWorks.size} works")
        if (totalPages > 1) {
            append(" · page $currentPage of $totalPages")
        }
    }

    LazyColumn(
        verticalArrangement = Arrangement.spacedBy(10.dp),
        contentPadding = PaddingValues(
            start = SubjectMetrics.accountGutter,
            end = SubjectMetrics.accountGutter,
            bottom = 24.dp
        ),
        modifier = Modifier.fillMaxSize()
    ) {
        item {
            SubjectHeaderBlock(
                kicker = "AO3 Account",
                title = "Marked for Later",
                subtitle = subtitle,
                palette = palette,
                gutter = 0.dp
            )
        }

        item {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                SubjectChip("All", style = SubjectChipStyle.Pill(filter == "all"), palette = palette, modifier = Modifier.clickable { filter = "all" })
                SubjectChip("Updated", style = SubjectChipStyle.Pill(filter == "updated"), palette = palette, modifier = Modifier.clickable { filter = "updated" })
                SubjectChip("Downloaded", style = SubjectChipStyle.Pill(filter == "downloaded"), palette = palette, modifier = Modifier.clickable { filter = "downloaded" })
                SubjectChip("Reset", style = SubjectChipStyle.Pill(false), leadingIcon = Icons.Outlined.Close, modifier = Modifier.clickable { filter = "all" })
            }
        }

        if (totalPages > 1) {
            item {
                KudosPaginationBar(currentPage = currentPage, totalPages = totalPages, onPageChange = onLoadPage)
            }
        }

        if (displayedWorks.isEmpty()) {
            item {
                EmptyStateCard(
                    title = "No matching works",
                    message = "No works on this page are ${filter}."
                )
            }
        } else if (filter == "all" && updatedWorks.isNotEmpty()) {
            // Group 1: Updated since you looked
            item {
                SectionRuleHeader(title = "Updated since you looked", count = updatedWorks.size)
            }
            items(updatedWorks, key = { "updated-${it.id}" }) { work ->
                MarkedForLaterRow(
                    work = work,
                    expandAll = expandAll,
                    palette = palette,
                    onOpenWork = onOpenWork,
                    onUnmark = { unmarkedIds = unmarkedIds + work.remote.id }
                )
            }

            // Group 2: Everything else
            val otherWorks = activeWorks.filter { it !in updatedWorks }
            if (otherWorks.isNotEmpty()) {
                item {
                    SectionRuleHeader(title = "Everything else", count = otherWorks.size)
                }
                items(otherWorks, key = { "other-${it.id}" }) { work ->
                    MarkedForLaterRow(
                        work = work,
                        expandAll = expandAll,
                        palette = palette,
                        onOpenWork = onOpenWork,
                        onUnmark = { unmarkedIds = unmarkedIds + work.remote.id }
                    )
                }
            }
        } else {
            items(displayedWorks, key = { "mfl-${it.id}" }) { work ->
                MarkedForLaterRow(
                    work = work,
                    expandAll = expandAll,
                    palette = palette,
                    onOpenWork = onOpenWork,
                    onUnmark = { unmarkedIds = unmarkedIds + work.remote.id }
                )
            }
        }

        item {
            Text(
                text = "Your Marked for Later list is stored on AO3. Unmarking a work here also removes it from that list on AO3. You're viewing $currentPage of $totalPages ${if (totalPages == 1) "page" else "pages"}.",
                color = LocalKudosTokens.current.secondaryInk,
                fontSize = 12.sp,
                modifier = Modifier.padding(top = 8.dp)
            )
        }

        if (totalPages > 1) {
            item {
                KudosPaginationBar(currentPage = currentPage, totalPages = totalPages, onPageChange = onLoadPage)
            }
        }
    }
}

@Composable
private fun MarkedForLaterRow(
    work: CanonicalWork,
    expandAll: Boolean,
    palette: SubjectPalette,
    onOpenWork: (AO3WorkSummary) -> Unit,
    onUnmark: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        PairedWorkRow(work = work, expandAll = expandAll, onOpenWork = onOpenWork)

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (work.local?.isDownloaded == true) {
                Text(
                    text = "Downloaded",
                    color = tokens.secondaryInk,
                    fontSize = 12.sp,
                    fontFamily = FontFamily.Monospace
                )
            } else {
                Spacer(modifier = Modifier.width(1.dp))
            }

            SubjectChip(
                text = "Unmark",
                style = SubjectChipStyle.Neutral,
                leadingIcon = Icons.Outlined.AccessTime,
                palette = palette,
                modifier = Modifier.clickable(onClick = onUnmark)
            )
        }
    }
}

// endregion

// region 2. Bookmarks Browser

@Composable
private fun BookmarksBrowser(
    works: List<CanonicalWork>,
    bookmarks: List<AO3AuthorBookmark>,
    currentPage: Int,
    totalPages: Int,
    expandAll: Boolean,
    palette: SubjectPalette,
    onLoadPage: (Int) -> Unit,
    onOpenWork: (AO3WorkSummary) -> Unit
) {
    val bookmarksByWorkId = remember(bookmarks) {
        bookmarks.mapNotNull { b -> b.work?.id?.let { it to b } }.toMap()
    }

    var filter by remember { mutableStateOf("all") }

    val displayedWorks = remember(works, bookmarksByWorkId, filter) {
        when (filter) {
            "recs" -> works.filter { bookmarksByWorkId[it.remote.id]?.isRecommendation == true }
            "private" -> works.filter { bookmarksByWorkId[it.remote.id]?.isPrivate == true }
            "withNotes" -> works.filter { bookmarksByWorkId[it.remote.id]?.notes?.isNotBlank() == true }
            else -> works
        }
    }

    val subtitle = buildString {
        append(if (displayedWorks.size == 1) "1 work" else "${displayedWorks.size} works")
        if (totalPages > 1) {
            append(" · page $currentPage of $totalPages")
        }
    }

    LazyColumn(
        verticalArrangement = Arrangement.spacedBy(10.dp),
        contentPadding = PaddingValues(
            start = SubjectMetrics.accountGutter,
            end = SubjectMetrics.accountGutter,
            bottom = 24.dp
        ),
        modifier = Modifier.fillMaxSize()
    ) {
        item {
            SubjectHeaderBlock(
                kicker = "AO3 Account",
                title = "Bookmarks",
                subtitle = subtitle,
                palette = palette,
                gutter = 0.dp
            )
        }

        item {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                SubjectChip("All", style = SubjectChipStyle.Pill(filter == "all"), palette = palette, modifier = Modifier.clickable { filter = "all" })
                SubjectChip("Recs", style = SubjectChipStyle.Pill(filter == "recs"), palette = palette, modifier = Modifier.clickable { filter = "recs" })
                SubjectChip("Private", style = SubjectChipStyle.Pill(filter == "private"), palette = palette, modifier = Modifier.clickable { filter = "private" })
                SubjectChip("With notes", style = SubjectChipStyle.Pill(filter == "withNotes"), palette = palette, modifier = Modifier.clickable { filter = "withNotes" })
                SubjectChip("Reset", style = SubjectChipStyle.Pill(false), leadingIcon = Icons.Outlined.Close, modifier = Modifier.clickable { filter = "all" })
            }
        }

        if (totalPages > 1) {
            item {
                KudosPaginationBar(currentPage = currentPage, totalPages = totalPages, onPageChange = onLoadPage)
            }
        }

        if (displayedWorks.isEmpty()) {
            item {
                EmptyStateCard(
                    title = "No matching works",
                    message = when (filter) {
                        "recs" -> "No works on this page are recommended."
                        "private" -> "No works on this page are private."
                        "withNotes" -> "No works on this page have notes."
                        else -> "No works on this page."
                    }
                )
            }
        } else {
            items(displayedWorks, key = { "bm-${it.id}" }) { work ->
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    PairedWorkRow(work = work, expandAll = expandAll, onOpenWork = onOpenWork)

                    val bookmark = bookmarksByWorkId[work.remote.id]
                    if (bookmark != null) {
                        Box(modifier = Modifier.padding(horizontal = 8.dp)) {
                            AO3BookmarkFootnote(bookmark = bookmark)
                        }
                    }
                }
            }
        }

        item {
            Text(
                text = "These are your AO3 bookmarks. Each row shows that bookmark's note, tags, date, privacy and recommendation status. The filters apply to $currentPage of $totalPages ${if (totalPages == 1) "page" else "pages"}.",
                color = LocalKudosTokens.current.secondaryInk,
                fontSize = 12.sp,
                modifier = Modifier.padding(top = 8.dp)
            )
        }

        if (totalPages > 1) {
            item {
                KudosPaginationBar(currentPage = currentPage, totalPages = totalPages, onPageChange = onLoadPage)
            }
        }
    }
}

// endregion

// region 3. History Browser

@Composable
private fun HistoryBrowser(
    works: List<CanonicalWork>,
    readings: List<AO3ReadingEntry>,
    currentPage: Int,
    totalPages: Int,
    expandAll: Boolean,
    palette: SubjectPalette,
    onLoadPage: (Int) -> Unit,
    onOpenWork: (AO3WorkSummary) -> Unit
) {
    val readingsByWorkId = remember(readings) {
        readings.mapNotNull { r -> r.workId?.let { it to r } }.toMap()
    }

    var filter by remember { mutableStateOf("everything") }
    var deletedIds by remember { mutableStateOf(setOf<Long>()) }
    var pendingDelete by remember { mutableStateOf<CanonicalWork?>(null) }
    var confirmClearHistory by remember { mutableStateOf(false) }

    val activeWorks = remember(works, deletedIds) {
        works.filter { it.remote.id !in deletedIds }
    }

    val displayedWorks = remember(activeWorks, filter) {
        when (filter) {
            "inProgress" -> activeWorks.filter {
                val local = it.local
                local != null && !local.isFinished && (local.readingProgress ?: 0.0) > 0.0
            }
            "finished" -> activeWorks.filter { it.local?.isFinished == true }
            else -> activeWorks
        }
    }

    DestructiveConfirmation(
        show = pendingDelete != null,
        title = "Delete from History?",
        text = if (pendingDelete?.remote?.title.isNullOrBlank()) {
            "This removes the work from your AO3 reading history. The work stays on AO3."
        } else {
            "“${pendingDelete?.remote?.title}” will be removed from your AO3 reading history. The work stays on AO3."
        },
        confirmText = "Delete from History",
        confirmBeforeDelete = true,
        onConfirm = {
            val pending = pendingDelete ?: return@DestructiveConfirmation
            pendingDelete = null
            deletedIds = deletedIds + pending.remote.id
        },
        onDismissRequest = { pendingDelete = null }
    )

    DestructiveConfirmation(
        show = confirmClearHistory,
        title = "Clear your entire history?",
        text = "This clears your AO3 reading history. It doesn't delete the works and can't be undone.",
        confirmText = "Clear History",
        confirmBeforeDelete = true,
        onConfirm = {
            confirmClearHistory = false
            deletedIds = works.map { it.remote.id }.toSet()
        },
        onDismissRequest = { confirmClearHistory = false }
    )

    val subtitle = buildString {
        append(if (displayedWorks.size == 1) "1 work" else "${displayedWorks.size} works")
        if (totalPages > 1) {
            append(" · page $currentPage of $totalPages")
        }
    }

    LazyColumn(
        verticalArrangement = Arrangement.spacedBy(10.dp),
        contentPadding = PaddingValues(
            start = SubjectMetrics.accountGutter,
            end = SubjectMetrics.accountGutter,
            bottom = 24.dp
        ),
        modifier = Modifier.fillMaxSize()
    ) {
        item {
            SubjectHeaderBlock(
                kicker = "AO3 Account",
                title = "History",
                subtitle = subtitle,
                palette = palette,
                gutter = 0.dp
            )
        }

        item {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                SubjectChip("Everything", style = SubjectChipStyle.Pill(filter == "everything"), palette = palette, modifier = Modifier.clickable { filter = "everything" })
                SubjectChip("In progress", style = SubjectChipStyle.Pill(filter == "inProgress"), palette = palette, modifier = Modifier.clickable { filter = "inProgress" })
                SubjectChip("Finished", style = SubjectChipStyle.Pill(filter == "finished"), palette = palette, modifier = Modifier.clickable { filter = "finished" })
                SubjectChip("Reset", style = SubjectChipStyle.Pill(false), leadingIcon = Icons.Outlined.Close, modifier = Modifier.clickable { filter = "everything" })
            }
        }

        if (totalPages > 1) {
            item {
                KudosPaginationBar(currentPage = currentPage, totalPages = totalPages, onPageChange = onLoadPage)
            }
        }

        if (displayedWorks.isEmpty()) {
            item {
                EmptyStateCard(
                    title = "No matching works",
                    message = "No works on this page are ${filter}."
                )
            }
        } else {
            items(displayedWorks, key = { "hist-${it.id}" }) { work ->
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    PairedWorkRow(work = work, expandAll = expandAll, onOpenWork = onOpenWork)

                    val reading = readingsByWorkId[work.remote.id]
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 8.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        if (reading != null) {
                            val facts = listOfNotNull(
                                reading.visitCountDisplay,
                                reading.versionDisplay,
                                reading.lastVisitedDisplay
                            ).joinToString(" · ")
                            Text(
                                text = facts,
                                color = LocalKudosTokens.current.secondaryInk,
                                fontSize = 12.sp,
                                fontFamily = FontFamily.Monospace,
                                modifier = Modifier.weight(1f, fill = false)
                            )
                        } else {
                            Spacer(modifier = Modifier.width(1.dp))
                        }

                        SubjectChip(
                            text = "Delete",
                            style = SubjectChipStyle.Neutral,
                            leadingIcon = Icons.Outlined.Delete,
                            palette = palette,
                            modifier = Modifier.clickable { pendingDelete = work }
                        )
                    }
                }
            }
        }

        if (totalPages > 1) {
            item {
                KudosPaginationBar(currentPage = currentPage, totalPages = totalPages, onPageChange = onLoadPage)
            }
        }
    }
}

// endregion

// region 4. Subscriptions Browser

@Composable
internal fun SubscriptionsBrowser(
    works: List<CanonicalWork>,
    watermarks: Map<Long, SubscriptionWatermark>,
    scope: String,
    onScopeChange: (String) -> Unit,
    onUnsubscribeWork: (CanonicalWork) -> Unit,
    currentPage: Int,
    totalPages: Int,
    expandAll: Boolean,
    palette: SubjectPalette,
    onLoadPage: (Int) -> Unit,
    onOpenWork: (AO3WorkSummary) -> Unit,
    worksState: AccountListUiState,
    namedLoader: NamedSubscriptionsLoader?,
    namedScope: AO3NamedSubscriptionsScope?,
    onNamedPageChange: (Int) -> Unit,
    onLogin: () -> Unit,
    onOpenSeries: (String) -> Unit,
    onOpenAuthor: (String) -> Unit,
    unsubscribePaths: Map<Long, String> = emptyMap(),
    unsubscribeState: SubscriptionUnsubscribeState? = null
) {
    val writeScope = rememberCoroutineScope()
    val busyPath = unsubscribeState?.busyPath?.collectAsState()?.value
    val writeError = unsubscribeState?.error?.collectAsState()?.value
    val visibleKey by rememberUpdatedState(Triple(scope, currentPage, namedLoader))
    var retryNamed by remember(namedLoader) { mutableStateOf(0) }
    // Activation, retry and refresh all die with the visible tab's composition.
    LaunchedEffect(namedLoader, retryNamed) { namedLoader?.load() }
    // A new flow must not draw the previous scope's last collected value for one frame.
    val namedState = key(namedLoader) { namedLoader?.uiState?.collectAsState()?.value }
    val namedPage = (namedState as? NamedSubscriptionsUiState.Loaded)?.page
    var filter by remember { mutableStateOf("all") }
    var pendingUnsubscribe by remember(unsubscribeState, scope, currentPage, namedLoader) {
        mutableStateOf<PendingSubscriptionUnsubscribe?>(null)
    }
    fun stageWork(work: CanonicalWork) {
        val path = unsubscribePaths[work.remote.id] ?: return
        if (busyPath != null) return
        pendingUnsubscribe = PendingSubscriptionUnsubscribe(
            path, work.remote.title, currentPage, false
        ) { onUnsubscribeWork(work) }
    }
    val activeWorks = works

    val updatedWorks = remember(activeWorks, watermarks) {
        activeWorks.filter { SubscriptionWatermarks.newChapterCount(it.remote, watermarks) > 0 }
    }

    val displayedWorks = when (filter) {
        "updated" -> updatedWorks
        else -> activeWorks
    }

    DestructiveConfirmation(
        show = pendingUnsubscribe != null,
        palette = palette,
        title = "Unsubscribe?",
        text = pendingUnsubscribe?.let { pending ->
            if (pending.named) {
                "“${pending.name}” will be removed from your AO3 subscriptions. " +
                    "You will stop getting update emails for it."
            } else if (pending.name.isBlank()) {
                "This removes the work from your AO3 subscriptions. The work stays on AO3."
            } else {
                "“${pending.name}” will be removed from your AO3 subscriptions. The work stays on AO3."
            }
        }.orEmpty(),
        confirmText = "Unsubscribe",
        confirmBeforeDelete = true,
        onConfirm = {
            val pending = pendingUnsubscribe ?: return@DestructiveConfirmation
            pendingUnsubscribe = null
            val writer = unsubscribeState ?: return@DestructiveConfirmation
            val requested = visibleKey
            writeScope.launch {
                writer.confirm(pending.path, pending.page) {
                    pending.onSuccess(visibleKey == requested)
                }
            }
        },
        onDismissRequest = { pendingUnsubscribe = null }
    )

    if (writeError != null) {
        val tokens = LocalKudosTokens.current
        AlertDialog(
            onDismissRequest = { unsubscribeState?.dismissError() },
            title = { Text("Couldn't unsubscribe", color = tokens.primaryInk) },
            text = { Text(writeError, color = tokens.secondaryInk) },
            containerColor = tokens.theme.cardSurface,
            confirmButton = {
                TextButton(onClick = { unsubscribeState?.dismissError() }) {
                    Text("OK", color = palette.accent)
                }
            }
        )
    }

    val subtitle = if (namedScope != null) {
        namedPage?.let { namedScope.subtitle(it.rows.size, it.currentPage, it.totalPages) }.orEmpty()
    } else if (worksState !is AccountListUiState.Loaded) "" else buildString {
        append(if (displayedWorks.size == 1) "1 work" else "${displayedWorks.size} works")
        if (filter == "all" && updatedWorks.isNotEmpty()) {
            append(" · ${updatedWorks.size} with new chapters")
        }
        if (totalPages > 1) {
            append(" · page $currentPage of $totalPages")
        }
    }

    val listContent: @Composable () -> Unit = {
        LazyColumn(
            verticalArrangement = Arrangement.spacedBy(10.dp),
            contentPadding = PaddingValues(
                start = SubjectMetrics.accountGutter,
                end = SubjectMetrics.accountGutter,
                bottom = 24.dp
            ),
            modifier = Modifier.fillMaxSize()
        ) {
            item {
                SubjectHeaderBlock(
                    kicker = "AO3 Account",
                    title = "Subscriptions",
                    subtitle = subtitle,
                    palette = palette,
                    gutter = 0.dp
                )
            }

            // Scope rail: Works / Series / Authors
            item {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    listOf("works" to "Works", "series" to "Series", "users" to "Authors").forEach { (value, title) ->
                        // The page's own pills, as before 3am and as the row of filters below.
                        SubjectChip(
                            title, style = SubjectChipStyle.Pill(scope == value), palette = palette,
                            modifier = Modifier.clickable { onScopeChange(value) }
                        )
                    }
                }
            }

            if (scope == "works" && worksState !is AccountListUiState.Loaded) {
                item {
                    when (worksState) {
                        AccountListUiState.Loading -> LoadingStateCard("Loading Subscriptions")
                        AccountListUiState.AuthRequired -> EmptyStateCard(
                            "AO3 session required", "Your AO3 session needs to be refreshed.",
                            primaryActionLabel = "Log In Again", onPrimaryAction = onLogin
                        )
                        is AccountListUiState.Failed -> ErrorStateCard(
                            "Could not load Subscriptions", worksState.message,
                            primaryActionLabel = "Retry", onPrimaryAction = { onLoadPage(currentPage) }
                        )
                        is AccountListUiState.Loaded -> Unit
                    }
                }
            } else if (scope == "works") {
                // Filter rail: All / Updated
                item {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        SubjectChip("All", style = SubjectChipStyle.Pill(filter == "all"), palette = palette, modifier = Modifier.clickable { filter = "all" })
                        SubjectChip("Updated", style = SubjectChipStyle.Pill(filter == "updated"), palette = palette, modifier = Modifier.clickable { filter = "updated" })
                        SubjectChip("Reset", style = SubjectChipStyle.Pill(false), leadingIcon = Icons.Outlined.Close, modifier = Modifier.clickable { filter = "all" })
                    }
                }

                if (totalPages > 1) {
                    item {
                        KudosPaginationBar(currentPage = currentPage, totalPages = totalPages, onPageChange = onLoadPage)
                    }
                }

                if (displayedWorks.isEmpty()) {
                    item {
                        EmptyStateCard(
                            title = "No subscriptions",
                            message = "Works you subscribe to on AO3 show up here."
                        )
                    }
                } else if (filter == "all" && updatedWorks.isNotEmpty()) {
                    item {
                        SectionRuleHeader(title = "New since you last looked", count = updatedWorks.size)
                    }
                    items(updatedWorks, key = { "sub-up-${it.id}" }) { work ->
                        SubscriptionWorkRow(
                            work = work,
                            expandAll = expandAll,
                            palette = palette,
                            newCount = SubscriptionWatermarks.newChapterCount(work.remote, watermarks),
                            onOpenWork = onOpenWork,
                            unsubscribePath = unsubscribePaths[work.remote.id],
                            busyPath = busyPath,
                            onUnsubscribe = { stageWork(work) }
                        )
                    }

                    val otherWorks = activeWorks.filter { it !in updatedWorks }
                    if (otherWorks.isNotEmpty()) {
                        item {
                            SectionRuleHeader(title = "All works", count = otherWorks.size)
                        }
                        items(otherWorks, key = { "sub-all-${it.id}" }) { work ->
                            SubscriptionWorkRow(
                                work = work,
                                expandAll = expandAll,
                                palette = palette,
                                newCount = 0,
                                onOpenWork = onOpenWork,
                                unsubscribePath = unsubscribePaths[work.remote.id],
                                busyPath = busyPath,
                                onUnsubscribe = { stageWork(work) }
                            )
                        }
                    }
                } else {
                    items(displayedWorks, key = { "sub-${it.id}" }) { work ->
                        SubscriptionWorkRow(
                            work = work,
                            expandAll = expandAll,
                            palette = palette,
                            newCount = SubscriptionWatermarks.newChapterCount(work.remote, watermarks),
                            onOpenWork = onOpenWork,
                            unsubscribePath = unsubscribePaths[work.remote.id],
                            busyPath = busyPath,
                            onUnsubscribe = { stageWork(work) }
                        )
                    }
                }

                item {
                    Text(
                        text = "Your subscriptions are stored on AO3. Unsubscribing here also unsubscribes you on AO3. You're viewing $currentPage of $totalPages ${if (totalPages == 1) "page" else "pages"}.",
                        color = LocalKudosTokens.current.secondaryInk,
                        fontSize = 12.sp,
                        modifier = Modifier.padding(top = 8.dp)
                    )
                }

                if (totalPages > 1) {
                    item {
                        KudosPaginationBar(currentPage = currentPage, totalPages = totalPages, onPageChange = onLoadPage)
                    }
                }
            } else if (namedScope != null) {
                if (namedPage != null && namedPage.totalPages > 1) {
                    item { KudosPaginationBar(namedPage.currentPage, namedPage.totalPages, onPageChange = onNamedPageChange) }
                }
                when (namedState) {
                    is NamedSubscriptionsUiState.Loaded -> {
                        if (namedState.page.rows.isEmpty()) {
                            item { EmptyStateCard(namedScope.emptyTitle, namedScope.emptyMessage) }
                        } else {
                            items(namedState.page.rows, key = { it.path }) { row ->
                                NamedSubscriptionRow(
                                    row = row, palette = palette, busyPath = busyPath,
                                    onUnsubscribe = {
                                        val path = row.unsubscribePath
                                        if (path != null && busyPath == null) {
                                            pendingUnsubscribe = PendingSubscriptionUnsubscribe(
                                                path, row.name, namedState.page.currentPage, true
                                            ) { stillVisible ->
                                                if (namedLoader?.removeSubscription(row.path) == true && stillVisible) {
                                                    onNamedPageChange(namedState.page.currentPage - 1)
                                                }
                                            }
                                        }
                                    }
                                ) {
                                    if (namedScope == AO3NamedSubscriptionsScope.Series) {
                                        AO3Constants.baseHttpUrl.resolve(row.path)?.let { onOpenSeries(it.toString()) }
                                    } else {
                                        AO3Constants.baseHttpUrl.resolve(row.path)?.pathSegments?.getOrNull(1)?.let(onOpenAuthor)
                                    }
                                }
                            }
                        }
                    }
                    is NamedSubscriptionsUiState.Failed -> item {
                        ErrorStateCard("Couldn't load your list", namedState.message,
                            primaryActionLabel = "Try Again", onPrimaryAction = {
                                // The composition owns retry too, through the same refresh box below.
                                retryNamed++
                            })
                    }
                    NamedSubscriptionsUiState.AuthRequired -> item {
                        EmptyStateCard("AO3 session required", "Your AO3 session needs to be refreshed.",
                            primaryActionLabel = "Log In Again", onPrimaryAction = onLogin)
                    }
                    else -> item { LoadingStateCard("Loading Subscriptions") }
                }
                if (namedPage != null && namedPage.totalPages > 1) {
                    item { KudosPaginationBar(namedPage.currentPage, namedPage.totalPages, onPageChange = onNamedPageChange) }
                }
            }
        }
    }
    if (namedLoader != null) {
        key(namedLoader) {
            KudosRefreshBox(onRefresh = { namedLoader.load() }, modifier = Modifier.fillMaxSize()) {
                listContent()
            }
        }
    } else {
        listContent()
    }
}

@Composable
private fun NamedSubscriptionRow(
    row: AO3NamedSubscription,
    palette: SubjectPalette,
    busyPath: String?,
    onUnsubscribe: () -> Unit,
    onOpen: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    Card(
        onClick = onOpen,
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = tokens.theme.cardSurface),
        shape = MaterialTheme.shapes.medium
    ) {
        Column(Modifier.padding(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(row.name, color = tokens.primaryInk, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            if (row.creators.isNotEmpty()) {
                Text("by " + row.creators.joinToString(", ") { it.displayName },
                    color = tokens.secondaryInk, fontSize = 12.5.sp)
            }
            row.unsubscribePath?.let { path ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    SubscriptionUnsubscribeChip(path, busyPath, palette, onUnsubscribe)
                }
            }
        }
    }
}

@Composable
private fun SubscriptionWorkRow(
    work: CanonicalWork,
    expandAll: Boolean,
    palette: SubjectPalette,
    newCount: Int,
    onOpenWork: (AO3WorkSummary) -> Unit,
    unsubscribePath: String?,
    busyPath: String?,
    onUnsubscribe: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        PairedWorkRow(work = work, expandAll = expandAll, onOpenWork = onOpenWork)

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (newCount > 0) {
                Text(
                    text = if (newCount == 1) "Chapter new" else "$newCount chapters new",
                    color = palette.accent,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium
                )
            } else {
                Spacer(modifier = Modifier.width(1.dp))
            }

            unsubscribePath?.let { path ->
                SubscriptionUnsubscribeChip(path, busyPath, palette, onUnsubscribe)
            }
        }
    }
}

private data class PendingSubscriptionUnsubscribe(
    val path: String,
    val name: String,
    val page: Int,
    val named: Boolean,
    val onSuccess: (Boolean) -> Unit
)

@Composable
private fun SubscriptionUnsubscribeChip(
    path: String,
    busyPath: String?,
    palette: SubjectPalette,
    onClick: () -> Unit
) {
    SubjectChip(
        text = if (busyPath == path) "Unsubscribing…" else "Unsubscribe",
        style = SubjectChipStyle.Neutral,
        leadingIcon = Icons.Outlined.NotificationsOff,
        palette = palette,
        modifier = Modifier.clickable(enabled = busyPath == null, onClick = onClick)
    )
}

// endregion

// region 5. Generic Account Works Browser (My Works, Collection, etc.)

@Composable
private fun GenericAccountWorksBrowser(
    type: AccountListType,
    works: List<CanonicalWork>,
    currentPage: Int,
    totalPages: Int,
    expandAll: Boolean,
    palette: SubjectPalette,
    onLoadPage: (Int) -> Unit,
    onOpenWork: (AO3WorkSummary) -> Unit
) {
    val subtitle = buildString {
        append(if (works.size == 1) "1 work" else "${works.size} works")
        if (totalPages > 1) {
            append(" · page $currentPage of $totalPages")
        }
    }

    LazyColumn(
        verticalArrangement = Arrangement.spacedBy(10.dp),
        contentPadding = PaddingValues(
            start = SubjectMetrics.accountGutter,
            end = SubjectMetrics.accountGutter,
            bottom = 24.dp
        ),
        modifier = Modifier.fillMaxSize()
    ) {
        item {
            SubjectHeaderBlock(
                kicker = "AO3 Account",
                title = type.title,
                subtitle = subtitle,
                palette = palette,
                gutter = 0.dp
            )
        }

        if (totalPages > 1) {
            item {
                KudosPaginationBar(currentPage = currentPage, totalPages = totalPages, onPageChange = onLoadPage)
            }
        }

        items(works, key = { "gen-${it.id}" }) { work ->
            PairedWorkRow(work = work, expandAll = expandAll, onOpenWork = onOpenWork)
        }

        if (totalPages > 1) {
            item {
                KudosPaginationBar(currentPage = currentPage, totalPages = totalPages, onPageChange = onLoadPage)
            }
        }
    }
}

// endregion

/**
 * An AO3 work card that enriches itself when sparse (e.g. Subscriptions).
 */
/**
 * iOS `AO3AccountWorksList.visibleEntries`: a library work that Hide mode hides is not paired, so
 * it stays a plain AO3 row with no local state. In Blur mode it stays paired, and its row blurs.
 */
internal fun visibleEntries(
    works: List<CanonicalWork>,
    privacy: PrivacySettings,
    reveal: PrivacyRevealState
): List<CanonicalWork> = works.map { work ->
    val hidden = work.local != null &&
        LibraryPrivacy.visibility(work.local, privacy, reveal) == LibraryPrivacyVisibility.Hidden
    if (hidden) work.copy(local = null) else work
}

/**
 * How a library work on these lists is shown, and what a tap on a blurred one does. Read from
 * the composition, as iOS's rows read its `PrivacyGate` from the environment.
 */
private class PairedRowPrivacy(
    val isObscured: (SavedWork) -> Boolean = { false },
    val reveal: (SavedWork) -> Unit = {}
)

private val LocalPairedRowPrivacy = compositionLocalOf { PairedRowPrivacy() }

/** A work in the reader's library draws as its library row, blurred while the privacy gate hides it. */
@Composable
private fun PairedWorkRow(
    work: CanonicalWork,
    expandAll: Boolean,
    onOpenWork: (AO3WorkSummary) -> Unit
) {
    val local = work.local
    if (local != null) {
        val privacy = LocalPairedRowPrivacy.current
        SensitiveWorkRow(
            work = local,
            expandAll = expandAll,
            obscured = privacy.isObscured(local),
            onReveal = { privacy.reveal(local) },
            onOpenWork = { onOpenWork(work.remote) }
        )
    } else {
        EnrichingWorkRow(work = work.remote, expandAll = expandAll, onOpenWork = onOpenWork)
    }
}

@Composable
private fun EnrichingWorkRow(
    work: AO3WorkSummary,
    expandAll: Boolean,
    onOpenWork: (AO3WorkSummary) -> Unit
) {
    val context = LocalContext.current
    val enricher = remember {
        (context.applicationContext as? io.github.cidy02.kudos.KudosApplication)
            ?.container?.sparseWorkEnricher
    }
    var enriched by remember(work.id) { mutableStateOf<AO3WorkSummary?>(null) }

    LaunchedEffect(work.id) {
        enriched = enricher?.enrich(work)
    }

    SensitiveWorkRow(
        work = enriched ?: work,
        expandAll = expandAll,
        onOpenWork = onOpenWork
    )
}
