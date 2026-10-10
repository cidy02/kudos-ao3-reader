package io.github.cidy02.kudos.account

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.network.ao3.account.*
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.settings.SettingsActionRow
import io.github.cidy02.kudos.settings.SettingsPanel
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.ui.subject.*
import io.github.cidy02.kudos.ui.subject.dialogGround
import io.github.cidy02.kudos.ui.subject.subjectPanel
import androidx.compose.foundation.layout.Column
import io.github.cidy02.kudos.writing.writingSuggestionPanel
import kotlinx.coroutines.launch

@Composable
fun AO3ChallengeAssignmentsScreen(slug: String, title: String, viewerIsOwner: Boolean,
    viewerIsMaintainer: Boolean, knownClosed: Boolean?, repository: AO3CollectionDetailRepository,
    writes: AO3WriteRepository, onOpenWeb: (String) -> Unit) {
    val auth = repository.authRepository
    val generation by auth.generation.collectAsState()
    val authState by auth.state.collectAsState()
    val admittedGeneration = remember(slug, repository) { generation }
    val model = remember(slug, repository, writes, generation, authState.isSignedIn, viewerIsOwner, viewerIsMaintainer, knownClosed) {
        AO3ChallengeAssignmentsState(slug, viewerIsOwner, viewerIsMaintainer && admittedGeneration == generation,
            knownClosed, repository, writes)
    }
    val state by model.state.collectAsState()
    val scope = rememberCoroutineScope()
    val tokens = LocalKudosTokens.current
    val palette = tokens.scopePalette
    val large = isAccessibilityFontScale()
    val disabled = state.busy || state.loading || state.terminal
    var segment by remember(model) { mutableStateOf(AssignmentSegment.Unmatched) }
    LaunchedEffect(model) { model.load() }
    DisposableEffect(model) { onDispose { model.close() } }
    ProvidePushedShellChrome(hasSubjectHeader = true, trailingContent = if (!state.loaded || state.terminal) null else { {
        IconButton(onClick = { scope.launch { model.load(refresh = true) } }, enabled = !disabled) {
            Icon(Icons.Default.Refresh, "Refresh assignments", tint = palette.accent)
        }
    } })
    state.picking?.let { kind ->
        Dialog(onDismissRequest = { model.cancel() }) {
            Column(Modifier.fillMaxWidth().dialogGround().subjectPanel()) {
                LazyColumn(Modifier.heightIn(max = 560.dp).testTag("Assignment candidates")) {
                    item { AssignmentText(kind.title, true, Modifier.padding(16.dp)) }
                    itemsIndexed(state.candidates(kind), key = { _, row -> row.id }) { _, row ->
                        SettingsActionRow("${row.giverDisplay} → ${row.recipientDisplay}", { model.select(kind, row) }, enabled = !disabled)
                    }
                    item { SettingsActionRow("Cancel", { model.cancel() }) }
                }
            }
        }
    }
    state.pending?.let { write ->
        if (!state.busy) AlertDialog(onDismissRequest = { model.cancel() }, containerColor = tokens.cardFill,
            titleContentColor = tokens.primaryInk, textContentColor = tokens.secondaryInk,
            title = { Text(write.kind.confirmTitle, lineHeight = 28.sp) },
            text = { Text(state.confirmation(write), lineHeight = 22.sp) },
            confirmButton = { TextButton(enabled = !disabled, onClick = { scope.launch { model.perform() } }) {
                Text(write.kind.confirmButton, color = if (write.kind == AssignmentWrite.Default) SubjectPalette.fromHue(0.0, tokens.theme).accent else palette.accent, lineHeight = 20.sp)
            } },
            dismissButton = { TextButton(onClick = { model.cancel() }) { Text("Cancel", color = palette.accent, lineHeight = 20.sp) } })
    }
    Column(Modifier.fillMaxSize().subjectScreenWash(palette)) {
        KudosRefreshBox(onRefresh = { model.load(refresh = true) }, modifier = Modifier.weight(1f)) {
            LazyColumn(Modifier.fillMaxSize().testTag("Challenge assignments"), contentPadding = PaddingValues(bottom = 24.dp)) {
                item {
                    Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
                    Spacer(Modifier.height(76.dp))
                    SubjectHeaderBlock(kicker = title.ifEmpty { slug }, title = "Assignments", subtitle = state.subtitle,
                        palette = palette, gutter = SubjectMetrics.accountGutter)
                    Row(Modifier.padding(top = 14.dp).horizontalScroll(rememberScrollState()).padding(horizontal = SubjectMetrics.accountGutter),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        AssignmentSegment.entries.forEach { option -> SubjectChip(option.label,
                            style = SubjectChipStyle.Pill(segment == option), palette = palette,
                            maxLines = if (large) Int.MAX_VALUE else 1, modifier = Modifier.clickable { segment = option }) }
                    }
                }
                when {
                    state.loading && !state.loaded -> item { AssignmentsLoading() }
                    state.failure != null -> item { AssignmentsFailure("Couldn't load assignments", state.failure.orEmpty(), !state.terminal && !disabled) {
                        scope.launch { model.load(refresh = true) }
                    } }
                    else -> {
                        state.actionError?.let { message -> item {
                            SettingsPanel(Modifier.padding(top = 8.dp)) {
                                Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Icon(Icons.Default.Warning, null, tint = SubjectPalette.fromHue(0.0, tokens.theme).accent,
                                        modifier = Modifier.padding(end = 8.dp).size(20.dp))
                                    Text(message, color = SubjectPalette.fromHue(0.0, tokens.theme).accent, fontSize = 12.5.sp, lineHeight = 18.sp, modifier = Modifier.weight(1f))
                                    IconButton(onClick = { model.dismissError() }) { Icon(Icons.Default.Close, "Dismiss error", tint = tokens.secondaryInk) }
                                }
                            }
                        } }
                        val error = when (segment) {
                            AssignmentSegment.Matched -> state.matchedError
                            AssignmentSegment.Unmatched -> state.errors[SignUpAssignmentList.Defaults]
                            AssignmentSegment.PinchHits -> state.errors[SignUpAssignmentList.PinchHits] ?: state.errors[SignUpAssignmentList.Defaults]
                        }
                        val count = when (segment) {
                            AssignmentSegment.Matched -> state.matched.size
                            AssignmentSegment.Unmatched -> state.unmatched.size
                            AssignmentSegment.PinchHits -> state.unmatched.size + state.claimed.size
                        }
                        item { ChallengeSection(if (segment == AssignmentSegment.Unmatched) "Unmatched sign-ups" else segment.label, count) }
                        if (error != null) item {
                            AssignmentsFailure(when (segment) {
                                AssignmentSegment.Matched -> "Couldn't load matched assignments"
                                AssignmentSegment.Unmatched -> "Couldn't load defaults"
                                AssignmentSegment.PinchHits -> "Couldn't load pinch hits"
                            }, error, !disabled) { scope.launch { model.load(refresh = true) } }
                        } else if (count == 0) item {
                            SettingsPanel(Modifier.padding(top = 8.dp)) { AssignmentText(when (segment) {
                                AssignmentSegment.Matched -> "No matched assignments yet."
                                AssignmentSegment.Unmatched -> "No defaulted assignments are waiting for a pinch hitter."
                                AssignmentSegment.PinchHits -> "No pinch hits open right now."
                            }, modifier = Modifier.padding(14.dp)) }
                        } else when (segment) {
                            AssignmentSegment.Matched -> itemsIndexed(state.matched, key = { index, row -> "$index:${row.id}" }) { index, row ->
                                AssignmentPanelRow(index == 0, index == state.matched.lastIndex) {
                                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                        AssignmentText("${row.recipientDisplay} → ${row.giverDisplay}", true)
                                        state.dueText?.let { AssignmentText("due $it") }
                                    }
                                    row.badge(state.dueInstant)?.let { badge ->
                                        SubjectChip(badge, style = if (badge == "LATE") SubjectChipStyle.Neutral else SubjectChipStyle.Tinted,
                                            palette = when (badge) {
                                                "DELIVERED" -> SubjectPalette.fromHue(0.36, tokens.theme)
                                                "DEFAULTED" -> SubjectPalette.fromHue(0.08, tokens.theme)
                                                else -> palette
                                            })
                                    }
                                }
                            }
                            AssignmentSegment.Unmatched -> itemsIndexed(state.unmatched.chunked(2)) { _, pair ->
                                val names = pair.map { it.recipientDisplay }
                                SettingsPanel(Modifier.padding(top = 9.dp)) {
                                    Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                        AssignmentText(if (names.size == 2) "Two sign-ups lost their giver" else "One sign-up lost its giver", true)
                                        AssignmentText((if (names.size == 2) "The givers for ${names[0]} and ${names[1]} defaulted, and no pinch hitter has covered them yet."
                                            else "The giver for ${names[0]} defaulted, and no pinch hitter has covered it yet.") +
                                            " Only AO3 can match participants, so cover this with a pinch hit or assign someone on AO3.")
                                    }
                                    SettingsActionRow("Open on AO3", { onOpenWeb(AO3ChallengeSignUpsUrls.assignments(slug, SignUpAssignmentList.PinchHits)) })
                                }
                            }
                            AssignmentSegment.PinchHits -> {
                                val rows = state.unmatched.map { it to true } + state.claimed.map { it to false }
                                itemsIndexed(rows, key = { _, pair -> "${pair.second}:${pair.first.id}" }) { index, (row, open) ->
                                    AssignmentPanelRow(index == 0, index == rows.lastIndex) {
                                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                            AssignmentText("Pinch hit #${index + 1}", true)
                                            SubjectChip(if (open) "OPEN" else "CLAIMED", style = if (open) SubjectChipStyle.Tinted else SubjectChipStyle.Neutral, palette = palette)
                                            val recipient = row.recipient.ifEmpty { "an anonymous sign-up" }
                                            AssignmentText(if (open) "Requested by $recipient" else "Claimed by ${row.pinchHitter.ifEmpty { row.giver }} for $recipient" +
                                                state.dueText?.let { " · due $it" }.orEmpty())
                                        }
                                        if (open && viewerIsOwner && authState.isSignedIn) SubjectChip("Claim", palette = palette,
                                            style = SubjectChipStyle.Pill(false), modifier = Modifier.clickable(enabled = !disabled) { model.select(AssignmentWrite.Claim, row) })
                                    }
                                }
                            }
                        }
                        val lists = when (segment) {
                            AssignmentSegment.Matched -> listOf(SignUpAssignmentList.Complete, SignUpAssignmentList.Open)
                            AssignmentSegment.Unmatched -> listOf(SignUpAssignmentList.Defaults)
                            AssignmentSegment.PinchHits -> listOf(SignUpAssignmentList.Defaults, SignUpAssignmentList.PinchHits)
                        }
                        lists.forEach { list -> state.pages[list]?.takeIf { it.currentPage < it.totalPages }?.let { page -> item {
                            SettingsPanel(Modifier.padding(top = 10.dp)) {
                                SettingsActionRow(loadMoreLabel(list), { scope.launch { model.load(more = list) } },
                                    enabled = !disabled && list !in state.blocked)
                            }
                        } } }
                        item { ChallengeFootnote("You can view assignments and pinch hits here one page at a time. You can report a default " +
                            "or claim a pinch hit here, but asking for a pinch hitter and running the match open on AO3.") }
                        if (state.loading || state.busy) item { AssignmentsLoading() }
                    }
                }
            }
        }
        if (viewerIsOwner && authState.isSignedIn && state.loaded) SettingsPanel(Modifier.padding(top = 12.dp, bottom = 26.dp)) {
            val actions: @Composable RowScope.() -> Unit = {
                SettingsActionRow("Report a default", { model.pick(AssignmentWrite.Default) }, modifier = Modifier.weight(1f), enabled = !disabled && state.reportable.isNotEmpty())
                AssignmentClaimAction(!disabled && state.unmatched.isNotEmpty(), Modifier.weight(1f)) { model.pick(AssignmentWrite.Claim) }
            }
            if (large) {
                SettingsActionRow("Report a default", { model.pick(AssignmentWrite.Default) }, enabled = !disabled && state.reportable.isNotEmpty())
                AssignmentClaimAction(!disabled && state.unmatched.isNotEmpty(), Modifier.fillMaxWidth()) { model.pick(AssignmentWrite.Claim) }
            } else Row(content = actions)
        }
    }
}

@Composable
private fun AssignmentText(text: String, heading: Boolean = false, modifier: Modifier = Modifier) {
    val tokens = LocalKudosTokens.current
    Text(text, color = if (heading) tokens.primaryInk else tokens.secondaryInk,
        fontSize = if (heading) 15.sp else 12.5.sp, lineHeight = if (heading) 21.sp else 18.sp,
        fontWeight = if (heading) FontWeight.SemiBold else FontWeight.Normal, modifier = modifier)
}
@Composable
private fun AssignmentPanelRow(first: Boolean, last: Boolean, content: @Composable RowScope.() -> Unit) {
    Row(Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = if (first) 8.dp else 0.dp)
        .writingSuggestionPanel(first = first, last = last).padding(horizontal = 14.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top, content = content)
}
@Composable
private fun AssignmentsLoading() {
    val tokens = LocalKudosTokens.current
    Row(Modifier.fillMaxWidth().padding(24.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
        CircularProgressIndicator(color = tokens.scopePalette.accent, trackColor = tokens.separator, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
        AssignmentText("Loading assignments…", modifier = Modifier.padding(start = 10.dp))
    }
}
@Composable
private fun AssignmentsFailure(title: String, message: String, retry: Boolean, onRetry: () -> Unit) {
    SettingsPanel(Modifier.padding(top = 14.dp)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            AssignmentText(title, true)
            AssignmentText(message)
        }
        if (retry) SettingsActionRow("Try Again", onRetry)
    }
}

@Composable
private fun AssignmentClaimAction(enabled: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val palette = LocalKudosTokens.current.scopePalette
    Box(modifier.padding(6.dp).alpha(if (enabled) 1f else 0.45f)
        .background(palette.accent, RoundedCornerShape(12.dp)).clickable(enabled = enabled, onClick = onClick)
        .heightIn(min = 44.dp).padding(horizontal = 12.dp, vertical = 10.dp), contentAlignment = Alignment.Center) {
        Text("Claim a pinch hit", color = palette.labelOnAccent, fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold)
    }
}

/** Android only: iOS reads every page at once; here each list is read a page at a time (owner question 16). */
internal fun loadMoreLabel(list: SignUpAssignmentList) = when (list) {
    SignUpAssignmentList.Complete -> "Load more complete assignments"
    SignUpAssignmentList.Open -> "Load more open assignments"
    SignUpAssignmentList.Defaults -> "Load more defaulted assignments"
    SignUpAssignmentList.PinchHits -> "Load more pinch hits"
}
