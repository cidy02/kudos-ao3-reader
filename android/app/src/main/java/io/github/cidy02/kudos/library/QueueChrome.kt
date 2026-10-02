package io.github.cidy02.kudos.library

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.DragHandle
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.ReaderTheme
import io.github.cidy02.kudos.ui.subject.SubjectChip
import io.github.cidy02.kudos.ui.subject.SubjectChipStyle
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.parseStoredColor
import io.github.cidy02.kudos.ui.subject.withOpacity
import kotlin.math.roundToInt

fun queuePalette(theme: ReaderTheme, queue: ReadingQueue): SubjectPalette {
    val picked = queue.colorHex?.let(::parseStoredColor)
    if (picked != null) return SubjectPalette.fromColor(picked, theme)
    return SubjectPalette.fromHue(ReadingQueueFacts.displayHue(queue), theme)
}

@Composable
fun QueueProgressStrip(
    progress: QueueProgress,
    palette: SubjectPalette,
    modifier: Modifier = Modifier,
    height: androidx.compose.ui.unit.Dp = 5.dp,
    gap: androidx.compose.ui.unit.Dp = 3.dp
) {
    Canvas(
        modifier
            .fillMaxWidth()
            .height(height)
            .clip(CircleShape)
    ) {
        val count = progress.total
        if (count <= 0) return@Canvas
        val spacing = if (count > 40) 0f else gap.toPx()
        val width = (size.width - spacing * (count - 1)) / count
        val radius = if (spacing == 0f) 0f else size.height / 2f
        for (index in 0 until count) {
            val rect = androidx.compose.ui.geometry.Rect(
                Offset(index * (width + spacing), 0f),
                Size(width, size.height)
            )
            drawRoundRect(palette.accent.withOpacity(0.22), rect.topLeft, rect.size, CornerRadius(radius, radius))
            val fill = when {
                index < progress.finished -> 1f
                index < progress.finished + progress.inProgress -> 0.45f
                else -> 0f
            }
            if (fill > 0f) {
                drawRoundRect(
                    palette.accent,
                    rect.topLeft,
                    Size(rect.width * fill, rect.height),
                    CornerRadius(radius, radius)
                )
            }
        }
    }
}

/** 44dp 2×2 peek of the first four works, each in that work's own colour. */
@Composable
fun QueuePeekTile(works: List<SavedWork>, modifier: Modifier = Modifier) {
    val tokens = LocalKudosTokens.current
    val shape = RoundedCornerShape(9.dp)
    Box(
        modifier
            .size(44.dp)
            .clip(shape)
            .background(tokens.glassFill(0.08))
            .border(0.5.dp, tokens.glassStroke(0.14), shape)
            .padding(3.dp)
    ) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(2.5.dp)) {
            repeat(2) { row ->
                Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(2.5.dp)) {
                    repeat(2) { column ->
                        val index = row * 2 + column
                        val work = works.getOrNull(index)
                        val cell = RoundedCornerShape(4.dp)
                        val color = if (work == null) {
                            tokens.primaryInk.withOpacity(0.05)
                        } else {
                            SubjectPalette.fromHue(
                                ReadingQueueFacts.coverHue(
                                    work.workFandoms.firstOrNull { it.isNotBlank() } ?: work.title
                                ),
                                tokens.theme
                            ).accent.withOpacity(0.4)
                        }
                        Box(Modifier.weight(1f).fillMaxSize().clip(cell).background(color))
                    }
                }
            }
        }
    }
}

@Composable
fun QueueRowTagLabel(text: String, dashed: Boolean = false, modifier: Modifier = Modifier) {
    val tokens = LocalKudosTokens.current
    val shape = RoundedCornerShape(6.dp)
    Text(
        text = text.uppercase(),
        modifier = modifier
            .then(
                if (dashed) {
                    Modifier.border(0.75.dp, tokens.tertiaryInk, shape)
                } else {
                    Modifier.background(tokens.primaryInk.withOpacity(0.08), shape)
                }
            )
            .padding(horizontal = 7.dp, vertical = 3.dp),
        color = tokens.secondaryInk,
        fontSize = 9.5.sp,
        fontWeight = FontWeight.SemiBold,
        letterSpacing = 0.4.sp,
        maxLines = 1
    )
}

@Composable
fun QueueSelectionStatusRow(queueName: String, selectedCount: Int, total: Int, modifier: Modifier = Modifier) {
    val tokens = LocalKudosTokens.current
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = queueName.uppercase(),
            color = tokens.secondaryInk,
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            letterSpacing = 1.4.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Box(Modifier.weight(1f).size(height = 0.5.dp, width = 0.dp).background(tokens.primaryInk.withOpacity(0.14)))
        Text(
            text = "$selectedCount / $total",
            color = tokens.secondaryInk,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold
        )
    }
}

@Composable
fun WorkLedgerCard(work: SavedWork, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val tokens = LocalKudosTokens.current
    val palette = SubjectPalette.fromHue(
        ReadingQueueFacts.coverHue(work.workFandoms.firstOrNull { it.isNotBlank() } ?: work.title),
        tokens.theme
    )
    val shape = RoundedCornerShape(SubjectMetrics.rowRadius)
    Box(
        modifier
            .clip(shape)
            .background(tokens.theme.cardSurface)
            .background(palette.rowWash)
            .border(0.5.dp, palette.rowBorder, shape)
    ) { content() }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun QueueHeaderDetails(
    works: List<SavedWork>,
    preservedIds: Set<String>,
    tags: List<String>,
    palette: SubjectPalette,
    quickFilter: QueueQuickFilter,
    onQuickFilter: (QueueQuickFilter) -> Unit,
    onAddTag: () -> Unit,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val progress = ReadingQueueFacts.progress(works)
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (works.isNotEmpty()) {
            Column(Modifier.padding(horizontal = SubjectMetrics.headerGutter), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                QueueProgressStrip(progress, palette)
                Text(
                    text = ReadingQueueFacts.legend(progress, preservedIds.size),
                    color = tokens.secondaryInk,
                    fontSize = 11.5.sp
                )
            }
        }
        FlowRow(
            modifier = Modifier.padding(horizontal = SubjectMetrics.headerGutter).fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            tags.sorted().forEach { name -> QueueRowTagLabel(name) }
            Box(Modifier.clickable(onClick = onAddTag)) { QueueRowTagLabel("+ Tag", dashed = true) }
        }
        Row(
            Modifier.padding(horizontal = SubjectMetrics.gutter).fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            QueueQuickFilter.entries.forEach { filter ->
                val count = works.count { filter.matches(it, it.id in preservedIds) }
                SubjectChip(
                    text = "${filter.title} $count",
                    style = SubjectChipStyle.Pill(filter == quickFilter),
                    palette = palette,
                    modifier = Modifier.clickable { onQuickFilter(filter) }
                )
            }
        }
    }
}

/** Press-and-hold: Edit Queue, Pin or Unpin, Delete. Saved for Later has none. */
@Composable
fun QueueCardPress(
    queue: ReadingQueue,
    enabled: Boolean,
    onClick: () -> Unit,
    onEdit: () -> Unit,
    onPin: () -> Unit,
    onDelete: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    val custom = enabled && queue.kindRaw == ReadingQueueKind.CUSTOM
    var menu by remember { mutableStateOf(false) }
    var confirm by remember { mutableStateOf(false) }
    Box(modifier) {
        if (custom) {
            Box(Modifier.combinedClickable(onClick = onClick, onLongClick = { menu = true })) { content() }
        } else {
            Box(Modifier.clickable(onClick = onClick)) { content() }
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(text = { Text("Edit Queue") }, onClick = { menu = false; onEdit() })
            DropdownMenuItem(
                text = { Text(if (queue.isPinned) "Unpin" else "Pin") },
                leadingIcon = { androidx.compose.material3.Icon(Icons.Outlined.PushPin, contentDescription = null) },
                onClick = { menu = false; onPin() }
            )
            DropdownMenuItem(text = { Text("Delete Queue") }, onClick = { menu = false; confirm = true })
        }
    }
    if (confirm) {
        AlertDialog(
            onDismissRequest = { confirm = false },
            title = { Text(ReadingQueueFacts.deleteTitle(listOf(queue))) },
            text = { Text(ReadingQueueFacts.deleteMessage(1)) },
            confirmButton = {
                TextButton(onClick = { confirm = false; onDelete() }) { Text("Delete") }
            },
            dismissButton = { TextButton(onClick = { confirm = false }) { Text("Cancel") } }
        )
    }
}

@Composable
fun QueueSwipeRow(
    enabled: Boolean,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    if (!enabled) {
        Box(modifier) { content() }
        return
    }
    val density = LocalDensity.current
    val revealed = with(density) { -148.dp.toPx() }
    var offset by remember { mutableFloatStateOf(0f) }
    Box(modifier.fillMaxWidth()) {
        if (offset < -1f) {
            Row(
                Modifier
                    .align(Alignment.CenterEnd)
                    .width(with(density) { (-offset).toDp() })
                    .clipToBounds(),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically
            ) {
                TextButton(onClick = { offset = 0f; onEdit() }) { Text("Edit") }
                TextButton(onClick = { offset = 0f; onDelete() }) { Text("Delete") }
            }
        }
        Box(
            Modifier
                .fillMaxWidth()
                .offset { IntOffset(offset.roundToInt(), 0) }
                .pointerInput(Unit) {
                    detectHorizontalDragGestures(
                        onDragEnd = { offset = if (offset < revealed / 2f) revealed else 0f }
                    ) { _, drag ->
                        offset = (offset + drag).coerceIn(revealed, 0f)
                    }
                }
        ) { content() }
    }
}

fun Modifier.queueDragHandle(enabled: Boolean, onStep: (Int) -> Unit): Modifier {
    if (!enabled) return this
    return pointerInput(onStep) {
        var accrued = 0f
        val step = 56.dp.toPx()
        detectVerticalDragGestures { _, drag ->
            accrued += drag
            while (accrued >= step) {
                onStep(1)
                accrued -= step
            }
            while (accrued <= -step) {
                onStep(-1)
                accrued += step
            }
        }
    }
}

@Composable
fun DragGrip(modifier: Modifier = Modifier) {
    androidx.compose.material3.Icon(
        imageVector = Icons.Filled.DragHandle,
        contentDescription = "Reorder",
        tint = LocalKudosTokens.current.secondaryInk,
        modifier = modifier.size(22.dp)
    )
}

@Composable
fun SelectionBubble(selected: Boolean, modifier: Modifier = Modifier) {
    val tokens = LocalKudosTokens.current
    Box(
        modifier
            .size(22.dp)
            .clip(CircleShape)
            .background(if (selected) tokens.accent else Color.Transparent)
            .border(1.5.dp, if (selected) tokens.accent else tokens.secondaryInk, CircleShape),
        contentAlignment = Alignment.Center
    ) {
        if (selected) {
            androidx.compose.material3.Icon(Icons.Filled.Check, contentDescription = null, tint = Color.White, modifier = Modifier.size(14.dp))
        }
    }
}
