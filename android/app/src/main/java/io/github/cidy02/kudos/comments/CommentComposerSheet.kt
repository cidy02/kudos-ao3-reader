package io.github.cidy02.kudos.comments

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.network.ao3.comments.AO3Comment
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectPalette

private const val AO3_COMMENT_CHARACTER_LIMIT = 10_000

/**
 * Reply / top-level comment sheet — matching iOS `CommentComposerSheet` (CommentsView.swift:1157).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CommentComposerSheet(
    replyTarget: AO3Comment?,
    editTarget: AO3Comment?,
    draft: String,
    onDraftChange: (String) -> Unit,
    submitting: Boolean,
    currentUsername: String?,
    isScopeByChapter: Boolean,
    palette: SubjectPalette,
    onDismiss: () -> Unit,
    onSubmit: () -> Unit,
    onOpenAuthor: (String) -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val tokens = LocalKudosTokens.current

    var textFieldValue by remember {
        mutableStateOf(TextFieldValue(draft, TextRange(draft.length)))
    }
    var showFormattingTray by remember { mutableStateOf(false) }

    LaunchedEffect(draft) {
        if (draft != textFieldValue.text) {
            textFieldValue = textFieldValue.copy(text = draft)
        }
    }

    val isReply = replyTarget != null
    val isEdit = editTarget != null

    val remainingCharacters = AO3_COMMENT_CHARACTER_LIMIT - textFieldValue.text.length
    val canPost = !submitting &&
        textFieldValue.text.trim().isNotEmpty() &&
        remainingCharacters >= 0 &&
        currentUsername != null

    val title = when {
        isEdit -> "Edit comment"
        isReply -> "Reply to ${replyTarget.author.name}"
        else -> "New comment"
    }

    val confirmationAction = if (isEdit) "Save" else "Post"

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = tokens.background
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .fillMaxHeight(0.85f)
        ) {
            // Header bar: Cancel, Title, Post/Save
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                TextButton(
                    onClick = onDismiss,
                    enabled = !submitting
                ) {
                    Text(
                        text = "Cancel",
                        fontSize = 16.sp,
                        color = if (submitting) tokens.secondaryInk else palette.accent
                    )
                }

                Text(
                    text = title,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = tokens.primaryInk
                )

                TextButton(
                    onClick = onSubmit,
                    enabled = canPost
                ) {
                    if (submitting) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp),
                            strokeWidth = 2.dp,
                            color = palette.accent
                        )
                    } else {
                        Text(
                            text = confirmationAction,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold,
                            color = if (canPost) palette.accent else tokens.secondaryInk
                        )
                    }
                }
            }

            if (replyTarget != null) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 6.dp)
                        .height(androidx.compose.foundation.layout.IntrinsicSize.Min)
                        .background(tokens.glassFill(0.06), RoundedCornerShape(11.dp))
                ) {
                    Box(
                        Modifier
                            .width(2.dp)
                            .fillMaxHeight()
                            .background(palette.accent)
                    )
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 12.dp, vertical = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(3.dp)
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Text(
                                text = replyTarget.author.name,
                                fontSize = 12.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = palette.accent,
                                modifier = Modifier.clickable {
                                    replyTarget.author.username?.let(onOpenAuthor)
                                }
                            )
                            if (replyTarget.chapterLabel != null && replyTarget.chapterLabel.isNotBlank()) {
                                Text(
                                    text = "· ${replyTarget.chapterLabel}",
                                    fontSize = 12.sp,
                                    color = tokens.secondaryInk
                                )
                            }
                        }
                        Text(
                            text = replyTarget.body,
                            fontSize = 12.5.sp,
                            lineHeight = 17.sp,
                            color = tokens.secondaryInk,
                            maxLines = 3
                        )
                    }
                }
            }

            // Multiline Editor taking remaining room
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp)
            ) {
                if (textFieldValue.text.isEmpty()) {
                    Text(
                        text = if (isReply) "Write your reply…" else "Share your thoughts…",
                        fontSize = 15.sp,
                        lineHeight = 22.sp,
                        color = tokens.secondaryInk
                    )
                }

                BasicTextField(
                    value = textFieldValue,
                    onValueChange = {
                        textFieldValue = it
                        onDraftChange(it.text)
                    },
                    textStyle = TextStyle(
                        fontSize = 15.sp,
                        lineHeight = 22.sp,
                        color = tokens.primaryInk
                    ),
                    cursorBrush = SolidColor(palette.accent),
                    modifier = Modifier.fillMaxWidth()
                )
            }

            // Honesty note & identity row & drag taller footer
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 6.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                if (!isReply && !isEdit && isScopeByChapter) {
                    Text(
                        text = "New comments post to the whole work. AO3 shows them on its latest chapter.",
                        fontSize = 11.sp,
                        color = tokens.secondaryInk
                    )
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = currentUsername?.let { "as $it" } ?: "Not signed in",
                        fontSize = 11.5.sp,
                        color = tokens.secondaryInk
                    )
                    Text(
                        text = "$remainingCharacters left",
                        fontSize = 11.5.sp,
                        fontFamily = FontFamily.Monospace,
                        color = if (remainingCharacters < 0) MaterialTheme.colorScheme.error else tokens.secondaryInk
                    )
                }

                Text(
                    text = "Drag the sheet taller",
                    fontSize = 11.sp,
                    color = tokens.secondaryInk
                )
            }

            // Format bar directly above the bottom inset
            CommentFormatBar(
                value = textFieldValue,
                onValueChange = {
                    textFieldValue = it
                    onDraftChange(it.text)
                },
                onOpenTray = { showFormattingTray = true }
            )
        }

        if (showFormattingTray) {
            CommentFormattingTray(
                value = textFieldValue,
                onValueChange = {
                    textFieldValue = it
                    onDraftChange(it.text)
                },
                onDismiss = { showFormattingTray = false }
            )
        }
    }
}
