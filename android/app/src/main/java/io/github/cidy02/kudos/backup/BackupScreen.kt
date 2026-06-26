package io.github.cidy02.kudos.backup

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.ui.components.PlaceholderScreen

@Composable
fun BackupScreen() {
    PlaceholderScreen(
        title = "Backup",
        subtitle = "Backup import and export are documented but not implemented in Phase 1.",
        sections = listOf(
            "Apple v1 facts and Android v2 additions live in BACKUP_FORMAT.md.",
            "No JSON serializers, filesystem access, or cloud storage integration exists yet.",
            "Future work must avoid labeling v2-only fields as v1 parity."
        )
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Button(
                enabled = false,
                onClick = {}
            ) {
                Text("Import unavailable")
            }
            OutlinedButton(
                enabled = false,
                onClick = {}
            ) {
                Text("Export unavailable")
            }
        }
    }
}
