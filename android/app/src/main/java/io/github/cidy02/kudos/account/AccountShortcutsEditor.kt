package io.github.cidy02.kudos.account

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.RemoveCircle
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
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
import io.github.cidy02.kudos.ui.subject.*
import io.github.cidy02.kudos.writing.writingSuggestionPanel
import kotlinx.coroutines.launch

@Composable
fun AccountShortcutsEditor(repository: SettingsRepository, onDone: () -> Unit) {
    val chosen by repository.accountShortcuts.collectAsState(initial = AccountShortcutStore.defaults)
    val scope = rememberCoroutineScope()
    AccountShortcutsEditorContent(chosen, { next -> scope.launch { repository.updateAccountShortcuts(next) } }, onDone)
}

@Composable
internal fun AccountShortcutsEditorContent(chosen: List<AccountShortcut>, onChange: (List<AccountShortcut>) -> Unit,
    onDone: () -> Unit) {
    val tokens = LocalKudosTokens.current
    val palette = tokens.scopePalette
    val available = AccountShortcut.entries.filter { it !in chosen }
    ProvidePushedShellChrome(hasSubjectHeader = true, hideTabBar = true, trailingContent = {
        IconButton(onClick = onDone) { Icon(Icons.Default.Check, "Done", tint = palette.accent) }
    })
    LazyColumn(Modifier.fillMaxSize().testTag("Account shortcuts editor").subjectScreenWash(palette), contentPadding = PaddingValues(
        top = WindowInsets.statusBars.asPaddingValues().calculateTopPadding() + 76.dp, bottom = 40.dp)) {
        item {
            SubjectHeaderBlock("AO3 Account", "Shortcuts", palette = palette)
        }
        item { SectionRuleHeader("On the grid", modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter, vertical = 16.dp)) }
        itemsIndexed(chosen) { index, shortcut ->
            Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter)
                .writingSuggestionPanel(first = index == 0, last = index == chosen.lastIndex)) {
                val remove = { onChange(chosen.filterNot { it == shortcut }) }
                val move: (Int) -> Unit = { destination ->
                    val next = chosen.toMutableList()
                    next.add(destination, next.removeAt(index))
                    onChange(next)
                }
                val reorder: @Composable () -> Unit = {
                    IconButton(enabled = index > 0, onClick = { move(index - 1) }) {
                        Icon(Icons.Default.KeyboardArrowUp, "Move ${shortcut.title} up",
                            tint = if (index > 0) palette.accent else tokens.tertiaryInk)
                    }
                    IconButton(enabled = index < chosen.lastIndex, onClick = { move(index + 1) }) {
                        Icon(Icons.Default.KeyboardArrowDown, "Move ${shortcut.title} down",
                            tint = if (index < chosen.lastIndex) palette.accent else tokens.tertiaryInk)
                    }
                }
                if (isAccessibilityFontScale()) {
                    ShortcutEditorRow(shortcut, chosen = true, onClick = remove)
                    Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), horizontalArrangement = Arrangement.End) {
                        reorder()
                    }
                } else ShortcutEditorRow(shortcut, chosen = true, trailing = reorder, onClick = remove)
                if (index < chosen.lastIndex) SubjectRowSeparator()
            }
        }
        if (chosen.isEmpty()) item {
            Text(AccountShortcutStore.emptyFooter, color = tokens.secondaryInk, fontSize = 12.sp, lineHeight = 17.sp,
                modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter + 4.dp))
        }
        if (available.isNotEmpty()) {
            item { SectionRuleHeader("Not on the grid", modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter, vertical = 16.dp)) }
            itemsIndexed(available) { index, shortcut ->
                Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter)
                    .writingSuggestionPanel(first = index == 0, last = index == available.lastIndex)) {
                    ShortcutEditorRow(shortcut, chosen = false) { onChange(chosen + shortcut) }
                    if (index < available.lastIndex) SubjectRowSeparator()
                }
            }
        }
        item {
            val enabled = chosen != AccountShortcutStore.defaults
            Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter, vertical = 20.dp)
                .writingSuggestionPanel(first = true, last = true)) {
                Row(Modifier.fillMaxWidth().clickable(enabled = enabled, role = Role.Button) {
                    onChange(AccountShortcutStore.defaults)
                }.padding(13.dp)) {
                    Text("Reset to Default", color = if (enabled) palette.accent else tokens.tertiaryInk,
                        fontSize = 14.5.sp, lineHeight = 20.sp)
                }
            }
        }
    }
}

@Composable
private fun ShortcutEditorRow(shortcut: AccountShortcut, chosen: Boolean,
    trailing: (@Composable () -> Unit)? = null, onClick: () -> Unit) {
    val tokens = LocalKudosTokens.current
    Row(Modifier.fillMaxWidth().clickable(role = Role.Button, onClick = onClick)
        .semantics(mergeDescendants = true) { contentDescription = "${if (chosen) "Remove" else "Add"} ${shortcut.title}" }
        .padding(13.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(if (chosen) Icons.Default.RemoveCircle else Icons.Default.AddCircle, null,
            tint = SubjectPalette.fromHue(if (chosen) 0.0 else 0.33, tokens.theme).accent)
        Icon(shortcut.icon, null, tint = tokens.primaryInk)
        Text(shortcut.title, Modifier.weight(1f), color = tokens.primaryInk, fontSize = 14.5.sp, lineHeight = 20.sp)
        trailing?.invoke()
    }
}
