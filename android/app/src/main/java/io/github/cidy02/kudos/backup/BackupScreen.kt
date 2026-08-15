package io.github.cidy02.kudos.backup

import android.net.Uri
import android.os.Environment
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.ui.components.KudosScreenHeader
import io.github.cidy02.kudos.ui.components.MetadataChipRow
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun BackupScreen(
    repository: BackupRepository,
    settingsRepository: SettingsRepository
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var statusMessage by remember { mutableStateOf<String?>(null) }
    var statusIsError by remember { mutableStateOf(false) }
    var pendingImport by remember { mutableStateOf<PendingBackupImport?>(null) }

    val exportLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.CreateDocument("application/zip")
    ) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            busy = true
            statusMessage = null
            try {
                val bytes = repository.exportV2ZipBytes()
                withContext(Dispatchers.IO) {
                    context.contentResolver.openOutputStream(uri)?.use { out ->
                        out.write(bytes)
                        out.flush()
                    } ?: error("Could not open the chosen location for writing.")
                }
                statusIsError = false
                statusMessage =
                    "Exported ${bytes.size / 1024} KB as a v${BackupVersion.CURRENT} .kudosbackup ZIP."
            } catch (error: Exception) {
                statusIsError = true
                statusMessage = userFacingError("Export failed", error)
            } finally {
                busy = false
            }
        }
    }

    val importLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            busy = true
            statusMessage = null
            try {
                val bytes = withContext(Dispatchers.IO) {
                    context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                        ?: error("Could not read the selected file.")
                }
                val pack = withContext(Dispatchers.IO) { BackupImporter.importV2Zip(bytes) }
                val preview = repository.previewImport(pack)
                val syncEnabled = settingsRepository.settings.first().sync.isEnabled
                pendingImport = PendingBackupImport(
                    bytes = bytes,
                    preview = preview,
                    syncEnabled = syncEnabled
                )
            } catch (error: Exception) {
                statusIsError = true
                statusMessage = userFacingError("Import failed", error)
            } finally {
                busy = false
            }
        }
    }

    fun clearPendingImport() {
        pendingImport = null
    }

    fun runImport(mode: BackupImportMode, pauseSync: Boolean) {
        val pending = pendingImport
        clearPendingImport()
        if (pending == null) return
        scope.launch {
            busy = true
            statusMessage = null
            try {
                var safetyName: String? = null
                if (mode == BackupImportMode.REPLACE_LIBRARY) {
                    val docs = context.getExternalFilesDir(Environment.DIRECTORY_DOCUMENTS)
                        ?: File(context.filesDir, "Documents").also { it.mkdirs() }
                    docs.mkdirs()
                    val file = File(docs, repository.suggestedSafetyBackupFileName())
                    val safetyBytes = repository.exportV2ZipBytes()
                    withContext(Dispatchers.IO) { file.writeBytes(safetyBytes) }
                    safetyName = file.name
                    if (pauseSync && pending.syncEnabled) {
                        settingsRepository.updateSyncIsEnabled(false)
                    }
                }
                val summary = repository.importV2ZipBytes(pending.bytes, mode)
                statusIsError = false
                statusMessage = buildString {
                    append(summary.toUserMessage())
                    if (safetyName != null) {
                        append(" Current library saved as ")
                        append(safetyName)
                        append(" first.")
                    }
                    if (pauseSync && pending.syncEnabled) {
                        append(" Sync paused on this device.")
                    }
                }
            } catch (error: Exception) {
                statusIsError = true
                statusMessage = userFacingError("Import failed", error)
            } finally {
                busy = false
            }
        }
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            // TopAppBar already says "Backup"; keep privacy/compatibility guidance only.
            KudosScreenHeader(
                subtitle = "Portable Kudos backups keep Library data, EPUB files, fonts, and settings separate from AO3 session data."
            )
        }
        item {
            BackupInfoCard(
                title = "Compatibility",
                rows = listOf(
                    "Export writes ZIP packages at manifest v${BackupVersion.CURRENT} (Apple-compatible).",
                    "Import accepts Apple/Android .kudosbackup ZIP versions ${BackupVersion.APPLE_V1}–${BackupVersion.CURRENT}.",
                    "Merge adds works that are not already here. Replace Library makes this device match the file.",
                    "Unsigned deletion claims in a backup or sync folder are ignored until signed tombstones ship."
                )
            )
        }
        item {
            BackupInfoCard(
                title = "Privacy",
                rows = listOf(
                    "AO3 passwords are never stored.",
                    "AO3 cookies, CSRF tokens, and session files are excluded from backups.",
                    "Backup import treats ZIP paths and filenames as untrusted input."
                )
            )
        }
        item {
            Card(
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainerLow
                ),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Text("Import and export", style = MaterialTheme.typography.titleMedium)
                    MetadataChipRow(
                        labels = listOf(
                            "v${BackupVersion.CURRENT} ZIP",
                            "v1–v${BackupVersion.CURRENT} import",
                            "SAF picker",
                            "merge or replace",
                            "session excluded"
                        ),
                        prominent = true
                    )
                    Text(
                        text = "Export saves a portable library archive. Import can merge new works " +
                            "or replace this device's library. Unsigned tombstones in the file are not applied.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        OutlinedButton(
                            enabled = !busy,
                            onClick = {
                                importLauncher.launch(
                                    arrayOf(
                                        "application/zip",
                                        "application/octet-stream",
                                        "*/*"
                                    )
                                )
                            },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("Import")
                        }
                        Button(
                            enabled = !busy,
                            onClick = {
                                exportLauncher.launch(repository.suggestedExportFileName())
                            },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("Export")
                        }
                    }
                    if (busy) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            CircularProgressIndicator()
                            Text(
                                text = "Working…",
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                    statusMessage?.let { message ->
                        Text(
                            text = message,
                            style = MaterialTheme.typography.bodyMedium,
                            color = if (statusIsError) {
                                MaterialTheme.colorScheme.error
                            } else {
                                MaterialTheme.colorScheme.primary
                            }
                        )
                    }
                }
            }
        }
    }

    pendingImport?.let { pending ->
        ImportBackupDialog(
            pending = pending,
            onDismiss = { clearPendingImport() },
            onMerge = { runImport(BackupImportMode.MERGE, pauseSync = false) },
            onReplace = { pauseSync ->
                runImport(BackupImportMode.REPLACE_LIBRARY, pauseSync = pauseSync)
            }
        )
    }
}

private data class PendingBackupImport(
    val bytes: ByteArray,
    val preview: BackupImportPreview,
    val syncEnabled: Boolean
)

@Composable
private fun ImportBackupDialog(
    pending: PendingBackupImport,
    onDismiss: () -> Unit,
    onMerge: () -> Unit,
    onReplace: (pauseSync: Boolean) -> Unit
) {
    val preview = pending.preview
    if (preview.isLibraryEmpty) {
        AlertDialog(
            onDismissRequest = onDismiss,
            title = { Text("Restore from Backup") },
            text = {
                Text(
                    "This library is empty. Restore ${preview.fileWorkCount} work(s) from the selected backup."
                )
            },
            confirmButton = {
                TextButton(onClick = onMerge) { Text("Restore from Backup") }
            },
            dismissButton = {
                TextButton(onClick = onDismiss) { Text("Cancel") }
            }
        )
    } else {
        ReplaceOrMergeDialog(
            pending = pending,
            onDismiss = onDismiss,
            onMerge = onMerge,
            onReplace = onReplace
        )
    }
}

@Composable
private fun ReplaceOrMergeDialog(
    pending: PendingBackupImport,
    onDismiss: () -> Unit,
    onMerge: () -> Unit,
    onReplace: (pauseSync: Boolean) -> Unit
) {
    val preview = pending.preview
    var acknowledgeRemoval by remember { mutableStateOf(false) }
    var pauseSync by remember { mutableStateOf(true) }
    var replaceArmed by remember { mutableStateOf(false) }
    LaunchedEffect(acknowledgeRemoval, preview.willRemove) {
        replaceArmed = false
        if (preview.willRemove == 0 || acknowledgeRemoval) {
            delay(1_500)
            replaceArmed = true
        }
    }
    val replaceEnabled = replaceArmed && (preview.willRemove == 0 || acknowledgeRemoval)

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Import this backup?") },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Text(
                    "Library: ${preview.localWorkCount} works. File: ${preview.fileWorkCount} works. " +
                        "Will add ${preview.willAdd}. Will remove ${preview.willRemove}. " +
                        "In both: ${preview.inBoth}."
                )
                Text(
                    "Merge adds works that are not already here. It does not delete local works " +
                        "or apply unsigned deletion claims from the file."
                )
                if (preview.isMuchSmallerThanLibrary) {
                    Text(
                        "This backup is much smaller than your library.",
                        color = MaterialTheme.colorScheme.tertiary
                    )
                }
                if (preview.willRemove > 0) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(
                            checked = acknowledgeRemoval,
                            onCheckedChange = { acknowledgeRemoval = it }
                        )
                        Text("Remove ${preview.willRemove} works that are not in this backup.")
                    }
                }
                if (pending.syncEnabled) {
                    Text("Sync will put removed works back. Pause sync for this device?")
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(
                            checked = pauseSync,
                            onCheckedChange = { pauseSync = it }
                        )
                        Text("Pause sync (recommended). The sync folder is not wiped.")
                    }
                }
            }
        },
        confirmButton = {
            Column(horizontalAlignment = Alignment.End) {
                TextButton(onClick = onMerge) { Text("Merge") }
                TextButton(
                    onClick = { onReplace(pending.syncEnabled && pauseSync) },
                    enabled = replaceEnabled,
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.error
                    )
                ) {
                    Text("Replace Library")
                }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        }
    )
}

@Composable
private fun BackupInfoCard(
    title: String,
    rows: List<String>
) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow
        ),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(text = title, style = MaterialTheme.typography.titleMedium)
            rows.forEach { row ->
                Text(
                    text = row,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

private fun userFacingError(prefix: String, error: Throwable): String {
    val detail = when (error) {
        is BackupError -> error.message
        else -> error.message
    }?.takeIf { it.isNotBlank() } ?: error::class.simpleName ?: "Unknown error"
    return "$prefix: $detail"
}
