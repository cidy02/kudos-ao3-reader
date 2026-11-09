package io.github.cidy02.kudos.home

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.author.AO3AuthorAvatar
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.ToolbarAddButton
import io.github.cidy02.kudos.ui.subject.ToolbarCircleButton

/**
 * Home's top-right chrome, drawn by the shell so it fades with the large title.
 * Lambdas live on [actions], which is not snapshot state, so writing them every
 * frame does not restart composition.
 */
class HomeShellChrome {
    var mounted by mutableStateOf(false)
    var hideTabBar by mutableStateOf(false)
    var selectionTitle by mutableStateOf<String?>(null)
    var allSelected by mutableStateOf(false)
    var showOverflow by mutableStateOf(false)
    var showPrivacy by mutableStateOf(false)
    var revealAll by mutableStateOf(false)
    var showSelect by mutableStateOf(false)
    var isSignedIn by mutableStateOf(false)
    var username by mutableStateOf<String?>(null)
    var avatarUrl by mutableStateOf<String?>(null)
    var unreadInboxCount by mutableStateOf<Int?>(null)
    /** The hero card's hue (owner, 2026-10-03): Home's wash takes the current hero's colour. */
    var washHue by mutableStateOf<Double?>(null)
    val actions = HomeShellActions()

    fun reset() {
        mounted = false
        hideTabBar = false
        selectionTitle = null
        allSelected = false
        showOverflow = false
        showPrivacy = false
        revealAll = false
        showSelect = false
        isSignedIn = false
        username = null
        avatarUrl = null
        unreadInboxCount = null
        washHue = null
        actions.onNewQueue = {}
        actions.onSelectAll = {}
        actions.onEnterSelect = {}
        actions.onTogglePrivacy = {}
        actions.onOpenAccount = {}
    }
}

class HomeShellActions {
    var onNewQueue: () -> Unit = {}
    var onSelectAll: () -> Unit = {}
    var onEnterSelect: () -> Unit = {}
    var onTogglePrivacy: () -> Unit = {}
    var onOpenAccount: () -> Unit = {}
}

fun formatAccountUnreadBadge(isLoggedIn: Boolean, unreadCount: Int?): String? {
    val count = unreadCount?.takeIf { isLoggedIn && it > 0 } ?: return null
    return if (count > 99) "99+" else count.toString()
}

fun formatAccountUnreadAccessibilityValue(isLoggedIn: Boolean, unreadCount: Int?): String {
    val count = unreadCount?.takeIf { isLoggedIn && it > 0 } ?: return ""
    return if (count == 1) "1 unread in Inbox" else "$count unread in Inbox"
}

fun accountAvatarInitial(username: String?): String? =
    username?.trim()?.firstOrNull()?.uppercaseChar()?.toString()

/** "+" and "…" while browsing. Select All, and the eye when mature hiding is on, while selecting. */
@Composable
fun HomeToolbarActions(chrome: HomeShellChrome) {
    val tokens = LocalKudosTokens.current
    if (chrome.hideTabBar) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = if (chrome.allSelected) "Deselect All" else "Select All",
                color = tokens.accentInk,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier
                    .clickable(onClick = { chrome.actions.onSelectAll() })
                    .padding(horizontal = 8.dp, vertical = 8.dp)
            )
            if (chrome.showPrivacy) {
                PrivacyButton(revealed = chrome.revealAll, onClick = { chrome.actions.onTogglePrivacy() })
            }
        }
    } else {
        Row(
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            ToolbarAddButton(
                onClick = { chrome.actions.onNewQueue() },
                accessibilityName = "New Queue"
            )
            if (chrome.showOverflow) {
                var open by remember { mutableStateOf(false) }
                Box {
                    ToolbarCircleButton(
                        onClick = { open = true },
                        accessibilityName = "More"
                    ) {
                        Icon(Icons.Filled.MoreVert, contentDescription = null)
                    }
                    DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                        if (chrome.showPrivacy) {
                            DropdownMenuItem(
                                text = { Text(if (chrome.revealAll) "Hide mature" else "Show mature") },
                                onClick = {
                                    open = false
                                    chrome.actions.onTogglePrivacy()
                                }
                            )
                        }
                        if (chrome.showSelect) {
                            DropdownMenuItem(
                                text = { Text("Select") },
                                onClick = {
                                    open = false
                                    chrome.actions.onEnterSelect()
                                }
                            )
                        }
                    }
                }
            }
            HomeProfileButton(
                isSignedIn = chrome.isSignedIn,
                username = chrome.username,
                avatarUrl = chrome.avatarUrl,
                unreadInboxCount = chrome.unreadInboxCount,
                onClick = { chrome.actions.onOpenAccount() }
            )
        }
    }
}

@Composable
fun HomeProfileButton(
    isSignedIn: Boolean,
    username: String?,
    avatarUrl: String?,
    unreadInboxCount: Int?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val palette = tokens.scopePalette
    val badgeText = formatAccountUnreadBadge(isSignedIn, unreadInboxCount)
    val a11yValue = formatAccountUnreadAccessibilityValue(isSignedIn, unreadInboxCount)
    val initial = accountAvatarInitial(username)

    IconButton(
        onClick = onClick,
        modifier = modifier.semantics {
            contentDescription = "Account"
            if (a11yValue.isNotEmpty()) stateDescription = a11yValue
        }
    ) {
        Box(contentAlignment = Alignment.TopEnd) {
            Box(
                modifier = Modifier
                    .size(28.dp)
                    .clip(CircleShape),
                contentAlignment = Alignment.Center
            ) {
                if (isSignedIn) {
                    when {
                        !avatarUrl.isNullOrBlank() -> {
                            AO3AuthorAvatar(
                                url = avatarUrl,
                                name = username ?: "Account",
                                size = 28.dp,
                                isCircular = true
                            )
                        }
                        initial != null -> {
                            Box(
                                modifier = Modifier
                                    .size(28.dp)
                                    .background(palette.controlChipFill, CircleShape),
                                contentAlignment = Alignment.Center
                            ) {
                                Text(
                                    text = initial,
                                    color = palette.controlInk,
                                    fontSize = 13.sp,
                                    fontWeight = FontWeight.SemiBold
                                )
                            }
                        }
                        else -> {
                            Icon(
                                imageVector = Icons.Filled.Person,
                                contentDescription = null,
                                tint = palette.controlInk,
                                modifier = Modifier.size(20.dp)
                            )
                        }
                    }
                } else {
                    Icon(
                        imageVector = Icons.Outlined.AccountCircle,
                        contentDescription = null,
                        tint = palette.controlInk,
                        modifier = Modifier.size(20.dp)
                    )
                }
            }
            if (badgeText != null) {
                Box(
                    modifier = Modifier
                        .offset(x = 6.dp, y = (-4).dp)
                        .background(tokens.destructive, RoundedCornerShape(999.dp))
                        .padding(horizontal = 4.dp, vertical = 1.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = badgeText,
                        color = Color.White,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        style = TextStyle(fontFeatureSettings = "tnum"),
                        maxLines = 1
                    )
                }
            }
        }
    }
}

@Composable
private fun PrivacyButton(revealed: Boolean, onClick: () -> Unit) {
    ToolbarCircleButton(
        onClick = onClick,
        accessibilityName = if (revealed) "Hide mature" else "Show mature"
    ) {
        Icon(
            imageVector = if (revealed) Icons.Filled.Visibility else Icons.Filled.VisibilityOff,
            contentDescription = null
        )
    }
}
