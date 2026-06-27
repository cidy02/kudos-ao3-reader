package io.github.cidy02.kudos.backup

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

@Composable
fun BackupScreen() {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(text = "Backup", style = MaterialTheme.typography.headlineMedium)
                Text(
                    text = "Portable Kudos backups keep Library data, EPUB files, fonts, and settings separate from AO3 session data.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        item {
            BackupInfoCard(
                title = "Compatibility",
                rows = listOf(
                    "Apple v1 directory manifests can be decoded when Android can access the package.",
                    "Android v2 ZIP .kudosbackup import/export is covered by automated compatibility tests.",
                    "Restore is merge-only and does not delete works that are already on the device."
                )
            )
        }
        item {
            BackupInfoCard(
                title = "Privacy",
                rows = listOf(
                    "AO3 passwords are never stored.",
                    "AO3 cookies, CSRF tokens, and session files are excluded from app/cloud backups.",
                    "Backup import treats ZIP paths and filenames as untrusted input."
                )
            )
        }
        item {
            Card(
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant
                ),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Text("Import and export", style = MaterialTheme.typography.titleMedium)
                    Text(
                        text = "The compatibility engine is ready. Android document picker wiring still needs device verification before import/export buttons are enabled.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        OutlinedButton(enabled = false, onClick = {}, modifier = Modifier.weight(1f)) {
                            Text("Import")
                        }
                        OutlinedButton(enabled = false, onClick = {}, modifier = Modifier.weight(1f)) {
                            Text("Export")
                        }
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
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
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
