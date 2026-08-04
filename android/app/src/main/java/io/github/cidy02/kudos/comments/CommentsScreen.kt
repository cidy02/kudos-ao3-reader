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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.ArrowRight
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
    draftStore: CommentDraftStore? = null
) {
    val viewModel: CommentsViewModel = viewModel(
        key = target?.workId?.toString(),
        factory = CommentsViewModel.factory(repository, target, draftStore, currentUsername)
    )
    val state by viewModel.state.collectAsState()
    val draft by viewModel.draft.collectAsState()
    val submitting by viewModel.submitting.collectAsState()
    val message by viewModel.message.collectAsState()
    val currentTarget by viewModel.currentTarget.collectAsState()
    val focusedCommentId by viewModel.focusedCommentId.collectAsState()
    
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()

    fun startReply(comment: AO3Comment) {
        val id = comment.numericId ?: return
        // Ideally ViewModel should handle this state, but keeping it simple for now.
        // viewModel.startReply(comment)
    }

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
                item {
                    // Show target picker if multiple chapters available.
                    // (Requires more data in thread model).
                    
                    CommentComposer(
                        thread = thread,
                        draft = draft,
                        submitting = submitting,
                        replyTarget = null, // Later: VM managed
                        onDraft = viewModel::updateDraft,
                        onCancelReply = { },
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
                            onReply = { /* viewModel.startReply(it) */ },
                            onLoadMore = { viewModel.load() },
                            onViewThread = { commentId -> viewModel.load(focusedId = commentId) }
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
    onDraft: (String) -> Unit,
    onCancelReply: () -> Unit,
    onLogin: () -> Unit,
    onSubmit: () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        when {
            // Prefer composer when form is present (signed-in).
            thread.form != null -> {
                if (replyTarget != null) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "Replying to ${replyTarget.authorName}",
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.weight(1f)
                        )
                        TextButton(onClick = onCancelReply) {
                            Text("Cancel")
                        }
                    }
                }
                OutlinedTextField(
                    value = draft,
                    onValueChange = onDraft,
                    label = {
                        Text(
                            if (replyTarget != null) "Write a reply" else "Leave a comment"
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
                            submitting && replyTarget != null -> "Posting reply…"
                            submitting -> "Posting…"
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
    onLoadMore: (String) -> Unit,
    onViewThread: (Long) -> Unit,
    depth: Int = 0
) {
    var expanded by remember { mutableStateOf(true) }
    val collapsedIds = remember { mutableStateMapOf<String, Boolean>() }

    Column(modifier = Modifier.fillMaxWidth()) {
        if (comment.isThreadCutoff) {
            CommentCutoffRow(comment = comment, onClick = { onLoadMore(comment.cutoffThreadPath!!) })
        } else {
            CommentRow(
                comment = comment,
                currentUsername = currentUsername,
                workAuthors = workAuthors,
                onReply = { onReply(comment) },
                isExpanded = expanded,
                onToggleExpand = { expanded = !expanded },
                depth = depth,
                onViewThread = onViewThread
            )
        }

        if (expanded && comment.replies.isNotEmpty()) {
            comment.replies.forEach { reply ->
                CommentThreadRow(
                    comment = reply,
                    currentUsername = currentUsername,
                    workAuthors = workAuthors,
                    onReply = onReply,
                    onLoadMore = onLoadMore,
                    onViewThread = onViewThread,
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
                
                Text(
                    text = comment.body,
                    style = MaterialTheme.typography.bodyMedium,
                    maxLines = if (showFullComment) Int.MAX_VALUE else 5,
                    overflow = TextOverflow.Ellipsis,
                    onTextLayout = { result -> isLongComment = result.hasVisualOverflow },
                    color = if (comment.isDeletedOrHidden) {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    } else {
                        MaterialTheme.colorScheme.onSurface
                    }
                )
                
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
