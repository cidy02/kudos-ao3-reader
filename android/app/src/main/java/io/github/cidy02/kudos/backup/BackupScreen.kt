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
        subtitle = "Backup compatibility services are present; Android document picker wiring is deferred.",
        sections = listOf(
            "Apple v1 directory manifests can be decoded where Android can access the package.",
            "Android v2 ZIP .kudosbackup import/export and merge logic are covered by JVM tests.",
            "Storage Access Framework and production restore UI remain later-phase work."
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
