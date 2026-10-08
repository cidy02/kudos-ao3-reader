package io.github.cidy02.kudos.account

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import androidx.core.content.ContextCompat
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.auth.AO3AuthState
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.writing.DraftExpiry
import io.github.cidy02.kudos.ui.components.KudosPaginationBar
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.ui.components.statusChips
import io.github.cidy02.kudos.ui.components.WorkStatIcons
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectKicker
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.ToolbarAddButton
import io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import io.github.cidy02.kudos.ui.subject.withOpacity
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.time.Clock
import java.time.LocalDate
import java.util.Locale

/** iOS WritingDraftsView (1x). Post/Delete belong in the editor, never on these cards. */
@Composable
fun WritingDraftsScreen(
    repository: WritingDraftsRepository,
    onOpenWork: (String) -> Unit,
    clock: Clock? = null,
    savedRevision: Int = 0
) {
    val tokens = LocalKudosTokens.current
    val palette = tokens.scopePalette
    val generation by repository.authRepository.generation.collectAsState()
    val auth by repository.authRepository.state.collectAsState()
    var page by rememberSaveable(repository) { mutableStateOf(1) }
    val loader = remember(repository, generation, auth, page, savedRevision) { WritingDraftsState(repository, page) }
    val state by loader.state.collectAsState()
    val scope = rememberCoroutineScope()
    val today = rememberDraftDay(clock)
    val accessibility = isAccessibilityFontScale()

    // iOS's drafts task reads this page on return from a saved form. One read, no enrichment.
    LaunchedEffect(loader) { if (auth != AO3AuthState.Restoring) loader.load() }
    ProvidePushedShellChrome(hasSubjectHeader = true, trailingContent = {
        ToolbarAddButton(onClick = { onOpenWork(WritingWorkDestination.route()) },
            accessibilityName = "New Work", palette = palette)
    })

    // Shared pagination reads Material roles; scope those roles to this page's tokens only.
    val scheme = MaterialTheme.colorScheme.copy(
        primary = palette.accent, onPrimary = palette.labelOnAccent,
        primaryContainer = palette.chipFill, onPrimaryContainer = palette.accentOnFill,
        secondary = palette.accent, onSecondary = palette.labelOnAccent,
        secondaryContainer = palette.chipFill, onSecondaryContainer = palette.accentOnFill,
        surface = tokens.cardFill, surfaceContainerHigh = tokens.cardFill,
        surfaceVariant = tokens.cardFill, surfaceContainer = tokens.cardFill,
        surfaceContainerHighest = tokens.cardFill, surfaceContainerLow = tokens.cardFill,
        surfaceContainerLowest = tokens.background, surfaceDim = tokens.background, surfaceBright = tokens.cardFill,
        onSurface = tokens.primaryInk, onSurfaceVariant = tokens.secondaryInk,
        background = tokens.background, onBackground = tokens.primaryInk,
        outline = tokens.separator, outlineVariant = tokens.separator, surfaceTint = palette.accent,
        scrim = tokens.primaryInk.copy(alpha = 0.32f)
    )
    MaterialTheme(colorScheme = scheme) {
        key(loader) {
            KudosRefreshBox(onRefresh = { loader.load() }, modifier = Modifier.fillMaxSize().subjectScreenWash(palette)) {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(start = SubjectMetrics.accountGutter,
                        end = SubjectMetrics.accountGutter, bottom = 24.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    item {
                        // Room for the status bar and the shell's back row, as the Moderation
                        // screen leaves it: with 20dp the kicker sat under the clock and the
                        // back arrow over the title.
                        Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
                        Spacer(Modifier.height(76.dp))
                        Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                            SubjectHeaderBlock("AO3 Account", "Drafts", palette, gutter = 0.dp)
                            state.drafts?.let {
                                Text(DraftExpiry.tally(it, today), color = tokens.secondaryInk,
                                    fontSize = 15.5.sp, lineHeight = 22.sp)
                            }
                        }
                    }
                    item {
                        val orange = SubjectPalette.fromHue(DraftExpiry.Tone.Orange.hue, tokens.theme).accent
                        val shape = RoundedCornerShape(SubjectMetrics.rowRadius)
                        // Add " Recovery copies stay on this device and aren't deleted with it." only when Android keeps writing recovery copies.
                        Text("AO3 deletes an unposted draft 30 days after you create it.",
                            color = tokens.primaryInk.withOpacity(0.78), fontSize = 12.5.sp, lineHeight = 18.sp,
                            modifier = Modifier.fillMaxWidth().padding(top = 6.dp)
                                .background(orange.withOpacity(0.1), shape)
                                .border(0.5.dp, orange.withOpacity(0.34), shape)
                                .padding(horizontal = 15.dp, vertical = 13.dp))
                    }
                    if (state.loading || auth == AO3AuthState.Restoring) item {
                        Row(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalArrangement = Arrangement.Center,
                            verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(color = palette.accent, modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                            Text("Loading drafts…", color = tokens.secondaryInk, fontSize = 13.sp, lineHeight = 19.sp,
                                modifier = Modifier.padding(start = 8.dp))
                        }
                    }
                    state.error?.let { message -> item {
                        Column {
                            DraftFootnote(message)
                            TextButton(onClick = { scope.launch { loader.load() } }) {
                                Text("Try Again", color = palette.accent, fontSize = 15.sp,
                                    lineHeight = 21.sp, fontWeight = FontWeight.SemiBold)
                            }
                        }
                    } }
                    state.drafts?.let { drafts ->
                        if (drafts.page.works.isEmpty()) item { DraftFootnote("Works you save as drafts appear here.") }
                        else {
                            item { SectionRuleHeader("On AO3", modifier = Modifier.padding(top = 6.dp)) }
                            items(drafts.page.works, key = { it.id }) { work ->
                                DraftCard(work, drafts.deletionDates[work.id], today) {
                                    onOpenWork(WritingWorkDestination.route(work.id))
                                }
                            }
                        }
                        if (drafts.page.totalPages > 1) item {
                            KudosPaginationBar(drafts.page.currentPage, drafts.page.totalPages,
                                onPageChange = { if (it != page) page = it }, stacked = accessibility)
                        }
                    }
                }
            }
        }
    }
}

/** Resume and a calendar-day change update local copy only, never reread AO3. */
@Composable
private fun rememberDraftDay(clock: Clock?): LocalDate {
    fun currentDay(): LocalDate = if (clock == null) LocalDate.now() else LocalDate.now(clock)
    var today by remember(clock) { mutableStateOf(currentDay()) }
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(context, lifecycle, clock) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) today = currentDay()
        }
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) { today = currentDay() }
        }
        val filter = IntentFilter(Intent.ACTION_DATE_CHANGED).apply {
            addAction(Intent.ACTION_TIME_CHANGED)
            addAction(Intent.ACTION_TIMEZONE_CHANGED)
        }
        lifecycle.addObserver(observer)
        ContextCompat.registerReceiver(context, receiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
        onDispose { lifecycle.removeObserver(observer); context.unregisterReceiver(receiver) }
    }
    return today
}

@Composable
private fun DraftFootnote(message: String) {
    Text(message, color = LocalKudosTokens.current.secondaryInk.withOpacity(0.7),
        fontSize = 11.5.sp, lineHeight = 17.sp,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 6.dp))
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun DraftCard(work: AO3WorkSummary, deletion: LocalDate?, today: LocalDate, onOpen: () -> Unit) {
    val tokens = LocalKudosTokens.current
    val palette = SubjectPalette.fromHue(HomeFacts.workHue(work.fandoms, work.title), tokens.theme)
    val accessibility = isAccessibilityFontScale()
    val title = work.title.ifEmpty { "Untitled" }
    val fandoms = work.fandoms.filter { it.isNotBlank() }
    val shape = RoundedCornerShape(SubjectMetrics.rowRadius)
    val heading: @Composable () -> Unit = {
        Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
            if (fandoms.isNotEmpty() || deletion != null) FlowRow(
                horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                fandoms.firstOrNull()?.let {
                    SubjectKicker(HomeFacts.primaryFandom(listOf(it)) ?: it, palette,
                        trailingCount = if (accessibility) 0 else fandoms.size - 1,
                        maxLines = if (accessibility) Int.MAX_VALUE else 1)
                    if (accessibility && fandoms.size > 1) Text("+${fandoms.size - 1}",
                        color = tokens.secondaryInk, fontSize = 10.sp, lineHeight = 14.sp, fontWeight = FontWeight.Bold)
                }
                deletion?.let { DraftExpiryBadge(DraftExpiry.daysLeft(it, today)) }
            }
            Text(title, color = tokens.primaryInk, fontSize = 19.sp, lineHeight = 25.sp,
                fontWeight = FontWeight.SemiBold, maxLines = if (accessibility) Int.MAX_VALUE else 2)
        }
    }
    Column(Modifier.fillMaxWidth().clip(shape).background(tokens.cardFill, shape).background(palette.cardWash, shape)
        .border(0.5.dp, palette.cardBorder, shape).clickable(onClick = onOpen)
        .padding(horizontal = 16.dp, vertical = 18.dp), verticalArrangement = Arrangement.spacedBy(11.dp)) {
        if (accessibility) {
            heading()
            DraftStatusGrid(work)
        } else Row(horizontalArrangement = Arrangement.spacedBy(13.dp)) {
            Box(Modifier.weight(1f)) { heading() }
            DraftStatusGrid(work)
        }
        if (work.summary.isNotEmpty()) Text(work.summary, color = tokens.secondaryInk, fontSize = 13.5.sp,
            lineHeight = 19.sp, maxLines = if (accessibility) Int.MAX_VALUE else 3)
        val words = work.wordCount?.let { "${NumberFormat.getIntegerInstance().format(it)} word${if (it == 1) "" else "s"}" }
        val created = deletion?.let {
            "Created ${android.text.format.DateFormat.getBestDateTimePattern(Locale.getDefault(), "dMMMy").let { pattern ->
                DraftExpiry.createdDate(it).format(java.time.format.DateTimeFormatter.ofPattern(pattern, Locale.getDefault()))
            }}"
        }
        val metadata: @Composable () -> Unit = {
            if (words != null) Text(words, color = tokens.secondaryInk, fontSize = 11.5.sp, lineHeight = 17.sp,
                style = TextStyle(fontFeatureSettings = "tnum"))
            if (created != null) Text(created, color = tokens.secondaryInk, fontSize = 11.5.sp, lineHeight = 17.sp,
                style = TextStyle(fontFeatureSettings = "tnum"))
        }
        if (words != null || created != null) {
            if (accessibility) Column(verticalArrangement = Arrangement.spacedBy(4.dp)) { metadata() }
            else FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = if (words == null) Arrangement.End else Arrangement.SpaceBetween,
                verticalArrangement = Arrangement.spacedBy(4.dp)) { metadata() }
        }
    }
}

@Composable
private fun DraftExpiryBadge(days: Int) {
    val tokens = LocalKudosTokens.current
    val color = SubjectPalette.fromHue(DraftExpiry.tone(days).hue, tokens.theme).accent
    val text = DraftExpiry.chipText(days)
    val shape = RoundedCornerShape(SubjectMetrics.chipRadius)
    Text(text.uppercase(), color = color, fontSize = 9.5.sp, lineHeight = 14.sp,
        fontWeight = FontWeight.SemiBold, letterSpacing = 0.5.sp,
        modifier = Modifier.background(color.withOpacity(0.15), shape).border(0.5.dp, color.withOpacity(0.35), shape)
            .padding(horizontal = 8.dp, vertical = 3.dp).clearAndSetSemantics { contentDescription = text })
}

/** Reuses the account cards' status mapping and glyphs, in iOS's four-cell tray. */
@Composable
private fun DraftStatusGrid(work: AO3WorkSummary) {
    val tokens = LocalKudosTokens.current
    val density = LocalDensity.current
    val scale = density.fontScale.coerceAtMost(1.8f)
    val letterSize = with(density) { (7.dp * scale).toSp() }
    val categorySize = with(density) { (14.dp * scale).toSp() }
    val stats = statusChips(work.rating, work.categories, work.warnings, work.isComplete)
    Column(Modifier.background(tokens.glassFill(0.10), RoundedCornerShape(SubjectMetrics.trayRadius))
        .border(0.5.dp, tokens.glassStroke(), RoundedCornerShape(SubjectMetrics.trayRadius))
        .padding(horizontal = 7.dp * scale, vertical = 5.5.dp * scale)
        .clearAndSetSemantics { contentDescription = stats.joinToString(", ") { it.accessibilityLabel ?: it.text } },
        verticalArrangement = Arrangement.spacedBy(3.5.dp * scale)) {
        stats.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(3.5.dp * scale)) {
                row.forEach { stat ->
                    val tint = stat.tint ?: tokens.secondaryInk
                    Box(Modifier.size(22.dp * scale).background(tint.withOpacity(0.3), RoundedCornerShape(5.dp * scale)),
                        contentAlignment = Alignment.Center) {
                        val category = when (stat.text) {
                            "F/F" -> "⚢"; "M/M" -> "⚣"; "F/M" -> "⚤"; "Gen" -> "☉"; "Other" -> "♅"
                            else -> null
                        }
                        if (category != null) Text(category, color = tint, fontSize = categorySize, lineHeight = categorySize)
                        else {
                            stat.icon?.let { Icon(it, contentDescription = null, tint = tint, modifier = Modifier.size(14.dp * scale)) }
                            if (stat.icon == WorkStatIcons.rating) {
                                val letter = when (work.rating) {
                                    "General Audiences" -> "G"; "Teen And Up Audiences" -> "T"
                                    "Mature" -> "M"; "Explicit" -> "E"; else -> "?"
                                }
                                Text(letter, color = tint, fontSize = letterSize, lineHeight = letterSize,
                                    fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                }
            }
        }
    }
}
