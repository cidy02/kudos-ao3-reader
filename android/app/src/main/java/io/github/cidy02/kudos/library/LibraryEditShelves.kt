package io.github.cidy02.kudos.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.outlined.RemoveCircleOutline
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import io.github.cidy02.kudos.core.model.LibraryPageArrangement
import io.github.cidy02.kudos.core.model.LibraryShelf
import io.github.cidy02.kudos.core.model.LibraryStyleCarousel
import io.github.cidy02.kudos.core.model.LibraryStyleList

/** Name a shelf id shows under. */
internal fun shelfTitle(id: String): String = LibraryShelf.fromId(id)?.title ?: id

/**
 * A shelf this build can draw. `imported` has no screen on Android yet and an unknown id comes from a
 * newer app: both stay in the stored layout (so they round-trip) but are neither drawn nor editable.
 */
internal fun isShelfSupported(id: String): Boolean =
    LibraryShelf.fromId(id) != null && id != LibraryShelf.Imported.id

internal typealias ArrangementEdit = (LibraryPageArrangement) -> LibraryPageArrangement

/** Move the shelf [id] to where [targetId] is, in whatever the latest stored layout is. */
internal fun moveSectionTo(id: String, targetId: String): ArrangementEdit = { cur ->
    val from = cur.sections.indexOfFirst { it.id == id }
    val to = cur.sections.indexOfFirst { it.id == targetId }
    if (from < 0 || to < 0) cur else cur.movingSection(from, to)
}

internal fun moveButtonTo(id: String, targetId: String): ArrangementEdit = { cur ->
    val from = cur.buttons.indexOf(id)
    val to = cur.buttons.indexOf(targetId)
    if (from < 0 || to < 0) cur else cur.movingButton(from, to)
}

/**
 * iOS Edit Shelves: show/hide, Carousel/List, and reorder (Move up/down, with TalkBack actions).
 * Each edit is a transform of the latest stored layout, so two quick taps both land.
 */
@Composable
internal fun LibraryEditShelvesDialog(
    arrangement: LibraryPageArrangement,
    onEdit: (ArrangementEdit) -> Unit,
    onDismiss: () -> Unit
) {
    val sections = arrangement.sections.filter { isShelfSupported(it.id) }
    val buttons = arrangement.buttons.filter(::isShelfSupported)
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Column(Modifier.windowInsetsPadding(WindowInsets.systemBars)) {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("Edit Shelves", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                    TextButton(onClick = onDismiss) { Text("Done") }
                }
                LazyColumn(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    item { EditHeader("On the Library page") }
                    if (sections.isEmpty()) item {
                        Text("Nothing is on the page. Add a shelf below.", Modifier.padding(16.dp))
                    }
                    items(sections.size) { i ->
                        val s = sections[i]
                        val title = shelfTitle(s.id)
                        val list = s.style == LibraryStyleList
                        val up = sections.getOrNull(i - 1)?.id
                        val down = sections.getOrNull(i + 1)?.id
                        EditRow(
                            title = title,
                            onUp = up?.let { t -> { onEdit(moveSectionTo(s.id, t)) } },
                            onDown = down?.let { t -> { onEdit(moveSectionTo(s.id, t)) } },
                            actionIcon = Icons.Outlined.RemoveCircleOutline,
                            actionLabel = "Remove $title from the Library page",
                            onAction = { onEdit { it.removingFromPage(s.id) } },
                            trailing = {
                                TextButton(
                                    onClick = {
                                        onEdit { it.settingStyle(s.id, if (list) LibraryStyleCarousel else LibraryStyleList) }
                                    },
                                    modifier = Modifier.semantics {
                                        contentDescription = "Style for $title, ${if (list) "List" else "Carousel"}"
                                    }
                                ) { Text(if (list) "List" else "Carousel") }
                            }
                        )
                    }
                    item { EditHeader("As shelf buttons") }
                    if (buttons.isEmpty()) item {
                        Text("Every shelf is on the page.", Modifier.padding(16.dp))
                    }
                    items(buttons.size) { i ->
                        val id = buttons[i]
                        val title = shelfTitle(id)
                        val up = buttons.getOrNull(i - 1)
                        val down = buttons.getOrNull(i + 1)
                        EditRow(
                            title = title,
                            onUp = up?.let { t -> { onEdit(moveButtonTo(id, t)) } },
                            onDown = down?.let { t -> { onEdit(moveButtonTo(id, t)) } },
                            actionIcon = Icons.Filled.Add,
                            actionLabel = "Show $title on the Library page",
                            onAction = { onEdit { it.addingToPage(id) } }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun EditHeader(text: String) {
    Text(text, style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
}

/** [onUp]/[onDown] are null at the ends. At large font the style control moves to its own line. */
@Composable
private fun EditRow(
    title: String,
    onUp: (() -> Unit)?,
    onDown: (() -> Unit)?,
    actionIcon: androidx.compose.ui.graphics.vector.ImageVector,
    actionLabel: String,
    onAction: () -> Unit,
    trailing: @Composable () -> Unit = {}
) {
    val actions = buildList {
        if (onUp != null) add(CustomAccessibilityAction("Move $title up") { onUp(); true })
        if (onDown != null) add(CustomAccessibilityAction("Move $title down") { onDown(); true })
    }
    val large = LocalDensity.current.fontScale >= 1.3f
    Column(Modifier.fillMaxWidth().padding(horizontal = 8.dp).semantics { customActions = actions }) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onAction) { Icon(actionIcon, contentDescription = actionLabel) }
            Text(title, Modifier.weight(1f).padding(horizontal = 4.dp))
            if (!large) trailing()
            IconButton(onClick = { onUp?.invoke() }, enabled = onUp != null) {
                Icon(Icons.Filled.KeyboardArrowUp, "Move $title up")
            }
            IconButton(onClick = { onDown?.invoke() }, enabled = onDown != null) {
                Icon(Icons.Filled.KeyboardArrowDown, "Move $title down")
            }
        }
        if (large) Row(Modifier.padding(start = 48.dp)) { trailing() }
    }
}
