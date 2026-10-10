package io.github.cidy02.kudos.app

import android.content.Intent
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
import androidx.compose.material.icons.outlined.OpenInBrowser
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.UnfoldLess
import androidx.compose.material.icons.outlined.UnfoldMore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.displayMessage
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.series.AO3SeriesRepository
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.KudosPaginationBar
import io.github.cidy02.kudos.ui.components.KudosSectionHeader
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.components.RemoteWorkBulkActions
import io.github.cidy02.kudos.ui.components.RemoteWorkSelectionBar
import io.github.cidy02.kudos.ui.components.SelectableRemoteWorkRow
import io.github.cidy02.kudos.ui.components.SensitiveWorkRow
import io.github.cidy02.kudos.ui.components.rememberRemoteWorkSelection
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.ToolbarCircleButton
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import io.github.cidy02.kudos.works.WorkImporter
import kotlinx.coroutines.launch

/** Native listing of works in an AO3 series (`/series/<id>`). */
@Composable
fun SeriesWorksScreen(
    seriesUrl: String,
    seriesRepository: AO3SeriesRepository,
    onOpenWork: (AO3WorkSummary) -> Unit,
    workImporter: WorkImporter? = null,
    readingQueueRepository: ReadingQueueRepository? = null,
    onOpenAo3: (String) -> Unit = {},
    formRepository: io.github.cidy02.kudos.network.ao3.writing.AO3SeriesFormRepository? = null,
    writes: io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository? = null
) {
    val sessionGeneration by seriesRepository.sessionChanges.collectAsState()
    var editing by remember(seriesUrl) { mutableStateOf<Boolean?>(null) }
    val accountState by (formRepository?.auth?.state?.collectAsState() ?: remember {
        mutableStateOf<io.github.cidy02.kudos.auth.AO3AuthState>(io.github.cidy02.kudos.auth.AO3AuthState.SignedOut) })
    var state by remember(seriesUrl, sessionGeneration) { mutableStateOf<SeriesWorksState>(SeriesWorksState.Loading) }
    var loadGeneration by remember(seriesUrl) { mutableIntStateOf(0) }
    var expandAll by remember(seriesUrl) { mutableStateOf(false) }
    var showMenu by remember(seriesUrl) { mutableStateOf(false) }
    val selection = rememberRemoteWorkSelection()
    var bulkBusy by remember { mutableStateOf(false) }
    var bulkStatus by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    fun load(page: Int = 1, bypassCache: Boolean = false): kotlinx.coroutines.Job {
        state = SeriesWorksState.Loading
        val generation = ++loadGeneration
        return scope.launch {
            val next = when (val result = seriesRepository.detailPage(seriesUrl, page, bypassCache)) {
                is AO3Result.Success -> SeriesWorksState.Loaded(result.value, result.isStale)
                is AO3Result.Failure -> SeriesWorksState.Error(result.error.displayMessage(), page)
            }
            if (generation == loadGeneration) state = next
        }
    }

    LaunchedEffect(seriesUrl, sessionGeneration) { editing = null; selection.exit(); load() }

    val page = (state as? SeriesWorksState.Loaded)?.page
    val detail = (state as? SeriesWorksState.Loaded)?.detail
    val title = detail?.title ?: "Series"
    val username = (accountState as? io.github.cidy02.kudos.auth.AO3AuthState.SignedIn)?.username
    val canEdit = username != null && detail?.creatorUsernames?.any { it.equals(username, true) } == true
    val seriesID = Regex("/series/([0-9]+)").find(seriesUrl)?.groupValues?.get(1)?.toLongOrNull()
    val editMode = editing
    if (editMode != null && seriesID != null && formRepository != null && writes != null) {
        io.github.cidy02.kudos.writing.WritingSeriesScreen(seriesID, title, formRepository, writes,
            onBack = { editing = null }, onOpenAo3 = onOpenAo3, reorderOnly = editMode, works = page?.works.orEmpty(),
            subtitle = listOfNotNull(title, detail?.workCount?.let { "$it ${if (it == 1) "work" else "works"}" },
                detail?.words?.takeIf { it > 0 }?.let { "%,d words".format(it) }).joinToString(" · "))
        return
    }
    val tokens = LocalKudosTokens.current
    val palette = remember(title, tokens.theme) {
        SubjectPalette.fromHue(HomeFacts.workHue(page?.works?.firstOrNull()?.fandoms.orEmpty(), title), tokens.theme)
    }

    ProvidePushedShellChrome(
        hasSubjectHeader = true,
        trailingContent = {
            Box {
                ToolbarCircleButton(
                    onClick = { showMenu = true },
                    accessibilityName = "More actions",
                    palette = palette
                ) {
                    Icon(Icons.Default.MoreVert, contentDescription = null)
                }
                DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                    if (!page?.works.isNullOrEmpty() && workImporter != null) {
                        DropdownMenuItem(
                            text = { Text(if (selection.isSelecting) "Exit selection" else "Select") },
                            leadingIcon = { Icon(Icons.Outlined.Checklist, contentDescription = null) },
                            onClick = {
                                showMenu = false
                                if (selection.isSelecting) selection.exit() else selection.enter()
                            }
                        )
                    }
                    if (!page?.works.isNullOrEmpty()) {
                        DropdownMenuItem(
                            text = { Text(if (expandAll) "Collapse All" else "Expand All") },
                            leadingIcon = {
                                Icon(
                                    if (expandAll) Icons.Outlined.UnfoldLess else Icons.Outlined.UnfoldMore,
                                    contentDescription = null
                                )
                            },
                            onClick = {
                                showMenu = false
                                expandAll = !expandAll
                            }
                        )
                    }
                    if (canEdit && formRepository != null && writes != null) {
                        DropdownMenuItem(text = { Text("Edit series", color = tokens.primaryInk, lineHeight = 21.sp) }, onClick = { showMenu = false; editing = false })
                        // iOS offers Reorder only when more than one work is loaded.
                        if ((page?.works?.size ?: 0) > 1) DropdownMenuItem(text = { Text("Reorder", color = tokens.primaryInk, lineHeight = 21.sp) }, onClick = { showMenu = false; editing = true })
                    }
                    DropdownMenuItem(
                        text = { Text("Open on AO3") },
                        leadingIcon = { Icon(Icons.Outlined.OpenInBrowser, contentDescription = null) },
                        onClick = {
                            showMenu = false
                            onOpenAo3(seriesUrl)
                        }
                    )
                    DropdownMenuItem(
                        text = { Text("Share Series") },
                        leadingIcon = { Icon(Icons.Outlined.Share, contentDescription = null) },
                        onClick = {
                            showMenu = false
                            val intent = Intent(Intent.ACTION_SEND)
                                .setType("text/plain")
                                .putExtra(Intent.EXTRA_TEXT, seriesUrl)
                            context.startActivity(Intent.createChooser(intent, null))
                        }
                    )
                }
            }
        }
    )

    io.github.cidy02.kudos.ui.components.KudosRefreshBox(onRefresh = {
        val job = load(1, bypassCache = true)
        try { job.join() } finally { if (job.isActive) job.cancel() }
    }) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .subjectScreenWash(palette)
    ) {
        Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
        Spacer(Modifier.height(56.dp))
        SubjectHeaderBlock(kicker = "Series", title = title, palette = palette)

        when (val current = state) {
            SeriesWorksState.Loading -> LoadingStateCard(
                "Loading series…",
                Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
            )
            is SeriesWorksState.Error -> ErrorStateCard(
                title = "Couldn't load series",
                message = current.message,
                primaryActionLabel = "Try Again",
                onPrimaryAction = { load(current.page, bypassCache = true) },
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
            )
            is SeriesWorksState.Loaded -> {
                if (current.isStale) io.github.cidy02.kudos.ui.components.CachedAO3DataRow(
                    Modifier.padding(horizontal = 16.dp, vertical = 12.dp))
                if (current.page.works.isEmpty()) {
                    EmptyStateCard(
                        title = "No visible works",
                        message = "No works in this series are visible to you on AO3.",
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
                    )
                } else {
                    LazyColumn(
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
                        modifier = Modifier
                            .fillMaxWidth()
                            .weight(1f, fill = false)
                    ) {
                        item {
                            KudosSectionHeader(
                                title = "Works",
                                subtitle = "Page ${current.page.currentPage} of ${current.page.totalPages}"
                            )
                            KudosPaginationBar(
                                currentPage = current.page.currentPage,
                                totalPages = current.page.totalPages,
                                onPageChange = { load(it) }
                            )
                        }
                        items(current.page.works, key = { it.id }) { work ->
                            if (selection.isSelecting) {
                                SelectableRemoteWorkRow(
                                    work = work,
                                    selected = selection.isSelected(work.id),
                                    onToggle = { selection.toggle(work.id) }
                                )
                            } else {
                                SensitiveWorkRow(
                                    work = work,
                                    onOpenWork = onOpenWork,
                                    expandAll = expandAll
                                )
                            }
                        }
                        item {
                            KudosPaginationBar(
                                currentPage = current.page.currentPage,
                                totalPages = current.page.totalPages,
                                onPageChange = { load(it) }
                            )
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
                    val picked = selection.selectedIn(page?.works.orEmpty())
                    scope.launch {
                        bulkBusy = true
                        bulkStatus = RemoteWorkBulkActions.saveToLibrary(picked, workImporter)
                        bulkBusy = false
                        selection.exit()
                    }
                },
                onSaveForLater = {
                    val queues = readingQueueRepository ?: return@RemoteWorkSelectionBar
                    val picked = selection.selectedIn(page?.works.orEmpty())
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

    }

    bulkStatus?.let { message ->
        AlertDialog(
            onDismissRequest = { bulkStatus = null },
            title = { Text("Selection") },
            text = { Text(message) },
            confirmButton = {
                TextButton(onClick = { bulkStatus = null }) { Text("OK") }
            }
        )
    }
}

private sealed interface SeriesWorksState {
    data object Loading : SeriesWorksState
    data class Loaded(val detail: io.github.cidy02.kudos.network.ao3.series.AO3SeriesDetailPage, val isStale: Boolean = false) : SeriesWorksState {
        val page get() = detail.page
    }
    data class Error(val message: String, val page: Int) : SeriesWorksState
}
