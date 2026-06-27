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

/** AO3 error → short Browse-facing message. Overload/capacity is never silent. */
fun AO3Error.browseMessage(): String = when (this) {
    AO3Error.BadRequest -> "AO3 rejected that request."
    AO3Error.AuthenticationRequired -> "AO3 requires login for that page."
    AO3Error.Forbidden -> "AO3 denied access to that page."
    AO3Error.NotFound -> "AO3 could not find that page."
    is AO3Error.Http -> "AO3 returned HTTP $statusCode."
    is AO3Error.Network -> message
    is AO3Error.Overloaded -> "AO3 is busy right now. Try again shortly."
    is AO3Error.Parse -> message
    is AO3Error.RateLimited -> "AO3 is rate-limiting requests. Try again shortly."
    is AO3Error.Server -> "AO3 had a server problem (HTTP $statusCode)."
    is AO3Error.Validation -> message
}
