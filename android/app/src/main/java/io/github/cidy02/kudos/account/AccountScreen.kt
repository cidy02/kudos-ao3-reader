package io.github.cidy02.kudos.account
import androidx.compose.foundation.background
import io.github.cidy02.kudos.R

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material3.Scaffold
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.ui.text.font.FontFamily
import io.github.cidy02.kudos.ui.subject.AccentIconSquare
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectChip

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.automirrored.outlined.Assignment
import androidx.compose.material.icons.automirrored.outlined.CallSplit
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.outlined.List
import androidx.compose.material.icons.automirrored.outlined.Logout
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.Cancel
import androidx.compose.material.icons.outlined.CardGiftcard
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Collections
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Drafts
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.Flag
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.NotificationsNone
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.People
import androidx.compose.material.icons.outlined.PersonAdd
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material.icons.outlined.Verified
import androidx.compose.material.icons.outlined.WifiOff
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
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.AO3AuthState
import io.github.cidy02.kudos.auth.AO3SessionHealth
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
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.library.LibraryWorkListItem
import io.github.cidy02.kudos.library.LibraryDisplayItem
import io.github.cidy02.kudos.library.LibraryCarouselCard
import io.github.cidy02.kudos.library.LibraryCardActions
import java.util.concurrent.TimeUnit

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
    workRepository: WorkRepository,
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
    onOpenSeries: (String) -> Unit = {},
    inboxRepository: io.github.cidy02.kudos.network.ao3.inbox.AO3InboxRepository? = null,
    commentRepository: io.github.cidy02.kudos.network.ao3.comments.AO3CommentRepository? = null,
    authorRepository: io.github.cidy02.kudos.network.ao3.author.AO3AuthorRepository? = null,
    countsCache: io.github.cidy02.kudos.account.AO3AccountListCountsCache? = null,
    onOpenWorkComments: (workId: Long, focusedId: Long?) -> Unit = { _, _ -> },
    modifier: Modifier = Modifier,
    viewModel: AccountViewModel = viewModel(
        factory = AccountViewModel.factory(
            authRepository,
            authorRepository,
            countsCache
        )
    )
) {
    val state by viewModel.uiState.collectAsState()
    val signedIn = state.authState is AO3AuthState.SignedIn
    val username = (state.authState as? AO3AuthState.SignedIn)?.username
    
    var activePage by rememberSaveable { mutableStateOf<String?>(null) }

    BackHandler(enabled = activePage != null) {
        activePage = null
    }

    if (activePage == "Inbox" && inboxRepository != null && commentRepository != null) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text("Inbox") },
                    navigationIcon = {
                        IconButton(onClick = { activePage = null }) {
                            Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back")
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = MaterialTheme.colorScheme.background
                    )
                )
            }
        ) { padding ->
            Box(modifier = Modifier.padding(padding)) {
                AccountInboxPane(
                    inboxRepository = inboxRepository,
                    commentRepository = commentRepository,
                    currentUsername = username,
                    onOpenWorkComments = onOpenWorkComments,
                    settingsRepository = listRepository.settingsRepository
                )
            }
        }
        return
    }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = 32.dp)
    ) {
        item {
            AccountProfileHeader(
                authState = state.authState,
                sessionHealth = state.sessionHealth,
                avatarUrl = state.header?.avatarUrl,
                onLogin = onLogin,
                onLogout = viewModel::logout,
                onVerifySession = viewModel::verifySession,
                onOpenSettings = onOpenSettings,
                onOpenAbout = onOpenAbout,
                onOpenPrivacy = onOpenPrivacy,
                onOpenBackup = onOpenBackup,
                onOpenLocalHistory = onOpenLocalHistory,
                onOpenLocalFavorites = onOpenLocalFavorites,
                onOpenCollections = onOpenCollections,
                onOpenAuthorProfile = { onOpenWeb("native:profile") }
            )
        }

        if (signedIn) {
            item { Spacer(Modifier.height(16.dp)) }
            
            item {
                AccountHubShortcuts(
                    counts = state.counts,
                    onOpenDashboard = onOpenDashboard,
                    onOpenList = onOpenList,
                    onOpenAO3Collections = onOpenAO3Collections,
                    onOpenWeb = onOpenWeb,
                    onOpenInbox = { activePage = "Inbox" }
                )
            }
            
            item { Spacer(Modifier.height(16.dp)) }

            item {
                AccountScopeGroup("Reading") {
                    AccountScopeRow(
                        title = "Marked for Later",
                        icon = Icons.Outlined.Schedule,
                        count = state.counts[AccountListType.MarkedForLater.listKey]?.displayText,
                        onClick = { onOpenList(AccountListType.MarkedForLater) }
                    )
                    HorizontalDivider(modifier = Modifier.padding(start = 50.dp))
                    AccountScopeRow(
                        title = "Bookmarks",
                        icon = Icons.Outlined.BookmarkBorder,
                        count = state.counts[AccountListType.Bookmarks.listKey]?.displayText,
                        onClick = { onOpenList(AccountListType.Bookmarks) }
                    )
                    HorizontalDivider(modifier = Modifier.padding(start = 50.dp))
                    AccountScopeRow(
                        title = "Collections",
                        icon = Icons.Outlined.Collections,
                        onClick = onOpenAO3Collections
                    )
                    HorizontalDivider(modifier = Modifier.padding(start = 50.dp))
                    AccountScopeRow(
                        title = "Subscriptions",
                        icon = Icons.Outlined.NotificationsNone,
                        count = state.counts[AccountListType.Subscriptions.listKey]?.displayText,
                        onClick = { onOpenList(AccountListType.Subscriptions) }
                    )
                }
            }

            item { Spacer(Modifier.height(16.dp)) }

            item {
                AccountScopeGroup("Writing") {
                    AccountScopeRow(
                        title = "Works",
                        icon = Icons.Outlined.Description,
                        count = state.counts[AccountListType.MyWorks.listKey]?.displayText,
                        onClick = { onOpenList(AccountListType.MyWorks) }
                    )
                    HorizontalDivider(modifier = Modifier.padding(start = 50.dp))
                    AccountScopeRow(
                        title = "Series",
                        icon = Icons.Outlined.Collections,
                        onClick = { username?.let { onOpenSeries("https://archiveofourown.org/users/$it/series") } }
                    )
                    HorizontalDivider(modifier = Modifier.padding(start = 50.dp))
                    AccountScopeRow(
                        title = "Drafts",
                        subtitle = "Deleted by AO3 after 30 days",
                        icon = Icons.Outlined.Drafts,
                        onClick = { username?.let { onOpenWeb("https://archiveofourown.org/users/$it/works/drafts") } }
                    )
                }
            }

            item { Spacer(Modifier.height(16.dp)) }

            item {
                AccountScopeGroup("Activity") {
                    AccountScopeRow(
                        title = "History",
                        subtitle = "Your AO3 history, not your reading activity in Kudos",
                        icon = Icons.Outlined.History,
                        count = state.counts[AccountListType.History.listKey]?.displayText,
                        onClick = { onOpenList(AccountListType.History) }
                    )
                    HorizontalDivider(modifier = Modifier.padding(start = 50.dp))
                    AccountScopeRow(
                        title = "Inbox",
                        icon = Icons.Outlined.Inbox,
                        onClick = { activePage = "Inbox" }
                    )
                }
            }

            item { Spacer(Modifier.height(16.dp)) }

            item {
                AccountScopeGroup("Account") {
                    AccountScopeRow(
                        title = "Preferences",
                        icon = Icons.Outlined.Tune,
                        onClick = { onOpenWeb("native:preferences") }
                    )
                    HorizontalDivider(modifier = Modifier.padding(start = 50.dp))
                    
                    var moreOnAo3MenuOpen by remember { mutableStateOf(false) }
                    Box {
                        AccountScopeRow(
                            title = "More on AO3",
                            icon = Icons.Outlined.Public,
                            onClick = { moreOnAo3MenuOpen = true }
                        )
                        DropdownMenu(
                            expanded = moreOnAo3MenuOpen,
                            onDismissRequest = { moreOnAo3MenuOpen = false }
                        ) {
                            val destinations = listOf(
                                Triple("Drafts", Icons.Outlined.Drafts, "works/drafts"),
                                Triple("Pseuds", Icons.Outlined.People, "pseuds"),
                                Triple("Skins", Icons.Outlined.Palette, "skins"),
                                Triple("Statistics", Icons.Outlined.BarChart, "stats"),
                                Triple("Co-Creator Requests", Icons.Outlined.PersonAdd, "creatorships"),
                                Triple("Sign-ups", Icons.Outlined.EditNote, "signups"),
                                Triple("Assignments", Icons.AutoMirrored.Outlined.Assignment, "assignments"),
                                Triple("Claims", Icons.Outlined.Flag, "claims"),
                                Triple("Related Works", Icons.AutoMirrored.Outlined.CallSplit, "related_works"),
                                Triple("Gifts", Icons.Outlined.CardGiftcard, "gifts")
                            )
                            destinations.forEach { (title, icon, pathSuffix) ->
                                DropdownMenuItem(
                                    text = { Text(title) },
                                    leadingIcon = {
                                        Icon(imageVector = icon, contentDescription = null)
                                    },
                                    onClick = {
                                        moreOnAo3MenuOpen = false
                                        if (username != null) {
                                            onOpenWeb("https://archiveofourown.org/users/$username/$pathSuffix")
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
            }
        } else {
            item { Spacer(Modifier.height(16.dp)) }
            item {
                SignedOutPreviewSection()
            }
        }
    }
}

@Composable
private fun AccountProfileHeader(
    authState: AO3AuthState,
    sessionHealth: AO3SessionHealth,
    avatarUrl: String?,
    onLogin: () -> Unit,
    onLogout: () -> Unit,
    onVerifySession: () -> Unit,
    onOpenSettings: () -> Unit,
    onOpenAbout: () -> Unit,
    onOpenPrivacy: () -> Unit,
    onOpenBackup: () -> Unit,
    onOpenLocalHistory: () -> Unit,
    onOpenLocalFavorites: () -> Unit,
    onOpenCollections: () -> Unit,
    onOpenAuthorProfile: () -> Unit = {}
) {
    var menuOpen by remember { mutableStateOf(false) }

    Column(modifier = Modifier.padding(horizontal = 12.dp)) {
        Text(
            text = "AO3 ACCOUNT",
            style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(bottom = 8.dp, start = 4.dp)
        )
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
                Box(modifier = Modifier.clickable(enabled = authState is AO3AuthState.SignedIn) {
                    onOpenAuthorProfile()
                }) {
                    AccountAvatar(avatarUrl = avatarUrl)
                }

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
                                    text = if (authState is AO3AuthState.SigningIn) "Signing in…" else "Checking session…",
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
                                SessionHealthIcon(sessionHealth)
                            }
                            Text(
                                text = "Signed in",
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.secondary
                            )
                            Card(
                                shape = androidx.compose.foundation.shape.CircleShape,
                                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
                                modifier = Modifier.padding(top = 4.dp)
                            ) {
                                Text(
                                    text = "Posting as Account Default",
                                    style = MaterialTheme.typography.labelSmall,
                                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
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
                        if (authState is AO3AuthState.SignedIn) {
                            DropdownMenuItem(
                                text = {
                                    Text(
                                        if (sessionHealth.isChecking) "Checking…" else "Verify Session"
                                    )
                                },
                                leadingIcon = {
                                    if (sessionHealth.isChecking) {
                                        CircularProgressIndicator(
                                            modifier = Modifier.size(18.dp),
                                            strokeWidth = 2.dp
                                        )
                                    } else {
                                        Icon(
                                            imageVector = Icons.Outlined.Refresh,
                                            contentDescription = null
                                        )
                                    }
                                },
                                enabled = !sessionHealth.isChecking,
                                onClick = {
                                    menuOpen = false
                                    onVerifySession()
                                }
                            )
                            HorizontalDivider()
                        }
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
}

@Composable
private fun SessionHealthIcon(health: AO3SessionHealth) {
    when (health) {
        AO3SessionHealth.Unknown -> {
            Icon(
                imageVector = Icons.Outlined.CheckCircle,
                contentDescription = "Signed in",
                tint = Color(0xFF34C759),
                modifier = Modifier.size(20.dp)
            )
        }
        AO3SessionHealth.Verifying -> {
            CircularProgressIndicator(
                modifier = Modifier.size(18.dp),
                strokeWidth = 2.dp
            )
        }
        is AO3SessionHealth.Healthy -> {
            Icon(
                imageVector = Icons.Outlined.Verified,
                contentDescription = "Session verified",
                tint = Color(0xFF34C759),
                modifier = Modifier.size(20.dp)
            )
        }
        AO3SessionHealth.Expired -> {
            Icon(
                imageVector = Icons.Outlined.Cancel,
                contentDescription = "Session expired",
                tint = MaterialTheme.colorScheme.error,
                modifier = Modifier.size(20.dp)
            )
        }
        AO3SessionHealth.Unreachable -> {
            Icon(
                imageVector = Icons.Outlined.WifiOff,
                contentDescription = "Network unreachable",
                tint = Color(0xFFFF9500),
                modifier = Modifier.size(20.dp)
            )
        }
    }
}

@Composable
private fun AccountAvatar(avatarUrl: String?) {
    Box(
        modifier = Modifier
            .size(56.dp)
            .clip(androidx.compose.foundation.shape.CircleShape)
            .background(MaterialTheme.colorScheme.surfaceVariant)
    ) {
        if (avatarUrl != null) {
            AsyncImage(
                model = ImageRequest.Builder(LocalContext.current)
                    .data(avatarUrl)
                    .crossfade(true)
                    .build(),
                contentDescription = "Avatar",
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop
            )
        } else {
            Icon(
                painter = painterResource(id = R.drawable.ic_kudos_mark),
                contentDescription = "Default avatar",
                modifier = Modifier
                    .fillMaxSize()
                    .padding(8.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun AccountShortcutGridTile(
    title: String,
    icon: ImageVector,
    count: String? = null,
    onClick: () -> Unit
) {
    Card(
        onClick = onClick,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
        shape = RoundedCornerShape(14.dp)
    ) {
        Column(
            modifier = Modifier.padding(10.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
            horizontalAlignment = Alignment.Start
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top
            ) {
                AccentIconSquare(icon = icon, contentDescription = null)
                if (count != null) {
                    Text(
                        text = count,
                        style = MaterialTheme.typography.labelSmall.copy(
                            fontFamily = FontFamily.Monospace,
                            fontWeight = FontWeight.Medium
                        ),
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            Text(
                text = title,
                style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Medium),
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
fun AccountScopeRow(
    title: String,
    icon: ImageVector,
    subtitle: String? = null,
    count: String? = null,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick() }
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        AccentIconSquare(icon = icon, contentDescription = null)
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            if (subtitle != null) {
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (count != null) {
            Text(
                text = count, 
                style = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace), 
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Icon(
            imageVector = Icons.AutoMirrored.Outlined.KeyboardArrowRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(20.dp)
        )
    }
}

@Composable
fun AccountScopeGroup(
    title: String,
    content: @Composable () -> Unit
) {
    var collapsed by rememberSaveable { mutableStateOf(false) }
    Column(modifier = Modifier.padding(horizontal = 12.dp)) {
        SectionRuleHeader(
            title = title,
            isCollapsed = collapsed,
            onToggleCollapse = { collapsed = !collapsed }
        )
        AnimatedVisibility(visible = !collapsed) {
            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
                shape = MaterialTheme.shapes.large
            ) {
                Column {
                    content()
                }
            }
        }
    }
}

@Composable
private fun AccountHubShortcuts(
    counts: Map<String, AO3AccountListCountsCache.Count>,
    onOpenDashboard: () -> Unit,
    onOpenList: (AccountListType) -> Unit,
    onOpenAO3Collections: () -> Unit,
    onOpenWeb: (String) -> Unit,
    onOpenInbox: () -> Unit
) {
    val defaults = listOf(
        ShortcutItem("Dashboard", Icons.Outlined.GridView, onClick = onOpenDashboard),
        ShortcutItem("Subscriptions", Icons.Outlined.NotificationsNone, count = counts[AccountListType.Subscriptions.listKey], onClick = { onOpenList(AccountListType.Subscriptions) }),
        ShortcutItem("Works", Icons.Outlined.Description, count = counts[AccountListType.MyWorks.listKey], onClick = { onOpenList(AccountListType.MyWorks) }),
        ShortcutItem("Bookmarks", Icons.Outlined.BookmarkBorder, count = counts[AccountListType.Bookmarks.listKey], onClick = { onOpenList(AccountListType.Bookmarks) }),
        ShortcutItem("Collections", Icons.Outlined.Collections, onClick = onOpenAO3Collections),
        ShortcutItem("History", Icons.Outlined.History, count = counts[AccountListType.History.listKey], onClick = { onOpenList(AccountListType.History) })
    )

    Column(modifier = Modifier.padding(horizontal = 12.dp)) {
        SectionRuleHeader(
            title = "Shortcuts",
            onSeeAll = { /* TODO implement shortcut editor */ }
        )
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            defaults.chunked(3).forEach { row ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    row.forEach { item ->
                        Box(modifier = Modifier.weight(1f)) {
                            AccountShortcutGridTile(
                                title = item.title,
                                icon = item.icon,
                                count = item.count?.displayText,
                                onClick = item.onClick
                            )
                        }
                    }
                    repeat(3 - row.size) {
                        Spacer(modifier = Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

private data class ShortcutItem(
    val title: String,
    val icon: ImageVector,
    val count: AO3AccountListCountsCache.Count? = null,
    val onClick: () -> Unit
)

@Composable
private fun SignedOutPreviewSection() {
    Column(modifier = Modifier.padding(horizontal = 12.dp)) {
        SectionRuleHeader(title = "What is waiting")
        Text(
            text = "When you sign in, this tab shows your AO3 account and activity.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(bottom = 14.dp, start = 4.dp)
        )

        Row(
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(bottom = 16.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(androidx.compose.foundation.shape.CircleShape)
                    .background(MaterialTheme.colorScheme.surfaceVariant)
            ) {
                Icon(
                    painter = painterResource(id = R.drawable.ic_kudos_mark),
                    contentDescription = null,
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(8.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Text(
                text = "Your username",
                style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold),
                color = MaterialTheme.colorScheme.onSurface
            )
        }

        AccountScopeGroup("Reading") {
            AccountScopeRow(title = "Marked for Later", icon = Icons.Outlined.Schedule, onClick = {})
            HorizontalDivider(modifier = Modifier.padding(start = 50.dp))
            AccountScopeRow(title = "Bookmarks", icon = Icons.Outlined.BookmarkBorder, onClick = {})
            HorizontalDivider(modifier = Modifier.padding(start = 50.dp))
            AccountScopeRow(title = "Collections", icon = Icons.Outlined.Collections, onClick = {})
            HorizontalDivider(modifier = Modifier.padding(start = 50.dp))
            AccountScopeRow(title = "Subscriptions", icon = Icons.Outlined.NotificationsNone, onClick = {})
        }
        Spacer(Modifier.height(16.dp))
        AccountScopeGroup("Writing") {
            AccountScopeRow(title = "Works", icon = Icons.Outlined.Description, onClick = {})
            HorizontalDivider(modifier = Modifier.padding(start = 50.dp))
            AccountScopeRow(title = "Series", icon = Icons.Outlined.Collections, onClick = {})
            HorizontalDivider(modifier = Modifier.padding(start = 50.dp))
            AccountScopeRow(title = "Drafts", icon = Icons.Outlined.Drafts, onClick = {})
        }
        Spacer(Modifier.height(16.dp))
        AccountScopeGroup("Activity") {
            AccountScopeRow(title = "History", icon = Icons.Outlined.History, onClick = {})
            HorizontalDivider(modifier = Modifier.padding(start = 50.dp))
            AccountScopeRow(title = "Inbox", icon = Icons.Outlined.Inbox, onClick = {})
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
    workRepository: WorkRepository,
    onLogin: () -> Unit,
    onOpenWork: (AO3WorkSummary) -> Unit,
    sectionTitle: String,
    fandomFilter: String? = null,
    onFandomFilterChange: (String?) -> Unit = {},
    showFandomChips: Boolean = false,
    detailedMode: Boolean = false,
    viewModel: AccountListViewModel = viewModel(
        key = "hub-${listType.listKey}",
        factory = AccountListViewModel.factory(listType, listRepository, workRepository)
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
            val allWorks = current.canonicalWorks
            if (allWorks.isEmpty() && current.page.works.isEmpty()) {
                EmptyStateCard(title = listType.emptyTitle, message = listType.emptyMessage)
                return
            }

            val fandomCounts = remember(allWorks) {
                allWorks
                    .flatMap { it.remote.fandoms }
                    .filter { it.isNotBlank() }
                    .groupingBy { it }
                    .eachCount()
                    .entries
                    .sortedByDescending { it.value }
            }
            val works = if (fandomFilter.isNullOrBlank()) {
                allWorks
            } else {
                allWorks.filter { work -> work.remote.fandoms.any { it == fandomFilter } }
            }

            if (detailedMode) {
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
                            if (work.local != null) {
                                LibraryCarouselCard(
                                    display = LibraryDisplayItem(
                                        item = LibraryWorkListItem(
                                            work = work.local,
                                            userTags = emptyList(), // Later: pair tags too
                                            collections = emptyList()
                                        )
                                    ),
                                    showProgress = true,
                                    footerOverride = null,
                                    actions = LibraryCardActions(
                                        onOpenWork = { onOpenWork(work.remote) },
                                        onOpenReader = { onOpenWork(work.remote) }, // Detail handles read
                                        onToggleFavorite = { },
                                        onToggleFinished = { },
                                        onRemove = { },
                                        onDownloadAction = { _, _ -> },
                                        onSelect = { },
                                        onReveal = { },
                                        onAddToQueue = { },
                                        onAddToCollection = { },
                                        onOpenComments = { }
                                    )
                                )
                            } else {
                                AccountRemoteWorkCover(work = work.remote, onOpen = { onOpenWork(work.remote) })
                            }
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
            } else {
                LazyColumn(
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    contentPadding = PaddingValues(bottom = 24.dp),
                    modifier = Modifier.fillMaxSize()
                ) {
                    if (showFandomChips && fandomCounts.isNotEmpty()) {
                        item {
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
                                        FilterChip(
                                            selected = fandomFilter == entry.key,
                                            onClick = { onFandomFilterChange(entry.key) },
                                            label = { Text(entry.key) }
                                        )
                                    }
                                }
                            }
                        }
                    }
                    item {
                        KudosSectionHeader(title = sectionTitle)
                    }
                    items(works, key = { "${listType.listKey}-${it.id}" }) { work ->
                        AO3WorkCard(
                            work = work.remote,
                            onOpenWork = onOpenWork,
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                    if (current.page.totalPages > 1) {
                        item {
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
        workId = work.id,
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
    workRepository: WorkRepository,
    onLogin: () -> Unit,
    onOpenWork: (AO3WorkSummary) -> Unit,
    modifier: Modifier = Modifier,
    viewModel: AccountListViewModel = viewModel(
        key = type.listKey,
        factory = AccountListViewModel.factory(type, repository, workRepository)
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
                if (current.canonicalWorks.isEmpty() && current.page.works.isEmpty()) {
                    EmptyStateCard(
                        title = type.emptyTitle,
                        message = type.emptyMessage
                    )
                } else {
                    AccountListContent(
                        type = type,
                        page = current.page.currentPage,
                        totalPages = current.page.totalPages,
                        works = current.canonicalWorks,
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
    works: List<io.github.cidy02.kudos.works.CanonicalWork>,
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
            if (work.local != null) {
                LibraryCarouselCard(
                    display = LibraryDisplayItem(
                        item = LibraryWorkListItem(
                            work = work.local,
                            userTags = emptyList(), // Later: pair tags too
                            collections = emptyList()
                        )
                    ),
                    showProgress = true,
                    footerOverride = null,
                    actions = LibraryCardActions(
                        onOpenWork = { onOpenWork(work.remote) },
                        onOpenReader = { onOpenWork(work.remote) }, // Detail handles read
                        onToggleFavorite = { },
                        onToggleFinished = { },
                        onRemove = { },
                        onDownloadAction = { _, _ -> },
                        onSelect = { },
                        onReveal = { },
                        onAddToQueue = { },
                        onAddToCollection = { },
                        onOpenComments = { }
                    )
                )
            } else {
                EnrichingAO3WorkCard(work = work.remote, onOpenWork = onOpenWork)
            }
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

/**
 * An AO3 work card that fills itself in when the listing it came from was sparse.
 *
 * AO3's subscriptions page lists only title, id and author, so those cards would
 * otherwise show no tags, no stats and no summary. The fetch happens per card as it
 * appears rather than for the whole page up front: 20 works would be 20 politeness
 * slots before anything could render, and scrolling past a work you didn't care
 * about would still have cost one.
 *
 * A card that is already complete — every other list — does no work at all;
 * `enrich` returns null immediately and this stays exactly [AO3WorkCard].
 */
@Composable
private fun EnrichingAO3WorkCard(
    work: AO3WorkSummary,
    onOpenWork: (AO3WorkSummary) -> Unit
) {
    val context = LocalContext.current
    val enricher = remember {
        (context.applicationContext as? io.github.cidy02.kudos.KudosApplication)
            ?.container?.sparseWorkEnricher
    }
    var enriched by remember(work.id) { mutableStateOf<AO3WorkSummary?>(null) }

    // Keyed on the id so recycling this slot onto a different work restarts the
    // effect instead of showing the previous work's metadata.
    LaunchedEffect(work.id) {
        enriched = enricher?.enrich(work)
    }

    AO3WorkCard(work = enriched ?: work, onOpenWork = onOpenWork)
}
