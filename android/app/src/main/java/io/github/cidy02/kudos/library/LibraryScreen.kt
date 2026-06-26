package io.github.cidy02.kudos.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.ui.components.PlaceholderScreen
import io.github.cidy02.kudos.ui.components.WorkCardPlaceholder

@Composable
fun LibraryScreen(
    onOpenWork: () -> Unit,
    onOpenReader: () -> Unit
) {
    PlaceholderScreen(
        title = "Library",
        subtitle = "Saved works, collections, and reading progress will be wired in later phases.",
        sections = listOf(
            "Room schema exists, but production Library queries are still deferred.",
            "Cards here are static placeholders for navigation and layout review.",
            "Reader progress contract fields remain lastSpineIndex and lastScrollFraction."
        ),
        primaryActionLabel = "Open Reader Placeholder",
        onPrimaryAction = onOpenReader
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            WorkCardPlaceholder(
                title = "Downloaded Work Placeholder",
                author = "Library Author",
                metadata = "Teen - 12 chapters - last read chapter 3",
                summary = "Static library row showing where offline works will appear.",
                onOpenWork = onOpenWork
            )
        }
    }
}
