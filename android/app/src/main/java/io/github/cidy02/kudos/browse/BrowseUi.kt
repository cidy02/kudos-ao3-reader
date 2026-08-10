package io.github.cidy02.kudos.browse

import androidx.compose.runtime.Composable
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.ui.components.ErrorStateCard

/** Shared error block for Browse surfaces: a message plus Retry / Open-on-AO3. */
@Composable
fun BrowseErrorBlock(
    message: String,
    onRetry: () -> Unit,
    onWebFallback: (() -> Unit)? = null
) {
    ErrorStateCard(
        title = "AO3 browse failed",
        message = message,
        primaryActionLabel = "Retry",
        onPrimaryAction = onRetry,
        secondaryActionLabel = if (onWebFallback != null) "Open on AO3" else null,
        onSecondaryAction = onWebFallback
    )
}

