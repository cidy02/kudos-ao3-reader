package io.github.cidy02.kudos.comments

import androidx.compose.material.icons.outlined.Check
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.semantics.selected
import io.github.cidy02.kudos.app.DebugShotEffect
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.OpenInFull
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.platform.testTag
import io.github.cidy02.kudos.ui.subject.subjectPanel
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.network.ao3.chapters.AO3ChapterIndexRepository
import io.github.cidy02.kudos.network.ao3.chapters.AO3ChapterRef
import io.github.cidy02.kudos.network.ao3.comments.AO3Comment
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentRepository
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentTarget
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentThread
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentWorkAuthor
import io.github.cidy02.kudos.network.ao3.comments.CommentDraftStore
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteUrls
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectChip
import io.github.cidy02.kudos.ui.subject.SubjectChipStyle
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.SubjectStatCell
import io.github.cidy02.kudos.ui.subject.SubjectStatStrip
import io.github.cidy02.kudos.ui.subject.compactCount
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import kotlinx.coroutines.launch

/**
 * Comments screen matching iOS `CommentsView.swift` redesigned architecture and density.
 */
@Composable
fun CommentsScreen(
    target: AO3CommentTarget?,
    repository: AO3CommentRepository,
    onLogin: () -> Unit,
    /** An AO3 page with no native screen (a thread AO3 cut off), in the app's web view. */
    onOpenWeb: (String) -> Unit = {},
    currentUsername: String? = null,
    /** The session's count beside the name: the same name signed in again is another reader. */
    sessionGeneration: Int = 0,
    onOpenAuthor: (String) -> Unit = {},
    draftStore: CommentDraftStore? = null,
    settingsRepository: SettingsRepository? = null,
    focusedCommentId: Long? = null,
    initialChapterPosition: Int? = null,
    initialComposes: Boolean = false,
    chapterIndexRepository: AO3ChapterIndexRepository? = null,
    isModal: Boolean = false,
    onRequestExpand: (() -> Unit)? = null,
    onBack: (() -> Unit)? = null
) {
    // The view model outlives this frame; it asks for the name each time it needs it.
    val latestUsername by androidx.compose.runtime.rememberUpdatedState(currentUsername)
    val latestGeneration by androidx.compose.runtime.rememberUpdatedState(sessionGeneration)
    val viewModel: CommentsViewModel = viewModel(
        key = target?.workId?.toString(),
        factory = CommentsViewModel.factory(repository, target, draftStore, focusedCommentId,
            initialChapterPosition, { latestGeneration }, chapterIndexRepository) { latestUsername }
    )

    // Before the effects below: a new reader gets the screen read again, and nothing of the last one's.
    LaunchedEffect(viewModel, currentUsername, sessionGeneration) { viewModel.syncViewer() }

    LaunchedEffect(viewModel, initialComposes) {
        // With a comment named too it is the Inbox's Reply: an answer to that comment, once its
        // thread is on screen. Without one, a new comment on the work. Signed out it does nothing,
        // as iOS's `consumeInitialComposeIfNeeded` (A59).
        if (initialComposes && currentUsername != null)
            focusedCommentId?.let(viewModel::replyWhenLoaded) ?: viewModel.openComposer()
    }

    // Deep link focus (e.g. Inbox notification)
    LaunchedEffect(focusedCommentId) {
        // A new view model has already asked for this thread; only a different one is new. With a chapter
        // named too (the Inbox's "Chapter Comments") the view model shows the thread on its chapter's page.
        if (focusedCommentId != null && initialChapterPosition == null && viewModel.focusedCommentId.value != focusedCommentId) {
            viewModel.load(focusedId = focusedCommentId)
        }
    }

    val state by viewModel.state.collectAsState()
    val scopeMode by viewModel.scope.collectAsState()
    val chapters by viewModel.chapters.collectAsState()
    val selectedChapter by viewModel.selectedChapter.collectAsState()
    val order by viewModel.order.collectAsState()
    val draft by viewModel.draft.collectAsState()
    val submitting by viewModel.submitting.collectAsState()
    val verifying by viewModel.verifying.collectAsState()
    val canReverify by viewModel.canReverify.collectAsState()
    val message by viewModel.message.collectAsState()
    val composerPresented by viewModel.composerPresented.collectAsState()
    val composerParent by viewModel.composerParent.collectAsState()
    val editTarget by viewModel.editTarget.collectAsState()
    val composerTarget by viewModel.composerTarget.collectAsState()
    val expandedRootIds by viewModel.expandedRootIds.collectAsState()
    val visibleReplyCounts by viewModel.visibleReplyCounts.collectAsState()
    val collapsedRootIds by viewModel.collapsedRootIds.collectAsState()

    val tokens = LocalKudosTokens.current
    val clipboard = LocalClipboardManager.current
    val coroutineScope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    val configuration = LocalConfiguration.current
    val screenWidth = configuration.screenWidthDp.dp

    var showingChapterPicker by remember { mutableStateOf(false) }
    DebugShotEffect("comments", ready = state is CommentsUiState.Loaded) {
        viewModel.loadChaptersIfNeeded(chapterIndexRepository)
        showingChapterPicker = true
    }

    var sortMenuOpen by remember { mutableStateOf(false) }
    var pendingDeleteComment by remember { mutableStateOf<AO3Comment?>(null) }
    var pushedThreadRootId by remember { mutableStateOf<Long?>(null) }

    val swipeTracker = remember { CommentSwipeTracker() }

    // Sourced work title & hue
    val workTitle = (state as? CommentsUiState.Loaded)?.thread?.workTitle ?: "Comments"
    val workHue = remember(workTitle) {
        HomeFacts.workHue(emptyList(), workTitle)
    }
    val palette = remember(workHue, tokens.theme) {
        SubjectPalette.fromHue(workHue, tokens.theme)
    }

    val handlers = remember(viewModel, onLogin, onOpenAuthor, currentUsername) {
        CommentThreadHandlers(
            onReply = { comment -> viewModel.openComposer(replyingTo = comment) },
            onEdit = { comment -> viewModel.openComposer(editing = comment) },
            onDelete = { comment -> pendingDeleteComment = comment },
            onCopyLink = { comment ->
                val path = comment.threadPath ?: "/comments/${comment.numericId ?: ""}"
                val url = AO3WriteUrls.absoluteUrl(path) ?: "https://archiveofourown.org$path"
                clipboard.setText(AnnotatedString(url))
            },
            onFocusThread = { commentId ->
                pushedThreadRootId = commentId
            },
            onRequestLogin = onLogin,
            onOpenAuthor = onOpenAuthor,
            isSignedIn = currentUsername != null,
            onOpenWebPage = onOpenWeb
        )
    }

    // Before the isolated thread's early return: Reply, Edit and Delete there set this state,
    // and without these the thread view showed nothing for them (A63 F07).
    // Delete confirmation dialog
    if (pendingDeleteComment != null) {
        AlertDialog(
            onDismissRequest = { pendingDeleteComment = null },
            title = { Text("Delete this comment?") },
            text = { Text("This removes the comment on AO3. It cannot be undone.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        val toDelete = pendingDeleteComment
                        pendingDeleteComment = null
                        if (toDelete != null) viewModel.deleteComment(toDelete)
                    }
                ) {
                    Text("Delete", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { pendingDeleteComment = null }) {
                    Text("Cancel")
                }
            }
        )
    }

    // Action banner message dialog
    if (message != null) {
        AlertDialog(
            onDismissRequest = { viewModel.clearMessage() },
            title = { Text("AO3") },
            text = { Text(message.orEmpty()) },
            dismissButton = {
                if (canReverify) TextButton(onClick = {
                    viewModel.clearMessage()
                    viewModel.reverify()
                }, enabled = !submitting) { Text("Check Again") }
            },
            confirmButton = {
                TextButton(onClick = { viewModel.clearMessage() }) {
                    Text("OK")
                }
            }
        )
    }

    // Composer modal sheet
    if (composerPresented) {
        CommentComposerSheet(
            replyTarget = composerParent,
            editTarget = editTarget,
            draft = draft,
            onDraftChange = viewModel::updateDraft,
            submitting = submitting,
            verifying = verifying,
            currentUsername = currentUsername,
            isScopeByChapter = composerTarget is AO3CommentTarget.Chapter,
            palette = palette,
            onDismiss = viewModel::closeComposer,
            onSubmit = viewModel::submitComment,
            onOpenAuthor = onOpenAuthor
        )
    }

    // If an isolated thread is opened, render CommentThreadScreen
    if (pushedThreadRootId != null) {
        val rootComment = remember(pushedThreadRootId, state) {
            pushedThreadRootId?.let { viewModel.findComment(it) }
        }
        val authors = (state as? CommentsUiState.Loaded)?.thread?.workAuthors ?: emptyList()
        CommentThreadScreen(
            root = rootComment,
            workTitle = workTitle,
            workAuthors = authors.map { it.displayName },
            workAuthorUsernames = authors.mapNotNull { it.username },
            palette = palette,
            handlers = handlers,
            onBack = { pushedThreadRootId = null }
        )
        return
    }

    // Pushed chrome registration
    ProvidePushedShellChrome(
        hasSubjectHeader = true,
        hideTabBar = true,
        onBack = onBack,
        trailingContent = if (isModal) {
            {
                if (onRequestExpand != null) {
                    IconButton(onClick = onRequestExpand) {
                        Icon(
                            imageVector = Icons.Outlined.OpenInFull,
                            contentDescription = "Expand to full screen",
                            tint = tokens.primaryInk
                        )
                    }
                }
                IconButton(onClick = { onBack?.invoke() }) {
                    Icon(
                        imageVector = Icons.Default.Close,
                        contentDescription = "Close",
                        tint = tokens.primaryInk
                    )
                }
            }
        } else null
    )

    // Chapter picker modal sheet
    if (showingChapterPicker) {
        val chaptersLoading by viewModel.chaptersLoading.collectAsState()
        val chaptersFailed by viewModel.chaptersFailed.collectAsState()
        val chaptersFailureMessage by viewModel.chaptersFailureMessage.collectAsState()
        ChapterPickerSheet(
            chapters = chapters,
            chaptersLoading = chaptersLoading,
            chaptersFailed = chaptersFailed,
            chaptersFailureMessage = chaptersFailureMessage,
            selectedChapter = selectedChapter,
            isScopeAll = scopeMode == CommentScope.All,
            totalComments = (state as? CommentsUiState.Loaded)?.thread?.totalComments,
            onSelectAll = {
                viewModel.setScope(CommentScope.All)
                showingChapterPicker = false
            },
            onSelectChapter = { chapter ->
                viewModel.selectChapter(chapter)
                showingChapterPicker = false
            },
            onDismiss = { showingChapterPicker = false },
            palette = palette
        )
    }

    val loadedThread = (state as? CommentsUiState.Loaded)?.thread
    val loadedFigures = remember(loadedThread) {
        loadedThread?.let { calculateFigures(it) }
    }
    val allComments = remember(loadedThread) {
        loadedThread?.let { flattenAll(it.comments) } ?: emptyList()
    }
    val repliesByRoot = remember(loadedThread) {
        loadedThread?.comments?.associate { root ->
            (root.numericId ?: 0L) to CommentThreadGeometry.flattenedReplies(root)
        } ?: emptyMap()
    }
    val rows = remember(
        loadedThread?.comments,
        repliesByRoot,
        expandedRootIds,
        visibleReplyCounts,
        collapsedRootIds
    ) {
        if (loadedThread != null) {
            CommentConversationBuilder.rows(
                roots = loadedThread.comments,
                repliesByRoot = repliesByRoot,
                expandedRootIds = expandedRootIds,
                visibleReplyCounts = visibleReplyCounts,
                collapsedRootIds = collapsedRootIds
            )
        } else emptyList()
    }

    io.github.cidy02.kudos.ui.components.KudosRefreshBox(
        onRefresh = { viewModel.refresh() },
        modifier = Modifier
            .fillMaxSize()
            .subjectScreenWash(palette, 480.dp)
    ) {
        LazyColumn(
            state = listState,
            modifier = Modifier.fillMaxSize()
        ) {
            // Header kicker and work title
            item {
                val kicker = if (scopeMode == CommentScope.ByChapter && selectedChapter != null) {
                    "Chapter ${selectedChapter?.position}"
                } else {
                    "Comments"
                }

                val authors = (state as? CommentsUiState.Loaded)?.thread?.workAuthors ?: emptyList()

                SubjectHeaderBlock(
                    kicker = kicker,
                    title = workTitle,
                    palette = palette,
                    // Below the floating back circle, as every pushed subject screen.
                    modifier = Modifier.padding(
                        top = androidx.compose.foundation.layout.WindowInsets.systemBars
                            .asPaddingValues().calculateTopPadding() + 56.dp
                    ),
                    trailing = if (authors.isNotEmpty()) {
                        {
                            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                // "Calytrix, Second Pseud": without the comma two creators
                                // read as one name.
                                for ((index, author) in authors.withIndex()) {
                                    Text(
                                        text = author.displayName + if (index < authors.lastIndex) "," else "",
                                        fontSize = 15.sp,
                                        color = palette.accent,
                                        modifier = Modifier.clickable {
                                            author.username?.let(onOpenAuthor)
                                        }
                                    )
                                }
                            }
                        }
                    } else null
                )
            }

            // Stat strip & Signal scope note
            if (loadedThread != null && loadedFigures != null) {
                val thread = loadedThread

                item {
                    val cells = mutableListOf<SubjectStatCell>()
                    if (thread.totalComments != null) {
                        cells.add(
                            SubjectStatCell(
                                value = thread.totalComments.compactCount(),
                                label = "Comments"
                            )
                        )
                    }
                    cells.add(
                        SubjectStatCell(
                            value = loadedFigures.threads.compactCount(),
                            label = "Threads"
                        )
                    )
                    if (currentUsername != null) {
                        cells.add(
                            SubjectStatCell(
                                value = loadedFigures.mine.compactCount(),
                                label = "Yours",
                                isHighlighted = loadedFigures.mine > 0
                            )
                        )
                    }
                    if (loadedFigures.latest != null) {
                        cells.add(
                            SubjectStatCell(
                                value = loadedFigures.latest,
                                label = "Latest"
                            )
                        )
                    }

                    if (cells.isNotEmpty()) {
                        SubjectStatStrip(
                            cells = cells,
                            palette = palette,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp)
                        )
                    }

                    if (thread.totalPages > 1) {
                        Text(
                            text = "Threads, Yours and Latest count only this page. The comment total covers the whole work.",
                            fontSize = 11.5.sp,
                            color = tokens.secondaryInk.copy(alpha = 0.7f),
                            modifier = Modifier.padding(horizontal = 20.dp, vertical = 4.dp),
                            lineHeight = 16.sp
                        )
                    }
                }
            }

            // Filter rail: Chapter pill + Sort pill
            item {
                val chapterPillTitle = if (scopeMode == CommentScope.ByChapter) {
                    selectedChapter?.let { "Chapter ${it.position}" } ?: "By chapter"
                } else {
                    "All comments"
                }

                CommentsFilterRail {
                    // Chapter pill
                    SubjectChip(
                        text = chapterPillTitle,
                        modifier = Modifier
                            .semantics {
                                contentDescription = "Browse comments by chapter"
                            }
                            .clickable {
                                viewModel.loadChaptersIfNeeded(chapterIndexRepository)
                                showingChapterPicker = true
                            },
                        style = SubjectChipStyle.Pill(isSelected = scopeMode == CommentScope.ByChapter),
                        leadingIcon = chapterPickerBookIcon,
                        trailingIcon = Icons.Filled.KeyboardArrowDown,
                        palette = palette
                    )

                    // Sort pill
                    Box {
                        SubjectChip(
                            text = if (order == CommentOrder.NewestFirst) "Newest" else "Oldest",
                            modifier = Modifier
                                .semantics {
                                    contentDescription = "Sort comments"
                                }
                                .clickable { sortMenuOpen = true },
                            style = SubjectChipStyle.Pill(isSelected = false),
                            leadingIcon = Icons.Default.SwapVert,
                            trailingIcon = Icons.Filled.KeyboardArrowDown,
                            palette = palette
                        )

                        DropdownMenu(
                            expanded = sortMenuOpen,
                            onDismissRequest = { sortMenuOpen = false }
                        ) {
                            DropdownMenuItem(
                                text = { Text("Oldest First") },
                                trailingIcon = if (order == CommentOrder.OldestFirst) {
                                    { Icon(Icons.Default.Check, contentDescription = null) }
                                } else null,
                                onClick = {
                                    viewModel.setOrder(CommentOrder.OldestFirst)
                                    sortMenuOpen = false
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("Newest First") },
                                trailingIcon = if (order == CommentOrder.NewestFirst) {
                                    { Icon(Icons.Default.Check, contentDescription = null) }
                                } else null,
                                onClick = {
                                    viewModel.setOrder(CommentOrder.NewestFirst)
                                    sortMenuOpen = false
                                }
                            )
                        }
                    }
                }
            }

            // Main Content Area
            when (val current = state) {
                is CommentsUiState.Loading -> {
                    item {
                        io.github.cidy02.kudos.ui.subject.SubjectSkeletonLoading("Loading comments") {
                            Column { repeat(4) { CommentSkeletonRow() } }
                        }
                    }
                }
                is CommentsUiState.Error -> {
                    item {
                        ContentUnavailableView(
                            title = "Couldn't Load Comments",
                            description = current.message,
                            icon = Icons.Outlined.ErrorOutline,
                            actionLabel = "Try Again",
                            onAction = { viewModel.retry() },
                            palette = palette
                        )
                    }
                }
                is CommentsUiState.AuthRequired -> {
                    item {
                        ContentUnavailableView(
                            title = "Couldn't Load Comments",
                            description = current.message,
                            icon = Icons.Outlined.ErrorOutline,
                            actionLabel = "Log in to AO3",
                            onAction = onLogin,
                            palette = palette
                        )
                    }
                }
                is CommentsUiState.Loaded -> {
                    val thread = current.thread
                    // AO3 could not be reached and this is the copy kept from the last reading: said,
                    // with its age. It was shown as if it were today's page.
                    thread.fetchedAt?.let { keptAt ->
                        item {
                            io.github.cidy02.kudos.ui.components.CachedAO3DataRow(
                                Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                                text = offlineCommentsLine(keptAt, System.currentTimeMillis(), thread.keptWhileOffline))
                        }
                    }
                    if (thread.comments.isEmpty()) {
                        item {
                            ContentUnavailableView(
                                title = "No Comments Yet",
                                description = "You can be the first to comment on this work.",
                                icon = Icons.Outlined.ChatBubbleOutline,
                                palette = palette
                            )
                        }
                    } else {
                        // Section Rule Header
                        item {
                            SectionRuleHeader(
                                title = "Comments",
                                count = allComments.size,
                                modifier = Modifier.padding(top = 8.dp)
                            )
                        }

                        // Flattened lazy items
                        items(
                            items = rows,
                            key = { it.id }
                        ) { row ->
                            CommentConversationRow(
                                row = row,
                                workAuthors = thread.workAuthors.map { it.displayName },
                                workAuthorUsernames = thread.workAuthors.mapNotNull { it.username },
                                palette = palette,
                                handlers = handlers,
                                swipeTracker = swipeTracker,
                                onExpand = { viewModel.expandReplies(row.rootId) },
                                onContinueThread = { pushedThreadRootId = row.rootId },
                                onToggleCollapse = { viewModel.toggleCollapsed(row.rootId) },
                                containerWidth = screenWidth
                            )
                        }

                        // Pagination controls if multiple pages
                        if (thread.totalPages > 1) {
                            item {
                                val previous: @Composable () -> Unit = {
                                    OutlinedButton(
                                        enabled = thread.currentPage > 1,
                                        onClick = { viewModel.load(page = thread.currentPage - 1) },
                                        shape = RoundedCornerShape(percent = 50)
                                    ) {
                                        Text("Previous")
                                    }
                                }
                                val position: @Composable () -> Unit = {
                                    Text(
                                        text = "Page ${thread.currentPage} of ${thread.totalPages}",
                                        fontSize = 13.sp,
                                        fontFamily = FontFamily.Monospace,
                                        color = tokens.secondaryInk
                                    )
                                }
                                val next: @Composable () -> Unit = {
                                    OutlinedButton(
                                        enabled = thread.currentPage < thread.totalPages,
                                        onClick = { viewModel.load(page = thread.currentPage + 1) },
                                        shape = RoundedCornerShape(percent = 50)
                                    ) {
                                        Text("Next")
                                    }
                                }
                                // One row holds the three at ordinary sizes, as on iOS. At an accessibility
                                // size it squeezed Next into a column of single letters.
                                if (io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale()) io.github.cidy02.kudos.ui.components.LargeTextPager(
                                    thread.currentPage, thread.totalPages, { viewModel.load(page = it) },
                                    Modifier.padding(horizontal = 16.dp, vertical = 16.dp)
                                ) else Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(horizontal = 16.dp, vertical = 16.dp),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    previous(); position(); next()
                                }
                            }
                        }
                    }
                }
            }

            // Bottom clearance for floating CTA pill
            item {
                Spacer(Modifier.height(84.dp))
            }
        }

        // Floating "Write Comment" / "Log in to comment" pill at bottom
        if (state is CommentsUiState.Loaded) {
            val isLoggedIn = currentUsername != null
            val title = if (isLoggedIn) "Write a comment" else "Log in to comment"
            val icon = if (isLoggedIn) Icons.Outlined.Edit else Icons.Outlined.Person

            Box(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .padding(bottom = 16.dp),
                contentAlignment = Alignment.Center
            ) {
                Surface(
                    onClick = {
                        if (isLoggedIn) {
                            viewModel.openComposer()
                        } else {
                            onLogin()
                        }
                    },
                    shape = RoundedCornerShape(percent = 50),
                    color = palette.accent,
                    shadowElevation = 6.dp,
                    modifier = Modifier.height(44.dp)
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 20.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(
                            imageVector = icon,
                            contentDescription = null,
                            tint = palette.solidButtonLabel,
                            modifier = Modifier.size(16.dp)
                        )
                        Text(
                            text = title,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = palette.solidButtonLabel
                        )
                    }
                }
            }
        }
    }
}

internal val chapterPickerBookIcon = Icons.AutoMirrored.Outlined.MenuBook

/**
 * Chapter picker sheet matching iOS `chapterPicker` (CommentsView.swift:893).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChapterPickerSheet(
    chapters: List<AO3ChapterRef>,
    chaptersLoading: Boolean = false,
    chaptersFailed: Boolean = false,
    chaptersFailureMessage: String? = null,
    selectedChapter: AO3ChapterRef?,
    isScopeAll: Boolean,
    totalComments: Int?,
    onSelectAll: () -> Unit,
    onSelectChapter: (AO3ChapterRef) -> Unit,
    onDismiss: () -> Unit,
    palette: SubjectPalette = LocalKudosTokens.current.scopePalette
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)
    val tokens = LocalKudosTokens.current

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = tokens.background
    ) {
        ChapterPickerContent(chapters, chaptersLoading, chaptersFailed, chaptersFailureMessage,
            selectedChapter, isScopeAll, totalComments, onSelectAll, onSelectChapter, palette)
    }
}

@Composable
internal fun ChapterPickerContent(
    chapters: List<AO3ChapterRef>, chaptersLoading: Boolean = false, chaptersFailed: Boolean = false,
    chaptersFailureMessage: String? = null, selectedChapter: AO3ChapterRef?, isScopeAll: Boolean,
    totalComments: Int?, onSelectAll: () -> Unit, onSelectChapter: (AO3ChapterRef) -> Unit,
    palette: SubjectPalette = LocalKudosTokens.current.scopePalette
) {
    val tokens = LocalKudosTokens.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 8.dp)
            .padding(bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = "Browse Comments by Chapter",
            fontSize = 17.sp,
            fontWeight = FontWeight.Bold,
            color = tokens.primaryInk,
            modifier = Modifier.padding(bottom = 4.dp)
        )

        Column(Modifier.fillMaxWidth().subjectPanel().testTag("Chapter choices")) {
            // "All comments" option
            Surface(
                onClick = onSelectAll,
                shape = androidx.compose.ui.graphics.RectangleShape,
                color = androidx.compose.ui.graphics.Color.Transparent,
                modifier = Modifier.fillMaxWidth().semantics { selected = isScopeAll }
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.ChatBubbleOutline,
                            contentDescription = null,
                            tint = palette.accent,
                            modifier = Modifier.size(18.dp)
                        )
                        Text(
                            text = "All Comments",
                            fontSize = 15.sp,
                            fontWeight = if (isScopeAll) FontWeight.SemiBold else FontWeight.Normal,
                            color = palette.accent
                        )
                    }
                    if (isScopeAll) Icon(Icons.Outlined.Check, null, tint = palette.accent)
                    if (totalComments != null) {
                        Text(
                            text = java.text.NumberFormat.getIntegerInstance().format(totalComments),
                            fontSize = 13.sp,
                            fontFamily = FontFamily.Monospace,
                            color = palette.accent.copy(alpha = if (isScopeAll) 1f else 0.6f)
                        )
                    }
                }
            }

            // Without a list the sheet said nothing: "All Comments" and a blank (iOS: a spinner,
            // or "Couldn't Load Chapters"). Opening the sheet again asks AO3 again.
            if (chapters.isEmpty() && (chaptersLoading || chaptersFailed)) {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 18.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    if (chaptersFailed) {
                        Text("Couldn't Load Chapters", fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
                            color = tokens.primaryInk)
                        Text(chaptersFailureMessage ?: "Check your connection and try again.", fontSize = 13.sp, lineHeight = 18.sp,
                            color = tokens.secondaryInk)
                    } else {
                        androidx.compose.material3.CircularProgressIndicator(
                            modifier = Modifier.size(22.dp).semantics { contentDescription = "Loading chapters" },
                            strokeWidth = 2.dp, color = palette.accent)
                    }
                }
            }

            // Chapter list
            for (chapter in chapters) {
                SubjectRowSeparator(modifier = Modifier.testTag("Chapter separator"))
                val isSelected = !isScopeAll && selectedChapter?.chapterId == chapter.chapterId
                Surface(
                    onClick = { onSelectChapter(chapter) },
                    shape = androidx.compose.ui.graphics.RectangleShape,
                    color = androidx.compose.ui.graphics.Color.Transparent,
                    modifier = Modifier.fillMaxWidth().semantics { selected = isSelected }
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            modifier = Modifier.weight(1f, fill = false)
                        ) {
                            Icon(
                                imageVector = chapterPickerBookIcon,
                                contentDescription = null,
                                tint = palette.accent,
                                modifier = Modifier.size(18.dp)
                            )
                            Text(
                                text = chapter.displayName,
                                fontSize = 15.sp,
                                fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
                                color = palette.accent,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                        if (isSelected) {
                            Icon(
                                imageVector = Icons.Default.Check,
                                contentDescription = null,
                                tint = palette.accent,
                                modifier = Modifier.size(16.dp)
                            )
                        }
                    }
                }
            }
        }
        Text(
            text = "AO3 doesn't show comment totals for each chapter. Choose a chapter to see its comments.",
            fontSize = 12.sp,
            color = tokens.secondaryInk,
            lineHeight = 16.sp,
            modifier = Modifier.padding(start = 4.dp, end = 4.dp, top = 4.dp)
        )
    }
}

private data class LoadedFigures(
    val threads: Int,
    val comments: Int,
    val mine: Int,
    val latest: String?
)

private fun calculateFigures(thread: AO3CommentThread): LoadedFigures {
    val all = flattenAll(thread.comments)
    val mine = all.count { it.editPath != null }
    // The newest of them, and how long ago, as iOS says it ("3mo ago"). This took the first
    // comment's date, which under "Oldest" is the oldest, and printed the day.
    val latestFormatted = all.mapNotNull { AO3CommentTimestamp.parse(it.date) }.maxOrNull()
        ?.let { AO3CommentTimestamp.relativeNarrow(it) }
        ?: all.firstNotNullOfOrNull { it.date.takeIf { d -> d.isNotBlank() } }

    return LoadedFigures(
        threads = thread.comments.size,
        comments = all.size,
        mine = mine,
        latest = latestFormatted
    )
}

private fun flattenAll(comments: List<AO3Comment>): List<AO3Comment> {
    val result = mutableListOf<AO3Comment>()
    fun walk(c: AO3Comment) {
        result.add(c)
        for (reply in c.replies) walk(reply)
    }
    for (c in comments) walk(c)
    return result
}

/**
 * iOS: "You're offline. These comments are from 2 hours ago and may be out of date.", and after any
 * other failed read "AO3 couldn't be reached. …" (it said offline after a timeout too).
 */
internal fun offlineCommentsLine(keptAt: Long, now: Long, offline: Boolean = true): String {
    val minutes = (now - keptAt) / 60_000
    fun count(n: Long, unit: String) = "$n $unit${if (n == 1L) "" else "s"} ago"
    val from = when {
        keptAt <= 0L -> "earlier"
        minutes < 1 -> "a moment ago"
        minutes < 60 -> count(minutes, "minute")
        minutes < 60 * 24 -> count(minutes / 60, "hour")
        else -> count(minutes / (60 * 24), "day")
    }
    val why = if (offline) "You're offline." else "AO3 couldn't be reached."
    return "$why These comments are from $from and may be out of date."
}

/** iOS CommentsView.filterRail gives each control its own row at accessibility sizes. */
@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
internal fun CommentsFilterRail(content: @Composable () -> Unit) {
    androidx.compose.foundation.layout.FlowRow(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
        maxItemsInEachRow = if (io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale()) 1 else 2,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(7.dp)
    ) { content() }
}
