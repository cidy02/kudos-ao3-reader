package io.github.cidy02.kudos.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DragHandle
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.zIndex
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectFieldLabel
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.writing.writingSuggestionPanel
import io.github.cidy02.kudos.ui.subject.SubjectPaletteTheme
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import io.github.cidy02.kudos.works.WorkRepository
import kotlinx.coroutines.launch

/**
 * Artboard **1bk**'s "Reorder works".
 * Reads works in reader order and lets the user adjust their sequence.
 * The order is committed on Done rather than on every move to avoid continuous database writes.
 */
@Composable
fun CollectionReorderSheet(
    collection: WorkCollection,
    works: List<SavedWork>,
    workRepository: WorkRepository,
    onDismiss: () -> Unit,
    onSaved: () -> Unit
) {
    val scope = rememberCoroutineScope()
    var ordered by remember(works) { mutableStateOf(works) }
    var saving by remember { mutableStateOf(false) }

    fun moveWork(fromIndex: Int, toIndex: Int) {
        if (fromIndex !in ordered.indices || toIndex !in ordered.indices) return
        val list = ordered.toMutableList()
        val item = list.removeAt(fromIndex)
        list.add(toIndex, item)
        ordered = list
    }

    Dialog(
        onDismissRequest = { if (!saving) onDismiss() },
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        CollectionReorderContent(collection, ordered, saving, onDismiss,
            onSave = {
                saving = true
                scope.launch {
                    workRepository.setCollectionReadingOrder(collection.id, ordered.map { it.id })
                    saving = false
                    onSaved()
                }
            }, onMove = ::moveWork)
    }
}

@Composable
internal fun CollectionReorderContent(
    collection: WorkCollection, ordered: List<SavedWork>, saving: Boolean,
    onDismiss: () -> Unit, onSave: () -> Unit, onMove: (Int, Int) -> Unit
) {
    val tokens = LocalKudosTokens.current
    val palette = collectionDraftPalette(tokens.theme, tokens.scopePalette, collection.hue, collection.colorHex)
    val bounds = remember { mutableMapOf<String, Rect>() }
    var dragged by remember { mutableStateOf<String?>(null) }
    var point by remember { mutableStateOf(Offset.Zero) }
    var displacement by remember { mutableStateOf(Offset.Zero) }
    SubjectPaletteTheme(palette) {
    Column(
        Modifier
            .fillMaxSize()
            .subjectScreenWash(palette)
            .windowInsetsPadding(WindowInsets.safeDrawing)
            .windowInsetsPadding(WindowInsets.ime)
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            TextButton(onClick = onDismiss, enabled = !saving) { Text("Cancel") }
            Text(
                text = "Reorder works",
                modifier = Modifier.weight(1f),
                color = tokens.primaryInk,
                fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold
            )
            TextButton(
                onClick = onSave,
                enabled = !saving
            ) {
                Text(
                    text = "Done",
                    color = if (saving) tokens.tertiaryInk else tokens.theme.accentInk(palette.tint),
                    fontWeight = FontWeight.Bold
                )
            }
        }

        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 16.dp)
                .testTag("Collection reorder rows")
        ) {
            item {
                SubjectHeaderBlock(
                    kicker = "Library › Collections",
                    title = "Reorder",
                    subtitle = collection.name,
                    palette = palette,
                    gutter = 0.dp,
                    modifier = Modifier.padding(top = 12.dp, bottom = 10.dp)
                )
            }

            item {
                SubjectFieldLabel("Reading order", Modifier.padding(top = 16.dp, bottom = 12.dp))
            }

            itemsIndexed(ordered, key = { _, work -> work.id }) { index, work ->
                DisposableEffect(work.id) { onDispose { bounds.remove(work.id) } }
                val position = index + 1
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .zIndex(if (dragged == work.id) 1f else 0f)
                        .onGloballyPositioned { bounds[work.id] = it.boundsInRoot() }
                        .graphicsLayer {
                            if (dragged == work.id) { translationX = displacement.x; translationY = displacement.y }
                        }
                        .pointerInput(work.id, ordered, saving) {
                            // shortcut: drops target visible rows; accessibility moves reach off-screen rows.
                            if (!saving) detectDragGesturesAfterLongPress(
                                onDragStart = { offset ->
                                    dragged = work.id
                                    displacement = Offset.Zero
                                    point = (bounds[work.id]?.topLeft ?: Offset.Zero) + offset
                                },
                                onDrag = { change, amount -> change.consume(); point += amount; displacement += amount },
                                onDragEnd = {
                                    val held = dragged
                                    val from = ordered.indexOfFirst { it.id == held }
                                    val target = bounds.entries.firstOrNull { it.key != held && it.value.contains(point) }?.key
                                    val to = ordered.indexOfFirst { it.id == target }
                                    onMove(from, to)
                                    dragged = null
                                },
                                onDragCancel = { dragged = null })
                        }
                        .writingSuggestionPanel(index == 0, index == ordered.lastIndex)
                        .testTag("Collection reorder row")
                        .semantics(mergeDescendants = true) {
                            stateDescription = "Drag to reorder."
                            if (!saving) customActions = buildList {
                                if (index > 0) add(CustomAccessibilityAction("Move up") { onMove(index, index - 1); true })
                                if (index < ordered.lastIndex) add(CustomAccessibilityAction("Move down") { onMove(index, index + 1); true })
                            }
                            contentDescription = if (work.author.isEmpty()) {
                                "$position. ${work.title}"
                            } else {
                                "$position. ${work.title}, ${work.author}"
                            }
                        }
                ) {
                    Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Text(
                            text = "$position",
                            color = palette.accent,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.SemiBold,
                            fontFamily = FontFamily.Monospace,
                            modifier = Modifier.widthIn(min = 24.dp)
                        )
                        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(
                                text = work.title,
                                color = tokens.primaryInk,
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Medium,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis
                            )
                            if (work.author.isNotEmpty()) {
                                Text(
                                    text = work.author,
                                    color = tokens.secondaryInk,
                                    fontSize = 12.sp,
                                    maxLines = Int.MAX_VALUE,
                                    overflow = TextOverflow.Clip
                                )
                            }
                        }
                        Icon(Icons.Filled.DragHandle, contentDescription = null, tint = tokens.tertiaryInk,
                            modifier = Modifier.testTag("Collection reorder handle"))
                    }
                    if (index < ordered.lastIndex) {
                        SubjectRowSeparator(modifier = Modifier.testTag("Collection reorder separator"))
                    }
                }
            }

            item {
                Spacer(Modifier.padding(top = 16.dp))
                FormFootnote(
                    "This order is used when no filter is on. Works you add later, or restore from " +
                        "Recently Deleted after tapping Done, appear at the end."
                )
                Spacer(Modifier.padding(bottom = 24.dp))
            }
        }
    }
    }
}
