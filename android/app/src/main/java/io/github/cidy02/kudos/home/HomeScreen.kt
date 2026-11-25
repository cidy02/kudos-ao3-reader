package io.github.cidy02.kudos.home

import io.github.cidy02.kudos.ui.subject.HomeCoverSkeleton
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.cidy02.kudos.account.AccountListRepository
import io.github.cidy02.kudos.account.SubscriptionWatermarks
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
import io.github.cidy02.kudos.ui.components.ChapterBarLayout
import io.github.cidy02.kudos.ui.components.ChapterBarModel
import io.github.cidy02.kudos.ui.components.ChapterBarScale
import io.github.cidy02.kudos.ui.components.ChapterBars
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.ui.components.hiddenMatureWorkSemantics
import io.github.cidy02.kudos.ui.components.keptForPrivacy
import io.github.cidy02.kudos.ui.components.rememberCollapsedSections
import io.github.cidy02.kudos.ui.subject.HomeStatusArrangement
import io.github.cidy02.kudos.ui.subject.HomeStatusTray
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.RevealCapsule
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectWorkCoverCard
import io.github.cidy02.kudos.ui.subject.downloadDimmed
import io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale
import io.github.cidy02.kudos.ui.subject.rememberWorkDownloadFraction
import io.github.cidy02.kudos.works.CanonicalWorkMerge
import io.github.cidy02.kudos.works.DownloadQueue
import io.github.cidy02.kudos.works.WorkImporter
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.works.rememberChapterLengths
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
    authorRepository: io.github.cidy02.kudos.network.ao3.author.AO3AuthorRepository? = null,
    inboxRepository: io.github.cidy02.kudos.network.ao3.inbox.AO3InboxRepository? = null,
    shellChrome: HomeShellChrome? = null,
    onOpenAccount: () -> Unit = {},
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
    val authState by authRepository.state.collectAsState()
    val signedInUsername = (authState as? io.github.cidy02.kudos.auth.AO3AuthState.SignedIn)?.username
    val pageCacheChanges by io.github.cidy02.kudos.network.ao3.AO3PageCache.shared.changes.collectAsState()
    val cachedAvatarUrl = remember(signedInUsername, pageCacheChanges, authorRepository) {
        signedInUsername?.let {
            authorRepository?.cachedDashboardAvatarUrl(
                io.github.cidy02.kudos.network.ao3.author.AO3AuthorRoute(it)
            )
        }
    }
    val cachedUnreadCount = remember(signedInUsername, pageCacheChanges, inboxRepository) {
        if (signedInUsername != null) inboxRepository?.cachedUnreadCount() else null
    }
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

    // A queue's works are not among the Library's display items: judged here, by the same rule.
    fun queueFace(works: List<SavedWork>) = HomeFacts.queueFace(works) {
        io.github.cidy02.kudos.library.LibraryPrivacy.visibility(it, state.privacy, privacyState)
    }

    fun queueBacks(works: List<SavedWork>): List<SavedWork> {
        val visible = works.filter {
            io.github.cidy02.kudos.library.LibraryPrivacy.visibility(it, state.privacy, privacyState) ==
                io.github.cidy02.kudos.library.LibraryPrivacyVisibility.Visible
        }
        val (upNext, inLine) = io.github.cidy02.kudos.library.ReadingQueueFacts.upNext(visible)
        return (listOfNotNull(upNext) + inLine)
            .take(io.github.cidy02.kudos.ui.components.CoverStackLayout.maxBacks)
    }

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
            shellChrome.bindAccount(signedInUsername, cachedAvatarUrl, cachedUnreadCount, onOpenAccount)
            shellChrome.washHue = readingNow.firstOrNull()?.let { HomeFacts.workHue(it.workFandoms, it.title) }
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
            },
            privacy = state.privacy,
            reveal = privacyState,
            onToggleMature = { privacyGate.toggleRevealAll(activity) }
        )
    }

    HomeWorkDialogs(
        controller = controller,
        workRepository = workRepository,
        queueRepository = queueRepository,
        confirmBeforeDelete = state.confirmBeforeDelete,
        workImporter = workImporter,
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
                                HomeQueueCard(
                                    queue = queue,
                                    works = works,
                                    face = queueFace(works),
                                    backs = queueBacks(works)
                                )
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
                                HomeQueueCard(
                                    queue = queue,
                                    works = works,
                                    face = queueFace(works),
                                    backs = queueBacks(works)
                                )
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
                    downloadFraction = rememberWorkDownloadFraction(hero, downloadQueue),
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
    // Hide drops a known-adult remote rating. A blank rating stays and the cover blurs.
    val rowEnv = io.github.cidy02.kudos.ui.components.LocalWorkRowEnvironment.current
    val shown = merged.filter { it.remote.keptForPrivacy(rowEnv) }
    val count = when {
        showSkeleton || shown.isEmpty() || state.subscriptionsExactCount == null -> null
        else -> shown.size
    }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(5.dp)) {
        SectionRuleHeader(
            title = "Subscriptions",
            count = count,
            isCollapsed = collapsed,
            onToggleCollapse = onToggle,
            onSeeAll = if (shown.isEmpty()) null else onSeeAll
        )
        if (!collapsed) {
            when {
                showSkeleton -> io.github.cidy02.kudos.ui.subject.SubjectSkeletonLoading("Loading Subscriptions") {
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .horizontalScroll(rememberScrollState())
                            .padding(horizontal = 16.dp, vertical = 6.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        repeat(6) { HomeCoverSkeleton() }
                    }
                }
                shown.isEmpty() -> HomeSectionEmpty(
                    message = HomeSubscriptionsCopy.emptyMessage(state.isSignedIn, state.subscriptionsLoadFailed),
                    icon = HomeEmptyIcons.subscriptions
                )
                else -> {
                    val context = androidx.compose.ui.platform.LocalContext.current
                    val watermarks = remember(context, shown) {
                        SubscriptionWatermarks.load(context, SubscriptionWatermarks.NAMESPACE_SUBSCRIPTIONS)
                    }
                    val visibleRows = shown.take(HomeShelfLimit)
                    Column(Modifier.fillMaxWidth()) {
                        visibleRows.forEachIndexed { index, entry ->
                            if (index > 0) {
                                androidx.compose.material3.HorizontalDivider(
                                    color = LocalKudosTokens.current.separator,
                                    modifier = Modifier.padding(start = 79.dp)
                                )
                            }
                            val local = entry.local
                            if (local != null) {
                                val obscured = displayById[local.id]?.privacyVisibility == LibraryPrivacyVisibility.Obscured
                                val chapterLengths = rememberChapterLengths(local)
                                val newCount = if (local.hasUpdate) {
                                    maxOf(0, local.postedChapterCount - (local.knownChapterCount ?: local.postedChapterCount))
                                } else 0
                                val layout = ChapterBarModel.layout(
                                    chapters = local.chapters,
                                    progress = local.readingProgressFraction(),
                                    isFinished = local.isFinished,
                                    weights = chapterLengths?.positions,
                                    heights = chapterLengths?.words,
                                    newChapterCount = newCount,
                                    scale = ChapterBarScale.Row
                                )
                                val downloadFraction = rememberWorkDownloadFraction(local, downloadQueue)
                                LocalFrame(
                                    work = local,
                                    obscured = obscured,
                                    allowSelect = false,
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
                                    onToggleSelected = {},
                                    onEnterSelect = {}
                                ) {
                                    HomeSubscriptionRow(
                                        title = local.title,
                                        author = local.author,
                                        fandoms = local.workFandoms,
                                        dateUpdated = local.dateUpdated,
                                        rating = local.rating,
                                        categories = local.workCategories,
                                        warnings = local.workWarnings,
                                        isComplete = local.knownCompletion,
                                        layout = layout,
                                        obscured = obscured,
                                        downloadFraction = downloadFraction
                                    )
                                }
                            } else {
                                val environment = io.github.cidy02.kudos.ui.components.LocalWorkRowEnvironment.current
                                val newCount = SubscriptionWatermarks.newChapterCount(entry.remote, watermarks)
                                if (environment != null) {
                                    io.github.cidy02.kudos.ui.components.RemoteWorkActionFrame(entry.remote, environment, onOpenRemote) {
                                        matched, obscured, click, longClick ->
                                        val chapterLengths = rememberChapterLengths(matched)
                                        val rowLayout = if (matched != null) {
                                            val localNew = if (matched.hasUpdate) {
                                                maxOf(0, matched.postedChapterCount - (matched.knownChapterCount ?: matched.postedChapterCount))
                                            } else 0
                                            ChapterBarModel.layout(
                                                chapters = matched.chapters,
                                                progress = matched.readingProgressFraction(),
                                                isFinished = matched.isFinished,
                                                weights = chapterLengths?.positions,
                                                heights = chapterLengths?.words,
                                                newChapterCount = localNew,
                                                scale = ChapterBarScale.Row
                                            )
                                        } else {
                                            ChapterBarModel.layout(
                                                chapters = entry.remote.chapters,
                                                progress = null,
                                                weights = null,
                                                newChapterCount = newCount,
                                                scale = ChapterBarScale.Row
                                            )
                                        }
                                        Box(Modifier.combinedClickable(onClick = click, onLongClick = longClick)) {
                                            HomeSubscriptionRow(
                                                title = matched?.title ?: entry.remote.title,
                                                author = matched?.author ?: entry.remote.authorText,
                                                fandoms = matched?.workFandoms ?: entry.remote.fandoms,
                                                dateUpdated = matched?.dateUpdated ?: entry.remote.updatedDate,
                                                rating = matched?.rating ?: entry.remote.rating,
                                                categories = matched?.workCategories ?: entry.remote.categories,
                                                warnings = matched?.workWarnings ?: entry.remote.warnings,
                                                isComplete = matched?.knownCompletion ?: entry.remote.isComplete,
                                                layout = rowLayout,
                                                obscured = obscured,
                                                downloadFraction = matched?.let { rememberWorkDownloadFraction(it, downloadQueue) }
                                            )
                                        }
                                    }
                                } else {
                                    val remoteLayout = ChapterBarModel.layout(
                                        chapters = entry.remote.chapters,
                                        progress = null,
                                        weights = null,
                                        newChapterCount = newCount,
                                        scale = ChapterBarScale.Row
                                    )
                                    HomePress(onClick = { onOpenRemote(entry.remote) }) {
                                        HomeSubscriptionRow(
                                            title = entry.remote.title,
                                            author = entry.remote.authorText,
                                            fandoms = entry.remote.fandoms,
                                            dateUpdated = entry.remote.updatedDate,
                                            rating = entry.remote.rating,
                                            categories = entry.remote.categories,
                                            warnings = entry.remote.warnings,
                                            isComplete = entry.remote.isComplete,
                                            layout = remoteLayout,
                                            obscured = false,
                                            downloadFraction = null
                                        )
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
            downloadFraction = rememberWorkDownloadFraction(work, downloadQueue),
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

@Composable
private fun HomeSubscriptionRow(
    title: String,
    author: String,
    fandoms: List<String>,
    dateUpdated: String,
    rating: String,
    categories: List<String>,
    warnings: List<String>,
    isComplete: Boolean?,
    layout: ChapterBarLayout,
    obscured: Boolean,
    downloadFraction: Double?,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val large = isAccessibilityFontScale()
    val metaText = remember(author, fandoms, dateUpdated) {
        val parts = mutableListOf<String>()
        val cleanAuthor = author.trim()
        if (cleanAuthor.isNotEmpty()) parts += cleanAuthor
        HomeFacts.primaryFandom(fandoms)?.let { parts += it }
        val cleanDate = dateUpdated.trim()
        if (cleanDate.isNotEmpty()) parts += cleanDate
        parts.joinToString(" · ")
    }
    Box(
        modifier
            .fillMaxWidth()
            .downloadDimmed(if (downloadFraction != null) 1f else 0f)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .then(if (obscured) Modifier.blur(6.dp) else Modifier)
                .padding(horizontal = 16.dp, vertical = 10.dp)
                .hiddenMatureWorkSemantics(obscured),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            HomeStatusTray(
                rating = rating,
                categories = categories,
                warnings = warnings,
                isComplete = isComplete,
                arrangement = HomeStatusArrangement.Grid,
                tileSize = 24.dp,
                announces = true
            )
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text(
                    text = title,
                    color = tokens.primaryInk,
                    fontSize = 15.5.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = if (large) Int.MAX_VALUE else 1,
                    overflow = TextOverflow.Ellipsis
                )
                if (!layout.isEmpty) {
                    ChapterBars(
                        layout = layout,
                        scale = ChapterBarScale.Row,
                        height = 16.dp,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
                if (metaText.isNotEmpty()) {
                    Text(
                        text = metaText,
                        color = tokens.secondaryInk,
                        fontSize = 12.5.sp,
                        maxLines = if (large) Int.MAX_VALUE else 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
        }
        if (obscured) {
            RevealCapsule(Modifier.align(Alignment.Center))
        }
    }
}
