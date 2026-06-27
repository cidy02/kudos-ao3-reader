package io.github.cidy02.kudos.comments

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.comments.AO3Comment
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentRepository
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentTarget
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentThread
import kotlinx.coroutines.launch

@Composable
fun CommentsScreen(
    target: AO3CommentTarget?,
    repository: AO3CommentRepository,
    onLogin: () -> Unit
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

    LaunchedEffect(target) { load() }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Text(text = "Comments", style = MaterialTheme.typography.headlineSmall)
        when (val current = state) {
            CommentsUiState.Loading -> CircularProgressIndicator()
            is CommentsUiState.AuthRequired -> {
                Text(current.message, color = MaterialTheme.colorScheme.error)
                Button(onClick = onLogin) { Text("Log in to AO3") }
            }
            is CommentsUiState.Error -> {
                Text(current.message, color = MaterialTheme.colorScheme.error)
                OutlinedButton(onClick = ::load) { Text("Retry") }
            }
            is CommentsUiState.Loaded -> {
                val thread = current.thread
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
                                        state = CommentsUiState.AuthRequired("Log in to AO3 before commenting.")
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
                message?.let { Text(it, color = MaterialTheme.colorScheme.primary) }
                HorizontalDivider()
                if (thread.comments.isEmpty()) {
                    Text("No comments yet.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                } else {
                    thread.comments.forEach { comment ->
                        CommentRow(comment)
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
            thread.form != null -> {
                OutlinedTextField(
                    value = draft,
                    onValueChange = onDraft,
                    label = { Text("Add a comment") },
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
            thread.commentsLocked -> {
                Text("AO3 is not accepting comments on this work.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            else -> {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Log in to AO3 to comment.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    OutlinedButton(onClick = onLogin) { Text("Log in") }
                }
            }
        }
    }
}

@Composable
private fun CommentRow(comment: AO3Comment) {
    Column(
        modifier = Modifier.padding(start = (comment.depth * 12).dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Text(comment.author.name, style = MaterialTheme.typography.titleSmall)
        if (comment.date.isNotBlank()) {
            Text(comment.date, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
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
