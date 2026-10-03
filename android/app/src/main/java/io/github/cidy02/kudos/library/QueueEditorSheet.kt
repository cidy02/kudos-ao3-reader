package io.github.cidy02.kudos.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.core.model.Tag
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectChip
import io.github.cidy02.kudos.ui.subject.SubjectChipStyle
import io.github.cidy02.kudos.ui.subject.SubjectFieldLabel
import io.github.cidy02.kudos.ui.subject.SubjectHueSwatchRow
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.SubjectToggle
import io.github.cidy02.kudos.ui.subject.parseStoredColor
import io.github.cidy02.kudos.ui.subject.subjectPanel
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import kotlinx.coroutines.launch

/**
 * New Queue and Edit Queue are one sheet (T-335). The wash follows the colour
 * the reader is picking (T-350). A custom colour is stored as `colorHex`.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun QueueEditorSheet(
    repository: ReadingQueueRepository,
    existing: ReadingQueue?,
    onDismiss: () -> Unit,
    onSaved: (ReadingQueue) -> Unit
) {
    val tokens = LocalKudosTokens.current
    val scope = rememberCoroutineScope()
    val editing = existing != null && existing.kindRaw == ReadingQueueKind.CUSTOM
    var name by remember(existing?.id) { mutableStateOf(if (editing) existing!!.name else "") }
    var hue by remember(existing?.id) { mutableStateOf(existing?.hue) }
    var colorHex by remember(existing?.id) { mutableStateOf(existing?.colorHex) }
    var notes by remember(existing?.id) { mutableStateOf(existing?.notes.orEmpty()) }
    var keep by remember(existing?.id) { mutableStateOf(existing?.keepsWorksOffline != false) }
    var tags by remember(existing?.id) { mutableStateOf<List<String>>(emptyList()) }
    var knownTags by remember { mutableStateOf<List<Tag>>(emptyList()) }
    var newTag by remember { mutableStateOf("") }
    var seed by remember(existing?.id) { mutableStateOf(false) }
    var seedCount by remember(existing?.id) { mutableIntStateOf(0) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(existing?.id) {
        knownTags = runCatching { repository.allTags() }.getOrDefault(emptyList())
        if (existing != null) {
            tags = runCatching { repository.tagsForQueue(existing.id).map { it.name } }.getOrDefault(emptyList())
        }
        if (!editing) {
            seedCount = runCatching { repository.savedForLaterSeedCount() }.getOrDefault(0)
        }
    }

    val palette = queueDraftPalette(tokens.theme, tokens.scopePalette, hue, colorHex)
    val canSave = name.isNotBlank() && !saving

    Dialog(
        onDismissRequest = { if (!saving) onDismiss() },
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .subjectScreenWash(palette)
                .windowInsetsPadding(WindowInsets.safeDrawing)
                .windowInsetsPadding(WindowInsets.ime)
        ) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                TextButton(onClick = onDismiss, enabled = !saving) { Text("Cancel") }
                Text(
                    text = if (editing) "Edit queue" else "New queue",
                    modifier = Modifier.weight(1f),
                    color = tokens.primaryInk,
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold
                )
                TextButton(
                    onClick = {
                        saving = true
                        scope.launch {
                            val saved = runCatching {
                                if (editing) {
                                    repository.updateQueue(
                                        existing!!.id,
                                        QueueEdit(
                                            name = name,
                                            hue = hue,
                                            colorHex = colorHex,
                                            keepsWorksOffline = keep,
                                            notes = notes,
                                            tagNames = tags
                                        )
                                    )
                                    repository.getQueue(existing.id)
                                } else {
                                    repository.createQueue(
                                        name = name,
                                        hue = hue,
                                        colorHex = colorHex,
                                        keepsWorksOffline = keep,
                                        notes = notes.ifBlank { null },
                                        tagNames = tags,
                                        seedFromSavedForLater = seed
                                    )
                                }
                            }
                            saving = false
                            saved.getOrNull()?.let(onSaved) ?: run {
                                error = saved.exceptionOrNull()?.message ?: "Could not save this queue."
                            }
                        }
                    },
                    enabled = canSave
                ) {
                    Text(
                        text = if (editing) "Save" else "Create",
                        color = if (canSave) palette.accent else tokens.tertiaryInk
                    )
                }
            }
            Column(
                Modifier
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp)
                    .padding(bottom = 28.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                SubjectFieldLabel("Name", Modifier.padding(top = 12.dp))
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("Case fic pile") },
                    singleLine = true
                )
                SubjectFieldLabel("Colour", Modifier.padding(top = 14.dp))
                SubjectHueSwatchRow(hue = hue, colorHex = colorHex, onChange = { nextHue, nextHex ->
                    hue = nextHue
                    colorHex = nextHex
                })
                FormFootnote(
                    if (hue == null && colorHex == null) {
                        "Kudos picks a colour from the queue name. Renaming it may change the colour."
                    } else {
                        "Your chosen colour stays the same if you rename the queue."
                    }
                )
                SubjectFieldLabel("Tags", Modifier.padding(top = 14.dp))
                TagToggleRow(knownTags, tags, palette) { tags = it }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = newTag,
                        onValueChange = { newTag = it },
                        modifier = Modifier.weight(1f),
                        placeholder = { Text("New tag") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                        keyboardActions = KeyboardActions(onDone = {
                            val trimmed = newTag.trim()
                            if (trimmed.isNotEmpty() && tags.none { it.equals(trimmed, ignoreCase = true) }) {
                                tags = tags + trimmed
                            }
                            newTag = ""
                        })
                    )
                    TextButton(
                        onClick = {
                            val trimmed = newTag.trim()
                            if (trimmed.isNotEmpty() && tags.none { it.equals(trimmed, ignoreCase = true) }) {
                                tags = tags + trimmed
                            }
                            newTag = ""
                        },
                        enabled = newTag.isNotBlank()
                    ) { Text("+ New tag", color = palette.accent) }
                }
                if (tags.isNotEmpty()) {
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        tags.forEach { tag ->
                            SubjectChip(
                                text = tag,
                                style = SubjectChipStyle.Tinted,
                                palette = palette
                            )
                        }
                    }
                }
                FormFootnote("A tag you use here is the same tag on your works.")
                SubjectFieldLabel("Offline", Modifier.padding(top = 14.dp))
                Row(
                    Modifier.fillMaxWidth().subjectPanel().padding(horizontal = 14.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("Keep works offline", modifier = Modifier.weight(1f), color = tokens.primaryInk, fontSize = 15.sp)
                    SubjectToggle(
                        checked = keep,
                        onCheckedChange = { keep = it },
                        accent = palette.accent,
                        contentDescription = "Keep works offline"
                    )
                }
                FormFootnote(
                    "When this is on, every work you add is downloaded for offline reading. " +
                        "When it is off, the queue keeps only your list and uses no extra storage."
                )
                SubjectFieldLabel("Description", Modifier.padding(top = 14.dp))
                OutlinedTextField(
                    value = notes,
                    onValueChange = { notes = it },
                    modifier = Modifier.fillMaxWidth(),
                    minLines = 3
                )
                if (!editing) {
                    SubjectFieldLabel("Start from", Modifier.padding(top = 14.dp))
                    Column(Modifier.fillMaxWidth().subjectPanel()) {
                        SeedRow(
                            label = "Empty",
                            subtitle = null,
                            selected = !seed,
                            enabled = true,
                            onClick = { seed = false }
                        )
                        SeedRow(
                            label = "Saved for Later",
                            subtitle = if (seedCount == 0) {
                                "You have no works in Saved for Later to copy."
                            } else {
                                "Copy $seedCount works. They stay in Saved for Later."
                            },
                            selected = seed,
                            enabled = seedCount > 0,
                            onClick = { seed = true }
                        )
                    }
                }
            }
        }
    }
    if (error != null) {
        AlertDialog(
            onDismissRequest = { error = null },
            title = { Text("Could not save") },
            text = { Text(error.orEmpty()) },
            confirmButton = { TextButton(onClick = { error = null }) { Text("OK") } }
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun TagToggleRow(
    known: List<Tag>,
    selected: List<String>,
    palette: SubjectPalette,
    onChange: (List<String>) -> Unit
) {
    if (known.isEmpty()) return
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        known.forEach { tag ->
            val on = selected.any { it.equals(tag.name, ignoreCase = true) }
            TextButton(onClick = {
                onChange(
                    if (on) selected.filterNot { it.equals(tag.name, ignoreCase = true) }
                    else selected + tag.name
                )
            }) {
                SubjectChip(
                    text = tag.name,
                    style = if (on) SubjectChipStyle.Tinted else SubjectChipStyle.Neutral,
                    palette = palette
                )
            }
        }
    }
}

@Composable
private fun SeedRow(
    label: String,
    subtitle: String?,
    selected: Boolean,
    enabled: Boolean,
    onClick: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        RadioButton(selected = selected, onClick = onClick, enabled = enabled)
        Column(Modifier.weight(1f)) {
            Text(label, color = if (enabled) tokens.primaryInk else tokens.tertiaryInk, fontSize = 15.sp)
            if (subtitle != null) {
                Text(subtitle, color = tokens.secondaryInk, fontSize = 12.sp)
            }
        }
    }
}

@Composable
internal fun FormFootnote(text: String) {
    Text(
        text = text,
        color = LocalKudosTokens.current.secondaryInk,
        fontSize = 11.5.sp,
        modifier = Modifier.padding(horizontal = 4.dp)
    )
}

private fun queueDraftPalette(
    theme: io.github.cidy02.kudos.ui.subject.ReaderTheme,
    fallback: SubjectPalette,
    hue: Double?,
    colorHex: String?
): SubjectPalette {
    val picked = colorHex?.let(::parseStoredColor)
    if (picked != null) return SubjectPalette.fromColor(picked, theme)
    if (hue != null) return SubjectPalette.fromHue(hue, theme)
    return fallback
}
