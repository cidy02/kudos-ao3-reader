package io.github.cidy02.kudos.account

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.network.ao3.account.*
import io.github.cidy02.kudos.settings.SettingsPanel
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.ui.subject.*
import kotlinx.coroutines.launch
import java.text.Collator

@Composable
fun AO3TagSetScreen(
    id: Int,
    title: String,
    isModerator: Boolean,
    repository: AO3CollectionDetailRepository,
    onOpenWeb: (String) -> Unit
) {
    val auth = repository.authRepository
    val generation by auth.generation.collectAsState()
    val authState by auth.state.collectAsState()
    val model = remember(id, repository, generation, authState.isSignedIn) { AO3TagSetState(id, repository) }
    val state by model.state.collectAsState()
    val scope = rememberCoroutineScope()
    val tokens = LocalKudosTokens.current
    val palette = tokens.scopePalette
    val large = isAccessibilityFontScale()
    val data = state.data
    val effectiveTitle = title.ifEmpty { data?.title?.ifEmpty { "Tag Set $id" } ?: "Tag Set $id" }
    val total = data?.totalTagCount ?: 0
    LaunchedEffect(model) { model.load() }
    DisposableEffect(model) { onDispose { model.close() } }
    ProvidePushedShellChrome(hasSubjectHeader = true)
    MaterialTheme(colorScheme = MaterialTheme.colorScheme.copy(
        primary = palette.accent, onPrimary = SubjectPalette.label(palette.accent),
        primaryContainer = palette.chipFill, onPrimaryContainer = palette.accentOnFill,
        surface = tokens.cardFill, onSurface = tokens.primaryInk,
        surfaceContainerHigh = tokens.cardFill, surfaceContainerHighest = tokens.cardFill,
        surfaceVariant = tokens.cardFill, onSurfaceVariant = tokens.secondaryInk,
        background = tokens.background, onBackground = tokens.primaryInk,
        outline = tokens.separator, outlineVariant = tokens.separator, surfaceTint = palette.accent
    )) {
        KudosRefreshBox(onRefresh = { model.load() }, modifier = Modifier.fillMaxSize().subjectScreenWash(palette)) {
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
                item {
                    Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
                    Spacer(Modifier.height(76.dp))
                    SubjectHeaderBlock(
                        kicker = if (isModerator) "Tag set · moderator" else "Tag set · owner",
                        title = "Tag set",
                        subtitle = "$effectiveTitle · ${total.compactCount()} tags",
                        palette = palette, gutter = SubjectMetrics.accountGutter
                    )
                }
                when {
                    state.loading || (data == null && state.failure == null) -> item {
                        Row(Modifier.fillMaxWidth().padding(vertical = 24.dp), horizontalArrangement = Arrangement.Center,
                            verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(color = palette.accent, trackColor = tokens.separator,
                                modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                            Text("Loading tag set…", color = tokens.secondaryInk, fontSize = 14.sp, lineHeight = 20.sp,
                                modifier = Modifier.padding(start = 10.dp))
                        }
                    }
                    state.failure != null -> item {
                        SettingsPanel(Modifier.padding(top = 14.dp)) {
                            Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text("Couldn't load tag set", color = tokens.primaryInk, fontSize = 15.sp, lineHeight = 21.sp,
                                    fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
                                Text(state.failure.orEmpty(), color = tokens.secondaryInk, fontSize = 13.sp,
                                    lineHeight = 19.sp, textAlign = TextAlign.Center)
                                TextButton(onClick = { scope.launch { model.load() } }) {
                                    Text("Try Again", color = palette.accent, fontSize = 14.sp, lineHeight = 20.sp)
                                }
                            }
                        }
                    }
                    data != null -> {
                        item {
                            ChallengeSection("Ownership")
                            SettingsPanel(Modifier.padding(top = 8.dp)) {
                                SubjectFormRow("Title", value = effectiveTitle, valueMaxLines = Int.MAX_VALUE)
                                SubjectRowSeparator()
                                ChallengeReadOnlyToggle("Visible to everyone", data.isVisible, palette, large)
                            }
                            ChallengeSection("Tags", total)
                            SettingsPanel(Modifier.padding(top = 8.dp)) {
                                AO3TagSetField.entries.forEachIndexed { index, field ->
                                    if (index > 0) SubjectRowSeparator()
                                    // iOS opens its "Add tags" editor from these rows: a write, so a later brief.
                                    SubjectFormRow(field.rowLabel, value = "${data.counts[field] ?: 0}", valueMaxLines = Int.MAX_VALUE)
                                }
                            }
                            ChallengeSection("Nominations")
                            SettingsPanel(Modifier.padding(top = 8.dp)) {
                                ChallengeReadOnlyToggle("Nominations open", data.isNominated, palette, large)
                                AO3TagSetField.entries.forEach { field ->
                                    SubjectRowSeparator()
                                    SubjectFormRow("${field.rowLabel} per person", value = "${data.nominationLimits[field] ?: 0}",
                                        valueMaxLines = Int.MAX_VALUE)
                                }
                            }
                            ChallengeSection("Review")
                            SettingsPanel(Modifier.padding(top = 8.dp)) {
                                listOf("Awaiting review" to AO3TagNominationState.Unreviewed,
                                    "Approved" to AO3TagNominationState.Approved, "Rejected" to AO3TagNominationState.Rejected)
                                    .forEachIndexed { index, (label, status) ->
                                        if (index > 0) SubjectRowSeparator()
                                        SubjectFormRow(label, value = "${data.reviewQueue.count { it.state == status }}", valueMaxLines = Int.MAX_VALUE)
                                    }
                            }
                        }
                        if (data.reviewQueue.isEmpty()) item {
                            SettingsPanel(Modifier.padding(top = 8.dp)) {
                                Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally,
                                    verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                    Text("No nominations yet", color = tokens.primaryInk, fontSize = 15.sp, lineHeight = 21.sp,
                                        fontWeight = FontWeight.SemiBold)
                                    Text("Nothing has been nominated to this tag set.", color = tokens.secondaryInk,
                                        fontSize = 12.5.sp, lineHeight = 18.sp, textAlign = TextAlign.Center)
                                }
                            }
                        } else {
                            val groups = data.reviewQueue.groupBy { it.parentTagName }
                            val collator = Collator.getInstance()
                            groups.keys.sortedWith(Comparator { a, b ->
                                when { a.isEmpty() != b.isEmpty() -> if (a.isEmpty()) 1 else -1; else -> collator.compare(a, b) }
                            }).forEach { fandom -> item {
                                SettingsPanel(Modifier.padding(top = 8.dp)) {
                                    Text(fandom.ifEmpty { "No fandom listed" }.uppercase(), color = palette.accent, fontSize = 11.sp,
                                        lineHeight = 16.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.77.sp,
                                        modifier = Modifier.padding(horizontal = 14.dp).padding(top = 12.dp, bottom = 8.dp))
                                    groups.getValue(fandom).forEachIndexed { index, nomination ->
                                        if (index > 0) SubjectRowSeparator()
                                        TagSetNominationRow(nomination, large)
                                    }
                                }
                            } }
                        }
                        item {
                            ChallengeFootnote("Before you approve a nominated character or relationship, it must be linked to a fandom. " +
                                "The review list groups nominations by fandom.")
                            ChallengeSection("At AO3")
                            SettingsPanel(Modifier.padding(top = 8.dp)) {
                                SubjectFormRow("Associate nominations", value = "Opens AO3", showsDisclosure = true,
                                    valueMaxLines = Int.MAX_VALUE, onClick = { onOpenWeb(AO3TagSetUrls.associations(id)) })
                                SubjectRowSeparator()
                                val destructive = SubjectPalette.fromHue(0.0, tokens.theme)
                                CompositionLocalProvider(LocalKudosTokens provides tokens.copy(primaryInk = destructive.accent)) {
                                    SubjectFormRow("Delete tag set", value = "Opens AO3", showsDisclosure = true,
                                        valueMaxLines = Int.MAX_VALUE, onClick = { onOpenWeb(AO3TagSetUrls.edit(id)) })
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TagSetNominationRow(nomination: AO3TagNomination, large: Boolean) {
    val tokens = LocalKudosTokens.current
    val label: @Composable () -> Unit = {
        Text(nomination.tagName, color = tokens.primaryInk, fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium)
        Text(nomination.field.nominationLabel, color = tokens.secondaryInk, fontSize = 11.sp, lineHeight = 16.sp)
    }
    val badge: @Composable () -> Unit = {
        when (nomination.state) {
            AO3TagNominationState.Unreviewed -> Unit // The later write brief owns Reject; no replacement control or sentence.
            AO3TagNominationState.Approved -> SubjectChip("Approved", style = SubjectChipStyle.Tinted,
                palette = SubjectPalette.fromHue(1.0 / 3.0, tokens.theme))
            AO3TagNominationState.Rejected -> SubjectChip("Rejected", style = SubjectChipStyle.Tinted,
                palette = SubjectPalette.fromHue(0.0, tokens.theme))
        }
    }
    if (large) Column(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)) { label(); badge() }
    else Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) { label() }
        badge()
    }
}
