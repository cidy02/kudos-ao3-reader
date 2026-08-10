package io.github.cidy02.kudos.library

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.KudosScreenHeader
import io.github.cidy02.kudos.ui.components.KudosSectionHeader
import io.github.cidy02.kudos.app.PrivacyGate
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlin.math.roundToInt
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn

data class ReadingStatisticsUiState(
    val loading: Boolean = true,
    val statistics: ReadingStatistics? = null,
    val error: String? = null
)

class ReadingStatisticsViewModel(
    libraryRepository: LibraryRepository,
    settingsRepository: SettingsRepository? = null,
    privacyGate: PrivacyGate = PrivacyGate()
) : ViewModel() {
    val state: StateFlow<ReadingStatisticsUiState> = combine(
        libraryRepository.observeStatisticsWorks(),
        settingsRepository?.settings ?: flowOf(KudosSettings()),
        privacyGate.state
    ) { works, settings, reveal ->
        // Aggregate counts and fandom labels must not leak a hidden mature work —
        // this had no privacy filtering at all before (found in review; every other
        // reader of the library applies LibraryPrivacy first). Apple's equivalent:
        // `works.filter { !hideMature || !$0.isAdult || gate.isRevealed($0) }`
        // (LibraryView.statisticsWorks).
        val visible = works.filter { work ->
            LibraryPrivacy.visibility(work, settings.privacy, reveal) ==
                LibraryPrivacyVisibility.Visible
        }
        ReadingStatisticsUiState(
            loading = false,
            statistics = ReadingStatistics.from(visible)
        )
    }
        .catch { throwable ->
            emit(
                ReadingStatisticsUiState(
                    loading = false,
                    error = throwable.message ?: "Reading Insights could not be loaded."
                )
            )
        }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = ReadingStatisticsUiState(loading = true)
        )

    companion object {
        fun factory(
            libraryRepository: LibraryRepository,
            settingsRepository: SettingsRepository? = null,
            privacyGate: PrivacyGate = PrivacyGate()
        ): ViewModelProvider.Factory =
            viewModelFactory {
                initializer { ReadingStatisticsViewModel(libraryRepository, settingsRepository, privacyGate) }
            }
    }
}

@Composable
fun ReadingStatisticsScreen(
    libraryRepository: LibraryRepository,
    settingsRepository: SettingsRepository? = null,
    privacyGate: PrivacyGate = PrivacyGate()
) {
    val viewModel: ReadingStatisticsViewModel = viewModel(
        factory = ReadingStatisticsViewModel.factory(libraryRepository, settingsRepository, privacyGate)
    )
    val state by viewModel.state.collectAsState()
    ReadingStatisticsContent(state = state)
}

@Composable
private fun ReadingStatisticsContent(
    state: ReadingStatisticsUiState
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        item {
            KudosScreenHeader(
                title = "Reading Insights",
                subtitle = "Local-only progress from works in your Library."
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

        val statistics = state.statistics
        if (statistics == null || statistics.totalWorks == 0) {
            item {
                EmptyStateCard(
                    title = "No statistics yet",
                    message = "Save works to your Library and open them in the reader " +
                        "to start tracking local reading insights."
                )
            }
            return@LazyColumn
        }

        item {
            KudosSectionHeader(title = "Overview")
            Spacer(Modifier.height(8.dp))
            OverviewMetricsGrid(statistics)
        }

        item {
            KudosSectionHeader(title = "Reading Activity")
            Spacer(Modifier.height(8.dp))
            ActivityCard(statistics)
        }

        item {
            KudosSectionHeader(title = "Completion")
            Spacer(Modifier.height(8.dp))
            CompletionCard(statistics)
        }

        item {
            KudosSectionHeader(title = "Top Fandoms")
            Spacer(Modifier.height(8.dp))
            TopFandomsCard(statistics)
        }

        item {
            Text(
                text = "Statistics stay on this device. Words Read includes finished works " +
                    "with a known AO3 word count; recent activity counts distinct works opened.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun OverviewMetricsGrid(statistics: ReadingStatistics) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            MetricCard(
                title = "Works Read",
                value = statistics.startedWorks.toString(),
                detail = "${statistics.totalWorks} in your library",
                modifier = Modifier.weight(1f)
            )
            MetricCard(
                title = "Words Read",
                value = formatCompactNumber(statistics.wordsRead),
                detail = "From finished works",
                modifier = Modifier.weight(1f)
            )
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            MetricCard(
                title = "Finished",
                value = statistics.finishedWorks.toString(),
                detail = formatPercent(statistics.completionRate),
                modifier = Modifier.weight(1f)
            )
            MetricCard(
                title = "In Progress",
                value = statistics.inProgressWorks.toString(),
                detail = "Started, not finished",
                modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
private fun MetricCard(
    title: String,
    value: String,
    detail: String,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerHighest
        ),
        shape = MaterialTheme.shapes.medium
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = value,
                style = MaterialTheme.typography.titleLarge
            )
            Text(
                text = detail,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1
            )
        }
    }
}

@Composable
private fun ActivityCard(statistics: ReadingStatistics) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow
        ),
        shape = MaterialTheme.shapes.medium
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            ActivityRow(
                title = "Past 7 days",
                value = worksOpenedText(statistics.openedLast7Days)
            )
            ActivityRow(
                title = "Past 30 days",
                value = worksOpenedText(statistics.openedLast30Days)
            )
            ActivityRow(
                title = "Last read",
                value = formatLatestRead(statistics.latestReadDate)
            )
        }
    }
}

@Composable
private fun ActivityRow(title: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(text = title, style = MaterialTheme.typography.bodyMedium)
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun CompletionCard(statistics: ReadingStatistics) {
    val detail = if (statistics.startedWorks > 0) {
        "${statistics.finishedWorks} of ${statistics.startedWorks} started works"
    } else {
        "Open a work in the reader to begin tracking progress."
    }
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow
        ),
        shape = MaterialTheme.shapes.medium
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(text = "Finished works", style = MaterialTheme.typography.bodyMedium)
                Text(
                    text = formatPercent(statistics.completionRate),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            LinearProgressIndicator(
                progress = { statistics.completionRate.toFloat().coerceIn(0f, 1f) },
                modifier = Modifier.fillMaxWidth(),
                trackColor = MaterialTheme.colorScheme.surfaceVariant,
                color = MaterialTheme.colorScheme.primary
            )
            Text(
                text = detail,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun TopFandomsCard(statistics: ReadingStatistics) {
    val top = remember(statistics.topFandoms) { statistics.topFandoms.take(6) }
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow
        ),
        shape = MaterialTheme.shapes.medium
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            if (top.isEmpty()) {
                Text(
                    text = "No fandom insights yet",
                    style = MaterialTheme.typography.titleSmall
                )
                Text(
                    text = "Fandoms appear after a started work has categorized AO3 tags.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                val maxCount = top.first().count.coerceAtLeast(1)
                top.forEachIndexed { index, fandom ->
                    FandomRow(
                        rank = index + 1,
                        fandom = fandom,
                        fraction = fandom.count.toFloat() / maxCount.toFloat()
                    )
                }
            }
        }
    }
}

@Composable
private fun FandomRow(
    rank: Int,
    fandom: ReadingStatistics.FandomCount,
    fraction: Float
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = rank.toString(),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.width(18.dp)
            )
            Text(
                text = fandom.name,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.weight(1f),
                maxLines = 2
            )
            Text(
                text = fandom.count.toString(),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(5.dp)
                .clip(RoundedCornerShape(50))
                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.18f))
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth(fraction.coerceIn(0f, 1f))
                    .height(5.dp)
                    .clip(RoundedCornerShape(50))
                    .background(MaterialTheme.colorScheme.primary)
            )
        }
    }
}

private fun worksOpenedText(count: Int): String {
    return if (count == 1) "1 work opened" else "$count works opened"
}

private fun formatPercent(rate: Double): String {
    val pct = (rate * 100.0).roundToInt()
    return "$pct%"
}

private fun formatLatestRead(date: Instant?): String {
    if (date == null) return "Not yet"
    val formatter = DateTimeFormatter
        .ofLocalizedDate(FormatStyle.MEDIUM)
        .withLocale(Locale.getDefault())
        .withZone(ZoneId.systemDefault())
    return formatter.format(date)
}

/** Compact notation roughly matching iOS `.number.notation(.compactName)`. */
internal fun formatCompactNumber(value: Int): String {
    val abs = kotlin.math.abs(value.toLong())
    val sign = if (value < 0) "-" else ""
    if (abs < 1_000L) return "$sign$abs"

    // Round-then-pick-unit, not pick-unit-then-round: rounding a tier's scaled
    // value to 1 decimal can itself reach 1000 (e.g. 999,950 / 1000 = 999.95,
    // which rounds to "1000.0"), which belongs in the next unit up, not this
    // one — check the rounded value before committing to a suffix.
    var scaled = abs / 1_000.0
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
