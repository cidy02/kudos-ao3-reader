package io.github.cidy02.kudos.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.outlined.LastPage
import androidx.compose.material.icons.outlined.FirstPage
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * Shared pagination control for Search / Browse / Account lists.
 * Shows First · Prev · Page X of Y · Next · Last.
 */
@Composable
fun KudosPaginationBar(
    currentPage: Int,
    totalPages: Int,
    onPageChange: (Int) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true
) {
    if (totalPages <= 1) return

    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            IconButton(
                onClick = { onPageChange(1) },
                enabled = enabled && currentPage > 1
            ) {
                Icon(Icons.Outlined.FirstPage, contentDescription = "First Page")
            }
            IconButton(
                onClick = { onPageChange(currentPage - 1) },
                enabled = enabled && currentPage > 1
            ) {
                Icon(Icons.AutoMirrored.Outlined.KeyboardArrowLeft, contentDescription = "Previous Page")
            }
        }

        Text(
            text = "Page $currentPage of $totalPages",
            style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Medium),
            color = MaterialTheme.colorScheme.onSurface
        )

        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            IconButton(
                onClick = { onPageChange(currentPage + 1) },
                enabled = enabled && currentPage < totalPages
            ) {
                Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = "Next Page")
            }
            IconButton(
                onClick = { onPageChange(totalPages) },
                enabled = enabled && currentPage < totalPages
            ) {
                Icon(Icons.AutoMirrored.Outlined.LastPage, contentDescription = "Last Page")
            }
        }
    }
}
