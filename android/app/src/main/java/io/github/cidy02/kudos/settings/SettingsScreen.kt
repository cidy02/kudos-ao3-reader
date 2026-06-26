package io.github.cidy02.kudos.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Button
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.ui.components.PlaceholderScreen

@Composable
fun SettingsScreen(onOpenBackup: () -> Unit) {
    val defaults = KudosSettings.Defaults

    PlaceholderScreen(
        title = "Settings",
        subtitle = "DataStore settings scaffolding is present; controls stay placeholder-only.",
        sections = listOf(
            "Default reader mode: ${defaults.reader.readerMode.storageValue}",
            "Default reader font: ${defaults.reader.readerFontId}",
            "Default reader theme: ${defaults.reader.readerTheme.storageValue}",
            "Default mature-content mode: ${defaults.privacy.matureContentMode.storageValue}",
            "Default accent: ${defaults.app.accentColorHex}",
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
