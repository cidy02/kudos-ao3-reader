package io.github.cidy02.kudos.account

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.Collections
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.NotificationsNone
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp

/** Native My Dashboard hub — mirrors Apple AO3DashboardView. */
@Composable
fun AO3DashboardScreen(
    username: String?,
    onOpenList: (AccountListType) -> Unit,
    onOpenAO3Collections: () -> Unit,
    modifier: Modifier = Modifier
) {
    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 12.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Text(
                text = username?.let { "Signed in as $it" } ?: "My AO3",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.padding(horizontal = 8.dp)
            )
        }
        item {
            Card(
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainerLow
                ),
                modifier = Modifier.fillMaxWidth()
            ) {
                DashboardRow("My Works", Icons.Outlined.Description) {
                    onOpenList(AccountListType.MyWorks)
                }
                DashboardRow("My Collections", Icons.Outlined.Collections, onClick = onOpenAO3Collections)
                DashboardRow("My Bookmarks", Icons.Outlined.BookmarkBorder) {
                    onOpenList(AccountListType.Bookmarks)
                }
                DashboardRow("My Subscriptions", Icons.Outlined.NotificationsNone) {
                    onOpenList(AccountListType.Subscriptions)
                }
                DashboardRow("Marked for Later", Icons.Outlined.Schedule) {
                    onOpenList(AccountListType.MarkedForLater)
                }
                DashboardRow(
                    title = "My History",
                    icon = Icons.Outlined.History,
                    showDivider = false
                ) {
                    onOpenList(AccountListType.History)
                }
            }
        }
        item {
            Text(
                text = "Your AO3 works, bookmarks, collections, subscriptions, reading " +
                    "list, and history — all in the app.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 8.dp)
            )
        }
    }
}

@Composable
private fun DashboardRow(
    title: String,
    icon: ImageVector,
    showDivider: Boolean = true,
    onClick: () -> Unit
) {
    Column {
        ListItem(
            headlineContent = { Text(title) },
            leadingContent = { Icon(icon, contentDescription = null) },
            trailingContent = {
                Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null)
            },
            colors = ListItemDefaults.colors(
                containerColor = MaterialTheme.colorScheme.surfaceContainerLow
            ),
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClick = onClick)
        )
        if (showDivider) {
            HorizontalDivider(
                modifier = Modifier.padding(start = 56.dp),
                color = MaterialTheme.colorScheme.outlineVariant
            )
        }
    }
}
