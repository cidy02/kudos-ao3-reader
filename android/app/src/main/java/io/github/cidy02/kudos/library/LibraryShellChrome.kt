package io.github.cidy02.kudos.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.List
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.CollectionsBookmark
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Queue
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
import io.github.cidy02.kudos.ui.subject.WorkSectionLayout
import io.github.cidy02.kudos.ui.theme.Ao3Red

/**
 * Library's top-right chrome, drawn by MainScaffold on the large title's row so it matches iOS and Home.
 */
class LibraryShellChrome {
    var mounted by mutableStateOf(false)
    var hideTabBar by mutableStateOf(false)
    var selectionTitle by mutableStateOf<String?>(null)
    var allSelected by mutableStateOf(false)
    var showPrivacyToggle by mutableStateOf(false)
    var revealAll by mutableStateOf(false)
    var hasSavedWorks by mutableStateOf(false)
    var filtersActive by mutableStateOf(false)
    var filterBadgeCount by mutableStateOf(0)
    var layout by mutableStateOf(WorkSectionLayout.Shelves)
    val actions = LibraryShellActions()

    fun reset() {
        mounted = false
        hideTabBar = false
        selectionTitle = null
        allSelected = false
        showPrivacyToggle = false
        revealAll = false
        hasSavedWorks = false
        filtersActive = false
        filterBadgeCount = 0
        layout = WorkSectionLayout.Shelves
        actions.onNewCollection = {}
        actions.onShowFilters = {}
        actions.onSelectAll = {}
        actions.onEnterSelect = {}
        actions.onTogglePrivacy = {}
        actions.onLayoutChange = {}
        actions.onOpenReadingQueues = {}
        actions.onOpenReadingStatistics = {}
        actions.onOpenRecentlyDeleted = {}
    }
}

class LibraryShellActions {
    var onNewCollection: () -> Unit = {}
    var onShowFilters: () -> Unit = {}
    var onSelectAll: () -> Unit = {}
    var onEnterSelect: () -> Unit = {}
    var onTogglePrivacy: () -> Unit = {}
    var onLayoutChange: (WorkSectionLayout) -> Unit = {}
    var onOpenReadingQueues: () -> Unit = {}
    var onOpenReadingStatistics: () -> Unit = {}
    var onOpenRecentlyDeleted: () -> Unit = {}
}

@Composable
fun LibraryToolbarActions(chrome: LibraryShellChrome) {
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
            if (chrome.showPrivacyToggle) {
                GlassCircleButton(
                    onClick = { chrome.actions.onTogglePrivacy() },
                    accessibilityName = if (chrome.revealAll) "Hide mature" else "Show mature"
                ) {
                    Icon(
                        imageVector = if (chrome.revealAll) Icons.Filled.Visibility else Icons.Filled.VisibilityOff,
                        contentDescription = null
                    )
                }
            }
        }
    } else {
        Row(
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            GlassCircleButton(
                onClick = { chrome.actions.onNewCollection() },
                accessibilityName = "New Collection"
            ) {
                Icon(Icons.Filled.Add, contentDescription = null, tint = Ao3Red)
            }
            GlassCircleButton(
                onClick = { chrome.actions.onShowFilters() },
                accessibilityName = "Filter",
                isAccented = chrome.filtersActive,
                badge = if (chrome.filterBadgeCount > 0) chrome.filterBadgeCount.toString() else null
            ) {
                Icon(
                    imageVector = Icons.Filled.FilterList,
                    contentDescription = null,
                    tint = if (chrome.filtersActive) tokens.accent else tokens.primaryInk
                )
            }
            var open by remember { mutableStateOf(false) }
            Box {
                GlassCircleButton(onClick = { open = true }, accessibilityName = "More") {
                    Icon(Icons.Filled.MoreHoriz, contentDescription = null)
                }
                DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                    if (chrome.showPrivacyToggle) {
                        DropdownMenuItem(
                            text = { Text(if (chrome.revealAll) "Hide mature works" else "Show mature works") },
                            leadingIcon = {
                                Icon(
                                    if (chrome.revealAll) Icons.Filled.Visibility else Icons.Filled.VisibilityOff,
                                    contentDescription = null
                                )
                            },
                            onClick = {
                                open = false
                                chrome.actions.onTogglePrivacy()
                            }
                        )
                    }
                    if (chrome.hasSavedWorks) {
                        DropdownMenuItem(
                            text = { Text("Select") },
                            leadingIcon = { Icon(Icons.Outlined.Checklist, contentDescription = null) },
                            onClick = {
                                open = false
                                chrome.actions.onEnterSelect()
                            }
                        )
                    }
                    DropdownMenuItem(
                        text = {
                            Text(
                                if (chrome.layout == WorkSectionLayout.Shelves) "Show Detailed List" else "Show Carousels"
                            )
                        },
                        leadingIcon = {
                            Icon(
                                if (chrome.layout == WorkSectionLayout.Shelves) {
                                    Icons.AutoMirrored.Outlined.List
                                } else {
                                    Icons.Outlined.CollectionsBookmark
                                },
                                contentDescription = null
                            )
                        },
                        onClick = {
                            open = false
                            chrome.actions.onLayoutChange(
                                if (chrome.layout == WorkSectionLayout.Shelves) {
                                    WorkSectionLayout.Ledger
                                } else {
                                    WorkSectionLayout.Shelves
                                }
                            )
                        }
                    )
                    DropdownMenuItem(
                        text = { Text("Reading Queues") },
                        leadingIcon = { Icon(Icons.Outlined.Queue, contentDescription = null) },
                        onClick = {
                            open = false
                            chrome.actions.onOpenReadingQueues()
                        }
                    )
                    if (chrome.hasSavedWorks) {
                        DropdownMenuItem(
                            text = { Text("Reading Insights") },
                            leadingIcon = { Icon(Icons.Outlined.BarChart, contentDescription = null) },
                            onClick = {
                                open = false
                                chrome.actions.onOpenReadingStatistics()
                            }
                        )
                    }
                    DropdownMenuItem(
                        text = { Text("Recently Deleted") },
                        leadingIcon = { Icon(Icons.Outlined.Delete, contentDescription = null) },
                        onClick = {
                            open = false
                            chrome.actions.onOpenRecentlyDeleted()
                        }
                    )
                }
            }
        }
    }
}
