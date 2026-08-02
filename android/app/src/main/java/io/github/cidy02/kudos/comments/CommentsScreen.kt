package io.github.cidy02.kudos.comments

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.comments.AO3Comment
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentParticipantRole
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentRepository
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentTarget
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentThread
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentWorkAuthor
import io.github.cidy02.kudos.ui.components.CommentAvatar
import io.github.cidy02.kudos.ui.components.CommentParticipantBadge
import kotlinx.coroutines.launch

@Composable
fun CommentsScreen(
    target: AO3CommentTarget?,
    repository: AO3CommentRepository,
    onLogin: () -> Unit,
    currentUsername: String? = null
) {
    var state by remember(target) { mutableStateOf<CommentsUiState>(CommentsUiState.Loading) }
    var draft by remember { mutableStateOf("") }
    var submitting by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    fun load() {
        val currentTarget = target
        if (currentTarget == null) {
            state = CommentsUiState.Error("Open comments from a work first.")
            return
        }
        scope.launch {
            state = CommentsUiState.Loading
            state = when (val result = repository.loadThread(currentTarget)) {
                is AO3Result.Failure -> result.error.toCommentsState()
                is AO3Result.Success -> CommentsUiState.Loaded(result.value)
            }
        }
    }

    LaunchedEffect(target) {
        draft = ""
        message = null
        load()
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
                OutlinedButton(onClick = ::load) { Text("Retry") }
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
                OutlinedButton(onClick = ::load) { Text("Retry") }
            }
        }
        is CommentsUiState.Loaded -> {
            val thread = current.thread
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(horizontal = 20.dp, vertical = 16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                item {
                    CommentComposer(
                        thread = thread,
                        draft = draft,
                        submitting = submitting,
                        onDraft = { draft = it },
                        onLogin = onLogin,
                        onSubmit = {
                            val currentTarget = target ?: return@CommentComposer
                            scope.launch {
                                submitting = true
                                message = null
                                when (val result = repository.submitComment(currentTarget, draft)) {
                                    is AO3Result.Failure -> {
                                        if (result.error == AO3Error.AuthenticationRequired) {
                                            state = CommentsUiState.AuthRequired(
                                                "Log in to AO3 before commenting."
                                            )
                                        } else if (result.error is AO3Error.Network) {
                                            // A network-layer failure (timeout, dropped
                                            // connection) is ambiguous: the POST may have
                                            // already reached AO3 before the response was
                                            // lost. Reload the thread instead of silently
                                            // inviting an immediate resubmit that could
                                            // double-post.
                                            message =
                                                "Couldn't confirm this posted — reloading the " +
                                                    "thread before you try again."
                                            load()
                                        } else {
                                            message = result.error.displayMessage()
                                        }
                                    }
                                    is AO3Result.Success -> {
                                        draft = ""
                                        message = result.value.message
                                        load()
                                    }
                                }
                                submitting = false
                            }
                        }
                    )
                }
                message?.let { msg ->
                    item {
                        Text(msg, color = MaterialTheme.colorScheme.primary)
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
                        CommentRow(
                            comment = comment,
                            currentUsername = currentUsername,
                            workAuthors = thread.workAuthors
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
    onDraft: (String) -> Unit,
    onLogin: () -> Unit,
    onSubmit: () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        when {
            // Prefer composer when form is present (signed-in).
            thread.form != null -> {
                OutlinedTextField(
                    value = draft,
                    onValueChange = onDraft,
                    label = { Text("Leave a comment") },
                    minLines = 3,
                    modifier = Modifier.fillMaxWidth()
                )
                Button(
                    enabled = !submitting && draft.isNotBlank(),
                    onClick = onSubmit
                ) {
                    Text(if (submitting) "Posting…" else "Post Comment")
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
private fun CommentRow(
    comment: AO3Comment,
    currentUsername: String?,
    workAuthors: List<AO3CommentWorkAuthor>
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
    Row(
        modifier = Modifier.padding(start = (comment.depth * 12).dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        CommentAvatar(
            avatarUrl = comment.avatarUrl,
            isGuest = comment.isGuest
        )
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = comment.author.name,
                    style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier.weight(1f, fill = false)
                )
                CommentParticipantBadge(role = role)
            }
            if (comment.date.isNotBlank()) {
                Text(
                    comment.date,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Text(
                comment.body,
                color = if (comment.isDeletedOrHidden) {
                    MaterialTheme.colorScheme.onSurfaceVariant
                } else {
                    MaterialTheme.colorScheme.onSurface
                }
            )
            HorizontalDivider()
        }
    }
}

private sealed interface CommentsUiState {
    data object Loading : CommentsUiState
    data class Loaded(val thread: AO3CommentThread) : CommentsUiState
    data class AuthRequired(val message: String) : CommentsUiState
    data class Error(val message: String) : CommentsUiState
}

private fun AO3Error.toCommentsState(): CommentsUiState {
    return if (this == AO3Error.AuthenticationRequired) {
        CommentsUiState.AuthRequired("AO3 requires login for these comments.")
    } else {
        CommentsUiState.Error(displayMessage())
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
