package io.github.cidy02.kudos.ui.subject

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.ui.components.coverHue
import kotlinx.coroutines.launch

enum class WorkSectionLayout { Shelves, Ledger }

object SubjectWorkCardMetrics {
    val width = 164.dp
    val height = 232.dp
    val spacing = 12.dp
}

data class WorkCardSignal(
    val text: String,
    val description: String,
    val tint: Color
)

@Composable
fun WorkCarouselSection(
    title: String,
    count: Int,
    collapsed: Boolean,
    onToggleCollapsed: () -> Unit,
    onSeeAll: (() -> Unit)?,
    emptyMessage: String,
    layout: WorkSectionLayout,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    val tokens = LocalKudosTokens.current
    Column(modifier, verticalArrangement = Arrangement.spacedBy(if (layout == WorkSectionLayout.Shelves) 5.dp else 8.dp)) {
        SectionRuleHeader(
            title = title,
            count = count,
            isCollapsed = collapsed,
            onToggleCollapse = onToggleCollapsed,
            onSeeAll = if (count > 0) onSeeAll else null
        )
        AnimatedVisibility(!collapsed) {
            if (count == 0) {
                Text(
                    text = emptyMessage,
                    color = tokens.secondaryInk,
                    fontSize = 13.sp,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                )
            } else {
                content()
            }
        }
    }
}

@Composable
fun <T> WorkCardCarousel(
    values: List<T>,
    key: (T) -> Any,
    card: @Composable (T) -> Unit
) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(SubjectWorkCardMetrics.spacing)
    ) {
        items(values, key = key) { card(it) }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun WorkLedgerRow(
    title: String,
    author: String,
    fandoms: List<String>,
    metadata: String,
    progress: Double,
    progressState: String?,
    signals: List<WorkCardSignal>,
    obscured: Boolean,
    favorite: Boolean,
    selected: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val subject = fandoms.firstOrNull { it.isNotBlank() } ?: title
    val palette = remember(subject, tokens.theme) {
        SubjectPalette.fromHue(coverHue(subject).toDouble() / 360.0, tokens.theme)
    }
    val shape = RoundedCornerShape(14.dp)
    Row(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .background(palette.rowWash)
            .border(if (selected) 2.dp else 0.5.dp, if (selected) tokens.accent else palette.rowBorder, shape)
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .padding(horizontal = 14.dp, vertical = 13.dp)
            .semantics {
                contentDescription = if (obscured) "Hidden mature work. Activate to reveal." else "$title, by $author"
            },
        horizontalArrangement = Arrangement.spacedBy(13.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        WorkProgressRing(progress, state = progressState, diameter = 44.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            SubjectKicker(
                text = HomeFacts.primaryFandom(fandoms) ?: "Library",
                palette = palette,
                trailingCount = (fandoms.count { it.isNotBlank() } - 1).coerceAtLeast(0),
                size = 9.sp,
                ruleSpacing = 4.dp
            )
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    title,
                    color = tokens.primaryInk,
                    fontSize = 16.5.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false)
                )
                if (favorite) Text("★", color = Color(0xFFFFC107), fontSize = 13.sp)
            }
            Text(
                metadata,
                color = tokens.secondaryInk,
                fontSize = 11.5.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        LedgerSignalGrid(signals.take(4), palette)
    }
}

@Composable
private fun LedgerSignalGrid(signals: List<WorkCardSignal>, palette: SubjectPalette) {
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        signals.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                row.forEach { signal ->
                    Box(
                        Modifier
                            .size(22.dp)
                            .clip(RoundedCornerShape(6.dp))
                            .background(signal.tint.copy(alpha = 0.34f))
                            .semantics { contentDescription = signal.description },
                        contentAlignment = Alignment.Center
                    ) {
                        Text(signal.text, color = palette.accentOnFill, fontSize = 8.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
    }
}

data class SwipeAction(
    val label: String,
    val icon: ImageVector,
    val color: Color,
    val onClick: () -> Unit
)

internal fun settleSwipeOffset(current: Float, leadingWidth: Float, trailingWidth: Float): Float = when {
    current > 56f && leadingWidth > 0f -> leadingWidth
    current < -56f && trailingWidth > 0f -> -trailingWidth
    else -> 0f
}

/** Partial swipe reveal: releasing never performs an action. */
@Composable
fun SwipeActionRow(
    leading: List<SwipeAction>,
    trailing: List<SwipeAction>,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    val actionWidth = 78.dp
    val density = LocalDensity.current
    val leadingPx = with(density) { (actionWidth * leading.size).toPx() }
    val trailingPx = with(density) { (actionWidth * trailing.size).toPx() }
    val offset = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    val dragState = rememberDraggableState { delta ->
        scope.launch {
            offset.snapTo((offset.value + delta).coerceIn(-trailingPx, leadingPx))
        }
    }
    Box(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
    ) {
        // Only the side being revealed is drawn: a glass card is translucent, so
        // actions drawn at rest would show through it.
        Row(Modifier.matchParentSize(), horizontalArrangement = Arrangement.SpaceBetween) {
            if (offset.value > 0f) {
                ActionButtons(leading, actionWidth) { action ->
                    action.onClick()
                    scope.launch { offset.animateTo(0f, tween(160)) }
                }
            }
            Spacer(Modifier.weight(1f))
            if (offset.value < 0f) {
                ActionButtons(trailing, actionWidth) { action ->
                    action.onClick()
                    scope.launch { offset.animateTo(0f, tween(160)) }
                }
            }
        }
        Box(
            Modifier
                .fillMaxWidth()
                .graphicsLayer { translationX = offset.value }
                .draggable(
                    state = dragState,
                    orientation = Orientation.Horizontal,
                    onDragStopped = {
                        offset.animateTo(
                            settleSwipeOffset(offset.value, leadingPx, trailingPx),
                            tween(180)
                        )
                    }
                )
        ) { content() }
    }
}

@Composable
private fun ActionButtons(actions: List<SwipeAction>, width: Dp, onClick: (SwipeAction) -> Unit) {
    Row(Modifier.fillMaxHeight()) {
        actions.forEach { action ->
            Column(
                Modifier
                    .width(width)
                    .fillMaxHeight()
                    .background(action.color)
                    .combinedClickable(onClick = { onClick(action) }),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Icon(action.icon, contentDescription = null, tint = Color.White, modifier = Modifier.size(18.dp))
                Text(action.label, color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

fun defaultWorkSignals(
    rating: String,
    categories: List<String>,
    warnings: List<String>,
    complete: Boolean
): List<WorkCardSignal> = listOf(
    WorkCardSignal(ratingShort(rating), rating.ifBlank { "Not rated" }, Color(0xFFFFC107)),
    WorkCardSignal(categories.firstOrNull()?.take(1)?.uppercase() ?: "○", categories.firstOrNull() ?: "No category", Color(0xFF35C46A)),
    WorkCardSignal(if (warnings.isEmpty()) "○" else "!", warnings.firstOrNull() ?: "No warnings", Color(0xFF8B8792)),
    WorkCardSignal(if (complete) "✓" else "…", if (complete) "Complete" else "Work in progress", Color(0xFF35C46A))
)

private fun ratingShort(rating: String): String = when {
    rating.contains("Explicit", true) -> "E"
    rating.contains("Mature", true) -> "M"
    rating.contains("Teen", true) -> "T"
    rating.contains("General", true) -> "G"
    else -> "NR"
}
