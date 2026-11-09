package io.github.cidy02.kudos.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
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
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import io.github.cidy02.kudos.core.model.LibraryPageArrangement
import io.github.cidy02.kudos.core.model.LibraryShelf
import io.github.cidy02.kudos.core.model.LibraryStyleCarousel
import io.github.cidy02.kudos.core.model.LibraryStyleList

/** Name a shelf id shows under: an id this build does not know shows as its raw id. */
internal fun shelfTitle(id: String): String = LibraryShelf.fromId(id)?.title ?: id

/** iOS Edit Shelves: show/hide, Carousel/List, and reorder (Move up/down, with TalkBack actions). */
@Composable
internal fun LibraryEditShelvesDialog(
    arrangement: LibraryPageArrangement,
    onChange: (LibraryPageArrangement) -> Unit,
    onDismiss: () -> Unit
) {
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Column {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("Edit Shelves", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                    TextButton(onClick = onDismiss) { Text("Done") }
                }
                LazyColumn(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    item { EditHeader("On the Library page") }
                    if (arrangement.sections.isEmpty()) item {
                        Text("Nothing is on the page. Add a shelf below.", Modifier.padding(16.dp))
                    }
                    items(arrangement.sections.size) { i ->
                        val s = arrangement.sections[i]
                        val title = shelfTitle(s.id)
                        val list = s.style == LibraryStyleList
                        EditRow(
                            title = title,
                            canUp = i > 0,
                            canDown = i < arrangement.sections.lastIndex,
                            onUp = { onChange(arrangement.movingSection(i, i - 1)) },
                            onDown = { onChange(arrangement.movingSection(i, i + 1)) },
                            actionIcon = Icons.Outlined.RemoveCircleOutline,
                            actionLabel = "Remove $title from the Library page",
                            onAction = { onChange(arrangement.removingFromPage(s.id)) },
                            trailing = {
                                TextButton(onClick = {
                                    onChange(arrangement.settingStyle(s.id, if (list) LibraryStyleCarousel else LibraryStyleList))
                                }) { Text(if (list) "List" else "Carousel") }
                            }
                        )
                    }
                    item { EditHeader("As shelf buttons") }
                    if (arrangement.buttons.isEmpty()) item {
                        Text("Every shelf is on the page.", Modifier.padding(16.dp))
                    }
                    items(arrangement.buttons.size) { i ->
                        val id = arrangement.buttons[i]
                        val title = shelfTitle(id)
                        EditRow(
                            title = title,
                            canUp = i > 0,
                            canDown = i < arrangement.buttons.lastIndex,
                            onUp = { onChange(arrangement.movingButton(i, i - 1)) },
                            onDown = { onChange(arrangement.movingButton(i, i + 1)) },
                            actionIcon = Icons.Filled.Add,
                            actionLabel = "Show $title on the Library page",
                            onAction = { onChange(arrangement.addingToPage(id)) }
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

@Composable
private fun EditRow(
    title: String,
    canUp: Boolean,
    canDown: Boolean,
    onUp: () -> Unit,
    onDown: () -> Unit,
    actionIcon: androidx.compose.ui.graphics.vector.ImageVector,
    actionLabel: String,
    onAction: () -> Unit,
    trailing: @Composable () -> Unit = {}
) {
    val actions = buildList {
        if (canUp) add(CustomAccessibilityAction("Move $title up") { onUp(); true })
        if (canDown) add(CustomAccessibilityAction("Move $title down") { onDown(); true })
    }
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 8.dp).semantics { customActions = actions },
        verticalAlignment = Alignment.CenterVertically
    ) {
        IconButton(onClick = onAction) { Icon(actionIcon, contentDescription = actionLabel) }
        Text(title, Modifier.weight(1f).padding(horizontal = 4.dp))
        trailing()
        IconButton(onClick = onUp, enabled = canUp) { Icon(Icons.Filled.KeyboardArrowUp, "Move $title up") }
        IconButton(onClick = onDown, enabled = canDown) { Icon(Icons.Filled.KeyboardArrowDown, "Move $title down") }
    }
}
