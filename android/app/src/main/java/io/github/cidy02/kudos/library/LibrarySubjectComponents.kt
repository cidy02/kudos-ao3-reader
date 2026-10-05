package io.github.cidy02.kudos.library

import androidx.compose.foundation.ExperimentalFoundationApi
import io.github.cidy02.kudos.home.HomeFacts
import androidx.compose.material.icons.outlined.Person
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.TextUnit
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.ui.components.coverHue
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.SubjectWorkCardMetrics
import io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale

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
    val accessibility = isAccessibilityFontScale()
    val palette = remember(collection.hue, collection.colorHex, collection.name, tokens.theme) {
        collectionDraftPalette(collection.name, collection.hue, collection.colorHex, tokens.theme)
    }
    Column(
        modifier
            .width(if (accessibility) (LocalConfiguration.current.screenWidthDp.dp - 32.dp).coerceAtLeast(1.dp)
                else SubjectWorkCardMetrics.width)
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .semantics {
                contentDescription = "${collection.name}, ${collection.workIds.size} works. Opens collection."
            },
        verticalArrangement = Arrangement.spacedBy(7.dp)
    ) {
        val shape = RoundedCornerShape(18.dp)
        if (collection.workIds.isEmpty()) {
            // iOS CollectionCard.singleTile: the collection's own hue, stack glyph at white 0.6.
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(221.dp)
                    .clip(shape)
                    .background(palette.cardWash),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Outlined.CollectionsBookmark,
                    contentDescription = null,
                    tint = Color.White.copy(alpha = 0.6f),
                    modifier = Modifier.size(38.dp)
                )
            }
        } else {
            // iOS StackedWorkCover: neutral glass, a 2x2 of the newest works, faint empty slots.
            val slots: List<SavedWork?> = previewWorks.take(4) + List(4 - previewWorks.size.coerceAtMost(4)) { null }
            Column(
                Modifier
                    .fillMaxWidth()
                    .then(if (accessibility) Modifier else Modifier.height(221.dp))
                    .clip(shape)
                    .background(tokens.glassFill(0.06))
                    .border(0.5.dp, tokens.glassStroke(0.07), shape)
                    .padding(10.dp),
                verticalArrangement = Arrangement.spacedBy(7.dp)
            ) {
                if (accessibility) {
                    slots.forEach { work ->
                        if (work == null) {
                            MosaicPlaceholder(Modifier.fillMaxWidth().height(54.dp))
                        } else {
                            MosaicWorkTile(work, Modifier.fillMaxWidth())
                        }
                    }
                } else {
                    slots.chunked(2).forEach { row ->
                        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                            row.forEach { work ->
                                val cell = Modifier.weight(1f).fillMaxHeight()
                                if (work == null) MosaicPlaceholder(cell) else MosaicWorkTile(work, cell)
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
            lineHeight = if (accessibility) 21.sp else TextUnit.Unspecified,
            maxLines = if (accessibility) Int.MAX_VALUE else 2,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            workCountLabel(collection.workIds.size),
            color = tokens.secondaryInk,
            fontSize = 12.sp,
            lineHeight = if (accessibility) 17.sp else TextUnit.Unspecified
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

/** iOS StackedWorkCover.workCell. */
@Composable
private fun MosaicWorkTile(work: SavedWork, modifier: Modifier) {
    val tokens = LocalKudosTokens.current
    val accessibility = isAccessibilityFontScale()
    val palette = remember(work.title, work.workFandoms, tokens.theme) {
        SubjectPalette.fromHue(HomeFacts.workHue(work.workFandoms, work.title), tokens.theme)
    }
    val shape = RoundedCornerShape(9.dp)
    val dark = tokens.theme.isDarkFamily
    val authorInk = if (accessibility) tokens.secondaryInk
        else if (dark) Color.White.copy(alpha = 0.62f) else tokens.secondaryInk
    Column(
        modifier
            .clip(shape)
            .background(palette.cardWash)
            .border(0.5.dp, tokens.glassStroke(0.10), shape)
            .padding(horizontal = 7.dp, vertical = 6.dp)
    ) {
        Box(Modifier.size(width = 14.dp, height = 2.dp).background(palette.accent, RoundedCornerShape(50)))
        Spacer(Modifier.height(6.dp))
        Text(
            work.title,
            color = if (accessibility) tokens.primaryInk
                else if (dark) Color.White.copy(alpha = 0.92f) else tokens.primaryInk,
            fontSize = 9.5.sp,
            lineHeight = 12.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = if (accessibility) Int.MAX_VALUE else 2,
            overflow = TextOverflow.Ellipsis
        )
        Spacer(if (accessibility) Modifier.height(4.dp) else Modifier.weight(1f).height(4.dp))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            Icon(Icons.Outlined.Person, contentDescription = null, tint = authorInk, modifier = Modifier.size(8.dp))
            Text(
                work.author, color = authorInk, fontSize = 8.5.sp,
                lineHeight = if (accessibility) 12.sp else TextUnit.Unspecified,
                maxLines = if (accessibility) Int.MAX_VALUE else 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

/** iOS StackedWorkCover.placeholderCell. */
@Composable
private fun MosaicPlaceholder(modifier: Modifier) {
    val tokens = LocalKudosTokens.current
    val shape = RoundedCornerShape(9.dp)
    Box(modifier.clip(shape).background(tokens.glassFill(0.04)).border(0.5.dp, tokens.glassStroke(0.06), shape))
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
