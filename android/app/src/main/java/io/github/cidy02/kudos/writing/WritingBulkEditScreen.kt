package io.github.cidy02.kudos.writing

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.RemoveCircle
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import io.github.cidy02.kudos.app.DebugShotEffect
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.network.ao3.search.AO3TagAutocompleteRepository
import io.github.cidy02.kudos.network.ao3.writing.*
import io.github.cidy02.kudos.settings.SubjectTextFieldRow
import io.github.cidy02.kudos.ui.subject.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

internal data class BulkPicker(val title: String, val field: String, val mode: String)

@Composable
fun WritingBulkEditScreen(model: WritingBulkEditState, focus: String?, onBack: () -> Unit,
    onSaved: () -> Unit, autocomplete: AO3TagAutocompleteRepository? = null, settings: SettingsRepository? = null,
    saveScope: CoroutineScope? = null) {
    val state by model.state.collectAsState()
    val form = state.form
    val changes = state.changes
    val tokens = LocalKudosTokens.current
    val palette = tokens.scopePalette
    val scope = rememberCoroutineScope()
    // A started Save finishes and reaches the opener after Cancel (A64 F04): the opener's scope.
    val saveIn = saveScope ?: scope
    var picker by remember(model) { mutableStateOf<BulkPicker?>(null) }
    DebugShotEffect("bulk-editor", ready = form != null) { name ->
        picker = if (name == "bulknames") BulkPicker("Add to collections", "work[collections_to_add]", "names")
            else BulkPicker("Archive warnings", AO3WorkFormField.warnings, "tri")
    }

    val list = rememberLazyListState()
    LaunchedEffect(model) { model.load() }
    LaunchedEffect(state.saved) { if (state.saved && saveScope == null) onSaved() }
    DisposableEffect(model) { onDispose { model.close() } }
    LaunchedEffect(form, focus) {
        if (form != null) when (focus) {
            "Collections and gifts" -> list.scrollToItem(18)
            "Comments and visibility" -> list.scrollToItem(22)
        }
    }
    val selectedPicker = picker
    if (selectedPicker != null && form != null) {
        val kind = when (selectedPicker.field) {
            AO3WorkFormField.fandoms -> WritingTagKind.Fandom
            AO3WorkFormField.relationships -> WritingTagKind.Relationship
            AO3WorkFormField.characters -> WritingTagKind.Character
            AO3WorkFormField.additionalTags -> WritingTagKind.Freeform
            else -> null
        }
        if (kind != null) {
            val adding = selectedPicker.mode == "add"
            val values = (if (adding) changes.added else changes.removed)[selectedPicker.field].orEmpty()
            WritingTagsEditorScreen(kind, values, autocomplete, settings, onValues = { names -> model.change {
                if (adding) it.copy(added = it.added + (selectedPicker.field to names))
                else it.copy(removed = it.removed + (selectedPicker.field to names))
            } }, readValues = { (if (adding) model.state.value.changes.added else model.state.value.changes.removed)[selectedPicker.field].orEmpty() },
                recordScope = scope, onBack = { picker = null })
        } else BulkOptionsScreen(selectedPicker, bulkOptions(form, selectedPicker.field), changes,
            onChange = model::change, onBack = { picker = null })
        return
    }
    BackHandler(onBack = onBack)
    ProvidePushedShellChrome(hasSubjectHeader = true, hideTabBar = true, onBack = onBack,
        trailingContent = if (form == null) null else {
            {
                IconButton(enabled = !state.saving && !state.saved, onClick = { saveIn.launch { if (model.save() && saveScope != null) onSaved() } }) {
                    Icon(Icons.Default.Check, "Save", tint = palette.accent)
                }
                IconButton(onClick = onBack) { Icon(Icons.Default.Close, "Cancel", tint = tokens.secondaryInk) }
            }
        })
    state.saveError?.let { error ->
        AlertDialog(onDismissRequest = model::dismissError, containerColor = tokens.cardFill,
            title = { Text("AO3 could not save the change", color = tokens.primaryInk, lineHeight = 28.sp) },
            text = { Text(error, color = tokens.secondaryInk, lineHeight = 22.sp) }, confirmButton = {
                TextButton(onClick = model::dismissError) { Text("OK", color = palette.accent, lineHeight = 20.sp) }
            })
    }
    LazyColumn(Modifier.fillMaxSize().subjectScreenWash(palette), state = list, contentPadding = PaddingValues(bottom = 32.dp)) {
        item { BulkHeader(if (model.ids.size == 1) "Edit 1 work" else "Edit ${model.ids.size} works", form?.titles?.joinToString(", ")) }
        if (form == null) item {
            Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 18.dp).writingSuggestionPanel(true, true)) {
                if (state.failure != null) {
                    Text(state.failure!!, color = tokens.secondaryInk, fontSize = 14.sp, lineHeight = 20.sp, modifier = Modifier.padding(14.dp))
                    SubjectFormRow("Try Again", onClick = { scope.launch { model.load(retry = true) } })
                } else Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(color = palette.accent, trackColor = tokens.separator, modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                    Text("Loading ${model.ids.size} works…", color = tokens.secondaryInk, fontSize = 14.sp, lineHeight = 20.sp, modifier = Modifier.padding(start = 10.dp))
                }
            }
        } else {
            item { Text("Your changes apply to every selected work. Use the separate Add and Remove groups for tags. Anything you leave alone stays unchanged.",
                color = tokens.secondaryInk, fontSize = 12.5.sp, lineHeight = 18.sp,
                modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter + 14.dp).padding(top = 14.dp)) }
            for ((mode, title) in listOf("add" to "Tags to add", "remove" to "Tags to remove")) {
                item { WorkFormSection(title) }
                for ((index, entry) in bulkTagFields.withIndex()) item {
                    val values = (if (mode == "add") changes.added else changes.removed)[entry.second].orEmpty()
                    BulkRow(entry.first, workFormCount(values), index, 4, !state.saving) { picker = BulkPicker(entry.first, entry.second, mode) }
                }
            }
            item { WorkFormSection("Change on all") }
            for ((index, entry) in listOf("Rating" to AO3WorkFormField.rating, "Archive warnings" to AO3WorkFormField.warnings,
                "Categories" to AO3WorkFormField.categories, "Language" to AO3WorkFormField.languageID).withIndex()) item {
                val tri = index == 1 || index == 2
                val options = form.options[entry.second].orEmpty()
                val adds = changes.added[entry.second].orEmpty().size; val removes = changes.removed[entry.second].orEmpty().size
                val value = if (tri) if (adds + removes == 0) "Leave as is" else "+$adds, -$removes"
                    else options.firstOrNull { it.value == changes.scalars[entry.second] }?.title ?: "Leave as is"
                BulkRow(entry.first, value, index, 4, !state.saving && (!tri || options.isNotEmpty()), choice = !tri) {
                    picker = BulkPicker(entry.first, entry.second, if (tri) "tri" else "scalar")
                }
            }
            item { WorkFormFootnote("Changing the rating or language replaces that value on every selected work. Warnings and categories are added or removed instead.") }
            item { WorkFormSection("Collections and gifts") }
            item { BulkRow("Add to collections", workFormCount(changes.collectionsToAdd), 0, 3, !state.saving) {
                picker = BulkPicker("Add to collections", "work[collections_to_add]", "names")
            } }
            item { BulkRow("Remove from collections", workFormCount(changes.collectionsToRemove), 1, 3,
                !state.saving && form.options["work[collections_to_remove][]"].orEmpty().isNotEmpty()) {
                picker = BulkPicker("Remove from collections", "work[collections_to_remove][]", "multi")
            } }
            item { BulkRow("Gift recipients", "Per work", 2, 3, false) {} }
            item { WorkFormSection("Comments and visibility") }
            for ((index, entry) in listOf("Only show to registered users" to AO3WorkFormField.restricted,
                "Enable comment moderation" to AO3WorkFormField.moderatedCommenting, "Who can comment" to AO3WorkFormField.commentPermissions).withIndex()) item {
                BulkRow(entry.first, bulkOptions(form, entry.second).firstOrNull { it.value == changes.scalars[entry.second] }?.title ?: "Leave as is",
                    index, 3, !state.saving, choice = true) { picker = BulkPicker(entry.first, entry.second, "scalar") }
            }
            item { WorkFormSection("Creators") }
            item {
                Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter).writingSuggestionPanel(true, false)) {
                    SubjectTextFieldRow("Add co-creators", changes.pseudsToAdd, "Pseud", { text -> model.change { it.copy(pseudsToAdd = text) } },
                        enabled = !state.saving, autocorrect = false)
                    SubjectRowSeparator()
                }
            }
            item {
                Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter).writingSuggestionPanel(false, true)) {
                    WorkFormToggle("Remove me as a co-creator", changes.removesSelf, enabled = !state.saving) { checked -> model.change { it.copy(removesSelf = checked) } }
                }
            }
            item { WorkFormFootnote("AO3 sends each co-creator an invitation. Their work doesn't change until they accept it.") }
        }
    }
}

private val bulkTagFields = listOf("Fandoms" to AO3WorkFormField.fandoms, "Relationships" to AO3WorkFormField.relationships,
    "Characters" to AO3WorkFormField.characters, "Additional tags" to AO3WorkFormField.additionalTags)

@Composable
private fun BulkHeader(title: String, subtitle: String? = null) {
    Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars)); Spacer(Modifier.height(76.dp))
    SubjectHeaderBlock(kicker = "AO3 Account", title = title, subtitle = subtitle, palette = LocalKudosTokens.current.scopePalette, gutter = SubjectMetrics.accountGutter)
}

@Composable
private fun BulkRow(label: String, value: String, index: Int, total: Int, enabled: Boolean, spokenValue: String? = null, mark: String? = null,
    /** iOS draws this row as `WritingChoiceRow`: the value in the accent with its picker mark. */
    choice: Boolean = false, click: () -> Unit) {
    val tokens = LocalKudosTokens.current
    Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter).writingSuggestionPanel(index == 0, index == total - 1).alpha(if (enabled) 1f else 0.55f)) {
        if (mark != null) Row(
            Modifier.fillMaxWidth().clickable(enabled = enabled, onClick = click)
                .semantics(mergeDescendants = true) { stateDescription = spokenValue ?: value }
                .padding(horizontal = 13.dp, vertical = 11.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Icon(when (mark) { "Add" -> Icons.Filled.AddCircle; "Remove" -> Icons.Filled.RemoveCircle; else -> Icons.Outlined.Circle },
                null, tint = tokens.secondaryInk, modifier = Modifier.testTag("Bulk option mark"))
            Text(label, Modifier.weight(1f), color = tokens.primaryInk, fontSize = 14.5.sp,
                textDecoration = if (mark == "Remove") TextDecoration.LineThrough else TextDecoration.None)
            Text(value, color = tokens.secondaryInk, fontSize = 13.sp)
        } else if (choice) SubjectFormRow(label, value = value, showsChoice = true, onClick = if (enabled) click else null)
        else SubjectFormRow(label, showsDisclosure = enabled, onClick = if (enabled) click else null,
            trailing = { Text(value, color = tokens.secondaryInk, fontSize = 13.sp, lineHeight = 18.sp, modifier = Modifier.widthIn(max = 160.dp)) })
        if (index < total - 1) SubjectRowSeparator()
    }
}

@Composable
internal fun BulkOptionsScreen(picker: BulkPicker, options: List<AO3FormOption>, changes: AO3BulkEditChanges,
    onChange: ((AO3BulkEditChanges) -> AO3BulkEditChanges) -> Unit, onBack: () -> Unit) {
    val tokens = LocalKudosTokens.current
    val palette = tokens.scopePalette
    var entry by remember(picker) { mutableStateOf("") }
    BackHandler(onBack = onBack)
    // iOS's tag-state page (`BulkTagStatePicker`) is a plain list; only its names page washes.
    val flat = picker.mode == "tri"
    ProvidePushedShellChrome(hasSubjectHeader = true, hideTabBar = true, onBack = onBack,
        pageBackground = if (flat) tokens.background else null)
    LazyColumn(Modifier.fillMaxSize().then(if (flat) Modifier.background(tokens.background) else Modifier.subjectScreenWash(palette)),
        contentPadding = PaddingValues(bottom = 32.dp)) {
        item { BulkHeader(picker.title) }
        val shown = if (picker.mode == "scalar") listOf(AO3FormOption("", "Leave as is")) + options.filter { it.value.isNotEmpty() }
            else if (picker.mode == "names") changes.collectionsToAdd.map { AO3FormOption(it, it) } else options
        if (picker.mode == "names" && shown.isNotEmpty()) item { WorkFormSection("Added") }
        itemsIndexed(shown) { index, option ->
            val value = when (picker.mode) {
                "tri" -> if (option.value in changes.added[picker.field].orEmpty()) "Add" else if (option.value in changes.removed[picker.field].orEmpty()) "Remove" else ""
                "scalar" -> if (changes.scalars[picker.field].orEmpty() == option.value) "Selected" else ""
                "multi" -> if (option.value in changes.collectionsToRemove) "Selected" else ""
                else -> "Remove"
            }
            BulkRow(option.title, value, index, shown.size, true,
                spokenValue = if (picker.mode == "tri" && value.isEmpty()) "Unchanged" else null,
                mark = if (picker.mode == "tri") value else if (picker.mode == "names") "Remove" else null) {
                onChange { old -> when (picker.mode) {
                    "scalar" -> old.copy(scalars = old.scalars + (picker.field to option.value))
                    "multi" -> old.copy(collectionsToRemove = if (option.value in old.collectionsToRemove) old.collectionsToRemove - option.value else old.collectionsToRemove + option.value)
                    "names" -> old.copy(collectionsToAdd = old.collectionsToAdd - option.value)
                    else -> {
                        val add = old.added[picker.field].orEmpty(); val remove = old.removed[picker.field].orEmpty()
                        old.copy(added = old.added + (picker.field to if (option.value !in add && option.value !in remove) add + option.value else add - option.value),
                            removed = old.removed + (picker.field to if (option.value in add) remove + option.value else remove - option.value))
                    }
                } }
                if (picker.mode == "scalar") onBack()
            }
        }
        if (picker.mode == "names") {
            item {
                Row(Modifier.padding(horizontal = SubjectMetrics.accountGutter).writingSuggestionPanel(true, true)
                    .padding(end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.weight(1f)) {
                        SubjectTextFieldRow("Collection name", entry, "Collection name", { entry = it },
                            autocorrect = false, fieldOnly = true)
                    }
                    TextButton(onClick = {
                        val name = trimWritingTag(entry)
                        onChange { if (name in it.collectionsToAdd) it else it.copy(collectionsToAdd = it.collectionsToAdd + name) }
                        entry = ""
                    }, enabled = trimWritingTag(entry).isNotEmpty(),
                        colors = androidx.compose.material3.ButtonDefaults.textButtonColors(contentColor = palette.accent)) { Text("Add") }
                }
            }
            item { WorkFormFootnote("Enter the collection name exactly as it appears on AO3. If AO3 doesn't recognize it, you will see that when you save.") }
        }
        if (picker.mode == "tri") item { WorkFormFootnote("Tap an option once to add it to every selected work, twice to remove it, or three times to leave it unchanged.") }
    }
}

/** iOS's two literal On/Off choices; all other choices come from the served form. */
private fun bulkOptions(form: AO3BulkEditForm, field: String): List<AO3FormOption> =
    if (field == AO3WorkFormField.restricted || field == AO3WorkFormField.moderatedCommenting)
        listOf(AO3FormOption("1", "On"), AO3FormOption("0", "Off"))
    else form.options[field].orEmpty()
