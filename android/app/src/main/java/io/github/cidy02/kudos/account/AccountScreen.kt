package io.github.cidy02.kudos.account

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.ui.components.PlaceholderScreen

@Composable
fun AccountScreen(
    onOpenBackup: () -> Unit,
    onOpenSettings: () -> Unit
) {
    PlaceholderScreen(
        title = "Account",
        subtitle = "AO3 sign-in is intentionally out of scope for Phase 1.",
        sections = listOf(
            "No cookies, credentials, subscriptions, or bookmarks are stored yet.",
            "Future auth work must follow the contracts before touching network behavior.",
            "Settings and backup routes are reachable for shell review only."
        )
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Button(onClick = onOpenSettings) {
                Text("Settings")
            }
            OutlinedButton(onClick = onOpenBackup) {
                Text("Backup")
            }
        }
    }
}
