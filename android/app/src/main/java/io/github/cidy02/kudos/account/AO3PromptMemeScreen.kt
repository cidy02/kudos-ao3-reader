package io.github.cidy02.kudos.account

import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.OpenInBrowser
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.draw.clip
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.auth.usernameOrNull
import io.github.cidy02.kudos.browse.FandomDisplayName
import io.github.cidy02.kudos.network.ao3.account.*
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.settings.SettingsPanel
import io.github.cidy02.kudos.ui.components.KudosPaginationBar
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.ui.subject.*
import kotlinx.coroutines.launch

@Composable
fun AO3PromptMemeScreen(
    slug: String, title: String, viewerIsOwner: Boolean,
    repository: AO3CollectionDetailRepository, writes: AO3WriteRepository, onOpenWeb: (String) -> Unit
) {
    val auth = repository.authRepository
    val generation by auth.generation.collectAsState()
    val authState by auth.state.collectAsState()
    val model = remember(slug, repository, writes, generation, authState.isSignedIn, viewerIsOwner) {
        AO3PromptMemeState(slug, repository, viewerIsOwner, writes)
    }
    val state by model.state.collectAsState()
    var filter by remember(model) { mutableStateOf(AO3PromptMemeFilter.All) }
    val scope = rememberCoroutineScope()
    val tokens = LocalKudosTokens.current
    val palette = tokens.scopePalette
    val large = isAccessibilityFontScale()
    val prompts = state.data?.prompts.orEmpty()
    val currentPage = state.data?.currentPage ?: 1
    val totalPages = state.data?.totalPages ?: 1
    val filtered = prompts.filter { filter.includes(it, authState.usernameOrNull.orEmpty()) }
    val subtitle = buildString {
        append("${prompts.size} ${if (prompts.size == 1) "prompt" else "prompts"} · ${prompts.count { !it.isClaimed }} unclaimed")
        if (totalPages > 1) append(" on page $currentPage of $totalPages")
        if (state.closeDateText.isNotEmpty()) append(" · ${state.closeDateText}")
    }
    LaunchedEffect(model) { model.load(readSchedule = true) }
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
        KudosRefreshBox(onRefresh = { model.load(readSchedule = true) }, modifier = Modifier.fillMaxSize().subjectScreenWash(palette)) {
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
                item {
                    Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
                    Spacer(Modifier.height(76.dp))
                    SubjectHeaderBlock(kicker = title.ifEmpty { slug }, title = "Prompts", subtitle = subtitle,
                        palette = palette, gutter = SubjectMetrics.accountGutter)
                    if (large) SettingsPanel(Modifier.padding(top = 14.dp)) {
                        AO3PromptMemeFilter.entries.forEachIndexed { index, option ->
                            if (index > 0) SubjectRowSeparator()
                            Text(option.label, color = if (filter == option) palette.accent else tokens.primaryInk,
                                fontSize = 13.sp, lineHeight = 19.sp, fontWeight = FontWeight.Medium,
                                modifier = Modifier.fillMaxWidth().semantics { selected = filter == option }
                                    .clickable(role = Role.RadioButton) { filter = option }.padding(14.dp))
                        }
                    } else SubjectSegmentedControl(options = AO3PromptMemeFilter.entries, selected = filter,
                        onSelect = { filter = it }, title = { it.label }, contentDescription = "Prompt filter",
                        modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 14.dp))
                }
                state.actionError?.let { message -> item {
                    SettingsPanel(Modifier.padding(top = 8.dp)) {
                        Row(Modifier.fillMaxWidth().padding(12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically) {
                            // The red the tag set screen uses for a refusal; no new token for one sentence.
                            val refusal = SubjectPalette.fromHue(0.0, tokens.theme).accent
                            Icon(Icons.Outlined.WarningAmber, null, tint = refusal, modifier = Modifier.size(18.dp))
                            Text(message, color = refusal, fontSize = 12.5.sp, lineHeight = 18.sp,
                                modifier = Modifier.weight(1f))
                            Box(Modifier.size(44.dp).clickable(role = Role.Button, onClick = model::dismissActionError),
                                contentAlignment = Alignment.Center) {
                                Icon(Icons.Outlined.Close, "Dismiss error", tint = tokens.secondaryInk, modifier = Modifier.size(16.dp))
                            }
                        }
                    }
                } }
                when {
                    state.loading && prompts.isEmpty() -> item {
                        Row(Modifier.fillMaxWidth().padding(vertical = 24.dp), horizontalArrangement = Arrangement.Center,
                            verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(color = palette.accent, trackColor = tokens.separator,
                                modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                            Text("Loading prompts…", color = tokens.secondaryInk, fontSize = 14.sp, lineHeight = 20.sp,
                                modifier = Modifier.padding(start = 10.dp))
                        }
                    }
                    state.failure != null && prompts.isEmpty() -> item {
                        PromptMemeMessage("Couldn't load prompts", state.failure.orEmpty()) {
                            TextButton(onClick = { scope.launch { model.load(currentPage) } }) {
                                Text("Try Again", color = palette.accent, fontSize = 14.sp, lineHeight = 20.sp)
                            }
                        }
                    }
                    else -> {
                        if (state.failure != null) item {
                            Row(Modifier.fillMaxWidth().padding(horizontal = SubjectMetrics.accountGutter + 4.dp).padding(top = 8.dp),
                                horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Outlined.WarningAmber, contentDescription = null, modifier = Modifier.size(16.dp),
                                    tint = tokens.secondaryInk.copy(alpha = 0.85f))
                                Text("Couldn't load that page: ${state.failure}", color = tokens.secondaryInk.copy(alpha = 0.85f),
                                    fontSize = 11.5.sp, lineHeight = 17.sp, modifier = Modifier.weight(1f))
                            }
                        }
                        item { ChallengeSection(filter.label, filtered.size) }
                        if (filtered.isEmpty()) item {
                            PromptMemeMessage(if (filter == AO3PromptMemeFilter.All) "No prompts yet" else "No ${filter.label.lowercase()} prompts",
                                if (filter == AO3PromptMemeFilter.All) "Prompts will appear here once someone posts one."
                                else "No prompts on this page match the \"${filter.label}\" filter.")
                        }
                        itemsIndexed(filtered, key = { index, prompt -> "$currentPage:$index:${prompt.id}" }) { _, prompt ->
                            PromptMemeCard(prompt, large, inFlight = state.promptInFlight == prompt.id,
                                enabled = state.promptInFlight == null && !state.loading,
                                onClaim = { scope.launch { model.claim(prompt.id) } },
                                onRelease = { scope.launch { model.release(prompt.id) } },
                                onOpenWeb = { onOpenWeb(AO3PromptMemeUrls.meme(slug)) })
                        }
                        item {
                            ChallengeFootnote("A Prompt Meme has no matching or assignments. You can claim a prompt here and release it later.")
                            if (state.loading && totalPages > 1) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                                CircularProgressIndicator(color = palette.accent, trackColor = tokens.separator,
                                    modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                            }
                            KudosPaginationBar(currentPage, totalPages, onPageChange = { page -> scope.launch { model.load(page) } },
                                enabled = !state.loading && state.promptInFlight == null, stacked = large,
                                modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 4.dp))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PromptMemeCard(prompt: AO3PromptMemePrompt, large: Boolean, inFlight: Boolean, enabled: Boolean,
    onClaim: () -> Unit, onRelease: () -> Unit, onOpenWeb: () -> Unit) {
    val tokens = LocalKudosTokens.current
    val palette = tokens.scopePalette
    SettingsPanel(Modifier.padding(top = 9.dp).testTag("prompt-${prompt.id}")) {
        Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            // A large-font kicker stacks so its state cannot be pushed off the row.
            if (large) Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                // No one-line limit at accessibility scale.
                prompt.fandoms.firstOrNull()?.let {
                    Text(FandomDisplayName.bareTitle(it).uppercase(), color = palette.accent, fontSize = 9.sp,
                        lineHeight = 14.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.99.sp)
                    if (prompt.fandoms.size > 1) Text("+${prompt.fandoms.size - 1}", color = palette.accent.copy(alpha = 0.6f),
                        fontSize = 9.sp, lineHeight = 14.sp, fontWeight = FontWeight.Bold)
                }
                PromptClaimState(prompt)
            } else Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
                prompt.fandoms.firstOrNull()?.let {
                    Text(FandomDisplayName.bareTitle(it).uppercase(), color = palette.accent, fontSize = 9.sp,
                        lineHeight = 14.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.99.sp,
                        maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                    if (prompt.fandoms.size > 1) Text("+${prompt.fandoms.size - 1}", color = palette.accent.copy(alpha = 0.6f),
                        fontSize = 9.sp, lineHeight = 14.sp, fontWeight = FontWeight.Bold)
                }
                PromptClaimState(prompt)
            }
            if (prompt.title.isNotEmpty()) Text(prompt.title, color = tokens.primaryInk, fontSize = 15.sp,
                lineHeight = 21.sp, fontWeight = FontWeight.SemiBold)
            Text(prompt.promptText, color = tokens.primaryInk, fontSize = 14.5.sp, lineHeight = 21.sp)
            if (prompt.tags.isNotEmpty()) CompositionLocalProvider(
                LocalKudosTokens provides tokens.copy(primaryInk = tokens.secondaryInk.copy(alpha = 0.65f))
            ) {
                SubjectChip(prompt.tags.joinToString(", "), maxLines = if (large) Int.MAX_VALUE else 1)
            }
            Text(if (prompt.isAnonymous) "Posted anonymously" else prompt.displayedOwner ?: "Unknown poster",
                color = tokens.secondaryInk, fontSize = 11.5.sp, lineHeight = 17.sp)
            if (prompt.claimedByCurrentUser) {
                if (large) Column(Modifier.fillMaxWidth().padding(top = 2.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Claimed by you", color = palette.accent, fontSize = 12.5.sp, lineHeight = 18.sp, fontWeight = FontWeight.Medium)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        PromptMemeAction("Release", prominent = false, inFlight = inFlight, enabled = enabled, action = onRelease)
                    }
                } else Row(Modifier.fillMaxWidth().padding(top = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("Claimed by you", color = palette.accent, fontSize = 12.5.sp, lineHeight = 18.sp,
                        fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
                    PromptMemeAction("Release", prominent = false, inFlight = inFlight, enabled = enabled, action = onRelease)
                }
            } else if (prompt.canClaim || prompt.isClaimed) Row(Modifier.fillMaxWidth().padding(top = 2.dp),
                horizontalArrangement = Arrangement.End) {
                if (prompt.canClaim) PromptMemeAction("Claim", prominent = true, inFlight = inFlight, enabled = enabled, action = onClaim)
                else PromptMemeAction("Fill it", prominent = false, inFlight = false, enabled = enabled, action = onOpenWeb)
            }
        }
    }
}

@Composable
private fun PromptMemeAction(title: String, prominent: Boolean, inFlight: Boolean, enabled: Boolean, action: () -> Unit) {
    val tokens = LocalKudosTokens.current
    val palette = tokens.scopePalette
    val ink = if (prominent) SubjectPalette.label(palette.accent) else palette.accent
    val shape = RoundedCornerShape(50)
    Box(Modifier.heightIn(min = 44.dp).clickable(enabled = enabled, role = Role.Button, onClick = action),
        contentAlignment = Alignment.Center) {
        Row(Modifier.heightIn(min = 34.dp).clip(shape)
            .background(if (prominent) palette.accent else palette.accent.copy(alpha = 0.14f))
            .padding(horizontal = 14.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically) {
            if (inFlight) CircularProgressIndicator(color = ink, trackColor = ink.copy(alpha = 0.2f),
                modifier = Modifier.size(14.dp).testTag("prompt-action-progress"), strokeWidth = 2.dp)
            else if (title == "Fill it") Icon(Icons.Outlined.OpenInBrowser, null, tint = ink, modifier = Modifier.size(14.dp))
            Text(title, color = ink, fontSize = 12.5.sp, lineHeight = 18.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun PromptClaimState(prompt: AO3PromptMemePrompt) {
    Text(if (prompt.isClaimed) "claimed" else "unclaimed", color = LocalKudosTokens.current.secondaryInk.copy(alpha = 0.6f),
        fontSize = 9.sp, lineHeight = 14.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.45.sp)
}

@Composable
private fun PromptMemeMessage(title: String, body: String, action: @Composable () -> Unit = {}) {
    val tokens = LocalKudosTokens.current
    SettingsPanel(Modifier.padding(top = 8.dp)) {
        Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(title, color = tokens.primaryInk, fontSize = 15.sp, lineHeight = 21.sp, fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.Center)
            Text(body, color = tokens.secondaryInk, fontSize = 13.sp, lineHeight = 19.sp, textAlign = TextAlign.Center)
            action()
        }
    }
}
