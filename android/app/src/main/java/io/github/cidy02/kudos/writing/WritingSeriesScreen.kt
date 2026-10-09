package io.github.cidy02.kudos.writing

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.core.strippingHtml
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.writing.*
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.settings.SubjectTextFieldRow
import io.github.cidy02.kudos.ui.subject.*
import kotlinx.coroutines.launch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Composable
fun WritingSeriesScreen(id: Long, title: String, repository: AO3SeriesFormRepository, writes: AO3WriteRepository,
    onBack: () -> Unit, onOpenAo3: (String) -> Unit = {}, reorderOnly: Boolean = false,
    works: List<AO3WorkSummary> = emptyList(), subtitle: String = title) {
    // Keep the exact draft across session failure; this model can never post under a new session.
    val model = remember(id, repository, writes, reorderOnly) { WritingSeriesState(id, repository, writes, reorderOnly, works) }
    LaunchedEffect(model) { model.load() }
    DisposableEffect(model) { onDispose { model.close() } }
    WritingSeriesContent(model, title, subtitle, onBack, onOpenAo3, reorderOnly)
}

@Composable
internal fun WritingSeriesContent(model: WritingSeriesState, title: String, subtitle: String = title,
    onBack: () -> Unit, onOpenAo3: (String) -> Unit = {}, reorderOnly: Boolean = false) {
    val state by model.state.collectAsState()
    val form = state.form
    val tokens = LocalKudosTokens.current
    val palette = tokens.scopePalette
    val scope = rememberCoroutineScope()
    val formList = rememberLazyListState()
    val orderList = rememberLazyListState()
    val removeList = rememberLazyListState()
    var textField by remember(model) { mutableStateOf<String?>(null) }
    var ordering by remember(model) { mutableStateOf(reorderOnly) }
    var removing by remember(model) { mutableStateOf(false) }
    var confirmRemoval by remember(model) { mutableStateOf<AO3SeriesWorkRow?>(null) }
    var summaryPreview by remember(model) { mutableStateOf<String?>(null) }
    LaunchedEffect(form?.summary) {
        summaryPreview = null
        val text = form?.summary.orEmpty()
        if (text.isNotEmpty()) summaryPreview = withContext(Dispatchers.Default) {
            text.strippingHtml().trim().takeIf(String::isNotEmpty)
        }
    }
    val field = textField
    if (field != null && form != null) {
        val summary = field == "summary"
        fun change(value: String) = model.edit { if (summary) it.copy(summary = value) else it.copy(notes = value) }
        WritingTextEditorScreen(if (summary) form.summary else form.notes, if (summary) "Series summary" else "Series notes",
            model.account, "series:${model.id}", field, onCheckpoint = ::change,
            onDone = { change(it); textField = null }, onBack = { textField = null })
        return
    }
    val back: () -> Unit = {
        if (ordering && !reorderOnly) ordering = false else if (removing) removing = false else onBack()
    }
    LaunchedEffect(state.orderSaved) { if (state.orderSaved) { if (reorderOnly) onBack() else ordering = false } }
    BackHandler(onBack = back)
    val canSave = !state.saving && !removing && if (ordering) (state.rows?.size ?: 0) >= 2
        else form != null && !seriesTitleIsBlank(form.title)
    val saveButton: (@Composable RowScope.() -> Unit)? = if (form != null || state.rows != null) {
        {
            TextButton(enabled = canSave, onClick = { scope.launch { model.save(order = ordering) } },
                colors = ButtonDefaults.textButtonColors(contentColor = palette.accent, disabledContentColor = tokens.tertiaryInk)) {
                Text("Save", fontSize = 15.sp, lineHeight = 21.sp)
            }
        }
    } else null
    ProvidePushedShellChrome(hasSubjectHeader = true, hideTabBar = true, onBack = back,
        trailingContent = if (removing) null else saveButton)
    val bounds = remember(model) { mutableMapOf<Long, Rect>() }
    var dragged by remember(model) { mutableStateOf<Long?>(null) }
    var point by remember(model) { mutableStateOf(Offset.Zero) }
    var displacement by remember(model) { mutableStateOf(Offset.Zero) }
    val rows = if (removing) form?.works else state.rows
    val currentRows = rows.orEmpty()
    LazyColumn(Modifier.fillMaxSize().subjectScreenWash(palette).imePadding().testTag("Writing series form"),
        state = if (ordering) orderList else if (removing) removeList else formList, contentPadding = PaddingValues(bottom = 24.dp)) {
        item {
            Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
            Spacer(Modifier.height(76.dp))
            SubjectHeaderBlock(kicker = "AO3 Account", title = if (ordering) "Reorder" else if (removing) "Remove works" else "Edit series",
                subtitle = if (ordering) title else if (removing) "$title · ${rows?.size ?: 0} works" else subtitle,
                palette = palette, gutter = SubjectMetrics.accountGutter)
        }
        if (form == null && state.rows == null) item {
            SeriesLoadingRow(state.failure) { scope.launch { model.load(retry = true) } }
        } else if (ordering || removing) {
            if (ordering) item { WorkFormSection("Reading order") }
            itemsIndexed(currentRows, key = { _, row -> row.serialWorkID }) { index, row ->
                DisposableEffect(row.serialWorkID) { onDispose { bounds.remove(row.serialWorkID) } }
                val rowModifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter)
                    .writingSuggestionPanel(index == 0, index == currentRows.lastIndex)
                    .onGloballyPositioned { bounds[row.serialWorkID] = it.boundsInRoot() }
                    .graphicsLayer { if (dragged == row.serialWorkID) { translationX = displacement.x; translationY = displacement.y } }
                    .pointerInput(row.serialWorkID, ordering, state.saving, currentRows) {
                        // ponytail: visible drop targets; add edge auto-scroll if device review needs held long-distance drags.
                        if (ordering && !state.saving) detectDragGesturesAfterLongPress(
                            onDragStart = { offset -> dragged = row.serialWorkID; displacement = Offset.Zero; point = (bounds[row.serialWorkID]?.topLeft ?: Offset.Zero) + offset },
                            onDrag = { change, amount -> change.consume(); point += amount; displacement += amount },
                            onDragEnd = {
                                val held = dragged
                                val from = currentRows.indexOfFirst { it.serialWorkID == held }
                                val target = bounds.entries.firstOrNull { it.key != held && it.value.contains(point) }?.key
                                val to = currentRows.indexOfFirst { it.serialWorkID == target }
                                model.move(from, to); dragged = null
                            }, onDragCancel = { dragged = null })
                    }.semantics(mergeDescendants = true) {
                        contentDescription = (if (ordering) "${index + 1}. " else "") + row.displayTitle +
                            (if (row.isDraft) ", Draft" else "") + row.metadataText.takeIf(String::isNotEmpty)?.let { ", $it" }.orEmpty()
                        if (ordering) stateDescription = "Drag to reorder."
                        if (ordering && !state.saving) customActions = listOf(
                            CustomAccessibilityAction("Move Earlier") { model.move(index, index - 1); true },
                            CustomAccessibilityAction("Move Later") { model.move(index, index + 1); true })
                    }
                Column(rowModifier) {
                    Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 11.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        if (ordering) Text("${index + 1}", color = palette.accent, fontSize = 13.sp, lineHeight = 19.sp)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Text(row.displayTitle, color = tokens.primaryInk, fontSize = 14.5.sp, lineHeight = 21.sp,
                                maxLines = if (isAccessibilityFontScale()) Int.MAX_VALUE else 2)
                            if (row.metadataText.isNotEmpty()) Text(row.metadataText, color = tokens.secondaryInk, fontSize = 11.5.sp, lineHeight = 17.sp)
                            if (row.isDraft) Text("Draft", color = tokens.secondaryInk, fontSize = 11.5.sp, lineHeight = 17.sp)
                        }
                        if (removing && currentRows.size > 1) TextButton(onClick = { confirmRemoval = row }, enabled = !state.saving,
                            colors = ButtonDefaults.textButtonColors(contentColor = SubjectPalette.fromHue(0.0, tokens.theme).accent)) {
                            Text("Remove", fontSize = 13.sp, lineHeight = 19.sp,
                                modifier = Modifier.semantics { contentDescription = "Remove ${row.displayTitle} from the series" })
                        }
                    }
                    if (index < currentRows.lastIndex) SubjectRowSeparator()
                }
            }
            item { WorkFormFootnote(if (ordering) "Each work has a numbered position. After you arrange the list, save once to update " +
                "the whole order on AO3 and check that it was saved." else if (rows.orEmpty().size > 1)
                "A removed work stays posted and only leaves this series." else
                "AO3 deletes a series when its last work leaves. Remove the last work by deleting the series on AO3.") }
        } else if (form != null) {
            item { WorkFormSection("Series") }
            item {
                Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter).writingSuggestionPanel(true, false)) {
                    SubjectTextFieldRow("Title", form.title, "Title", { value -> model.edit { it.copy(title = value) } }, enabled = !state.saving)
                    SubjectRowSeparator()
                }
            }
            item {
                Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter).writingSuggestionPanel(false, false)) {
                    SubjectTextFieldRow("Creators", form.creators.coauthorByline, "Add a co-creator byline",
                        { value -> model.edit { it.copy(creators = it.creators.copy(coauthorByline = value)) } },
                        enabled = !state.saving, autocorrect = false)
                    SubjectRowSeparator()
                }
            }
            for ((index, name) in listOf("summary", "notes").withIndex()) item {
                Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter).writingSuggestionPanel(false, index == 1)) {
                    val value = if (name == "summary") form.summary else form.notes
                    SubjectFormRow(if (name == "summary") "Series summary" else "Series notes", showsDisclosure = true,
                        onClick = if (state.saving) null else ({ textField = name }), trailing = {
                            if (name != "summary" || summaryPreview == null)
                                Text(if (value.isEmpty()) "Empty" else "Set", color = tokens.secondaryInk, fontSize = 14.5.sp, lineHeight = 20.sp)
                        })
                    if (name == "summary" && summaryPreview != null) Text(summaryPreview.orEmpty(), color = tokens.secondaryInk,
                        fontSize = 12.5.sp, lineHeight = 18.sp, maxLines = if (isAccessibilityFontScale()) Int.MAX_VALUE else 2,
                        modifier = Modifier.padding(horizontal = 14.dp).padding(bottom = 11.dp))
                    if (index == 0) SubjectRowSeparator()
                }
            }
            item { WorkFormSection("State") }
            item {
                Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter).writingSuggestionPanel(true, true)) {
                    WorkFormToggle("Series is complete", form.isComplete, !state.saving) { value -> model.edit { it.copy(isComplete = value) } }
                }
                WorkFormFootnote("Complete appears on the AO3 series page and its description. You can still add works to a complete series.")
            }
            item { WorkFormSection("Works") }
            item {
                Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter).writingSuggestionPanel(true, true)) {
                    SubjectFormRow("Reorder works", showsDisclosure = form.works.size >= 2, onClick = if (state.saving || form.works.size < 2) null else
                        ({ model.beginReorder(); ordering = true }), trailing = {
                        Text("${form.works.size}", color = tokens.secondaryInk, fontSize = 14.5.sp, lineHeight = 20.sp) })
                    SubjectRowSeparator()
                    SubjectFormRow("Remove works", showsDisclosure = true, onClick = if (state.saving) null else ({ removing = true }), trailing = {
                        Text("${form.works.size}", color = tokens.secondaryInk, fontSize = 14.5.sp, lineHeight = 20.sp) })
                }
                WorkFormFootnote("Reordering changes the saved position on ${worksPhrase(form.works.size)}. All positions are saved together.")
            }
            item { WorkFormSection("Delete") }
            item {
                Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter).writingSuggestionPanel(true, true)) {
                    SubjectFormRow("Delete series on AO3", showsDisclosure = true, onClick = { onOpenAo3(AO3SeriesFormUrls.show(model.id)) })
                }
                WorkFormFootnote("Deleting the series leaves ${worksPhrase(form.works.size)} posted and unlinks them.")
            }
        }
        state.error?.let { message -> item { Text(message, color = SubjectPalette.fromHue(0.0, tokens.theme).accent, fontSize = 14.sp, lineHeight = 20.sp,
            modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 12.dp)) } }
        if (!ordering && !removing) state.notice?.let { message -> item { Text(message, color = tokens.secondaryInk, fontSize = 14.sp,
            lineHeight = 20.sp, modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 12.dp)) } }
        if (state.saving) item { SeriesLoadingRow(null, saving = true) {} }
    }
    confirmRemoval?.let { row ->
        AlertDialog(onDismissRequest = { confirmRemoval = null }, containerColor = tokens.cardFill,
            titleContentColor = tokens.primaryInk, textContentColor = tokens.secondaryInk,
            title = { Text("Remove “${row.displayTitle}” from $title?", lineHeight = 28.sp) },
            text = { Text("The work stays posted on AO3.", lineHeight = 22.sp) },
            confirmButton = { TextButton(onClick = { confirmRemoval = null; scope.launch { model.remove(row) } }) {
                Text("Remove from series", color = SubjectPalette.fromHue(0.0, tokens.theme).accent, lineHeight = 20.sp) } },
            dismissButton = { TextButton(onClick = { confirmRemoval = null }) { Text("Cancel", color = palette.accent, lineHeight = 20.sp) } })
    }
}

private fun worksPhrase(count: Int) = if (count == 1) "the work" else "the $count works"

@Composable
private fun SeriesLoadingRow(failure: String?, saving: Boolean = false, retry: () -> Unit) {
    val tokens = LocalKudosTokens.current
    Column(Modifier.fillMaxWidth().padding(horizontal = SubjectMetrics.accountGutter).padding(top = 18.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (failure != null) {
            Text("Couldn't load from AO3", color = tokens.primaryInk, fontSize = 20.sp, lineHeight = 27.sp)
            Text(failure, color = tokens.secondaryInk, fontSize = 14.sp, lineHeight = 20.sp)
            TextButton(onClick = retry, colors = ButtonDefaults.textButtonColors(contentColor = tokens.scopePalette.accent)) {
                Text("Try Again", fontSize = 14.sp, lineHeight = 20.sp)
            }
        } else Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            CircularProgressIndicator(color = tokens.scopePalette.accent, trackColor = tokens.separator,
                modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
            Text(if (saving) "Saving…" else "Loading…", color = tokens.secondaryInk, fontSize = 14.sp, lineHeight = 20.sp)
        }
    }
}
