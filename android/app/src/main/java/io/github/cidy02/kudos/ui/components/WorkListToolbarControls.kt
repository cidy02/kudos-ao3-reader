package io.github.cidy02.kudos.ui.components

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.outlined.FilterList
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp

/**
 * Work-list filter control: outline + neutral when off, filled + primary when a
 * filter is active. Long-press (when [onClearFilters] is set) clears all filters,
 * matching iOS `FilterButton`.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun FilterToolbarButton(
    filtersActive: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    onClearFilters: (() -> Unit)? = null,
    badgeCount: Int = 0,
    showBadge: Boolean = false,
    contentDescription: String = "Filters"
) {
    var menuOpen by remember { mutableStateOf(false) }
    val canClear = filtersActive && onClearFilters != null
    Box(modifier = modifier) {
        Box(
            modifier = Modifier
                .size(48.dp)
                .clip(CircleShape)
                .combinedClickable(
                    onClick = onClick,
                    onLongClick = if (canClear) ({ menuOpen = true }) else null,
                    role = Role.Button
                ),
            contentAlignment = Alignment.Center
        ) {
            val icon = if (filtersActive) Icons.Filled.FilterList else Icons.Outlined.FilterList
            val tint = if (filtersActive) {
                MaterialTheme.colorScheme.primary
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant
            }
            if (badgeCount > 0 || showBadge) {
                BadgedBox(
                    badge = {
                        Badge {
                            Text(
                                if (badgeCount > 0) {
                                    badgeCount.coerceAtMost(99).toString()
                                } else {
                                    "!"
                                }
                            )
                        }
                    }
                ) {
                    Icon(
                        imageVector = icon,
                        contentDescription = contentDescription,
                        tint = tint
                    )
                }
            } else {
                Icon(
                    imageVector = icon,
                    contentDescription = contentDescription,
                    tint = tint
                )
            }
        }
        if (canClear) {
            DropdownMenu(
                expanded = menuOpen,
                onDismissRequest = { menuOpen = false }
            ) {
                DropdownMenuItem(
                    text = { Text("Clear all filters") },
                    onClick = {
                        menuOpen = false
                        onClearFilters.invoke()
                    }
                )
            }
        }
    }
}

@Composable
fun NeutralToolbarIconButton(
    icon: ImageVector,
    contentDescription: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    IconButton(onClick = onClick, modifier = modifier) {
        Icon(
            imageVector = icon,
            contentDescription = contentDescription,
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
fun MatureRevealToolbarButton(
    revealAll: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    IconButton(onClick = onClick, modifier = modifier) {
        Icon(
            imageVector = if (revealAll) Icons.Filled.VisibilityOff else Icons.Filled.Visibility,
            contentDescription = if (revealAll) "Hide mature works" else "Show mature works",
            tint = if (revealAll) {
                MaterialTheme.colorScheme.primary
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant
            }
        )
    }
}
