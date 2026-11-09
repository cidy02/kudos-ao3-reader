package io.github.cidy02.kudos.library

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.browse.FandomDisplayName
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.ui.components.SensitiveWorkRow
import io.github.cidy02.kudos.ui.subject.KudosTokens
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectKicker
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.SubjectSegmentedControl
import io.github.cidy02.kudos.ui.subject.SubjectStateBadge
import io.github.cidy02.kudos.ui.subject.SwipeActionRow
import io.github.cidy02.kudos.ui.subject.WorkLedgerRow
import io.github.cidy02.kudos.ui.subject.compactCount
import io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale
import io.github.cidy02.kudos.ui.subject.rememberWorkDownloadFraction
import io.github.cidy02.kudos.ui.subject.subjectCard
import io.github.cidy02.kudos.ui.subject.subjectPanel
import java.time.DayOfWeek
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.format.TextStyle as JavaTextStyle
import java.time.temporal.WeekFields
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.roundToInt

/**
 * Reading History as a Week / Month / Year timeline (port of iOS `ReadingHistoryTimelineView`, T-462).
 *
 * Why rows are taller than board 02's compact cards: the ledger work row keeps the author,
 * word/chapter counts, and the four-symbol AO3 tray so no metadata that the old History list
 * showed is lost, with the sitting's chapter cells, detail line, and Started/Finished badge
 * added directly below it.
 */
internal fun LazyListScope.readingHistoryTimelineItems(
    timeline: ReadingHistoryTimeline,
    scope: ReadingHistoryScope,
    onScopeChange: (ReadingHistoryScope) -> Unit,
    onStepPeriod: (Int) -> Unit,
    itemsById: Map<String, LibraryDisplayItem>,
    abandonedWorks: List<LibraryDisplayItem>,
    untimedWorks: List<LibraryDisplayItem>,
    state: LibraryUiState,
    ledger: Boolean,
    expandAll: Boolean,
    cardActions: LibraryCardActions,
    onRemoveFromHistory: (String) -> Unit,
    onRemoveFromAllQueues: (String) -> Unit,
    onKeepInProgress: (String) -> Unit,
    now: Instant,
    zone: ZoneId,
    locale: Locale,
    weekFields: WeekFields
) {
    item(key = "history-timeline-summary") {
        ReadingHistoryPeriodSummary(timeline, scope, onScopeChange, onStepPeriod, now, zone, locale)
    }
    item(key = "history-timeline-chart") {
        ReadingHistoryChart(timeline, now, zone, locale, weekFields)
    }
    if (timeline.scope == ReadingHistoryScope.Month) {
        val topWorksForMonth = timeline.topWorks
            .filter { itemsById[it.workID]?.privacyVisibility == LibraryPrivacyVisibility.Visible }
            .take(3)
        if (topWorksForMonth.isNotEmpty()) {
            item(key = "history-month-most-read-header") {
                SectionRuleHeader("Most read", count = topWorksForMonth.size, modifier = Modifier.padding(top = 6.dp))
            }
            item(key = "history-month-most-read-list") {
                Column(Modifier.fillMaxWidth().padding(horizontal = SubjectMetrics.gutter).subjectPanel()) {
                    topWorksForMonth.forEachIndexed { index, item ->
                        if (index > 0) SubjectRowSeparator()
                        TopWorkRow(rank = index + 1, item = item, work = itemsById[item.workID]?.item?.work) { work ->
                            if (work.hasEpub) cardActions.onOpenReader(work.id) else cardActions.onOpenWork(work.id)
                        }
                    }
                }
            }
        }
    }
    if (timeline.scope == ReadingHistoryScope.Year && timeline.totalSeconds > 0.0) {
        item(key = "history-year-facts") { YearFactsSection(timeline) }
    }
    if (timeline.days.isEmpty()) {
        item(key = "history-empty-period") { EmptyPeriodNotice(timeline) }
    } else {
        timeline.days.forEach { day ->
            item(key = "history-day-${day.start.epochSecond}") {
                SectionRuleHeader(
                    title = dayTitle(day.start, now, zone, locale),
                    countText = ReadingInsights.durationLabel(day.totalSeconds),
                    modifier = Modifier.padding(top = 8.dp)
                )
            }
            day.sittings.forEachIndexed { index, sitting ->
                item(key = "history-sitting-${sitting.id}") {
                    SittingTimelineRow(
                        sitting = sitting,
                        isLastInDay = index == day.sittings.lastIndex,
                        display = itemsById[sitting.workID],
                        state = state,
                        ledger = ledger,
                        expandAll = expandAll,
                        actions = cardActions,
                        onRemoveFromHistory = onRemoveFromHistory,
                        onRemoveFromAllQueues = onRemoveFromAllQueues,
                        now = now,
                        zone = zone,
                        locale = locale
                    )
                }
            }
        }
    }
    if (abandonedWorks.isNotEmpty()) {
        item(key = "history-abandoned-header") {
            SectionRuleHeader(
                title = "Abandoned",
                count = abandonedWorks.size,
                note = "In progress, untouched for 21 days",
                modifier = Modifier.padding(top = 8.dp)
            )
        }
        items(abandonedWorks, key = { "history-abandoned-${it.item.work.id}" }) { display ->
            val id = display.item.work.id
            LibrarySubjectLedgerRow(
                display = display, kind = LibrarySectionKind.History, actions = cardActions,
                onRemoveFromHistory = onRemoveFromHistory, onRemoveFromAllQueues = onRemoveFromAllQueues,
                selected = id in state.selectedWorkIds, selecting = state.selectionMode,
                showsZeroStats = state.showsZeroStats, ledger = ledger, expandAll = expandAll,
                summary = state.readingSummaries[id], abandoned = true, onKeepInProgress = onKeepInProgress
            )
        }
    }
    if (untimedWorks.isNotEmpty()) {
        item(key = "history-untimed-header") {
            SectionRuleHeader(
                title = "No reading time recorded",
                count = untimedWorks.size,
                note = "Read before Kudos kept time",
                modifier = Modifier.padding(top = 8.dp)
            )
        }
        items(untimedWorks, key = { "history-untimed-${it.item.work.id}" }) { display ->
            val id = display.item.work.id
            LibrarySubjectLedgerRow(
                display = display, kind = LibrarySectionKind.History, actions = cardActions,
                onRemoveFromHistory = onRemoveFromHistory, onRemoveFromAllQueues = onRemoveFromAllQueues,
                selected = id in state.selectedWorkIds, selecting = state.selectionMode,
                showsZeroStats = state.showsZeroStats, ledger = ledger, expandAll = expandAll,
                summary = state.readingSummaries[id], abandoned = false, onKeepInProgress = onKeepInProgress
            )
        }
    }
}

@Composable
private fun ReadingHistoryPeriodSummary(
    timeline: ReadingHistoryTimeline,
    scope: ReadingHistoryScope,
    onScopeChange: (ReadingHistoryScope) -> Unit,
    onStepPeriod: (Int) -> Unit,
    now: Instant,
    zone: ZoneId,
    locale: Locale
) {
    val tokens = LocalKudosTokens.current
    Column(
        Modifier.fillMaxWidth().padding(horizontal = SubjectMetrics.gutter),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        SubjectSegmentedControl(
            options = ReadingHistoryScope.entries,
            selected = scope,
            onSelect = onScopeChange,
            title = { it.title }
        )
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(periodTitle(timeline, now, zone, locale), color = tokens.secondaryInk,
                    fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                Text(ReadingInsights.durationLabel(timeline.totalSeconds), color = tokens.primaryInk,
                    fontSize = 28.sp, lineHeight = 34.sp, fontWeight = FontWeight.Bold,
                    style = TextStyle(fontFeatureSettings = "tnum"))
                Text(summaryLine(timeline), color = tokens.secondaryInk, fontSize = 13.sp, lineHeight = 18.sp)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                PeriodStepButton(
                    icon = Icons.AutoMirrored.Outlined.KeyboardArrowLeft,
                    label = "Previous ${scope.title.lowercase(Locale.ROOT)}",
                    enabled = true,
                    onClick = { onStepPeriod(-1) }
                )
                PeriodStepButton(
                    icon = Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                    label = "Next ${scope.title.lowercase(Locale.ROOT)}",
                    enabled = !timeline.isCurrent,
                    onClick = { onStepPeriod(1) }
                )
            }
        }
    }
}

@Composable
private fun PeriodStepButton(
    icon: ImageVector,
    label: String,
    enabled: Boolean,
    onClick: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    Box(
        Modifier.size(34.dp).subjectPanel(cornerRadius = 17.dp)
            .then(if (enabled) Modifier.clickable(role = Role.Button, onClick = onClick) else Modifier)
            .semantics { contentDescription = label; if (!enabled) disabled() },
        contentAlignment = Alignment.Center
    ) {
        Icon(icon, contentDescription = null,
            tint = if (enabled) tokens.primaryInk else tokens.tertiaryInk,
            modifier = Modifier.size(18.dp))
    }
}

@Composable
internal fun ReadingHistoryChart(
    timeline: ReadingHistoryTimeline,
    now: Instant,
    zone: ZoneId,
    locale: Locale,
    weekFields: WeekFields
) {
    val summary = timeline.chartSummary(periodTitle(timeline, now, zone, locale), zone, locale)
    Box(
        Modifier.fillMaxWidth().padding(horizontal = SubjectMetrics.gutter)
            .subjectPanel().padding(14.dp)
            .clearAndSetSemantics { contentDescription = summary }
    ) {
        when (timeline.scope) {
            ReadingHistoryScope.Week -> WeekChart(timeline, zone, locale)
            ReadingHistoryScope.Month -> MonthHeatmap(timeline, now, zone, locale, weekFields)
            ReadingHistoryScope.Year -> YearChart(timeline, zone, locale)
        }
    }
}

@Composable
private fun WeekChart(timeline: ReadingHistoryTimeline, zone: ZoneId, locale: Locale) {
    val tokens = LocalKudosTokens.current
    val buckets = timeline.buckets
    val average = timeline.averageBucketSeconds
    val latestActiveStart = buckets.lastOrNull { !it.isFuture }?.start
    val maxSeconds = maxOf(buckets.maxOfOrNull { it.seconds } ?: 0.0, average, 60.0)

    Column(Modifier.fillMaxWidth()) {
        Box(Modifier.fillMaxWidth().height(128.dp)) {
            val accent = tokens.accent
            val barMuted = tokens.accent.copy(alpha = 0.55f)
            val ruleColor = tokens.glassStroke(0.18)
            val avgColor = tokens.secondaryInk.copy(alpha = 0.65f)

            Canvas(Modifier.fillMaxSize()) {
                if (buckets.isEmpty()) return@Canvas
                val usableHeight = (size.height - 18.dp.toPx()).coerceAtLeast(1f)
                val slotWidth = size.width / buckets.size.toFloat()
                val barWidth = (slotWidth * 0.56f).coerceAtMost(28.dp.toPx())
                val corner = CornerRadius(5.dp.toPx())

                buckets.forEachIndexed { index, bucket ->
                    if (!bucket.isFuture && bucket.seconds > 0.0) {
                        val barHeight = ((bucket.seconds / maxSeconds).toFloat() * usableHeight)
                            .coerceAtLeast(3.dp.toPx())
                        val x = index * slotWidth + (slotWidth - barWidth) / 2f
                        drawRoundRect(
                            color = if (bucket.start == latestActiveStart) accent else barMuted,
                            topLeft = Offset(x, size.height - barHeight),
                            size = Size(barWidth, barHeight),
                            cornerRadius = corner
                        )
                    }
                }
                drawLine(ruleColor, Offset(0f, size.height), Offset(size.width, size.height), 1.dp.toPx())
                if (average > 0.0) {
                    val avgY = size.height - ((average / maxSeconds).toFloat() * usableHeight)
                    drawLine(
                        color = avgColor,
                        start = Offset(0f, avgY),
                        end = Offset(size.width, avgY),
                        strokeWidth = 1.dp.toPx(),
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 3.dp.toPx()))
                    )
                }
            }
            if (average > 0.0) {
                Text("avg ${ReadingInsights.durationLabel(average)}", color = tokens.secondaryInk,
                    fontSize = 10.sp, fontWeight = FontWeight.Medium,
                    style = TextStyle(fontFeatureSettings = "tnum"),
                    modifier = Modifier.align(Alignment.TopEnd))
            }
        }
        Row(Modifier.fillMaxWidth().padding(top = 6.dp)) {
            buckets.forEach { bucket ->
                val label = bucket.start.atZone(zone).dayOfWeek.getDisplayName(JavaTextStyle.NARROW, locale)
                Text(label, color = tokens.secondaryInk, fontSize = 10.sp,
                    textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun MonthHeatmap(
    timeline: ReadingHistoryTimeline,
    now: Instant,
    zone: ZoneId,
    locale: Locale,
    weekFields: WeekFields
) {
    val tokens = LocalKudosTokens.current
    val large = isAccessibilityFontScale()
    val weekdays = orderedWeekdays(weekFields)
    val rows = monthCells(timeline.buckets, zone, weekFields).chunked(7)
    val maxSeconds = maxOf(timeline.buckets.maxOfOrNull { it.seconds } ?: 0.0, 1.0)
    val todayDate = now.atZone(zone).toLocalDate()
    val minCellHeight = if (large) 30.dp else 38.dp

    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            weekdays.forEach { dayOfWeek ->
                Text(dayOfWeek.getDisplayName(JavaTextStyle.NARROW, locale), color = tokens.secondaryInk,
                    fontSize = 10.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center,
                    modifier = Modifier.weight(1f))
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
            rows.forEach { row ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    for (col in 0 until 7) {
                        val bucket = row.getOrNull(col)
                        if (bucket == null) {
                            Spacer(Modifier.weight(1f).heightIn(min = minCellHeight))
                        } else {
                            val date = bucket.start.atZone(zone).toLocalDate()
                            val isToday = date == todayDate
                            val minutes = (bucket.seconds / 60.0).roundToInt()
                            val shape = RoundedCornerShape(6.dp)
                            Column(
                                Modifier.weight(1f).heightIn(min = minCellHeight)
                                    .background(dayShade(bucket, maxSeconds, tokens), shape)
                                    .border(
                                        width = if (isToday) 1.5.dp else 0.5.dp,
                                        color = if (isToday) tokens.accent else tokens.glassStroke(0.10),
                                        shape = shape
                                    )
                                    .padding(vertical = 4.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.Center
                            ) {
                                Text(
                                    text = date.dayOfMonth.toString(),
                                    color = if (bucket.isFuture) tokens.tertiaryInk else tokens.primaryInk,
                                    fontSize = 11.sp,
                                    fontWeight = if (minutes > 0) FontWeight.SemiBold else FontWeight.Normal,
                                    style = TextStyle(fontFeatureSettings = "tnum")
                                )
                                if (!large) {
                                    Text(
                                        text = if (minutes > 0) "${minutes}m" else " ",
                                        color = tokens.secondaryInk,
                                        fontSize = 9.sp,
                                        maxLines = 1,
                                        style = TextStyle(fontFeatureSettings = "tnum")
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(5.dp)
        ) {
            Spacer(Modifier.weight(1f))
            Text("Less", color = tokens.secondaryInk, fontSize = 10.sp)
            listOf(0.0, 0.22, 0.45, 0.70, 0.95).forEach { alpha ->
                val fill = if (alpha == 0.0) tokens.glassFill(0.06) else tokens.accent.copy(alpha = alpha.toFloat())
                Box(Modifier.size(10.dp).background(fill, RoundedCornerShape(2.5.dp)))
            }
            Text("More", color = tokens.secondaryInk, fontSize = 10.sp)
        }
    }
}

private fun dayShade(bucket: ReadingHistoryTimeline.Bucket, maxSeconds: Double, tokens: KudosTokens): Color {
    if (bucket.isFuture) return Color.Transparent
    if (bucket.seconds <= 0.0) return tokens.glassFill(0.06)
    val ratio = (bucket.seconds / maxSeconds).coerceIn(0.0, 1.0)
    return tokens.accent.copy(alpha = (0.22 + ratio * 0.73).toFloat())
}

@Composable
private fun YearChart(timeline: ReadingHistoryTimeline, zone: ZoneId, locale: Locale) {
    val tokens = LocalKudosTokens.current
    val buckets = timeline.buckets
    val maxHours = maxOf((buckets.maxOfOrNull { it.seconds } ?: 0.0) / 3600.0, 1.0)

    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Column(Modifier.fillMaxWidth()) {
            Row(
                Modifier.fillMaxWidth().height(136.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.Bottom
            ) {
                buckets.forEach { bucket ->
                    val hours = bucket.seconds / 3600.0
                    val fraction = if (bucket.isFuture || hours <= 0.0) 0f
                    else (hours / maxHours).toFloat().coerceIn(0.04f, 1f)
                    Column(
                        Modifier.weight(1f).fillMaxHeight(),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Bottom
                    ) {
                        if (bucket.finishedCount > 0 && !bucket.isFuture) {
                            Text(bucket.finishedCount.toString(), color = tokens.accentInk,
                                fontSize = 9.sp, fontWeight = FontWeight.Bold,
                                style = TextStyle(fontFeatureSettings = "tnum"))
                        }
                        if (fraction > 0f) {
                            Box(
                                Modifier.fillMaxWidth(0.68f).fillMaxHeight(fraction * 0.82f)
                                    .heightIn(min = 3.dp).background(tokens.accent, RoundedCornerShape(4.dp))
                            )
                        } else {
                            Spacer(Modifier.height(1.dp))
                        }
                    }
                }
            }
            Box(Modifier.fillMaxWidth().height(1.dp).background(tokens.glassStroke(0.18)))
            Row(Modifier.fillMaxWidth().padding(top = 6.dp)) {
                buckets.forEach { bucket ->
                    val label = bucket.start.atZone(zone).month.getDisplayName(JavaTextStyle.NARROW, locale)
                    Text(label, color = tokens.secondaryInk, fontSize = 10.sp,
                        textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
                }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Box(Modifier.size(10.dp).background(tokens.accent, RoundedCornerShape(2.5.dp)))
                Text("Hours read", color = tokens.secondaryInk, fontSize = 11.sp)
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Text("3", color = tokens.accentInk, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                Text("Works finished", color = tokens.secondaryInk, fontSize = 11.sp)
            }
        }
    }
}

@Composable
private fun TopWorkRow(
    rank: Int,
    item: ReadingHistoryTimeline.WorkTime,
    work: SavedWork?,
    onOpen: (SavedWork) -> Unit
) {
    val tokens = LocalKudosTokens.current
    val large = isAccessibilityFontScale()
    val title = work?.title ?: item.title.ifEmpty { "Untitled" }
    val fandom = FandomDisplayName.bareTitle(
        work?.workFandoms?.firstOrNull().orEmpty().ifEmpty { item.fandom }
    )
    val rowModifier = Modifier.fillMaxWidth()
        .then(if (work != null) Modifier.clickable(role = Role.Button) { onOpen(work) } else Modifier)
        .padding(horizontal = 14.dp, vertical = 11.dp)

    if (large) {
        Column(rowModifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("$rank. $title", color = tokens.primaryInk, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            if (fandom.isNotEmpty()) Text(fandom, color = tokens.secondaryInk, fontSize = 12.sp)
            Text(ReadingInsights.durationLabel(item.seconds), color = tokens.secondaryInk,
                fontSize = 13.sp, fontWeight = FontWeight.SemiBold, style = TextStyle(fontFeatureSettings = "tnum"))
        }
    } else {
        Row(rowModifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(rank.toString(), color = tokens.secondaryInk, fontSize = 13.sp, fontWeight = FontWeight.Bold,
                style = TextStyle(fontFeatureSettings = "tnum"), modifier = Modifier.width(18.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(title, color = tokens.primaryInk, fontSize = 14.sp, fontWeight = FontWeight.SemiBold,
                    maxLines = 2, overflow = TextOverflow.Ellipsis)
                if (fandom.isNotEmpty()) {
                    Text(fandom, color = tokens.secondaryInk, fontSize = 12.sp,
                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            Text(ReadingInsights.durationLabel(item.seconds), color = tokens.secondaryInk,
                fontSize = 13.sp, fontWeight = FontWeight.SemiBold, style = TextStyle(fontFeatureSettings = "tnum"))
        }
    }
}

private data class YearFactCardData(
    val kicker: String,
    val value: String,
    val detail: String,
    val palette: SubjectPalette
)

@Composable
private fun YearFactsSection(timeline: ReadingHistoryTimeline) {
    val tokens = LocalKudosTokens.current
    val large = isAccessibilityFontScale()
    val cards = listOf(
        YearFactCardData(
            kicker = "Longest streak",
            value = if (timeline.longestStreakDays == 1) "1 day" else "${timeline.longestStreakDays} days",
            detail = "Consecutive reading days",
            palette = tokens.scopePalette
        ),
        YearFactCardData(
            kicker = "Most-read fandom",
            value = timeline.topFandom?.let { FandomDisplayName.bareTitle(it.name) } ?: "—",
            detail = timeline.topFandom?.let { ReadingInsights.durationLabel(it.seconds) } ?: "No fandom recorded",
            palette = timeline.topFandom?.let {
                SubjectPalette.fromHue(HomeFacts.workHue(listOf(it.name), it.name), tokens.theme)
            } ?: tokens.scopePalette
        ),
        YearFactCardData(
            kicker = "Longest work finished",
            value = timeline.longestFinishedWork?.let { "${it.wordCount.compactCount()} words" } ?: "—",
            detail = timeline.longestFinishedWork?.title?.takeIf { it.isNotEmpty() } ?: "No finished works",
            palette = tokens.scopePalette
        ),
        YearFactCardData(
            kicker = "Favourite time",
            value = timeline.favoriteTimeOfDay?.title ?: "—",
            detail = timeline.favoriteTimeOfDay?.hours ?: "No sessions",
            palette = tokens.scopePalette
        )
    )

    Column(
        Modifier.fillMaxWidth().padding(horizontal = SubjectMetrics.gutter),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        if (large) {
            cards.forEach { card -> YearFactCard(card, Modifier.fillMaxWidth()) }
        } else {
            cards.chunked(2).forEach { pair ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    pair.forEach { card -> YearFactCard(card, Modifier.weight(1f)) }
                }
            }
        }
    }
}

@Composable
private fun YearFactCard(card: YearFactCardData, modifier: Modifier = Modifier) {
    val tokens = LocalKudosTokens.current
    val large = isAccessibilityFontScale()
    Column(
        modifier.subjectCard(card.palette, cornerRadius = 14.dp).padding(13.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        SubjectKicker(text = card.kicker, palette = card.palette, size = 9.5.sp, ruleWidth = 18.dp)
        Text(card.value, color = tokens.primaryInk, fontSize = 18.sp, fontWeight = FontWeight.Bold,
            maxLines = if (large) Int.MAX_VALUE else 2, overflow = TextOverflow.Ellipsis,
            style = TextStyle(fontFeatureSettings = "tnum"))
        Text(card.detail, color = tokens.secondaryInk, fontSize = 11.5.sp,
            maxLines = if (large) Int.MAX_VALUE else 2, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun EmptyPeriodNotice(timeline: ReadingHistoryTimeline) {
    val tokens = LocalKudosTokens.current
    Text(
        text = "Nothing read ${periodNoun(timeline)}.",
        color = tokens.secondaryInk,
        fontSize = 14.sp,
        modifier = Modifier.fillMaxWidth().padding(horizontal = SubjectMetrics.gutter)
            .subjectPanel().padding(horizontal = 16.dp, vertical = 18.dp)
    )
}

@Composable
private fun SittingTimelineRow(
    sitting: ReadingHistoryTimeline.Sitting,
    isLastInDay: Boolean,
    display: LibraryDisplayItem?,
    state: LibraryUiState,
    ledger: Boolean,
    expandAll: Boolean,
    actions: LibraryCardActions,
    onRemoveFromHistory: (String) -> Unit,
    onRemoveFromAllQueues: (String) -> Unit,
    now: Instant,
    zone: ZoneId,
    locale: Locale
) {
    val tokens = LocalKudosTokens.current
    val large = isAccessibilityFontScale()
    val work = display?.item?.work
    val obscured = display?.privacyVisibility == LibraryPrivacyVisibility.Obscured
    val selecting = state.selectionMode
    val selected = work != null && work.id in state.selectedWorkIds
    val muted = work != null && ReadingAbandonment.isAbandoned(work, now)
    var menuOpen by remember(sitting.id) { mutableStateOf(false) }
    val timeText = sittingTime(sitting.startedAt, zone, locale)

    val sittingContent: @Composable () -> Unit = {
        if (large) {
            Column(
                Modifier.fillMaxWidth().padding(horizontal = SubjectMetrics.gutter, vertical = 4.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text(timeText, color = tokens.secondaryInk, fontSize = 11.sp, fontWeight = FontWeight.Medium,
                    style = TextStyle(fontFeatureSettings = "tnum"), modifier = Modifier.clearAndSetSemantics {})
                SittingWorkAndFactsColumn(
                    sitting = sitting, work = work, obscured = obscured, selecting = selecting,
                    selected = selected, muted = muted, ledger = ledger, expandAll = expandAll,
                    showsZeroStats = state.showsZeroStats, actions = actions,
                    onOpenMenu = { if (!obscured && !selecting) menuOpen = true }, timeText = timeText
                )
            }
        } else {
            val dotColor = railDotColor(sitting, work, obscured, tokens)
            val railLineColor = tokens.glassStroke(0.18)
            val cardSurface = tokens.cardFill
            Row(
                Modifier.fillMaxWidth().padding(horizontal = SubjectMetrics.gutter),
                verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = timeText, color = tokens.secondaryInk, fontSize = 11.sp,
                    fontWeight = FontWeight.Medium, textAlign = TextAlign.End, maxLines = 1,
                    style = TextStyle(fontFeatureSettings = "tnum"),
                    modifier = Modifier.width(54.dp).padding(top = 12.dp).clearAndSetSemantics {}
                )
                Row(
                    Modifier.weight(1f).drawBehind {
                        val centerX = 6.dp.toPx()
                        val centerY = 16.dp.toPx()
                        val radius = 6.dp.toPx()
                        if (!isLastInDay) {
                            drawLine(railLineColor, Offset(centerX, centerY + radius), Offset(centerX, size.height), 2.dp.toPx())
                        }
                        if (sitting.didFinish) {
                            drawCircle(dotColor, radius, Offset(centerX, centerY))
                        } else {
                            drawCircle(cardSurface, radius, Offset(centerX, centerY))
                            drawCircle(dotColor, radius - 1.dp.toPx(), Offset(centerX, centerY), style = Stroke(2.dp.toPx()))
                        }
                    },
                    verticalAlignment = Alignment.Top
                ) {
                    Spacer(Modifier.width(22.dp))
                    Box(Modifier.weight(1f).padding(bottom = if (isLastInDay) 4.dp else 14.dp)) {
                        SittingWorkAndFactsColumn(
                            sitting = sitting, work = work, obscured = obscured, selecting = selecting,
                            selected = selected, muted = muted, ledger = ledger, expandAll = expandAll,
                            showsZeroStats = state.showsZeroStats, actions = actions,
                            onOpenMenu = { if (!obscured && !selecting) menuOpen = true }, timeText = timeText
                        )
                    }
                }
            }
        }
    }

    if (work == null || selecting || obscured) {
        sittingContent()
    } else {
        SwipeActionRow(
            leading = leadingSwipeActions(work, LibrarySectionKind.History, actions),
            trailing = trailingSwipeActions(work, LibrarySectionKind.History, actions, onRemoveFromHistory, onRemoveFromAllQueues),
            content = sittingContent
        )
    }
    if (work != null) LibraryWorkMenu(menuOpen, { menuOpen = false }, work, actions)
}

@Composable
private fun SittingWorkAndFactsColumn(
    sitting: ReadingHistoryTimeline.Sitting,
    work: SavedWork?,
    obscured: Boolean,
    selecting: Boolean,
    selected: Boolean,
    muted: Boolean,
    ledger: Boolean,
    expandAll: Boolean,
    showsZeroStats: Boolean,
    actions: LibraryCardActions,
    onOpenMenu: () -> Unit,
    timeText: String
) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (work != null) {
            val progress = work.readingProgressFraction() ?: 0.0
            if (ledger) {
                WorkLedgerRow(
                    title = work.title,
                    author = work.author.ifBlank { "Anonymous" },
                    fandoms = work.workFandoms,
                    metadata = HomeFacts.localWorkMetadata(work.author, work.wordCount, work.chapters).joinToString(" · "),
                    progress = progress,
                    downloadFraction = rememberWorkDownloadFraction(work),
                    progressState = if (progress <= 0.0) null else if (progress >= 1.0) "Finished" else "Reading",
                    rating = work.rating,
                    categories = work.workCategories,
                    warnings = work.workWarnings,
                    isComplete = work.knownCompletion,
                    obscured = obscured,
                    favorite = work.isFavorite,
                    selected = selected,
                    selecting = selecting,
                    muted = muted,
                    onClick = {
                        when {
                            selecting -> actions.onSelect(work.id)
                            obscured -> actions.onReveal(work.id)
                            work.hasEpub -> actions.onOpenReader(work.id)
                            else -> actions.onOpenWork(work.id)
                        }
                    },
                    onLongClick = onOpenMenu
                )
            } else {
                SensitiveWorkRow(
                    work = work,
                    showsZeroStats = showsZeroStats,
                    mutedHistory = muted,
                    onOpenWork = { if (work.hasEpub) actions.onOpenReader(work.id) else actions.onOpenWork(work.id) },
                    selecting = selecting,
                    selected = selected,
                    obscured = obscured,
                    expandAll = expandAll,
                    onSelect = { actions.onSelect(work.id) },
                    onReveal = { actions.onReveal(work.id) },
                    onLongClick = onOpenMenu
                )
            }
        } else {
            MissingSittingWorkRow(sitting)
        }
        SittingFactsRow(sitting, work, obscured, timeText)
    }
}

@Composable
private fun MissingSittingWorkRow(sitting: ReadingHistoryTimeline.Sitting) {
    val tokens = LocalKudosTokens.current
    Column(
        Modifier.fillMaxWidth().subjectPanel(cornerRadius = 12.dp).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(3.dp)
    ) {
        if (sitting.fandom.isNotEmpty()) {
            Text(FandomDisplayName.bareTitle(sitting.fandom).uppercase(),
                color = tokens.secondaryInk, fontSize = 10.sp, fontWeight = FontWeight.Bold)
        }
        Text(sitting.title.ifEmpty { "Removed work" },
            color = tokens.primaryInk, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun SittingFactsRow(
    sitting: ReadingHistoryTimeline.Sitting,
    work: SavedWork?,
    obscured: Boolean,
    timeText: String
) {
    val tokens = LocalKudosTokens.current
    val large = isAccessibilityFontScale()
    val workColor = sittingWorkColor(sitting, work, obscured, tokens)
    val a11yLabel = sittingAccessibilityLabel(sitting, timeText)

    Column(
        Modifier.fillMaxWidth().semantics(mergeDescendants = true) { contentDescription = a11yLabel },
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        if (sitting.chapters != null && !obscured) {
            ChapterCells(span = sitting.chapters, color = workColor)
        }
        if (large) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(sitting.detailLine, color = tokens.secondaryInk, fontSize = 12.sp,
                    fontWeight = FontWeight.Medium, style = TextStyle(fontFeatureSettings = "tnum"))
                sitting.badge?.let { badge ->
                    SubjectStateBadge(badge.title, badgeColor(badge, sitting, work, obscured, tokens))
                }
            }
        } else {
            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(sitting.detailLine, color = tokens.secondaryInk, fontSize = 12.sp,
                    fontWeight = FontWeight.Medium, style = TextStyle(fontFeatureSettings = "tnum"),
                    modifier = Modifier.weight(1f))
                sitting.badge?.let { badge ->
                    SubjectStateBadge(badge.title, badgeColor(badge, sitting, work, obscured, tokens))
                }
            }
        }
    }
}

private const val MaxDrawnChapterCells = 30

@Composable
internal fun ChapterCells(
    span: ReadingHistoryTimeline.ChapterSpan,
    color: Color,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val cells = minOf(span.total, MaxDrawnChapterCells)
    val futureColor = tokens.secondaryInk.copy(alpha = 0.26f)
    Canvas(modifier.fillMaxWidth().height(6.dp).clearAndSetSemantics {}) {
        if (cells <= 0) return@Canvas
        val gap = (if (cells > 16) 2.dp else 3.dp).toPx()
        val totalGap = gap * maxOf(0, cells - 1).toFloat()
        val cellWidth = maxOf(2f, (size.width - totalGap) / cells.toFloat())
        val scale = cells.toDouble() / span.total.toDouble()
        val firstCell = maxOf(1, floor((span.first - 1).toDouble() * scale).toInt() + 1)
        val lastCell = maxOf(firstCell, ceil(span.last.toDouble() * scale).toInt())
        val corner = CornerRadius(2.dp.toPx())
        for (cell in 1..cells) {
            val x = (cell - 1).toFloat() * (cellWidth + gap)
            val fill = when {
                cell < firstCell -> color.copy(alpha = 0.32f)
                cell <= lastCell -> color
                else -> futureColor
            }
            drawRoundRect(fill, Offset(x, 0f), Size(cellWidth, size.height), corner)
        }
    }
}

private fun sittingWorkColor(
    sitting: ReadingHistoryTimeline.Sitting,
    work: SavedWork?,
    obscured: Boolean,
    tokens: KudosTokens
): Color {
    if (obscured) return tokens.secondaryInk
    val hue = if (work != null) HomeFacts.workHue(work.workFandoms, work.title)
    else HomeFacts.workHue(listOf(sitting.fandom), sitting.title)
    return SubjectPalette.fromHue(hue, tokens.theme).accent
}

private fun railDotColor(
    sitting: ReadingHistoryTimeline.Sitting,
    work: SavedWork?,
    obscured: Boolean,
    tokens: KudosTokens
): Color = if (sitting.didFinish) tokens.accent else sittingWorkColor(sitting, work, obscured, tokens)

private fun badgeColor(
    badge: ReadingHistoryTimeline.Badge,
    sitting: ReadingHistoryTimeline.Sitting,
    work: SavedWork?,
    obscured: Boolean,
    tokens: KudosTokens
): Color = when (badge) {
    ReadingHistoryTimeline.Badge.Finished -> tokens.accentInk
    ReadingHistoryTimeline.Badge.Started -> sittingWorkColor(sitting, work, obscured, tokens)
}

private fun sittingAccessibilityLabel(sitting: ReadingHistoryTimeline.Sitting, timeText: String): String {
    val parts = mutableListOf("Read at $timeText")
    sitting.chapters?.let { parts += it.accessibilityLabel }
    parts += sitting.detailLine
    sitting.badge?.let { parts += it.title }
    return parts.joinToString(", ")
}

private fun periodTitle(
    timeline: ReadingHistoryTimeline,
    now: Instant,
    zone: ZoneId,
    locale: Locale
): String = when (timeline.scope) {
    ReadingHistoryScope.Week -> {
        if (timeline.isCurrent) "This week"
        else {
            val fmt = DateTimeFormatter.ofPattern("MMM d", locale)
            val start = timeline.period.start.atZone(zone).toLocalDate()
            val end = timeline.period.end.atZone(zone).toLocalDate().minusDays(1)
            "${fmt.format(start)} – ${fmt.format(end)}"
        }
    }
    ReadingHistoryScope.Month ->
        DateTimeFormatter.ofPattern("MMMM yyyy", locale).format(timeline.period.start.atZone(zone))
    ReadingHistoryScope.Year ->
        timeline.period.start.atZone(zone).year.toString()
}

private fun summaryLine(timeline: ReadingHistoryTimeline): String {
    val parts = mutableListOf<String>()
    parts += if (timeline.workCount == 1) "1 work" else "${timeline.workCount} works"
    if (timeline.finishedCount > 0) parts += "${timeline.finishedCount} finished"
    if (timeline.scope == ReadingHistoryScope.Month) {
        val readDays = timeline.buckets.count { !it.isFuture && it.seconds > 0.0 }
        val elapsedDays = maxOf(1, timeline.buckets.count { !it.isFuture })
        if (readDays > 0) parts += "read on $readDays of $elapsedDays days"
    }
    if (timeline.streakDays > 1) parts += "${timeline.streakDays}-day streak"
    return parts.joinToString(" · ")
}

private fun periodNoun(timeline: ReadingHistoryTimeline): String = when (timeline.scope) {
    ReadingHistoryScope.Week -> if (timeline.isCurrent) "this week" else "that week"
    ReadingHistoryScope.Month -> if (timeline.isCurrent) "this month" else "that month"
    ReadingHistoryScope.Year -> if (timeline.isCurrent) "this year" else "that year"
}

private fun dayTitle(dayStart: Instant, now: Instant, zone: ZoneId, locale: Locale): String {
    val date = dayStart.atZone(zone).toLocalDate()
    val today = now.atZone(zone).toLocalDate()
    if (date == today) return "Today"
    if (date == today.minusDays(1)) return "Yesterday"
    val pattern = if (date.year == today.year) "EEEE, MMM d" else "EEEE, MMM d, yyyy"
    return DateTimeFormatter.ofPattern(pattern, locale).format(date)
}

private fun sittingTime(startedAt: Instant, zone: ZoneId, locale: Locale): String =
    DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale).format(startedAt.atZone(zone))

private fun orderedWeekdays(weekFields: WeekFields): List<DayOfWeek> =
    (0L until 7L).map { weekFields.firstDayOfWeek.plus(it) }

private fun monthCells(
    buckets: List<ReadingHistoryTimeline.Bucket>,
    zone: ZoneId,
    weekFields: WeekFields
): List<ReadingHistoryTimeline.Bucket?> {
    val first = buckets.firstOrNull()?.start ?: return emptyList()
    val firstDow = first.atZone(zone).dayOfWeek
    val offset = ((firstDow.value - weekFields.firstDayOfWeek.value) + 7) % 7
    return List(offset) { null } + buckets
}
