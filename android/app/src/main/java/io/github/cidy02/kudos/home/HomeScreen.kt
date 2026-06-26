package io.github.cidy02.kudos.home

import androidx.compose.runtime.Composable
import io.github.cidy02.kudos.ui.components.PlaceholderScreen
import io.github.cidy02.kudos.ui.components.WorkCardPlaceholder

@Composable
fun HomeScreen(
    onOpenWork: () -> Unit,
    onOpenLibrary: () -> Unit
) {
    PlaceholderScreen(
        title = "Welcome back",
        subtitle = "A native Android shell for the Kudos reader is ready for Phase 1 review.",
        sections = listOf(
            "Continue Reading is a placeholder until the reader and persistence phases land.",
            "Recent AO3 results will remain stubbed until networking and parsing are approved.",
            "This screen preserves the intended Home route without importing Apple behavior."
        ),
        primaryActionLabel = "Open Library",
        onPrimaryAction = onOpenLibrary
    ) {
        WorkCardPlaceholder(
            title = "Placeholder Work",
            author = "AO3 Author",
            metadata = "Mature - 42,000 words - Complete",
            summary = "Representative card layout for search, browse, and library surfaces.",
            onOpenWork = onOpenWork
        )
    }
}
