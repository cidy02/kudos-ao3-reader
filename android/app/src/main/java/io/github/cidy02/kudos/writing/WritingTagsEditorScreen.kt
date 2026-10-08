package io.github.cidy02.kudos.writing

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.network.ao3.search.AO3TagAutocompleteRepository
import io.github.cidy02.kudos.settings.SubjectTextFieldRow
import io.github.cidy02.kudos.ui.subject.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch

@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun WritingTagsEditorScreen(
    kind: WritingTagKind,
    values: List<String>,
    repository: AO3TagAutocompleteRepository?,
    settings: SettingsRepository?,
    onValues: (List<String>) -> Unit,
    readValues: () -> List<String>,
    recordScope: CoroutineScope,
    onBack: () -> Unit
) {
    val currentRead by rememberUpdatedState(readValues)
    val currentEdit by rememberUpdatedState(onValues)
    val scope = rememberCoroutineScope()
    val model = remember(kind, repository, settings) {
        WritingTagsEditorState(kind, repository, scope, { currentRead() }, { currentEdit(it) }, { name ->
            // The parent form's scope survives Back from this picker, so an accepted
            // add reaches the atomic settings edit even when the writer leaves immediately.
            if (settings != null) recordScope.launch { settings.recordWritingTag(kind.endpoint, name) }
        })
    }
    DisposableEffect(model) { onDispose { model.close() } }
    val state by model.state.collectAsState()
    val recentFlow = remember(settings) { settings?.recentWritingTags ?: flowOf(emptyMap()) }
    val byKind by recentFlow.collectAsState(initial = emptyMap())
    val recent = byKind[kind.endpoint].orEmpty().filterNot { excludesWritingSuggestion(it, values) }
    // Through the collected state, so an answer that arrives after the last keystroke redraws the list;
    // model.suggestions() reads the flow's value without subscribing, and the names waited for the next key.
    val suggestions = state.names
    val typed = model.typedTerm()
    val hasRows = typed != null || suggestions.isNotEmpty() || state.error != null
    val keyboard = LocalSoftwareKeyboardController.current
    val leave = { keyboard?.hide(); model.close(); onBack() }
    BackHandler(onBack = leave)
    ProvidePushedShellChrome(hasSubjectHeader = true, hideTabBar = true, onBack = leave)
    val tokens = LocalKudosTokens.current
    val palette = tokens.scopePalette
    val drag = remember(model) { WritingChipDrag() }
    val list = rememberLazyListState()
    var fieldHeight by remember { mutableIntStateOf(0) }
    Column(Modifier.fillMaxSize().subjectScreenWash(palette).imePadding()) {
        Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
        Spacer(Modifier.height(76.dp))
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            val width = maxWidth - SubjectMetrics.accountGutter * 2
            val chosenRows = writingChipRows(values, width, chosen = true)
            val recentRows = writingChipRows(recent, width, chosen = false)
            val suggestionIndex = 2 + chosenRows.size + if (recentRows.isEmpty()) 0 else recentRows.size + 1
            // Keep the pinned input and the suggestions in the viewport when the
            // keyboard takes space, even if hundreds of chosen chips precede them.
            LaunchedEffect(state.term, hasRows, fieldHeight) {
                if (state.term.isNotEmpty() && hasRows && fieldHeight > 0) {
                    list.scrollToItem(suggestionIndex, scrollOffset = -fieldHeight)
                }
            }
            LazyColumn(Modifier.fillMaxSize().testTag("Writing tags editor"), state = list,
                contentPadding = PaddingValues(bottom = 24.dp)) {
                item {
                    SubjectHeaderBlock(kicker = "Edit tags", title = kind.title, subtitle = writingTagSubtitle(values),
                        palette = palette, gutter = SubjectMetrics.accountGutter)
                }
                stickyHeader {
                    // Opaque token wash keeps the scrolled chips out from under the field.
                    Column(Modifier.onSizeChanged { fieldHeight = it.height }
                        .subjectWash(palette, SubjectMetrics.defaultWashHeight).padding(horizontal = SubjectMetrics.accountGutter)
                        .padding(top = 18.dp, bottom = 8.dp).subjectPanel(cornerRadius = 12.dp)) {
                        SubjectTextFieldRow("Add a tag", state.term, "Add a tag", model::type, autocorrect = false,
                            fieldOnly = true, onSubmit = { model.add() }, leading = {
                                Icon(Icons.Default.Search, null, tint = tokens.secondaryInk, modifier = Modifier.size(16.dp))
                            }, trailing = {
                                Box(Modifier.size(48.dp), contentAlignment = Alignment.Center) {
                                    if (state.term.isNotEmpty()) IconButton(onClick = { model.type("") }) {
                                        Icon(Icons.Default.Close, "Clear", tint = tokens.secondaryInk, modifier = Modifier.size(18.dp))
                                    }
                                }
                            })
                    }
                }
                itemsIndexed(chosenRows) { index, row ->
                    Row(Modifier.fillMaxWidth().padding(horizontal = SubjectMetrics.accountGutter)
                        .padding(top = if (index == 0) 10.dp else 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        row.forEach { chip ->
                            WritingChosenChip(chip.name, chip.width, model, drag)
                        }
                    }
                }
                if (recentRows.isNotEmpty()) {
                    item { SubjectFieldLabel("Recently used", lineHeight = 15.sp,
                        modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 18.dp)) }
                    itemsIndexed(recentRows) { _, row ->
                        Row(Modifier.fillMaxWidth().padding(horizontal = SubjectMetrics.accountGutter).padding(top = 8.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            row.forEach { chip ->
                                SubjectChip(chip.name, Modifier.width(chip.width).heightIn(min = 48.dp)
                                    .clickable(role = Role.Button) { model.add(chip.name) }
                                    .semantics { contentDescription = "Add ${chip.name}" },
                                    style = SubjectChipStyle.Dashed, leadingIcon = Icons.Default.Add, palette = palette,
                                    maxLines = Int.MAX_VALUE)
                            }
                        }
                    }
                }
                if (hasRows) {
                    item { SubjectFieldLabel("Suggestions", lineHeight = 15.sp,
                        modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 20.dp, bottom = 8.dp)) }
                    val rows = listOfNotNull(typed?.let { it to false }) + suggestions.map { it to true }
                    itemsIndexed(rows) { index, (name, canonical) ->
                        Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter).writingSuggestionPanel(
                            first = index == 0, last = index == rows.lastIndex && state.error == null)) {
                            WritingSuggestionRow(name, canonical) { model.add(name) }
                            if (index != rows.lastIndex || state.error != null) SubjectRowSeparator()
                        }
                    }
                    state.error?.let { error ->
                        item {
                            Text(error, color = tokens.secondaryInk, fontSize = 11.5.sp, lineHeight = 17.sp,
                                modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter)
                                    .writingSuggestionPanel(first = rows.isEmpty(), last = true)
                                    .padding(horizontal = 14.dp, vertical = 11.dp))
                        }
                    }
                }
                item {
                    Text(WritingTagFootnote, color = tokens.secondaryInk.copy(alpha = 0.7f), fontSize = 11.5.sp, lineHeight = 17.sp,
                        modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter + 4.dp)
                            .padding(top = if (hasRows) 8.dp else 20.dp))
                }
            }
        }
    }
}

@Composable
private fun WritingSuggestionRow(name: String, canonical: Boolean, onAdd: () -> Unit) {
    val tokens = LocalKudosTokens.current
    val palette = tokens.scopePalette
    Row(Modifier.fillMaxWidth().clickable(role = Role.Button, onClick = onAdd).semantics(mergeDescendants = true) {
        contentDescription = "Add $name"
        stateDescription = if (canonical) "canonical tag" else "posts as typed"
    }.padding(horizontal = 14.dp, vertical = 11.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(name, color = tokens.primaryInk, fontSize = 15.sp, lineHeight = 21.sp)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                val badge = SubjectPalette.fromHue(if (canonical) 0.33 else 0.08, tokens.theme).accent
                if (canonical) Icon(Icons.Default.CheckCircle, null, tint = badge, modifier = Modifier.size(12.dp))
                Text(if (canonical) "Canonical" else "Posts as typed", color = badge, fontSize = 10.5.sp, lineHeight = 15.sp,
                    fontWeight = if (canonical) FontWeight.Medium else FontWeight.Normal)
            }
        }
        Icon(Icons.Default.Add, null, tint = palette.accent, modifier = Modifier.size(18.dp))
    }
}

private class WritingChipDrag {
    val bounds = mutableMapOf<String, Rect>()
    var name by mutableStateOf<String?>(null)
    var point = Offset.Zero
    var displacement by mutableStateOf(Offset.Zero)
    fun clear() { name = null; displacement = Offset.Zero }
}

@Composable
private fun WritingChosenChip(name: String, width: Dp, model: WritingTagsEditorState, drag: WritingChipDrag) {
    val tokens = LocalKudosTokens.current
    DisposableEffect(name) { onDispose { drag.bounds.remove(name) } }
    Row(Modifier.width(width), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        SubjectChip(name, Modifier.weight(1f).heightIn(min = 48.dp)
            .onGloballyPositioned { drag.bounds[name] = it.boundsInRoot() }
            .graphicsLayer {
                if (drag.name == name) { translationX = drag.displacement.x; translationY = drag.displacement.y }
            }
            .pointerInput(name, model) {
                detectDragGesturesAfterLongPress(onDragStart = { offset ->
                    drag.name = name; drag.displacement = Offset.Zero
                    drag.point = (drag.bounds[name]?.topLeft ?: Offset.Zero) + offset
                }, onDrag = { change, amount ->
                    change.consume(); drag.point += amount; drag.displacement += amount
                }, onDragEnd = {
                    drag.bounds.entries.firstOrNull { it.key != name && it.value.contains(drag.point) }?.let {
                        model.move(name, it.key)
                    }
                    drag.clear()
                }, onDragCancel = drag::clear)
            }.semantics(mergeDescendants = true) {
                contentDescription = name
                stateDescription = "Drag to reorder."
                customActions = listOf(CustomAccessibilityAction("Move Earlier") { model.step(name, false); true },
                    CustomAccessibilityAction("Move Later") { model.step(name, true); true })
            }, style = SubjectChipStyle.Pill(false), palette = tokens.scopePalette, maxLines = Int.MAX_VALUE)
        IconButton(onClick = { model.remove(name) }) {
            Icon(Icons.Default.Close, "Remove $name", tint = tokens.secondaryInk, modifier = Modifier.size(14.dp))
        }
    }
}

private data class WritingChipSize(val name: String, val width: Dp)

/** Measure flow rows once, then virtualize each row rather than composing a whole long list. */
@Composable
private fun writingChipRows(names: List<String>, width: Dp, chosen: Boolean): List<List<WritingChipSize>> {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    return remember(names, width, chosen, measurer, density) {
        val result = mutableListOf<List<WritingChipSize>>()
        var row = mutableListOf<WritingChipSize>()
        var used = 0.dp
        names.forEach { name ->
            val textWidth = with(density) {
                measurer.measure(name, TextStyle(fontSize = 13.sp, lineHeight = 18.sp), softWrap = false).size.width.toDp()
            }
            val chipWidth = (textWidth + if (chosen) 78.dp else 45.dp).coerceAtMost(width).coerceAtLeast(0.dp)
            val gap = if (row.isEmpty()) 0.dp else 8.dp
            if (row.isNotEmpty() && used + gap + chipWidth > width) {
                result.add(row); row = mutableListOf(); used = 0.dp
            }
            used += (if (row.isEmpty()) 0.dp else 8.dp) + chipWidth
            row.add(WritingChipSize(name, chipWidth))
        }
        if (row.isNotEmpty()) result.add(row)
        result
    }
}

/** Lazy rows share one rounded panel, with side strokes and only the outer end caps. */
@Composable
internal fun Modifier.writingSuggestionPanel(first: Boolean, last: Boolean): Modifier {
    val tokens = LocalKudosTokens.current
    val radius = SubjectMetrics.panelRadius
    val border = tokens.glassStroke(0.13)
    val shape = RoundedCornerShape(topStart = if (first) radius else 0.dp, topEnd = if (first) radius else 0.dp,
        bottomStart = if (last) radius else 0.dp, bottomEnd = if (last) radius else 0.dp)
    return background(tokens.glassFill(0.09), shape).drawBehind {
        val r = radius.toPx().coerceAtMost(size.width / 2).coerceAtMost(size.height / 2)
        val path = Path()
        path.moveTo(0f, if (first) r else 0f)
        if (first) {
            path.quadraticBezierTo(0f, 0f, r, 0f)
            path.lineTo(size.width - r, 0f)
            path.quadraticBezierTo(size.width, 0f, size.width, r)
        } else { path.moveTo(size.width, 0f) }
        path.lineTo(size.width, if (last) size.height - r else size.height)
        if (last) {
            path.quadraticBezierTo(size.width, size.height, size.width - r, size.height)
            path.lineTo(r, size.height)
            path.quadraticBezierTo(0f, size.height, 0f, size.height - r)
        } else { path.moveTo(0f, size.height) }
        path.lineTo(0f, if (first) r else 0f)
        drawPath(path, border, style = Stroke(0.5.dp.toPx()))
    }
}
