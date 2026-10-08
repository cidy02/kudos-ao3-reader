package io.github.cidy02.kudos.works.detail

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.Layers
import androidx.compose.material.icons.outlined.Cancel
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.material3.SheetValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.library.SeriesPreservationPrompt
import io.github.cidy02.kudos.library.SeriesPreservationResult
import io.github.cidy02.kudos.library.queueText
import io.github.cidy02.kudos.network.ao3.writes.AO3BookmarkInput
import io.github.cidy02.kudos.settings.SettingsActionRow
import io.github.cidy02.kudos.settings.SettingsSection
import io.github.cidy02.kudos.settings.SubjectTextFieldRow
import io.github.cidy02.kudos.ui.subject.*

/** Grouped form sheets on the same surfaces as My Copy, with no Material field/button chrome. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DetailForm(
    title: String,
    onClose: () -> Unit,
    allowDismiss: Boolean = true,
    leading: (@Composable RowScope.() -> Unit)? = null,
    actions: @Composable RowScope.() -> Unit = {},
    content: LazyListScope.() -> Unit
) {
    val tokens = LocalKudosTokens.current
    val canDismiss by rememberUpdatedState(allowDismiss)
    // This form takes Detail's place in the route; it owns the shell row registration.
    ProvidePushedShellChrome(hasSubjectHeader = true, onBack = onClose)
    BackHandler(onBack = onClose)
    ModalBottomSheet(onDismissRequest = onClose,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true,
            confirmValueChange = { it != SheetValue.Hidden || canDismiss }),
        containerColor = tokens.background,
        scrimColor = tokens.primaryInk.copy(alpha = 0.32f),
        contentColor = tokens.primaryInk,
        dragHandle = {
            Box(Modifier.padding(vertical = 10.dp).width(32.dp).height(4.dp)
                .background(tokens.separator, androidx.compose.foundation.shape.CircleShape))
        }) {
        Column(Modifier.fillMaxHeight(0.95f).imePadding()) {
            if (isAccessibilityFontScale()) {
                Text(title, color = tokens.primaryInk, fontSize = 17.sp, lineHeight = 24.sp,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = SubjectMetrics.accountGutter, vertical = 8.dp))
                Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp)) {
                    leading?.invoke(this)
                    Spacer(Modifier.weight(1f))
                    actions()
                }
            } else Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                leading?.invoke(this)
                Text(title, color = tokens.primaryInk, fontSize = 17.sp, lineHeight = 24.sp,
                    modifier = Modifier.weight(1f).padding(horizontal = 8.dp))
                actions()
            }
            LazyColumn(Modifier.fillMaxWidth().weight(1f).subjectScreenWash(tokens.scopePalette)
                .testTag("Work detail form"), contentPadding = PaddingValues(bottom = 32.dp), content = content)
        }
    }
}

@Composable
private fun FormToolbarAction(label: String, enabled: Boolean, onClick: () -> Unit) {
    val tokens = LocalKudosTokens.current
    // The palette's accent, as the wash behind it: the theme's own accent is a deep red that
    // could barely be read as text on a dark sheet (seen on the emulator).
    Text(label, color = if (enabled) tokens.scopePalette.accent else tokens.tertiaryInk,
        fontSize = 14.sp, lineHeight = 20.sp,
        modifier = Modifier.clickable(enabled = enabled, onClick = onClick).padding(12.dp))
}

@Composable
internal fun DetailFormText(text: String, error: Boolean = false, primary: Boolean = false) {
    val tokens = LocalKudosTokens.current
    Text(text, color = when {
        error -> SubjectPalette.fromHue(0.0, tokens.theme).accent
        primary -> tokens.primaryInk
        else -> tokens.secondaryInk
    }, fontSize = if (primary) 14.5.sp else 13.sp, lineHeight = if (primary) 20.sp else 18.sp, modifier = Modifier.padding(13.dp))
}

@Composable
internal fun DetailToggleRow(label: String, checked: Boolean, enabled: Boolean = true, change: (Boolean) -> Unit) {
    // Keep the full label at large type; short control is trailing, never value.
    if (isAccessibilityFontScale()) {
        Column(Modifier.fillMaxWidth().padding(13.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(label, color = LocalKudosTokens.current.primaryInk, fontSize = 14.5.sp, lineHeight = 20.sp)
            SubjectToggle(checked, change, enabled = enabled, contentDescription = label)
        }
    } else SubjectFormRow(label, trailing = {
        SubjectToggle(checked, change, enabled = enabled, contentDescription = label)
    })
}

/** AO3WorkActionsModel.swift:190–257. No client-side length limit; AO3 supplies refusals. */
@Composable
internal fun WorkDetailBookmarkForm(
    input: AO3BookmarkInput,
    isEdit: Boolean,
    working: Boolean,
    error: String?,
    onChange: (AO3BookmarkInput) -> Unit,
    onSave: () -> Unit,
    onClose: () -> Unit
) {
    val close = { if (!working) onClose() }
    DetailForm(if (isEdit) "Edit Bookmark on AO3" else "Bookmark on AO3", close, allowDismiss = !working,
        leading = { FormToolbarAction("Cancel", !working, close) }, actions = {
        if (working) CircularProgressIndicator(color = LocalKudosTokens.current.scopePalette.accent,
            trackColor = LocalKudosTokens.current.separator, modifier = Modifier.size(20.dp))
        else FormToolbarAction("Save", true, onSave)
    }) {
        item { SettingsSection(label = "Notes", footnote = null) {
            Box(Modifier.heightIn(min = 90.dp)) {
                SubjectTextFieldRow("Notes", input.notes, "", { onChange(input.copy(notes = it)) },
                    multiline = true, fieldOnly = true, enabled = !working)
            }
        } }
        item { SettingsSection(label = "Tags", footnote = "Separate your bookmark tags with commas.") {
            SubjectTextFieldRow("Tags", input.tags, "Comma-separated tags", { onChange(input.copy(tags = it)) },
                fieldOnly = true, enabled = !working)
        } }
        item { SettingsSection(footnote = null) {
            DetailToggleRow("Private", input.isPrivate) { onChange(input.copy(isPrivate = it)) }
            SubjectRowSeparator()
            DetailToggleRow("Recommend", input.isRecommendation) { onChange(input.copy(isRecommendation = it)) }
        } }
        if (error != null) item { SettingsSection(footnote = null) {
            Row(Modifier.fillMaxWidth().padding(start = 13.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                Icon(Icons.Outlined.Warning, contentDescription = null,
                    tint = SubjectPalette.fromHue(0.0, LocalKudosTokens.current.theme).accent, modifier = Modifier.size(20.dp))
                Box(Modifier.weight(1f)) { DetailFormText(error, error = true) }
            }
        } }
    }
}

/** WorkDetailView.swift:1183–1232. Setting is the same stored switch as Reading queues. */
@Composable
internal fun WorkDetailSeriesForm(
    prompt: SeriesPreservationPrompt,
    enabled: Boolean,
    onAutoPreserveChange: (Boolean) -> Unit,
    onOnlyThisWork: () -> Unit,
    onPreserve: () -> Unit
) {
    DetailForm("Preserve Series?", onOnlyThisWork) {
        item { SettingsSection(footnote = null) {
            DetailFormText(prompt.message, primary = true)
            DetailFormText("Kudos saves the series one work at a time, with the usual pause between visits to AO3.")
        } }
        item { SettingsSection(footnote = null) {
            DetailToggleRow(prompt.autoPreserveLabel, enabled, change = onAutoPreserveChange)
            DetailFormText("Kudos saves a series automatically only when the first AO3 page shows the full series " +
                "and it has ${prompt.threshold} works or fewer.")
        } }
        item { SettingsSection(footnote = null) {
            SettingsActionRow("Preserve Entire Series", onPreserve, icon = Icons.Outlined.Layers)
            SubjectRowSeparator()
            SettingsActionRow("Only This Work", onOnlyThisWork, icon = Icons.Outlined.BookmarkBorder)
        } }
    }
}

/** ReadingQueues.swift:448–553. Membership controls here are deliberately additive. */
@Composable
internal fun WorkDetailQueueForm(
    queues: List<ReadingQueue>,
    selected: Set<String>,
    newName: String,
    working: Boolean,
    hasSeries: Boolean,
    includeSeries: Boolean,
    checkingPreview: Boolean,
    prompt: SeriesPreservationPrompt?,
    preserving: Boolean,
    result: SeriesPreservationResult?,
    onName: (String) -> Unit,
    onCreate: () -> Unit,
    onAdd: (ReadingQueue) -> Unit,
    onIncludeSeries: (Boolean) -> Unit,
    onPreserve: () -> Unit,
    onCancel: () -> Unit,
    onClose: () -> Unit,
    workingQueueId: String? = null
) {
    DetailForm("Add to Queue", onClose, actions = { FormToolbarAction("Done", true, onClose) }) {
        item { SettingsSection(footnote = null) {
            SubjectTextFieldRow("New queue", newName, "New queue", onName, fieldOnly = true, enabled = !working)
            SettingsActionRow("Add", onCreate, enabled = newName.trim().isNotEmpty() && !working)
        } }
        item { SettingsSection(label = "Queues",
            footnote = "A queue with Keep works offline turned on keeps its works downloaded for you.") {
            queues.forEachIndexed { index, queue ->
                if (index > 0) SubjectRowSeparator()
                SubjectFormRow(queue.displayName, onClick = { if (!working && !preserving) onAdd(queue) }, trailing = {
                    if (queue.id == workingQueueId) CircularProgressIndicator(color = LocalKudosTokens.current.scopePalette.accent,
                        trackColor = LocalKudosTokens.current.separator, modifier = Modifier.size(20.dp))
                    else if (queue.id in selected) Text("✓", color = LocalKudosTokens.current.scopePalette.accent, fontSize = 15.sp, lineHeight = 21.sp)
                })
            }
        } }
        if (hasSeries) item { SettingsSection(label = "Series",
            footnote = "Kudos adds series works only after you choose Add Series, one work at a time.") {
            DetailToggleRow("Also add works from this AO3 series", includeSeries, !preserving, onIncludeSeries)
            if (includeSeries) {
                if (checkingPreview) Row(Modifier.fillMaxWidth().padding(13.dp),
                    verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    CircularProgressIndicator(color = LocalKudosTokens.current.scopePalette.accent,
                        trackColor = LocalKudosTokens.current.separator, modifier = Modifier.size(20.dp))
                    Text("Checking series size…", color = LocalKudosTokens.current.secondaryInk,
                        fontSize = 13.sp, lineHeight = 18.sp, modifier = Modifier.weight(1f))
                } else if (prompt != null) DetailFormText(prompt.message)
                if (preserving) SubjectFormRow("Add Series to Selected Queues", trailing = {
                    CircularProgressIndicator(color = LocalKudosTokens.current.scopePalette.accent,
                        trackColor = LocalKudosTokens.current.separator, modifier = Modifier.size(20.dp))
                }) else SettingsActionRow("Add Series to Selected Queues", onPreserve, icon = Icons.Outlined.Layers,
                    enabled = selected.isNotEmpty() && !checkingPreview && !working)
                if (preserving) SettingsActionRow("Cancel Series Addition", onCancel, icon = Icons.Outlined.Cancel)
                if (result != null) DetailFormText(result.queueText(preserving))
            }
        } }
    }
}

/** WorkDetailView.swift:328–356. Token colours also cover Sepia and OLED. */
@Composable
internal fun WorkDetailSeriesStatus(progress: SeriesPreservationResult?, notice: String?, running: Boolean, onCancel: () -> Unit) {
    val tokens = LocalKudosTokens.current
    Column(Modifier.fillMaxWidth().padding(horizontal = SubjectMetrics.panelGutter)) {
        if (running && progress != null && progress.total > 0) LinearProgressIndicator(
            progress = { progress.completed.toFloat() / progress.total }, color = tokens.scopePalette.accent,
            trackColor = tokens.separator, modifier = Modifier.fillMaxWidth())
        if (notice != null) DetailFormText(notice)
        if (running) SettingsActionRow("Cancel Series Preservation", onCancel, icon = Icons.Outlined.Cancel)
    }
}
