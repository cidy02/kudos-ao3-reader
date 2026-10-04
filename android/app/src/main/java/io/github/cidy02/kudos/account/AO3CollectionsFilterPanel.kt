package io.github.cidy02.kudos.account

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectFieldLabel
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.SubjectSegmentedControl
import io.github.cidy02.kudos.ui.subject.SubjectToggle
import io.github.cidy02.kudos.ui.subject.subjectPanel

/** The sheet owns its draft; dismiss and Cancel resolve to the opening value. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AO3CollectionsFilterPanel(
    initial: AO3CollectionsFilter,
    onFinish: (AO3CollectionsFilter) -> Unit
) {
    val tokens = LocalKudosTokens.current
    val editor = remember { AO3CollectionsFilterDraft(initial) }
    var draft by remember { mutableStateOf(editor.draft) }
    var sortMenuOpen by remember { mutableStateOf(false) }
    fun finish(resolution: AO3CollectionsFilterDraft.Resolution) {
        editor.draft = draft
        onFinish(editor.resolved(resolution))
    }
    ModalBottomSheet(
        onDismissRequest = { finish(AO3CollectionsFilterDraft.Resolution.Cancel) },
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = tokens.background
    ) {
        Column(
            Modifier.fillMaxWidth()
                .padding(horizontal = SubjectMetrics.headerGutter).padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { finish(AO3CollectionsFilterDraft.Resolution.Cancel) }) {
                    Icon(Icons.Default.Close, "Cancel", tint = tokens.accent)
                }
                Text(
                    "Sort and filter", modifier = Modifier.weight(1f),
                    color = tokens.primaryInk, fontSize = 18.sp, fontWeight = FontWeight.SemiBold
                )
                IconButton(
                    onClick = { finish(AO3CollectionsFilterDraft.Resolution.Apply) },
                    enabled = draft != editor.initial
                ) {
                    Icon(
                        Icons.Default.Check, "Apply",
                        tint = if (draft != editor.initial) tokens.accent else tokens.tertiaryInk
                    )
                }
            }
            Column(
                Modifier.fillMaxWidth().heightIn(max = 520.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(18.dp)
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    SubjectFieldLabel("Sort by")
                    Column(Modifier.subjectPanel()) {
                        // The whole row opens the choices, as iOS's picker row does.
                        SubjectFormRow("Order by", onClick = { sortMenuOpen = true }, trailing = {
                            Box {
                                TextButton(onClick = { sortMenuOpen = true }) {
                                    Text(draft.sort.title, color = tokens.accent)
                                }
                                DropdownMenu(
                                    expanded = sortMenuOpen,
                                    onDismissRequest = { sortMenuOpen = false }
                                ) {
                                    AO3CollectionsFilter.Sort.entries.forEach { sort ->
                                        DropdownMenuItem(
                                            text = { Text(sort.title) },
                                            onClick = {
                                                draft = draft.copy(sort = sort)
                                                sortMenuOpen = false
                                            }
                                        )
                                    }
                                }
                            }
                        })
                        if (draft.sort != AO3CollectionsFilter.Sort.AsReturned) {
                            SubjectRowSeparator()
                            SubjectFormRow("Direction", trailing = {
                                SubjectSegmentedControl(
                                    options = AO3CollectionsFilter.Order.entries,
                                    selected = draft.order,
                                    onSelect = { draft = draft.copy(order = it) },
                                    title = { it.title(draft.sort) },
                                    modifier = Modifier.width(180.dp),
                                    contentDescription = "Direction"
                                )
                            })
                        }
                    }
                    if (draft.sort == AO3CollectionsFilter.Sort.RecentlyUpdated) {
                        FilterNote("Recently updated uses the date shown on each AO3 collection. If a date " +
                            "can't be read, that collection stays in AO3's order.")
                    }
                }
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    SubjectFieldLabel("Show only")
                    Column(Modifier.subjectPanel()) {
                        FilterToggleRow("Open to new works", draft.showsOpenOnly) {
                            draft = draft.copy(showsOpenOnly = it)
                        }
                        SubjectRowSeparator()
                        FilterToggleRow("Has works", draft.showsWithWorksOnly) {
                            draft = draft.copy(showsWithWorksOnly = it)
                        }
                        SubjectRowSeparator()
                        FilterToggleRow("Moderated", draft.showsModeratedOnly) {
                            draft = draft.copy(showsModeratedOnly = it)
                        }
                        SubjectRowSeparator()
                        FilterToggleRow("Unrevealed", draft.showsUnrevealedOnly) {
                            draft = draft.copy(showsUnrevealedOnly = it)
                        }
                    }
                    FilterNote("You can turn on more than one of these. Each choice narrows the results further.")
                }
                FilterNote("AO3 doesn't show your role in its collections list, so you can't filter by " +
                    "Maintainer, Member or Invited here.")
            }
            SubjectRowSeparator(inset = 0.dp)
            OutlinedButton(
                onClick = { editor.reset(); draft = editor.draft },
                enabled = draft != AO3CollectionsFilter()
            ) {
                Text("Reset", color = if (draft != AO3CollectionsFilter()) tokens.accent else tokens.tertiaryInk)
            }
        }
    }
}

@Composable
private fun FilterToggleRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    SubjectFormRow(label, trailing = {
        SubjectToggle(checked, onChange, contentDescription = label)
    })
}

@Composable
private fun FilterNote(text: String) {
    Text(text, color = LocalKudosTokens.current.secondaryInk, fontSize = 12.sp, lineHeight = 17.sp)
}
