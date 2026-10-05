package io.github.cidy02.kudos.account

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ExitToApp
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionParticipant
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionParticipantRole
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.settings.SettingsActionRow
import io.github.cidy02.kudos.settings.SubjectTextFieldRow
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.ui.subject.*
import kotlinx.coroutines.launch

@Composable
fun AO3CollectionMaintainersScreen(
    slug: String,
    title: String,
    repository: AO3CollectionDetailRepository,
    writes: AO3WriteRepository,
    onLeft: () -> Unit
) {
    val auth = repository.authRepository
    val generation by auth.generation.collectAsState()
    val authState by auth.state.collectAsState()
    val model = remember(slug, repository, writes, generation, authState.isSignedIn) {
        AO3CollectionMaintainersState(slug, repository, writes)
    }
    val state by model.state.collectAsState()
    val scope = rememberCoroutineScope()
    val tokens = LocalKudosTokens.current
    val effectiveTitle = title.ifEmpty { slug }
    val palette = remember(effectiveTitle, tokens.theme) {
        SubjectPalette.fromHue(HomeFacts.workHue(emptyList(), effectiveTitle), tokens.theme)
    }
    val red = SubjectPalette.fromHue(0.0, tokens.theme).accent
    var roleMenu by remember(model) { mutableStateOf(false) }
    LaunchedEffect(model) { model.load() }
    LaunchedEffect(model, state.left) { if (state.left && authState.isSignedIn) onLeft() }
    DisposableEffect(model) { onDispose { model.close() } }
    ProvidePushedShellChrome(hasSubjectHeader = true)

    CompositionLocalProvider(LocalKudosTokens provides tokens.copy(accent = palette.accent)) {
        // The shared refresh/dialog/menu chrome must also use subject tokens on all four themes.
        MaterialTheme(colorScheme = MaterialTheme.colorScheme.copy(
            primary = palette.accent, onPrimary = SubjectPalette.label(palette.accent),
            secondary = palette.accent, onSecondary = SubjectPalette.label(palette.accent),
            primaryContainer = palette.chipFill, onPrimaryContainer = palette.accentOnFill,
            secondaryContainer = palette.chipFill, onSecondaryContainer = palette.accentOnFill,
            tertiary = palette.accent, onTertiary = SubjectPalette.label(palette.accent),
            tertiaryContainer = palette.chipFill, onTertiaryContainer = palette.accentOnFill,
            inversePrimary = palette.accent, inverseSurface = tokens.cardFill, inverseOnSurface = tokens.primaryInk,
            error = red, onError = tokens.cardFill, errorContainer = tokens.panelFill, onErrorContainer = tokens.primaryInk,
            surfaceTint = palette.accent, surfaceVariant = tokens.cardFill,
            surfaceDim = tokens.background, surfaceBright = tokens.cardFill,
            surfaceContainerLowest = tokens.background, surfaceContainerLow = tokens.cardFill,
            surfaceContainerHighest = tokens.cardFill, surface = tokens.cardFill,
            onSurface = tokens.primaryInk, onSurfaceVariant = tokens.secondaryInk,
            surfaceContainer = tokens.cardFill, surfaceContainerHigh = tokens.cardFill,
            background = tokens.background, onBackground = tokens.primaryInk,
            outline = tokens.separator, outlineVariant = tokens.separator, scrim = tokens.primaryInk.copy(alpha = 0.32f)
        )) {
            KudosRefreshBox(onRefresh = { model.load() }, modifier = Modifier.fillMaxSize().subjectScreenWash(palette)) {
                LazyColumn(modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
                    item {
                        Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
                        Spacer(Modifier.height(56.dp))
                        val count = state.owners.size + state.moderators.size
                        SubjectHeaderBlock(kicker = "AO3 Account", title = "Maintainers",
                            subtitle = "$effectiveTitle · ${if (count == 1) "1 person" else "$count people"}",
                            palette = palette, gutter = SubjectMetrics.accountGutter)
                    }
                    when {
                        state.loading || (!state.loaded && state.loadError == null && authState.isSignedIn) -> item {
                            Row(Modifier.fillMaxWidth().padding(vertical = 24.dp),
                                horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                                MaintainersSpinner(palette)
                                Spacer(Modifier.width(10.dp))
                                Text("Loading maintainers…", color = tokens.secondaryInk, fontSize = 14.sp, lineHeight = 20.sp)
                            }
                        }
                        state.loadError != null || !authState.isSignedIn -> item {
                            Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 14.dp)
                                .fillMaxWidth().subjectPanel().padding(16.dp),
                                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text("Couldn't load maintainers", color = tokens.primaryInk, fontSize = 15.sp,
                                    lineHeight = 21.sp, fontWeight = FontWeight.SemiBold)
                                Text(state.loadError ?: "Log in to AO3 before using this feature.", color = tokens.secondaryInk,
                                    fontSize = 13.sp, lineHeight = 19.sp, textAlign = TextAlign.Center)
                                TextButton(onClick = { scope.launch { model.load() } }, enabled = authState.isSignedIn) {
                                    Text("Try Again", color = palette.accent, lineHeight = 20.sp)
                                }
                            }
                        }
                        else -> {
                            if (state.owners.isNotEmpty()) {
                                item { MaintainersSectionHeader("Owners") }
                                item { MaintainersPanel {
                                    state.owners.forEachIndexed { index, owner ->
                                        if (index > 0) SubjectRowSeparator()
                                        MaintainerRow(owner, if (model.isReader(owner.pseud)) "You · created the collection" else null, palette)
                                    }
                                } }
                            }
                            if (state.moderators.isNotEmpty()) {
                                item { MaintainersSectionHeader("Moderators") }
                                item { MaintainersPanel {
                                    state.moderators.forEachIndexed { index, moderator ->
                                        if (index > 0) SubjectRowSeparator()
                                        MaintainerRow(moderator, "Can approve works, cannot delete the collection", palette)
                                    }
                                } }
                            }
                            item { MaintainersSectionHeader("Invitations") }
                            item { MaintainersPanel {
                                SubjectTextFieldRow("Invite by username", state.username, "Add a username", model::changeUsername,
                                    autocorrect = false)
                                SubjectRowSeparator()
                                // The menu has its own row, so sending cannot open the role picker.
                                Box(Modifier.fillMaxWidth()) {
                                    SubjectFormRow("Invite as", value = state.role.title, valueMaxLines = Int.MAX_VALUE,
                                        onClick = { roleMenu = true })
                                    DropdownMenu(expanded = roleMenu, onDismissRequest = { roleMenu = false }, containerColor = tokens.cardFill) {
                                        listOf(AO3CollectionParticipantRole.Moderator, AO3CollectionParticipantRole.Owner).forEach { role ->
                                            DropdownMenuItem(text = { Text(role.title, color = tokens.primaryInk,
                                                fontSize = 14.5.sp, lineHeight = 20.sp) }, onClick = { roleMenu = false; model.chooseRole(role) })
                                        }
                                    }
                                }
                                if (state.username.trim().isNotEmpty()) {
                                    SubjectRowSeparator()
                                    TextButton(onClick = { scope.launch { model.invite() } }, enabled = !state.busy,
                                        modifier = Modifier.fillMaxWidth(), contentPadding = PaddingValues(horizontal = 14.dp, vertical = 12.dp)) {
                                        if (state.inviting) {
                                            MaintainersSpinner(palette)
                                            Spacer(Modifier.width(8.dp))
                                        }
                                        Text("Send invitation to ${state.username.trim()}",
                                            color = palette.accent.copy(alpha = if (state.busy) 0.45f else 1f),
                                            fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold,
                                            textAlign = TextAlign.Center)
                                    }
                                }
                            } }
                            item {
                                Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 8.dp),
                                    verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                    state.notice?.let { Text(it, color = palette.accent, fontSize = 11.5.sp, lineHeight = 17.sp) }
                                    state.inviteError?.let { Text(it, color = red, fontSize = 11.5.sp, lineHeight = 17.sp) }
                                    Text("AO3 sends the other account an invitation. Nothing changes until they accept it. " +
                                        "An owner can remove a moderator, but the last owner can't step down.",
                                        color = tokens.secondaryInk, fontSize = 11.5.sp, lineHeight = 17.sp, modifier = Modifier.padding(horizontal = 4.dp))
                                }
                            }
                            item { MaintainersSectionHeader("Leave") }
                            item { MaintainersPanel {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    SettingsActionRow(if (model.isOwner) "Step down as owner" else "Leave collection",
                                        onClick = model::leaveTap, icon = Icons.AutoMirrored.Filled.ExitToApp,
                                        destructive = true, enabled = !state.busy, modifier = Modifier.weight(1f))
                                    if (state.leaving) Box(Modifier.padding(end = 13.dp)) { MaintainersSpinner(palette) }
                                }
                            } }
                            state.leaveError?.let { message -> item {
                                Text(message, color = red, fontSize = 11.5.sp, lineHeight = 17.sp,
                                    modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 8.dp))
                            } }
                        }
                    }
                }
            }
            state.dialog?.let { dialog ->
                val lastOwner = dialog == AO3CollectionMaintainersUiState.Dialog.LastOwner
                val owner = dialog == AO3CollectionMaintainersUiState.Dialog.Owner
                AlertDialog(onDismissRequest = model::cancelDialog, containerColor = tokens.cardFill,
                    titleContentColor = tokens.primaryInk, textContentColor = tokens.secondaryInk,
                    title = { Text(if (lastOwner) "Cannot Step Down" else if (owner) "Step down as owner?" else "Leave collection?", lineHeight = 28.sp) },
                    text = { Text(when {
                        lastOwner -> "You're the last owner. Appoint another owner before you step down."
                        owner -> "You will relinquish owner privileges for $effectiveTitle. Another owner must maintain the collection."
                        else -> "You will no longer be a moderator for $effectiveTitle."
                    }, lineHeight = 22.sp) },
                    confirmButton = { TextButton(onClick = {
                        if (lastOwner) model.cancelDialog() else scope.launch { model.confirmLeave() }
                    }) { Text(if (lastOwner) "OK" else if (owner) "Step Down" else "Leave",
                        color = if (lastOwner) palette.accent else red, lineHeight = 20.sp) } },
                    dismissButton = { if (!lastOwner) TextButton(onClick = model::cancelDialog) {
                        Text("Cancel", color = palette.accent, lineHeight = 20.sp)
                    } })
            }
        }
    }
}

@Composable
private fun MaintainersSectionHeader(title: String) {
    SectionRuleHeader(title = title, modifier = Modifier.padding(top = 18.dp, bottom = 8.dp))
}

@Composable
private fun MaintainersPanel(content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter).fillMaxWidth().subjectPanel(), content = content)
}

@Composable
private fun MaintainersSpinner(palette: SubjectPalette) {
    CircularProgressIndicator(color = palette.accent, trackColor = LocalKudosTokens.current.separator, modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
}

@Composable
private fun MaintainerRow(person: AO3CollectionParticipant, subtitle: String?, palette: SubjectPalette) {
    val tokens = LocalKudosTokens.current
    val stacked = isAccessibilityFontScale()
    val badge: @Composable () -> Unit = {
        Text(person.role.uppercase(), color = tokens.secondaryInk, fontSize = 10.5.sp, lineHeight = 15.sp,
            fontWeight = FontWeight.SemiBold, letterSpacing = 0.42.sp,
            modifier = Modifier.background(tokens.glassFill(0.08), RoundedCornerShape(99.dp))
                .border(0.5.dp, tokens.glassStroke(0.12), RoundedCornerShape(99.dp)).padding(horizontal = 10.dp, vertical = 5.dp))
    }
    Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(11.dp)) {
        Box(Modifier.size(32.dp).background(Brush.linearGradient(listOf(palette.accent.copy(alpha = 0.35f), tokens.cardFill.copy(alpha = 0.8f))), CircleShape)
            .border(0.5.dp, tokens.glassStroke(0.16), CircleShape), contentAlignment = Alignment.Center) {
            Text(person.pseud.take(1).uppercase(), color = palette.accentOnFill, fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.Bold)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(person.pseud, color = tokens.primaryInk, fontSize = 15.sp, lineHeight = 21.sp)
            subtitle?.let { Text(it, color = tokens.secondaryInk, fontSize = 11.5.sp, lineHeight = 17.sp) }
            if (stacked) badge()
        }
        if (!stacked) badge()
    }
}
