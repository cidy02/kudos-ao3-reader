package io.github.cidy02.kudos.account

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.settings.SettingsActionRow
import io.github.cidy02.kudos.settings.SettingsPanel
import io.github.cidy02.kudos.ui.components.KudosPaginationBar
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.ui.subject.*
import kotlinx.coroutines.launch

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun AO3CollectionModerationScreen(
    slug: String,
    title: String,
    viewerIsOwner: Boolean,
    repository: AO3CollectionDetailRepository,
    writes: AO3WriteRepository,
    onRecentlyDecided: () -> Unit,
    onMaintainers: () -> Unit,
    onMessageCreator: (Long) -> Unit
) {
    val auth = repository.authRepository
    val generation by auth.generation.collectAsState()
    val authState by auth.state.collectAsState()
    val model = remember(slug, generation, authState.isSignedIn, viewerIsOwner) {
        AO3CollectionModerationState(slug, viewerIsOwner, repository, writes)
    }
    val state by model.state.collectAsState()
    val scope = rememberCoroutineScope()
    val tokens = LocalKudosTokens.current
    val effectiveTitle = title.ifEmpty { slug }
    val palette = SubjectPalette.fromHue(HomeFacts.workHue(emptyList(), effectiveTitle), tokens.theme)
    val errorColor = SubjectPalette.fromHue(0.0, tokens.theme).accent
    val large = isAccessibilityFontScale()
    LaunchedEffect(model) { model.load() }
    ProvidePushedShellChrome(hasSubjectHeader = true)

    MaterialTheme(colorScheme = MaterialTheme.colorScheme.copy(
        primary = palette.accent, onPrimary = SubjectPalette.label(palette.accent),
        primaryContainer = palette.chipFill, onPrimaryContainer = palette.accentOnFill,
        secondary = palette.accent, onSecondary = SubjectPalette.label(palette.accent),
        secondaryContainer = palette.chipFill, onSecondaryContainer = palette.accentOnFill,
        tertiary = palette.accent, onTertiary = SubjectPalette.label(palette.accent),
        tertiaryContainer = palette.chipFill, onTertiaryContainer = palette.accentOnFill,
        inversePrimary = palette.accent, inverseSurface = tokens.cardFill, inverseOnSurface = tokens.primaryInk,
        surface = tokens.cardFill, surfaceContainerHigh = tokens.cardFill,
        surfaceVariant = tokens.cardFill, surfaceContainer = tokens.cardFill,
        surfaceContainerHighest = tokens.cardFill, surfaceContainerLow = tokens.cardFill,
        surfaceContainerLowest = tokens.background, surfaceDim = tokens.background, surfaceBright = tokens.cardFill,
        onSurface = tokens.primaryInk, onSurfaceVariant = tokens.secondaryInk,
        error = errorColor, onError = tokens.cardFill, errorContainer = tokens.panelFill, onErrorContainer = tokens.primaryInk,
        background = tokens.background, onBackground = tokens.primaryInk,
        outline = tokens.separator, outlineVariant = tokens.separator, surfaceTint = palette.accent,
        scrim = tokens.primaryInk.copy(alpha = 0.32f)
    )) {
        state.pending?.let { decision ->
            AlertDialog(onDismissRequest = model::cancel,
                containerColor = tokens.cardFill, titleContentColor = tokens.primaryInk, textContentColor = tokens.secondaryInk,
                title = { Text(decision.title, lineHeight = 28.sp) },
                text = { Text(decision.message, lineHeight = 22.sp) },
                confirmButton = { TextButton(onClick = { scope.launch { model.confirm() } }, enabled = !state.busy) {
                    Text(decision.button, color = errorColor, lineHeight = 20.sp)
                } }, dismissButton = { TextButton(onClick = model::cancel) {
                    Text("Cancel", color = palette.accent, lineHeight = 20.sp)
                } })
        }
        KudosRefreshBox(onRefresh = { if (!state.busy && state.pending == null) model.load() },
            modifier = Modifier.fillMaxSize().subjectScreenWash(palette)) {
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
                item {
                    Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
                    Spacer(Modifier.height(76.dp))
                    val queue = state.data?.queue
                    val count = queue?.items?.size ?: 0
                    val works = if (count == 1) "1 work awaiting review" else "$count works awaiting review"
                    val paged = if (queue != null && queue.totalPages > 1)
                        " on this page · page ${queue.currentPage} of ${queue.totalPages}" else ""
                    val requests = state.data?.requests?.size ?: 0
                    SubjectHeaderBlock(kicker = effectiveTitle, title = "Moderation", palette = palette,
                        subtitle = "$works$paged · $requests membership request${if (requests == 1) "" else "s"}",
                        gutter = SubjectMetrics.accountGutter)
                }
                when {
                    state.loading -> item {
                        Row(Modifier.fillMaxWidth().padding(vertical = 24.dp), horizontalArrangement = Arrangement.Center,
                            verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(color = palette.accent, trackColor = tokens.separator,
                                modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                            Text("Loading moderation…", color = tokens.secondaryInk, fontSize = 14.sp, lineHeight = 20.sp,
                                modifier = Modifier.padding(start = 10.dp))
                        }
                    }
                    state.failure != null -> item {
                        ModerationMessage("Couldn't load moderation", state.failure.orEmpty()) {
                            ModerationPill("Try Again", palette, enabled = true) { scope.launch { model.load() } }
                        }
                    }
                    else -> {
                        state.actionError?.let { message -> item {
                            SettingsPanel(Modifier.padding(top = 8.dp)) {
                                Row(Modifier.padding(12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp),
                                    verticalAlignment = Alignment.CenterVertically) {
                                    Icon(Icons.Outlined.Warning, contentDescription = null, tint = errorColor, modifier = Modifier.size(20.dp))
                                    Text(message, color = errorColor, fontSize = 12.5.sp, lineHeight = 18.sp, modifier = Modifier.weight(1f))
                                    IconButton(onClick = model::dismissError) {
                                        Icon(Icons.Filled.Close, contentDescription = "Dismiss error", tint = tokens.secondaryInk, modifier = Modifier.size(16.dp))
                                    }
                                }
                            }
                        } }
                        val data = state.data
                        item { ModerationSection("Awaiting review", data?.queue?.items?.size ?: 0) }
                        if (data?.queue?.items.isNullOrEmpty()) item {
                            ModerationMessage("No works waiting for review", "All submissions to this collection have been reviewed.")
                        }
                        items(data?.queue?.items.orEmpty(), key = { "item-${it.id}" }) { work ->
                            Column(Modifier.padding(top = 9.dp).padding(horizontal = SubjectMetrics.accountGutter)
                                .fillMaxWidth().subjectPanel(cornerRadius = 16.dp)) {
                                Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                        Text(work.itemType.uppercase(), color = palette.accent, fontSize = 9.sp, lineHeight = 13.sp,
                                            fontWeight = FontWeight.Bold, letterSpacing = 0.99.sp)
                                        Text(work.workTitle, color = tokens.primaryInk, fontSize = 16.sp, lineHeight = 22.sp,
                                            fontWeight = FontWeight.SemiBold)
                                        Text(work.creatorByline + work.dateText.trim().takeIf { it.isNotEmpty() }
                                            ?.let { " · submitted $it" }.orEmpty(), color = tokens.secondaryInk,
                                            fontSize = 11.5.sp, lineHeight = 17.sp)
                                    }
                                    FlowRow(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                                        ModerationPill("Approve", palette, prominent = true, enabled = !state.busy,
                                            loading = state.inFlight?.let { it.id == work.id && it.action in listOf(ModerationAction.Approve, ModerationAction.Reject) } == true) {
                                            scope.launch { model.choose(ModerationDecision(ModerationAction.Approve, work.id, work.workTitle)) }
                                        }
                                        ModerationPill("Reject", palette, enabled = !state.busy) {
                                            scope.launch { model.choose(ModerationDecision(ModerationAction.Reject, work.id, work.workTitle)) }
                                        }
                                        ModerationPill("Message creator", palette, enabled = work.workId != null) {
                                            work.workId?.let(onMessageCreator)
                                        }
                                    }
                                }
                            }
                        }
                        data?.queue?.takeIf { it.totalPages > 1 }?.let { queue -> item {
                            KudosPaginationBar(queue.currentPage, queue.totalPages,
                                onPageChange = { scope.launch { model.loadPage(it) } }, enabled = !state.busy,
                                stacked = large, modifier = Modifier.padding(top = 4.dp)
                                    .padding(horizontal = SubjectMetrics.accountGutter).subjectPanel())
                        } }
                        item {
                            ModerationFootnote("AO3 doesn't send the creator a reason or email when you reject a work. The work stays on AO3 and only leaves this collection.")
                            SettingsPanel(Modifier.padding(top = 12.dp)) {
                                SubjectFormRow("Recently decided", value = "Approved and rejected", showsDisclosure = true,
                                    valueMaxLines = if (large) Int.MAX_VALUE else 1, onClick = onRecentlyDecided)
                            }
                            ModerationSection("Membership requests", data?.requests?.size ?: 0)
                        }
                        if (data?.requests.isNullOrEmpty()) item {
                            ModerationMessage("No membership requests", "Nobody is waiting to join $effectiveTitle.")
                        } else item {
                            SettingsPanel(Modifier.padding(top = 8.dp)) {
                                data?.requests.orEmpty().forEachIndexed { index, participant ->
                                    if (index > 0) SubjectRowSeparator()
                                    val identity: @Composable (Modifier) -> Unit = { modifier ->
                                        Column(modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                            Text(participant.pseud, color = tokens.primaryInk, fontSize = 14.5.sp, lineHeight = 20.sp,
                                                fontWeight = FontWeight.SemiBold)
                                            Text("Wants to join $effectiveTitle", color = tokens.secondaryInk, fontSize = 11.5.sp, lineHeight = 17.sp)
                                        }
                                    }
                                    val buttons: @Composable () -> Unit = {
                                        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                            ModerationPill("Accept", palette, prominent = true, enabled = !state.busy,
                                                loading = state.inFlight?.let { it.id == participant.id && it.action == ModerationAction.Accept } == true) {
                                                scope.launch { model.choose(ModerationDecision(ModerationAction.Accept, participant.id, participant.pseud)) }
                                            }
                                            ModerationPill("Decline", palette, enabled = !state.busy) {
                                                scope.launch { model.choose(ModerationDecision(ModerationAction.Decline, participant.id, participant.pseud)) }
                                            }
                                        }
                                    }
                                    if (large) Column(Modifier.padding(horizontal = 14.dp, vertical = 11.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                        identity(Modifier.fillMaxWidth()); buttons()
                                    } else Row(Modifier.padding(horizontal = 14.dp, vertical = 11.dp), verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(10.dp)) { identity(Modifier.weight(1f)); buttons() }
                                }
                            }
                        }
                        item {
                            ModerationSection("Maintainers")
                            SettingsPanel(Modifier.padding(top = 8.dp)) {
                                SubjectFormRow("Owners and moderators", showsDisclosure = true, onClick = onMaintainers,
                                    trailing = { Text("${data?.maintainerCount ?: 0}", color = tokens.secondaryInk, fontSize = 14.5.sp,
                                        lineHeight = 20.sp, fontFamily = FontFamily.Monospace) })
                                SubjectRowSeparator()
                                SubjectFormRow("Invite a maintainer", showsDisclosure = true, onClick = onMaintainers)
                            }
                            ModerationFootnote("This shows how many maintainers there are. Manage roles, invitations and the last-owner rule under Maintainers.")
                            ModerationSection("Reveal and anonymity")
                            SettingsPanel(Modifier.padding(top = 8.dp)) {
                                SubjectFormRow("Works", value = if (data?.unrevealed == true) "Unrevealed until reveal" else "Revealed",
                                    valueMaxLines = if (large) Int.MAX_VALUE else 1)
                                SubjectRowSeparator()
                                SubjectFormRow("Creators", value = if (data?.anonymous == true) "Anonymous until reveal" else "Credited",
                                    valueMaxLines = if (large) Int.MAX_VALUE else 1)
                                if (data?.anonymous == true) Text("Creators are hidden from everyone but maintainers.",
                                    color = tokens.secondaryInk, fontSize = 11.5.sp, lineHeight = 17.sp,
                                    modifier = Modifier.padding(horizontal = 14.dp).padding(bottom = 11.dp))
                            }
                            if (model.showsReveal || model.showsUnanon) SettingsPanel(Modifier.padding(top = 8.dp)) {
                                if (model.showsReveal) Row(verticalAlignment = Alignment.CenterVertically) {
                                    SettingsActionRow("Reveal now", icon = Icons.Outlined.Visibility, modifier = Modifier.weight(1f),
                                        destructive = true, enabled = !state.busy, onClick = { scope.launch { model.choose(ModerationDecision(ModerationAction.Reveal)) } })
                                    if (state.inFlight?.action == ModerationAction.Reveal) CircularProgressIndicator(color = errorColor,
                                        trackColor = tokens.separator, strokeWidth = 2.dp, modifier = Modifier.padding(end = 14.dp).size(18.dp))
                                }
                                if (model.showsReveal && model.showsUnanon) SubjectRowSeparator()
                                if (model.showsUnanon) Row(verticalAlignment = Alignment.CenterVertically) {
                                    SettingsActionRow("Remove anonymity", icon = Icons.Outlined.Person, modifier = Modifier.weight(1f),
                                        destructive = true, enabled = !state.busy, onClick = { scope.launch { model.choose(ModerationDecision(ModerationAction.Unanon)) } })
                                    if (state.inFlight?.action == ModerationAction.Unanon) CircularProgressIndicator(color = errorColor,
                                        trackColor = tokens.separator, strokeWidth = 2.dp, modifier = Modifier.padding(end = 14.dp).size(18.dp))
                                }
                            }
                            state.revealError?.let { Text(it, color = errorColor, fontSize = 11.5.sp, lineHeight = 17.sp,
                                modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 8.dp)) }
                            ModerationFootnote("Reveal and Remove anonymity are separate actions. You confirm each one, and neither can be undone in Kudos.")
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ModerationSection(title: String, count: Int? = null) {
    SectionRuleHeader(title, count = count, modifier = Modifier.padding(top = 18.dp))
}

@Composable
private fun ModerationFootnote(text: String) {
    Text(text, color = LocalKudosTokens.current.secondaryInk.copy(alpha = 0.7f), fontSize = 11.5.sp, lineHeight = 17.sp,
        modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter + 4.dp).padding(top = 8.dp))
}

@Composable
private fun ModerationMessage(title: String, message: String, action: (@Composable () -> Unit)? = null) {
    val tokens = LocalKudosTokens.current
    SettingsPanel(Modifier.padding(top = 8.dp)) {
        Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(title, color = tokens.primaryInk, fontSize = 15.sp, lineHeight = 21.sp, fontWeight = FontWeight.SemiBold)
            Text(message, color = tokens.secondaryInk, fontSize = 12.5.sp, lineHeight = 18.sp)
            action?.invoke()
        }
    }
}

@Composable
private fun ModerationPill(title: String, palette: SubjectPalette, enabled: Boolean, prominent: Boolean = false,
    loading: Boolean = false, onClick: () -> Unit) {
    val tokens = LocalKudosTokens.current
    val shape = RoundedCornerShape(50)
    val fill = if (prominent) palette.tint else tokens.glassFill(0.10)
    Row(Modifier.heightIn(min = 34.dp).background(fill, shape).border(0.5.dp,
        if (prominent) palette.tint else tokens.glassStroke(0.16), shape)
        .clickable(enabled = enabled, role = Role.Button, onClick = onClick).padding(horizontal = 14.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        val ink = if (prominent) SubjectPalette.label(palette.accent) else tokens.primaryInk
        if (loading) CircularProgressIndicator(color = ink, trackColor = tokens.separator,
            modifier = Modifier.size(14.dp), strokeWidth = 2.dp)
        Text(title, color = ink.copy(alpha = if (enabled || loading) 1f else 0.45f), fontSize = 12.5.sp,
            lineHeight = 18.sp, fontWeight = FontWeight.SemiBold)
    }
}
