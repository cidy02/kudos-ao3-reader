package io.github.cidy02.kudos.writing

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.network.ao3.search.AO3TagAutocompleteRepository
import io.github.cidy02.kudos.network.ao3.writing.trimWritingTag
import io.github.cidy02.kudos.ui.subject.*
import kotlinx.coroutines.launch

/** Separate posted-work tags page; the work text never enters this editor. */
@Composable
internal fun WritingEditTagsScreen(
    model: WritingWorkFormState,
    workTitle: String,
    autocompleteRepository: AO3TagAutocompleteRepository?,
    settingsRepository: SettingsRepository?,
    onBack: () -> Unit,
    onSave: () -> Unit
) {
    val state by model.state.collectAsState()
    val form = state.form
    val tokens = LocalKudosTokens.current
    val palette = tokens.scopePalette
    val scope = rememberCoroutineScope()
    var addingKind by remember(model) { mutableStateOf<WritingTagKind?>(null) }
    LaunchedEffect(model) { model.load() }
    DisposableEffect(model) {
        // iOS's save Task survives Back: its owner still needs the confirmed tag refresh.
        onDispose { if (!model.state.value.saving) model.close() }
    }
    val kind = addingKind
    if (kind != null && form != null) {
        WritingTagsEditorScreen(kind, kind.values(form), autocompleteRepository, settingsRepository,
            onValues = { model.writingTags(kind, it) },
            readValues = { model.state.value.form?.let(kind::values).orEmpty() },
            recordScope = scope, onBack = { addingKind = null })
        return
    }
    BackHandler(onBack = onBack)
    val save: (@Composable RowScope.() -> Unit)? = if (form == null) null else {
        {
            TextButton(enabled = !state.saving && !state.saved, onClick = onSave,
                colors = ButtonDefaults.textButtonColors(contentColor = palette.accent, disabledContentColor = tokens.tertiaryInk)) {
                Text("Save", fontSize = 15.sp, lineHeight = 21.sp)
            }
        }
    }
    ProvidePushedShellChrome(hasSubjectHeader = true, hideTabBar = true, onBack = onBack, trailingContent = save)
    state.saveError?.let { message ->
        AlertDialog(onDismissRequest = model::dismissSaveError, containerColor = tokens.cardFill,
            titleContentColor = tokens.primaryInk, textContentColor = tokens.secondaryInk,
            title = { Text("AO3 could not save the change", lineHeight = 28.sp) },
            text = { Text(message, lineHeight = 22.sp) }, confirmButton = {
                TextButton(onClick = model::dismissSaveError) { Text("OK", color = palette.accent, lineHeight = 20.sp) }
            })
    }
    BoxWithConstraints(Modifier.fillMaxSize().subjectScreenWash(palette)) {
        val chipWidth = (maxWidth - SubjectMetrics.accountGutter * 2 - 28.dp).coerceAtLeast(0.dp)
        val chipExtra = with(androidx.compose.ui.platform.LocalDensity.current) { 22.dp + 6.dp + 11.sp.toDp() + 1.dp }
        val chipRows = WritingTagKind.entries.associateWith { tagKind ->
            // A chip here is its words, its padding and a small mark inside it. It was laid out
            // at the width of the tag editor's chip, which has a 48 dp button beside it: every
            // chip was 38 dp too wide, blank past its "×", and "Add" was pushed to a row of its
            // own. The mark is sized in sp, so its share grows with the reader's text size.
            writingChipRows(form?.let(tagKind::values).orEmpty() + "Add", chipWidth, chosen = true, extra = chipExtra)
        }
        LazyColumn(Modifier.fillMaxSize().testTag("Writing edit tags"), contentPadding = PaddingValues(bottom = 24.dp)) {
            item {
                Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
                Spacer(Modifier.height(76.dp))
                SubjectHeaderBlock(kicker = "AO3 Account", title = "Edit tags",
                    subtitle = listOf(trimWritingTag(workTitle), "changes here do not touch the text")
                        .filter(String::isNotEmpty).joinToString(" · "),
                    palette = palette, gutter = SubjectMetrics.accountGutter)
            }
            if (form == null) item {
                Column(Modifier.fillMaxWidth().padding(top = 18.dp).padding(horizontal = SubjectMetrics.accountGutter),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    val failure = state.failure
                    if (failure != null) {
                        Text(failure, color = tokens.secondaryInk, fontSize = 14.sp, lineHeight = 20.sp)
                        TextButton(onClick = { scope.launch { model.load(retry = true) } },
                            colors = ButtonDefaults.textButtonColors(contentColor = palette.accent)) {
                            Text("Try Again", color = palette.accent, fontSize = 14.sp, lineHeight = 20.sp)
                        }
                    } else Row(verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(color = palette.accent, trackColor = tokens.separator,
                            modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                        Text("Loading tags…", color = tokens.secondaryInk, fontSize = 14.sp, lineHeight = 20.sp,
                            modifier = Modifier.padding(start = 10.dp))
                    }
                }
            } else {
                item { WorkFormSection("Rating") }
                itemsIndexed(form.ratingOptions) { index, option ->
                    Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter)
                        .writingSuggestionPanel(index == 0, index == form.ratingOptions.lastIndex)) {
                        SubjectFormRow(option.title, onClick = { model.choice(WorkFormChoice.Rating, option.value) }, trailing = {
                            if (form.rating == option.value) Icon(Icons.Default.Check, "Selected",
                                tint = palette.accent, modifier = Modifier.size(18.dp))
                        })
                        if (index < form.ratingOptions.lastIndex) SubjectRowSeparator()
                    }
                }
                item { WorkFormSection("Archive warnings") }
                itemsIndexed(form.warningOptions) { index, option ->
                    Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter)
                        .writingSuggestionPanel(index == 0, index == form.warningOptions.lastIndex)) {
                        SubjectFormRow(option.title, onClick = { model.toggleTag(WorkFormTags.Warnings, option.value) }, trailing = {
                            if (option.value in form.warnings) Icon(Icons.Default.Check, "Selected",
                                tint = palette.accent, modifier = Modifier.size(18.dp))
                        })
                        if (index < form.warningOptions.lastIndex) SubjectRowSeparator()
                    }
                }
                item { WorkFormFootnote("Choose at least one warning. Choose the first option if you don't want to name a specific warning.") }
                item { WorkFormSection("Categories") }
                itemsIndexed(form.categoryOptions) { index, option ->
                    Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter)
                        .writingSuggestionPanel(index == 0, index == form.categoryOptions.lastIndex)) {
                        WorkFormToggle(option.title, option.value in form.categories) {
                            model.toggleTag(WorkFormTags.Categories, option.value)
                        }
                        if (index < form.categoryOptions.lastIndex) SubjectRowSeparator()
                    }
                }
                item { WorkFormSection("Tags") }
                for ((kindIndex, tagKind) in WritingTagKind.entries.withIndex()) {
                    val values = tagKind.values(form)
                    item {
                        Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter).writingSuggestionPanel(kindIndex == 0, false)) {
                            if (kindIndex > 0) SubjectRowSeparator()
                            SubjectFormRow(tagKind.title + if (tagKind == WritingTagKind.Fandom) " ∗" else "", trailing = {
                                Text(workFormCount(values), color = tokens.secondaryInk, fontSize = 13.sp, lineHeight = 18.sp)
                            })
                        }
                    }
                    val rows = chipRows.getValue(tagKind)
                    itemsIndexed(rows) { rowIndex, row ->
                        val lastRow = rowIndex == rows.lastIndex
                        Row(Modifier.padding(horizontal = SubjectMetrics.accountGutter)
                            .writingSuggestionPanel(false, lastRow && kindIndex == WritingTagKind.entries.lastIndex)
                            .fillMaxWidth().padding(horizontal = 14.dp).padding(bottom = if (lastRow) 12.dp else 0.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            // The chip is drawn at its own height, as iOS draws it, inside the 48 dp
                            // it is touched by. It was drawn 48 dp tall.
                            row.forEachIndexed { chipIndex, chip ->
                                if (lastRow && chipIndex == row.lastIndex) {
                                    Box(Modifier.width(chip.width).heightIn(min = 48.dp)
                                        .clickable(role = Role.Button) { addingKind = tagKind }
                                        .semantics(mergeDescendants = true) { contentDescription = "Add ${tagKind.title}" },
                                        contentAlignment = Alignment.CenterStart) {
                                        SubjectChip("Add", style = SubjectChipStyle.Dashed, leadingIcon = Icons.Default.Add,
                                            palette = palette, maxLines = Int.MAX_VALUE)
                                    }
                                } else {
                                    Box(Modifier.width(chip.width).heightIn(min = 48.dp)
                                        .clickable(role = Role.Button) {
                                            // The list as it is now, not as it was drawn: two removes
                                            // before a redraw used to bring the first tag back.
                                            val now = model.state.value.form?.let(tagKind::values) ?: values
                                            model.writingTags(tagKind, now.filterNot { it == chip.name })
                                        }.semantics(mergeDescendants = true) { contentDescription = "Remove ${chip.name}" },
                                        contentAlignment = Alignment.CenterStart) {
                                        SubjectChip(chip.name, trailingIcon = Icons.Default.Close, palette = palette,
                                            maxLines = Int.MAX_VALUE)
                                    }
                                }
                            }
                        }
                    }
                }
                item { WorkFormFootnote("As you type, AO3 suggests its canonical tags first. You can still post a tag that isn't canonical, and removing one here doesn't delete it from AO3.") }
            }
        }
    }
}
