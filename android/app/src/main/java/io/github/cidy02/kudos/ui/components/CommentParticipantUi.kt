package io.github.cidy02.kudos.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentParticipantRole

/**
 * Shared role chip for native Comments and (later) Inbox notification cards.
 *
 * Product intent matches iOS `CommentParticipantBadge` (Author/Me emphasized;
 * Guest neutral) expressed in Material 3 chip idiom — not a pixel clone.
 *
 * Only a role that says something gets a chip (iOS): a plain commenter is nearly
 * everyone, so "User" on each byline said nothing and crowded the name.
 */
@Composable
fun CommentParticipantBadge(
    role: AO3CommentParticipantRole,
    modifier: Modifier = Modifier
) {
    if (role == AO3CommentParticipantRole.User) return
    val emphasized = role == AO3CommentParticipantRole.Me ||
        role == AO3CommentParticipantRole.Author
    val accessibilityLabel = when (role) {
        AO3CommentParticipantRole.Me -> "Your comment"
        AO3CommentParticipantRole.Author -> "Work author"
        AO3CommentParticipantRole.User,
        AO3CommentParticipantRole.Guest -> role.label
    }
    Surface(
        modifier = modifier.semantics { contentDescription = accessibilityLabel },
        shape = MaterialTheme.shapes.small,
        color = if (emphasized) {
            MaterialTheme.colorScheme.primary
        } else {
            MaterialTheme.colorScheme.surfaceContainerHighest
        },
        contentColor = if (emphasized) {
            MaterialTheme.colorScheme.onPrimary
        } else {
            MaterialTheme.colorScheme.onSurfaceVariant
        },
        tonalElevation = 0.dp,
        border = if (emphasized) {
            null
        } else {
            BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)
        }
    ) {
        Text(
            text = role.label,
            style = MaterialTheme.typography.labelSmall.copy(
                fontWeight = if (emphasized) FontWeight.SemiBold else FontWeight.Normal
            ),
            maxLines = 1,
            modifier = Modifier.padding(horizontal = 7.dp, vertical = 2.dp)
        )
    }
}

/**
 * Circular commenter avatar (~40dp). Loads from [avatarUrl] via Coil; any load
 * failure silently falls back to a placeholder. Never shows an error state or
 * retries visibly (matches iOS `CommentAvatar`).
 *
 * The placeholder is the first letter of [name], as on iOS: most commenters have
 * no icon, and one silhouette down a whole thread told nobody apart. A guest
 * keeps the silhouette (AO3 gives a guest no identity to take a letter from).
 */
@Composable
fun CommentAvatar(
    avatarUrl: String?,
    isGuest: Boolean,
    modifier: Modifier = Modifier,
    size: Dp = 40.dp,
    name: String? = null
) {
    val initial = if (isGuest) null else avatarInitial(name)
    val imageUrl = if (isGuest) null else avatarUrl
    var showPlaceholder by remember(imageUrl) { mutableStateOf(imageUrl == null) }
    val context = LocalContext.current

    Surface(
        modifier = modifier.size(size),
        shape = CircleShape,
        color = MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = 0.5f),
        border = BorderStroke(0.5.dp, MaterialTheme.colorScheme.outlineVariant),
        tonalElevation = 0.dp
    ) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            if (imageUrl != null && !showPlaceholder) {
                AsyncImage(
                    model = ImageRequest.Builder(context)
                        .data(imageUrl)
                        .crossfade(false)
                        .build(),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .fillMaxSize()
                        .clip(CircleShape),
                    onError = {
                        // Generic avatar is the intentional fallback: an icon
                        // request must never surface an error or retry loop.
                        showPlaceholder = true
                    },
                    onSuccess = { showPlaceholder = false }
                )
            }
            if ((showPlaceholder || imageUrl == null) && initial != null) {
                // Part of the picture, so sized with the circle and not with the text size,
                // and not spoken: the name beside it is.
                Text(
                    text = initial,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontSize = with(LocalDensity.current) { (size * 0.42f).toSp() },
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    modifier = Modifier.clearAndSetSemantics {}
                )
            } else if (showPlaceholder || imageUrl == null) {
                Icon(
                    imageVector = Icons.Outlined.Person,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(size * 0.45f)
                )
            }
        }
    }
}

/**
 * The first visible character of a name, uppercased (iOS `CommentAvatar.initial`). A whole
 * character, not a code unit: AO3 names carry emoji and combining marks. Null when the name
 * has none, which leaves the silhouette.
 */
internal fun avatarInitial(name: String?): String? {
    val trimmed = name?.trim().orEmpty()
    if (trimmed.isEmpty()) return null
    val end = java.text.BreakIterator.getCharacterInstance().apply { setText(trimmed) }.next()
    return trimmed.substring(0, end).uppercase()
}
