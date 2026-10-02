package io.github.cidy02.kudos.home

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.ui.subject.GlassCircleButton
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectMetrics

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
        actions.onNewQueue = {}
        actions.onSelectAll = {}
        actions.onEnterSelect = {}
        actions.onTogglePrivacy = {}
    }
}

class HomeShellActions {
    var onNewQueue: () -> Unit = {}
    var onSelectAll: () -> Unit = {}
    var onEnterSelect: () -> Unit = {}
    var onTogglePrivacy: () -> Unit = {}
}

/** "+" and "…" while browsing. Select All, and the eye when mature hiding is on, while selecting. */
@Composable
fun HomeToolbarActions(chrome: HomeShellChrome) {
    val tokens = LocalKudosTokens.current
    if (chrome.hideTabBar) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = if (chrome.allSelected) "Deselect All" else "Select All",
                color = tokens.accent,
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
        Row(verticalAlignment = Alignment.CenterVertically) {
            GlassCircleButton(
                onClick = { chrome.actions.onNewQueue() },
                accessibilityName = "New Queue",
                diameter = SubjectMetrics.toolbarCircle
            ) {
                Icon(Icons.Filled.Add, contentDescription = null, tint = tokens.accent)
            }
            if (chrome.showOverflow) {
                var open by remember { mutableStateOf(false) }
                Box {
                    GlassCircleButton(
                        onClick = { open = true },
                        accessibilityName = "More",
                        diameter = SubjectMetrics.toolbarCircle
                    ) {
                        Icon(Icons.Filled.MoreHoriz, contentDescription = null)
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
        }
    }
}

@Composable
private fun PrivacyButton(revealed: Boolean, onClick: () -> Unit) {
    GlassCircleButton(
        onClick = onClick,
        accessibilityName = if (revealed) "Hide mature" else "Show mature",
        diameter = SubjectMetrics.toolbarCircle
    ) {
        Icon(
            imageVector = if (revealed) Icons.Filled.Visibility else Icons.Filled.VisibilityOff,
            contentDescription = null
        )
    }
}
