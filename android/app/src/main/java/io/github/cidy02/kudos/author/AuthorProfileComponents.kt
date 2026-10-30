package io.github.cidy02.kudos.author

import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.icons.outlined.AccountBox
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.LibraryBooks
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.outlined.Event
import androidx.compose.material.icons.outlined.Layers
import androidx.compose.material.icons.outlined.Verified
import androidx.compose.material.icons.outlined.PanTool
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.People
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.NotificationsOff
import androidx.compose.material.icons.outlined.VolumeOff
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
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
import io.github.cidy02.kudos.ui.components.WorkStatIcons
import io.github.cidy02.kudos.ui.components.WorkStatItem
import io.github.cidy02.kudos.ui.components.WorkStatLabel
import io.github.cidy02.kudos.ui.subject.cardRow
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

/** iOS AuthorProfileView.pseudSelector: one Scope row with a menu, also on account headers. */
@Composable
internal fun AuthorPseudSelector(
    pseuds: List<io.github.cidy02.kudos.network.ao3.author.AO3AuthorPseud>,
    route: AO3AuthorRoute,
    /** Under the author hero iOS draws it as a card row (`pseudSelector(...).cardRow()`), as the hero itself. */
    card: Boolean = false,
    onSelect: (AO3AuthorRoute) -> Unit
) {
    var expanded by remember(route.username) { mutableStateOf(false) }
    Box(Modifier.fillMaxWidth().then(if (card) Modifier.cardRow() else Modifier.subjectPanel())) {
        io.github.cidy02.kudos.ui.subject.SubjectFormRow(
            "Scope", value = route.pseud ?: "All Pseuds", showsChoice = true,
            valueMaxLines = if (io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale()) 2 else 1,
            leadingIcon = Icons.Outlined.People,
            modifier = Modifier.semantics { contentDescription = "Author scope" },
            onClick = { expanded = true }
        )
        androidx.compose.material3.DropdownMenu(
            expanded = expanded, onDismissRequest = { expanded = false },
            containerColor = LocalKudosTokens.current.cardFill
        ) {
            val choices = listOf("All Pseuds" to AO3AuthorRoute(route.username)) + pseuds.map { it.name to it.route }
            choices.forEach { (name, choice) ->
                androidx.compose.material3.DropdownMenuItem(
                    text = { Text(name, color = LocalKudosTokens.current.primaryInk) },
                    leadingIcon = if (route.id == choice.id) { { Icon(Icons.Outlined.Check, "Selected") } } else null,
                    onClick = { expanded = false; if (route.id != choice.id) onSelect(choice) }
                )
            }
        }
    }
}

@Composable
internal fun AO3AuthorHero(
    header: AO3AuthorHeader,
    route: AO3AuthorRoute,
    profileTitle: String,
    isOwnProfile: Boolean,
    onSubscription: (io.github.cidy02.kudos.network.ao3.author.AO3AuthorSubscriptionForm) -> Unit,
    onModeration: (AO3AuthorWebAction) -> Unit,
    subscriptionBusy: Boolean = false,
    moderationBusy: Boolean = false,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val context = LocalContext.current
    val mute = header.actions.firstOrNull { it.kind == AO3AuthorWebAction.Kind.Mute }
    val block = header.actions.firstOrNull { it.kind == AO3AuthorWebAction.Kind.Block }
    
    val showsAccountActions = !isOwnProfile && route.username.isNotBlank() && route.username.lowercase() != "orphan_account"
    val showsActionRow = showsAccountActions && (header.subscriptionForm != null || mute != null || block != null)

    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.Top
    ) {
        AO3AuthorAvatar(url = header.avatarUrl, name = route.displayName, size = 72.dp)
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
            if (showsActionRow) {
                @OptIn(ExperimentalLayoutApi::class)
                FlowRow(
                    modifier = Modifier.padding(top = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    itemVerticalAlignment = Alignment.CenterVertically
                ) {
                    header.subscriptionForm?.let { form ->
                        Button(
                            onClick = { onSubscription(form) },
                            enabled = !subscriptionBusy,
                            colors = ButtonDefaults.buttonColors(
                                containerColor = tokens.scopePalette.tint,
                                contentColor = SubjectPalette.label(tokens.scopePalette.tint)
                            ),
                            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 12.dp, vertical = 6.dp),
                            modifier = Modifier.heightIn(min = 32.dp)
                        ) {
                            Icon(
                                imageVector = if (form.isSubscribed) Icons.Outlined.NotificationsOff else Icons.Outlined.Notifications,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp)
                            )
                            Spacer(Modifier.size(5.dp))
                            Text(if (form.isSubscribed) "Unsubscribe" else "Subscribe", fontSize = 13.sp)
                        }
                    }
                    mute?.let { action ->
                        AuthorModerationButton(action, Icons.Outlined.VolumeOff, !moderationBusy) { onModeration(action) }
                    }
                    block?.let { action ->
                        AuthorModerationButton(action, Icons.Outlined.PanTool, !moderationBusy) { onModeration(action) }
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
    enabled: Boolean = true,
    onClick: () -> Unit
) {
    OutlinedButton(
        onClick = onClick,
        enabled = enabled,
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
    modifier: Modifier = Modifier,
    bookmark: io.github.cidy02.kudos.ui.components.LedgerBookmark? = null,
    selecting: Boolean = false,
    selected: Boolean = false,
    actions: (@Composable () -> Unit)? = null
) {
    // iOS `showsPerformance`: on the writer's own works the kudos, comments and hits are a
    // strip inside the ledger card, and its line of figures leaves them out. They were
    // printed twice, on the line and again in a strip under the card. The detailed card's
    // own row of figures already has them, so it has no strip (iOS has none there either).
    val strip = showsPerformance && displayMode != AuthorDisplayMode.Detailed
    SensitiveWorkRow(
        work = work,
        onOpenWork = onOpenWork,
        modifier = modifier,
        expandAll = expandAll,
        // A bookmark is iOS's one card in every layout (1q).
        ledger = displayMode != AuthorDisplayMode.Detailed || bookmark != null,
        bookmark = bookmark,
        neutralCard = bookmark != null,
        footer = if (strip || actions != null) { {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                if (strip) AO3AuthorPerformanceStrip(work)
                if (actions != null) Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) { actions() }
            }
        } } else null,
        figuresIncludePerformance = !strip,
        selecting = selecting,
        selected = selected
    )
}

/** A bookmark as the one card carries it (iOS 1q): its badges, its day, then its note and tags. */
internal fun AO3AuthorBookmark.asLedgerBookmark() = io.github.cidy02.kudos.ui.components.LedgerBookmark(
    badges = listOfNotNull("Private".takeIf { isPrivate }, "Rec".takeIf { isRecommendation }),
    date = date,
    footnote = { if (notes.isNotBlank() || tags.isNotEmpty()) AO3BookmarkFootnote(this, showsStatus = false) },
    localFootnote = { AO3BookmarkFootnote(this) }
)

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
    if (cells.isEmpty()) return
    // Four cells across cut their labels at the large text sizes ("COMMEN…"): two to a row there.
    if (io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale() && cells.size > 2) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            cells.chunked(2).forEach { SubjectStatStrip(cells = it, palette = palette) }
        }
    } else {
        SubjectStatStrip(cells = cells, palette = palette)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun AO3SeriesRow(
    series: AO3AuthorSeriesSummary,
    displayMode: AuthorDisplayMode,
    /** Null at the head of the series's own page, where the card opens nothing. */
    onOpenSeries: ((String) -> Unit)?,
    modifier: Modifier = Modifier,
    trailingContent: (@Composable () -> Unit)? = null,
    /** False under a page title that already says it. */
    showsTitle: Boolean = true,
    onOpenAuthor: (io.github.cidy02.kudos.network.ao3.author.AO3AuthorRoute) -> Unit = {}
) {
    val tokens = LocalKudosTokens.current
    val palette = remember(series.fandoms, series.title, tokens.theme) {
        SubjectPalette.fromHue(HomeFacts.workHue(series.fandoms, series.title), tokens.theme)
    }
    Column(
        modifier
            .fillMaxWidth()
            .cardRow()
            .then(if (onOpenSeries != null) Modifier.clickable { onOpenSeries(series.url) } else Modifier)
            .padding(horizontal = 18.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(if (displayMode == AuthorDisplayMode.Ledger) 10.dp else 7.dp)
    ) {
        val large = io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale()
        // iOS 1w: "Complete" in green and "Restricted" in amber beside the fandom. AO3 says
        // both on its own page, and the card said neither.
        val hasBadges = series.isComplete == true || series.isRestricted
        val badges: @Composable () -> Unit = {
            if (series.isComplete == true) io.github.cidy02.kudos.ui.subject.SubjectStateBadge(
                "Complete", SubjectPalette.fromHue(0.36, tokens.theme).accent)
            if (series.isRestricted) io.github.cidy02.kudos.ui.subject.SubjectStateBadge(
                "Restricted", SubjectPalette.fromHue(0.10, tokens.theme).accent)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
            SeriesSpineStackMark(palette)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                SubjectKicker(
                    text = series.fandoms.firstOrNull() ?: "Series",
                    palette = palette,
                    size = 10.sp,
                    ruleSpacing = 4.dp,
                    trailing = if (hasBadges && !large) badges else null
                )
                // No room beside the fandom at the large sizes: a line of their own.
                if (hasBadges && large) FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)
                ) { badges() }
                if (showsTitle) Text(
                    series.title,
                    color = tokens.primaryInk,
                    fontSize = if (displayMode == AuthorDisplayMode.Ledger) 19.sp else 17.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = if (io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale()) Int.MAX_VALUE else 2,
                    lineHeight = 25.sp
                )
            }
            trailingContent?.invoke()
        }
        if (series.summary.isNotBlank()) {
            Text(series.summary, color = tokens.secondaryInk, fontSize = 13.5.sp, maxLines = 3)
        }
        // iOS `AO3SeriesRow.figures`: works, the whole word count, the bookmarks, and the date
        // at the line's far end (under the figures at the large sizes).
        val figures = listOfNotNull(
            series.workCount?.let { if (it == 1) "1 work" else "%,d works".format(it) },
            series.words?.let { "%,d words".format(it) },
            series.bookmarkCount?.let { if (it == 1) "1 bookmark" else "%,d bookmarks".format(it) }
        ).joinToString("  ·  ")
        if (large) {
            if (figures.isNotBlank()) Text(figures, color = tokens.secondaryInk, fontSize = 11.5.sp)
            if (series.dateUpdated.isNotBlank()) Text(series.dateUpdated, color = tokens.secondaryInk, fontSize = 11.5.sp)
        } else if (figures.isNotBlank() || series.dateUpdated.isNotBlank()) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(figures, color = tokens.secondaryInk, fontSize = 11.5.sp, modifier = Modifier.weight(1f))
                Text(series.dateUpdated, color = tokens.secondaryInk, fontSize = 11.5.sp, maxLines = 1)
            }
        }
        SeriesCreatorByline(series, onOpenAuthor)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun SeriesDetailCard(
    series: AO3AuthorSeriesSummary,
    onOpenAuthor: (io.github.cidy02.kudos.network.ao3.author.AO3AuthorRoute) -> Unit = {}
) {
    val tokens = LocalKudosTokens.current
    Column(Modifier.fillMaxWidth().cardRow().padding(horizontal = 18.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(7.dp)) {
        Text(series.title, color = tokens.primaryInk, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
        SeriesCreatorByline(series, onOpenAuthor)
        if (series.fandoms.isNotEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.Top) {
            Icon(Icons.AutoMirrored.Outlined.LibraryBooks, contentDescription = null, tint = tokens.secondaryInk,
                modifier = Modifier.size(with(LocalDensity.current) { 14.sp.toDp() }).testTag("Series fandom icon"))
            Text(series.fandoms.joinToString(", "), color = tokens.secondaryInk, fontSize = 12.sp,
                maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        }
        if (series.summary.isNotBlank()) Text(series.summary, color = tokens.secondaryInk,
            fontSize = 14.sp, maxLines = 3)
        androidx.compose.material3.HorizontalDivider(color = tokens.separator)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(18.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            series.workCount?.let { WorkStatLabel(WorkStatItem("$it works", icon = Icons.Outlined.Layers)) }
            series.words?.let { WorkStatLabel(WorkStatItem("%,d words".format(it), icon = WorkStatIcons.words)) }
            series.bookmarkCount?.let { WorkStatLabel(WorkStatItem(
                if (it == 1) "1 bookmark" else "%,d bookmarks".format(it), icon = WorkStatIcons.bookmarks)) }
            if (series.isRestricted) WorkStatLabel(WorkStatItem("Restricted", icon = Icons.Filled.Lock))
            series.isComplete?.let { WorkStatLabel(WorkStatItem(if (it) "Complete" else "In progress",
                icon = if (it) Icons.Outlined.Verified else WorkStatIcons.inProgress)) }
            if (series.dateUpdated.isNotBlank()) WorkStatLabel(WorkStatItem(series.dateUpdated, icon = Icons.Outlined.Event))
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SeriesCreatorByline(series: AO3AuthorSeriesSummary,
    onOpenAuthor: (io.github.cidy02.kudos.network.ao3.author.AO3AuthorRoute) -> Unit) {
    val tokens = LocalKudosTokens.current
    val creators = series.creatorIdentities.ifEmpty {
        series.creators.map { io.github.cidy02.kudos.network.ao3.author.AO3SeriesCreator(it, null) }
    }
    if (creators.isNotEmpty()) FlowRow(horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp), itemVerticalAlignment = Alignment.CenterVertically) {
        Text("by", color = tokens.secondaryInk, fontSize = 12.sp)
        creators.forEachIndexed { index, creator ->
            Text(creator.displayName + if (index < creators.lastIndex) "," else "",
                color = if (creator.route != null) tokens.scopePalette.controlInk else tokens.secondaryInk, fontSize = 12.sp,
                modifier = if (creator.route != null) Modifier.clickable { onOpenAuthor(creator.route) }
                    .semantics { contentDescription = "Author: ${creator.displayName}" } else Modifier)
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
internal fun AO3BookmarkFootnote(
    bookmark: AO3AuthorBookmark,
    modifier: Modifier = Modifier,
    /** Private, Rec and the date, for a row whose card cannot carry them (iOS `showsStatus`). */
    showsStatus: Boolean = true
) {
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
        if (showsStatus && (badges.isNotEmpty() || bookmark.date.isNotBlank())) {
            FlowRow(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                itemVerticalAlignment = Alignment.CenterVertically
            ) {
                badges.forEach { SubjectChip(it, style = SubjectChipStyle.Tinted, palette = palette) }
                Spacer(Modifier.weight(1f))
                if (bookmark.date.isNotBlank()) {
                    Text(
                        bookmark.date, color = tokens.secondaryInk, fontSize = 11.5.sp, maxLines = 1,
                        modifier = Modifier.semantics { contentDescription = "Bookmarked ${bookmark.date}" }
                    )
                }
            }
        }
        if (bookmark.notes.isNotBlank()) {
            // The rail is as tall as the note; at a fixed 34dp it stopped beside its second line.
            Row(
                modifier = Modifier.height(IntrinsicSize.Min),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Box(Modifier.width(2.dp).fillMaxHeight().background(palette.accent, CircleShape))
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
            .background(palette.cardWash, RoundedCornerShape(16.dp))
            .subjectPanel(cornerRadius = 16.dp, isFilled = false)
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

/**
 * iOS `AO3AuthorAvatar`: the avatar when it loads, otherwise a person glyph at 42% of the size
 * over a quiet fill, square with soft corners on an author page and round on the Account
 * header. Android's fallbacks were the Kudos mark on Account and a blank square on an author's
 * page. The glyph sits underneath, so a loaded image simply covers it.
 */
@Composable
internal fun AO3AuthorAvatar(
    url: String?,
    name: String,
    size: androidx.compose.ui.unit.Dp,
    isCircular: Boolean = false,
    modifier: Modifier = Modifier,
    spokenName: String = "$name profile image"
) {
    val tokens = LocalKudosTokens.current
    val shape = if (isCircular) androidx.compose.foundation.shape.CircleShape else RoundedCornerShape(8.dp)
    Box(
        modifier = modifier.size(size).clip(shape).background(tokens.glassFill(), shape)
            .semantics { contentDescription = spokenName },
        contentAlignment = Alignment.Center
    ) {
        Icon(
            if (isCircular) Icons.Outlined.AccountCircle else Icons.Outlined.AccountBox,
            contentDescription = null, tint = tokens.secondaryInk, modifier = Modifier.size(size * 0.42f)
        )
        if (url != null) {
            AsyncImage(
                model = ImageRequest.Builder(LocalContext.current).data(url).crossfade(true).build(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        }
    }
}
