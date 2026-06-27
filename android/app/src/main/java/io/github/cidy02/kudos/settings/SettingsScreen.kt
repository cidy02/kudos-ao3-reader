package io.github.cidy02.kudos.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.ui.components.KudosScreenHeader
import kotlinx.coroutines.launch

@Composable
fun SettingsScreen(
    repository: SettingsRepository,
    onOpenBackup: () -> Unit
) {
    val settings by repository.settings.collectAsState(initial = KudosSettings.Defaults)
    val scope = rememberCoroutineScope()

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            KudosScreenHeader(
                title = "Settings",
                subtitle = "Reader, privacy, and backup-compatible app preferences."
            )
        }
        item {
            SettingsGroup(title = "Reader") {
                SettingRow("Mode", settings.reader.readerMode.storageValue)
                SettingRow("Reader theme", settings.reader.readerTheme.storageValue)
                SettingRow("Font", settings.reader.readerFontId)
                SettingRow("Text size", "${settings.reader.readerFontPt} pt")
                SettingRow("Line height", settings.reader.readerLineHeight.toString())
                SettingRow("Margin", "${settings.reader.readerMargin} pt")
                SettingRow("Justified text", yesNo(settings.reader.readerJustify))
                SettingRow("Match app theme", yesNo(settings.reader.matchAppReaderTheme))
            }
        }
        item {
            SettingsGroup(title = "Privacy") {
                SettingRow("Hide mature content", yesNo(settings.privacy.hideMatureContent))
                SettingRow("Mature content mode", settings.privacy.matureContentMode.storageValue)
                SettingRow("Require device reveal", yesNo(settings.privacy.requireBiometricToReveal))
            }
        }
        item {
            SettingsGroup(title = "App") {
                SettingRow("App theme", settings.app.appTheme.storageValue)
                SettingRow("Accent color", settings.app.accentColorHex)
                SettingRow("Confirm before delete", yesNo(settings.app.confirmBeforeDelete))
            }
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
                    Text("Backup and reset", style = MaterialTheme.typography.titleMedium)
                    Text(
                        text = "Settings use the same field names and defaults as the cross-platform backup contract.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Button(onClick = onOpenBackup, modifier = Modifier.weight(1f)) {
                            Text("Backup")
                        }
                        OutlinedButton(
                            onClick = { scope.launch { repository.resetToDefaults() } },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("Reset")
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SettingsGroup(
    title: String,
    content: @Composable ColumnScope.() -> Unit
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(text = title, style = MaterialTheme.typography.titleMedium)
            content()
        }
    }
}

@Composable
private fun SettingRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.weight(1f)
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

private fun yesNo(value: Boolean): String = if (value) "On" else "Off"
