package io.github.cidy02.kudos.account

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.auth.usernameOrNull
import io.github.cidy02.kudos.network.ao3.account.*
import io.github.cidy02.kudos.settings.SettingsActionRow
import io.github.cidy02.kudos.settings.SettingsPanel
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.ui.subject.*
import io.github.cidy02.kudos.writing.writingSuggestionPanel
import kotlinx.coroutines.launch

@Composable
fun AO3ChallengeSignUpsScreen(slug: String, title: String, viewerIsOwner: Boolean,
    viewerIsMaintainer: Boolean, repository: AO3CollectionDetailRepository, onOpenSignUp: (Int?) -> Unit) {
    val auth = repository.authRepository
    val generation by auth.generation.collectAsState()
    val authState by auth.state.collectAsState()
    val admissionGeneration = remember(slug, repository) { generation }
    val admitted = viewerIsMaintainer && generation == admissionGeneration
    val model = remember(slug, repository, generation, authState.isSignedIn, viewerIsOwner, viewerIsMaintainer) {
        AO3ChallengeSignUpsState(slug, viewerIsOwner, admitted, repository)
    }
    val state by model.state.collectAsState()
    val scope = rememberCoroutineScope()
    val tokens = LocalKudosTokens.current
    val palette = tokens.scopePalette
    val effectiveTitle = title.ifEmpty { slug }
    var filter by remember(model) { mutableStateOf(SignUpFilter.All) }
    var participant by remember(model) { mutableStateOf<AO3ListedSignUp?>(null) }
    LaunchedEffect(model) { model.load() }
    DisposableEffect(model) { onDispose { model.close() } }
    val detail = participant
    if (detail != null) {
        BackHandler { participant = null }
        ChallengeSignUpDetail(detail, effectiveTitle) { participant = null }
        return
    }
    ProvidePushedShellChrome(hasSubjectHeader = true)
    val filtered = state.filtered(filter) // derive every drawn row from collected state
    val large = isAccessibilityFontScale()
    MaterialTheme(colorScheme = MaterialTheme.colorScheme.copy(primary = palette.accent,
        primaryContainer = palette.chipFill, onPrimaryContainer = palette.accentOnFill,
        surface = tokens.cardFill, onSurface = tokens.primaryInk,
        surfaceContainerHigh = tokens.cardFill, surfaceContainerHighest = tokens.cardFill,
        surfaceVariant = tokens.cardFill, onSurfaceVariant = tokens.secondaryInk,
        outline = tokens.separator, outlineVariant = tokens.separator, surfaceTint = palette.accent)) {
        Column(Modifier.fillMaxSize().subjectScreenWash(palette)) {
            KudosRefreshBox(onRefresh = { model.load(refresh = true) }, modifier = Modifier.weight(1f)) {
                LazyColumn(Modifier.fillMaxSize().testTag("Challenge sign-ups"), contentPadding = PaddingValues(bottom = 24.dp)) {
                    item {
                        PushedChallengeHeader(effectiveTitle, "Sign-ups", listOfNotNull(
                            state.total?.let { signUpCount(it, "sign-up") }, state.closeDateText.takeIf { it.isNotEmpty() }
                        ).joinToString(" · "))
                        Row(Modifier.padding(top = 14.dp).horizontalScroll(rememberScrollState())
                            .padding(horizontal = SubjectMetrics.accountGutter), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            SignUpFilter.entries.forEach { option ->
                                SubjectChip(option.label, style = SubjectChipStyle.Pill(filter == option), palette = palette,
                                    maxLines = if (large) Int.MAX_VALUE else 1,
                                    modifier = Modifier.clickable { filter = option })
                            }
                        }
                    }
                    when {
                        state.loading && state.rows.isEmpty() -> item { SignUpsLoading() }
                        state.failure != null && state.rows.isEmpty() -> item {
                            SignUpsFailure(state.failure.orEmpty(), !state.terminal) { scope.launch { model.load(refresh = true) } }
                        }
                        else -> {
                            item {
                                ChallengeSection("Sign-ups", filtered.size)
                                state.failure?.let { ChallengeFootnote("Couldn't load sign-ups: $it") }
                                state.matchNote?.let { ChallengeFootnote(it) }
                            }
                            if (filtered.isEmpty()) item {
                                val unknown = state.matchNote != null && filter != SignUpFilter.All
                                SettingsPanel(Modifier.padding(top = 8.dp)) {
                                    Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                        Text(if (unknown) "Match state unavailable" else if (filter == SignUpFilter.All) "No sign-ups yet"
                                            else "No ${filter.label.lowercase()} sign-ups", color = tokens.primaryInk,
                                            fontSize = 15.sp, lineHeight = 21.sp, fontWeight = FontWeight.SemiBold)
                                        Text(if (unknown) "No sign-up can be shown as matched or unmatched without assignments."
                                            else if (filter == SignUpFilter.All) "Sign-ups will appear here as people join the challenge."
                                            else "No sign-ups in this page match the \"${filter.label}\" filter.",
                                            color = tokens.secondaryInk, fontSize = 12.5.sp, lineHeight = 18.sp)
                                    }
                                }
                            }
                            itemsIndexed(filtered, key = { _, row -> row.id }) { index, row ->
                                Row(Modifier.padding(horizontal = SubjectMetrics.accountGutter)
                                    .padding(top = if (index == 0) 8.dp else 0.dp)
                                    .writingSuggestionPanel(first = index == 0, last = index == filtered.lastIndex)
                                    .clickable { participant = row }.padding(horizontal = 14.dp, vertical = 11.dp),
                                    verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(11.dp)) {
                                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                        val match = signUpMatch(row, state.assignments)
                                        val badge: @Composable () -> Unit = {
                                            if (match != SignUpMatch.Unknown) SubjectChip(
                                                if (match == SignUpMatch.Matched) "MATCHED" else "UNMATCHED",
                                                style = if (match == SignUpMatch.Matched) SubjectChipStyle.Tinted else SubjectChipStyle.Neutral,
                                                palette = palette, maxLines = if (large) Int.MAX_VALUE else 1)
                                        }
                                        if (large) {
                                            Text(row.pseud, color = tokens.primaryInk, fontSize = 15.sp, lineHeight = 21.sp,
                                                fontWeight = FontWeight.SemiBold)
                                            badge()
                                        } else Row(verticalAlignment = Alignment.CenterVertically,
                                            horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                                            Text(row.pseud, color = tokens.primaryInk, fontSize = 15.sp, lineHeight = 21.sp,
                                                fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                                            badge()
                                        }
                                        Text(signUpPromptCount(row), color = tokens.secondaryInk, fontSize = 11.5.sp, lineHeight = 17.sp)
                                        if (row.requestTagSummary.isNotEmpty()) Text(row.requestTagSummary,
                                            color = tokens.secondaryInk.copy(alpha = 0.7f), fontSize = 11.sp, lineHeight = 16.sp,
                                            maxLines = if (large) Int.MAX_VALUE else 1, overflow = TextOverflow.Ellipsis)
                                    }
                                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null,
                                        tint = tokens.secondaryInk, modifier = Modifier.size(18.dp))
                                }
                            }
                            item {
                                ChallengeFootnote("AO3 shows 20 sign-ups per page, so these filters apply only to the pages you have loaded. " +
                                    "Each tag summary shows one line from that person's sign-up requests.")
                            }
                            if (state.hasMore) item {
                                SettingsPanel(Modifier.padding(top = 10.dp)) {
                                    if (state.loading) SignUpsLoading()
                                    SettingsActionRow("Load page ${state.loadedPages + 1} of ${state.totalPages}",
                                        { scope.launch { model.load(more = true) } }, enabled = !state.loading && !state.terminal)
                                }
                            }
                        }
                    }
                }
            }
            if (authState.isSignedIn && admitted) SettingsPanel(Modifier.padding(top = 12.dp, bottom = 26.dp)) {
                val own = ownListedSignUpID(state.rows, authState.usernameOrNull.orEmpty())
                if (large) {
                    SettingsActionRow("Your sign-up", { onOpenSignUp(own) })
                    SubjectRowSeparator()
                    SettingsActionRow("Create sign-up", { onOpenSignUp(null) })
                } else Row {
                    SettingsActionRow("Your sign-up", { onOpenSignUp(own) }, modifier = Modifier.weight(1f))
                    SettingsActionRow("Create sign-up", { onOpenSignUp(null) }, modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun PushedChallengeHeader(kicker: String, title: String, subtitle: String) {
    Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
    Spacer(Modifier.height(76.dp))
    SubjectHeaderBlock(kicker = kicker, title = title, subtitle = subtitle,
        palette = LocalKudosTokens.current.scopePalette, gutter = SubjectMetrics.accountGutter)
}

@Composable
private fun SignUpsLoading() {
    val tokens = LocalKudosTokens.current
    Row(Modifier.fillMaxWidth().padding(24.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
        CircularProgressIndicator(color = tokens.scopePalette.accent, trackColor = tokens.separator,
            modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
        Text("Loading sign-ups…", color = tokens.secondaryInk, fontSize = 14.sp, lineHeight = 20.sp,
            modifier = Modifier.padding(start = 10.dp))
    }
}

@Composable
private fun SignUpsFailure(message: String, retry: Boolean, onRetry: () -> Unit) {
    val tokens = LocalKudosTokens.current
    SettingsPanel(Modifier.padding(top = 14.dp)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Couldn't load sign-ups", color = tokens.primaryInk, fontSize = 15.sp, lineHeight = 21.sp, fontWeight = FontWeight.SemiBold)
            Text(message, color = tokens.secondaryInk, fontSize = 13.sp, lineHeight = 19.sp)
        }
        if (retry) SettingsActionRow("Try Again", onRetry)
    }
}

/** A pushed read of the index's inline prompts. No participant GET and no editable controls. */
@Composable
private fun ChallengeSignUpDetail(row: AO3ListedSignUp, title: String, onBack: () -> Unit) {
    ProvidePushedShellChrome(hasSubjectHeader = true, onBack = onBack)
    val tokens = LocalKudosTokens.current
    LazyColumn(Modifier.fillMaxSize().subjectScreenWash(tokens.scopePalette).testTag("Participant sign-up"),
        contentPadding = PaddingValues(bottom = 24.dp)) {
        item { PushedChallengeHeader(title, row.pseud, signUpPromptCount(row)) }
        for ((noun, prompts) in listOf("Request" to row.requests, "Offer" to row.offers)) {
            itemsIndexed(prompts, key = { index, _ -> "$noun:$index" }) { index, prompt ->
                ChallengeSection("$noun ${index + 1}")
                val tags = listOf(SignUpTagType.Fandom to "Fandoms", SignUpTagType.Relationship to "Relationships",
                    SignUpTagType.Character to "Characters", SignUpTagType.Freeform to "Additional tags").map { (type, label) ->
                    label to (prompt.tags[type].orEmpty() + if (type in prompt.any) listOf("Any") else emptyList())
                }.plus("Optional tags" to prompt.optionalTags).filter { it.second.isNotEmpty() }
                if (tags.isNotEmpty() || prompt.text.isNotEmpty()) SettingsPanel(Modifier.padding(top = 8.dp)) {
                    tags.forEachIndexed { tagIndex, (label, values) ->
                        if (tagIndex > 0) SubjectRowSeparator()
                        Column(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 11.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(label, color = tokens.primaryInk, fontSize = 15.sp, lineHeight = 21.sp)
                            Text(values.joinToString(", "), color = tokens.secondaryInk, fontSize = 11.5.sp, lineHeight = 17.sp)
                        }
                    }
                    if (prompt.text.isNotEmpty()) {
                        if (tags.isNotEmpty()) SubjectRowSeparator()
                        Text(prompt.text, color = tokens.primaryInk, fontSize = 13.5.sp, lineHeight = 20.sp,
                            fontFamily = FontFamily.Serif, modifier = Modifier.fillMaxWidth().padding(14.dp))
                    }
                }
            }
        }
    }
}
