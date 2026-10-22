package io.github.cidy02.kudos.writing

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens

/** System Back and the shell button must ask the same question before dropping a draft. */
@Composable
internal fun rememberWritingFormBack(owner: Any, hasChanges: Boolean, onBack: () -> Unit): () -> Unit {
    var confirming by remember(owner) { mutableStateOf(false) }
    val tokens = LocalKudosTokens.current
    if (confirming) {
        AlertDialog(
            onDismissRequest = { confirming = false },
            containerColor = tokens.cardFill,
            titleContentColor = tokens.primaryInk,
            textContentColor = tokens.secondaryInk,
            title = { Text("Discard unsaved changes?") },
            text = { Text("Your changes haven't been saved to AO3.") },
            confirmButton = {
                TextButton(onClick = { confirming = false; onBack() }) {
                    Text("Discard changes", color = tokens.scopePalette.accent)
                }
            },
            dismissButton = { TextButton(onClick = { confirming = false }) {
                Text("Keep editing", color = tokens.scopePalette.accent)
            } }
        )
    }
    return { if (hasChanges) confirming = true else onBack() }
}
