package io.github.cidy02.kudos.library

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.outlined.CollectionsBookmark
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.ui.components.coverHue
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.SubjectWorkCardMetrics

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun CollectionCard(
    collection: WorkCollection,
    previewWorks: List<SavedWork>,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val palette = remember(collection.hue, collection.name, tokens.theme) {
        SubjectPalette.fromHue(
            collection.hue ?: coverHue(collection.name).toDouble() / 360.0,
            tokens.theme
        )
    }
    Column(
        modifier
            .width(SubjectWorkCardMetrics.width)
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .semantics {
                contentDescription = "${collection.name}, ${collection.workIds.size} works. Opens collection."
            },
        verticalArrangement = Arrangement.spacedBy(7.dp)
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(221.dp)
                .clip(RoundedCornerShape(18.dp))
                .background(palette.cardWash)
                .border(0.5.dp, palette.cardBorder, RoundedCornerShape(18.dp))
                .padding(8.dp)
        ) {
            if (previewWorks.isEmpty()) {
                Icon(
                    Icons.Outlined.CollectionsBookmark,
                    contentDescription = null,
                    tint = palette.accent.copy(alpha = 0.6f),
                    modifier = Modifier.size(42.dp).align(Alignment.Center)
                )
            } else {
                val slots = previewWorks.take(4).map<SavedWork, SavedWork?> { it } +
                    List((4 - previewWorks.size.coerceAtMost(4)).coerceAtLeast(0)) { null }
                Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    slots.chunked(2).forEach { row ->
                        Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                            row.forEach { work ->
                                if (work == null) {
                                    EmptyMiniatureWorkCover(Modifier.weight(1f), height = 100.dp)
                                } else {
                                    MiniatureWorkCover(work, Modifier.weight(1f), height = 100.dp)
                                }
                            }
                        }
                    }
                }
            }
        }
        Text(
            collection.name,
            color = tokens.primaryInk,
            fontSize = 15.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            workCountLabel(collection.workIds.size),
            color = tokens.secondaryInk,
            fontSize = 12.sp
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun CollectionLedgerRow(
    collection: WorkCollection,
    previewWorks: List<SavedWork>,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    Row(
        modifier
            .fillMaxWidth()
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(13.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(
            Modifier.width(128.dp),
            verticalArrangement = Arrangement.spacedBy(5.dp)
        ) {
            previewWorks.take(4).chunked(2).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    row.forEach { work -> MiniatureWorkCover(work, Modifier.weight(1f)) }
                    repeat(2 - row.size) { EmptyMiniatureWorkCover(Modifier.weight(1f)) }
                }
            }
            if (previewWorks.isEmpty()) {
                repeat(2) {
                    Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                        EmptyMiniatureWorkCover(Modifier.weight(1f))
                        EmptyMiniatureWorkCover(Modifier.weight(1f))
                    }
                }
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                collection.name,
                color = tokens.primaryInk,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            Text(workCountLabel(collection.workIds.size), color = tokens.secondaryInk, fontSize = 12.sp)
        }
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = tokens.tertiaryInk
        )
    }
}

@Composable
private fun MiniatureWorkCover(
    work: SavedWork,
    modifier: Modifier = Modifier,
    height: Dp = 54.dp
) {
    val tokens = LocalKudosTokens.current
    val palette = remember(work.title, tokens.theme) {
        SubjectPalette.fromHue(coverHue(work.workFandoms.firstOrNull() ?: work.title).toDouble() / 360.0, tokens.theme)
    }
    Column(
        modifier
            .height(height)
            .clip(RoundedCornerShape(7.dp))
            .background(palette.cardWash)
            .padding(6.dp),
        verticalArrangement = Arrangement.spacedBy(3.dp)
    ) {
        Box(Modifier.size(width = 13.dp, height = 2.dp).background(palette.accent, RoundedCornerShape(50)))
        Text(
            work.title,
            color = tokens.primaryInk,
            fontSize = 9.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun EmptyMiniatureWorkCover(
    modifier: Modifier = Modifier,
    height: Dp = 54.dp
) {
    val tokens = LocalKudosTokens.current
    Box(
        modifier
            .height(height)
            .clip(RoundedCornerShape(7.dp))
            .background(tokens.glassFill(0.04))
            .border(0.5.dp, tokens.glassStroke(0.06), RoundedCornerShape(7.dp))
    )
}

private fun workCountLabel(count: Int): String = if (count == 1) "1 work" else "$count works"
