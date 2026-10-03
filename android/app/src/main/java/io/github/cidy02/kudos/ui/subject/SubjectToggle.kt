package io.github.cidy02.kudos.ui.subject

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

/**
 * iOS `UISwitch` proportions: 51×31 track, 27pt white thumb, 2pt inset.
 * On uses the accent track. Off uses a neutral glass track.
 */
@Composable
fun SubjectToggle(
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    accent: Color = LocalKudosTokens.current.accent,
    contentDescription: String? = null
) {
    val tokens = LocalKudosTokens.current
    val width = 51.dp
    val height = 31.dp
    val thumb = 27.dp
    val inset = 2.dp
    val travel = width - thumb - inset * 2
    val thumbX by animateDpAsState(if (checked) travel else 0.dp, label = "subjectToggle")
    val shape = RoundedCornerShape(percent = 50)
    val track = if (checked) accent else tokens.glassFill(0.28)
    val stroke = if (checked) Color.Transparent else tokens.glassStroke(0.35)
    Box(
        modifier
            .alpha(if (enabled) 1f else 0.4f)
            .size(width, height)
            .clip(shape)
            .background(track)
            .border(0.5.dp, stroke, shape)
            .semantics {
                if (contentDescription != null) this.contentDescription = contentDescription
            }
            .toggleable(
                value = checked,
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                enabled = enabled,
                role = Role.Switch,
                onValueChange = onCheckedChange
            )
    ) {
        Box(
            Modifier
                .align(Alignment.CenterStart)
                .offset(x = inset + thumbX)
                .size(thumb)
                .background(Color.White, CircleShape)
        )
    }
}
