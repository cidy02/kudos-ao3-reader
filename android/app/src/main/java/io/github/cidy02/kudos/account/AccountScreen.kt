package io.github.cidy02.kudos.account

import android.content.Intent
import android.net.Uri
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
import androidx.compose.material.icons.automirrored.outlined.Logout
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.BugReport
import androidx.compose.material.icons.outlined.CloudUpload
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material.icons.outlined.Collections
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.NotificationsNone
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.PrivacyTip
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.StarOutline
import androidx.compose.material.icons.outlined.Tune
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
import androidx.compose.ui.platform.LocalContext
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

/**
 * Account hub — Material expression of Apple [AccountView] Form sections:
 * AO3 Account → My AO3 → On AO3 → Local → App → Help.
 */
@Composable
fun AccountScreen(
    authRepository: AO3AuthRepository,
    onLogin: () -> Unit,
    onOpenList: (AccountListType) -> Unit,
    onOpenBackup: () -> Unit,
    onOpenSettings: () -> Unit,
    onOpenCollections: () -> Unit = {},
    onOpenAO3Collections: () -> Unit = {},
    onOpenDashboard: () -> Unit = {},
    onOpenLocalHistory: () -> Unit = {},
    onOpenLocalFavorites: () -> Unit = {},
    onOpenAbout: () -> Unit = {},
    onOpenPrivacy: () -> Unit = {},
    onOpenWeb: (String) -> Unit = {},
    modifier: Modifier = Modifier,
    viewModel: AccountViewModel = viewModel(factory = AccountViewModel.factory(authRepository))
) {
    val state by viewModel.uiState.collectAsState()
    val signedIn = state.authState is AO3AuthState.SignedIn
    val context = LocalContext.current

    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        item {
            AccountStatusSection(
                authState = state.authState,
                onLogin = onLogin,
                onLogout = viewModel::logout
            )
        }
        item {
            AccountSection(
                title = "My AO3",
                footer = if (!signedIn) {
                    "Log in to use your AO3 subscriptions, bookmarks, history, and reading list."
                } else {
                    null
                }
            ) {
                AccountNavRow(
                    title = "My Dashboard",
                    icon = Icons.Outlined.GridView,
                    enabled = signedIn,
                    onClick = onOpenDashboard
                )
                AccountNavRow(
                    title = "My Works",
                    icon = Icons.Outlined.Description,
                    enabled = signedIn,
                    onClick = { onOpenList(AccountListType.MyWorks) }
                )
                AccountNavRow(
                    title = "My Collections",
                    icon = Icons.Outlined.Collections,
                    enabled = signedIn,
                    onClick = onOpenAO3Collections
                )
                AccountNavRow(
                    title = "My Subscriptions",
                    icon = Icons.Outlined.NotificationsNone,
                    enabled = signedIn,
                    onClick = { onOpenList(AccountListType.Subscriptions) }
                )
                AccountNavRow(
                    title = "My AO3 Bookmarks",
                    icon = Icons.Outlined.BookmarkBorder,
                    enabled = signedIn,
                    onClick = { onOpenList(AccountListType.Bookmarks) }
                )
                AccountNavRow(
                    title = "Marked for Later",
                    icon = Icons.Outlined.Schedule,
                    enabled = signedIn,
                    onClick = { onOpenList(AccountListType.MarkedForLater) }
                )
                AccountNavRow(
                    title = "My AO3 History",
                    icon = Icons.Outlined.History,
                    enabled = signedIn,
                    onClick = { onOpenList(AccountListType.History) },
                    showDivider = false
                )
            }
        }
        item {
            AccountSection(
                title = "On AO3",
                footer = "Opens your AO3 settings on the website."
            ) {
                AccountNavRow(
                    title = "My Preferences",
                    icon = Icons.Outlined.Tune,
                    enabled = true,
                    onClick = { onOpenWeb("https://archiveofourown.org/preferences") },
                    showDivider = false
                )
            }
        }
        item {
            AccountSection(
                title = "Local",
                footer = "Stored on this device — distinct from your AO3 account history."
            ) {
                AccountNavRow(
                    title = "Local Reading History",
                    icon = Icons.Outlined.History,
                    enabled = true,
                    onClick = onOpenLocalHistory
                )
                AccountNavRow(
                    title = "Favorites",
                    icon = Icons.Outlined.StarOutline,
                    enabled = true,
                    onClick = onOpenLocalFavorites
                )
                AccountNavRow(
                    title = "Local Collections",
                    icon = Icons.Outlined.Collections,
                    enabled = true,
                    onClick = onOpenCollections,
                    showDivider = false
                )
            }
        }
        item {
            AccountSection(title = "App") {
                AccountNavRow(
                    title = "Settings",
                    icon = Icons.Outlined.Settings,
                    enabled = true,
                    onClick = onOpenSettings
                )
                AccountNavRow(
                    title = "Privacy & Local Data",
                    icon = Icons.Outlined.PrivacyTip,
                    enabled = true,
                    onClick = onOpenPrivacy
                )
                AccountNavRow(
                    title = "Backup",
                    icon = Icons.Outlined.CloudUpload,
                    enabled = true,
                    onClick = onOpenBackup,
                    showDivider = false
                )
            }
        }
        item {
            AccountSection(title = "Help & Project") {
                AccountNavRow(
                    title = "About Kudos",
                    icon = Icons.Outlined.Info,
                    enabled = true,
                    onClick = onOpenAbout
                )
                AccountNavRow(
                    title = "Report a Bug",
                    icon = Icons.Outlined.BugReport,
                    enabled = true,
                    onClick = {
                        val intent = Intent(Intent.ACTION_SENDTO).apply {
                            data = Uri.parse("mailto:")
                            putExtra(Intent.EXTRA_EMAIL, arrayOf("cidy02@users.noreply.github.com"))
                            putExtra(Intent.EXTRA_SUBJECT, "Kudos Android bug report")
                        }
                        runCatching { context.startActivity(intent) }
                    }
                )
                AccountNavRow(
                    title = "Source on GitHub",
                    icon = Icons.Outlined.Code,
                    enabled = true,
                    onClick = {
                        val intent = Intent(
                            Intent.ACTION_VIEW,
                            Uri.parse("https://github.com/cidy02/kudos-ao3-reader")
                        )
                        runCatching { context.startActivity(intent) }
                    },
                    showDivider = false
                )
            }
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
        key = type.listKey,
        factory = AccountListViewModel.factory(type, repository)
    )
) {
    val state by viewModel.uiState.collectAsState()

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
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
        items(works, key = { "${type.listKey}-${it.id}" }) { work ->
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
            modifier = Modifier
                .weight(1f)
                .padding(top = 12.dp),
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
private fun AccountStatusSection(
    authState: AO3AuthState,
    onLogin: () -> Unit,
    onLogout: () -> Unit
) {
    AccountSection(
        title = "AO3 Account",
        footer = when (authState) {
            is AO3AuthState.SignedIn ->
                "Your session stays on this device and is never included in Kudos backups."
            else ->
                "Log in to use your AO3 subscriptions, bookmarks, history, and reading list. " +
                    "Your session stays on this device."
        }
    ) {
        when (authState) {
            AO3AuthState.Restoring -> {
                ListItem(
                    headlineContent = { Text("Checking saved AO3 session…") },
                    leadingContent = { CircularProgressIndicator() },
                    colors = accountListItemColors()
                )
            }
            AO3AuthState.SigningIn -> {
                ListItem(
                    headlineContent = { Text("Capturing AO3 session…") },
                    leadingContent = { CircularProgressIndicator() },
                    colors = accountListItemColors()
                )
            }
            is AO3AuthState.SignedIn -> {
                ListItem(
                    headlineContent = {
                        Text(
                            "Signed In",
                            color = MaterialTheme.colorScheme.primary
                        )
                    },
                    supportingContent = { Text(authState.username) },
                    leadingContent = {
                        Icon(
                            imageVector = Icons.Outlined.Person,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary
                        )
                    },
                    colors = accountListItemColors()
                )
                HorizontalDivider(
                    modifier = Modifier.padding(start = 56.dp),
                    color = MaterialTheme.colorScheme.outlineVariant
                )
                ListItem(
                    headlineContent = {
                        Text("Log Out", color = MaterialTheme.colorScheme.error)
                    },
                    leadingContent = {
                        Icon(
                            imageVector = Icons.AutoMirrored.Outlined.Logout,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.error
                        )
                    },
                    colors = accountListItemColors(),
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(onClick = onLogout)
                )
            }
            AO3AuthState.SignedOut -> {
                ListItem(
                    headlineContent = { Text("Log In to AO3…") },
                    supportingContent = {
                        Text("Kudos opens AO3's real login page and never stores your password.")
                    },
                    leadingContent = {
                        Icon(Icons.Outlined.Person, contentDescription = null)
                    },
                    colors = accountListItemColors(),
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(onClick = onLogin)
                )
            }
            is AO3AuthState.Expired -> {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(authState.message, color = MaterialTheme.colorScheme.error)
                    Button(onClick = onLogin) { Text("Log In Again") }
                }
            }
            is AO3AuthState.Error -> {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(authState.message, color = MaterialTheme.colorScheme.error)
                    Button(onClick = onLogin) { Text("Log In") }
                }
            }
        }
    }
}

@Composable
private fun AccountSection(
    title: String,
    footer: String? = null,
    content: @Composable () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(horizontal = 8.dp)
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
                modifier = Modifier.padding(horizontal = 8.dp)
            )
        }
    }
}

@Composable
private fun AccountNavRow(
    title: String,
    icon: ImageVector,
    enabled: Boolean,
    onClick: () -> Unit,
    showDivider: Boolean = true,
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
            headlineContent = { Text(title) },
            supportingContent = if (!supportingText.isNullOrBlank()) {
                { Text(supportingText) }
            } else {
                null
            },
            leadingContent = {
                Icon(imageVector = icon, contentDescription = null, tint = iconColor)
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

@Composable
private fun accountListItemColors() = ListItemDefaults.colors(
    containerColor = MaterialTheme.colorScheme.surfaceContainerLow
)
