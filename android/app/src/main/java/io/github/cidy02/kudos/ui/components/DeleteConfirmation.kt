package io.github.cidy02.kudos.ui.components

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect

@Composable
fun DestructiveConfirmation(
    show: Boolean,
    title: String,
    text: String,
    confirmText: String = "Delete",
    dismissText: String = "Cancel",
    confirmBeforeDelete: Boolean,
    onConfirm: () -> Unit,
    onDismissRequest: () -> Unit
) {
    if (show) {
        if (!confirmBeforeDelete) {
            LaunchedEffect(Unit) {
                onConfirm()
            }
        } else {
            AlertDialog(
                onDismissRequest = onDismissRequest,
                title = { Text(title) },
                text = { Text(text) },
                confirmButton = {
                    TextButton(onClick = onConfirm) {
                        Text(
                            text = confirmText,
                            color = MaterialTheme.colorScheme.error
                        )
                    }
                },
                dismissButton = {
                    TextButton(onClick = onDismissRequest) {
                        Text(dismissText)
                    }
                }
            )
        }
    }
}
