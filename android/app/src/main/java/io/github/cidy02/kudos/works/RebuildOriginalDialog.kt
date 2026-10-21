package io.github.cidy02.kudos.works

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.LaunchedEffect
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
    var checking by remember(work.id) { mutableStateOf(true) }
    suspend fun rebuild() {
        working = true
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
    LaunchedEffect(work.id) {
        val stale = importer.conversionIsStale(work)
        checking = false
        if (stale) rebuild()
    }
    // A stale copy rebuilds immediately; only a current copy asks for confirmation.
    if (checking) return
    AlertDialog(
        onDismissRequest = { if (!working) onDismiss() },
        title = { Text(if (error != null) "Couldn't Rebuild" else if (working) "Rebuilding…" else "Rebuild this work?") },
        text = {
            Text(error ?: if (working) "Kudos has a newer way to build this work. Rebuilding reads the original " +
                "file again and keeps your progress, tags, and collections."
            else "This work already uses the latest way Kudos builds imported files, so its " +
                "text will probably not change. If its details look wrong, rebuilding " +
                "reads everything from the original file again.")
        },
        confirmButton = {
            TextButton(enabled = !working, onClick = {
                if (error != null) onDismiss() else scope.launch { rebuild() }
            }) { Text(if (error != null) "OK" else if (working) "Rebuilding…" else "Rebuild") }
        },
        dismissButton = {
            if (error == null) TextButton(enabled = !working, onClick = onDismiss) { Text("Cancel") }
        }
    )
}
