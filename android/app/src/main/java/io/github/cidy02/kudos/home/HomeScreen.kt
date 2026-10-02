package io.github.cidy02.kudos.home

import io.github.cidy02.kudos.ui.subject.HomeCoverSkeleton
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.cidy02.kudos.account.AccountListRepository
import io.github.cidy02.kudos.app.PrivacyGate
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.library.LibraryDisplayItem
import io.github.cidy02.kudos.library.LibraryPrivacyVisibility
import io.github.cidy02.kudos.library.LibraryRepository
import io.github.cidy02.kudos.library.QueueCardPress
import io.github.cidy02.kudos.library.QueueEditorSheet
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.library.readingProgressFraction
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataRepository
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.ui.components.rememberCollapsedSections
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectRemoteCoverCard
import io.github.cidy02.kudos.ui.subject.SubjectWorkCoverCard
import io.github.cidy02.kudos.ui.subject.rememberWorkDownloading
import io.github.cidy02.kudos.works.CanonicalWorkMerge
import io.github.cidy02.kudos.works.DownloadQueue
import io.github.cidy02.kudos.works.WorkImporter
import io.github.cidy02.kudos.works.WorkRepository
import kotlinx.coroutines.launch

private const val HomeShelfLimit = 12

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    libraryRepository: LibraryRepository,
    workRepository: WorkRepository,
    metadataRepository: AO3WorkMetadataRepository,
    authRepository: AO3AuthRepository,
    accountListRepository: AccountListRepository,
    privacyGate: PrivacyGate = PrivacyGate(),
    queueRepository: ReadingQueueRepository? = null,
    downloadQueue: DownloadQueue? = null,
    workImporter: WorkImporter? = null,
    shellChrome: HomeShellChrome? = null,
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit,
    onOpenRemoteWork: (AO3WorkSummary) -> Unit,
    onOpenSubscriptionsList: () -> Unit,
    onOpenLibrary: () -> Unit,
    onOpenBrowse: () -> Unit,
    onOpenSection: (HomeSectionKind, Boolean, Set<String>) -> Unit,
    onOpenComments: (Long) -> Unit = {},
    onOpenQueue: (String) -> Unit = {},
    onOpenQueues: () -> Unit = {},
    onOpenCollection: (String) -> Unit = {}
) {
    val viewModel: HomeViewModel = viewModel(
        factory = HomeViewModel.factory(
            libraryRepository = libraryRepository,
            workRepository = workRepository,
            metadataRepository = metadataRepository,
            authRepository = authRepository,
            accountListRepository = accountListRepository,
            privacyGate = privacyGate
        )
    )
    val state by viewModel.state.collectAsState()
    val privacyState by privacyGate.state.collectAsState()
    val activity = androidx.compose.ui.platform.LocalContext.current as? androidx.fragment.app.FragmentActivity
    val collapsed = rememberCollapsedSections()
    val scope = rememberCoroutineScope()
    val controller = remember { HomeWorkController() }

    var isSelecting by remember { mutableStateOf(false) }
    var selection by remember { mutableStateOf<Set<String>>(emptySet()) }
    var showNewQueue by remember { mutableStateOf(false) }
    var editingQueue by remember { mutableStateOf<ReadingQueue?>(null) }
    var queues by remember { mutableStateOf<List<Pair<ReadingQueue, List<SavedWork>>>>(emptyList()) }
    var queueReload by remember { mutableIntStateOf(0) }

    val displayById = remember(state.visibleItems) {
        state.visibleItems.associateBy { it.item.work.id }
    }
    val visibleWorks = remember(state.visibleItems) { state.visibleItems.map { it.item.work } }
    val readingNow = remember(visibleWorks) { HomeSectionKind.ReadingNow.works(visibleWorks) { true } }
    val recentlyUpdated = remember(visibleWorks) { HomeSectionKind.RecentlyUpdated.works(visibleWorks) { true } }
    val selectable = remember(readingNow, recentlyUpdated) { (readingNow + recentlyUpdated).distinctBy { it.id } }
    val selectedWorks = selectable.filter { it.id in selection }
    val allSelected = selectable.isNotEmpty() && selectable.all { it.id in selection }
    val hideMature = state.hideMatureContent

    suspend fun reloadQueues() {
        val repo = queueRepository ?: return
        val loaded = runCatching {
            repo.listQueues()
                .filter { it.kindRaw == ReadingQueueKind.CUSTOM && !it.isDeleted }
                .sortedBy { it.sortOrder }
                .take(HomeShelfLimit)
                .map { queue -> queue to repo.listWorks(queue.id).mapNotNull { it.work } }
        }
        if (loaded.isSuccess) queues = loaded.getOrThrow()
    }

    LaunchedEffect(queueRepository, queueReload, state.totalSaved) { reloadQueues() }

    if (shellChrome != null) {
        SideEffect {
            shellChrome.mounted = true
            shellChrome.hideTabBar = isSelecting
            shellChrome.selectionTitle = if (isSelecting) HomeSelectionTitle.text(selection.size) else null
            shellChrome.allSelected = allSelected
            shellChrome.showOverflow = selectable.isNotEmpty() || hideMature
            shellChrome.showPrivacy = hideMature
            shellChrome.revealAll = privacyState.revealAll
            shellChrome.showSelect = selectable.isNotEmpty()
            shellChrome.actions.onNewQueue = { showNewQueue = true }
            shellChrome.actions.onSelectAll = {
                selection = if (allSelected) emptySet() else selectable.map { it.id }.toSet()
            }
            shellChrome.actions.onEnterSelect = { isSelecting = true }
            shellChrome.actions.onTogglePrivacy = { privacyGate.toggleRevealAll(activity) }
            controller.onChanged = { reloadQueues() }
        }
        DisposableEffect(shellChrome) {
            onDispose { shellChrome.reset() }
        }
    }

    fun openLocal(work: SavedWork) {
        if (work.hasEpub) {
            viewModel.onOpenLocalWork(work.id)
            onOpenReader(work.id)
        } else {
            onOpenWork(work.id)
        }
    }

    val queueRepo = queueRepository
    if (queueRepo != null && (showNewQueue || editingQueue != null)) {
        QueueEditorSheet(
            repository = queueRepo,
            existing = editingQueue,
            onDismiss = {
                showNewQueue = false
                editingQueue = null
            },
            onSaved = {
                showNewQueue = false
                editingQueue = null
                queueReload += 1
            }
        )
    }

    HomeWorkDialogs(
        controller = controller,
        workRepository = workRepository,
        queueRepository = queueRepository,
        confirmBeforeDelete = state.confirmBeforeDelete,
        onDeleted = {
            isSelecting = false
            selection = emptySet()
        }
    )

    KudosRefreshBox(
        onRefresh = {
            viewModel.refreshNow()
            reloadQueues()
        },
        modifier = Modifier.fillMaxSize()
    ) {
        if (state.loading && state.visibleItems.isEmpty()) {
            Text(
                text = "Loading your library…",
                color = LocalKudosTokens.current.secondaryInk,
                fontSize = 15.sp,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 24.dp)
            )
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(
                    top = 12.dp,
                    bottom = 12.dp + if (isSelecting) 72.dp else 0.dp
                ),
                verticalArrangement = Arrangement.spacedBy(22.dp)
            ) {
                item {
                    ContinueReadingBlock(
                        works = readingNow,
                        displayById = displayById,
                        stripCollapsed = collapsed["home.readingNow.strip"],
                        onToggleStrip = { collapsed.toggle("home.readingNow.strip") },
                        isSelecting = isSelecting,
                        selection = selection,
                        downloadQueue = downloadQueue,
                        controller = controller,
                        workRepository = workRepository,
                        queueRepository = queueRepository,
                        workImporter = workImporter,
                        onOpen = ::openLocal,
                        onDetails = { onOpenWork(it.id) },
                        onComments = onOpenComments,
                        onReveal = { viewModel.revealWork(it.id, activity) },
                        onToggleSelected = { work ->
                            selection = if (work.id in selection) selection - work.id else selection + work.id
                        },
                        onEnterSelect = { work ->
                            selection = selection + work.id
                            isSelecting = true
                        },
                        onSeeAll = {
                            onOpenSection(HomeSectionKind.ReadingNow, isSelecting, selection)
                        },
                        onOpenBrowse = onOpenBrowse,
                        onOpenLibrary = onOpenLibrary
                    )
                }
                item {
                    HomeCarouselSection(
                        title = "Reading Queues",
                        items = queues,
                        collapsed = collapsed["home.readingQueues"],
                        onToggleCollapse = if (queues.isEmpty()) null else ({ collapsed.toggle("home.readingQueues") }),
                        onSeeAll = if (queues.isEmpty()) null else onOpenQueues,
                        emptyIcon = HomeEmptyIcons.queues,
                        emptyMessage = "Use + above to make a reading queue and plan what you want to read next."
                    ) { (queue, works) ->
                        if (queueRepo == null) {
                            HomePress(onClick = { onOpenQueue(queue.id) }) {
                                HomeQueueCard(queue = queue, works = works)
                            }
                        } else {
                            QueueCardPress(
                                queue = queue,
                                enabled = true,
                                onClick = { onOpenQueue(queue.id) },
                                onEdit = { editingQueue = queue },
                                onPin = {
                                    scope.launch {
                                        queueRepo.setQueuesPinned(listOf(queue.id), !queue.isPinned)
                                        queueReload += 1
                                    }
                                },
                                onDelete = {
                                    scope.launch {
                                        queueRepo.deleteQueue(queue.id)
                                        queueReload += 1
                                    }
                                }
                            ) {
                                HomeQueueCard(queue = queue, works = works)
                            }
                        }
                    }
                }
                items(state.homeCollections, key = { it.id }) { shelf ->
                    HomeCarouselSection(
                        title = shelf.name,
                        items = shelf.works.take(HomeShelfLimit),
                        count = if (shelf.works.isEmpty()) null else shelf.works.size,
                        collapsed = collapsed["home.collection.${shelf.id}"],
                        onToggleCollapse = { collapsed.toggle("home.collection.${shelf.id}") },
                        onSeeAll = if (shelf.works.isEmpty()) null else ({ onOpenCollection(shelf.id) }),
                        emptyIcon = HomeEmptyIcons.collections,
                        emptyMessage = "Add works to this collection to see them here."
                    ) { item ->
                        LocalCard(
                            item = item,
                            allowSelect = false,
                            footer = null,
                            progress = item.item.work.readingProgressFraction(),
                            isSelecting = isSelecting,
                            isSelected = item.item.work.id in selection,
                            downloadQueue = downloadQueue,
                            controller = controller,
                            workRepository = workRepository,
                            queueRepository = queueRepository,
                            workImporter = workImporter,
                            onOpen = ::openLocal,
                            onDetails = { onOpenWork(it.id) },
                            onComments = onOpenComments,
                            onReveal = { viewModel.revealWork(it.id, activity) },
                            onToggleSelected = {},
                            onEnterSelect = {}
                        )
                    }
                }
                item {
                    HomeCarouselSection(
                        title = HomeSectionKind.RecentlyUpdated.title,
                        items = recentlyUpdated.take(HomeShelfLimit),
                        count = if (recentlyUpdated.isEmpty()) null else recentlyUpdated.size,
                        collapsed = collapsed["home.recentlyUpdated"],
                        onToggleCollapse = { collapsed.toggle("home.recentlyUpdated") },
                        onSeeAll = if (recentlyUpdated.size > 1) {
                            {
                                onOpenSection(HomeSectionKind.RecentlyUpdated, isSelecting, selection)
                            }
                        } else {
                            null
                        },
                        emptyIcon = HomeEmptyIcons.updated,
                        emptyMessage = HomeSectionKind.RecentlyUpdated.emptyMessage
                    ) { work ->
                        val item = displayById[work.id]
                        if (item != null) {
                            LocalCard(
                                item = item,
                                allowSelect = true,
                                footer = HomeFacts.updateFooter(work),
                                progress = null,
                                isSelecting = isSelecting,
                                isSelected = work.id in selection,
                                downloadQueue = downloadQueue,
                                controller = controller,
                                workRepository = workRepository,
                                queueRepository = queueRepository,
                                workImporter = workImporter,
                                onOpen = ::openLocal,
                                onDetails = { onOpenWork(it.id) },
                                onComments = onOpenComments,
                                onReveal = { viewModel.revealWork(it.id, activity) },
                                onToggleSelected = { picked ->
                                    selection = if (picked.id in selection) selection - picked.id else selection + picked.id
                                },
                                onEnterSelect = { picked ->
                                    selection = selection + picked.id
                                    isSelecting = true
                                }
                            )
                        }
                    }
                }
                item {
                    SubscriptionsBlock(
                        state = state,
                        displayById = displayById,
                        collapsed = collapsed["home.subscriptions"],
                        onToggle = { collapsed.toggle("home.subscriptions") },
                        isSelecting = isSelecting,
                        selection = selection,
                        downloadQueue = downloadQueue,
                        controller = controller,
                        workRepository = workRepository,
                        queueRepository = queueRepository,
                        workImporter = workImporter,
                        onOpen = ::openLocal,
                        onDetails = { onOpenWork(it.id) },
                        onComments = onOpenComments,
                        onReveal = { viewModel.revealWork(it.id, activity) },
                        onOpenRemote = onOpenRemoteWork,
                        onSeeAll = onOpenSubscriptionsList
                    )
                }
            }
        }
        if (isSelecting) {
            HomeBulkBar(
                selectedWorks = selectedWorks,
                controller = controller,
                workRepository = workRepository,
                queueRepository = queueRepository,
                downloadQueue = downloadQueue,
                onDone = {
                    isSelecting = false
                    selection = emptySet()
                },
                modifier = Modifier.align(androidx.compose.ui.Alignment.BottomCenter)
            )
        }
    }
}

@Composable
private fun ContinueReadingBlock(
    works: List<SavedWork>,
    displayById: Map<String, LibraryDisplayItem>,
    stripCollapsed: Boolean,
    onToggleStrip: () -> Unit,
    isSelecting: Boolean,
    selection: Set<String>,
    downloadQueue: DownloadQueue?,
    controller: HomeWorkController,
    workRepository: WorkRepository,
    queueRepository: ReadingQueueRepository?,
    workImporter: WorkImporter?,
    onOpen: (SavedWork) -> Unit,
    onDetails: (SavedWork) -> Unit,
    onComments: (Long) -> Unit,
    onReveal: (SavedWork) -> Unit,
    onToggleSelected: (SavedWork) -> Unit,
    onEnterSelect: (SavedWork) -> Unit,
    onSeeAll: () -> Unit,
    onOpenBrowse: () -> Unit,
    onOpenLibrary: () -> Unit
) {
    val hero = works.firstOrNull()
    val strip = works.drop(1).take(4)
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(11.dp)) {
        SectionRuleHeader(
            title = "Continue Reading",
            count = if (works.isEmpty()) null else works.size,
            isCollapsed = stripCollapsed,
            onToggleCollapse = if (strip.isEmpty()) null else onToggleStrip,
            onSeeAll = if (works.size > 5) onSeeAll else null
        )
        if (hero == null) {
            HomeSectionEmpty(
                message = HomeSectionKind.ReadingNow.emptyMessage,
                icon = HomeEmptyIcons.reading
            )
            ContinueReadingActions(onOpenBrowse = onOpenBrowse, onOpenLibrary = onOpenLibrary)
        } else {
            val heroItem = displayById[hero.id]
            LocalFrame(
                work = hero,
                obscured = heroItem?.privacyVisibility == LibraryPrivacyVisibility.Obscured,
                allowSelect = true,
                isSelecting = isSelecting,
                controller = controller,
                workRepository = workRepository,
                queueRepository = queueRepository,
                downloadQueue = downloadQueue,
                workImporter = workImporter,
                onOpen = onOpen,
                onDetails = onDetails,
                onComments = onComments,
                onReveal = onReveal,
                onToggleSelected = onToggleSelected,
                onEnterSelect = onEnterSelect
            ) {
                HomeResumeHero(
                    work = hero,
                    downloading = rememberWorkDownloading(hero, downloadQueue),
                    obscured = heroItem?.privacyVisibility == LibraryPrivacyVisibility.Obscured,
                    isSelecting = isSelecting,
                    isSelected = hero.id in selection
                )
            }
            if (strip.isNotEmpty() && !stripCollapsed) {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState())
                        .padding(horizontal = 16.dp)
                        .padding(bottom = 6.dp)
                        .offset(y = (-8).dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    strip.forEach { work ->
                        val item = displayById[work.id] ?: return@forEach
                        LocalCard(
                            item = item,
                            allowSelect = true,
                            footer = null,
                            progress = work.readingProgressFraction(),
                            isSelecting = isSelecting,
                            isSelected = work.id in selection,
                            downloadQueue = downloadQueue,
                            controller = controller,
                            workRepository = workRepository,
                            queueRepository = queueRepository,
                            workImporter = workImporter,
                            onOpen = onOpen,
                            onDetails = onDetails,
                            onComments = onComments,
                            onReveal = onReveal,
                            onToggleSelected = onToggleSelected,
                            onEnterSelect = onEnterSelect
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun SubscriptionsBlock(
    state: HomeUiState,
    displayById: Map<String, LibraryDisplayItem>,
    collapsed: Boolean,
    onToggle: () -> Unit,
    isSelecting: Boolean,
    selection: Set<String>,
    downloadQueue: DownloadQueue?,
    controller: HomeWorkController,
    workRepository: WorkRepository,
    queueRepository: ReadingQueueRepository?,
    workImporter: WorkImporter?,
    onOpen: (SavedWork) -> Unit,
    onDetails: (SavedWork) -> Unit,
    onComments: (Long) -> Unit,
    onReveal: (SavedWork) -> Unit,
    onOpenRemote: (AO3WorkSummary) -> Unit,
    onSeeAll: () -> Unit
) {
    val showSkeleton = state.isSignedIn && state.subscriptionsLoading && state.subscriptions.isEmpty()
    val merged = remember(state.subscriptions, state.visibleItems) {
        CanonicalWorkMerge.remoteLed(
            remote = state.subscriptions,
            localLibrary = state.visibleItems.map { it.item.work }
        )
    }
    val count = when {
        showSkeleton || merged.isEmpty() || state.subscriptionsExactCount == null -> null
        else -> merged.size
    }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(5.dp)) {
        SectionRuleHeader(
            title = "Subscriptions",
            count = count,
            isCollapsed = collapsed,
            onToggleCollapse = onToggle,
            onSeeAll = if (merged.isEmpty()) null else onSeeAll
        )
        if (!collapsed) {
            when {
                showSkeleton -> Row(
                    Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState())
                        .padding(horizontal = 16.dp, vertical = 6.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    repeat(6) { HomeCoverSkeleton() }
                }
                merged.isEmpty() -> HomeSectionEmpty(
                    message = HomeSubscriptionsCopy.emptyMessage(state.isSignedIn, state.subscriptionsLoadFailed),
                    icon = HomeEmptyIcons.subscriptions
                )
                else -> Row(
                    Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState())
                        .padding(horizontal = 16.dp, vertical = 6.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    merged.take(HomeShelfLimit).forEach { entry ->
                        val local = entry.local
                        if (local != null) {
                            val item = displayById[local.id]
                            if (item != null) {
                                LocalCard(
                                    item = item,
                                    allowSelect = false,
                                    footer = null,
                                    progress = local.readingProgressFraction(),
                                    isSelecting = isSelecting,
                                    isSelected = local.id in selection,
                                    downloadQueue = downloadQueue,
                                    controller = controller,
                                    workRepository = workRepository,
                                    queueRepository = queueRepository,
                                    workImporter = workImporter,
                                    onOpen = onOpen,
                                    onDetails = onDetails,
                                    onComments = onComments,
                                    onReveal = onReveal,
                                    onToggleSelected = {},
                                    onEnterSelect = {}
                                )
                            }
                        } else {
                            HomePress(onClick = { onOpenRemote(entry.remote) }) {
                                SubjectRemoteCoverCard(summary = entry.remote, showsProvenance = true)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LocalCard(
    item: LibraryDisplayItem,
    allowSelect: Boolean,
    footer: String?,
    progress: Double?,
    isSelecting: Boolean,
    isSelected: Boolean,
    downloadQueue: DownloadQueue?,
    controller: HomeWorkController,
    workRepository: WorkRepository,
    queueRepository: ReadingQueueRepository?,
    workImporter: WorkImporter?,
    onOpen: (SavedWork) -> Unit,
    onDetails: (SavedWork) -> Unit,
    onComments: (Long) -> Unit,
    onReveal: (SavedWork) -> Unit,
    onToggleSelected: (SavedWork) -> Unit,
    onEnterSelect: (SavedWork) -> Unit
) {
    val work = item.item.work
    val obscured = item.privacyVisibility == LibraryPrivacyVisibility.Obscured
    LocalFrame(
        work = work,
        obscured = obscured,
        allowSelect = allowSelect,
        isSelecting = isSelecting,
        controller = controller,
        workRepository = workRepository,
        queueRepository = queueRepository,
        downloadQueue = downloadQueue,
        workImporter = workImporter,
        onOpen = onOpen,
        onDetails = onDetails,
        onComments = onComments,
        onReveal = onReveal,
        onToggleSelected = onToggleSelected,
        onEnterSelect = onEnterSelect
    ) {
        SubjectWorkCoverCard(
            work = work,
            obscured = obscured,
            downloading = rememberWorkDownloading(work, downloadQueue),
            footer = footer,
            progress = progress,
            isSelecting = isSelecting,
            isSelected = isSelected
        )
    }
}

@Composable
private fun LocalFrame(
    work: SavedWork,
    obscured: Boolean,
    allowSelect: Boolean,
    isSelecting: Boolean,
    controller: HomeWorkController,
    workRepository: WorkRepository,
    queueRepository: ReadingQueueRepository?,
    downloadQueue: DownloadQueue?,
    workImporter: WorkImporter?,
    onOpen: (SavedWork) -> Unit,
    onDetails: (SavedWork) -> Unit,
    onComments: (Long) -> Unit,
    onReveal: (SavedWork) -> Unit,
    onToggleSelected: (SavedWork) -> Unit,
    onEnterSelect: (SavedWork) -> Unit,
    content: @Composable () -> Unit
) {
    HomeLocalWorkFrame(
        work = work,
        obscured = obscured,
        allowSelect = allowSelect,
        isSelecting = isSelecting,
        controller = controller,
        workRepository = workRepository,
        queueRepository = queueRepository,
        downloadQueue = downloadQueue,
        workImporter = workImporter,
        onOpen = onOpen,
        onDetails = onDetails,
        onComments = onComments,
        onReveal = onReveal,
        onToggleSelected = onToggleSelected,
        onEnterSelect = onEnterSelect,
        content = content
    )
}

@Composable
private fun HomePress(onClick: () -> Unit, content: @Composable () -> Unit) {
    Box(Modifier.clickable(onClick = onClick)) { content() }
}