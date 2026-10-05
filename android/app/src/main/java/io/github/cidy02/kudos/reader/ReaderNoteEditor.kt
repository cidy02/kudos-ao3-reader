package io.github.cidy02.kudos.reader

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.core.model.ReadingAnnotation
import io.github.cidy02.kudos.settings.SettingsActionRow
import io.github.cidy02.kudos.settings.SettingsSection
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.ToolbarCircleButton
import io.github.cidy02.kudos.ui.theme.Ao3Red

/** Contents' note editor, also opened by a page highlight (iOS ReaderNoteEditor). */
@Composable
internal fun ReaderNoteEditor(
    annotation: ReadingAnnotation,
    onCancel: () -> Unit,
    onDone: (String) -> Unit,
    onColorChange: (String) -> Unit,
    onDelete: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    var draft by remember(annotation.id) { mutableStateOf(annotation.note) }
    val focus = remember(annotation.id) { FocusRequester() }
    val color = ReadingAnnotationColor.fromRaw(annotation.colorRaw)

    Column(
        Modifier.fillMaxWidth().imePadding().verticalScroll(rememberScrollState())
            .navigationBarsPadding().padding(bottom = 24.dp)
    ) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = SubjectMetrics.accountGutter),
            verticalAlignment = Alignment.CenterVertically
        ) {
            TextButton(onClick = onCancel) { Text("Cancel", color = tokens.accent) }
            Text(
                if (annotation.note.isBlank()) "Add Note" else "Edit Note",
                modifier = Modifier.weight(1f),
                color = tokens.primaryInk,
                fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold
            )
            ToolbarCircleButton(onClick = { onDone(draft.trim()) }, accessibilityName = "Done") {
                Icon(Icons.Filled.Check, contentDescription = null)
            }
        }
        if (annotation.selectedText.isNotEmpty()) {
            SettingsSection(footnote = null, label = "Highlighted", top = 14.dp) {
                Row(
                    Modifier.fillMaxWidth().padding(13.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Box(Modifier.size(width = 3.dp, height = 24.dp)
                        .background(color.color, RoundedCornerShape(2.dp)))
                    Text(annotation.selectedText, color = tokens.primaryInk, fontSize = 14.sp)
                }
            }
        }
        SettingsSection(footnote = null, label = "Note") {
            BasicTextField(
                value = draft,
                onValueChange = { draft = it },
                textStyle = TextStyle(color = tokens.primaryInk, fontSize = 16.sp),
                cursorBrush = SolidColor(tokens.accent),
                modifier = Modifier.fillMaxWidth().padding(13.dp).heightIn(min = 120.dp)
                    .focusRequester(focus).semantics { contentDescription = "Note" }
            )
        }
        SettingsSection(footnote = null, label = "Colour") {
            Row(
                Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(9.dp),
                horizontalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                ReadingAnnotationColor.entries.forEach { option ->
                    val selected = color == option
                    Box(
                        Modifier.size(44.dp)
                            .selectable(selected = selected, role = Role.RadioButton,
                                onClick = { onColorChange(option.raw) })
                            .semantics { contentDescription = option.displayName },
                        contentAlignment = Alignment.Center
                    ) {
                        Box(
                            Modifier.size(32.dp)
                                .then(if (option == ReadingAnnotationColor.UNDERLINE) Modifier
                                    else Modifier.background(option.color, CircleShape))
                                .border(if (selected) 3.dp else 1.dp,
                                    if (selected) tokens.accent else tokens.primaryInk.copy(alpha = 0.12f),
                                    CircleShape),
                            contentAlignment = Alignment.Center
                        ) {
                            if (option == ReadingAnnotationColor.UNDERLINE) {
                                Box(Modifier.size(width = 20.dp, height = 3.dp).background(option.color))
                            }
                        }
                    }
                }
            }
        }
        SettingsSection(footnote = null) {
            // Explicit app red, not the ambient Material error colour over a reader page.
            MaterialTheme(colorScheme = MaterialTheme.colorScheme.copy(error = Ao3Red)) {
                SettingsActionRow("Delete Highlight", onClick = onDelete,
                    icon = Icons.Filled.Delete, destructive = true)
            }
        }
    }
    LaunchedEffect(annotation.id) { focus.requestFocus() }
}
