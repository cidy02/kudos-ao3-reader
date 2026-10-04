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
import androidx.compose.material.icons.outlined.AccessTime
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.NotificationsOff
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
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.author.AO3BookmarkFootnote
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.readingProgress
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.network.ao3.account.AO3ReadingEntry
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorBookmark
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.ui.components.DestructiveConfirmation
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.KudosPaginationBar
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.components.SensitiveWorkRow
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
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

/**
 * Top-level screen for AO3 Account Work Lists (Marked for Later, Bookmarks, History, Subscriptions, Collections).
 * Mirrors iOS AO3AccountWorksList.swift.
 */
@Composable
fun AccountWorksListScreen(
    type: AccountListType,
    repository: AccountListRepository,
    workRepository: WorkRepository,
    onLogin: () -> Unit,
    onOpenWork: (AO3WorkSummary) -> Unit,
    modifier: Modifier = Modifier,
    viewModel: AccountListViewModel = viewModel(
        key = type.listKey,
        factory = AccountListViewModel.factory(type, repository, workRepository)
    )
) {
    val state by viewModel.uiState.collectAsState()
    val tokens = LocalKudosTokens.current
    val palette = remember(tokens.theme) { SubjectPalette.fromHue(210.0, tokens.theme) }

    var expandAll by remember { mutableStateOf(false) }
    var hideMature by remember { mutableStateOf(false) }
    var showMenu by remember { mutableStateOf(false) }

    ProvidePushedShellChrome(
        hasSubjectHeader = true,
        trailingContent = {
            Box {
                // A glass circle, as iOS's toolbar draws it and as the Inbox's menu does.
                io.github.cidy02.kudos.ui.subject.ToolbarCircleButton(
                    onClick = { showMenu = true },
                    accessibilityName = "More actions",
                    palette = palette
                ) {
                    Icon(imageVector = Icons.Default.MoreVert, contentDescription = null)
                }
                DropdownMenu(
                    expanded = showMenu,
                    onDismissRequest = { showMenu = false }
                ) {
                    DropdownMenuItem(
                        text = { Text(if (hideMature) "Show Mature Content" else "Hide Mature Content") },
                        onClick = {
                            showMenu = false
                            hideMature = !hideMature
                        }
                    )
                    DropdownMenuItem(
                        text = { Text(if (expandAll) "Collapse All" else "Expand All") },
                        onClick = {
                            showMenu = false
                            expandAll = !expandAll
                        }
                    )
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

            when (val current = state) {
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
                        when (type) {
                            AccountListType.MarkedForLater -> {
                                MarkedForLaterBrowser(
                                    works = current.canonicalWorks,
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
                                    works = current.canonicalWorks,
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
                                    works = current.canonicalWorks,
                                    readings = current.page.readingEntries,
                                    currentPage = current.page.currentPage,
                                    totalPages = current.page.totalPages,
                                    expandAll = expandAll,
                                    palette = palette,
                                    onLoadPage = viewModel::load,
                                    onOpenWork = onOpenWork
                                )
                            }
                            AccountListType.Subscriptions -> {
                                SubscriptionsBrowser(
                                    works = current.canonicalWorks,
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
                                    works = current.canonicalWorks,
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
        if (work.local != null) {
            SensitiveWorkRow(
                work = work.local,
                expandAll = expandAll,
                onOpenWork = { onOpenWork(work.remote) }
            )
        } else {
            EnrichingWorkRow(
                work = work.remote,
                expandAll = expandAll,
                onOpenWork = onOpenWork
            )
        }

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
                    if (work.local != null) {
                        SensitiveWorkRow(
                            work = work.local,
                            expandAll = expandAll,
                            onOpenWork = { onOpenWork(work.remote) }
                        )
                    } else {
                        EnrichingWorkRow(
                            work = work.remote,
                            expandAll = expandAll,
                            onOpenWork = onOpenWork
                        )
                    }

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
                    if (work.local != null) {
                        SensitiveWorkRow(
                            work = work.local,
                            expandAll = expandAll,
                            onOpenWork = { onOpenWork(work.remote) }
                        )
                    } else {
                        EnrichingWorkRow(
                            work = work.remote,
                            expandAll = expandAll,
                            onOpenWork = onOpenWork
                        )
                    }

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
private fun SubscriptionsBrowser(
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
        mutableStateOf(SubscriptionWatermarks.load(context, SubscriptionWatermarks.NAMESPACE_SUBSCRIPTIONS))
    }

    LaunchedEffect(works) {
        watermarks = SubscriptionWatermarks.baseline(
            context,
            SubscriptionWatermarks.NAMESPACE_SUBSCRIPTIONS,
            works.map { it.remote }
        )
    }

    var scope by remember { mutableStateOf("works") } // "works", "series", "authors"
    var filter by remember { mutableStateOf("all") }
    var unsubscribedIds by remember { mutableStateOf(setOf<Long>()) }
    var pendingUnsubscribe by remember { mutableStateOf<CanonicalWork?>(null) }

    val activeWorks = remember(works, unsubscribedIds) {
        works.filter { it.remote.id !in unsubscribedIds }
    }

    val updatedWorks = remember(activeWorks, watermarks) {
        activeWorks.filter { SubscriptionWatermarks.newChapterCount(it.remote, watermarks) > 0 }
    }

    val displayedWorks = when (filter) {
        "updated" -> updatedWorks
        else -> activeWorks
    }

    DestructiveConfirmation(
        show = pendingUnsubscribe != null,
        title = "Unsubscribe?",
        text = if (pendingUnsubscribe?.remote?.title.isNullOrBlank()) {
            "This removes the work from your AO3 subscriptions. The work stays on AO3."
        } else {
            "“${pendingUnsubscribe?.remote?.title}” will be removed from your AO3 subscriptions. The work stays on AO3."
        },
        confirmText = "Unsubscribe",
        confirmBeforeDelete = true,
        onConfirm = {
            val pending = pendingUnsubscribe ?: return@DestructiveConfirmation
            pendingUnsubscribe = null
            unsubscribedIds = unsubscribedIds + pending.remote.id
        },
        onDismissRequest = { pendingUnsubscribe = null }
    )

    val subtitle = buildString {
        append(if (displayedWorks.size == 1) "1 work" else "${displayedWorks.size} works")
        if (filter == "all" && updatedWorks.isNotEmpty()) {
            append(" · ${updatedWorks.size} with new chapters")
        }
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
                SubjectChip("Works", style = SubjectChipStyle.Pill(scope == "works"), palette = palette, modifier = Modifier.clickable { scope = "works" })
                SubjectChip("Series", style = SubjectChipStyle.Pill(scope == "series"), palette = palette, modifier = Modifier.clickable { scope = "series" })
                SubjectChip("Authors", style = SubjectChipStyle.Pill(scope == "authors"), palette = palette, modifier = Modifier.clickable { scope = "authors" })
            }
        }

        if (scope == "works") {
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
                        onUnsubscribe = { pendingUnsubscribe = work }
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
                            onUnsubscribe = { pendingUnsubscribe = work }
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
                        onUnsubscribe = { pendingUnsubscribe = work }
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
        } else if (scope == "series") {
            item {
                EmptyStateCard(
                    title = "No series subscriptions",
                    message = "Series you subscribe to on AO3 show up here."
                )
            }
        } else {
            item {
                EmptyStateCard(
                    title = "No author subscriptions",
                    message = "Authors you subscribe to on AO3 show up here."
                )
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
    onUnsubscribe: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        if (work.local != null) {
            SensitiveWorkRow(
                work = work.local,
                expandAll = expandAll,
                onOpenWork = { onOpenWork(work.remote) }
            )
        } else {
            EnrichingWorkRow(
                work = work.remote,
                expandAll = expandAll,
                onOpenWork = onOpenWork
            )
        }

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

            SubjectChip(
                text = "Unsubscribe",
                style = SubjectChipStyle.Neutral,
                leadingIcon = Icons.Outlined.NotificationsOff,
                palette = palette,
                modifier = Modifier.clickable(onClick = onUnsubscribe)
            )
        }
    }
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
            if (work.local != null) {
                SensitiveWorkRow(
                    work = work.local,
                    expandAll = expandAll,
                    onOpenWork = { onOpenWork(work.remote) }
                )
            } else {
                EnrichingWorkRow(
                    work = work.remote,
                    expandAll = expandAll,
                    onOpenWork = onOpenWork
                )
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

/**
 * An AO3 work card that enriches itself when sparse (e.g. Subscriptions).
 */
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
