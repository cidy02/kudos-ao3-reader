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
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Slider
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import kotlin.math.roundToInt

/**
 * Shared pagination control for Search / Browse / Account lists.
 * First · Prev · Page X of Y · Next · Last, where the centre is a button that
 * opens a scrubber for the long jump.
 *
 * The arrows answer the common move — one page at a time. Reaching page 2,731 of
 * 5,000 with them is not a navigation model, which is what the scrubber is for: a
 * slider addresses a long ordered set in one gesture where stepping cannot.
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

    var showScrubber by remember { mutableStateOf(false) }

    if (showScrubber) {
        PageScrubberSheet(
            currentPage = currentPage,
            totalPages = totalPages,
            onSelect = onPageChange,
            onDismiss = { showScrubber = false }
        )
    }

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

        TextButton(
            onClick = { showScrubber = true },
            enabled = enabled && totalPages > 1
        ) {
            Text(
                text = "Page $currentPage of $totalPages",
                style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Medium),
                color = MaterialTheme.colorScheme.onSurface
            )
        }

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

/**
 * The long jump.
 *
 * **The slider does not load anything while you drag.** Pagination is a network
 * fetch, so a live-bound slider would fire a request per tick and rate-limit the
 * reader out of AO3 in one gesture. The sheet holds a draft, previews it in the
 * readout, and commits once on Go — which is what makes a slider affordable here.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PageScrubberSheet(
    currentPage: Int,
    totalPages: Int,
    onSelect: (Int) -> Unit,
    onDismiss: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var draft by remember(currentPage) { mutableFloatStateOf(currentPage.toFloat()) }
    val draftPage = draft.roundToInt().coerceIn(1, maxOf(totalPages, 1))

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .padding(bottom = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text(
                text = "$draftPage",
                style = MaterialTheme.typography.displaySmall.copy(fontWeight = FontWeight.SemiBold)
            )
            Text(
                text = "of $totalPages",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Slider(
                value = draft,
                onValueChange = { draft = it },
                valueRange = 1f..maxOf(totalPages, 2).toFloat(),
                // Continuous, *not* `steps = totalPages - 2`. A stepped Material
                // slider draws a tick per step, and AO3 lists run to 5,000 pages —
                // that is 4,998 ticks smeared into a solid bar, and a lot of them to
                // lay out. The readout rounds instead, so the thumb still resolves to
                // a whole page.
                modifier = Modifier.fillMaxWidth()
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                TextButton(onClick = { draft = 1f }, enabled = draftPage > 1) {
                    Text("First")
                }
                TextButton(
                    onClick = { draft = maxOf(totalPages, 1).toFloat() },
                    enabled = draftPage < totalPages
                ) {
                    Text("Last")
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                OutlinedButton(onClick = onDismiss, modifier = Modifier.weight(1f)) {
                    Text("Cancel")
                }
                Button(
                    onClick = {
                        if (draftPage != currentPage) onSelect(draftPage)
                        onDismiss()
                    },
                    enabled = draftPage != currentPage,
                    modifier = Modifier.weight(1f)
                ) {
                    Text("Go")
                }
            }
        }
    }
}
