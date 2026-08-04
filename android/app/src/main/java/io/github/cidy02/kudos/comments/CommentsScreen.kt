package io.github.cidy02.kudos.comments

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.ArrowRight
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.comments.AO3Comment
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentParticipantRole
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentRepository
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentTarget
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentThread
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentWorkAuthor
import io.github.cidy02.kudos.network.ao3.comments.CommentDraftStore
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.ui.components.DestructiveConfirmation
import io.github.cidy02.kudos.ui.components.CommentAvatar
import io.github.cidy02.kudos.ui.components.CommentParticipantBadge
import kotlinx.coroutines.launch

/** In-composer reply target (parent comment for a reply POST). */
private data class ReplyTarget(
    val commentId: Long,
    val authorName: String
)

@Composable
fun CommentsScreen(
    target: AO3CommentTarget?,
    repository: AO3CommentRepository,
    onLogin: () -> Unit,
    currentUsername: String? = null,
    draftStore: CommentDraftStore? = null,
    settingsRepository: SettingsRepository? = null,
    focusedCommentId: Long? = null
) {
    val viewModel: CommentsViewModel = viewModel(
        key = target?.workId?.toString(),
        factory = CommentsViewModel.factory(repository, target, draftStore, currentUsername)
    )
    
    // Initial focus from deep-link (Inbox tap)
    LaunchedEffect(focusedCommentId) {
        if (focusedCommentId != null) {
            viewModel.load(focusedId = focusedCommentId)
        }
    }

    val state by viewModel.state.collectAsState()
    val settingsState = settingsRepository?.settings?.collectAsState(initial = KudosSettings.Defaults)
    val settings = settingsState?.value ?: KudosSettings.Defaults
    val draft by viewModel.draft.collectAsState()
    val submitting by viewModel.submitting.collectAsState()
    val message by viewModel.message.collectAsState()
    val currentTarget by viewModel.currentTarget.collectAsState()
    val focusedCommentId by viewModel.focusedCommentId.collectAsState()
    val order by viewModel.order.collectAsState()
    val replyTarget by viewModel.replyTarget.collectAsState()
    val editTarget by viewModel.editTarget.collectAsState()
    
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    var pendingDeleteComment by remember { mutableStateOf<AO3Comment?>(null) }
    val collapsedIds = remember { mutableStateMapOf<String, Boolean>() }

    fun startReply(comment: AO3Comment) {
        viewModel.startReply(comment)
        scope.launch {
            listState.animateScrollToItem(0)
        }
    }

    DestructiveConfirmation(
        show = pendingDeleteComment != null,
        title = "Delete comment?",
        text = "This will permanently remove your comment from AO3.",
        confirmText = "Delete",
        confirmBeforeDelete = settings.app.confirmBeforeDelete,
        onConfirm = {
            val comment = pendingDeleteComment ?: return@DestructiveConfirmation
            pendingDeleteComment = null
            viewModel.deleteComment(comment)
        },
        onDismissRequest = { pendingDeleteComment = null }
    )

    when (val current = state) {
        CommentsUiState.Loading -> {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(24.dp),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                CircularProgressIndicator()
                Text(
                    text = "Loading comments…",
                    modifier = Modifier.padding(top = 12.dp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        is CommentsUiState.AuthRequired -> {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text(current.message, color = MaterialTheme.colorScheme.error)
                Button(onClick = onLogin) { Text("Log in to AO3") }
                OutlinedButton(onClick = { viewModel.load() }) { Text("Retry") }
            }
        }
        is CommentsUiState.Error -> {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text(current.message, color = MaterialTheme.colorScheme.error)
                OutlinedButton(onClick = { viewModel.load() }) { Text("Retry") }
            }
        }
        is CommentsUiState.Loaded -> {
            val thread = current.thread
            LazyColumn(
                state = listState,
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(horizontal = 20.dp, vertical = 16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                item {
                    if (focusedCommentId != null) {
                        Surface(
                            color = MaterialTheme.colorScheme.secondaryContainer,
                            shape = MaterialTheme.shapes.medium,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Row(
                                modifier = Modifier.padding(12.dp),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    "Viewing focused thread",
                                    style = MaterialTheme.typography.labelLarge
                                )
                                TextButton(onClick = { viewModel.load(1, null) }) {
                                    Text("Show all")
                                }
                            }
                        }
                    }
                }
                
                // Chapter Picker + Sort (iOS parity)
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        ChapterScopePicker(
                            currentTarget = currentTarget,
                            initialTarget = viewModel.initialTarget,
                            onSelectTarget = { viewModel.setTarget(it) },
                            modifier = Modifier.weight(1f)
                        )
                        
                        var sortMenuOpen by remember { mutableStateOf(false) }
                        Box {
                            TextButton(onClick = { sortMenuOpen = true }) {
                                Text(if (order == CommentOrder.NewestFirst) "Newest First" else "Oldest First")
                                Icon(Icons.Default.ArrowDropDown, null)
                            }
                            DropdownMenu(expanded = sortMenuOpen, onDismissRequest = { sortMenuOpen = false }) {
                                DropdownMenuItem(
                                    text = { Text("Oldest First") },
                                    onClick = {
                                        viewModel.setOrder(CommentOrder.OldestFirst)
                                        sortMenuOpen = false
                                    }
                                )
                                DropdownMenuItem(
                                    text = { Text("Newest First") },
                                    onClick = {
                                        viewModel.setOrder(CommentOrder.NewestFirst)
                                        sortMenuOpen = false
                                    }
                                )
                            }
                        }
                    }
                }

                item {
                    // Show target picker if multiple chapters available.
                    // (Requires more data in thread model).
                    
                    CommentComposer(
                        thread = thread,
                        draft = draft,
                        submitting = submitting,
                        replyTarget = replyTarget?.let { ReplyTarget(it.commentId, it.authorName) },
                        editTarget = editTarget,
                        onDraft = viewModel::updateDraft,
                        onCancelReply = viewModel::cancelReply,
                        onCancelEdit = viewModel::cancelEdit,
                        onLogin = onLogin,
                        onSubmit = { viewModel.submitComment() }
                    )
                }
                message?.let { msg ->
                    item {
                        Text(msg, color = MaterialTheme.colorScheme.primary)
                    }
                }
                if (thread.totalPages > 1) {
                    item {
                        PaginationControls(
                            page = thread.currentPage,
                            totalPages = thread.totalPages,
                            onLoadPage = { page -> viewModel.load(page) }
                        )
                    }
                }
                item { HorizontalDivider() }
                if (thread.comments.isEmpty()) {
                    item {
                        Text(
                            "No comments yet.",
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                } else {
                    items(
                        items = thread.comments,
                        key = { it.id ?: "${it.author.name}-${it.date}-${it.body.hashCode()}" }
                    ) { comment ->
                        CommentThreadRow(
                            comment = comment,
                            currentUsername = currentUsername,
                            workAuthors = thread.workAuthors,
                            onReply = ::startReply,
                            onEdit = { viewModel.startEdit(it) },
                            onDelete = { pendingDeleteComment = it },
                            onLoadMore = { viewModel.load() },
                            onViewThread = { commentId -> viewModel.load(focusedId = commentId) },
                            collapsedIds = collapsedIds
                        )
                    }
                }
                if (thread.totalPages > 1) {
                    item {
                        PaginationControls(
                            page = thread.currentPage,
                            totalPages = thread.totalPages,
                            onLoadPage = { page -> viewModel.load(page) }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun CommentComposer(
    thread: AO3CommentThread,
    draft: String,
    submitting: Boolean,
    replyTarget: ReplyTarget?,
    editTarget: AO3Comment? = null,
    onDraft: (String) -> Unit,
    onCancelReply: () -> Unit,
    onCancelEdit: () -> Unit = {},
    onLogin: () -> Unit,
    onSubmit: () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        when {
            // Prefer composer when form is present (signed-in).
            thread.form != null -> {
                if (replyTarget != null || editTarget != null) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = when {
                                editTarget != null -> "Editing your comment"
                                else -> "Replying to ${replyTarget?.authorName}"
                            },
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.weight(1f)
                        )
                        TextButton(onClick = {
                            if (editTarget != null) onCancelEdit() else onCancelReply()
                        }) {
                            Text("Cancel")
                        }
                    }
                }
                OutlinedTextField(
                    value = draft,
                    onValueChange = onDraft,
                    label = {
                        Text(
                            when {
                                editTarget != null -> "Edit comment"
                                replyTarget != null -> "Write a reply"
                                else -> "Leave a comment"
                            }
                        )
                    },
                    minLines = 3,
                    modifier = Modifier.fillMaxWidth()
                )
                Button(
                    enabled = !submitting && draft.isNotBlank(),
                    onClick = onSubmit
                ) {
                    Text(
                        when {
                            submitting && editTarget != null -> "Saving…"
                            submitting && replyTarget != null -> "Posting reply…"
                            submitting -> "Posting…"
                            editTarget != null -> "Save Changes"
                            replyTarget != null -> "Post Reply"
                            else -> "Post Comment"
                        }
                    )
                }
            }
            // True lock (not "log in to comment" — that is handled below).
            thread.commentsLocked -> {
                Text(
                    "AO3 is not accepting comments on this work.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            else -> {
                Text(
                    "Log in to AO3 to leave a comment.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                OutlinedButton(onClick = onLogin) { Text("Log in") }
            }
        }
    }
}

@Composable
private fun CommentThreadRow(
    comment: AO3Comment,
    currentUsername: String?,
    workAuthors: List<AO3CommentWorkAuthor>,
    onReply: (AO3Comment) -> Unit,
    onEdit: (AO3Comment) -> Unit,
    onDelete: (AO3Comment) -> Unit,
    onLoadMore: (String) -> Unit,
    onViewThread: (Long) -> Unit,
    collapsedIds: MutableMap<String, Boolean>,
    depth: Int = 0
) {
    // Initial collapse: deep nests (depth > 2) default to collapsed.
    // Cutoffs are always "collapsed" in the sense that they need to load more.
    val isCollapsed = collapsedIds[comment.id ?: ""] ?: (depth > 2 && comment.replies.isNotEmpty())
    
    fun toggle() {
        comment.id?.let { id ->
            collapsedIds[id] = !isCollapsed
        }
    }

    Column(modifier = Modifier.fillMaxWidth()) {
        if (comment.isThreadCutoff) {
            CommentCutoffRow(comment = comment, onClick = { onLoadMore(comment.cutoffThreadPath!!) })
        } else {
            CommentRow(
                comment = comment,
                currentUsername = currentUsername,
                workAuthors = workAuthors,
                onReply = { onReply(comment) },
                onEdit = { onEdit(comment) },
                onDelete = { onDelete(comment) },
                isExpanded = !isCollapsed,
                onToggleExpand = ::toggle,
                depth = depth,
                onViewThread = onViewThread
            )
        }

        if (!isCollapsed && comment.replies.isNotEmpty()) {
            comment.replies.forEach { reply ->
                CommentThreadRow(
                    comment = reply,
                    currentUsername = currentUsername,
                    workAuthors = workAuthors,
                    onReply = onReply,
                    onEdit = onEdit,
                    onDelete = onDelete,
                    onLoadMore = onLoadMore,
                    onViewThread = onViewThread,
                    collapsedIds = collapsedIds,
                    depth = depth + 1
                )
            }
        }
    }
}

@Composable
private fun CommentRow(
    comment: AO3Comment,
    currentUsername: String?,
    workAuthors: List<AO3CommentWorkAuthor>,
    onReply: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    isExpanded: Boolean,
    onToggleExpand: () -> Unit,
    onViewThread: (Long) -> Unit,
    depth: Int
) {
    val role = remember(comment, currentUsername, workAuthors) {
        AO3CommentParticipantRole.resolve(
            name = comment.author.name,
            isGuest = comment.isGuest,
            isAnonymousCreator = comment.isAnonymousCreator,
            commenterUsername = comment.author.username,
            currentUsername = currentUsername,
            workAuthors = workAuthors.map { it.displayName },
            workAuthorUsernames = workAuthors.mapNotNull { it.username }
        )
    }
    val clipboard = LocalClipboardManager.current
    var showMenu by remember { mutableStateOf(false) }

    Row(
        modifier = Modifier
            .padding(start = (depth * 12).coerceAtMost(60).dp)
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        if (comment.replies.isNotEmpty()) {
            IconButton(
                onClick = onToggleExpand,
                modifier = Modifier.size(24.dp)
            ) {
                Icon(
                    imageVector = if (isExpanded) Icons.Default.ArrowDropDown else Icons.Default.ArrowRight,
                    contentDescription = if (isExpanded) "Collapse" else "Expand"
                )
            }
        } else {
            Spacer(Modifier.size(24.dp))
        }

        CommentAvatar(
            avatarUrl = comment.avatarUrl,
            isGuest = comment.isGuest,
            modifier = Modifier.size(32.dp)
        )

        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = comment.author.name,
                    style = MaterialTheme.typography.titleSmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false)
                )
                CommentParticipantBadge(role = role)
                if (comment.chapterLabel != null) {
                    Surface(
                        color = MaterialTheme.colorScheme.surfaceVariant,
                        shape = MaterialTheme.shapes.extraSmall
                    ) {
                        Text(
                            text = comment.chapterLabel!!,
                            style = MaterialTheme.typography.labelSmall,
                            modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp)
                        )
                    }
                }
            }
            if (comment.date.isNotBlank()) {
                Text(
                    comment.date,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            
            if (isExpanded) {
                var isLongComment by remember { mutableStateOf(false) }
                var showFullComment by remember { mutableStateOf(false) }
                
                if (comment.isDeletedOrHidden) {
                    Surface(
                        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
                        shape = MaterialTheme.shapes.small,
                        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)
                    ) {
                        Text(
                            text = comment.body,
                            style = MaterialTheme.typography.bodyMedium.copy(
                                fontStyle = androidx.compose.ui.text.font.FontStyle.Italic
                            ),
                            modifier = Modifier.padding(12.dp),
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                } else {
                    Text(
                        text = comment.body,
                        style = MaterialTheme.typography.bodyMedium,
                        maxLines = if (showFullComment) Int.MAX_VALUE else 5,
                        overflow = TextOverflow.Ellipsis,
                        onTextLayout = { result -> isLongComment = result.hasVisualOverflow },
                        color = MaterialTheme.colorScheme.onSurface
                    )
                }
                
                if (isLongComment && !showFullComment) {
                    TextButton(
                        onClick = { showFullComment = true },
                        contentPadding = PaddingValues(0.dp)
                    ) {
                        Text("Read more", style = MaterialTheme.typography.labelMedium)
                    }
                }

                Row(
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    if (comment.canReply && comment.numericId != null) {
                        TextButton(
                            onClick = onReply,
                            contentPadding = PaddingValues(0.dp)
                        ) {
                            Text("Reply", style = MaterialTheme.typography.labelMedium)
                        }
                    }
                    
                    Box {
                        TextButton(
                            onClick = { showMenu = true },
                            contentPadding = PaddingValues(0.dp)
                        ) {
                            Text("More", style = MaterialTheme.typography.labelMedium)
                        }
                        DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                            if (comment.editPath != null) {
                                DropdownMenuItem(
                                    text = { Text("Edit") },
                                    onClick = {
                                        showMenu = false
                                        onEdit()
                                    }
                                )
                            }
                            if (comment.deletePath != null) {
                                DropdownMenuItem(
                                    text = { Text("Delete", color = MaterialTheme.colorScheme.error) },
                                    onClick = {
                                        showMenu = false
                                        onDelete()
                                    }
                                )
                            }
                            DropdownMenuItem(
                                text = { Text("Copy Link") },
                                onClick = {
                                    showMenu = false
                                    comment.threadPath?.let { 
                                        clipboard.setText(AnnotatedString("https://archiveofourown.org$it"))
                                    }
                                }
                            )
                            if (comment.threadPath != null) {
                                DropdownMenuItem(
                                    text = { Text("View Thread") },
                                    onClick = {
                                        showMenu = false
                                        comment.numericId?.let { onViewThread(it) }
                                    }
                                )
                            }
                        }
                    }
                }
            } else {
                Text(
                    text = "Thread collapsed",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            HorizontalDivider(thickness = 0.5.dp, color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
        }
    }
}

@Composable
private fun CommentCutoffRow(
    comment: AO3Comment,
    onClick: () -> Unit
) {
    Surface(
        onClick = onClick,
        modifier = Modifier
            .padding(start = (comment.depth * 12).dp)
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        color = MaterialTheme.colorScheme.secondaryContainer,
        shape = MaterialTheme.shapes.small
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center
        ) {
            Text(
                text = comment.body, // "N more comments in this thread"
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSecondaryContainer
            )
        }
    }
}

/**
 * Previous / Page X of Y / Next — same visual pattern as AccountScreen's
 * private PaginationControls (replicated here so we don't touch that file).
 */
@Composable
private fun PaginationControls(page: Int, totalPages: Int, onLoadPage: (Int) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
        OutlinedButton(
            enabled = page > 1,
            onClick = { onLoadPage(page - 1) },
            modifier = Modifier.weight(1f)
        ) {
            Text("Previous")
        }
        Text(
            text = "Page $page of $totalPages",
            modifier = Modifier
                .weight(1f)
                .padding(top = 12.dp),
            style = MaterialTheme.typography.labelLarge,
            textAlign = TextAlign.Center
        )
        OutlinedButton(
            enabled = page < totalPages,
            onClick = { onLoadPage(page + 1) },
            modifier = Modifier.weight(1f)
        ) {
            Text("Next")
        }
    }
}

@Composable
private fun ChapterScopePicker(
    currentTarget: AO3CommentTarget?,
    initialTarget: AO3CommentTarget?,
    onSelectTarget: (AO3CommentTarget) -> Unit,
    modifier: Modifier = Modifier
) {
    if (currentTarget == null) return
    val workId = currentTarget.workId
    val chapterTarget = (initialTarget as? AO3CommentTarget.Chapter)
        ?: (currentTarget as? AO3CommentTarget.Chapter)
    
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        FilterChip(
            selected = currentTarget is AO3CommentTarget.Work,
            onClick = { onSelectTarget(AO3CommentTarget.Work(workId)) },
            label = { Text("All Comments") }
        )
        if (chapterTarget != null) {
            FilterChip(
                selected = currentTarget is AO3CommentTarget.Chapter,
                onClick = { onSelectTarget(chapterTarget) },
                label = { Text("Chapter ${chapterTarget.chapterId}") }
            )
        }
    }
}

private fun AO3Error.displayMessage(): String {
    return when (this) {
        AO3Error.BadRequest -> "AO3 rejected the request."
        AO3Error.AuthenticationRequired -> "AO3 requires login."
        AO3Error.Forbidden -> "AO3 denied access."
        AO3Error.NotFound -> "AO3 could not find these comments."
        is AO3Error.Http -> "AO3 returned HTTP $statusCode."
        is AO3Error.Network -> message
        is AO3Error.Overloaded -> "AO3 is busy. Try again shortly."
        is AO3Error.Parse -> message
        is AO3Error.RateLimited -> "AO3 is rate-limiting requests. Try again shortly."
        is AO3Error.Server -> "AO3 had a server problem (HTTP $statusCode)."
        is AO3Error.Validation -> message
    }
}
