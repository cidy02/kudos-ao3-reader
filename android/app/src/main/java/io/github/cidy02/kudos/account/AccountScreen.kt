package io.github.cidy02.kudos.account

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items as gridItems
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.outlined.Logout
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Collections
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.NotificationsNone
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.cidy02.kudos.R
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.AO3AuthState
import io.github.cidy02.kudos.network.ao3.account.AO3Collection
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.ui.components.AO3WorkCard
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.KudosSectionHeader
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.components.WorkCoverCard
import io.github.cidy02.kudos.ui.components.WorkCoverCardMetrics
import io.github.cidy02.kudos.ui.components.coverCardStats
import io.github.cidy02.kudos.ui.theme.Ao3Red

/**
 * Account hub — Material 3 expression of the iOS Account SoT:
 * profile header · Overview/Reading/Writing/Activity tabs · shortcut grid ·
 * inline list browsers that reuse [AccountListRepository] / [AccountListType].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccountScreen(
    authRepository: AO3AuthRepository,
    listRepository: AccountListRepository,
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
    onOpenWork: (AO3WorkSummary) -> Unit = {},
    onOpenCollection: (AO3Collection) -> Unit = {},
    modifier: Modifier = Modifier,
    viewModel: AccountViewModel = viewModel(factory = AccountViewModel.factory(authRepository))
) {
    val state by viewModel.uiState.collectAsState()
    val signedIn = state.authState is AO3AuthState.SignedIn
    val username = (state.authState as? AO3AuthState.SignedIn)?.username

    var tab by rememberSaveable { mutableStateOf(AccountHubTab.Overview.name) }
    var readingKind by rememberSaveable { mutableStateOf(AccountReadingKind.MarkedForLater.name) }
    var writingKind by rememberSaveable { mutableStateOf(AccountWritingKind.Works.name) }
    var activityKind by rememberSaveable { mutableStateOf(AccountActivityKind.History.name) }
    var selectedFandom by rememberSaveable { mutableStateOf<String?>(null) }

    val selectedTab = AccountHubTab.entries.find { it.name == tab } ?: AccountHubTab.Overview
    val selectedReading =
        AccountReadingKind.entries.find { it.name == readingKind } ?: AccountReadingKind.MarkedForLater
    val selectedWriting =
        AccountWritingKind.entries.find { it.name == writingKind } ?: AccountWritingKind.Works
    val selectedActivity =
        AccountActivityKind.entries.find { it.name == activityKind } ?: AccountActivityKind.History

    // Reset client fandom filter when the active list identity changes.
    LaunchedEffect(selectedTab, selectedReading, selectedWriting, selectedActivity) {
        selectedFandom = null
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        AccountProfileHeader(
            authState = state.authState,
            onLogin = onLogin,
            onLogout = viewModel::logout,
            onOpenSettings = onOpenSettings,
            onOpenAbout = onOpenAbout,
            onOpenPrivacy = onOpenPrivacy,
            onOpenBackup = onOpenBackup,
            onOpenLocalHistory = onOpenLocalHistory,
            onOpenLocalFavorites = onOpenLocalFavorites,
            onOpenCollections = onOpenCollections
        )

        AccountHubTabRow(
            selected = selectedTab,
            onSelect = { tab = it.name }
        )

        when (selectedTab) {
            AccountHubTab.Overview -> {
                OverviewTabContent(
                    signedIn = signedIn,
                    username = username,
                    onOpenDashboard = onOpenDashboard,
                    onOpenList = onOpenList,
                    onOpenAO3Collections = onOpenAO3Collections,
                    onOpenWeb = onOpenWeb
                )
            }
            AccountHubTab.Reading -> {
                ReadingTabContent(
                    signedIn = signedIn,
                    kind = selectedReading,
                    onKindChange = { readingKind = it.name },
                    listRepository = listRepository,
                    onLogin = onLogin,
                    onOpenWork = onOpenWork,
                    onOpenCollection = onOpenCollection,
                    onOpenAO3Collections = onOpenAO3Collections
                )
            }
            AccountHubTab.Writing -> {
                WritingTabContent(
                    signedIn = signedIn,
                    kind = selectedWriting,
                    onKindChange = { writingKind = it.name },
                    selectedFandom = selectedFandom,
                    onFandomChange = { selectedFandom = it },
                    listRepository = listRepository,
                    onLogin = onLogin,
                    onOpenWork = onOpenWork
                )
            }
            AccountHubTab.Activity -> {
                ActivityTabContent(
                    signedIn = signedIn,
                    kind = selectedActivity,
                    onKindChange = { activityKind = it.name },
                    listRepository = listRepository,
                    onLogin = onLogin,
                    onOpenWork = onOpenWork
                )
            }
        }
    }
}

// region Profile + tabs

@Composable
private fun AccountProfileHeader(
    authState: AO3AuthState,
    onLogin: () -> Unit,
    onLogout: () -> Unit,
    onOpenSettings: () -> Unit,
    onOpenAbout: () -> Unit,
    onOpenPrivacy: () -> Unit,
    onOpenBackup: () -> Unit,
    onOpenLocalHistory: () -> Unit,
    onOpenLocalFavorites: () -> Unit,
    onOpenCollections: () -> Unit
) {
    var menuOpen by remember { mutableStateOf(false) }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow
        ),
        shape = MaterialTheme.shapes.large
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            AccountAvatarPlaceholder()

            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                when (authState) {
                    AO3AuthState.Restoring, AO3AuthState.SigningIn -> {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                            Text(
                                text = if (authState is AO3AuthState.SigningIn) {
                                    "Signing in…"
                                } else {
                                    "Checking session…"
                                },
                                style = MaterialTheme.typography.titleMedium
                            )
                        }
                    }
                    is AO3AuthState.SignedIn -> {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = authState.username,
                                style = MaterialTheme.typography.titleMedium.copy(
                                    fontWeight = FontWeight.SemiBold
                                ),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.weight(1f, fill = false)
                            )
                            Icon(
                                imageVector = Icons.Outlined.CheckCircle,
                                contentDescription = "Signed in",
                                tint = Color(0xFF34C759),
                                modifier = Modifier.size(20.dp)
                            )
                        }
                        // Pseud picker is iOS-only until AO3 pseuds are scraped; show a quiet status line.
                        Text(
                            text = "Signed in to AO3",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.primary
                        )
                    }
                    AO3AuthState.SignedOut -> {
                        Text(
                            text = "Not signed in",
                            style = MaterialTheme.typography.titleMedium.copy(
                                fontWeight = FontWeight.SemiBold
                            )
                        )
                        TextButton(
                            onClick = onLogin,
                            contentPadding = PaddingValues(horizontal = 0.dp, vertical = 0.dp)
                        ) {
                            Text("Log In to AO3…")
                        }
                    }
                    is AO3AuthState.Expired -> {
                        Text(
                            text = "Session expired",
                            style = MaterialTheme.typography.titleMedium.copy(
                                fontWeight = FontWeight.SemiBold
                            ),
                            color = MaterialTheme.colorScheme.error
                        )
                        TextButton(
                            onClick = onLogin,
                            contentPadding = PaddingValues(horizontal = 0.dp, vertical = 0.dp)
                        ) {
                            Text("Log In Again")
                        }
                    }
                    is AO3AuthState.Error -> {
                        Text(
                            text = "Account error",
                            style = MaterialTheme.typography.titleMedium.copy(
                                fontWeight = FontWeight.SemiBold
                            ),
                            color = MaterialTheme.colorScheme.error
                        )
                        TextButton(
                            onClick = onLogin,
                            contentPadding = PaddingValues(horizontal = 0.dp, vertical = 0.dp)
                        ) {
                            Text("Log In")
                        }
                    }
                }
            }

            Box {
                IconButton(onClick = { menuOpen = true }) {
                    Icon(
                        imageVector = Icons.Outlined.MoreHoriz,
                        contentDescription = "Account menu"
                    )
                }
                DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                    DropdownMenuItem(
                        text = { Text("Settings") },
                        onClick = {
                            menuOpen = false
                            onOpenSettings()
                        }
                    )
                    DropdownMenuItem(
                        text = { Text("Privacy & Local Data") },
                        onClick = {
                            menuOpen = false
                            onOpenPrivacy()
                        }
                    )
                    DropdownMenuItem(
                        text = { Text("Backup") },
                        onClick = {
                            menuOpen = false
                            onOpenBackup()
                        }
                    )
                    DropdownMenuItem(
                        text = { Text("Local Reading History") },
                        onClick = {
                            menuOpen = false
                            onOpenLocalHistory()
                        }
                    )
                    DropdownMenuItem(
                        text = { Text("Favorites") },
                        onClick = {
                            menuOpen = false
                            onOpenLocalFavorites()
                        }
                    )
                    DropdownMenuItem(
                        text = { Text("Local Collections") },
                        onClick = {
                            menuOpen = false
                            onOpenCollections()
                        }
                    )
                    DropdownMenuItem(
                        text = { Text("About Kudos") },
                        onClick = {
                            menuOpen = false
                            onOpenAbout()
                        }
                    )
                    if (authState is AO3AuthState.SignedIn) {
                        HorizontalDivider()
                        DropdownMenuItem(
                            text = {
                                Text("Log Out", color = MaterialTheme.colorScheme.error)
                            },
                            leadingIcon = {
                                Icon(
                                    imageVector = Icons.AutoMirrored.Outlined.Logout,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.error
                                )
                            },
                            onClick = {
                                menuOpen = false
                                onLogout()
                            }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun AccountAvatarPlaceholder() {
    Surface(
        modifier = Modifier
            .size(56.dp)
            .semantics { contentDescription = "Account avatar" },
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHighest
    ) {
        Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
            Image(
                painter = painterResource(id = R.drawable.ic_kudos_mark),
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier
                    .size(40.dp)
                    .clip(RoundedCornerShape(8.dp))
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AccountHubTabRow(
    selected: AccountHubTab,
    onSelect: (AccountHubTab) -> Unit
) {
    val tabs = AccountHubTab.entries
    SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
        tabs.forEachIndexed { index, hubTab ->
            SegmentedButton(
                selected = selected == hubTab,
                onClick = { onSelect(hubTab) },
                shape = SegmentedButtonDefaults.itemShape(index = index, count = tabs.size),
                label = {
                    Text(
                        text = hubTab.label,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            )
        }
    }
}

// endregion

// region Overview

@Composable
private fun OverviewTabContent(
    signedIn: Boolean,
    username: String?,
    onOpenDashboard: () -> Unit,
    onOpenList: (AccountListType) -> Unit,
    onOpenAO3Collections: () -> Unit,
    onOpenWeb: (String) -> Unit
) {
    val context = LocalContext.current
    LazyColumn(
        verticalArrangement = Arrangement.spacedBy(16.dp),
        contentPadding = PaddingValues(bottom = 24.dp)
    ) {
        item {
            KudosSectionHeader(title = "Shortcuts")
            Spacer(Modifier.height(8.dp))
            AccountShortcutsGrid(
                signedIn = signedIn,
                onOpenDashboard = onOpenDashboard,
                onOpenList = onOpenList,
                onOpenAO3Collections = onOpenAO3Collections
            )
        }
        item {
            KudosSectionHeader(title = "Account")
            Spacer(Modifier.height(8.dp))
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                AccountLinkRow(
                    title = "Preferences",
                    icon = Icons.Outlined.Tune,
                    onClick = { onOpenWeb("https://archiveofourown.org/preferences") }
                )
                AccountLinkRow(
                    title = "More on AO3",
                    icon = Icons.Outlined.Public,
                    onClick = {
                        val url = if (!username.isNullOrBlank()) {
                            "https://archiveofourown.org/users/$username"
                        } else {
                            "https://archiveofourown.org"
                        }
                        onOpenWeb(url)
                    }
                )
            }
        }
        if (!signedIn) {
            item {
                Text(
                    text = "Log in to use AO3 subscriptions, bookmarks, history, and your reading list.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 4.dp)
                )
            }
        }
        item {
            // Quiet help affordance — iOS keeps bug/source off the overview face.
            TextButton(
                onClick = {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/cidy02/kudos-ao3-reader"))
                    runCatching { context.startActivity(intent) }
                }
            ) {
                Text("Source on GitHub", style = MaterialTheme.typography.labelLarge)
            }
        }
    }
}

@Composable
private fun AccountShortcutsGrid(
    signedIn: Boolean,
    onOpenDashboard: () -> Unit,
    onOpenList: (AccountListType) -> Unit,
    onOpenAO3Collections: () -> Unit
) {
    val shortcuts = listOf(
        ShortcutItem("My Dashboard", Icons.Outlined.GridView, enabled = signedIn, onClick = onOpenDashboard),
        ShortcutItem(
            "My Subscriptions",
            Icons.Outlined.NotificationsNone,
            enabled = signedIn,
            onClick = { onOpenList(AccountListType.Subscriptions) }
        ),
        ShortcutItem(
            "My Works",
            Icons.Outlined.Description,
            enabled = signedIn,
            onClick = { onOpenList(AccountListType.MyWorks) }
        ),
        ShortcutItem(
            "My Bookmarks",
            Icons.Outlined.BookmarkBorder,
            enabled = signedIn,
            onClick = { onOpenList(AccountListType.Bookmarks) }
        ),
        ShortcutItem(
            "My Collections",
            Icons.Outlined.Collections,
            enabled = signedIn,
            onClick = onOpenAO3Collections
        ),
        ShortcutItem(
            "My History",
            Icons.Outlined.History,
            enabled = signedIn,
            onClick = { onOpenList(AccountListType.History) }
        )
    )

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        shortcuts.chunked(3).forEach { row ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                row.forEach { item ->
                    AccountShortcutTile(
                        item = item,
                        modifier = Modifier.weight(1f)
                    )
                }
                // Pad incomplete final rows so tiles keep equal width.
                repeat(3 - row.size) {
                    Spacer(Modifier.weight(1f))
                }
            }
        }
    }
}

private data class ShortcutItem(
    val title: String,
    val icon: ImageVector,
    val enabled: Boolean,
    val onClick: () -> Unit
)

@Composable
private fun AccountShortcutTile(
    item: ShortcutItem,
    modifier: Modifier = Modifier
) {
    val iconTint = if (item.enabled) Ao3Red else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
    val textColor = if (item.enabled) {
        MaterialTheme.colorScheme.onSurface
    } else {
        MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
    }
    Card(
        onClick = item.onClick,
        enabled = item.enabled,
        modifier = modifier.aspectRatio(1f),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
            disabledContainerColor = MaterialTheme.colorScheme.surfaceContainerLow.copy(alpha = 0.7f)
        ),
        shape = MaterialTheme.shapes.large
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Icon(
                imageVector = item.icon,
                contentDescription = null,
                tint = iconTint,
                modifier = Modifier.size(28.dp)
            )
            Spacer(Modifier.height(8.dp))
            Text(
                text = item.title,
                style = MaterialTheme.typography.labelMedium,
                color = textColor,
                textAlign = TextAlign.Center,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun AccountLinkRow(
    title: String,
    icon: ImageVector,
    onClick: () -> Unit
) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow
        ),
        shape = MaterialTheme.shapes.large
    ) {
        ListItem(
            headlineContent = { Text(title) },
            leadingContent = {
                Icon(imageVector = icon, contentDescription = null, tint = Ao3Red)
            },
            trailingContent = {
                Icon(
                    imageVector = Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            },
            colors = ListItemDefaults.colors(
                containerColor = Color.Transparent
            )
        )
    }
}

// endregion

// region Reading / Writing / Activity tabs

@Composable
private fun ReadingTabContent(
    signedIn: Boolean,
    kind: AccountReadingKind,
    onKindChange: (AccountReadingKind) -> Unit,
    listRepository: AccountListRepository,
    onLogin: () -> Unit,
    onOpenWork: (AO3WorkSummary) -> Unit,
    onOpenCollection: (AO3Collection) -> Unit,
    onOpenAO3Collections: () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxSize()) {
        AccountListKindPicker(
            label = kind.label,
            icon = when (kind) {
                AccountReadingKind.MarkedForLater -> Icons.Outlined.Schedule
                AccountReadingKind.Subscriptions -> Icons.Outlined.NotificationsNone
                AccountReadingKind.Bookmarks -> Icons.Outlined.BookmarkBorder
                AccountReadingKind.Collections -> Icons.Outlined.Collections
            },
            options = AccountReadingKind.entries.map { it.label to it },
            onSelect = onKindChange
        )

        if (!signedIn) {
            SignInRequiredCard(onLogin)
            return
        }

        when (kind) {
            AccountReadingKind.Collections -> {
                HubCollectionsPane(
                    listRepository = listRepository,
                    onLogin = onLogin,
                    onOpenCollection = onOpenCollection,
                    onOpenFullIndex = onOpenAO3Collections
                )
            }
            else -> {
                val listType = kind.toAccountListType() ?: return
                HubWorksPane(
                    listType = listType,
                    listRepository = listRepository,
                    onLogin = onLogin,
                    onOpenWork = onOpenWork,
                    sectionTitle = kind.label
                )
            }
        }
    }
}

@Composable
private fun WritingTabContent(
    signedIn: Boolean,
    kind: AccountWritingKind,
    onKindChange: (AccountWritingKind) -> Unit,
    selectedFandom: String?,
    onFandomChange: (String?) -> Unit,
    listRepository: AccountListRepository,
    onLogin: () -> Unit,
    onOpenWork: (AO3WorkSummary) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxSize()) {
        AccountListKindPicker(
            label = kind.label,
            icon = Icons.Outlined.Description,
            options = AccountWritingKind.entries.map { it.label to it },
            onSelect = onKindChange
        )

        if (!signedIn) {
            SignInRequiredCard(onLogin)
            return
        }

        when (kind) {
            AccountWritingKind.Works -> {
                HubWorksPane(
                    listType = AccountListType.MyWorks,
                    listRepository = listRepository,
                    onLogin = onLogin,
                    onOpenWork = onOpenWork,
                    sectionTitle = "Works",
                    fandomFilter = selectedFandom,
                    onFandomFilterChange = onFandomChange,
                    showFandomChips = true
                )
            }
            AccountWritingKind.Series -> {
                EmptyStateCard(
                    title = "Series not available yet",
                    message = "Your AO3 series will show here once list support lands."
                )
            }
            AccountWritingKind.Drafts -> {
                EmptyStateCard(
                    title = "Drafts not available yet",
                    message = "AO3 drafts stay on the website until a drafts parser is added."
                )
            }
        }
    }
}

@Composable
private fun ActivityTabContent(
    signedIn: Boolean,
    kind: AccountActivityKind,
    onKindChange: (AccountActivityKind) -> Unit,
    listRepository: AccountListRepository,
    onLogin: () -> Unit,
    onOpenWork: (AO3WorkSummary) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxSize()) {
        AccountListKindPicker(
            label = kind.label,
            icon = when (kind) {
                AccountActivityKind.History -> Icons.Outlined.History
                AccountActivityKind.Inbox -> Icons.Outlined.Inbox
            },
            options = AccountActivityKind.entries.map { it.label to it },
            onSelect = onKindChange
        )

        if (!signedIn) {
            SignInRequiredCard(onLogin)
            return
        }

        when (kind) {
            AccountActivityKind.History -> {
                HubWorksPane(
                    listType = AccountListType.History,
                    listRepository = listRepository,
                    onLogin = onLogin,
                    onOpenWork = onOpenWork,
                    sectionTitle = "My AO3 History"
                )
            }
            AccountActivityKind.Inbox -> {
                EmptyStateCard(
                    title = "Inbox not available yet",
                    message = "AO3 inbox messages stay on the website for now."
                )
            }
        }
    }
}

@Composable
private fun <T> AccountListKindPicker(
    label: String,
    icon: ImageVector,
    options: List<Pair<String, T>>,
    onSelect: (T) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    Box(modifier = Modifier.fillMaxWidth()) {
        Card(
            onClick = { expanded = true },
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceContainerLow
            ),
            shape = MaterialTheme.shapes.large
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 14.dp, vertical = 14.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(imageVector = icon, contentDescription = null, tint = Ao3Red)
                Text(
                    text = label,
                    style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier.weight(1f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Icon(
                    imageVector = Icons.Outlined.ExpandMore,
                    contentDescription = "Choose list",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            options.forEach { (optionLabel, value) ->
                DropdownMenuItem(
                    text = { Text(optionLabel) },
                    onClick = {
                        expanded = false
                        onSelect(value)
                    }
                )
            }
        }
    }
}

@Composable
private fun SignInRequiredCard(onLogin: () -> Unit) {
    EmptyStateCard(
        title = "AO3 session required",
        message = "Log in to AO3 to browse this account list.",
        primaryActionLabel = "Log In to AO3",
        onPrimaryAction = onLogin
    )
}

@Composable
private fun HubWorksPane(
    listType: AccountListType,
    listRepository: AccountListRepository,
    onLogin: () -> Unit,
    onOpenWork: (AO3WorkSummary) -> Unit,
    sectionTitle: String,
    fandomFilter: String? = null,
    onFandomFilterChange: (String?) -> Unit = {},
    showFandomChips: Boolean = false,
    viewModel: AccountListViewModel = viewModel(
        key = "hub-${listType.listKey}",
        factory = AccountListViewModel.factory(listType, listRepository)
    )
) {
    val state by viewModel.uiState.collectAsState()

    when (val current = state) {
        AccountListUiState.Loading -> LoadingStateCard("Loading ${listType.title}")
        AccountListUiState.AuthRequired -> SignInRequiredCard(onLogin)
        is AccountListUiState.Failed -> ErrorStateCard(
            title = "Could not load ${listType.title}",
            message = current.message,
            primaryActionLabel = "Retry",
            onPrimaryAction = { viewModel.load(1) }
        )
        is AccountListUiState.Loaded -> {
            val allWorks = current.page.works
            if (allWorks.isEmpty()) {
                EmptyStateCard(title = listType.emptyTitle, message = listType.emptyMessage)
                return
            }

            val fandomCounts = remember(allWorks) {
                allWorks
                    .flatMap { it.fandoms }
                    .filter { it.isNotBlank() }
                    .groupingBy { it }
                    .eachCount()
                    .entries
                    .sortedByDescending { it.value }
            }
            val works = if (fandomFilter.isNullOrBlank()) {
                allWorks
            } else {
                allWorks.filter { work -> work.fandoms.any { it == fandomFilter } }
            }

            LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = WorkCoverCardMetrics.width),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
                contentPadding = PaddingValues(bottom = 24.dp),
                modifier = Modifier.fillMaxSize()
            ) {
                if (showFandomChips && fandomCounts.isNotEmpty()) {
                    item(span = { GridItemSpan(maxLineSpan) }) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(
                                text = "Fandom",
                                style = MaterialTheme.typography.titleSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                item {
                                    FilterChip(
                                        selected = fandomFilter == null,
                                        onClick = { onFandomFilterChange(null) },
                                        label = { Text("All") }
                                    )
                                }
                                items(fandomCounts, key = { it.key }) { entry ->
                                    val label = if (entry.value > 1) {
                                        "${entry.key} (${entry.value})"
                                    } else {
                                        entry.key
                                    }
                                    FilterChip(
                                        selected = fandomFilter == entry.key,
                                        onClick = { onFandomFilterChange(entry.key) },
                                        label = {
                                            Text(
                                                text = label,
                                                maxLines = 1,
                                                overflow = TextOverflow.Ellipsis
                                            )
                                        }
                                    )
                                }
                            }
                        }
                    }
                }

                item(span = { GridItemSpan(maxLineSpan) }) {
                    KudosSectionHeader(
                        title = sectionTitle,
                        subtitle = if (current.page.totalPages > 1) {
                            "Page ${current.page.currentPage} of ${current.page.totalPages}"
                        } else {
                            null
                        }
                    )
                }

                if (works.isEmpty()) {
                    item(span = { GridItemSpan(maxLineSpan) }) {
                        EmptyStateCard(
                            title = "No works in this fandom",
                            message = "Try another fandom chip or clear the filter."
                        )
                    }
                } else {
                    gridItems(works, key = { "${listType.listKey}-${it.id}" }) { work ->
                        AccountRemoteWorkCover(work = work, onOpen = { onOpenWork(work) })
                    }
                }

                if (current.page.totalPages > 1) {
                    item(span = { GridItemSpan(maxLineSpan) }) {
                        PaginationControls(
                            page = current.page.currentPage,
                            totalPages = current.page.totalPages,
                            onLoadPage = viewModel::load
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun HubCollectionsPane(
    listRepository: AccountListRepository,
    onLogin: () -> Unit,
    onOpenCollection: (AO3Collection) -> Unit,
    onOpenFullIndex: () -> Unit,
    viewModel: AO3CollectionsViewModel = viewModel(
        key = "hub-collections",
        factory = AO3CollectionsViewModel.factory(listRepository)
    )
) {
    val state by viewModel.uiState.collectAsState()
    when (val current = state) {
        AO3CollectionsUiState.Loading -> LoadingStateCard("Loading collections")
        AO3CollectionsUiState.AuthRequired -> SignInRequiredCard(onLogin)
        is AO3CollectionsUiState.Failed -> ErrorStateCard(
            title = "Couldn't load collections",
            message = current.message,
            primaryActionLabel = "Retry",
            onPrimaryAction = viewModel::load
        )
        is AO3CollectionsUiState.Loaded -> {
            if (current.collections.isEmpty()) {
                EmptyStateCard(
                    title = "No collections yet",
                    message = "Collections you create or maintain on AO3 show up here."
                )
            } else {
                LazyColumn(
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    contentPadding = PaddingValues(bottom = 24.dp)
                ) {
                    item {
                        KudosSectionHeader(
                            title = "Collections",
                            trailing = {
                                TextButton(onClick = onOpenFullIndex) {
                                    Text("See all")
                                }
                            }
                        )
                    }
                    items(current.collections, key = { it.name }) { collection ->
                        Card(
                            onClick = { onOpenCollection(collection) },
                            colors = CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.surfaceContainerLow
                            ),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            ListItem(
                                headlineContent = { Text(collection.title) },
                                supportingContent = if (collection.byline.isNotBlank()) {
                                    {
                                        Text(
                                            text = collection.byline,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis
                                        )
                                    }
                                } else {
                                    null
                                },
                                leadingContent = {
                                    Icon(
                                        imageVector = Icons.Outlined.Collections,
                                        contentDescription = null,
                                        tint = Ao3Red
                                    )
                                },
                                trailingContent = {
                                    Icon(
                                        imageVector = Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                                        contentDescription = null
                                    )
                                },
                                colors = ListItemDefaults.colors(containerColor = Color.Transparent)
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun AccountRemoteWorkCover(
    work: AO3WorkSummary,
    onOpen: () -> Unit
) {
    WorkCoverCard(
        title = work.title,
        author = work.authorText,
        fandom = work.fandoms.firstOrNull { it.isNotBlank() },
        stats = coverCardStats(
            rating = work.rating,
            chapters = work.chapters,
            isComplete = work.isComplete == true,
            wordCount = work.wordCount?.takeIf { it > 0 },
            kudos = work.kudos?.takeIf { it > 0 }
        ),
        onOpen = onOpen,
        onOpenDetails = onOpen,
        modifier = Modifier.fillMaxWidth(),
        statusChips = listOfNotNull(
            if (work.isRestricted) "Restricted" else null
        ),
        contentDescription = "Open ${work.title}, by ${work.authorText}"
    )
}

// endregion

// region Full-page list (existing destinations)

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
            style = MaterialTheme.typography.labelLarge,
            textAlign = TextAlign.Center
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

// endregion
