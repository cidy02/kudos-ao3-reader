package io.github.cidy02.kudos.browse

import androidx.compose.runtime.Composable
import io.github.cidy02.kudos.ui.components.PlaceholderScreen
import io.github.cidy02.kudos.ui.components.WorkCardPlaceholder

@Composable
fun BrowseScreen(
    onOpenSearch: () -> Unit,
    onOpenWork: () -> Unit
) {
    PlaceholderScreen(
        title = "Browse",
        subtitle = "AO3 discovery surfaces are represented without live requests.",
        sections = listOf(
            "Sort values and request concurrency are documented in Phase 0 contracts.",
            "Phase 1 does not include AO3 HTML fetching, parsing, authentication, or subscriptions.",
            "This route exists so navigation can be reviewed before data work begins."
        ),
        primaryActionLabel = "Open Search",
        onPrimaryAction = onOpenSearch
    ) {
        WorkCardPlaceholder(
            title = "Browse Result Placeholder",
            author = "Discovery Author",
            metadata = "Explicit - Updated today - 8 kudos",
            summary = "Sample browse result card for future AO3 search responses.",
            onOpenWork = onOpenWork
        )
    }
}
