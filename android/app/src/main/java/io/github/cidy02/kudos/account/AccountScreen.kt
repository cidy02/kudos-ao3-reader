package io.github.cidy02.kudos.account
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import io.github.cidy02.kudos.R

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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.automirrored.outlined.Login
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.font.FontFamily
import io.github.cidy02.kudos.ui.subject.AccentIconSquare
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.LocalSubjectPalette
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectChip
import io.github.cidy02.kudos.ui.subject.SubjectKicker
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale
import io.github.cidy02.kudos.ui.subject.subjectScreenWash

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
import io.github.cidy02.kudos.ui.components.LogOutConfirmation
import io.github.cidy02.kudos.ui.components.SensitiveWorkRow
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
    onOpenAO3Collections: () -> Unit = {},
    onOpenDrafts: () -> Unit = {},
    onOpenDashboard: () -> Unit = {},
    onOpenWeb: (String) -> Unit = {},
    onOpenWork: (AO3WorkSummary) -> Unit = {},
    onOpenCollection: (AO3Collection) -> Unit = {},
    onOpenSeries: (String) -> Unit = {},
    inboxRepository: io.github.cidy02.kudos.network.ao3.inbox.AO3InboxRepository? = null,
    commentRepository: io.github.cidy02.kudos.network.ao3.comments.AO3CommentRepository? = null,
    authorRepository: io.github.cidy02.kudos.network.ao3.author.AO3AuthorRepository? = null,
    countsCache: io.github.cidy02.kudos.account.AO3AccountListCountsCache? = null,
    onOpenWorkComments: (workId: Long, focusedId: Long?) -> Unit = { _, _ -> },
    // Inbox is its own pushed route (iOS pushes AccountInboxScreen); see Routes.AccountInbox.
    onOpenInbox: () -> Unit = {},
    settingsRepository: io.github.cidy02.kudos.data.preferences.SettingsRepository? = null,
    onEditShortcuts: () -> Unit = {},
    modifier: Modifier = Modifier,
    viewModel: AccountViewModel = viewModel(
        factory = AccountViewModel.factory(
            authRepository,
            authorRepository,
            countsCache,
            listRepository
        )
    )
) {
    val state by viewModel.uiState.collectAsState()
    val shortcuts by (settingsRepository?.accountShortcuts ?: kotlinx.coroutines.flow.flowOf(AccountShortcutStore.defaults))
        .collectAsState(initial = AccountShortcutStore.defaults)
    val signedIn = state.authState is AO3AuthState.SignedIn
    val username = (state.authState as? AO3AuthState.SignedIn)?.username
    val palette = LocalSubjectPalette.current
    val tokens = LocalKudosTokens.current
    
    // The signed-in wash is drawn by the shell (MainScaffold), so it reaches the top edge.
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = 32.dp)
    ) {
        item {
            AccountProfileHeader(
                authState = state.authState,
                sessionHealth = state.sessionHealth,
                avatarUrl = state.header?.avatarUrl,
                pseuds = state.header?.pseuds.orEmpty(),
                onLogin = onLogin,
                onLogout = viewModel::logout,
                onVerifySession = viewModel::verifySession,
                onOpenAuthorProfile = { onOpenWeb("native:profile") },
                onOpenWeb = onOpenWeb
            )
        }

        if (signedIn) {
            item { Spacer(Modifier.height(16.dp)) }
            
            item {
                AccountHubShortcuts(shortcuts, state.counts, onEditShortcuts) { shortcut ->
                    shortcut.listType?.let(onOpenList) ?: when (shortcut) {
                        AccountShortcut.Dashboard -> onOpenDashboard()
                        AccountShortcut.Collections -> onOpenAO3Collections()
                        AccountShortcut.Drafts -> onOpenDrafts()
                        AccountShortcut.Inbox -> onOpenInbox()
                        AccountShortcut.Preferences -> onOpenWeb("native:preferences")
                        AccountShortcut.MoreOnAO3 -> onOpenWeb("native:more-on-ao3")
                        else -> Unit
                    }
                }
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
                    AccountDraftsRow(onOpenDrafts)
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
                        onClick = onOpenInbox
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
                                Triple("Skins and site styles", Icons.Outlined.Palette, "skins"),
                                Triple("Statistics", Icons.Outlined.BarChart, "stats"),
                                Triple("Co-Creator Requests", Icons.Outlined.PersonAdd, "creatorships"),
                                Triple("Sign-ups", Icons.Outlined.EditNote, "signups"),
                                Triple("Assignments", Icons.AutoMirrored.Outlined.Assignment, "assignments"),
                                Triple("Claims", Icons.Outlined.Flag, "claims"),
                                Triple("Related works", Icons.AutoMirrored.Outlined.CallSplit, "related_works"),
                                Triple("Gifts given and received", Icons.Outlined.CardGiftcard, "gifts")
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
    pseuds: List<io.github.cidy02.kudos.network.ao3.author.AO3AuthorPseud> = emptyList(),
    onLogin: () -> Unit,
    onLogout: () -> Unit,
    onVerifySession: () -> Unit,
    onOpenAuthorProfile: () -> Unit = {},
    onOpenWeb: (String) -> Unit = {}
) {
    if (authState is AO3AuthState.SignedIn) {
        AccountSignedInHeader(
            username = authState.username,
            sessionHealth = sessionHealth,
            avatarUrl = avatarUrl,
            pseuds = pseuds,
            onOpenAuthorProfile = onOpenAuthorProfile,
            onVerifySession = onVerifySession,
            onLogout = onLogout,
            onOpenWeb = onOpenWeb
        )
    } else {
        AccountSignedOutHeader(authState = authState, onLogin = onLogin)
    }
}

@Composable
private fun AccountSignedInHeader(
    username: String,
    sessionHealth: AO3SessionHealth,
    avatarUrl: String?,
    pseuds: List<io.github.cidy02.kudos.network.ao3.author.AO3AuthorPseud>,
    onOpenAuthorProfile: () -> Unit,
    onVerifySession: () -> Unit,
    onLogout: () -> Unit,
    onOpenWeb: (String) -> Unit
) {
    val tokens = LocalKudosTokens.current
    val palette = LocalSubjectPalette.current
    var pseudMenuOpen by remember { mutableStateOf(false) }
    var menuOpen by remember { mutableStateOf(false) }
    var postingPseudName by rememberSaveable { mutableStateOf<String?>(null) }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = SubjectMetrics.accountGutter, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(13.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        AccountAvatar(
            avatarUrl = avatarUrl,
            onClick = onOpenAuthorProfile
        )

        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            SubjectKicker(
                text = "AO3 Account",
                palette = palette,
                ruleWidth = SubjectMetrics.pageRuleWidth,
                ruleSpacing = 7.dp
            )

            Text(
                text = username,
                fontSize = 27.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = (-0.5).sp,
                color = tokens.primaryInk,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp)
            ) {
                Box(
                    modifier = Modifier
                        .size(7.dp)
                        .background(
                            when (sessionHealth) {
                                AO3SessionHealth.Expired -> MaterialTheme.colorScheme.error
                                AO3SessionHealth.Unreachable -> Color(0xFFFF9500)
                                else -> Color(0xFF34C759)
                            },
                            CircleShape
                        )
                )
                Text(
                    text = when (sessionHealth) {
                        AO3SessionHealth.Verifying -> "Checking session…"
                        AO3SessionHealth.Expired -> "Session expired"
                        AO3SessionHealth.Unreachable -> "Signed in · couldn't verify"
                        else -> "Signed in"
                    },
                    fontSize = 12.sp,
                    color = tokens.secondaryInk,
                    maxLines = 1
                )
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.padding(top = 4.dp)
            ) {
                // The pill gives way, not the menu beside it: at large text it filled the row and
                // pushed the "…" button off it.
                Box(Modifier.weight(1f, fill = false)) {
                    Box(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(tokens.glassFill(0.12))
                            .clickable { pseudMenuOpen = true }
                            .padding(horizontal = 13.dp, vertical = 7.dp)
                    ) {
                        Text(
                            text = "Posting as ${postingPseudName ?: "Account Default"}",
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Medium,
                            color = tokens.primaryInk,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                    DropdownMenu(
                        expanded = pseudMenuOpen,
                        onDismissRequest = { pseudMenuOpen = false }
                    ) {
                        DropdownMenuItem(
                            text = { Text("Account Default") },
                            trailingIcon = if (postingPseudName == null) {
                                { Icon(Icons.Filled.Check, contentDescription = null) }
                            } else null,
                            onClick = {
                                postingPseudName = null
                                pseudMenuOpen = false
                            }
                        )
                        pseuds.forEach { pseud ->
                            DropdownMenuItem(
                                text = { Text(pseud.name) },
                                trailingIcon = if (postingPseudName == pseud.name) {
                                    { Icon(Icons.Filled.Check, contentDescription = null) }
                                } else null,
                                onClick = {
                                    postingPseudName = pseud.name
                                    pseudMenuOpen = false
                                }
                            )
                        }
                    }
                }

                Box {
                    Box(
                        modifier = Modifier
                            .size(width = 36.dp, height = 30.dp)
                            .clip(CircleShape)
                            .background(tokens.glassFill(0.12))
                            .clickable { menuOpen = true },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.MoreHoriz,
                            contentDescription = "Account actions",
                            tint = tokens.primaryInk,
                            modifier = Modifier.size(18.dp)
                        )
                    }
                    AccountOverflowDropdownMenu(
                        expanded = menuOpen,
                        onDismissRequest = { menuOpen = false },
                        sessionHealth = sessionHealth,
                        username = username,
                        onVerifySession = onVerifySession,
                        onLogout = onLogout,
                        onOpenWeb = onOpenWeb
                    )
                }
            }
        }
    }
}

@Composable
private fun AccountSignedOutHeader(
    authState: AO3AuthState,
    onLogin: () -> Unit,
) {
    val tokens = LocalKudosTokens.current

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = SubjectMetrics.accountGutter, vertical = 4.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(13.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            AccountAvatar(avatarUrl = null)

            Text(
                text = when (authState) {
                    is AO3AuthState.Expired -> "Session expired"
                    is AO3AuthState.Error -> "Account error"
                    else -> "Not signed in"
                },
                style = MaterialTheme.typography.titleLarge.copy(
                    fontSize = 27.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = (-0.5).sp
                ),
                color = if (authState is AO3AuthState.Expired || authState is AO3AuthState.Error) {
                    MaterialTheme.colorScheme.error
                } else {
                    tokens.primaryInk
                },
                modifier = Modifier.weight(1f),
                maxLines = 2
            )

        }

        Text(
            text = "Log in to see your AO3 works, bookmarks, subscriptions, history and inbox. Your sign-in stays on this device.",
            fontSize = 13.sp,
            color = tokens.secondaryInk,
            lineHeight = 18.sp
        )

        Button(
            onClick = onLogin,
            shape = CircleShape,
            colors = ButtonDefaults.buttonColors(
                containerColor = tokens.accent,
                contentColor = Color.White
            ),
            enabled = authState !is AO3AuthState.SigningIn
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(7.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.AutoMirrored.Outlined.Login,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp)
                )
                Text(
                    text = when {
                        authState is AO3AuthState.SigningIn -> "Logging In…"
                        authState is AO3AuthState.Expired -> "Log In Again"
                        else -> "Log In to AO3"
                    },
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
    }
}

/** iOS's account menu (`accountMenu`): Verify Session, Open on AO3, Log Out. Log Out asks first. */
@Composable
private fun AccountOverflowDropdownMenu(
    expanded: Boolean,
    onDismissRequest: () -> Unit,
    sessionHealth: AO3SessionHealth,
    username: String,
    onVerifySession: () -> Unit,
    onLogout: () -> Unit,
    onOpenWeb: (String) -> Unit
) {
    var confirmingLogOut by remember { mutableStateOf(false) }
    DropdownMenu(expanded = expanded, onDismissRequest = onDismissRequest) {
        DropdownMenuItem(
            text = {
                Text(if (sessionHealth.isChecking) "Checking…" else "Verify Session")
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
                onDismissRequest()
                onVerifySession()
            }
        )
        DropdownMenuItem(
            text = { Text("Open on AO3") },
            leadingIcon = {
                Icon(Icons.Outlined.Public, contentDescription = null)
            },
            onClick = {
                onDismissRequest()
                onOpenWeb("https://archiveofourown.org/users/$username")
            }
        )
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
                onDismissRequest()
                confirmingLogOut = true
            }
        )
    }
    LogOutConfirmation(
        show = confirmingLogOut,
        onConfirm = {
            confirmingLogOut = false
            onLogout()
        },
        onDismissRequest = { confirmingLogOut = false }
    )
}

@Composable
private fun AccountAvatar(
    avatarUrl: String?,
    onClick: (() -> Unit)? = null
) {
    Box(
        modifier = Modifier
            .size(56.dp)
            .clip(CircleShape)
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier),
        contentAlignment = Alignment.Center
    ) {
        if (avatarUrl != null) {
            AsyncImage(
                model = ImageRequest.Builder(LocalContext.current)
                    .data(avatarUrl)
                    .crossfade(true)
                    .build(),
                contentDescription = "View Profile",
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop,
                error = painterResource(id = R.drawable.ic_kudos_mark),
                placeholder = painterResource(id = R.drawable.ic_kudos_mark)
            )
        } else {
            Icon(
                painter = painterResource(id = R.drawable.ic_kudos_mark),
                contentDescription = "Default avatar",
                modifier = Modifier
                    .fillMaxSize()
                    .padding(8.dp),
                tint = Color.Unspecified
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
    val tokens = LocalKudosTokens.current
    val accessibility = isAccessibilityFontScale()
    Card(
        onClick = onClick,
        // A glass panel, as iOS draws the hub and as `subjectPanel` draws every other screen.
        // Material's container colour ignores the theme: it is stark white on Sepia.
        colors = CardDefaults.cardColors(containerColor = LocalKudosTokens.current.glassFill(0.09)),
        border = BorderStroke(0.5.dp, LocalKudosTokens.current.glassStroke(0.13)),
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
                            fontWeight = FontWeight.Medium, lineHeight = 17.sp
                        ),
                        color = tokens.secondaryInk
                    )
                }
            }
            Text(
                text = title,
                style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Medium, lineHeight = 17.sp),
                color = tokens.primaryInk,
                maxLines = if (accessibility) Int.MAX_VALUE else 2,
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
                colors = CardDefaults.cardColors(containerColor = LocalKudosTokens.current.glassFill(0.09)),
                border = BorderStroke(0.5.dp, LocalKudosTokens.current.glassStroke(0.13)),
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
internal fun AccountHubShortcuts(
    shortcuts: List<AccountShortcut>,
    counts: Map<String, AO3AccountListCountsCache.Count>,
    onEdit: () -> Unit,
    onOpen: (AccountShortcut) -> Unit
) {
    if (shortcuts.isEmpty()) return
    Column(modifier = Modifier.padding(horizontal = 12.dp)) {
        SectionRuleHeader(
            title = "Shortcuts",
            onSeeAll = onEdit
        )
        // iOS `shortcutGridColumns`: three across, two at accessibility text sizes on a phone, so
        // a label reflows instead of breaking mid-word.
        val columns = if (isAccessibilityFontScale()) 2 else 3
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            shortcuts.chunked(columns).forEach { row ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    row.forEach { item ->
                        Box(modifier = Modifier.weight(1f)) {
                            AccountShortcutGridTile(
                                title = item.title,
                                icon = item.icon,
                                count = item.listType?.listKey?.let { counts[it]?.displayText },
                                onClick = { onOpen(item) }
                            )
                        }
                    }
                    repeat(columns - row.size) {
                        Spacer(modifier = Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

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
internal fun AccountDraftsRow(onOpen: () -> Unit) {
    AccountScopeRow(title = "Drafts", subtitle = "Deleted by AO3 after 30 days",
        icon = Icons.Outlined.Drafts, onClick = onOpen)
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
                        SensitiveWorkRow(
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
                            colors = CardDefaults.cardColors(containerColor = LocalKudosTokens.current.glassFill(0.09)),
                            border = BorderStroke(0.5.dp, LocalKudosTokens.current.glassStroke(0.13)),
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
                EnrichingSensitiveWorkRow(work = work.remote, onOpenWork = onOpenWork)
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
private fun EnrichingSensitiveWorkRow(
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

    SensitiveWorkRow(work = enriched ?: work, onOpenWork = onOpenWork)
}
