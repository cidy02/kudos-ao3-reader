package io.github.cidy02.kudos.comments

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.Reply
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Forum
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.network.ao3.comments.AO3Comment
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentParticipantRole
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentWorkAuthor
import io.github.cidy02.kudos.ui.components.CommentAvatar
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Tracks which comment row is currently being swiped so child replies can drop connecting rails.
 */
class CommentSwipeTracker {
    var swipedId by mutableStateOf<Long?>(null)
}

/**
 * Native swipe and connector actions handler.
 */
data class CommentThreadHandlers(
    val onReply: (AO3Comment) -> Unit,
    val onEdit: (AO3Comment) -> Unit,
    val onDelete: (AO3Comment) -> Unit,
    val onCopyLink: (AO3Comment) -> Unit,
    val onFocusThread: (Long) -> Unit,
    val onRequestLogin: () -> Unit,
    val onOpenAuthor: (String) -> Unit
)

/**
 * Formats AO3 timestamps to relative or short dates (iOS AO3CommentTimestamp.swift).
 */
object AO3CommentTimestamp {
    private val parseFormats = listOf(
        "EEE dd MMM yyyy hh:mma zzz",
        "EEE dd MMM yyyy h:mma zzz",
        "EEE dd MMM yyyy hh:mm a zzz",
        "EEE dd MMM yyyy HH:mm zzz",
        "dd MMM yyyy hh:mma zzz",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd"
    )

    fun parse(rawText: String): Date? {
        val normalized = rawText.replace("\u00a0", " ").trim()
        if (normalized.isEmpty()) return null
        for (format in parseFormats) {
            try {
                val formatter = SimpleDateFormat(format, Locale.US).apply {
                    timeZone = TimeZone.getTimeZone("UTC")
                }
                val date = formatter.parse(normalized)
                if (date != null) return date
            } catch (_: Exception) {}
        }
        return null
    }

    fun displayText(rawText: String): String {
        val date = parse(rawText) ?: return rawText
        val now = System.currentTimeMillis()
        val diff = now - date.time

        if (diff in 0..(24 * 60 * 60 * 1000L)) {
            val minutes = diff / (60 * 1000L)
            val hours = diff / (60 * 60 * 1000L)
            return when {
                minutes < 1 -> "just now"
                minutes < 60 -> "${minutes}m ago"
                else -> "${hours}h ago"
            }
        }

        val outFormat = SimpleDateFormat("MMM d, yyyy", Locale.getDefault())
        return outFormat.format(date)
    }
}

/**
 * Draws the vertical connector rails and curved elbows (iOS ThreadConnectors, CommentThreadRow.swift:519).
 */
@Composable
fun Modifier.threadConnectors(
    depth: Int,
    isLastSibling: Boolean,
    ancestorLines: List<Boolean>,
    leadingInset: Dp,
    topInset: Dp,
    hasChildBelow: Boolean,
    indents: List<Dp>,
    hiddenLevel: Int?,
    strokeColor: Color,
    strokeWidth: Dp = CommentThreadGeometry.railWidth
): Modifier {
    val density = LocalDensity.current
    return this.drawBehind {
        val strokePx = with(density) { strokeWidth.toPx() }
        val leadingInsetPx = with(density) { leadingInset.toPx() }
        val topInsetPx = with(density) { topInset.toPx() }
        val avatarSizePx = with(density) { CommentThreadGeometry.avatarSize(depth).toPx() }
        val avatarTopPx = topInsetPx
        val railGapPx = with(density) { CommentThreadGeometry.railAvatarGap.toPx() }

        fun railXPx(level: Int): Float {
            val levelIndentPx = with(density) {
                if (level in indents.indices) indents[level].toPx() else (indents.lastOrNull()?.toPx() ?: 0f)
            }
            val levelAvatarSizePx = with(density) { CommentThreadGeometry.avatarSize(level).toPx() }
            return leadingInsetPx + levelIndentPx + levelAvatarSizePx / 2f
        }

        // 1. This comment's own rail down towards child reply below
        if (hasChildBelow) {
            val x = railXPx(depth)
            val startY = avatarTopPx + avatarSizePx + railGapPx
            if (startY < size.height) {
                drawLine(
                    color = strokeColor,
                    start = Offset(x, startY),
                    end = Offset(x, size.height),
                    strokeWidth = strokePx
                )
            }
        }

        if (depth > 0) {
            // 2. Ancestor vertical rails running straight through this row
            for (level in 0 until minOf(depth - 1, ancestorLines.size)) {
                if (ancestorLines[level] && level != hiddenLevel) {
                    val x = railXPx(level)
                    drawLine(
                        color = strokeColor,
                        start = Offset(x, 0f),
                        end = Offset(x, size.height),
                        strokeWidth = strokePx
                    )
                }
            }

            // 3. Parent's rail elbow into this reply
            if (hiddenLevel != (depth - 1)) {
                val parentX = railXPx(depth - 1)
                val avatarLeftPx = leadingInsetPx + with(density) {
                    if (depth in indents.indices) indents[depth].toPx() else (indents.lastOrNull()?.toPx() ?: 0f)
                }
                val midY = avatarTopPx + avatarSizePx / 2f
                val run = avatarLeftPx - parentX
                val elbowRadiusPx = with(density) { CommentThreadGeometry.elbowRadius(depth).toPx() }

                val path = Path()
                path.moveTo(parentX, 0f)
                if (run > 0) {
                    val radius = minOf(elbowRadiusPx, run, midY)
                    path.lineTo(parentX, midY - radius)
                    path.quadraticTo(parentX, midY, parentX + radius, midY)
                    path.lineTo(avatarLeftPx, midY)
                } else {
                    path.lineTo(parentX, avatarTopPx)
                }
                drawPath(path, strokeColor, style = Stroke(width = strokePx))

                // If not the last child, parent's vertical rail continues past this row
                if (!isLastSibling) {
                    drawLine(
                        color = strokeColor,
                        start = Offset(parentX, 0f),
                        end = Offset(parentX, size.height),
                        strokeWidth = strokePx
                    )
                }
            }
        }
    }
}

/**
 * One row in the conversation: Post, Expander, or ContinueThread.
 */
@Composable
fun CommentConversationRow(
    row: CommentConversationRowItem,
    workAuthors: List<String>,
    workAuthorUsernames: List<String>,
    palette: SubjectPalette,
    handlers: CommentThreadHandlers,
    swipeTracker: CommentSwipeTracker,
    onExpand: () -> Unit,
    onContinueThread: () -> Unit,
    onToggleCollapse: () -> Unit,
    containerWidth: Dp,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val depth = row.depth
    val indents = remember(containerWidth, depth) {
        (0..maxOf(0, depth)).map {
            CommentThreadGeometry.indent(it, containerWidth)
        }
    }
    val currentIndent = indents.getOrElse(depth) { 0.dp }

    val topInset = if (row.startsConversation) {
        CommentThreadGeometry.conversationGap * 2
    } else {
        CommentThreadGeometry.rowTopPadding
    }

    val hiddenLevel = swipeTracker.swipedId?.let { id ->
        row.ancestorIds.indexOf(id).takeIf { it >= 0 }
    }

    val connectorModifier = Modifier.threadConnectors(
        depth = depth,
        isLastSibling = row.isLastSibling,
        ancestorLines = row.ancestorLines,
        leadingInset = CommentThreadGeometry.sideMargin,
        topInset = topInset,
        hasChildBelow = row.nextDepth == depth + 1,
        indents = indents,
        hiddenLevel = hiddenLevel,
        strokeColor = tokens.glassStroke(0.18)
    )

    Box(
        modifier = modifier
            .fillMaxWidth()
            .then(connectorModifier)
            .padding(
                top = topInset,
                start = CommentThreadGeometry.sideMargin + currentIndent,
                end = CommentThreadGeometry.sideMargin
            )
    ) {
        if (row.startsConversation) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .offset(y = -CommentThreadGeometry.conversationGap)
                    .height(0.5.dp)
                    .background(tokens.glassStroke(0.12))
            )
        }

        when (val item = row.item) {
            is CommentConversationItem.Post -> {
                CommentPostRow(
                    comment = item.comment,
                    workAuthors = workAuthors,
                    workAuthorUsernames = workAuthorUsernames,
                    depth = depth,
                    replyToAuthor = item.parentAuthor,
                    showsParentAttribution = row.showsParentAttribution,
                    parentIsViewer = item.parentIsViewer,
                    collapse = row.collapse,
                    palette = palette,
                    handlers = handlers,
                    onToggleCollapse = onToggleCollapse
                )
            }
            is CommentConversationItem.Expander -> {
                val text = if (item.showsVerb) {
                    "Show ${item.hiddenCount} more"
                } else if (item.hiddenCount == 1) {
                    "Show 1 reply"
                } else {
                    "Show ${item.hiddenCount} replies"
                }
                TextButton(
                    onClick = onExpand,
                    contentPadding = PaddingValues(0.dp),
                    modifier = Modifier.height(44.dp)
                ) {
                    Text(
                        text = text,
                        style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
                        color = palette.accent
                    )
                }
            }
            is CommentConversationItem.ContinueThread -> {
                val countText = if (item.hiddenCount == 1) "1 deeper reply" else "${item.hiddenCount} deeper replies"
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(44.dp)
                        .clickable(onClick = onContinueThread),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text(
                        text = "Continue thread",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium,
                        color = palette.accent
                    )
                    Text("·", color = tokens.tertiaryInk, fontSize = 12.sp)
                    Text(
                        text = countText,
                        fontSize = 12.sp,
                        fontFamily = FontFamily.Monospace,
                        color = tokens.secondaryInk
                    )
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                        contentDescription = null,
                        tint = palette.accent,
                        modifier = Modifier.size(14.dp)
                    )
                }
            }
        }
    }
}

/**
 * One comment post: Avatar on left, content on right.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun CommentPostRow(
    comment: AO3Comment,
    workAuthors: List<String>,
    workAuthorUsernames: List<String>,
    depth: Int,
    replyToAuthor: String?,
    showsParentAttribution: Boolean,
    parentIsViewer: Boolean,
    collapse: CommentCollapseState?,
    palette: SubjectPalette,
    handlers: CommentThreadHandlers,
    onToggleCollapse: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    val avatarSize = CommentThreadGeometry.avatarSize(depth)
    val spacing = CommentThreadGeometry.avatarContentSpacing(depth)

    val participantRole = remember(comment, workAuthors, workAuthorUsernames) {
        AO3CommentParticipantRole.resolve(
            name = comment.author.name,
            isGuest = comment.isGuest,
            isAnonymousCreator = comment.isAnonymousCreator,
            commenterUsername = comment.author.username,
            workAuthors = workAuthors,
            workAuthorUsernames = workAuthorUsernames
        )
    }

    val timestamp = remember(comment.date) {
        AO3CommentTimestamp.displayText(comment.date)
    }

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(spacing),
        verticalAlignment = Alignment.Top
    ) {
        // Avatar
        Box(
            modifier = Modifier
                .size(avatarSize)
                .then(
                    if (comment.author.username != null) {
                        Modifier
                            .clickable { handlers.onOpenAuthor(comment.author.username) }
                            .semantics { contentDescription = "View ${comment.author.name}'s profile" }
                    } else Modifier
                )
        ) {
            CommentAvatar(
                avatarUrl = comment.avatarUrl,
                isGuest = comment.isGuest,
                size = avatarSize
            )
        }

        // Content
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            // Byline: Name, Role chip, timestamp, chapter badge, collapse pill.
            val nameAndRole: @Composable RowScope.() -> Unit = {
                // Name
                Text(
                    text = comment.author.name,
                    fontSize = if (depth == 0) 14.sp else 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = if (participantRole == AO3CommentParticipantRole.Author) {
                        palette.accent
                    } else {
                        tokens.primaryInk
                    },
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier
                        .weight(1f, fill = false)
                        .then(
                            if (comment.author.username != null) {
                                Modifier.clickable { handlers.onOpenAuthor(comment.author.username) }
                            } else Modifier
                        )
                )

                // Role badge: Author / Me only
                if (participantRole != AO3CommentParticipantRole.User && participantRole != AO3CommentParticipantRole.Guest) {
                    CommentParticipantBadge(role = participantRole, palette = palette)
                }
            }
            val meta: @Composable () -> Unit = {
                if (timestamp.isNotEmpty()) {
                    Text(
                        text = timestamp,
                        fontSize = 11.sp,
                        color = tokens.secondaryInk,
                        maxLines = 1
                    )
                }

                if (comment.chapterLabel != null && comment.chapterLabel.isNotBlank()) {
                    Surface(
                        shape = RoundedCornerShape(percent = 50),
                        color = tokens.glassFill(0.12)
                    ) {
                        Text(
                            text = comment.chapterLabel,
                            fontSize = 10.sp,
                            color = tokens.secondaryInk,
                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                        )
                    }
                }

                if (collapse != null) {
                    Surface(
                        shape = RoundedCornerShape(percent = 50),
                        color = tokens.glassFill(0.12),
                        modifier = Modifier.clickable(onClick = onToggleCollapse)
                    ) {
                        Text(
                            text = collapse.label,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = tokens.secondaryInk,
                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp)
                        )
                    }
                }
            }
            if (isAccessibilityFontScale()) {
                // At large text the date, the chapter and Hide are wider than the row by themselves,
                // and the row was as tall as the avatar: the name was squeezed to a letter or out,
                // and the rest was cut in half (iOS had the same line run off the screen: T-373).
                // The name takes its own line and the rest wraps under it.
                Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp), content = nameAndRole)
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                        itemVerticalAlignment = Alignment.CenterVertically) { meta() }
                }
            } else {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = avatarSize),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    // The name's block takes the room that is left, so the name is cut short only when
                    // the line is really full. With a weighted gap beside it the two split that room
                    // in half, and "Calytrix" was drawn "Calyt…" next to empty space.
                    Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp), content = nameAndRole)
                    meta()
                }
            }

            // Parent attribution
            if (parentIsViewer && participantRole != AO3CommentParticipantRole.Me) {
                Text(
                    text = "REPLYING TO YOU",
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 0.8.sp,
                    color = palette.accent
                )
            } else if (showsParentAttribution && !replyToAuthor.isNullOrEmpty()) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.Reply,
                        contentDescription = null,
                        tint = tokens.secondaryInk,
                        modifier = Modifier.size(12.dp)
                    )
                    Text(
                        text = "in reply to $replyToAuthor",
                        fontSize = 11.sp,
                        color = tokens.secondaryInk,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }

            // Comment Body
            if (comment.isDeletedOrHidden) {
                Text(
                    text = if (comment.body.isEmpty()) "(Previous comment deleted.)" else comment.body,
                    fontSize = 13.sp,
                    fontStyle = FontStyle.Italic,
                    color = tokens.secondaryInk,
                    modifier = Modifier.padding(vertical = 2.dp)
                )
            } else if (comment.isThreadCutoff) {
                val cutoffText = comment.cutoffCount?.let {
                    "$it more ${if (it == 1) "comment" else "comments"} in this thread"
                } ?: "More comments in this thread"
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text(
                        text = cutoffText,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Medium,
                        color = palette.accent
                    )
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                        contentDescription = null,
                        tint = palette.accent,
                        modifier = Modifier.size(14.dp)
                    )
                }
            } else {
                ExpandableCommentBody(text = comment.body)
            }

            // Action strip (Reply leading, Overflow trailing)
            CommentActionRowLayout(
                comment = comment,
                palette = palette,
                handlers = handlers
            )
        }
    }
}

/**
 * Role badge for comments (Author / Me).
 */
@Composable
fun CommentParticipantBadge(
    role: AO3CommentParticipantRole,
    palette: SubjectPalette,
    modifier: Modifier = Modifier
) {
    val isAuthor = role == AO3CommentParticipantRole.Author
    val isMe = role == AO3CommentParticipantRole.Me
    if (!isAuthor && !isMe) return

    val label = role.label
    val tokens = LocalKudosTokens.current

    Surface(
        shape = RoundedCornerShape(percent = 50),
        color = palette.accent,
        modifier = modifier
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 7.dp, vertical = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(3.dp)
        ) {
            if (isAuthor) {
                Icon(
                    imageVector = Icons.Outlined.Person,
                    contentDescription = null,
                    tint = palette.solidButtonLabel,
                    modifier = Modifier.size(11.dp)
                )
            }
            Text(
                text = label,
                fontSize = 10.sp,
                fontWeight = FontWeight.SemiBold,
                color = palette.solidButtonLabel
            )
        }
    }
}

/**
 * Expandable body clamped to 5 lines with "Read more" / "Show less" toggle.
 */
@Composable
fun ExpandableCommentBody(text: String) {
    val tokens = LocalKudosTokens.current
    var isExpanded by remember { mutableStateOf(false) }
    var hasOverflow by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .animateContentSize(),
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Text(
            text = text,
            fontSize = 14.sp,
            lineHeight = 21.sp,
            color = tokens.primaryInk.copy(alpha = 0.85f),
            maxLines = if (isExpanded) Int.MAX_VALUE else CommentThreadGeometry.collapsedBodyLineLimit,
            overflow = TextOverflow.Ellipsis,
            onTextLayout = { result ->
                if (!isExpanded) {
                    hasOverflow = result.hasVisualOverflow || result.lineCount > CommentThreadGeometry.collapsedBodyLineLimit
                }
            }
        )

        if (hasOverflow) {
            Text(
                text = if (isExpanded) "Show less" else "Read more",
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                color = tokens.secondaryInk,
                modifier = Modifier
                    .clickable { isExpanded = !isExpanded }
                    .padding(vertical = 4.dp)
            )
        }
    }
}

/**
 * Action strip under comment (Reply leading, More menu trailing).
 */
@Composable
fun CommentActionRowLayout(
    comment: AO3Comment,
    palette: SubjectPalette,
    handlers: CommentThreadHandlers
) {
    val clipboard = LocalClipboardManager.current
    var showMenu by remember { mutableStateOf(false) }
    val tokens = LocalKudosTokens.current
    val canReply = comment.canReply && comment.numericId != null

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(if (canReply) 40.dp else 28.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (canReply) {
            Row(
                modifier = Modifier
                    .height(44.dp)
                    .clickable { handlers.onReply(comment) }
                    .padding(end = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.Reply,
                    contentDescription = null,
                    tint = palette.accent,
                    modifier = Modifier.size(14.dp)
                )
                Text(
                    text = "Reply",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                    color = palette.accent
                )
            }
        }

        Spacer(Modifier.weight(1f))

        Box {
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clickable { showMenu = true },
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.MoreHoriz,
                    contentDescription = "More actions for ${comment.author.name}'s comment",
                    tint = tokens.secondaryInk,
                    modifier = Modifier.size(18.dp)
                )
            }

            DropdownMenu(
                expanded = showMenu,
                onDismissRequest = { showMenu = false }
            ) {
                if (canReply) {
                    DropdownMenuItem(
                        text = { Text("Reply") },
                        leadingIcon = {
                            Icon(Icons.AutoMirrored.Filled.Reply, contentDescription = null)
                        },
                        onClick = {
                            showMenu = false
                            handlers.onReply(comment)
                        }
                    )
                } else if (comment.canReply) {
                    DropdownMenuItem(
                        text = { Text("Log in to Reply") },
                        leadingIcon = {
                            Icon(Icons.Outlined.Person, contentDescription = null)
                        },
                        onClick = {
                            showMenu = false
                            handlers.onRequestLogin()
                        }
                    )
                }

                if (comment.editPath != null) {
                    DropdownMenuItem(
                        text = { Text("Edit Comment") },
                        leadingIcon = {
                            Icon(Icons.Outlined.Edit, contentDescription = null)
                        },
                        onClick = {
                            showMenu = false
                            handlers.onEdit(comment)
                        }
                    )
                }

                DropdownMenuItem(
                    text = { Text("Copy Link") },
                    leadingIcon = {
                        Icon(Icons.Outlined.Link, contentDescription = null)
                    },
                    onClick = {
                        showMenu = false
                        handlers.onCopyLink(comment)
                    }
                )

                if (comment.threadPath != null || comment.numericId != null) {
                    DropdownMenuItem(
                        text = { Text("Thread") },
                        leadingIcon = {
                            Icon(Icons.Outlined.Forum, contentDescription = null)
                        },
                        onClick = {
                            showMenu = false
                            val id = comment.numericId ?: return@DropdownMenuItem
                            handlers.onFocusThread(id)
                        }
                    )
                }

                if (comment.parentCommentId != null) {
                    DropdownMenuItem(
                        text = { Text("Parent Thread") },
                        leadingIcon = {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                        },
                        onClick = {
                            showMenu = false
                            handlers.onFocusThread(comment.parentCommentId)
                        }
                    )
                }

                if (comment.deletePath != null) {
                    DropdownMenuItem(
                        text = { Text("Delete Comment", color = MaterialTheme.colorScheme.error) },
                        leadingIcon = {
                            Icon(Icons.Outlined.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                        },
                        onClick = {
                            showMenu = false
                            handlers.onDelete(comment)
                        }
                    )
                }
            }
        }
    }
}

/**
 * Comment skeleton placeholder row (iOS CommentSkeletonRow).
 */
@Composable
fun CommentSkeletonRow(modifier: Modifier = Modifier) {
    val tokens = LocalKudosTokens.current
    val barColor = tokens.glassFill(0.18)
    val avatarSize = CommentThreadGeometry.avatarSize(0)

    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(
                top = CommentThreadGeometry.rowTopPadding,
                bottom = CommentThreadGeometry.conversationGap,
                start = CommentThreadGeometry.sideMargin,
                end = CommentThreadGeometry.sideMargin
            ),
        horizontalArrangement = Arrangement.spacedBy(11.dp),
        verticalAlignment = Alignment.Top
    ) {
        Box(
            Modifier
                .size(avatarSize)
                .background(barColor, CircleShape)
        )
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    Modifier
                        .width(110.dp)
                        .height(12.dp)
                        .background(barColor, RoundedCornerShape(4.dp))
                )
                Box(
                    Modifier
                        .width(60.dp)
                        .height(10.dp)
                        .background(barColor, RoundedCornerShape(4.dp))
                )
            }
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(12.dp)
                    .background(barColor, RoundedCornerShape(4.dp))
            )
            Box(
                Modifier
                    .fillMaxWidth(0.9f)
                    .height(12.dp)
                    .background(barColor, RoundedCornerShape(4.dp))
            )
            Box(
                Modifier
                    .width(140.dp)
                    .height(12.dp)
                    .background(barColor, RoundedCornerShape(4.dp))
            )
        }
    }
}

/**
 * Apple-styled unavailable / empty state view (iOS ContentUnavailableView).
 */
@Composable
fun ContentUnavailableView(
    title: String,
    description: String,
    icon: ImageVector = Icons.Outlined.ChatBubbleOutline,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
    palette: SubjectPalette? = null,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 32.dp, vertical = 48.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = tokens.secondaryInk,
            modifier = Modifier.size(48.dp)
        )
        Text(
            text = title,
            fontSize = 20.sp,
            fontWeight = FontWeight.Bold,
            color = tokens.primaryInk,
            textAlign = TextAlign.Center
        )
        Text(
            text = description,
            fontSize = 14.sp,
            color = tokens.secondaryInk,
            textAlign = TextAlign.Center,
            lineHeight = 20.sp
        )
        if (actionLabel != null && onAction != null) {
            Spacer(Modifier.height(4.dp))
            Button(
                onClick = onAction,
                colors = ButtonDefaults.buttonColors(
                    containerColor = palette?.accent ?: tokens.accent,
                    contentColor = palette?.labelOnAccent ?: Color.White
                ),
                shape = RoundedCornerShape(percent = 50)
            ) {
                Text(
                    text = actionLabel,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
    }
}
