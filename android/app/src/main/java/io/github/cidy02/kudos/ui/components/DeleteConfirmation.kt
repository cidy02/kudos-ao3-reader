package io.github.cidy02.kudos.ui.components

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AlertDialogDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectPalette

@Composable
fun DestructiveConfirmation(
    show: Boolean,
    title: String,
    text: String,
    confirmText: String = "Delete",
    dismissText: String = "Cancel",
    confirmBeforeDelete: Boolean,
    onConfirm: () -> Unit,
    onDismissRequest: () -> Unit,
    palette: SubjectPalette? = null
) {
    val tokens = LocalKudosTokens.current
    if (show) {
        if (!confirmBeforeDelete) {
            LaunchedEffect(Unit) {
                onConfirm()
            }
        } else {
            AlertDialog(
                containerColor = if (palette != null) tokens.theme.cardSurface else AlertDialogDefaults.containerColor,
                titleContentColor = if (palette != null) tokens.primaryInk else AlertDialogDefaults.titleContentColor,
                textContentColor = if (palette != null) tokens.secondaryInk else AlertDialogDefaults.textContentColor,
                onDismissRequest = onDismissRequest,
                title = { Text(title) },
                text = { Text(text) },
                confirmButton = {
                    TextButton(onClick = onConfirm) {
                        Text(
                            text = confirmText,
                            color = palette?.accent ?: MaterialTheme.colorScheme.error
                        )
                    }
                },
                dismissButton = {
                    TextButton(onClick = onDismissRequest) {
                        Text(dismissText, color = palette?.accent ?: MaterialTheme.colorScheme.primary)
                    }
                }
            )
        }
    }
}

/** iOS `logOutConfirmation`: Log Out asks first, the same way everywhere it is offered. */
@Composable
fun LogOutConfirmation(show: Boolean, onConfirm: () -> Unit, onDismissRequest: () -> Unit) {
    DestructiveConfirmation(
        show = show,
        title = "Log out of AO3?",
        text = "You will be signed out of AO3 on this device. Your Library, downloads, and queues stay.",
        confirmText = "Log Out",
        confirmBeforeDelete = true,
        onConfirm = onConfirm,
        onDismissRequest = onDismissRequest
    )
}
