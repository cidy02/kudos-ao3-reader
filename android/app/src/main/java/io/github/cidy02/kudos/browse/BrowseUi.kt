package io.github.cidy02.kudos.browse

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.network.ao3.AO3Error

/** Shared error block for Browse surfaces: a message plus Retry / Open-on-AO3. */
@Composable
fun BrowseErrorBlock(
    message: String,
    onRetry: () -> Unit,
    onWebFallback: (() -> Unit)? = null
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            text = message,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.error
        )
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Button(onClick = onRetry) { Text("Retry") }
            if (onWebFallback != null) {
                OutlinedButton(onClick = onWebFallback) { Text("Open on AO3") }
            }
        }
    }
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
