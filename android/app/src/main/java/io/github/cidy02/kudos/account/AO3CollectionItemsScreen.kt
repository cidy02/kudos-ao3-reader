package io.github.cidy02.kudos.account

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionItem
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionItemApproval
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionItemDraft
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionItemTab
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.ui.components.KudosPaginationBar
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectChip
import io.github.cidy02.kudos.ui.subject.SubjectChipStyle
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectKicker
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.ToolbarCircleButton
import io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale
import io.github.cidy02.kudos.ui.subject.subjectPanel
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import kotlinx.coroutines.launch

@Composable
fun AO3CollectionItemsScreen(
    slug: String,
    title: String,
    repository: AO3CollectionDetailRepository,
    writes: AO3WriteRepository
) {
    val auth = repository.authRepository
    val generation by auth.generation.collectAsState()
    val authState by auth.state.collectAsState()
    // Key the state on auth before rendering: replacement sessions never see old private rows/forms.
    val model = remember(slug, generation, authState.isSignedIn) { AO3CollectionItemsState(slug, repository, writes) }
    val state by model.state.collectAsState()
    var tab by remember(slug) { mutableStateOf(AO3CollectionItemTab.Unreviewed) }
    var confirming by remember(slug, generation, authState.isSignedIn) { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val tokens = LocalKudosTokens.current
    val palette = tokens.scopePalette
    val pending = state.pending.size
    val canSubmit = pending > 0 && !state.busy && authState.isSignedIn
    val submitting = state.phase == AO3CollectionItemsUiState.Phase.Submitting
    val loadError = state.loadError ?: AO3CollectionItemsState.SIGNED_OUT.takeIf { !authState.isSignedIn }
    LaunchedEffect(model, tab) { model.load(tab, 1) }

    ProvidePushedShellChrome(hasSubjectHeader = true, trailingContent = {
        if (pending > 0) {
            Text("$pending staged", color = tokens.secondaryInk, fontSize = 12.sp, lineHeight = 17.sp)
            ToolbarCircleButton(
                onClick = { if (!submitting) model.discard() }, accessibilityName = "Discard",
                palette = palette, modifier = Modifier.alpha(if (submitting) 0.45f else 1f)
                    .semantics { if (submitting) disabled() }
            ) { Icon(Icons.Filled.Close, contentDescription = null) }
        }
        ToolbarCircleButton(
            onClick = { if (canSubmit) confirming = true },
            accessibilityName = if (pending == 0) "Submit staged changes" else "Submit $pending staged changes",
            palette = palette, modifier = Modifier.alpha(if (canSubmit) 1f else 0.45f)
                .semantics { if (!canSubmit) disabled() }
        ) { Icon(Icons.Filled.Check, contentDescription = null) }
    })

    // The collection page uses AlertDialog. Explicit colours also cover shared pagination/refresh chrome.
    MaterialTheme(colorScheme = MaterialTheme.colorScheme.copy(
        primary = palette.accent, onPrimary = SubjectPalette.label(palette.accent),
        secondary = palette.accent, onSecondary = SubjectPalette.label(palette.accent),
        primaryContainer = palette.chipFill, onPrimaryContainer = palette.accentOnFill,
        secondaryContainer = palette.chipFill, onSecondaryContainer = palette.accentOnFill,
        tertiary = palette.accent, onTertiary = SubjectPalette.label(palette.accent),
        tertiaryContainer = palette.chipFill, onTertiaryContainer = palette.accentOnFill,
        inversePrimary = palette.accent, inverseSurface = tokens.cardFill, inverseOnSurface = tokens.primaryInk,
        error = SubjectPalette.fromHue(0.0, tokens.theme).accent, onError = tokens.cardFill,
        errorContainer = tokens.panelFill, onErrorContainer = tokens.primaryInk,
        surfaceTint = palette.accent, surfaceVariant = tokens.cardFill,
        surfaceDim = tokens.background, surfaceBright = tokens.cardFill,
        surfaceContainerLowest = tokens.background, surfaceContainerLow = tokens.cardFill,
        surfaceContainerHighest = tokens.cardFill,
        surface = tokens.cardFill, onSurface = tokens.primaryInk, onSurfaceVariant = tokens.secondaryInk,
        surfaceContainer = tokens.cardFill, surfaceContainerHigh = tokens.cardFill,
        background = tokens.background, onBackground = tokens.primaryInk, outline = tokens.separator,
        outlineVariant = tokens.separator, scrim = tokens.primaryInk.copy(alpha = 0.32f)
    )) {
        if (confirming) {
            AlertDialog(
                onDismissRequest = { confirming = false },
                containerColor = tokens.cardFill, titleContentColor = tokens.primaryInk,
                textContentColor = tokens.secondaryInk,
                title = { Text("Submit staged changes?", lineHeight = 28.sp) },
                text = { Text("Submit $pending staged change${if (pending == 1) "" else "s"} to AO3?", lineHeight = 22.sp) },
                confirmButton = {
                    TextButton(onClick = {
                        confirming = false
                        scope.launch { model.confirmSubmit() }
                    }, enabled = canSubmit) { Text("Submit", color = palette.accent, lineHeight = 20.sp) }
                },
                dismissButton = {
                    TextButton(onClick = { confirming = false }) { Text("Cancel", color = palette.accent, lineHeight = 20.sp) }
                }
            )
        }
        KudosRefreshBox(onRefresh = { if (!confirming && !state.busy) model.load(tab) },
            modifier = Modifier.fillMaxSize().subjectScreenWash(palette)) {
            LazyColumn(modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
                item {
                    Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
                    Spacer(Modifier.height(56.dp))
                    val items = state.page?.items.orEmpty()
                    val decisions = items.count { it.creatorApproval == AO3CollectionItemApproval.Unreviewed ||
                        it.moderatorApproval == AO3CollectionItemApproval.Unreviewed }
                    val tally = if (decisions > 0) "$decisions ${if (decisions == 1) "needs" else "need"} a decision"
                        else "${items.size} item${if (items.size == 1) "" else "s"}"
                    val paging = state.page?.takeIf { it.totalPages > 1 }?.let {
                        " · page ${it.currentPage} of ${it.totalPages}"
                    }.orEmpty()
                    SubjectHeaderBlock(kicker = "AO3 Account › Collections", title = "Collection items",
                        subtitle = "$title · $tally$paging", palette = palette, gutter = SubjectMetrics.accountGutter)
                    Row(Modifier.padding(top = 14.dp).horizontalScroll(rememberScrollState())
                        .padding(horizontal = SubjectMetrics.accountGutter), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        AO3CollectionItemTab.entries.forEach { option ->
                            SubjectChip(option.title, style = SubjectChipStyle.Pill(tab == option), palette = palette,
                                modifier = Modifier.clickable(enabled = !submitting && !confirming) { tab = option })
                        }
                        SubjectChip("Reset", style = SubjectChipStyle.Pill(false), leadingIcon = Icons.Filled.Close,
                            modifier = Modifier.alpha(if (tab == AO3CollectionItemTab.Unreviewed) 0.45f else 0.7f)
                                .clickable(enabled = tab != AO3CollectionItemTab.Unreviewed && !submitting && !confirming) {
                                    tab = AO3CollectionItemTab.Unreviewed
                                }.semantics { contentDescription = "Reset filters" })
                    }
                }
                state.submitError?.let { message -> item { ItemsMessage(message, isError = true) } }
                loadError?.let { message ->
                    item {
                        if (!state.page?.items.isNullOrEmpty() || !authState.isSignedIn) {
                            ItemsMessage(message, isError = true)
                        } else Column(Modifier.padding(top = 14.dp).padding(horizontal = SubjectMetrics.accountGutter)
                            .fillMaxWidth().subjectPanel().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            if (state.phase != AO3CollectionItemsUiState.Phase.SignedOut) {
                                Text("Couldn't load collection items", color = tokens.primaryInk,
                                    fontSize = 15.sp, lineHeight = 21.sp, fontWeight = FontWeight.SemiBold)
                            }
                            Text(message, color = tokens.secondaryInk, fontSize = 13.sp, lineHeight = 19.sp)
                            if (authState.isSignedIn) {
                                TextButton(onClick = { scope.launch { model.load(tab) } }) {
                                    Text("Try Again", color = palette.accent, lineHeight = 20.sp)
                                }
                            }
                        }
                    }
                }
                if (authState.isSignedIn && (state.busy || state.phase == AO3CollectionItemsUiState.Phase.Idle) &&
                    state.page?.items.isNullOrEmpty()) {
                    item { Box(Modifier.fillMaxWidth().padding(top = 20.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = palette.accent, trackColor = tokens.separator, modifier = Modifier.size(24.dp))
                    } }
                } else if (state.phase == AO3CollectionItemsUiState.Phase.Loaded && state.page?.items.isNullOrEmpty()) {
                    item { ItemsMessage("Nothing in this tab.") }
                }
                items(state.page?.items.orEmpty(), key = { it.id }) { item ->
                    CollectionItemPanel(item, state.staging.shown(item), state.staging.pending(listOf(item)).isNotEmpty(),
                        enabled = !state.busy && !confirming,
                        onStage = { change -> model.stage(item, change) }, onRemove = { model.remove(item) })
                }
                state.page?.takeIf { it.totalPages > 1 }?.let { page ->
                    item {
                        KudosPaginationBar(page.currentPage, page.totalPages,
                            onPageChange = { scope.launch { model.load(tab, it) } }, enabled = !state.busy && !confirming, stacked = isAccessibilityFontScale(),
                            modifier = Modifier.padding(top = 14.dp).padding(horizontal = SubjectMetrics.accountGutter).subjectPanel())
                    }
                }
            }
        }
    }
}

@Composable
private fun ItemsMessage(message: String, isError: Boolean = false) {
    val tokens = LocalKudosTokens.current
    Text(message, color = if (isError) SubjectPalette.fromHue(0.0, tokens.theme).accent else tokens.secondaryInk, fontSize = 12.5.sp, lineHeight = 18.sp,
        modifier = Modifier.fillMaxWidth().padding(top = 14.dp).padding(horizontal = SubjectMetrics.accountGutter)
            .subjectPanel().padding(horizontal = 14.dp, vertical = 12.dp))
}

@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
private fun CollectionItemPanel(
    item: AO3CollectionItem,
    draft: AO3CollectionItemDraft,
    changed: Boolean,
    enabled: Boolean,
    onStage: ((AO3CollectionItemDraft) -> AO3CollectionItemDraft) -> Unit,
    onRemove: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    val accessibility = isAccessibilityFontScale()
    val palette = SubjectPalette.fromHue(HomeFacts.workHue(emptyList(), item.collectionTitle), tokens.theme)
    Column(Modifier.padding(top = 10.dp).padding(horizontal = SubjectMetrics.accountGutter).fillMaxWidth()
        .subjectPanel().alpha(if (draft.remove) 0.7f else 1f).padding(horizontal = 18.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        val eyebrow: @Composable () -> Unit = {
            SubjectKicker(item.collectionTitle, palette, maxLines = if (accessibility) Int.MAX_VALUE else 1)
        }
        val role: @Composable () -> Unit = {
            if (item.role.isNotBlank()) Text(item.role, color = tokens.secondaryInk, fontSize = 10.sp, lineHeight = 14.sp)
            if (changed) Box(Modifier.size(7.dp).background(palette.accent, CircleShape)
                .semantics { contentDescription = "Has unsent changes" })
        }
        if (accessibility) {
            eyebrow()
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) { role() }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(1f)) { eyebrow() }
                role()
            }
        }
        Text(item.workTitle, color = tokens.primaryInk, fontSize = 19.sp, lineHeight = 25.sp,
            fontWeight = FontWeight.SemiBold, maxLines = if (accessibility) Int.MAX_VALUE else 2,
            textDecoration = if (draft.remove) TextDecoration.LineThrough else TextDecoration.None)
        if (draft.remove) {
            Text("This work will leave the collection when you submit your changes. It stays on AO3.",
                color = tokens.secondaryInk, fontSize = 12.sp, lineHeight = 17.sp)
        } else {
            Column {
                ItemApprovalRow("Approved by creator", draft.creatorApproval ?: item.creatorApproval,
                    item.creatorEditable && enabled) { approval -> onStage { it.copy(creatorApproval = approval) } }
                SubjectRowSeparator()
                ItemApprovalRow("Approved by moderators", draft.moderatorApproval ?: item.moderatorApproval,
                    item.moderatorEditable && enabled) { approval -> onStage { it.copy(moderatorApproval = approval) } }
                SubjectRowSeparator()
                ItemFlagRow("Unrevealed", draft.unrevealed ?: item.unrevealed, item.unrevealedEditable, enabled, palette) { value ->
                    onStage { it.copy(unrevealed = value) }
                }
                SubjectRowSeparator()
                ItemFlagRow("Anonymous", draft.anonymous ?: item.anonymous, item.anonymousEditable, enabled, palette) { value ->
                    onStage { it.copy(anonymous = value) }
                }
            }
        }
        val byline: @Composable (Modifier) -> Unit = { modifier ->
            if (item.creatorByline.isNotBlank()) Text(item.creatorByline, modifier = modifier, color = tokens.secondaryInk,
                fontSize = 11.5.sp, lineHeight = 17.sp, maxLines = if (accessibility) Int.MAX_VALUE else 1,
                overflow = TextOverflow.Ellipsis)
        }
        val action: @Composable () -> Unit = {
            if (item.removeEditable || draft.remove) {
                TextButton(onClick = onRemove, enabled = enabled, contentPadding = PaddingValues(0.dp)) {
                    Text(if (draft.remove) "Keep" else "Remove from collection", lineHeight = 17.sp, fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold, color = if (draft.remove) palette.accent else
                            SubjectPalette.fromHue(0.0, tokens.theme).accent)
                }
            }
        }
        val date: @Composable () -> Unit = {
            if (item.dateText.isNotBlank()) Text(item.dateText, color = tokens.secondaryInk, fontSize = 11.5.sp, lineHeight = 17.sp)
        }
        if (accessibility) Column { byline(Modifier); action(); date() } else {
            // One centred line, as on iOS: the byline, the action beside it, the date at the end.
            // Only the byline gives way (one line, ellipsis); the action and the date never do.
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    byline(Modifier.weight(1f, fill = false))
                    action()
                }
                date()
            }
        }
    }
}

@Composable
private fun ItemSettingRow(label: String, control: @Composable () -> Unit) {
    if (isAccessibilityFontScale()) {
        Column(Modifier.fillMaxWidth().padding(vertical = 9.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(label, color = LocalKudosTokens.current.secondaryInk, fontSize = 13.5.sp, lineHeight = 19.sp)
            control()
        }
    } else SubjectFormRow(label = label, trailing = control)
}

@Composable
private fun ItemApprovalRow(label: String, value: AO3CollectionItemApproval, editable: Boolean,
    onSelect: (AO3CollectionItemApproval) -> Unit) {
    var choosing by remember(editable) { mutableStateOf(false) }
    val tokens = LocalKudosTokens.current
    val hue = when (value) {
        AO3CollectionItemApproval.Unreviewed -> 0.10
        AO3CollectionItemApproval.Approved -> 0.36
        AO3CollectionItemApproval.Rejected -> 0.0
    }
    ItemSettingRow(label) {
        SubjectChip(value.title, style = SubjectChipStyle.Tinted, palette = SubjectPalette.fromHue(hue, tokens.theme),
            trailingIcon = if (editable) Icons.Filled.ExpandMore else null,
            modifier = Modifier.clickable(enabled = editable) { choosing = true }
                .semantics { contentDescription = "$label: ${value.title}" })
    }
    if (choosing) AlertDialog(onDismissRequest = { choosing = false }, containerColor = tokens.cardFill,
        titleContentColor = tokens.primaryInk, textContentColor = tokens.secondaryInk,
        title = { Text(label, lineHeight = 28.sp) }, text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                AO3CollectionItemApproval.entries.forEach { option ->
                    SubjectChip(option.title, style = SubjectChipStyle.Pill(value == option), palette = tokens.scopePalette,
                        modifier = Modifier.clickable { choosing = false; onSelect(option) })
                }
            }
        }, confirmButton = {
            TextButton(onClick = { choosing = false }) { Text("Cancel", color = tokens.accent, lineHeight = 20.sp) }
        })
}

@Composable
private fun ItemFlagRow(label: String, value: Boolean, editable: Boolean, enabled: Boolean,
    palette: SubjectPalette, onChange: (Boolean) -> Unit) {
    val tokens = LocalKudosTokens.current
    ItemSettingRow(label) {
        if (editable) Switch(checked = value, onCheckedChange = onChange, enabled = enabled,
            modifier = Modifier.semantics { contentDescription = label }, colors = SwitchDefaults.colors(
                checkedThumbColor = tokens.cardFill, checkedTrackColor = palette.accent,
                checkedBorderColor = palette.accent, uncheckedThumbColor = tokens.secondaryInk,
                uncheckedTrackColor = tokens.panelFill, uncheckedBorderColor = tokens.separator,
                disabledCheckedThumbColor = tokens.secondaryInk, disabledCheckedTrackColor = tokens.panelFill,
                disabledCheckedBorderColor = tokens.separator, disabledUncheckedThumbColor = tokens.tertiaryInk,
                disabledUncheckedTrackColor = tokens.panelFill, disabledUncheckedBorderColor = tokens.separator
            )) else Text(if (value) "On" else "Off", color = tokens.secondaryInk, fontSize = 12.sp, lineHeight = 17.sp)
    }
}
