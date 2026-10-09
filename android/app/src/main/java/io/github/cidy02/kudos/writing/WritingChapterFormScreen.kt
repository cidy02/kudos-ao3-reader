package io.github.cidy02.kudos.writing

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.network.ao3.writing.*
import io.github.cidy02.kudos.settings.SubjectTextFieldRow
import io.github.cidy02.kudos.ui.subject.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** Chapter form fields are drawn only from collected state. Editors share the exact recovery key. */
@Composable
internal fun WritingChapterFormScreen(model: WritingChapterFormState, workTitle: String,
    operationScope: CoroutineScope? = null, onSaved: () -> Unit = {}, onBack: () -> Unit) {
    val state by model.state.collectAsState()
    val form = state.form
    val tokens = LocalKudosTokens.current
    val palette = tokens.scopePalette
    val scope = rememberCoroutineScope()
    val ownerScope = operationScope ?: scope
    var mounted by remember(model) { mutableStateOf(true) }
    DisposableEffect(model) { onDispose { mounted = false; if (!model.state.value.busy) model.close() } }
    fun run(operation: suspend () -> Unit) {
        ownerScope.launch {
            val revision = model.state.value.savedRevision
            try {
                operation()
            } finally {
                if (model.state.value.savedRevision != revision) onSaved()
                if (mounted && model.state.value.finished) onBack()
                if (!mounted) model.close()
            }
        }
    }
    val preview = state.preview
    if (preview != null) {
        WritingAO3PreviewScreen(preview, form?.let { chapterSubtitle(workTitle, it) }.orEmpty(),
            postTitle = if (form?.posts == true) "Post chapter" else "Update", busy = state.busy, error = state.saveError,
            dismissError = model::dismissError, onBack = model::closePreview,
            onPost = { run { model.save(if (form?.posts == true) AO3WorkSubmitAction.Post else AO3WorkSubmitAction.Update) } })
        return
    }
    var editing by remember(model) { mutableStateOf<ChapterFormText?>(null) }
    var dating by remember(model) { mutableStateOf(false) }
    LaunchedEffect(model) { model.load() }
    val field = editing
    if (field != null && form != null) {
        WritingTextEditorScreen(field.text(form), field.title, model.account, form.recoveryTarget(), field.field,
            onCheckpoint = { model.checkpoint(field, it) }, onDone = { model.checkpoint(field, it); editing = null },
            onBack = { editing = null }, ruleTitle = if (field == ChapterFormText.Content) chapterNumber(form.position)?.let { "Chapter $it" } else null,
            chapterActions = if (field == ChapterFormText.Content) WritingChapterEditorActions(
                preview = { run { model.openPreview() } },
                deleteName = if (form.chapterID != null && (model.chapterCount ?: 0) > 1) chapterDeleteName(form) else null,
                delete = { run { model.deleteChapter(confirmed = true) } }) else null)
        return
    }
    BackHandler(onBack = onBack)
    ProvidePushedShellChrome(hasSubjectHeader = true, hideTabBar = true, onBack = onBack)
    state.saveError?.let { WritingErrorAlert("AO3 could not save the chapter", it, model::dismissError) }
    LazyColumn(Modifier.fillMaxSize().subjectScreenWash(palette).testTag("Writing chapter form"),
        contentPadding = PaddingValues(bottom = 24.dp)) {
        item {
            Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
            Spacer(Modifier.height(76.dp))
            SubjectHeaderBlock(kicker = "AO3 Account", title = if (form?.chapterID == null && form != null) "Add chapter" else "Edit chapter",
                subtitle = form?.let { chapterSubtitle(workTitle, it) }, palette = palette, gutter = SubjectMetrics.accountGutter)
        }
        if (form == null) item {
            Column(Modifier.fillMaxWidth().padding(top = 60.dp).padding(horizontal = SubjectMetrics.accountGutter),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                val failure = state.failure
                if (failure == null) CircularProgressIndicator(color = palette.accent, trackColor = tokens.separator)
                else {
                    Text("Couldn't load from AO3", color = tokens.primaryInk, fontSize = 20.sp, lineHeight = 27.sp)
                    Text(failure, color = tokens.secondaryInk, fontSize = 14.sp, lineHeight = 20.sp)
                    TextButton(onClick = { scope.launch { model.load(retry = true) } }, colors = ButtonDefaults.textButtonColors(contentColor = palette.accent)) {
                        Text("Try Again", color = palette.accent, fontSize = 14.sp, lineHeight = 20.sp)
                    }
                }
            }
        } else {
            val enabled = !state.busy && !state.chapterSaved && !state.finished
            item { WorkFormSection("Chapter") }
            item { WritingPanelRow(first = true, last = false) {
                SubjectTextFieldRow("Title", form.title, "Title", model::title, enabled = enabled)
            } }
            item { WritingPanelRow(first = false, last = !form.includePosition) {
                WorkFormControlRow(if (form.includePosition && chapterNumber(form.position) != null) "Chapter number" else "Expected chapter total") {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        if (form.includePosition) chapterNumber(form.position)?.let {
                            Text("$it of", color = tokens.secondaryInk, fontSize = 14.5.sp, lineHeight = 20.sp)
                        }
                        ChapterNumberField(form.wipLength, "Expected chapter total", if (form.includePosition) "?" else "Unknown", enabled, model::total)
                    }
                }
            } }
            if (form.includePosition) item { WritingPanelRow(first = false, last = true) {
                WorkFormControlRow("Position") {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("After chapter", color = tokens.secondaryInk, fontSize = 14.5.sp, lineHeight = 20.sp)
                        ChapterNumberField(chapterAfterText(form.position), "Position, after chapter", "?", enabled, model::afterChapter)
                    }
                }
            } }
            item { WorkFormSection("Text") }
            itemsIndexed(ChapterFormText.entries) { index, text ->
                WritingPanelRow(first = index == 0, last = index == ChapterFormText.entries.lastIndex) {
                    val emptyContent = text == ChapterFormText.Content && form.content.isEmpty()
                    SubjectFormRow(text.title, showsDisclosure = true, onClick = if (enabled) ({ editing = text }) else null,
                        trailing = if (emptyContent) null else ({
                            Text(if (text.text(form).isEmpty()) "Empty" else "Set", color = tokens.secondaryInk, fontSize = 14.5.sp, lineHeight = 20.sp)
                        }))
                    if (emptyContent) Text("Empty. This opens the editor with plain text, AO3’s HTML tags, or a paste from elsewhere.",
                        color = tokens.secondaryInk, fontSize = 12.5.sp, lineHeight = 18.sp,
                        maxLines = if (isAccessibilityFontScale()) Int.MAX_VALUE else 2,
                        modifier = Modifier.padding(horizontal = 14.dp).padding(bottom = 11.dp))
                }
            }
            item { WorkFormSection("Publication") }
            item { WritingPanelRow(first = true, last = false) {
                WorkFormToggle("Set a different publication date", form.publishedYear.isNotEmpty(), enabled, model::dateEnabled)
            } }
            if (form.publishedYear.isNotEmpty()) item { WritingPanelRow(first = false, last = false) {
                SubjectFormRow("Publication date", onClick = if (enabled) ({ dating = true }) else null, trailing = {
                    Text(form.publicationDate().format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)),
                        color = tokens.secondaryInk, fontSize = 14.5.sp, lineHeight = 20.sp)
                })
            } }
            if (form.posts) item { WritingPanelRow(first = false, last = false) {
                WorkFormToggle("Post without preview", state.postWithoutPreview, enabled, model::withoutPreview)
            } }
            item { WritingPanelRow(first = false, last = true) {
                WorkFormToggle("This is the last chapter", state.isLastChapter, enabled, model::lastChapter)
            } }
            item { WorkFormFootnote(CHAPTER_LAST_NOTE) }
            item { WorkFormSection("Post") }
            if (state.chapterSaved) {
                item { WritingPanelRow(first = true, last = true) {
                    SubjectFormRow("Retry updating the work total", onClick = if (state.busy) null else ({ run { model.save(AO3WorkSubmitAction.Update) } }))
                } }
                item { WorkFormFootnote("The chapter was saved. Only the work total will be retried.") }
            } else {
                item { WritingPanelRow(first = true, last = !form.posts) {
                    SubjectFormRow(if (form.posts) "Post chapter now" else "Save chapter changes",
                        onClick = if (state.busy) null else ({ run {
                            if (form.posts && !state.postWithoutPreview) model.openPreview()
                            else model.save(if (form.posts) AO3WorkSubmitAction.PostWithoutPreview else AO3WorkSubmitAction.Update)
                        } }), trailing = { if (state.busy) CircularProgressIndicator(color = palette.accent,
                            trackColor = tokens.separator, modifier = Modifier.size(20.dp), strokeWidth = 2.dp) })
                } }
                if (form.posts) item { WritingPanelRow(first = false, last = true) {
                    SubjectFormRow("Save as draft", onClick = if (state.busy) null else ({ run { model.save(AO3WorkSubmitAction.SaveDraft) } }))
                } }
            }
            item { WorkFormFootnote(CHAPTER_POST_NOTE) }
        }
    }
    if (dating && form != null) WorkFormDateSheet(form.publicationDate(), model::date, bounded = false) { dating = false }
}

@Composable
internal fun WritingPanelRow(first: Boolean, last: Boolean, content: @Composable () -> Unit) {
    Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = if (first) 8.dp else 0.dp)
        .writingSuggestionPanel(first, last)) {
        content()
        if (!last) SubjectRowSeparator()
    }
}

@Composable
private fun ChapterNumberField(value: String, label: String, hint: String, enabled: Boolean, change: (String) -> Unit) {
    val tokens = LocalKudosTokens.current
    androidx.compose.foundation.text.BasicTextField(value, onValueChange = change, enabled = enabled,
        singleLine = true, keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Number),
        textStyle = androidx.compose.ui.text.TextStyle(color = tokens.primaryInk, fontSize = 14.5.sp, lineHeight = 20.sp, textAlign = androidx.compose.ui.text.style.TextAlign.End),
        cursorBrush = androidx.compose.ui.graphics.SolidColor(tokens.scopePalette.accent),
        modifier = Modifier.width(90.dp).testTag(label).semantics { contentDescription = label }, decorationBox = { input ->
            Box(contentAlignment = Alignment.CenterEnd) {
                if (value.isEmpty()) Text(hint, color = tokens.tertiaryInk, fontSize = 14.5.sp, lineHeight = 20.sp)
                input()
            }
        })
}

internal const val CHAPTER_LAST_NOTE = "When you turn on Last chapter, Kudos sets the work's total to this chapter's position. AO3 marks the work complete when its posted and total chapters match."
internal const val CHAPTER_POST_NOTE = "Posting a chapter notifies your subscribers. Save it as a draft if you want to work on it over several sittings without sending a notification."

@Composable
internal fun WritingErrorAlert(title: String, message: String, dismiss: () -> Unit) {
    val tokens = LocalKudosTokens.current
    AlertDialog(onDismissRequest = dismiss, containerColor = tokens.cardFill,
        titleContentColor = tokens.primaryInk, textContentColor = tokens.secondaryInk,
        title = { Text(title, lineHeight = 28.sp) }, text = { Text(message, lineHeight = 22.sp) },
        confirmButton = { TextButton(onClick = dismiss) { Text("OK", color = tokens.scopePalette.accent, lineHeight = 20.sp) } })
}

/** Draft work chapter entrances are debug-only: iOS's production work form exposes only posted chapters. */
@Composable
internal fun WritingChapterDemoScreen(chapterID: Long?, repository: AO3WorkFormRepository,
    auth: io.github.cidy02.kudos.auth.AO3AuthRepository,
    writes: io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository, onClose: () -> Unit) {
    val model = remember(chapterID, repository, auth) {
        WritingChapterFormState(995001, chapterID, if (chapterID == null) null else 1, repository, auth, writes = writes)
    }
    WritingChapterFormScreen(model, "Lanterns Above the Mill", onBack = onClose)
}
