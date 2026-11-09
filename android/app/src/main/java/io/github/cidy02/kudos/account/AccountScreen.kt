package io.github.cidy02.kudos.account

import android.content.Intent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.outlined.Logout
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.Drafts
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Explore
import androidx.compose.material.icons.outlined.FilterNone
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.NotificationsNone
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.cidy02.kudos.app.PrivacyRevealState
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.AO3AuthState
import io.github.cidy02.kudos.auth.AO3InvitationRequestLink
import io.github.cidy02.kudos.auth.InviteRequestUrl
import io.github.cidy02.kudos.author.AO3AuthorAvatar
import io.github.cidy02.kudos.author.AuthorOverview
import io.github.cidy02.kudos.author.AuthorOverviewHeader
import io.github.cidy02.kudos.author.AuthorSeeAll
import io.github.cidy02.kudos.author.redacted
import io.github.cidy02.kudos.core.model.PrivacySettings
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.library.LibraryPrivacy
import io.github.cidy02.kudos.library.LibraryPrivacyVisibility
import io.github.cidy02.kudos.network.ao3.account.AO3Collection
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorHeader
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorRepository
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorRoute
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentRepository
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxItem
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxRepository
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.ui.components.CachedAO3DataRow
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.ui.components.LocalWorkRowEnvironment
import io.github.cidy02.kudos.ui.components.LogOutConfirmation
import io.github.cidy02.kudos.ui.components.WorkRowEnvironment
import io.github.cidy02.kudos.ui.components.hiddenMatureWorkSemantics
import io.github.cidy02.kudos.ui.components.withoutHiddenRemote
import io.github.cidy02.kudos.ui.subject.AccentIconSquare
import io.github.cidy02.kudos.ui.subject.HomeStatusTray
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.LocalSubjectPalette
import io.github.cidy02.kudos.ui.subject.RevealCapsule
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectKicker
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.compactCount
import io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale
import io.github.cidy02.kudos.ui.subject.subjectPanel
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import io.github.cidy02.kudos.works.WorkRepository
import kotlinx.coroutines.launch

internal const val AccountInboxPreviewLimit = 2

/**
 * Account sheet (port of iOS `AccountView`, T-470):
 * author-style header tinted in the user's colour with pseud chooser and bio;
 * View Profile, Share, Edit; Works · Series · Bookmarks · Subscriptions count strip;
 * Your Latest card; Inbox card with the two newest messages; AO3 and Kudos groups.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccountScreen(
    authRepository: AO3AuthRepository,
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
    inboxRepository: AO3InboxRepository? = null,
    commentRepository: AO3CommentRepository? = null,
    authorRepository: AO3AuthorRepository? = null,
    countsCache: AO3AccountListCountsCache? = null,
    onOpenWorkComments: (workId: Long, focusedId: Long?) -> Unit = { _, _ -> },
    onOpenInbox: () -> Unit = {},
    settingsRepository: SettingsRepository? = null,
    onEditShortcuts: () -> Unit = {},
    onOpenSettings: () -> Unit = {},
    onOpenBackup: () -> Unit = {},
    onOpenAbout: () -> Unit = {},
    privacySettings: PrivacySettings? = null,
    privacyRevealState: PrivacyRevealState = PrivacyRevealState(),
    modifier: Modifier = Modifier,
    viewModel: AccountViewModel = viewModel(
        factory = AccountViewModel.factory(
            authRepository,
            authorRepository,
            countsCache,
            inboxRepository
        )
    )
) {
    val state by viewModel.uiState.collectAsState()
    val profileUnavailable by viewModel.profileUnavailable.collectAsState()
    val profileFailure by viewModel.profileFailure.collectAsState()
    val lastUnreadPair by (inboxRepository?.lastUnreadCount ?: kotlinx.coroutines.flow.flowOf(null))
        .collectAsState(initial = null)
    val generation by authRepository.generation.collectAsState()
    val settingsState by (settingsRepository?.settings ?: kotlinx.coroutines.flow.flowOf(null))
        .collectAsState(initial = null)
    val profileScope = rememberCoroutineScope()
    val signedIn = state.authState is AO3AuthState.SignedIn
    val username = (state.authState as? AO3AuthState.SignedIn)?.username
    val tokens = LocalKudosTokens.current
    val accountPalette = remember(username, tokens.theme) {
        SubjectPalette.fromHue(HomeFacts.coverHue(username ?: "AO3 account"), tokens.theme)
    }
    val activeRoute = state.route ?: username?.let { AO3AuthorRoute(it) }
    val rowEnv = LocalWorkRowEnvironment.current
    val effectivePrivacy = privacySettings ?: rowEnv?.privacy ?: settingsState?.privacy
    val effectivePrivacyLoaded = privacySettings != null || (rowEnv != null && rowEnv.loaded) || settingsState != null
    val effectiveReveal = if (privacySettings != null) privacyRevealState else (rowEnv?.revealState ?: privacyRevealState)

    val unreadCount = when (val preview = state.inboxPreview) {
        is AccountInboxPreviewState.Loaded -> preview.unreadCount
        else -> if (username != null) {
            val expectedScope = "${username.lowercase()}|$generation"
            lastUnreadPair?.takeIf { it.first == expectedScope }?.second
        } else null
    }

    var confirmingLogout by remember { mutableStateOf(false) }

    CompositionLocalProvider(LocalSubjectPalette provides accountPalette) {
        KudosRefreshBox(onRefresh = { viewModel.refreshProfile() }) {
            LazyColumn(
                modifier = modifier
                    .fillMaxSize()
                    .then(if (signedIn) Modifier.subjectScreenWash(accountPalette) else Modifier)
                    .padding(horizontal = SubjectMetrics.accountGutter),
                contentPadding = PaddingValues(top = 8.dp, bottom = 32.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                item(key = "account-profile") {
                    when {
                        signedIn && username != null && activeRoute != null -> {
                            AccountSignedInProfileSection(
                                username = username,
                                route = activeRoute,
                                state = state,
                                palette = accountPalette,
                                profileUnavailable = profileUnavailable,
                                profileFailure = profileFailure,
                                onSelectScope = viewModel::selectScope,
                                onRetryAbout = viewModel::retryAbout,
                                onRetryProfile = { profileScope.launch { viewModel.refreshProfile() } },
                                onOpenProfile = { onOpenWeb("native:profile") },
                                onOpenWeb = onOpenWeb
                            )
                        }
                        state.authState is AO3AuthState.Restoring -> {
                            AccountRestoringHeader()
                        }
                        else -> {
                            AccountSignedOutCard(
                                authState = state.authState,
                                onLogin = onLogin,
                                onOpenWeb = onOpenWeb
                            )
                        }
                    }
                }

                if (signedIn && activeRoute != null) {
                    val header = state.header
                    if (header != null) {
                        item(key = "account-count-strip") {
                            AccountProfileCountStrip(
                                header = header,
                                route = activeRoute,
                                counts = state.counts,
                                onOpenList = onOpenList,
                                onOpenSeries = onOpenSeries
                            )
                        }
                        item(key = "account-latest") {
                            AccountLatestSection(
                                header = header,
                                env = rowEnv,
                                privacyLoaded = effectivePrivacyLoaded,
                                privacy = effectivePrivacy ?: LibraryPrivacy.UNREAD_SETTING,
                                reveal = effectiveReveal,
                                onOpenWork = onOpenWork
                            )
                        }
                    }

                    item(key = "account-inbox") {
                        AccountInboxSection(
                            inboxPreview = state.inboxPreview,
                            unreadCount = unreadCount,
                            palette = accountPalette,
                            onOpenInbox = onOpenInbox,
                            onOpenWorkComments = onOpenWorkComments,
                            onOpenWeb = onOpenWeb,
                            onRetry = viewModel::retryInbox
                        )
                    }

                    item(key = "account-ao3-group") {
                        AccountAO3Section(
                            unreadCount = unreadCount,
                            palette = accountPalette,
                            onOpenInbox = onOpenInbox,
                            onOpenPreferences = { onOpenWeb("native:preferences") },
                            onOpenDashboard = onOpenDashboard,
                            onOpenMoreOnAO3 = { onOpenWeb("native:more-on-ao3") },
                            onOpenAO3 = { onOpenWeb("https://archiveofourown.org") }
                        )
                    }
                }

                item(key = "account-kudos-group") {
                    AccountKudosSection(
                        palette = accountPalette,
                        onOpenSettings = onOpenSettings,
                        onOpenBackup = onOpenBackup,
                        onOpenAbout = onOpenAbout
                    )
                }

                if (signedIn) {
                    item(key = "account-logout") {
                        AccountLogOutSection(onLogoutClick = { confirmingLogout = true })
                    }
                }
            }
        }
    }

    LogOutConfirmation(
        show = confirmingLogout,
        onConfirm = {
            confirmingLogout = false
            viewModel.logout()
        },
        onDismissRequest = { confirmingLogout = false }
    )
}

@Composable
internal fun AccountSignedInProfileSection(
    username: String,
    route: AO3AuthorRoute,
    state: AccountUiState,
    palette: SubjectPalette,
    profileUnavailable: Boolean,
    profileFailure: String?,
    onSelectScope: (AO3AuthorRoute) -> Unit,
    onRetryAbout: () -> Unit,
    onRetryProfile: () -> Unit,
    onOpenProfile: () -> Unit,
    onOpenWeb: (String) -> Unit
) {
    val tokens = LocalKudosTokens.current
    Column(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        if (state.isShowingStaleCache) {
            CachedAO3DataRow(inPanel = true, onRefresh = onRetryProfile)
        }
        val header = state.header
        if (header != null) {
            AuthorOverviewHeader(
                header = header,
                route = route,
                about = state.about,
                aboutLoad = state.aboutLoad,
                isOwnProfile = true,
                subscriptionBusy = false,
                moderationBusy = false,
                onSubscription = {},
                onModeration = {},
                onSelectScope = onSelectScope,
                onOpenWeb = onOpenWeb,
                onRetryAbout = onRetryAbout
            )
            AccountProfileActions(
                username = username,
                route = route,
                palette = palette,
                onOpenProfile = onOpenProfile,
                onOpenWeb = onOpenWeb
            )
        } else {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(14.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                AO3AuthorAvatar(url = null, name = username, size = 56.dp, isCircular = true)
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    SubjectKicker(
                        text = "AO3 Account",
                        palette = palette,
                        ruleWidth = SubjectMetrics.pageRuleWidth,
                        ruleSpacing = 6.dp
                    )
                    Text(
                        text = username,
                        color = tokens.primaryInk,
                        fontSize = 24.sp,
                        lineHeight = 30.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
            when {
                profileUnavailable -> {
                    EmptyStateCard(
                        title = "Profile unavailable",
                        message = "AO3 could not load your profile. It may be temporarily unavailable."
                    )
                }
                profileFailure != null -> {
                    ErrorStateCard(
                        title = "Couldn't load your profile",
                        message = profileFailure,
                        primaryActionLabel = "Try Again",
                        onPrimaryAction = onRetryProfile
                    )
                }
                else -> {
                    Text(
                        text = "Loading your AO3 profile…",
                        color = tokens.secondaryInk,
                        fontSize = 13.sp,
                        lineHeight = 18.sp
                    )
                }
            }
        }
    }
}

@Composable
internal fun AccountProfileActions(
    username: String,
    route: AO3AuthorRoute,
    palette: SubjectPalette,
    onOpenProfile: () -> Unit,
    onOpenWeb: (String) -> Unit
) {
    val tokens = LocalKudosTokens.current
    val context = LocalContext.current
    val editUrl = MoreOnAO3.url(MoreOnAO3.Target.User("profile/edit"), username)
    val shareProfile: () -> Unit = {
        val send = Intent(Intent.ACTION_SEND)
            .setType("text/plain")
            .putExtra(Intent.EXTRA_TEXT, route.dashboardUrl)
        runCatching { context.startActivity(Intent.createChooser(send, null)) }
    }

    if (isAccessibilityFontScale()) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            Button(
                onClick = onOpenProfile,
                shape = CircleShape,
                colors = ButtonDefaults.buttonColors(
                    containerColor = palette.tint,
                    contentColor = SubjectPalette.label(palette.tint)
                ),
                modifier = Modifier.fillMaxWidth().heightIn(min = 40.dp)
            ) {
                Icon(Icons.Outlined.Person, contentDescription = null, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(6.dp))
                Text("View Profile", fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            }
            OutlinedButton(
                onClick = shareProfile,
                shape = CircleShape,
                border = BorderStroke(0.5.dp, tokens.glassStroke(0.22)),
                modifier = Modifier.fillMaxWidth().heightIn(min = 40.dp)
            ) {
                Icon(Icons.Outlined.Share, contentDescription = null, tint = tokens.primaryInk, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(6.dp))
                Text("Share", color = tokens.primaryInk, fontSize = 14.sp, fontWeight = FontWeight.Medium)
            }
            if (editUrl != null) {
                OutlinedButton(
                    onClick = { onOpenWeb(editUrl) },
                    shape = CircleShape,
                    border = BorderStroke(0.5.dp, tokens.glassStroke(0.22)),
                    modifier = Modifier.fillMaxWidth().heightIn(min = 40.dp)
                ) {
                    Icon(Icons.Outlined.Edit, contentDescription = null, tint = tokens.primaryInk, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("Edit", color = tokens.primaryInk, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                }
            }
        }
    } else {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Button(
                onClick = onOpenProfile,
                shape = CircleShape,
                colors = ButtonDefaults.buttonColors(
                    containerColor = palette.tint,
                    contentColor = SubjectPalette.label(palette.tint)
                ),
                contentPadding = PaddingValues(horizontal = 14.dp, vertical = 8.dp),
                modifier = Modifier.weight(1f).heightIn(min = 40.dp)
            ) {
                Icon(Icons.Outlined.Person, contentDescription = null, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(6.dp))
                Text("View Profile", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
            }
            OutlinedButton(
                onClick = shareProfile,
                shape = CircleShape,
                border = BorderStroke(0.5.dp, tokens.glassStroke(0.22)),
                contentPadding = PaddingValues(horizontal = 14.dp, vertical = 8.dp),
                modifier = Modifier.heightIn(min = 40.dp)
            ) {
                Icon(Icons.Outlined.Share, contentDescription = null, tint = tokens.primaryInk, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(6.dp))
                Text("Share", color = tokens.primaryInk, fontSize = 14.sp, fontWeight = FontWeight.Medium, maxLines = 1)
            }
            if (editUrl != null) {
                OutlinedButton(
                    onClick = { onOpenWeb(editUrl) },
                    shape = CircleShape,
                    border = BorderStroke(0.5.dp, tokens.glassStroke(0.22)),
                    contentPadding = PaddingValues(horizontal = 14.dp, vertical = 8.dp),
                    modifier = Modifier.heightIn(min = 40.dp)
                ) {
                    Icon(Icons.Outlined.Edit, contentDescription = null, tint = tokens.primaryInk, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("Edit", color = tokens.primaryInk, fontSize = 14.sp, fontWeight = FontWeight.Medium, maxLines = 1)
                }
            }
        }
    }
}

private data class AccountStripCell(
    val label: String,
    val countText: String,
    val onClick: () -> Unit
)

/** iOS `accountProfileCountStrip`: Works · Series · Bookmarks · Subscriptions. */
@Composable
internal fun AccountProfileCountStrip(
    header: AO3AuthorHeader,
    route: AO3AuthorRoute,
    counts: Map<String, AO3AccountListCountsCache.Count>,
    onOpenList: (AccountListType) -> Unit,
    onOpenSeries: (String) -> Unit
) {
    val tokens = LocalKudosTokens.current
    val worksCount = AuthorOverview.listCount(header, route, AuthorSeeAll.Works)?.compactCount() ?: "—"
    val seriesCount = AuthorOverview.listCount(header, route, AuthorSeeAll.Series)?.compactCount() ?: "—"
    val bookmarksCount = AuthorOverview.listCount(header, route, AuthorSeeAll.Bookmarks)?.compactCount() ?: "—"
    val subscriptionsCount = counts[AccountListType.Subscriptions.listKey]?.displayText ?: "—"

    val cells = listOf(
        AccountStripCell("Works", worksCount) { onOpenList(AccountListType.MyWorks) },
        AccountStripCell("Series", seriesCount) { onOpenSeries(route.seriesUrl) },
        AccountStripCell("Bookmarks", bookmarksCount) { onOpenList(AccountListType.Bookmarks) },
        AccountStripCell("Subscriptions", subscriptionsCount) { onOpenList(AccountListType.Subscriptions) }
    )
    val columns = if (isAccessibilityFontScale()) 2 else cells.size
    Column(Modifier.fillMaxWidth().subjectPanel()) {
        cells.chunked(columns).forEachIndexed { rowIndex, rowItems ->
            if (rowIndex > 0) {
                Box(Modifier.fillMaxWidth().height(0.5.dp).background(tokens.glassStroke(0.13)))
            }
            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
                rowItems.forEachIndexed { index, item ->
                    val spoken = if (item.countText != "—") "${item.countText} ${item.label.lowercase()}" else item.label
                    Column(
                        Modifier
                            .weight(1f)
                            .heightIn(min = 48.dp)
                            .clickable(onClick = item.onClick)
                            .semantics { contentDescription = spoken }
                            .padding(vertical = 10.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text(
                            text = item.countText,
                            color = tokens.primaryInk,
                            fontSize = 20.sp,
                            fontWeight = FontWeight.Bold,
                            fontFamily = FontFamily.Monospace
                        )
                        Text(
                            text = item.label,
                            color = tokens.secondaryInk,
                            fontSize = 11.sp
                        )
                    }
                    if (index < rowItems.lastIndex) {
                        Box(
                            Modifier
                                .width(0.5.dp)
                                .fillMaxHeight()
                                .padding(vertical = 8.dp)
                                .background(tokens.glassStroke(0.13))
                        )
                    }
                }
            }
        }
    }
}

/** iOS `accountLatestSection`: the newest work under the reader's privacy rules. */
@Composable
internal fun AccountLatestSection(
    header: AO3AuthorHeader,
    env: WorkRowEnvironment?,
    privacyLoaded: Boolean = env != null && env.loaded,
    privacy: PrivacySettings = env?.privacy ?: LibraryPrivacy.UNREAD_SETTING,
    reveal: PrivacyRevealState = env?.revealState ?: PrivacyRevealState(),
    onOpenWork: (AO3WorkSummary) -> Unit
) {
    val tokens = LocalKudosTokens.current
    var locallyRevealedIds by remember { mutableStateOf(emptySet<String>()) }
    val combinedReveal = remember(reveal, locallyRevealedIds) {
        if (locallyRevealedIds.isEmpty()) reveal
        else reveal.copy(revealedIds = reveal.revealedIds + locallyRevealedIds)
    }

    val rawLatest = AuthorOverview.latest(header)
    if (rawLatest != null) {
        val keptByEnv = if (env != null) {
            listOf(rawLatest).withoutHiddenRemote(env).isNotEmpty()
        } else {
            LibraryPrivacy.keepsRemoteRow(
                rawLatest.id.toString(),
                rawLatest.rating,
                null,
                if (privacyLoaded) privacy else LibraryPrivacy.UNREAD_SETTING,
                if (privacyLoaded) combinedReveal else PrivacyRevealState()
            )
        }
        val localMatch = if (env != null && env.loaded) env.index.findMatch(rawLatest) else null
        val visibility = AuthorOverview.workVisibility(
            work = rawLatest,
            loaded = privacyLoaded,
            privacy = privacy,
            reveal = combinedReveal,
            local = localMatch
        )
        if (!keptByEnv || visibility == LibraryPrivacyVisibility.Hidden) {
            return
        }
        val obscured = visibility == LibraryPrivacyVisibility.Obscured
        val shownWork = if (obscured) rawLatest.redacted() else rawLatest
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionRuleHeader(title = "Your Latest", gutter = 0.dp)
            Box(
                Modifier
                    .fillMaxWidth()
                    .clickable {
                        if (obscured) {
                            val ids = buildSet {
                                localMatch?.let { add(it.id) }
                                add(rawLatest.id.toString())
                            }
                            if (env != null) env.revealIds(ids) else locallyRevealedIds = locallyRevealedIds + ids
                        } else {
                            onOpenWork(rawLatest)
                        }
                    }
            ) {
                AccountLatestCard(work = shownWork, obscured = obscured)
            }
        }
    } else {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionRuleHeader(title = "Your Latest", gutter = 0.dp)
            Text(
                text = if (header.recentWorks == null) {
                    "Couldn't read your latest work. Open Works to try again."
                } else {
                    "No recent works visible on AO3."
                },
                color = tokens.secondaryInk,
                fontSize = 15.sp,
                lineHeight = 21.sp,
                modifier = Modifier.fillMaxWidth().subjectPanel().padding(16.dp)
            )
        }
    }
}

/**
 * iOS `AuthorProfileLatestCard(work: work, opensInReader: false)`:
 * feature card for the newest work; concealed cards redact text and apply [hiddenMatureWorkSemantics].
 */
@Composable
internal fun AccountLatestCard(work: AO3WorkSummary, obscured: Boolean) {
    val tokens = LocalKudosTokens.current
    val palette = remember(work.fandoms, work.title, tokens.theme) {
        SubjectPalette.fromHue(HomeFacts.workHue(work.fandoms, work.title), tokens.theme)
    }
    val shape = RoundedCornerShape(SubjectMetrics.panelRadius)
    val kicker = listOfNotNull(
        HomeFacts.primaryFandom(work.fandoms),
        work.chapters.takeIf { it.isNotBlank() }?.let { if (it.contains("/")) "Ch. $it" else it }
    ).joinToString(" · ")
    val stats = listOfNotNull(
        work.updatedDate.takeIf { it.isNotBlank() }?.let { "Updated $it" },
        work.wordCount?.let { "%,d words".format(it) },
        work.kudos?.let { "♥ ${it.compactCount()}" },
        work.hits?.let { "${it.compactCount()} hits" }
    ).joinToString(" · ")

    Box(Modifier.fillMaxWidth()) {
        Column(
            Modifier
                .fillMaxWidth()
                .then(if (obscured) Modifier.blur(10.dp).hiddenMatureWorkSemantics(true) else Modifier)
                .background(tokens.theme.cardSurface, shape)
                .background(palette.cardWash, shape)
                .border(0.5.dp, palette.cardBorder, shape)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Column(Modifier.weight(1f).padding(end = 44.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    if (kicker.isNotEmpty()) SubjectKicker(kicker, palette = palette)
                    Text(
                        text = work.title,
                        color = tokens.primaryInk,
                        fontSize = 22.sp,
                        lineHeight = 28.sp,
                        fontWeight = FontWeight.SemiBold,
                        fontFamily = FontFamily.Serif,
                        maxLines = if (isAccessibilityFontScale()) Int.MAX_VALUE else 3,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
            if (work.summary.isNotBlank()) {
                Text(
                    text = work.summary,
                    color = tokens.primaryInk.copy(alpha = 0.92f),
                    fontSize = 15.sp,
                    lineHeight = 21.sp,
                    maxLines = if (isAccessibilityFontScale()) Int.MAX_VALUE else 3,
                    overflow = TextOverflow.Ellipsis
                )
            }
            HomeStatusTray(
                rating = work.rating,
                categories = work.categories,
                warnings = work.warnings,
                isComplete = work.isComplete,
                tileSize = 24.dp,
                announces = !obscured
            )
            if (stats.isNotEmpty()) {
                Text(stats, color = tokens.secondaryInk, fontSize = 12.sp, lineHeight = 17.sp)
            }
        }
        if (!obscured) {
            Box(
                Modifier
                    .align(Alignment.TopEnd)
                    .padding(14.dp)
                    .size(40.dp)
                    .background(Color.White, CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    tint = tokens.accent,
                    modifier = Modifier.size(20.dp)
                )
            }
        } else {
            RevealCapsule(Modifier.align(Alignment.Center))
        }
    }
}

/** iOS `accountInboxSection`: Inbox header row + at most two latest messages. */
@Composable
internal fun AccountInboxSection(
    inboxPreview: AccountInboxPreviewState,
    unreadCount: Int?,
    palette: SubjectPalette,
    onOpenInbox: () -> Unit,
    onOpenWorkComments: (workId: Long, focusedId: Long?) -> Unit,
    onOpenWeb: (String) -> Unit,
    onRetry: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    Column(Modifier.fillMaxWidth().subjectPanel()) {
        AccountPanelNavRow(
            title = "Inbox",
            icon = Icons.Outlined.Inbox,
            palette = palette,
            badgeCount = unreadCount,
            onClick = onOpenInbox,
            testTag = "Account Inbox Card Header"
        )
        SubjectRowSeparator()
        when (inboxPreview) {
            AccountInboxPreviewState.Idle,
            AccountInboxPreviewState.Loading -> {
                Text(
                    text = "Loading recent messages…",
                    color = tokens.secondaryInk,
                    fontSize = 13.sp,
                    lineHeight = 18.sp,
                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp)
                )
            }
            is AccountInboxPreviewState.Loaded -> {
                val items = inboxPreview.items.take(AccountInboxPreviewLimit)
                if (items.isEmpty()) {
                    Text(
                        text = "No messages in your AO3 inbox.",
                        color = tokens.secondaryInk,
                        fontSize = 13.sp,
                        lineHeight = 18.sp,
                        modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp)
                    )
                } else {
                    items.forEachIndexed { index, item ->
                        if (index > 0) SubjectRowSeparator()
                        AccountInboxPreviewRow(
                            item = item,
                            palette = palette,
                            onClick = {
                                val workId = item.workId
                                if (workId != null) {
                                    onOpenWorkComments(workId, item.id)
                                } else {
                                    onOpenWeb(commentThreadUrl(item.id))
                                }
                            }
                        )
                    }
                }
            }
            is AccountInboxPreviewState.Failed -> {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Text(
                        text = inboxPreview.message,
                        color = tokens.secondaryInk,
                        fontSize = 12.sp,
                        lineHeight = 17.sp,
                        modifier = Modifier.weight(1f)
                    )
                    TextButton(onClick = onRetry) {
                        Text(
                            text = "Try Again",
                            color = palette.controlInk,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun AccountInboxPreviewRow(
    item: AO3InboxItem,
    palette: SubjectPalette,
    onClick: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    val initial = item.commenterName.trim().firstOrNull()?.uppercase() ?: "?"
    val targetTitle = item.workTitle.takeIf { it.isNotBlank() } ?: item.subjectTitle
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 11.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Top
    ) {
        Box(
            modifier = Modifier
                .size(28.dp)
                .background(palette.accent.copy(alpha = 0.16f), CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = initial,
                color = palette.controlInk,
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold
            )
        }
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                if (item.isUnread) {
                    Box(
                        modifier = Modifier
                            .size(7.dp)
                            .background(tokens.accent, CircleShape)
                    )
                }
                Text(
                    text = item.commenterName,
                    color = tokens.primaryInk,
                    fontSize = 13.sp,
                    fontWeight = if (item.isUnread) FontWeight.SemiBold else FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                if (targetTitle.isNotBlank()) {
                    Text(
                        text = "on $targetTitle",
                        color = tokens.secondaryInk,
                        fontSize = 12.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false)
                    )
                }
                Spacer(Modifier.weight(1f))
                if (item.postedAgo.isNotBlank()) {
                    Text(
                        text = item.postedAgo,
                        color = tokens.tertiaryInk,
                        fontSize = 11.sp,
                        maxLines = 1
                    )
                }
            }
            Text(
                text = if (item.isUnavailable) "A comment here is unavailable" else item.excerpt,
                color = if (item.isUnavailable) tokens.tertiaryInk else tokens.secondaryInk,
                fontSize = 12.sp,
                lineHeight = 17.sp,
                fontStyle = if (item.isUnavailable) FontStyle.Italic else FontStyle.Normal,
                maxLines = if (isAccessibilityFontScale()) 4 else 2,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

/** iOS `accountAO3Section`: Inbox, AO3 Preferences, My Dashboard, More on AO3, Open AO3. */
@Composable
internal fun AccountAO3Section(
    unreadCount: Int?,
    palette: SubjectPalette,
    onOpenInbox: () -> Unit,
    onOpenPreferences: () -> Unit,
    onOpenDashboard: () -> Unit,
    onOpenMoreOnAO3: () -> Unit,
    onOpenAO3: () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionRuleHeader(title = "AO3", gutter = 0.dp)
        Column(Modifier.fillMaxWidth().subjectPanel()) {
            AccountPanelNavRow(
                title = "Inbox",
                icon = Icons.Outlined.Inbox,
                palette = palette,
                badgeCount = unreadCount,
                onClick = onOpenInbox
            )
            SubjectRowSeparator()
            AccountPanelNavRow(
                title = "AO3 Preferences",
                icon = Icons.Outlined.Tune,
                palette = palette,
                onClick = onOpenPreferences
            )
            SubjectRowSeparator()
            AccountPanelNavRow(
                title = "My Dashboard",
                icon = Icons.Outlined.GridView,
                palette = palette,
                onClick = onOpenDashboard
            )
            SubjectRowSeparator()
            AccountPanelNavRow(
                title = "More on AO3",
                icon = Icons.Outlined.Explore,
                palette = palette,
                onClick = onOpenMoreOnAO3
            )
            SubjectRowSeparator()
            AccountPanelNavRow(
                title = "Open AO3",
                icon = Icons.Outlined.Public,
                palette = palette,
                onClick = onOpenAO3
            )
        }
    }
}

/** iOS `accountKudosSection`: Settings, Backup & Sync, About. */
@Composable
internal fun AccountKudosSection(
    palette: SubjectPalette,
    onOpenSettings: () -> Unit,
    onOpenBackup: () -> Unit,
    onOpenAbout: () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionRuleHeader(title = "Kudos", gutter = 0.dp)
        Column(Modifier.fillMaxWidth().subjectPanel()) {
            AccountPanelNavRow(
                title = "Settings",
                icon = Icons.Outlined.Settings,
                palette = palette,
                onClick = onOpenSettings
            )
            SubjectRowSeparator()
            AccountPanelNavRow(
                title = "Backup & Sync",
                icon = Icons.Outlined.Sync,
                palette = palette,
                onClick = onOpenBackup
            )
            SubjectRowSeparator()
            AccountPanelNavRow(
                title = "About",
                icon = Icons.Outlined.Info,
                palette = palette,
                onClick = onOpenAbout
            )
        }
    }
}

/** iOS `accountLogOutSection`: destructive Log Out row with confirmation. */
@Composable
internal fun AccountLogOutSection(onLogoutClick: () -> Unit) {
    val tokens = LocalKudosTokens.current
    Column(Modifier.fillMaxWidth().subjectPanel()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .clickable(onClick = onLogoutClick)
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Icon(
                imageVector = Icons.AutoMirrored.Outlined.Logout,
                contentDescription = null,
                tint = tokens.destructive,
                modifier = Modifier.size(20.dp)
            )
            Text(
                text = "Log Out",
                color = tokens.destructive,
                fontSize = 16.sp,
                lineHeight = 22.sp,
                fontWeight = FontWeight.Medium
            )
        }
    }
}

@Composable
private fun AccountPanelNavRow(
    title: String,
    icon: ImageVector,
    palette: SubjectPalette,
    badgeCount: Int? = null,
    testTag: String? = null,
    onClick: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .then(if (testTag != null) Modifier.testTag(testTag) else Modifier)
            .heightIn(min = 48.dp)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = palette.controlInk,
            modifier = Modifier.size(20.dp)
        )
        Text(
            text = title,
            color = tokens.primaryInk,
            fontSize = 16.sp,
            lineHeight = 22.sp,
            modifier = Modifier.weight(1f)
        )
        if (badgeCount != null && badgeCount > 0) {
            Text(
                text = badgeCount.compactCount(),
                color = SubjectPalette.label(tokens.accent),
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                fontFamily = FontFamily.Monospace,
                modifier = Modifier
                    .background(tokens.accent, CircleShape)
                    .padding(horizontal = 7.dp, vertical = 2.dp)
            )
        }
        Icon(
            imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = tokens.tertiaryInk,
            modifier = Modifier.size(18.dp)
        )
    }
}

/** iOS `signedOutCard` (T-470): heading, description, Log In to AO3 button, invitation link, footnote. */
@Composable
internal fun AccountSignedOutCard(
    authState: AO3AuthState,
    onLogin: () -> Unit,
    onOpenWeb: (String) -> Unit
) {
    val tokens = LocalKudosTokens.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .subjectPanel()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            AO3AuthorAvatar(url = null, name = "AO3 account", size = 52.dp, isCircular = true)
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(
                    text = "Bring your AO3 account along",
                    color = tokens.primaryInk,
                    fontSize = 17.sp,
                    lineHeight = 22.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.semantics { heading() }
                )
            }
        }

        Text(
            text = "Your bookmarks, history, subscriptions, inbox and works appear here. Your library works without an account.",
            color = tokens.secondaryInk,
            fontSize = 13.sp,
            lineHeight = 18.sp
        )

        Button(
            onClick = onLogin,
            shape = CircleShape,
            colors = ButtonDefaults.buttonColors(
                containerColor = tokens.accent,
                contentColor = SubjectPalette.label(tokens.accent)
            ),
            enabled = authState !is AO3AuthState.SigningIn,
            modifier = Modifier.fillMaxWidth()
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(7.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Outlined.Key,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp)
                )
                Text(
                    text = if (authState is AO3AuthState.SigningIn) "Logging In…" else "Log In to AO3",
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }

        AO3InvitationRequestLink(
            onOpenAO3 = { onOpenWeb(InviteRequestUrl) }
        )

        Text(
            text = "Your sign-in stays on this device. Kudos never sees your password.",
            color = tokens.tertiaryInk,
            fontSize = 12.sp,
            lineHeight = 16.sp
        )
    }
}

@Composable
private fun AccountRestoringHeader() {
    val tokens = LocalKudosTokens.current
    val alpha by rememberInfiniteTransition(label = "accountRestoring").animateFloat(
        initialValue = 0.08f, targetValue = 0.18f,
        animationSpec = infiniteRepeatable(tween(900), RepeatMode.Reverse), label = "skeletonAlpha"
    )
    Row(
        modifier = Modifier.fillMaxWidth()
            .padding(vertical = 4.dp)
            .testTag("Restoring account header")
            .clearAndSetSemantics { contentDescription = "Restoring AO3 session" },
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.size(72.dp).background(tokens.primaryInk.copy(alpha = alpha), RoundedCornerShape(8.dp)))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(9.dp)) {
            Box(Modifier.fillMaxWidth(0.72f).height(20.dp).background(tokens.primaryInk.copy(alpha = alpha), RoundedCornerShape(4.dp)))
            Box(Modifier.fillMaxWidth(0.53f).height(13.dp).background(tokens.primaryInk.copy(alpha = alpha), RoundedCornerShape(4.dp)))
            Box(Modifier.fillMaxWidth(0.86f).height(13.dp).background(tokens.primaryInk.copy(alpha = alpha), RoundedCornerShape(4.dp)))
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
                                count = (if (item == AccountShortcut.Series) AO3AccountListCountsCache.SERIES
                                    else item.listType?.listKey)?.let { counts[it]?.displayText },
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

internal data class AccountOverviewReadingRow(
    val title: String,
    val icon: ImageVector,
    val countKey: String?,
    val listType: AccountListType?
)

internal fun accountOverviewReadingRows(): List<AccountOverviewReadingRow> = listOf(
    AccountOverviewReadingRow(
        "Bookmarks",
        Icons.Outlined.BookmarkBorder,
        AccountListType.Bookmarks.listKey,
        AccountListType.Bookmarks
    ),
    AccountOverviewReadingRow(
        "Collections",
        Icons.Outlined.FilterNone,
        AO3AccountListCountsCache.COLLECTIONS,
        null
    ),
    AccountOverviewReadingRow(
        "Subscriptions",
        Icons.Outlined.NotificationsNone,
        AccountListType.Subscriptions.listKey,
        AccountListType.Subscriptions
    )
)

internal const val SIGNED_OUT_ACCOUNT_LINE =
    "When you sign in, this page shows your AO3 account and activity."

@Composable
internal fun AccountDraftsRow(onOpen: () -> Unit) {
    AccountScopeRow(
        title = "Drafts",
        subtitle = "Deleted by AO3 after 30 days",
        icon = Icons.Outlined.Drafts,
        onClick = onOpen
    )
}
