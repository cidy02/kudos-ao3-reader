package io.github.cidy02.kudos.library

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import io.github.cidy02.kudos.app.PrivacyGate
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.data.local.dao.ReadingLogDao
import io.github.cidy02.kudos.data.local.entity.ReadingSessionEntity
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.ToolbarCircleButton
import io.github.cidy02.kudos.ui.subject.subjectPanel
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import java.text.NumberFormat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToInt
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn

data class ReadingStatisticsUiState(
    val loading: Boolean = true,
    val statistics: ReadingStatistics? = null,
    val insights: ReadingInsights = ReadingInsights(),
    val period: ReadingInsightsPeriod = ReadingInsightsPeriod.Month,
    val now: Instant = Instant.now(),
    val error: String? = null
)

class ReadingStatisticsViewModel(
    libraryRepository: LibraryRepository,
    readingLogDao: ReadingLogDao? = null,
    settingsRepository: SettingsRepository? = null,
    privacyGate: PrivacyGate = PrivacyGate()
) : ViewModel() {
    private val period = MutableStateFlow(ReadingInsightsPeriod.Month)
    private val referenceNow = MutableStateFlow(Instant.now())
    private val periodAndNow = combine(period, referenceNow) { selected, now -> selected to now }
    private val sessions = readingLogDao?.observeSessions()
        ?: flowOf(emptyList<ReadingSessionEntity>())

    val state: StateFlow<ReadingStatisticsUiState> = combine(
        libraryRepository.observeStatisticsWorks(),
        settingsRepository?.settings ?: flowOf(KudosSettings()),
        privacyGate.state,
        sessions,
        periodAndNow
    ) { works, settings, reveal, sessions, selected ->
        val visible = works.filter { work ->
            LibraryPrivacy.visibility(work, settings.privacy, reveal) ==
                LibraryPrivacyVisibility.Visible
        }
        val (selectedPeriod, now) = selected
        ReadingStatisticsUiState(
            loading = false,
            statistics = ReadingStatistics.from(visible, now),
            insights = ReadingInsights.from(
                sessions = sessions,
                works = visible,
                period = selectedPeriod,
                now = now
            ),
            period = selectedPeriod,
            now = now
        )
    }.catch { throwable ->
        emit(
            ReadingStatisticsUiState(
                loading = false,
                period = period.value,
                now = referenceNow.value,
                error = throwable.message ?: "Reading Insights could not be loaded."
            )
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = ReadingStatisticsUiState()
    )

    fun selectPeriod(value: ReadingInsightsPeriod) {
        period.value = value
        referenceNow.value = Instant.now()
    }

    fun refresh() {
        referenceNow.value = Instant.now()
    }

    companion object {
        fun factory(
            libraryRepository: LibraryRepository,
            readingLogDao: ReadingLogDao? = null,
            settingsRepository: SettingsRepository? = null,
            privacyGate: PrivacyGate = PrivacyGate()
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                ReadingStatisticsViewModel(
                    libraryRepository,
                    readingLogDao,
                    settingsRepository,
                    privacyGate
                )
            }
        }
    }
}

@Composable
fun ReadingStatisticsScreen(
    libraryRepository: LibraryRepository,
    readingLogDao: ReadingLogDao? = null,
    settingsRepository: SettingsRepository? = null,
    privacyGate: PrivacyGate = PrivacyGate()
) {
    val viewModel: ReadingStatisticsViewModel = viewModel(
        factory = ReadingStatisticsViewModel.factory(
            libraryRepository,
            readingLogDao,
            settingsRepository,
            privacyGate
        )
    )
    val state by viewModel.state.collectAsState()
    val tokens = LocalKudosTokens.current
    var periodMenuOpen by remember { mutableStateOf(false) }

    ProvidePushedShellChrome(
        hasSubjectHeader = true,
        trailingContent = {
            Box {
                ToolbarCircleButton(
                    onClick = { periodMenuOpen = true },
                    accessibilityName = "More"
                ) {
                    Icon(Icons.Filled.MoreVert, contentDescription = null)
                }
                DropdownMenu(
                    expanded = periodMenuOpen,
                    onDismissRequest = { periodMenuOpen = false }
                ) {
                    DropdownMenuItem(
                        text = {
                            Text(
                                text = "Period",
                                color = tokens.secondaryInk,
                                fontWeight = FontWeight.SemiBold
                            )
                        },
                        enabled = false,
                        onClick = {}
                    )
                    ReadingInsightsPeriod.entries.forEach { period ->
                        DropdownMenuItem(
                            text = { Text(period.title) },
                            leadingIcon = {
                                if (period == state.period) {
                                    Icon(Icons.Filled.Check, contentDescription = "Selected")
                                }
                            },
                            onClick = {
                                periodMenuOpen = false
                                viewModel.selectPeriod(period)
                            }
                        )
                    }
                }
            }
        }
    )

    ReadingStatisticsContent(
        state = state,
        onRefresh = { viewModel.refresh() }
    )
}

@Composable
private fun ReadingStatisticsContent(
    state: ReadingStatisticsUiState,
    onRefresh: suspend () -> Unit
) {
    val tokens = LocalKudosTokens.current
    val palette = tokens.scopePalette
    val topInset = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()

    KudosRefreshBox(onRefresh = onRefresh, modifier = Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .subjectScreenWash(palette),
            contentPadding = PaddingValues(
                start = 16.dp,
                top = topInset + 56.dp,
                end = 16.dp,
                bottom = 24.dp
            ),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                SubjectHeaderBlock(
                    kicker = "Library",
                    title = "Reading Insights",
                    subtitle = headerTally(state),
                    palette = palette,
                    gutter = 0.dp,
                    modifier = Modifier.padding(bottom = 4.dp)
                )
            }

            if (state.loading) {
                item { LoadingStateCard("Loading Reading Insights") }
                return@LazyColumn
            }

            state.error?.let { error ->
                item {
                    ErrorStateCard(
                        title = "Reading Insights could not load",
                        message = error
                    )
                }
                return@LazyColumn
            }

            val statistics = state.statistics ?: return@LazyColumn
            val hasSessions = state.insights.totalSeconds > 0
            if (!hasSessions && statistics.totalWorks == 0) {
                item {
                    EmptyStateCard(
                        title = "No reading logged yet",
                        message = "Open a work and read for at least " +
                            "${ReadingInsights.minimumPersistableDurationSeconds} seconds. " +
                            "Your reading activity stays on this device and isn't sent anywhere."
                    )
                }
                return@LazyColumn
            }

            if (hasSessions) {
                item {
                    SectionRuleHeader(
                        title = state.period.title,
                        count = state.insights.weeklySeconds.size,
                        modifier = Modifier.padding(top = 2.dp)
                    )
                }
                item {
                    HoursCard(
                        insights = state.insights,
                        period = state.period,
                        now = state.now,
                        palette = palette
                    )
                }

                item {
                    SectionRuleHeader(
                        title = "Where the hours went",
                        count = state.insights.byFandom.size,
                        modifier = Modifier.padding(top = 6.dp)
                    )
                }
                item {
                    FandomHoursCard(state.insights.byFandom, palette)
                }

                item {
                    SectionRuleHeader(
                        title = "Pace and follow-through",
                        modifier = Modifier.padding(top = 6.dp)
                    )
                }
                item { PaceCard(state.insights) }
            } else {
                item { NoSessionsNote(state.period) }
            }

            item {
                SectionRuleHeader(
                    title = "Your library",
                    count = statistics.totalWorks,
                    modifier = Modifier.padding(top = 6.dp)
                )
            }
            item { LibraryCard(statistics, state.now) }

            val topFandoms = statistics.topFandoms.take(6)
            if (topFandoms.isNotEmpty()) {
                item {
                    SectionRuleHeader(
                        title = "Most-read fandoms",
                        count = topFandoms.size,
                        modifier = Modifier.padding(top = 6.dp)
                    )
                }
                item { MostReadFandomsCard(topFandoms, palette) }
            }
        }
    }
}

@Composable
private fun HoursCard(
    insights: ReadingInsights,
    period: ReadingInsightsPeriod,
    now: Instant,
    palette: SubjectPalette
) {
    val tokens = LocalKudosTokens.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .subjectPanel()
            .padding(horizontal = 18.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(13.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.Bottom
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = ReadingInsights.hoursLabel(insights.totalSeconds),
                    color = tokens.primaryInk,
                    fontSize = 44.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = FontFamily.Monospace,
                    maxLines = 1
                )
                Text(
                    text = "hours in ${periodName(period, now)}",
                    color = tokens.secondaryInk,
                    fontSize = 12.5.sp
                )
            }
            insights.previousPeriodSeconds?.let { previous ->
                val delta = insights.totalSeconds - previous
                Row(
                    modifier = Modifier
                        .subjectPanel(cornerRadius = 50.dp)
                        .padding(horizontal = 12.dp, vertical = 7.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = if (delta < 0) "↘" else "↗",
                        color = if (delta < 0) tokens.secondaryInk else palette.accent,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = ReadingInsights.signedHoursLabel(delta),
                        color = tokens.primaryInk,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Medium,
                        fontFamily = FontFamily.Monospace
                    )
                    Text(
                        text = "vs ${previousPeriodName(period, now)}",
                        color = tokens.secondaryInk,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.SemiBold,
                        fontFamily = FontFamily.Monospace
                    )
                }
            }
        }
        DividerLine()
        WeeklyChart(insights.weeklySeconds, palette)
    }
}

@Composable
private fun WeeklyChart(
    buckets: List<ReadingInsights.WeeklyBucket>,
    palette: SubjectPalette
) {
    val tokens = LocalKudosTokens.current
    val peak = buckets.maxOfOrNull { it.seconds } ?: 0.0
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(7.dp),
        verticalAlignment = Alignment.Bottom
    ) {
        buckets.forEachIndexed { index, bucket ->
            val isLatest = index == buckets.lastIndex
            val fraction = if (peak > 0) {
                (bucket.seconds / peak).toFloat().coerceIn(0.03f, 1f)
            } else {
                0.03f
            }
            Column(
                modifier = Modifier.weight(1f),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(
                    text = ReadingInsights.hoursLabel(bucket.seconds),
                    color = if (isLatest) palette.accent else tokens.secondaryInk,
                    fontSize = 9.5.sp,
                    fontWeight = FontWeight.SemiBold,
                    fontFamily = FontFamily.Monospace,
                    maxLines = 1
                )
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(72.dp),
                    contentAlignment = Alignment.BottomCenter
                ) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth(0.78f)
                            .fillMaxHeight(fraction)
                            .clip(RoundedCornerShape(topStart = 5.dp, topEnd = 5.dp, bottomStart = 2.dp, bottomEnd = 2.dp))
                            .background(palette.accent.copy(alpha = if (isLatest) 0.72f else 0.34f))
                    )
                }
                Text(
                    text = weekLabel(bucket.weekStart),
                    color = tokens.tertiaryInk,
                    fontSize = 8.5.sp,
                    maxLines = 1
                )
            }
        }
    }
}

@Composable
private fun FandomHoursCard(
    fandoms: List<ReadingInsights.FandomShare>,
    palette: SubjectPalette
) {
    val peak = fandoms.maxOfOrNull { it.seconds } ?: 0.0
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .subjectPanel()
            .padding(horizontal = 18.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(13.dp)
    ) {
        fandoms.forEachIndexed { index, fandom ->
            FandomBarRow(
                name = fandom.name,
                value = "${ReadingInsights.hoursLabel(fandom.seconds)} h",
                fraction = share(fandom.seconds, peak),
                rank = index,
                isRemainder = fandom.isRemainder,
                palette = palette
            )
        }
    }
}

@Composable
private fun PaceCard(insights: ReadingInsights) {
    val wordsPerHour = insights.wordsPerHour.roundToInt().takeIf { it > 0 }
        ?.let { NumberFormat.getIntegerInstance().format(it) }
        ?: "—"
    val finishRate = insights.finishRate?.let { "${(it * 100).roundToInt()}%" } ?: "—"
    val streak = insights.longestStreakDays
    val metrics = listOf(
        ReadingInsights.durationLabel(insights.medianSessionSeconds) to "median session",
        wordsPerHour to "words per hour",
        finishRate to "of started works finished",
        "$streak day${if (streak == 1) "" else "s"}" to "longest streak"
    )
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .subjectPanel()
            .padding(horizontal = 18.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(13.dp)
    ) {
        MetricGrid(metrics)
        DividerLine()
        Text(
            text = "Reading time under ${ReadingInsights.minimumPersistableDurationSeconds} seconds isn't counted.",
            color = LocalKudosTokens.current.secondaryInk,
            fontSize = 12.sp
        )
    }
}

@Composable
private fun NoSessionsNote(period: ReadingInsightsPeriod) {
    val tokens = LocalKudosTokens.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .subjectPanel()
            .padding(horizontal = 18.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text(
            text = "No reading logged this ${if (period == ReadingInsightsPeriod.Month) "month" else "year"}",
            color = tokens.primaryInk,
            fontSize = 15.sp,
            fontWeight = FontWeight.SemiBold
        )
        Text(
            text = "Kudos counts reading time only on this device, while a work is open in the reader. " +
                "Your Library totals still appear below.",
            color = tokens.secondaryInk,
            fontSize = 12.5.sp
        )
    }
}

@Composable
private fun LibraryCard(statistics: ReadingStatistics, now: Instant) {
    val metrics = listOf(
        NumberFormat.getIntegerInstance().format(statistics.startedWorks) to "works opened",
        formatCompactNumber(statistics.wordsRead) to "words read",
        NumberFormat.getIntegerInstance().format(statistics.inProgressWorks) to "still in progress",
        NumberFormat.getIntegerInstance().format(statistics.finishedWorks) to
            "finished (${formatPercent(statistics.completionRate)})",
        NumberFormat.getIntegerInstance().format(statistics.openedLast7Days) to "opened in 7 days",
        NumberFormat.getIntegerInstance().format(statistics.openedLast30Days) to "opened in 30 days",
        (statistics.latestReadDate?.let { HomeFacts.relativeNamed(it, now) } ?: "Not yet") to "last read"
    )
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .subjectPanel()
            .padding(horizontal = 18.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(13.dp)
    ) {
        MetricGrid(metrics)
        DividerLine()
        Text(
            text = "Words read includes finished works when AO3 provides a word count. " +
                "Recent activity counts each work you opened once. Finished includes works " +
                "you completed before Kudos began recording time.",
            color = LocalKudosTokens.current.secondaryInk,
            fontSize = 12.sp
        )
    }
}

@Composable
private fun MostReadFandomsCard(
    fandoms: List<ReadingStatistics.FandomCount>,
    palette: SubjectPalette
) {
    val peak = fandoms.firstOrNull()?.count?.toDouble() ?: 0.0
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .subjectPanel()
            .padding(horizontal = 18.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(13.dp)
    ) {
        fandoms.forEachIndexed { index, fandom ->
            FandomBarRow(
                name = fandom.name,
                value = NumberFormat.getIntegerInstance().format(fandom.count),
                fraction = share(fandom.count.toDouble(), peak),
                rank = index,
                isRemainder = false,
                palette = palette
            )
        }
    }
}

@Composable
private fun MetricGrid(metrics: List<Pair<String, String>>) {
    Column(verticalArrangement = Arrangement.spacedBy(15.dp)) {
        metrics.chunked(2).forEach { rowMetrics ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                rowMetrics.forEach { (figure, caption) ->
                    MetricCell(figure, caption, Modifier.weight(1f))
                }
                if (rowMetrics.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun MetricCell(
    figure: String,
    caption: String,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
            text = figure,
            color = tokens.primaryInk,
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
            fontFamily = FontFamily.Monospace,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            text = caption,
            color = tokens.secondaryInk,
            fontSize = 11.5.sp
        )
    }
}

@Composable
private fun FandomBarRow(
    name: String,
    value: String,
    fraction: Float,
    rank: Int,
    isRemainder: Boolean,
    palette: SubjectPalette
) {
    val tokens = LocalKudosTokens.current
    val tint = if (isRemainder) {
        tokens.secondaryInk
    } else {
        SubjectPalette.fromHue((palette.hue + rank * 0.06) % 1.0, tokens.theme).accent
    }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = name,
                color = tokens.primaryInk,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f)
            )
            Spacer(Modifier.width(8.dp))
            Text(
                text = value,
                color = tint,
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
                fontFamily = FontFamily.Monospace
            )
        }
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(5.dp)
                .clip(RoundedCornerShape(50.dp))
                .background(tokens.glassFill(0.09))
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth(fraction)
                    .height(5.dp)
                    .clip(RoundedCornerShape(50.dp))
                    .background(tint)
            )
        }
    }
}

@Composable
private fun DividerLine() {
    Box(
        Modifier
            .fillMaxWidth()
            .height(0.5.dp)
            .background(LocalKudosTokens.current.separator)
    )
}

private fun headerTally(state: ReadingStatisticsUiState): String {
    if (state.insights.totalSeconds <= 0) return "Your reading activity stays on this device"
    return "${ReadingInsights.hoursLabel(state.insights.totalSeconds)} hours in " +
        "${periodName(state.period, state.now)} · stays on this device"
}

private fun periodName(period: ReadingInsightsPeriod, now: Instant): String {
    val pattern = if (period == ReadingInsightsPeriod.Month) "LLLL" else "yyyy"
    return dateFormatter(pattern).format(now)
}

private fun previousPeriodName(period: ReadingInsightsPeriod, now: Instant): String {
    val zone = ZoneId.systemDefault()
    val earlier = when (period) {
        ReadingInsightsPeriod.Month -> now.atZone(zone).minusMonths(1).toInstant()
        ReadingInsightsPeriod.Year -> now.atZone(zone).minusYears(1).toInstant()
    }
    return dateFormatter(if (period == ReadingInsightsPeriod.Month) "MMM" else "yyyy")
        .format(earlier)
}

private fun weekLabel(weekStart: Instant): String = dateFormatter("MMM d").format(weekStart)

private fun dateFormatter(pattern: String): DateTimeFormatter =
    DateTimeFormatter.ofPattern(pattern, Locale.getDefault()).withZone(ZoneId.systemDefault())

private fun share(value: Double, peak: Double): Float =
    if (peak > 0) (value / peak).toFloat().coerceIn(0f, 1f) else 0f

private fun formatPercent(rate: Double): String = "${(rate * 100.0).roundToInt()}%"

/** Compact notation matching iOS `.number.notation(.compactName)`. */
internal fun formatCompactNumber(value: Int): String {
    val magnitude = kotlin.math.abs(value.toLong())
    val sign = if (value < 0) "-" else ""
    if (magnitude < 1_000L) return "$sign$magnitude"

    var scaled = magnitude / 1_000.0
    var suffix = "K"
    for (nextSuffix in listOf("M", "B")) {
        if (roundToOneDecimal(scaled) < 1_000.0) break
        scaled /= 1_000.0
        suffix = nextSuffix
    }

    val rounded = roundToOneDecimal(scaled)
    return if (rounded % 1.0 == 0.0) {
        "$sign${rounded.toLong()}$suffix"
    } else {
        String.format(Locale.US, "%s%.1f%s", sign, rounded, suffix)
    }
}

private fun roundToOneDecimal(value: Double): Double = Math.round(value * 10) / 10.0
