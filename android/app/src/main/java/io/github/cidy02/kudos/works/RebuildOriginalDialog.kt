package io.github.cidy02.kudos.works

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.network.ao3.displayMessage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Shared by the card menu, Work Detail and My copy. */
@Composable
fun RebuildOriginalDialog(
    work: SavedWork,
    importer: WorkImporter,
    onRebuilt: (SavedWork) -> Unit = {},
    onDismiss: () -> Unit
) {
    val scope = rememberCoroutineScope()
    var working by remember(work.id) { mutableStateOf(false) }
    var error by remember(work.id) { mutableStateOf<String?>(null) }
    AlertDialog(
        onDismissRequest = { if (!working) onDismiss() },
        title = { Text(if (error == null) "Rebuild this work?" else "Couldn't Rebuild") },
        text = {
            // Android has no converter-version stamp; ask even when its age is unknown.
            Text(error ?: "Rebuilding probably won't change this work if it already uses the latest version. " +
                "Try rebuilding if its text or details look wrong. Kudos will use the original file you " +
                "imported and keep your progress, tags, and collections.")
        },
        confirmButton = {
            TextButton(enabled = !working, onClick = {
                if (error != null) {
                    onDismiss()
                } else {
                    working = true
                    scope.launch {
                        try {
                            when (val result = withContext(Dispatchers.IO) { importer.rebuildFromOriginal(work) }) {
                                is WorkImportResult.Success -> {
                                    onRebuilt(result.work)
                                    onDismiss()
                                }
                                is WorkImportResult.Failure -> error = result.error.displayMessage()
                            }
                        } catch (cancelled: CancellationException) {
                            throw cancelled
                        } catch (failure: Exception) {
                            error = failure.message ?: "The original file couldn't be rebuilt."
                        } finally {
                            working = false
                        }
                    }
                }
            }) { Text(if (error != null) "OK" else if (working) "Rebuilding…" else "Rebuild") }
        },
        dismissButton = {
            if (error == null) TextButton(enabled = !working, onClick = onDismiss) { Text("Cancel") }
        }
    )
}
