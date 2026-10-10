package io.github.cidy02.kudos.browse

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.network.ao3.browse.AO3MediaCategory
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectChip
import io.github.cidy02.kudos.ui.subject.SubjectChipStyle
import io.github.cidy02.kudos.ui.subject.SubjectKicker
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.compactCount
import java.util.Locale

private val JumpBackInCardWidth = 112.dp
private val PanelShape = RoundedCornerShape(SubjectMetrics.rowRadius)
private val IconTileShape = RoundedCornerShape(9.dp)

@Composable
fun JumpBackInSection(
    picks: List<JumpBackIn.Pick>,
    categories: List<AO3MediaCategory>,
    onOpenFandom: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    if (picks.isEmpty()) return
    val names = picks.map { it.fandom }
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(11.dp)) {
        SectionRuleHeader(title = "Jump Back In", count = picks.size)
        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(11.dp),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 6.dp)
        ) {
            items(picks, key = { it.fandom }) { pick ->
                val category = categories.firstOrNull { it.name == pick.categoryId } ?: return@items
                JumpBackInCard(
                    pick = pick,
                    category = category,
                    among = names,
                    onOpen = { onOpenFandom(pick.fandom) }
                )
            }
        }
    }
}

@Composable
private fun JumpBackInCard(
    pick: JumpBackIn.Pick,
    category: AO3MediaCategory,
    among: List<String>,
    onOpen: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    val palette = SubjectPalette.fromHue(HomeFacts.coverHue(category.name), tokens.theme)
    val shape = RoundedCornerShape(14.dp)
    val title = FandomDisplayName.bareTitle(pick.fandom, among)
    // With the text, as Home's cards: at twice the size "Doctor Who" read "Doct…" and the count was gone.
    val grow = io.github.cidy02.kudos.ui.subject.carouselCardScale(JumpBackInCardWidth)
    Column(
        modifier = Modifier
            .width(JumpBackInCardWidth * grow)
            .heightIn(min = 132.dp * grow)
            .clip(shape)
            .background(tokens.cardFill)
            .background(palette.cardWash)
            .border(0.5.dp, palette.rowBorder, shape)
            .clickable(onClick = onOpen)
            .padding(12.dp)
            .semantics { contentDescription = "$title. ${category.name}." },
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        SubjectKicker(
            text = category.name,
            palette = palette,
            size = 8.5.sp,
            ruleWidth = 18.dp,
            ruleSpacing = 6.dp
        )
        Text(
            text = title,
            color = tokens.primaryInk,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
        val count = pick.workCount
        if (count != null) {
            Text(
                text = "${count.compactCount()} works",
                color = tokens.secondaryInk,
                fontSize = 10.5.sp
            )
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun CategoryPanel(
    category: AO3MediaCategory,
    stats: CategoryStats,
    onOpen: () -> Unit,
    onOpenFandom: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val palette = SubjectPalette.fromHue(HomeFacts.coverHue(category.name), tokens.theme)
    val familiar = stats.recentFandoms.map { it.lowercase(Locale.US) }.toSet()
    Column(
        modifier = modifier
            .padding(horizontal = 16.dp)
            .fillMaxWidth()
            .clip(PanelShape)
            .background(tokens.theme.cardBackdrop)
            .background(palette.panelWash)
            .border(0.5.dp, palette.rowBorder, PanelShape)
            .clickable(onClick = onOpen)
            .padding(top = 14.dp, bottom = 16.dp)
            .semantics { contentDescription = "${category.name}. Open fandoms." },
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(32.dp)
                    .clip(IconTileShape)
                    .background(palette.cardWash)
                    .border(0.5.dp, tokens.glassStroke(0.14), IconTileShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = CategoryStatsCalculator.iconFor(category.name),
                    contentDescription = null,
                    tint = palette.accent,
                    modifier = Modifier.size(15.dp)
                )
            }
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(
                    text = category.name,
                    color = tokens.primaryInk,
                    fontSize = 15.sp,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                CategoryCountsLine(stats, palette)
            }
            Icon(
                imageVector = Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                contentDescription = null,
                tint = tokens.tertiaryInk,
                modifier = Modifier.size(12.dp)
            )
        }
        if (stats.recentFandoms.isNotEmpty() || stats.clusterFandoms.isNotEmpty()) {
            Column(
                modifier = Modifier.padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                if (stats.recentFandoms.isNotEmpty()) {
                    RecentlyReadBlock(stats.recentFandoms, onOpenFandom)
                }
                if (stats.clusterFandoms.isNotEmpty()) {
                    FandomChipCluster(
                        fandoms = stats.clusterFandoms,
                        total = stats.familyCount ?: stats.clusterFandoms.size,
                        palette = palette,
                        familiarNames = familiar,
                        onOpenFandom = onOpenFandom
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CategoryCountsLine(stats: CategoryStats, palette: SubjectPalette) {
    val count = stats.familyCount ?: stats.fandomCount
    val tokens = LocalKudosTokens.current
    if (count == null) {
        Text(
            text = "Counting fandoms…",
            color = tokens.tertiaryInk,
            fontSize = 11.sp
        )
        return
    }
    FlowRow(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        CountBit("${count.compactCount()} fandoms", palette)
        stats.workCount?.let { works ->
            val figure = works.compactCount()
            val label = if (stats.isApproximateWorkCount) "~$figure works" else "$figure works"
            CountBit(label, palette)
        }
        if (stats.savedCount > 0) {
            CountBit("${stats.savedCount} downloaded", palette)
        }
    }
}

@Composable
private fun CountBit(text: String, palette: SubjectPalette) {
    Text(text = text, color = palette.accent, fontSize = 11.sp, fontWeight = FontWeight.Medium)
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun RecentlyReadBlock(fandoms: List<String>, onOpenFandom: (String) -> Unit) {
    val tokens = LocalKudosTokens.current
    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Text(
            text = "Recently read",
            color = tokens.tertiaryInk,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold
        )
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            fandoms.forEach { fandom ->
                SubjectChip(
                    text = FandomDisplayName.bareTitle(fandom),
                    modifier = Modifier.clickable { onOpenFandom(fandom) }
                )
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FandomChipCluster(
    fandoms: List<CategoryStats.ClusterFandom>,
    total: Int,
    palette: SubjectPalette,
    familiarNames: Set<String>,
    onOpenFandom: (String) -> Unit
) {
    val shown = fandoms.size
    val remainder = (total - shown).coerceAtLeast(0)
    FlowRow(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
        fandoms.forEach { fandom ->
            val familiar = fandom.names.any { it.lowercase(Locale.US) in familiarNames }
            ClusterChip(
                fandom = fandom,
                palette = palette,
                isFamiliar = familiar,
                onOpen = { fandom.names.firstOrNull()?.let(onOpenFandom) }
            )
        }
        if (remainder > 0) {
            SubjectChip(
                text = "+${remainder.compactCount()} more",
                style = SubjectChipStyle.Dashed
            )
        }
    }
}

@Composable
private fun ClusterChip(
    fandom: CategoryStats.ClusterFandom,
    palette: SubjectPalette,
    isFamiliar: Boolean,
    onOpen: () -> Unit
) {
    val shape = RoundedCornerShape(SubjectMetrics.chipRadius)
    val tokens = LocalKudosTokens.current
    Row(
        modifier = Modifier
            .clip(shape)
            .background(tokens.glassFill(0.09))
            .border(0.5.dp, palette.chipStroke, shape)
            .clickable(onClick = onOpen)
            .padding(horizontal = 11.dp, vertical = 7.dp)
            .semantics {
                contentDescription = buildString {
                    append(fandom.title)
                    append(", ")
                    if (fandom.isApproximate) append("about ")
                    append(fandom.workCount)
                    append(" works")
                }
            },
        horizontalArrangement = Arrangement.spacedBy(7.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (isFamiliar) {
            Box(
                Modifier
                    .size(width = 2.5.dp, height = 14.dp)
                    .background(palette.accent, RoundedCornerShape(percent = 50))
            )
        }
        Text(
            text = fandom.title,
            color = palette.accent,
            fontSize = 12.5.sp,
            fontWeight = FontWeight.Medium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            text = (if (fandom.isApproximate) "~" else "") + fandom.workCount.compactCount(),
            color = palette.accent.copy(alpha = 0.62f),
            fontSize = 11.sp,
            maxLines = 1
        )
    }
}

@Composable
fun OpenAo3WebsiteRow(modifier: Modifier = Modifier, onOpen: () -> Unit) {
    val tokens = LocalKudosTokens.current
    val shape = RoundedCornerShape(12.dp)
    Row(
        modifier = modifier
            .padding(horizontal = 16.dp)
            .fillMaxWidth()
            .clip(shape)
            .dashedRoundedBorder(tokens.tertiaryInk)
            .clickable(onClick = onOpen)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = "Open AO3 Website",
            color = tokens.secondaryInk,
            fontSize = 13.5.sp,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.weight(1f)
        )
        Icon(
            imageVector = Icons.AutoMirrored.Outlined.KeyboardArrowRight,
            contentDescription = null,
            tint = tokens.tertiaryInk,
            modifier = Modifier.size(11.dp)
        )
    }
}

private fun Modifier.dashedRoundedBorder(color: androidx.compose.ui.graphics.Color): Modifier = drawBehind {
    val stroke = Stroke(
        width = 1.dp.toPx(),
        pathEffect = PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 5.dp.toPx()))
    )
    drawRoundRect(
        color = color,
        style = stroke,
        cornerRadius = CornerRadius(12.dp.toPx())
    )
}

@Composable
fun BrowseInstructions() {
    Text(
        text = "Browse fandoms from AO3. Tap a category to see its fandoms.",
        color = LocalKudosTokens.current.secondaryInk,
        fontSize = 13.sp,
        modifier = Modifier
            .padding(horizontal = 16.dp)
            .fillMaxWidth()
    )
}
