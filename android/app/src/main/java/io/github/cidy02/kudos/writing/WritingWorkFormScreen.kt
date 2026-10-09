package io.github.cidy02.kudos.writing

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle as ComposeTextStyle
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.core.strippingHtml
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.network.ao3.search.AO3TagAutocompleteRepository
import io.github.cidy02.kudos.network.ao3.writing.*
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.settings.SettingsPanel
import io.github.cidy02.kudos.settings.SubjectTextFieldRow
import io.github.cidy02.kudos.ui.subject.*
import io.github.cidy02.kudos.ui.theme.SuccessGreen
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.format.TextStyle
import java.util.Locale

/** A user-opened AO3 work form; edits stay here until AO3 confirms Save. */
@Composable
fun WritingWorkFormScreen(
    workID: Long?,
    repository: AO3WorkFormRepository,
    auth: AO3AuthRepository,
    onClose: () -> Unit,
    autocompleteRepository: AO3TagAutocompleteRepository? = null,
    settingsRepository: SettingsRepository? = null,
    writeRepository: AO3WriteRepository,
    onSaved: () -> Unit = onClose,
    seriesRepository: AO3SeriesFormRepository? = null
) {
    val generation by auth.generation.collectAsState()
    val accountState by auth.state.collectAsState()
    var savingModel by remember(workID, repository, auth) { mutableStateOf<WritingWorkFormState?>(null) }
    val currentModel = remember(workID, repository, auth, generation, accountState.isSignedIn) {
        WritingWorkFormState(workID, repository, auth, writes = writeRepository)
    }
    // Once Save is tapped its exact draft survives even a session failure. It can never be
    // sent by the replacement session; the opening generation remains the write fence.
    val model = savingModel ?: currentModel
    LaunchedEffect(model) { model.load() }
    DisposableEffect(model) { onDispose { model.close() } }
    WritingWorkFormContent(model, model.account, if (workID == null) "New work" else "Edit work", onClose,
        autocompleteRepository, settingsRepository, onSaved = onSaved, onSaving = { savingModel = model },
        seriesRepository = seriesRepository, seriesWrites = writeRepository)
}

@Composable
internal fun WritingWorkFormContent(model: WritingWorkFormState, account: String, loadingTitle: String, onClose: () -> Unit,
    autocompleteRepository: AO3TagAutocompleteRepository? = null, settingsRepository: SettingsRepository? = null,
    onSaved: () -> Unit = onClose, onSaving: () -> Unit = {}, seriesRepository: AO3SeriesFormRepository? = null, seriesWrites: AO3WriteRepository? = null) {
    val state by model.state.collectAsState()
    val form = state.form
    val tokens = LocalKudosTokens.current
    val palette = tokens.scopePalette
    val list = rememberLazyListState()
    val scope = rememberCoroutineScope()
    LaunchedEffect(state.saved) { if (state.saved) onSaved() }
    val preview = state.preview
    if (preview != null && form != null) {
        WritingAO3PreviewScreen(preview, form.subtitle(), if (form.isPosted) "Update" else "Post work",
            busy = state.saving, error = state.saveError, dismissError = model::dismissSaveError,
            onBack = model::closePreview, onPost = { onSaving(); scope.launch { if (form.isPosted) model.save() else model.post() } },
            confirmation = if (form.isPosted) null else workPostConfirmation(form.missingRequiredFields()),
            screenTag = "Writing work preview")
        return
    }
    var confirmingPost by remember(model) { mutableStateOf(false) }
    var editing by remember(model) { mutableStateOf<WorkFormText?>(null) }
    var association by remember(model) { mutableStateOf<WorkAssociation?>(null) }
    var writingTags by remember(model) { mutableStateOf<WritingTagKind?>(null) }
    var choosingTags by remember(model) { mutableStateOf<WorkFormTags?>(null) }
    var choosing by remember(model) { mutableStateOf<WorkFormChoice?>(null) }
    var dating by remember(model) { mutableStateOf(false) }
    var chapterModel by remember(model) { mutableStateOf<WritingChapterFormState?>(null) }
    var viewingChapters by remember(model) { mutableStateOf(false) }
    var editingPostedTags by remember(model) { mutableStateOf<WritingWorkFormState?>(null) }
    LaunchedEffect(state.publicationNeedRefresh) { if (state.publicationNeedRefresh) model.refreshPublication() }
    LaunchedEffect(state.tagsNeedRefresh) { if (state.tagsNeedRefresh) model.refreshTags() }
    editingPostedTags?.let { tagsModel ->
        WritingEditTagsScreen(tagsModel, form?.title.orEmpty(), autocompleteRepository, settingsRepository,
            onBack = { editingPostedTags = null }, onSave = {
                // The work form owns this save, so Back during a dispatched POST cannot leave
                // its old tags ready to overwrite a confirmed change (iOS's Task also survives Back).
                scope.launch {
                    try {
                        tagsModel.save()
                        if (tagsModel.state.value.saved) {
                            model.tagsSaved()
                            if (editingPostedTags === tagsModel) editingPostedTags = null
                        }
                    } finally {
                        if (editingPostedTags !== tagsModel) tagsModel.close()
                    }
                }
            })
        return
    }
    var reorder by remember(model) { mutableStateOf<Pair<Long, String>?>(null) }
    val onReorderSeries: ((Long, String) -> Unit)? = if (seriesRepository == null || seriesWrites == null) null
        else ({ id, title -> reorder = id to title })
    val order = reorder
    if (order != null && seriesRepository != null && seriesWrites != null) {
        WritingSeriesScreen(order.first, order.second, seriesRepository, seriesWrites,
            onBack = { reorder = null }, reorderOnly = true)
        return
    }
    chapterModel?.let { chapter ->
        WritingChapterFormScreen(chapter, form?.title.orEmpty(), operationScope = scope,
            onSaved = { model.chapterSaved(); scope.launch { model.refreshPublication() } },
            onBack = { if (!chapter.state.value.busy) chapter.close(); if (chapterModel === chapter) chapterModel = null })
        return
    }
    val field = editing
    if (field != null && form != null) {
        WritingTextEditorScreen(field.text(form), field.title, account, form.recoveryTarget(), field.field,
            onCheckpoint = { model.checkpoint(field, it) },
            onDone = { model.checkpoint(field, it); editing = null }, onBack = { editing = null })
        return
    }
    val writingKind = writingTags
    if (writingKind != null && form != null) {
        WritingTagsEditorScreen(writingKind, writingKind.values(form), autocompleteRepository, settingsRepository,
            onValues = { model.writingTags(writingKind, it) },
            readValues = { model.state.value.form?.let(writingKind::values).orEmpty() },
            recordScope = scope, onBack = { writingTags = null })
        return
    }
    val associationKind = association
    if (associationKind != null && form != null) {
        WritingAssociationPicker(associationKind, form, model, autocompleteRepository, onReorderSeries) { association = null }
        return
    }
    if (viewingChapters && form?.isPosted == true && form.workID != null) {
        WritingChaptersScreen(form.title, model::loadChapters,
            openChapter = { chapter, count -> onSaving(); model.chapterModel(chapter.chapterId, count) },
            operationScope = scope,
            onSaved = { model.chapterSaved(); scope.launch { model.refreshPublication() } },
            onBack = { viewingChapters = false })
        return
    }
    val tags = choosingTags
    if (tags != null && form != null) {
        WorkFormTagChoices(form, tags, model::toggleTag) { choosingTags = null }
        return
    }
    BackHandler(onBack = onClose)
    // No button until there is a form, as a value the shell sees change: a button that tested
    // for the form inside its own content stayed empty when the form arrived after the screen.
    val saveButton: (@Composable RowScope.() -> Unit)? = if (form == null) null else {
        {
            TextButton(enabled = !state.saving && !state.saved && !state.tagsNeedRefresh && !state.publicationNeedRefresh,
                onClick = { onSaving(); scope.launch { model.save() } },
                colors = ButtonDefaults.textButtonColors(contentColor = palette.accent, disabledContentColor = tokens.tertiaryInk)) {
                Text("Save", fontSize = 15.sp, lineHeight = 21.sp)
            }
        }
    }
    ProvidePushedShellChrome(hasSubjectHeader = true, hideTabBar = true, onBack = onClose, trailingContent = saveButton)
    state.saveError?.let { WritingErrorAlert("AO3 could not save the change", it, model::dismissSaveError) }
    if (confirmingPost && form != null) {
        val missing = form.missingRequiredFields()
        WorkPostAlert(workPostConfirmation(missing), if (missing.isEmpty()) "Post work" else "Fill in what is missing",
            onDismiss = { confirmingPost = false }, onConfirm = {
                confirmingPost = false
                if (missing.isEmpty()) { onSaving(); scope.launch { model.post() } }
            })
    }
    state.deleteImplications?.let { implications ->
        if (form != null && !state.saving) AlertDialog(onDismissRequest = model::dismissDelete,
            containerColor = tokens.cardFill, titleContentColor = tokens.primaryInk, textContentColor = tokens.secondaryInk,
            title = { Text(if (form.isDraft) "Delete this draft?" else "Delete this work?", lineHeight = 28.sp) },
            text = { Text(implications.cautionText, lineHeight = 22.sp) },
            confirmButton = { TextButton(onClick = { onSaving(); scope.launch { model.delete() } }) {
                Text(if (form.isDraft) "Delete" else "Delete on AO3", color = MaterialTheme.colorScheme.error, lineHeight = 20.sp)
            } }, dismissButton = { TextButton(onClick = model::dismissDelete) {
                Text("Cancel", color = palette.accent, lineHeight = 20.sp)
            } })
    }
    LazyColumn(Modifier.fillMaxSize().subjectScreenWash(palette).testTag("Writing work form"), state = list,
        contentPadding = PaddingValues(bottom = 24.dp)) {
        item {
            Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
            Spacer(Modifier.height(76.dp))
            SubjectHeaderBlock(kicker = "AO3 Account", title = form?.screenTitle() ?: loadingTitle,
                subtitle = form?.subtitle(), palette = palette, gutter = SubjectMetrics.accountGutter)
            if (form?.isDraft == true) WorkFormFootnote("This draft isn't public yet. Options that apply only after posting " +
                "will appear once you post it.")
        }
        if (form == null) item {
            Box(Modifier.fillMaxWidth().padding(top = 60.dp).padding(horizontal = SubjectMetrics.accountGutter),
                contentAlignment = Alignment.Center) {
                val failure = state.failure
                if (failure == null) CircularProgressIndicator(color = palette.accent, trackColor = tokens.separator)
                else Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Couldn't load from AO3", color = tokens.primaryInk, fontSize = 20.sp, lineHeight = 27.sp,
                        textAlign = TextAlign.Center)
                    Text(failure, color = tokens.secondaryInk, fontSize = 14.sp, lineHeight = 20.sp, textAlign = TextAlign.Center)
                    TextButton(onClick = { scope.launch { model.load(retry = true) } },
                        colors = ButtonDefaults.textButtonColors(contentColor = palette.accent)) {
                        Text("Try Again", color = palette.accent, fontSize = 14.sp, lineHeight = 20.sp)
                    }
                }
            }
        } else {
            item {
                WorkFormSection(if (form.isDraft) "Required before posting" else "Required")
                SettingsPanel(Modifier.padding(top = 8.dp)) {
                    SubjectTextFieldRow("Title ∗", form.title, "Title", model::title, enabled = !state.saving)
                    SubjectRowSeparator()
                    WorkFormChoiceRow("Rating", form, WorkFormChoice.Rating, enabled = !state.saving) { if (!state.saving) choosing = it }
                    SubjectRowSeparator()
                    SubjectFormRow("Archive warnings ∗", value = workFormCount(form.warnings), showsDisclosure = true,
                        onClick = if (state.saving) null else ({ choosingTags = WorkFormTags.Warnings }), valueMaxLines = Int.MAX_VALUE)
                    SubjectRowSeparator()
                    SubjectFormRow("Fandoms ∗", value = workFormCount(form.fandoms), valueMaxLines = Int.MAX_VALUE,
                        showsDisclosure = true, onClick = if (state.saving) null else ({ writingTags = WritingTagKind.Fandom }))
                    SubjectRowSeparator()
                    WorkFormChoiceRow("Language", form, WorkFormChoice.Language, enabled = !state.saving) { if (!state.saving) choosing = it }
                }
            }
            item {
                WorkFormSection("Tags")
                if (state.tagsNeedRefresh) TextButton(enabled = !state.refreshingTags,
                    onClick = { scope.launch { model.refreshTags(retry = true) } },
                    colors = ButtonDefaults.textButtonColors(contentColor = palette.accent)) {
                    Text("Reload tags", color = palette.accent, fontSize = 14.sp, lineHeight = 20.sp)
                }
                SettingsPanel(Modifier.padding(top = 8.dp)) {
                    SubjectFormRow("Categories", value = workFormCount(form.categories), showsDisclosure = true,
                        onClick = if (state.saving) null else ({ choosingTags = WorkFormTags.Categories }), valueMaxLines = Int.MAX_VALUE)
                    SubjectRowSeparator()
                    SubjectFormRow("Relationships", value = workFormCount(form.relationships), valueMaxLines = Int.MAX_VALUE,
                        showsDisclosure = true, onClick = if (state.saving) null else ({ writingTags = WritingTagKind.Relationship }))
                    SubjectRowSeparator()
                    SubjectFormRow("Characters", value = workFormCount(form.characters), valueMaxLines = Int.MAX_VALUE,
                        showsDisclosure = true, onClick = if (state.saving) null else ({ writingTags = WritingTagKind.Character }))
                    SubjectRowSeparator()
                    SubjectFormRow("Additional tags", value = workFormCount(form.additionalTags), valueMaxLines = Int.MAX_VALUE,
                        showsDisclosure = true, onClick = if (state.saving) null else ({ writingTags = WritingTagKind.Freeform }))
                }
                WorkFormFootnote("Tags can also be edited separately from the work text.")
            }
            item {
                WorkFormSection("Association")
                SettingsPanel(Modifier.padding(top = 8.dp)) {
                    SubjectFormRow("Series", value = form.seriesValue(), valueMaxLines = Int.MAX_VALUE,
                        showsDisclosure = true, onClick = if (state.saving) null else ({ association = WorkAssociation.Series }))
                    SubjectRowSeparator()
                    SubjectFormRow("Add to collections", value = workFormCount(form.postedCollectionNames), valueMaxLines = Int.MAX_VALUE,
                        showsDisclosure = true, onClick = if (state.saving) null else ({ association = WorkAssociation.CollectionsGifts }))
                    SubjectRowSeparator()
                    SubjectFormRow("Gift recipients", value = workFormCount(form.gifts), valueMaxLines = Int.MAX_VALUE,
                        showsDisclosure = true, onClick = if (state.saving) null else ({ association = WorkAssociation.CollectionsGifts }))
                    SubjectRowSeparator()
                    SubjectFormRow("Co-creators", value = form.creatorsValue(), valueMaxLines = Int.MAX_VALUE,
                        showsDisclosure = true, onClick = if (state.saving) null else ({ association = WorkAssociation.Creators }))
                    SubjectRowSeparator()
                    SubjectFormRow("Inspired by", value = if (form.parentWork.url.isEmpty()) "None" else "1", valueMaxLines = Int.MAX_VALUE,
                        showsDisclosure = true, onClick = if (state.saving) null else ({ association = WorkAssociation.Parent }))
                }
            }
            item {
                WorkFormSection("Text")
                SettingsPanel(Modifier.padding(top = 8.dp)) {
                    WorkFormTextRow(form, WorkFormText.Summary, enabled = !state.saving) { if (!state.saving) editing = it }
                    SubjectRowSeparator()
                    WorkFormTextRow(form, WorkFormText.Notes, enabled = !state.saving) { if (!state.saving) editing = it }
                    SubjectRowSeparator()
                    WorkFormTextRow(form, WorkFormText.Endnotes, enabled = !state.saving) { if (!state.saving) editing = it }
                    // Not for a draft with several chapters: AO3 serves no text box there, and this
                    // row would be an empty one that replaces chapter 1 (audit A4-1).
                    if ((form.kind == AO3WorkFormKind.New || form.isDraft) && form.chapter?.contentServed != false) {
                        SubjectRowSeparator()
                        WorkFormTextRow(form, WorkFormText.Content, enabled = !state.saving) { if (!state.saving) editing = it }
                    }
                    if (form.isPosted && form.workID != null) {
                        SubjectRowSeparator()
                        SubjectFormRow("Chapters", value = form.chaptersPosted?.toString().orEmpty(), valueMaxLines = Int.MAX_VALUE,
                            showsDisclosure = true, onClick = if (state.saving) null else ({ viewingChapters = true }))
                        SubjectRowSeparator()
                        SubjectFormRow("Add chapter", showsDisclosure = true,
                            onClick = if (state.saving) null else ({ onSaving(); chapterModel = model.chapterModel(null, null) }))
                        SubjectRowSeparator()
                        SubjectFormRow("Edit tags", value = "", showsDisclosure = true,
                            onClick = if (state.saving) null else ({ model.editTagsModel()?.let { onSaving(); editingPostedTags = it } }))
                    }
                    SubjectRowSeparator()
                    WorkFormChoiceRow("Work skin", form, WorkFormChoice.Skin, enabled = !state.saving) { if (!state.saving) choosing = it }
                }
            }
            item {
                WorkFormSection(if (form.isDraft) "When posted" else "Publication")
                if (state.publicationNeedRefresh) TextButton(enabled = !state.refreshingPublication,
                    onClick = { scope.launch { model.refreshPublication(retry = true) } },
                    colors = ButtonDefaults.textButtonColors(contentColor = palette.accent)) {
                    Text("Reload chapter totals", color = palette.accent, fontSize = 14.sp, lineHeight = 20.sp)
                }
                SettingsPanel(Modifier.padding(top = 8.dp)) {
                    if (form.isPosted) {
                        WorkFormControlRow("Chapters posted") {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text("${form.chaptersPosted ?: 1} of", color = tokens.secondaryInk, fontSize = 14.5.sp, lineHeight = 20.sp)
                                BasicTextField(form.chapterTotal, onValueChange = model::chapterTotal,
                                    enabled = !state.saving && !state.publicationNeedRefresh,
                                    singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                                    textStyle = ComposeTextStyle(color = tokens.primaryInk, fontSize = 14.5.sp, lineHeight = 20.sp,
                                        textAlign = TextAlign.End), cursorBrush = SolidColor(palette.accent),
                                    modifier = Modifier.width(64.dp).semantics { contentDescription = "Chapter total" },
                                    decorationBox = { input -> Box(contentAlignment = Alignment.CenterEnd) {
                                        if (form.chapterTotal.isEmpty()) Text("?", color = tokens.tertiaryInk, fontSize = 14.5.sp, lineHeight = 20.sp)
                                        input()
                                    } })
                            }
                        }
                        SubjectRowSeparator()
                        WorkFormToggle("Work is complete", form.chapterTotal == "${form.chaptersPosted ?: 1}", enabled = !state.saving && !state.publicationNeedRefresh) {
                            model.toggle(WorkFormSwitch.Complete, it)
                        }
                        SubjectRowSeparator()
                    }
                    WorkFormToggle("Set a different publication date", form.backdate, enabled = !state.saving && !state.publicationNeedRefresh) { model.toggle(WorkFormSwitch.Backdate, it) }
                    if (form.backdate && form.chapter != null) {
                        SubjectRowSeparator()
                        SubjectFormRow("Publication date", value = form.publicationDate().format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)),
                            onClick = if (state.saving || state.publicationNeedRefresh) null else ({ dating = true }), valueMaxLines = Int.MAX_VALUE)
                    }
                    SubjectRowSeparator()
                    WorkFormToggle("Only show to registered users", form.restricted, enabled = !state.saving && !state.publicationNeedRefresh) { model.toggle(WorkFormSwitch.Restricted, it) }
                    SubjectRowSeparator()
                    WorkFormToggle("Enable comment moderation", form.moderatedCommenting, enabled = !state.saving && !state.publicationNeedRefresh) { model.toggle(WorkFormSwitch.Moderation, it) }
                    SubjectRowSeparator()
                    WorkFormChoiceRow("Who can comment", form, WorkFormChoice.Comments, enabled = !state.saving && !state.publicationNeedRefresh) { if (!state.saving && !state.publicationNeedRefresh) choosing = it }
                }
                if (form.isPosted) WorkFormFootnote("AO3 marks a work in progress when its total chapters are higher than the number " +
                    "posted. Complete sets both numbers to the same value.")
            }
            val actionsEnabled = !state.saving && !state.saved && !state.tagsNeedRefresh && !state.publicationNeedRefresh
            if (!form.isPosted) {
                item { WorkFormSection("Post") }
                item { WritingPanelRow(first = true, last = false) {
                    WritingPostRow("Post work", Icons.Filled.ArrowUpward, SuccessGreen, enabled = actionsEnabled) { confirmingPost = true }
                } }
                item { WritingPanelRow(first = false, last = form.workID == null) {
                    WritingPostRow("Preview on AO3", Icons.Filled.Visibility, tokens.primaryInk, enabled = actionsEnabled) {
                        onSaving(); scope.launch { model.openPreview() }
                    }
                } }
                if (form.workID != null) {
                    item { WritingPanelRow(first = false, last = true) {
                        WritingPostRow("Delete draft", Icons.Filled.Delete, MaterialTheme.colorScheme.error, enabled = actionsEnabled) {
                            onSaving(); scope.launch { model.prepareDelete() }
                        }
                    } }
                    item { WorkFormFootnote("AO3 deletes an unposted draft 30 days after it is created.") }
                }
            } else if (form.workID != null) {
                item { WorkFormSection("Delete") }
                item { WritingPanelRow(first = true, last = true) {
                    WritingPostRow("Delete work on AO3", null, MaterialTheme.colorScheme.error, enabled = actionsEnabled) {
                        onSaving(); scope.launch { model.prepareDelete() }
                    }
                } }
            }
        }
    }
    if (form != null) {
        choosing?.let { choice ->
            val options = form.choiceOptions(choice)
            val current = form.choiceValue(choice)
            WorkFormChoiceSheet(when (choice) {
                WorkFormChoice.Rating -> "Rating"
                WorkFormChoice.Language -> "Language"
                WorkFormChoice.Comments -> "Who can comment"
                WorkFormChoice.Skin -> "Work skin"
            }, if (options.none { it.value == current }) listOf(AO3FormOption(current, current.ifEmpty { "Select…" })) + options else options,
                current, onDismiss = { choosing = null }, onPick = { model.choice(choice, it); choosing = null })
        }
        if (dating) WorkFormDateSheet(form.publicationDate(), model::publicationDate) { dating = false }
    }
}

@Composable
internal fun WorkFormSection(title: String) = SectionRuleHeader(title, modifier = Modifier.padding(top = 18.dp))

@Composable
internal fun WorkFormFootnote(text: String) {
    Text(text, color = LocalKudosTokens.current.secondaryInk.copy(alpha = 0.7f), fontSize = 11.5.sp, lineHeight = 17.sp,
        modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter + 14.dp).padding(top = 8.dp))
}

@Composable
private fun WorkFormChoiceRow(label: String, form: AO3WorkForm, kind: WorkFormChoice, enabled: Boolean = true, onPick: (WorkFormChoice) -> Unit) {
    val value = form.choiceValue(kind)
    SubjectFormRow(label, value = form.choiceOptions(kind).firstOrNull { it.value == value }?.title ?: value.ifEmpty { "Select…" },
        valueMaxLines = Int.MAX_VALUE, onClick = if (enabled) ({ onPick(kind) }) else null)
}

@Composable
private fun WorkFormTextRow(form: AO3WorkForm, field: WorkFormText, enabled: Boolean = true, onEdit: (WorkFormText) -> Unit) {
    val text = field.text(form)
    var detail by remember { mutableStateOf<String?>(null) }
    // Summary only; never lay out or count chapter content in this row.
    LaunchedEffect(text, field) {
        detail = if (field == WorkFormText.Summary && text.isNotEmpty()) withContext(Dispatchers.Default) {
            text.strippingHtml().trim().takeIf { it.isNotEmpty() }
        } else null
    }
    Column {
        SubjectFormRow(field.title, value = if (detail == null) if (text.isEmpty()) "Empty" else "Set" else null,
            showsDisclosure = true, onClick = if (enabled) ({ onEdit(field) }) else null)
        detail?.let { preview ->
            Text(preview, color = LocalKudosTokens.current.secondaryInk, fontSize = 12.5.sp, lineHeight = 18.sp,
                maxLines = if (isAccessibilityFontScale()) Int.MAX_VALUE else 2,
                modifier = Modifier.padding(horizontal = 14.dp).padding(bottom = 11.dp))
        }
    }
}

@Composable
internal fun WorkFormControlRow(label: String, control: @Composable () -> Unit) {
    if (isAccessibilityFontScale()) Column(Modifier.fillMaxWidth().padding(horizontal = 13.dp, vertical = 11.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(label, color = LocalKudosTokens.current.primaryInk, fontSize = 14.5.sp, lineHeight = 20.sp)
        control()
    } else SubjectFormRow(label, trailing = control)
}

@Composable
internal fun WorkFormToggle(label: String, checked: Boolean, enabled: Boolean = true, onChange: (Boolean) -> Unit) {
    WorkFormControlRow(label) {
        SubjectToggle(checked, onChange, enabled = enabled, accent = LocalKudosTokens.current.scopePalette.accent, contentDescription = label)
    }
}

/** Warnings/categories are the iOS closed-list pushed chooser, with no toolbar actions. */
@Composable
private fun WorkFormTagChoices(form: AO3WorkForm, kind: WorkFormTags, onToggle: (WorkFormTags, String) -> Unit, onBack: () -> Unit) {
    val palette = LocalKudosTokens.current.scopePalette
    val title = if (kind == WorkFormTags.Warnings) "Archive warnings" else "Categories"
    val values = form.tagValues(kind)
    BackHandler(onBack = onBack)
    ProvidePushedShellChrome(hasSubjectHeader = true, hideTabBar = true, onBack = onBack)
    Column(Modifier.fillMaxSize().subjectScreenWash(palette)) {
        Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
        Spacer(Modifier.height(76.dp))
        SubjectHeaderBlock(kicker = "Choose", title = title,
            subtitle = if (values.isEmpty()) "None chosen" else "${values.size} chosen", palette = palette, gutter = SubjectMetrics.accountGutter)
        LazyColumn(Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 18.dp).subjectPanel()) {
            itemsIndexed(form.tagOptions(kind)) { index, option ->
                if (index > 0) SubjectRowSeparator()
                WorkFormOptionRow(option.title, option.value in values) { onToggle(kind, option.value) }
            }
        }
    }
}

@Composable
private fun WorkFormOptionRow(label: String, selected: Boolean, onClick: () -> Unit) {
    val tokens = LocalKudosTokens.current
    SubjectFormRow(label, onClick = onClick, trailing = {
        if (selected) Icon(Icons.Filled.Check, contentDescription = "Selected", tint = tokens.scopePalette.accent, modifier = Modifier.size(18.dp))
    })
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun WorkFormChoiceSheet(title: String, options: List<AO3FormOption>, selected: String, onDismiss: () -> Unit, onPick: (String) -> Unit) {
    val tokens = LocalKudosTokens.current
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = tokens.cardFill, contentColor = tokens.primaryInk, scrimColor = tokens.primaryInk.copy(alpha = 0.32f), dragHandle = null) {
        Text(title, fontSize = 18.sp, lineHeight = 25.sp, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
        LazyColumn(Modifier.fillMaxWidth().heightIn(max = 480.dp).navigationBarsPadding()) {
            itemsIndexed(options) { index, option ->
                if (index > 0) SubjectRowSeparator()
                WorkFormOptionRow(option.title, option.value == selected) { onPick(option.value) }
            }
        }
    }
}

/** Gregorian date components avoid a fixed-height calendar clipping at accessibility sizes.
 * Bounds are iOS AO3PublicationDate.allowedRange, not an invented served-choice catalog. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun WorkFormDateSheet(date: LocalDate, onChange: (LocalDate) -> Unit, bounded: Boolean = true, onDismiss: () -> Unit) {
    val tokens = LocalKudosTokens.current
    val today = LocalDate.now()
    var component by remember { mutableStateOf<String?>(null) }
    val part = component
    val choices = when (part) {
        "Year" -> (if (bounded) (1950..today.year).reversed() else (date.year downTo 1).toList() + ((date.year + 1)..9999).toList()).map { AO3FormOption("$it", "$it") }
        "Month" -> (1..if (bounded && date.year == today.year) today.monthValue else 12).map {
            AO3FormOption("$it", java.time.Month.of(it).getDisplayName(TextStyle.FULL, Locale.getDefault()))
        }
        "Day" -> (1..if (bounded && date.year == today.year && date.monthValue == today.monthValue) today.dayOfMonth else date.lengthOfMonth())
            .map { AO3FormOption("$it", "$it") }
        else -> emptyList()
    }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = tokens.cardFill, contentColor = tokens.primaryInk, scrimColor = tokens.primaryInk.copy(alpha = 0.32f), dragHandle = null) {
        Text(part ?: "Publication date", fontSize = 18.sp, lineHeight = 25.sp, modifier = Modifier.padding(16.dp))
        LazyColumn(Modifier.fillMaxWidth().heightIn(max = 480.dp).navigationBarsPadding()) {
            if (part == null) itemsIndexed(listOf("Year" to date.year.toString(), "Month" to date.month.getDisplayName(TextStyle.FULL, Locale.getDefault()),
                "Day" to date.dayOfMonth.toString())) { index, (label, value) ->
                if (index > 0) SubjectRowSeparator()
                SubjectFormRow(label, value = value, onClick = { component = label }, valueMaxLines = Int.MAX_VALUE)
            } else itemsIndexed(choices) { index, option ->
                if (index > 0) SubjectRowSeparator()
                val selected = when (part) { "Year" -> date.year; "Month" -> date.monthValue; else -> date.dayOfMonth }
                WorkFormOptionRow(option.title, option.value == "$selected") {
                    val number = option.value.toInt()
                    val changed = when (part) { "Year" -> date.withYear(number); "Month" -> date.withMonth(number); else -> date.withDayOfMonth(number) }
                    onChange(if (bounded && changed > today) today else changed)
                    component = null
                }
            }
        }
    }
}
