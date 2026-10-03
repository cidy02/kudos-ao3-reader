package io.github.cidy02.kudos.account

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.FilterList
import androidx.compose.material.icons.outlined.MarkEmailRead
import androidx.compose.material.icons.outlined.MarkEmailUnread
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentParticipantRole
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentRepository
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentWorkAuthor
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxBulkAction
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxItem
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxRepository
import io.github.cidy02.kudos.ui.components.CommentAvatar
import io.github.cidy02.kudos.ui.components.CommentParticipantBadge
import io.github.cidy02.kudos.ui.components.DestructiveConfirmation
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.KudosPaginationBar
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectChip
import io.github.cidy02.kudos.ui.subject.SubjectChipStyle
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.subjectPanel
import io.github.cidy02.kudos.ui.subject.subjectScreenWash

/**
 * Account › Activity › Inbox pane — redesigned to match iOS AccountInboxScreen.swift and AccountInboxViews.swift.
 */
@Composable
fun AccountInboxPane(
    inboxRepository: AO3InboxRepository,
    commentRepository: AO3CommentRepository,
    currentUsername: String?,
    onOpenWorkComments: (workId: Long, focusedId: Long?) -> Unit,
    settingsRepository: SettingsRepository? = null,
    modifier: Modifier = Modifier,
    viewModel: AccountInboxViewModel = viewModel(
        key = "account-inbox",
        factory = AccountInboxViewModel.factory(inboxRepository, commentRepository)
    )
) {
    val state by viewModel.uiState.collectAsState()
    val settingsFlow = settingsRepository?.settings ?: kotlinx.coroutines.flow.flowOf(KudosSettings.Defaults)
    val settingsState = settingsFlow.collectAsState(initial = KudosSettings.Defaults)
    val settings = settingsState.value
    val tokens = LocalKudosTokens.current
    val palette = remember(tokens.theme) { SubjectPalette.fromHue(210.0, tokens.theme) }

    var pendingDelete by remember { mutableStateOf<PendingInboxDelete?>(null) }
    var showingFilters by remember { mutableStateOf(false) }

    ProvidePushedShellChrome(
        hasSubjectHeader = true,
        trailingContent = {
            if (state.isSelecting) {
                TextButton(
                    onClick = viewModel::toggleSelectAllCurrentPage,
                    enabled = !state.isPerformingBulkAction && state.selectableItemIds.isNotEmpty()
                ) {
                    Text(
                        text = if (state.allCurrentPageSelected) "Deselect all" else "Select all",
                        color = palette.accent
                    )
                }
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    if (state.canFilter) {
                        IconButton(onClick = { showingFilters = true }) {
                            Icon(
                                imageVector = Icons.Outlined.FilterList,
                                contentDescription = "Filters",
                                tint = tokens.secondaryInk
                            )
                        }
                    }
                    if (state.canSelectItems) {
                        var showMoreMenu by remember { mutableStateOf(false) }
                        Box {
                            IconButton(onClick = { showMoreMenu = true }) {
                                Icon(
                                    imageVector = Icons.Outlined.MoreVert,
                                    contentDescription = "Select inbox items",
                                    tint = tokens.secondaryInk
                                )
                            }
                            DropdownMenu(
                                expanded = showMoreMenu,
                                onDismissRequest = { showMoreMenu = false }
                            ) {
                                DropdownMenuItem(
                                    text = { Text("Select") },
                                    leadingIcon = {
                                        Icon(Icons.Outlined.Checklist, contentDescription = null)
                                    },
                                    onClick = {
                                        showMoreMenu = false
                                        viewModel.beginSelection()
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
    )

    DestructiveConfirmation(
        show = pendingDelete != null,
        title = if (pendingDelete?.items?.size == 1) {
            "Remove this notification from your AO3 Inbox?"
        } else {
            "Remove ${pendingDelete?.items?.size ?: 0} notifications from your AO3 Inbox?"
        },
        text = "This only removes the selected notification${if (pendingDelete?.items?.size == 1) "" else "s"} from AO3's Inbox. It does not delete the comment${if (pendingDelete?.items?.size == 1) "" else "s"}.",
        confirmText = "Delete From Inbox",
        confirmBeforeDelete = settings.app.confirmBeforeDelete,
        onConfirm = {
            val pending = pendingDelete ?: return@DestructiveConfirmation
            pendingDelete = null
            if (pending.items.size == 1) {
                viewModel.startItemAction(
                    AO3InboxBulkAction.Delete,
                    pending.items.first()
                )
            } else {
                viewModel.startBulkAction(AO3InboxBulkAction.Delete)
            }
        },
        onDismissRequest = { pendingDelete = null }
    )

    if (showingFilters && state.filterForm != null) {
        AccountInboxFilterSheet(
            filterForm = state.filterForm!!,
            selectedValues = state.filterValues,
            onApplyFilter = viewModel::applyFilter,
            onDismiss = { showingFilters = false },
            palette = palette
        )
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .subjectScreenWash(palette = palette)
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            Spacer(modifier = Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
            Spacer(modifier = Modifier.height(56.dp))

            val tally = buildString {
                state.totalComments?.let { append("$it comments") }
                state.unreadCount?.let {
                    if (isNotEmpty()) append(" · ")
                    append("$it unread")
                }
                if (state.totalPages > 1) {
                    if (isNotEmpty()) append(" · ")
                    append("Page ${state.currentPage} of ${state.totalPages}")
                }
            }.ifEmpty { null }

            SubjectHeaderBlock(
                kicker = "AO3 Account",
                title = "Inbox",
                subtitle = tally,
                palette = palette,
                gutter = SubjectMetrics.accountGutter
            )

            Spacer(modifier = Modifier.height(12.dp))

            // Filter pills (All, Unread, Awaiting reply, Replied)
            InboxFilterPillRail(
                state = state,
                palette = palette,
                onApplyFilters = viewModel::applyFilters
            )

            Spacer(modifier = Modifier.height(12.dp))

            state.actionError?.let { message ->
                Box(modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter)) {
                    ErrorStateCard(
                        title = "Couldn't update Inbox",
                        message = message,
                        primaryActionLabel = "Dismiss",
                        onPrimaryAction = viewModel::clearActionError
                    )
                }
                Spacer(modifier = Modifier.height(8.dp))
            }

            state.actionNotice?.let { message ->
                Surface(
                    color = MaterialTheme.colorScheme.secondaryContainer,
                    shape = MaterialTheme.shapes.medium,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = SubjectMetrics.accountGutter)
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = message,
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.weight(1f)
                        )
                        TextButton(onClick = viewModel::clearActionNotice) {
                            Text("OK")
                        }
                    }
                }
                Spacer(modifier = Modifier.height(8.dp))
            }

            when {
                state.phase == AccountInboxUiState.Phase.Loading && state.items.isEmpty() -> {
                    Box(modifier = Modifier.padding(SubjectMetrics.accountGutter)) {
                        LoadingStateCard("Loading Inbox")
                    }
                }
                state.phase == AccountInboxUiState.Phase.Failed && state.items.isEmpty() -> {
                    Box(modifier = Modifier.padding(SubjectMetrics.accountGutter)) {
                        ErrorStateCard(
                            title = "Couldn't load your inbox",
                            message = state.actionError ?: "Something went wrong.",
                            primaryActionLabel = "Retry",
                            onPrimaryAction = viewModel::retry
                        )
                    }
                }
                state.phase == AccountInboxUiState.Phase.Loaded && state.items.isEmpty() -> {
                    Box(modifier = Modifier.padding(SubjectMetrics.accountGutter)) {
                        EmptyStateCard(
                            title = "No comments yet",
                            message = "Comments on your works and replies to your comments appear here from your AO3 inbox."
                        )
                    }
                }
                else -> {
                    LazyColumn(
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                        contentPadding = PaddingValues(
                            start = SubjectMetrics.accountGutter,
                            end = SubjectMetrics.accountGutter,
                            bottom = if (state.isSelecting) 80.dp else 24.dp
                        ),
                        modifier = Modifier.fillMaxSize()
                    ) {
                        items(state.items, key = { it.id }) { item ->
                            val authors = state.workAuthorsById[item.workId].orEmpty()
                            InboxItemCard(
                                item = item,
                                workAuthors = authors,
                                currentUsername = currentUsername,
                                isSelecting = state.isSelecting,
                                isSelected = item.id in state.selectedItemIds,
                                isSelectable = item.id in state.selectableItemIds,
                                isPerformingAction = state.isPerformingBulkAction,
                                canMarkRead = viewModel.canPerformItemAction(
                                    AO3InboxBulkAction.MarkRead,
                                    item
                                ),
                                canMarkUnread = viewModel.canPerformItemAction(
                                    AO3InboxBulkAction.MarkUnread,
                                    item
                                ),
                                canDelete = viewModel.canPerformItemAction(
                                    AO3InboxBulkAction.Delete,
                                    item
                                ),
                                onOpen = {
                                    item.workId?.let { onOpenWorkComments(it, item.id) }
                                },
                                onOpenChapter = {
                                    item.workId?.let { onOpenWorkComments(it, item.id) }
                                },
                                onReply = {
                                    item.workId?.let { onOpenWorkComments(it, item.id) }
                                },
                                onToggleSelection = { viewModel.toggleSelection(item) },
                                onMarkRead = {
                                    viewModel.startItemAction(AO3InboxBulkAction.MarkRead, item)
                                },
                                onMarkUnread = {
                                    viewModel.startItemAction(AO3InboxBulkAction.MarkUnread, item)
                                },
                                onDelete = {
                                    pendingDelete = PendingInboxDelete(listOf(item))
                                },
                                palette = palette
                            )
                        }

                        if (state.totalPages > 1) {
                            item {
                                KudosPaginationBar(
                                    currentPage = state.currentPage,
                                    totalPages = state.totalPages,
                                    onPageChange = viewModel::goToPage,
                                    enabled = !state.isPerformingBulkAction,
                                    modifier = Modifier.padding(vertical = 8.dp)
                                )
                            }
                        }
                    }
                }
            }
        }

        // Floating Bulk Action Bar when selecting (matches iOS AccountInboxBulkActionBar)
        if (state.isSelecting) {
            Surface(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth(),
                color = tokens.cardFill,
                shadowElevation = 8.dp
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    TextButton(
                        onClick = {
                            if (state.selectedItems.isNotEmpty()) {
                                pendingDelete = PendingInboxDelete(state.selectedItems)
                            }
                        },
                        enabled = state.selectedItems.isNotEmpty() && !state.isPerformingBulkAction
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.Delete,
                            contentDescription = "Delete from inbox",
                            tint = if (state.selectedItems.isNotEmpty()) MaterialTheme.colorScheme.error else tokens.tertiaryInk
                        )
                        Spacer(modifier = Modifier.size(4.dp))
                        Text(
                            text = "Delete",
                            color = if (state.selectedItems.isNotEmpty()) MaterialTheme.colorScheme.error else tokens.tertiaryInk
                        )
                    }

                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        TextButton(
                            onClick = {
                                viewModel.startBulkAction(AO3InboxBulkAction.MarkRead)
                            },
                            enabled = state.selectedItems.isNotEmpty() && !state.isPerformingBulkAction
                        ) {
                            Icon(Icons.Outlined.MarkEmailRead, contentDescription = "Mark read", tint = palette.accent)
                            Spacer(modifier = Modifier.size(4.dp))
                            Text("Mark Read", color = palette.accent)
                        }
                        TextButton(
                            onClick = {
                                viewModel.startBulkAction(AO3InboxBulkAction.MarkUnread)
                            },
                            enabled = state.selectedItems.isNotEmpty() && !state.isPerformingBulkAction
                        ) {
                            Icon(Icons.Outlined.MarkEmailUnread, contentDescription = "Mark unread", tint = palette.accent)
                            Spacer(modifier = Modifier.size(4.dp))
                            Text("Mark Unread", color = palette.accent)
                        }
                    }

                    TextButton(
                        onClick = viewModel::endSelection,
                        enabled = !state.isPerformingBulkAction
                    ) {
                        Text("Done", color = palette.accent, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }
    }
}

private data class PendingInboxDelete(val items: List<AO3InboxItem>)

@Composable
private fun InboxFilterPillRail(
    state: AccountInboxUiState,
    palette: SubjectPalette,
    onApplyFilters: (Map<String, String>) -> Unit
) {
    val currentRead = state.filterValues["filters[read]"] ?: "all"
    val currentReplied = state.filterValues["filters[replied_to]"] ?: "all"

    val isAll = currentRead == "all" && currentReplied == "all"
    val isUnread = currentRead == "false"
    val isAwaitingReply = currentReplied == "false"
    val isReplied = currentReplied == "true"

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = SubjectMetrics.accountGutter),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        SubjectChip(
            text = "All",
            style = SubjectChipStyle.Pill(isSelected = isAll),
            palette = palette,
            modifier = Modifier.clickable {
                val map = state.filterValues.toMutableMap()
                map["filters[read]"] = "all"
                map["filters[replied_to]"] = "all"
                onApplyFilters(map)
            }
        )
        SubjectChip(
            text = "Unread",
            style = SubjectChipStyle.Pill(isSelected = isUnread),
            palette = palette,
            modifier = Modifier.clickable {
                val map = state.filterValues.toMutableMap()
                map["filters[read]"] = "false"
                onApplyFilters(map)
            }
        )
        SubjectChip(
            text = "Awaiting reply",
            style = SubjectChipStyle.Pill(isSelected = isAwaitingReply),
            palette = palette,
            modifier = Modifier.clickable {
                val map = state.filterValues.toMutableMap()
                map["filters[replied_to]"] = "false"
                onApplyFilters(map)
            }
        )
        SubjectChip(
            text = "Replied",
            style = SubjectChipStyle.Pill(isSelected = isReplied),
            palette = palette,
            modifier = Modifier.clickable {
                val map = state.filterValues.toMutableMap()
                map["filters[replied_to]"] = "true"
                onApplyFilters(map)
            }
        )
    }
}

@Composable
private fun InboxItemCard(
    item: AO3InboxItem,
    workAuthors: List<AO3CommentWorkAuthor>,
    currentUsername: String?,
    isSelecting: Boolean,
    isSelected: Boolean,
    isSelectable: Boolean,
    isPerformingAction: Boolean,
    canMarkRead: Boolean,
    canMarkUnread: Boolean,
    canDelete: Boolean,
    onOpen: () -> Unit,
    onOpenChapter: () -> Unit,
    onReply: () -> Unit,
    onToggleSelection: () -> Unit,
    onMarkRead: () -> Unit,
    onMarkUnread: () -> Unit,
    onDelete: () -> Unit,
    palette: SubjectPalette
) {
    val tokens = LocalKudosTokens.current
    val role = item.participantRole(
        workAuthors = workAuthors.map { it.displayName },
        workAuthorUsernames = workAuthors.mapNotNull { it.username },
        currentUsername = currentUsername
    )

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .subjectPanel()
            .then(
                if (isSelecting) {
                    Modifier.clickable(enabled = isSelectable, onClick = onToggleSelection)
                } else if (!item.isUnavailable && item.workId != null) {
                    Modifier.clickable(onClick = onOpen)
                } else {
                    Modifier
                }
            )
            .padding(14.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            if (isSelecting) {
                Checkbox(
                    checked = isSelected,
                    onCheckedChange = { onToggleSelection() },
                    enabled = isSelectable && !isPerformingAction,
                    modifier = Modifier.align(Alignment.CenterVertically)
                )
            }

            if (item.isUnavailable) {
                Box(
                    modifier = Modifier
                        .size(40.dp)
                        .clip(CircleShape)
                        .background(tokens.glassFill(0.2)),
                    contentAlignment = Alignment.Center
                ) {
                    Text("?", color = tokens.secondaryInk, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                }
                Text(
                    text = "A comment here is unavailable",
                    color = tokens.secondaryInk,
                    fontSize = 14.sp,
                    modifier = Modifier
                        .weight(1f)
                        .align(Alignment.CenterVertically)
                )
            } else {
                CommentAvatar(
                    avatarUrl = item.avatarUrl,
                    isGuest = item.isGuest,
                    size = 40.dp
                )

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
                                    .size(8.dp)
                                    .clip(CircleShape)
                                    .background(palette.accent)
                            )
                        }
                        Text(
                            text = item.commenterName,
                            color = tokens.primaryInk,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f, fill = false)
                        )
                        if (role != AO3CommentParticipantRole.User || workAuthors.isNotEmpty()) {
                            if (role != AO3CommentParticipantRole.User ||
                                item.isGuest ||
                                item.isAnonymousCreator ||
                                workAuthors.isNotEmpty() ||
                                item.commenterUsername?.equals(currentUsername, ignoreCase = true) == true
                            ) {
                                CommentParticipantBadge(role = role)
                            }
                        }
                        if (item.postedAgo.isNotEmpty()) {
                            Text(
                                text = item.postedAgo,
                                color = tokens.tertiaryInk,
                                fontSize = 11.sp,
                                maxLines = 1
                            )
                        }
                    }

                    // Context on work / chapter
                    if (item.subjectTitle.isNotEmpty()) {
                        val chapter = item.chapterIndicatorTitle
                        if (chapter != null) {
                            Row(
                                horizontalArrangement = Arrangement.spacedBy(4.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    text = "on",
                                    color = tokens.secondaryInk,
                                    fontSize = 12.sp
                                )
                                Text(
                                    text = "$chapter of ${item.workTitle}",
                                    color = tokens.secondaryInk,
                                    fontSize = 12.sp,
                                    maxLines = 2,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                        } else {
                            Text(
                                text = "on ${item.subjectTitle}",
                                color = tokens.secondaryInk,
                                fontSize = 12.sp,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                    }

                    // Excerpt
                    if (item.excerpt.isNotEmpty()) {
                        Text(
                            text = item.excerpt,
                            color = tokens.primaryInk,
                            fontSize = 14.sp,
                            maxLines = 3,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.padding(top = 2.dp)
                        )
                    }

                    // Bottom actions row: Replied badge, Reply, Chapter comments, Menu
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        if (item.isReplied) {
                            InboxRepliedBadge()
                        }
                        Spacer(Modifier.weight(1f))
                        if (!isSelecting) {
                            TextButton(onClick = onReply) {
                                Text("Reply", fontSize = 12.sp, color = palette.accent)
                            }
                            if (item.chapterIndicatorTitle != null) {
                                TextButton(onClick = onOpenChapter) {
                                    Text("Chapter Comments", fontSize = 12.sp, color = tokens.secondaryInk)
                                }
                            }
                            InboxItemOverflowMenu(
                                item = item,
                                enabled = !isPerformingAction,
                                canMarkRead = canMarkRead,
                                canMarkUnread = canMarkUnread,
                                canDelete = canDelete,
                                onOpen = onOpen,
                                onOpenChapter = onOpenChapter,
                                onMarkRead = onMarkRead,
                                onMarkUnread = onMarkUnread,
                                onDelete = onDelete
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun InboxRepliedBadge() {
    Surface(
        shape = RoundedCornerShape(percent = 50),
        color = Color(0xFF2E7D32).copy(alpha = 0.12f),
        contentColor = Color(0xFF2E7D32)
    ) {
        Text(
            text = "Replied",
            color = Color(0xFF2E7D32),
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp)
        )
    }
}

@Composable
private fun InboxItemOverflowMenu(
    item: AO3InboxItem,
    enabled: Boolean,
    canMarkRead: Boolean,
    canMarkUnread: Boolean,
    canDelete: Boolean,
    onOpen: () -> Unit,
    onOpenChapter: () -> Unit,
    onMarkRead: () -> Unit,
    onMarkUnread: () -> Unit,
    onDelete: () -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    val clipboardManager = LocalClipboardManager.current

    Box {
        IconButton(
            onClick = { expanded = true },
            enabled = enabled,
            modifier = Modifier.size(28.dp)
        ) {
            Icon(
                Icons.Outlined.MoreVert,
                contentDescription = "More actions for ${item.commenterName}'s inbox comment",
                modifier = Modifier.size(18.dp)
            )
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            if (item.workId != null) {
                DropdownMenuItem(
                    text = { Text("Open Thread") },
                    onClick = {
                        expanded = false
                        onOpen()
                    }
                )
                if (item.chapterIndicatorTitle != null) {
                    DropdownMenuItem(
                        text = { Text("Chapter Comments") },
                        onClick = {
                            expanded = false
                            onOpenChapter()
                        }
                    )
                }
                DropdownMenuItem(
                    text = { Text("Copy Link") },
                    onClick = {
                        expanded = false
                        item.workId?.let { workId ->
                            clipboardManager.setText(
                                AnnotatedString("https://archiveofourown.org/comments/${item.id}")
                            )
                        }
                    }
                )
            }
            if (item.isUnread && canMarkRead) {
                DropdownMenuItem(
                    text = { Text("Mark Read") },
                    onClick = {
                        expanded = false
                        onMarkRead()
                    }
                )
            }
            if (!item.isUnread && canMarkUnread) {
                DropdownMenuItem(
                    text = { Text("Mark Unread") },
                    onClick = {
                        expanded = false
                        onMarkUnread()
                    }
                )
            }
            if (canDelete) {
                DropdownMenuItem(
                    text = {
                        Text(
                            text = "Delete From Inbox",
                            color = MaterialTheme.colorScheme.error
                        )
                    },
                    onClick = {
                        expanded = false
                        onDelete()
                    }
                )
            }
        }
    }
}
