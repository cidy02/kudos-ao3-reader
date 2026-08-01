package io.github.cidy02.kudos.backup

import android.net.Uri
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
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.ui.components.KudosScreenHeader
import io.github.cidy02.kudos.ui.components.MetadataChipRow
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun BackupScreen(
    repository: BackupRepository
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var statusMessage by remember { mutableStateOf<String?>(null) }
    var statusIsError by remember { mutableStateOf(false) }

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
                statusMessage = "Exported ${bytes.size / 1024} KB as a v2 .kudosbackup ZIP."
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
                val summary = repository.importV2ZipBytes(bytes)
                statusIsError = false
                statusMessage = summary.toUserMessage()
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
            KudosScreenHeader(
                title = "Backup",
                subtitle = "Portable Kudos backups keep Library data, EPUB files, fonts, and settings separate from AO3 session data."
            )
        }
        item {
            BackupInfoCard(
                title = "Compatibility",
                rows = listOf(
                    "Export writes Android v2 ZIP packages with a .kudosbackup name.",
                    "Import accepts v2 ZIP .kudosbackup files (including those from other devices).",
                    "Restore is merge-only and does not delete works that are already on the device."
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
                        labels = listOf("v2 ZIP", "SAF picker", "merge-only", "session excluded"),
                        prominent = true
                    )
                    Text(
                        text = "Export saves a portable library archive. Import merges a chosen " +
                            ".kudosbackup into this device without wiping existing works.",
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
