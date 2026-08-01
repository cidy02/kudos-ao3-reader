package io.github.cidy02.kudos.account

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.CloudUpload
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.automirrored.outlined.LibraryBooks
import androidx.compose.material.icons.outlined.NotificationsNone
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.AO3AuthState
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.ui.components.AO3WorkCard
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.components.StatusBadge

@Composable
fun AccountScreen(
    authRepository: AO3AuthRepository,
    onLogin: () -> Unit,
    onOpenList: (AccountListType) -> Unit,
    onOpenBackup: () -> Unit,
    onOpenSettings: () -> Unit,
    onOpenCollections: () -> Unit = {},
    modifier: Modifier = Modifier,
    viewModel: AccountViewModel = viewModel(factory = AccountViewModel.factory(authRepository))
) {
    val state by viewModel.uiState.collectAsState()
    val signedIn = state.authState is AO3AuthState.SignedIn

    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Text(
                text = "AO3 session, account lists, settings, and backup.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        item {
            AccountStatusCard(
                authState = state.authState,
                onLogin = onLogin,
                onLogout = viewModel::logout
            )
        }
        item {
            AccountDestinationGroup(
                title = "My AO3",
                footer = if (!signedIn) "Log in to load account lists." else null
            ) {
                AccountListType.entries.forEachIndexed { index, type ->
                    AccountDestinationRow(
                        title = type.title,
                        icon = type.leadingIcon,
                        enabled = signedIn,
                        supportingText = if (!signedIn) "Sign in required" else null,
                        onClick = { onOpenList(type) },
                        showDivider = index < AccountListType.entries.lastIndex
                    )
                }
            }
        }
        item {
            AccountDestinationGroup(title = "App") {
                AccountDestinationRow(
                    title = "Local Collections",
                    icon = Icons.AutoMirrored.Outlined.LibraryBooks,
                    enabled = true,
                    supportingText = "Named shelves in your Library",
                    onClick = onOpenCollections,
                    showDivider = true
                )
                AccountDestinationRow(
                    title = "Settings",
                    icon = Icons.Outlined.Settings,
                    enabled = true,
                    onClick = onOpenSettings,
                    showDivider = true
                )
                AccountDestinationRow(
                    title = "Backup",
                    icon = Icons.Outlined.CloudUpload,
                    enabled = true,
                    onClick = onOpenBackup,
                    showDivider = false
                )
            }
        }
        item {
            Text(
                text = "AO3 lists live here. User-initiated kudos, comments, bookmarks, " +
                    "subscriptions, and Mark for Later actions are available from each work detail.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
fun AccountListScreen(
    type: AccountListType,
    repository: AccountListRepository,
    onLogin: () -> Unit,
    onOpenWork: (AO3WorkSummary) -> Unit,
    modifier: Modifier = Modifier,
    viewModel: AccountListViewModel = viewModel(
        key = type.name,
        factory = AccountListViewModel.factory(type, repository)
    )
) {
    val state by viewModel.uiState.collectAsState()

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        // TopAppBar is generic ("Account List"); keep a compact type label only.
        Text(
            text = type.title,
            style = MaterialTheme.typography.titleLarge
        )
        Text(
            text = "Read-only AO3 account list.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        when (val current = state) {
            AccountListUiState.Loading -> LoadingStateCard("Loading ${type.title}")
            AccountListUiState.AuthRequired -> EmptyStateCard(
                title = "AO3 session required",
                message = "Your AO3 session needs to be refreshed.",
                primaryActionLabel = "Log In Again",
                onPrimaryAction = onLogin
            )
            is AccountListUiState.Failed -> {
                ErrorStateCard(
                    title = "Could not load ${type.title}",
                    message = current.message,
                    primaryActionLabel = "Retry",
                    onPrimaryAction = { viewModel.load(1) }
                )
            }
            is AccountListUiState.Loaded -> {
                if (current.page.works.isEmpty()) {
                    EmptyStateCard(
                        title = type.emptyTitle,
                        message = type.emptyMessage
                    )
                } else {
                    AccountListContent(
                        type = type,
                        page = current.page.currentPage,
                        totalPages = current.page.totalPages,
                        works = current.page.works,
                        onLoadPage = viewModel::load,
                        onOpenWork = onOpenWork
                    )
                }
            }
        }
    }
}

@Composable
private fun AccountListContent(
    type: AccountListType,
    page: Int,
    totalPages: Int,
    works: List<AO3WorkSummary>,
    onLoadPage: (Int) -> Unit,
    onOpenWork: (AO3WorkSummary) -> Unit
) {
    LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            if (totalPages > 1) {
                PaginationControls(page, totalPages, onLoadPage)
            }
        }
        items(works, key = { "${type.name}-${it.id}" }) { work ->
            AO3WorkCard(work = work, onOpenWork = onOpenWork)
        }
        item {
            if (totalPages > 1) {
                PaginationControls(page, totalPages, onLoadPage)
            }
        }
    }
}

@Composable
private fun PaginationControls(page: Int, totalPages: Int, onLoadPage: (Int) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
        OutlinedButton(
            enabled = page > 1,
            onClick = { onLoadPage(page - 1) },
            modifier = Modifier.weight(1f)
        ) {
            Text("Previous")
        }
        Text(
            text = "Page $page of $totalPages",
            modifier = Modifier.weight(1f),
            style = MaterialTheme.typography.labelLarge
        )
        OutlinedButton(
            enabled = page < totalPages,
            onClick = { onLoadPage(page + 1) },
            modifier = Modifier.weight(1f)
        ) {
            Text("Next")
        }
    }
}

@Composable
private fun AccountStatusCard(
    authState: AO3AuthState,
    onLogin: () -> Unit,
    onLogout: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow
        )
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text("AO3 Account", style = MaterialTheme.typography.titleMedium)
            when (authState) {
                AO3AuthState.Restoring -> {
                    InlineLoading("Checking saved AO3 session.")
                }
                AO3AuthState.SigningIn -> {
                    InlineLoading("Capturing AO3 session.")
                }
                is AO3AuthState.SignedIn -> {
                    StatusBadge("Signed in")
                    Text(
                        text = authState.username,
                        style = MaterialTheme.typography.titleSmall
                    )
                    Text(
                        text = "Session cookies stay app-private and are never included in Kudos backups.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    OutlinedButton(onClick = onLogout) { Text("Log Out") }
                }
                AO3AuthState.SignedOut -> SignedOutLoginCopy(onLogin)
                is AO3AuthState.Expired -> {
                    Text(authState.message, color = MaterialTheme.colorScheme.error)
                    Button(onClick = onLogin) { Text("Log In Again") }
                }
                is AO3AuthState.Error -> {
                    Text(authState.message, color = MaterialTheme.colorScheme.error)
                    Button(onClick = onLogin) { Text("Log In") }
                }
            }
        }
    }
}

@Composable
private fun InlineLoading(message: String) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        CircularProgressIndicator()
        Text(message)
    }
}

@Composable
private fun SignedOutLoginCopy(onLogin: () -> Unit) {
    Text("AO3 login is optional.")
    Text(
        text = "Kudos opens AO3's real login page. It never stores your AO3 password.",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
    Text(
        text = "Kudos is an unofficial app and is not affiliated with AO3 or OTW.",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
    Button(onClick = onLogin) { Text("Log In to AO3") }
}

@Composable
private fun AccountDestinationGroup(
    title: String,
    footer: String? = null,
    content: @Composable () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(horizontal = 4.dp)
        )
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceContainerLow
            )
        ) {
            content()
        }
        if (!footer.isNullOrBlank()) {
            Text(
                text = footer,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 4.dp)
            )
        }
    }
}

@Composable
private fun AccountDestinationRow(
    title: String,
    icon: ImageVector,
    enabled: Boolean,
    onClick: () -> Unit,
    showDivider: Boolean,
    supportingText: String? = null
) {
    val contentColor = if (enabled) {
        MaterialTheme.colorScheme.onSurface
    } else {
        MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
    }
    val iconColor = if (enabled) {
        MaterialTheme.colorScheme.onSurfaceVariant
    } else {
        MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
    }
    Column {
        ListItem(
            headlineContent = {
                Text(title)
            },
            supportingContent = if (!supportingText.isNullOrBlank()) {
                { Text(supportingText) }
            } else {
                null
            },
            leadingContent = {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = iconColor
                )
            },
            trailingContent = {
                Icon(
                    imageVector = Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                    contentDescription = null,
                    tint = iconColor
                )
            },
            colors = ListItemDefaults.colors(
                containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
                headlineColor = contentColor,
                supportingColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(
                    alpha = if (enabled) 1f else 0.6f
                ),
                leadingIconColor = iconColor,
                trailingIconColor = iconColor
            ),
            modifier = Modifier
                .fillMaxWidth()
                .clickable(enabled = enabled, onClick = onClick)
        )
        if (showDivider) {
            HorizontalDivider(
                modifier = Modifier.padding(start = 56.dp),
                color = MaterialTheme.colorScheme.outlineVariant
            )
        }
    }
}

private val AccountListType.leadingIcon: ImageVector
    get() = when (this) {
        AccountListType.MarkedForLater -> Icons.Outlined.Schedule
        AccountListType.Bookmarks -> Icons.Outlined.BookmarkBorder
        AccountListType.History -> Icons.Outlined.History
        AccountListType.Subscriptions -> Icons.Outlined.NotificationsNone
        AccountListType.MyWorks -> Icons.Outlined.Description
    }
