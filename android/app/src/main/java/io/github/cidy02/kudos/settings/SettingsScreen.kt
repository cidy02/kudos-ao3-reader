package io.github.cidy02.kudos.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Button
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.ui.components.PlaceholderScreen

@Composable
fun SettingsScreen(onOpenBackup: () -> Unit) {
    PlaceholderScreen(
        title = "Settings",
        subtitle = "Preference controls are visual placeholders until DataStore work begins.",
        sections = listOf(
            "Theme is handled in memory for Phase 1 only.",
            "No persistent settings are written by this scaffold.",
            "Backup controls route to the placeholder backup screen."
        )
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Sample toggles")
            Switch(
                checked = false,
                onCheckedChange = {}
            )
            Button(onClick = onOpenBackup) {
                Text("Backup")
            }
        }
    }
}
