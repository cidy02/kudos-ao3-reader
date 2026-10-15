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
import io.github.cidy02.kudos.core.model.SavedWork

/** PreservedWorkService.deleteConfirmationMessage, including a batch's last AO3 copy. */
fun workDeletionMessage(works: List<SavedWork>): String {
    val subject = if (works.size == 1) "This work" else "At least one selected work"
    return if (works.any { it.ao3Unavailable }) {
        "$subject is no longer available on AO3. If you don't restore it within 90 days, " +
            "Kudos will permanently remove this copy, and you can't download it from AO3 again."
    } else {
        "Works move to Recently Deleted. You can restore them for the next 90 days."
    }
}

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
