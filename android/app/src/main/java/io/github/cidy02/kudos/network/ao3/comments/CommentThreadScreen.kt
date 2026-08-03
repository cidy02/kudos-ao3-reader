package io.github.cidy02.kudos.network.ao3.comments

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.ui.components.CommentAvatar
import io.github.cidy02.kudos.ui.components.CommentParticipantBadge

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CommentThreadScreen(
    thread: AO3CommentThread,
    currentUsername: String?,
    onReply: (AO3Comment) -> Unit,
    replyParent: AO3Comment?,
    onCancelReply: () -> Unit,
    replyDraft: String,
    onReplyDraftChange: (String) -> Unit,
    onSubmitReply: (String?) -> Unit // Optional pseudId
) {
    var replyDialogVisible by remember(replyParent) { mutableStateOf(replyParent != null) }
    var pseudId by remember { mutableStateOf("") }
    
    LaunchedEffect(replyParent) {
        if (replyParent != null) replyDialogVisible = true
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        items(
            items = thread.comments,
            key = { it.id ?: "${it.author.name}-${it.date}-${it.body.hashCode()}" }
        ) { comment ->
            CommentTreeNode(
                comment = comment,
                currentUsername = currentUsername,
                workAuthors = thread.workAuthors,
                onReply = onReply
            )
        }
    }

    if (replyDialogVisible && replyParent != null) {
        AlertDialog(
            onDismissRequest = {
                replyDialogVisible = false
                onCancelReply()
            },
            title = { Text("Replying to ${replyParent.author.name}") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        text = replyParent.body,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 3
                    )
                    OutlinedTextField(
                        value = replyDraft,
                        onValueChange = onReplyDraftChange,
                        label = { Text("Your reply") },
                        minLines = 3,
                        modifier = Modifier.fillMaxWidth()
                    )
                    // Pseud selector
                    OutlinedTextField(
                        value = pseudId,
                        onValueChange = { pseudId = it },
                        label = { Text("Pseud ID (Optional)") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        replyDialogVisible = false
                        onSubmitReply(pseudId.takeIf { it.isNotBlank() })
                    },
                    enabled = replyDraft.isNotBlank()
                ) {
                    Text("Post Reply")
                }
            },
            dismissButton = {
                TextButton(
                    onClick = {
                        replyDialogVisible = false
                        onCancelReply()
                    }
                ) {
                    Text("Cancel")
                }
            }
        )
    }
}

@Composable
fun CommentTreeNode(
    comment: AO3Comment,
    currentUsername: String?,
    workAuthors: List<AO3CommentWorkAuthor>,
    onReply: (AO3Comment) -> Unit,
    depth: Int = 0
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = (depth * 12).dp)
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
        
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
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
                if (comment.canReply && comment.numericId != null) {
                    TextButton(
                        onClick = { onReply(comment) },
                        contentPadding = PaddingValues(horizontal = 0.dp, vertical = 0.dp)
                    ) {
                        Text("Reply")
                    }
                }
                HorizontalDivider()
            }
        }
        
        // Recursive children
        if (comment.replies.isNotEmpty()) {
            Spacer(modifier = Modifier.height(8.dp))
            comment.replies.forEach { child ->
                CommentTreeNode(
                    comment = child,
                    currentUsername = currentUsername,
                    workAuthors = workAuthors,
                    onReply = onReply,
                    depth = depth + 1
                )
            }
        }
    }
}
