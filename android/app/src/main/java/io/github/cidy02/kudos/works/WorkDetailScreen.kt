package io.github.cidy02.kudos.works

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.ui.components.PlaceholderScreen

@Composable
fun WorkDetailScreen(onOpenReader: () -> Unit) {
    PlaceholderScreen(
        title = "Placeholder Work",
        subtitle = "Representative work detail route for Phase 1 navigation.",
        sections = listOf(
            "Rating: Mature",
            "Warnings: Creator chose not to use archive warnings",
            "Words: 42,000",
            "Chapters: 12/12",
            "Summary: This screen reserves space for AO3 metadata, actions, and reader entry."
        )
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Button(onClick = onOpenReader) {
                Text("Open Reader Placeholder")
            }
            OutlinedButton(
                enabled = false,
                onClick = {}
            ) {
                Text("Download unavailable")
            }
        }
    }
}
