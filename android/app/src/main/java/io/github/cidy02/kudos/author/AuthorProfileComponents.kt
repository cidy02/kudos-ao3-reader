package io.github.cidy02.kudos.author

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Block
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.VolumeOff
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorBookmark
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorHeader
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorRoute
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorSeriesSummary
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorWebAction
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.ui.components.SensitiveWorkRow
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectChip
import io.github.cidy02.kudos.ui.subject.SubjectChipStyle
import io.github.cidy02.kudos.ui.subject.SubjectKicker
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.SubjectStatCell
import io.github.cidy02.kudos.ui.subject.SubjectStatStrip
import io.github.cidy02.kudos.ui.subject.compactCount
import io.github.cidy02.kudos.ui.subject.subjectPanel

internal enum class AuthorDisplayMode(val label: String) {
    Ledger("Ledger"),
    Detailed("Detailed")
}

@Composable
internal fun AO3AuthorHero(
    header: AO3AuthorHeader,
    route: AO3AuthorRoute,
    profileTitle: String,
    isOwnProfile: Boolean,
    onSubscription: (String) -> Unit,
    onModeration: (AO3AuthorWebAction) -> Unit,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val context = LocalContext.current
    val mute = header.actions.firstOrNull { it.kind == AO3AuthorWebAction.Kind.Mute }
    val block = header.actions.firstOrNull { it.kind == AO3AuthorWebAction.Kind.Block }
    Row(
        modifier
            .fillMaxWidth()
            .subjectPanel(cornerRadius = 16.dp)
            .padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.Top
    ) {
        AsyncImage(
            model = ImageRequest.Builder(context).data(header.avatarUrl).crossfade(true).build(),
            contentDescription = "${route.displayName} profile image",
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .size(72.dp)
                .background(tokens.glassFill(), RoundedCornerShape(8.dp))
                .clip(RoundedCornerShape(8.dp))
        )
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(
                route.displayName,
                color = tokens.primaryInk,
                fontSize = 22.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                route.pseud?.let { "Pseud of ${route.username}" } ?: "AO3 user",
                color = tokens.secondaryInk,
                fontSize = 15.sp
            )
            if (profileTitle.isNotBlank()) {
                Text(profileTitle, color = tokens.primaryInk, fontSize = 15.sp, fontWeight = FontWeight.Medium)
            }
            if (!isOwnProfile && (header.subscriptionForm != null || mute != null || block != null)) {
                Row(
                    modifier = Modifier.padding(top = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    header.subscriptionForm?.let { form ->
                        Button(onClick = { onSubscription(form.actionUrl) }) {
                            Icon(Icons.Outlined.Notifications, contentDescription = null, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.size(5.dp))
                            Text(if (form.isSubscribed) "Unsubscribe" else "Subscribe")
                        }
                    }
                    mute?.let { action ->
                        AuthorModerationButton(action, Icons.Outlined.VolumeOff) { onModeration(action) }
                    }
                    block?.let { action ->
                        AuthorModerationButton(action, Icons.Outlined.Block) { onModeration(action) }
                    }
                }
            }
        }
    }
}

@Composable
private fun AuthorModerationButton(
    action: AO3AuthorWebAction,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    onClick: () -> Unit
) {
    OutlinedButton(
        onClick = onClick,
        contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp),
        modifier = Modifier.size(40.dp).semantics { contentDescription = action.label }
    ) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(17.dp))
    }
}

@Composable
internal fun AO3AuthorWorkCard(
    work: AO3WorkSummary,
    displayMode: AuthorDisplayMode,
    expandAll: Boolean,
    showsPerformance: Boolean,
    onOpenWork: (AO3WorkSummary) -> Unit,
    modifier: Modifier = Modifier
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (displayMode == AuthorDisplayMode.Detailed) {
            SensitiveWorkRow(work = work, onOpenWork = onOpenWork, expandAll = expandAll)
        } else {
            AO3AuthorLedgerWorkRow(work = work, onOpenWork = onOpenWork)
        }
        if (showsPerformance) AO3AuthorPerformanceStrip(work)
    }
}

@Composable
private fun AO3AuthorLedgerWorkRow(work: AO3WorkSummary, onOpenWork: (AO3WorkSummary) -> Unit) {
    val tokens = LocalKudosTokens.current
    val palette = remember(work.fandoms, work.title, tokens.theme) {
        SubjectPalette.fromHue(HomeFacts.workHue(work.fandoms, work.title), tokens.theme)
    }
    Column(
        Modifier
            .fillMaxWidth()
            .background(palette.cardWash, RoundedCornerShape(16.dp))
            .border(0.5.dp, palette.cardBorder, RoundedCornerShape(16.dp))
            .clickable { onOpenWork(work) }
            .padding(horizontal = 18.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        SubjectKicker(
            text = HomeFacts.primaryFandom(work.fandoms) ?: "Work",
            palette = palette,
            trailingCount = (work.fandoms.size - 1).coerceAtLeast(0)
        )
        Text(
            work.title,
            color = tokens.primaryInk,
            fontSize = 19.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
        Text("by ${work.authorText}", color = tokens.secondaryInk, fontSize = 13.sp, maxLines = 1)
        if (work.summary.isNotBlank()) {
            Text(work.summary, color = tokens.secondaryInk, fontSize = 13.5.sp, maxLines = 3)
        }
        val meta = buildList {
            work.wordCount?.let { add("${it.compactCount()} words") }
            if (work.chapters.isNotBlank()) add(work.chapters)
            if (work.updatedDate.isNotBlank()) add(work.updatedDate)
        }.joinToString(" · ")
        if (meta.isNotBlank()) Text(meta, color = tokens.secondaryInk, fontSize = 11.5.sp)
    }
}

@Composable
internal fun AO3AuthorPerformanceStrip(work: AO3WorkSummary) {
    val tokens = LocalKudosTokens.current
    val palette = remember(work.fandoms, work.title, tokens.theme) {
        SubjectPalette.fromHue(HomeFacts.workHue(work.fandoms, work.title), tokens.theme)
    }
    val cells = listOfNotNull(
        work.kudos?.let { SubjectStatCell(it.compactCount(), "Kudos") },
        work.comments?.let { SubjectStatCell(it.compactCount(), "Comments") },
        work.hits?.let { SubjectStatCell(it.compactCount(), "Hits") },
        work.bookmarks?.let { SubjectStatCell(it.compactCount(), "Bookmarks") }
    )
    if (cells.isNotEmpty()) SubjectStatStrip(cells = cells, palette = palette)
}

@Composable
internal fun AO3SeriesRow(
    series: AO3AuthorSeriesSummary,
    displayMode: AuthorDisplayMode,
    onOpenSeries: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val palette = remember(series.fandoms, series.title, tokens.theme) {
        SubjectPalette.fromHue(HomeFacts.workHue(series.fandoms, series.title), tokens.theme)
    }
    Column(
        modifier
            .fillMaxWidth()
            .subjectPanel(cornerRadius = 16.dp)
            .clickable { onOpenSeries(series.url) }
            .padding(horizontal = 18.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(if (displayMode == AuthorDisplayMode.Ledger) 10.dp else 7.dp)
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
            SeriesSpineStackMark(palette)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                SubjectKicker(
                    text = series.fandoms.firstOrNull() ?: "Series",
                    palette = palette,
                    size = 10.sp,
                    ruleSpacing = 4.dp
                )
                Text(
                    series.title,
                    color = tokens.primaryInk,
                    fontSize = if (displayMode == AuthorDisplayMode.Ledger) 19.sp else 17.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 2
                )
            }
        }
        if (series.summary.isNotBlank()) {
            Text(series.summary, color = tokens.secondaryInk, fontSize = 13.5.sp, maxLines = 3)
        }
        val meta = buildList {
            series.workCount?.let { add(if (it == 1) "1 work" else "$it works") }
            series.words?.let { add("${it.compactCount()} words") }
            if (series.dateUpdated.isNotBlank()) add(series.dateUpdated)
        }.joinToString(" · ")
        if (meta.isNotBlank()) Text(meta, color = tokens.secondaryInk, fontSize = 11.5.sp)
        if (series.creators.isNotEmpty()) {
            Text("by ${series.creators.joinToString()}", color = tokens.secondaryInk, fontSize = 12.sp)
        }
    }
}

@Composable
private fun SeriesSpineStackMark(palette: SubjectPalette) {
    val shape = RoundedCornerShape(10.dp)
    Box(
        Modifier
            .size(38.dp)
            .background(palette.cardWash, shape)
            .border(0.5.dp, palette.chipStroke, shape),
        contentAlignment = Alignment.Center
    ) {
        repeat(3) { index ->
            Box(
                Modifier
                    .offset(x = (index * 3 - 3).dp, y = (index * -3 + 3).dp)
                    .size(width = 14.dp, height = 20.dp)
                    .border(1.25.dp, palette.accent, RoundedCornerShape(3.dp))
            )
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun AO3BookmarkFootnote(bookmark: AO3AuthorBookmark, modifier: Modifier = Modifier) {
    val tokens = LocalKudosTokens.current
    val title = bookmark.work?.title.orEmpty()
    val fandoms = bookmark.work?.fandoms.orEmpty()
    val palette = remember(fandoms, title, tokens.theme) {
        SubjectPalette.fromHue(HomeFacts.workHue(fandoms, title), tokens.theme)
    }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        val badges = buildList {
            if (bookmark.isPrivate) add("Private")
            if (bookmark.isRecommendation) add("Rec")
        }
        if (badges.isNotEmpty()) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                badges.forEach { SubjectChip(it, style = SubjectChipStyle.Tinted, palette = palette) }
            }
        }
        if (bookmark.notes.isNotBlank()) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.size(width = 2.dp, height = 34.dp).background(palette.accent, CircleShape))
                Text(bookmark.notes, color = tokens.secondaryInk, fontSize = 14.sp, modifier = Modifier.weight(1f))
            }
        }
        if (bookmark.tags.isNotEmpty()) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                bookmark.tags.forEach { BookmarkTagPill(it) }
            }
        }
    }
}

@Composable
private fun BookmarkTagPill(text: String) {
    val tokens = LocalKudosTokens.current
    Text(
        text,
        color = tokens.primaryInk,
        fontSize = 13.sp,
        modifier = Modifier
            .background(tokens.glassFill(0.09), RoundedCornerShape(8.dp))
            .border(0.5.dp, tokens.glassStroke(0.14), RoundedCornerShape(8.dp))
            .padding(horizontal = 10.dp, vertical = 6.dp)
    )
}

@Composable
internal fun AO3DashboardCompactCard(
    fandoms: List<String>,
    title: String,
    meta: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val palette = remember(fandoms, title, tokens.theme) {
        SubjectPalette.fromHue(HomeFacts.workHue(fandoms, title), tokens.theme)
    }
    Column(
        modifier
            .fillMaxWidth()
            .subjectPanel(cornerRadius = 16.dp)
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 13.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        fandoms.firstOrNull { it.isNotBlank() }?.let {
            Text(
                it.uppercase(),
                color = palette.accent,
                fontSize = 9.5.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = 0.95.sp,
                maxLines = 1
            )
        }
        Text(title, color = tokens.primaryInk, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 2)
        if (meta.isNotBlank()) Text(meta, color = tokens.secondaryInk, fontSize = 11.5.sp, maxLines = 1)
    }
}

