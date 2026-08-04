package io.github.cidy02.kudos.account

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.FilterList
import androidx.compose.material.icons.outlined.MarkEmailRead
import androidx.compose.material.icons.outlined.MarkEmailUnread
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material3.AlertDialog
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.ui.components.DestructiveConfirmation
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentParticipantRole
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentRepository
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentWorkAuthor
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxBulkAction
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxFilterField
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxItem
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxRepository
import io.github.cidy02.kudos.ui.components.CommentAvatar
import io.github.cidy02.kudos.ui.components.CommentParticipantBadge
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.KudosSectionHeader
import io.github.cidy02.kudos.ui.components.LoadingStateCard

/**
 * Account › Activity › Inbox pane — Material 3 expression of iOS AccountInboxViews.
 *
 * Chapter position is shown as informational text only; taps always open the
 * work's general comment thread ([AO3CommentTarget.Work]), matching Android's
 * existing comments-routing gap (not a new regression).
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
    val settingsState = settingsRepository?.settings?.collectAsState(initial = KudosSettings.Defaults)
    val settings = settingsState?.value ?: KudosSettings.Defaults
    var pendingDelete by remember { mutableStateOf<PendingInboxDelete?>(null) }

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

    when {
        state.phase == AccountInboxUiState.Phase.Loading && state.items.isEmpty() -> {
            LoadingStateCard("Loading Inbox")
        }
        state.phase == AccountInboxUiState.Phase.Failed && state.items.isEmpty() -> {
            ErrorStateCard(
                title = "Couldn't load your inbox",
                message = state.actionError ?: "Something went wrong.",
                primaryActionLabel = "Retry",
                onPrimaryAction = viewModel::retry
            )
        }
        state.phase == AccountInboxUiState.Phase.Loaded && state.items.isEmpty() -> {
            EmptyStateCard(
                title = "No comments yet",
                message = "Comments on your works, and replies to comments you've " +
                    "posted, show up here from your AO3 inbox."
            )
        }
        else -> {
            Column(
                modifier = modifier.fillMaxSize(),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                InboxToolbar(
                    state = state,
                    onBeginSelection = viewModel::beginSelection,
                    onEndSelection = viewModel::endSelection,
                    onToggleSelectAll = viewModel::toggleSelectAllCurrentPage,
                    onFilter = viewModel::applyFilter,
                    onBulkMarkRead = {
                        viewModel.startBulkAction(AO3InboxBulkAction.MarkRead)
                    },
                    onBulkMarkUnread = {
                        viewModel.startBulkAction(AO3InboxBulkAction.MarkUnread)
                    },
                    onBulkDelete = {
                        if (state.selectedItems.isNotEmpty()) {
                            pendingDelete = PendingInboxDelete(state.selectedItems)
                        }
                    }
                )

                state.actionError?.let { message ->
                    ErrorStateCard(
                        title = "Inbox update",
                        message = message,
                        primaryActionLabel = "Dismiss",
                        onPrimaryAction = viewModel::clearActionError
                    )
                }
                state.actionNotice?.let { message ->
                    Surface(
                        color = MaterialTheme.colorScheme.secondaryContainer,
                        shape = MaterialTheme.shapes.medium,
                        modifier = Modifier.fillMaxWidth()
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
                }

                LazyColumn(
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    contentPadding = PaddingValues(bottom = 24.dp),
                    modifier = Modifier.fillMaxSize()
                ) {
                    item {
                        val subtitle = buildString {
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
                        KudosSectionHeader(title = "Inbox", subtitle = subtitle)
                    }

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
                            onToggleSelection = { viewModel.toggleSelection(item) },
                            onMarkRead = {
                                viewModel.startItemAction(AO3InboxBulkAction.MarkRead, item)
                            },
                            onMarkUnread = {
                                viewModel.startItemAction(AO3InboxBulkAction.MarkUnread, item)
                            },
                            onDelete = {
                                pendingDelete = PendingInboxDelete(listOf(item))
                            }
                        )
                    }

                    if (state.totalPages > 1) {
                        item {
                            InboxPaginationControls(
                                page = state.currentPage,
                                totalPages = state.totalPages,
                                enabled = !state.isPerformingBulkAction,
                                onLoadPage = viewModel::goToPage
                            )
                        }
                    }
                }
            }
        }
    }
}

private data class PendingInboxDelete(val items: List<AO3InboxItem>)

@Composable
private fun InboxToolbar(
    state: AccountInboxUiState,
    onBeginSelection: () -> Unit,
    onEndSelection: () -> Unit,
    onToggleSelectAll: () -> Unit,
    onFilter: (String, String) -> Unit,
    onBulkMarkRead: () -> Unit,
    onBulkMarkUnread: () -> Unit,
    onBulkDelete: () -> Unit
) {
    if (state.isSelecting) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            TextButton(
                onClick = onToggleSelectAll,
                enabled = !state.isPerformingBulkAction && state.selectableItemIds.isNotEmpty()
            ) {
                Text(if (state.allCurrentPageSelected) "Deselect all" else "Select all")
            }
            Spacer(Modifier.weight(1f))
            IconButton(
                onClick = onBulkDelete,
                enabled = state.selectedItems.isNotEmpty() && !state.isPerformingBulkAction
            ) {
                Icon(Icons.Outlined.Delete, contentDescription = "Delete from inbox")
            }
            IconButton(
                onClick = onBulkMarkRead,
                enabled = state.selectedItems.isNotEmpty() && !state.isPerformingBulkAction
            ) {
                Icon(Icons.Outlined.MarkEmailRead, contentDescription = "Mark read")
            }
            IconButton(
                onClick = onBulkMarkUnread,
                enabled = state.selectedItems.isNotEmpty() && !state.isPerformingBulkAction
            ) {
                Icon(Icons.Outlined.MarkEmailUnread, contentDescription = "Mark unread")
            }
            TextButton(
                onClick = onEndSelection,
                enabled = !state.isPerformingBulkAction
            ) {
                Text("Done")
            }
        }
    } else {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.End,
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (state.canFilter) {
                InboxFilterMenu(
                    fields = state.filterForm?.fields.orEmpty(),
                    selectedValues = state.filterValues,
                    enabled = !state.isPerformingBulkAction,
                    onSelect = onFilter
                )
            }
            if (state.canSelectItems) {
                IconButton(
                    onClick = onBeginSelection,
                    enabled = !state.isPerformingBulkAction
                ) {
                    Icon(Icons.Outlined.Checklist, contentDescription = "Select inbox items")
                }
            }
        }
    }
}

@Composable
private fun InboxFilterMenu(
    fields: List<AO3InboxFilterField>,
    selectedValues: Map<String, String>,
    enabled: Boolean,
    onSelect: (String, String) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        OutlinedButton(
            onClick = { expanded = true },
            enabled = enabled
        ) {
            Icon(
                Icons.Outlined.FilterList,
                contentDescription = null,
                modifier = Modifier.size(18.dp)
            )
            Spacer(Modifier.width(6.dp))
            Text("Filters")
            Icon(Icons.Outlined.ExpandMore, contentDescription = null)
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            fields.forEach { field ->
                Text(
                    text = field.title,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp)
                )
                field.options.forEach { option ->
                    val selected = (selectedValues[field.name] ?: field.selectedValue) ==
                        option.value
                    DropdownMenuItem(
                        text = {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(option.label, modifier = Modifier.weight(1f))
                                if (selected) {
                                    Icon(
                                        Icons.Outlined.Check,
                                        contentDescription = "Selected",
                                        modifier = Modifier.size(18.dp)
                                    )
                                }
                            }
                        },
                        onClick = {
                            expanded = false
                            onSelect(field.name, option.value)
                        }
                    )
                }
            }
        }
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
    onToggleSelection: () -> Unit,
    onMarkRead: () -> Unit,
    onMarkUnread: () -> Unit,
    onDelete: () -> Unit
) {
    val role = item.participantRole(
        workAuthors = workAuthors.map { it.displayName },
        workAuthorUsernames = workAuthors.mapNotNull { it.username },
        currentUsername = currentUsername
    )

    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow
        ),
        modifier = Modifier
            .fillMaxWidth()
            .then(
                if (isSelecting) {
                    Modifier.clickable(enabled = isSelectable, onClick = onToggleSelection)
                } else if (!item.isUnavailable && item.workId != null) {
                    Modifier.clickable(onClick = onOpen)
                } else {
                    Modifier
                }
            )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            if (isSelecting) {
                Checkbox(
                    checked = isSelected,
                    onCheckedChange = { onToggleSelection() },
                    enabled = isSelectable && !isPerformingAction
                )
            }

            if (item.isUnavailable) {
                Box(
                    modifier = Modifier
                        .size(40.dp)
                        .clip(CircleShape)
                        .background(MaterialTheme.colorScheme.surfaceContainerHighest),
                    contentAlignment = Alignment.Center
                ) {
                    Text("?", style = MaterialTheme.typography.labelLarge)
                }
                Text(
                    text = "A comment here is unavailable",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier
                        .weight(1f)
                        .align(Alignment.CenterVertically)
                )
            } else {
            CommentAvatar(
                avatarUrl = item.avatarUrl,
                isGuest = item.isGuest
            )

            Column(modifier = Modifier.weight(1f)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    if (item.isUnread) {
                        Box(
                            modifier = Modifier
                                .size(8.dp)
                                .clip(CircleShape)
                                .background(MaterialTheme.colorScheme.primary)
                        )
                    }
                    Text(
                        text = item.commenterName,
                        style = MaterialTheme.typography.titleSmall.copy(
                            fontWeight = FontWeight.SemiBold
                        ),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false)
                    )
                    if (role != AO3CommentParticipantRole.User || workAuthors.isNotEmpty()) {
                        // Show badge when enrichment resolved Author/Me/Guest, or
                        // always for Guest/anonymous; skip neutral User when
                        // authors aren't loaded yet so we don't flash User→Author.
                        if (role != AO3CommentParticipantRole.User ||
                            item.isGuest ||
                            item.isAnonymousCreator ||
                            workAuthors.isNotEmpty() ||
                            item.commenterUsername?.equals(
                                currentUsername,
                                ignoreCase = true
                            ) == true
                        ) {
                            CommentParticipantBadge(role = role)
                        }
                    }
                    if (item.postedAgo.isNotEmpty()) {
                        Text(
                            text = item.postedAgo,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1
                        )
                    }
                }

                if (item.subjectTitle.isNotEmpty()) {
                    val chapter = item.chapterIndicatorTitle
                    if (chapter != null) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier.padding(top = 2.dp)
                        ) {
                            Text(
                                text = "on",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Surface(
                                shape = MaterialTheme.shapes.small,
                                color = MaterialTheme.colorScheme.surfaceContainerHighest
                            ) {
                                Text(
                                    text = chapter,
                                    style = MaterialTheme.typography.labelSmall,
                                    modifier = Modifier.padding(horizontal = 7.dp, vertical = 2.dp)
                                )
                            }
                            Text(
                                text = "of ${item.workTitle}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                    } else {
                        Text(
                            text = "on ${item.subjectTitle}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.padding(top = 2.dp)
                        )
                    }
                }

                if (item.excerpt.isNotEmpty()) {
                    Text(
                        text = item.excerpt,
                        style = MaterialTheme.typography.bodyMedium,
                        maxLines = 3,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(top = 4.dp)
                    )
                }

                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    if (item.isReplied) {
                        InboxRepliedBadge()
                    }
                    Spacer(Modifier.weight(1f))
                    if (!isSelecting) {
                        InboxItemOverflowMenu(
                            item = item,
                            enabled = !isPerformingAction,
                            canMarkRead = canMarkRead,
                            canMarkUnread = canMarkUnread,
                            canDelete = canDelete,
                            onOpen = onOpen,
                            onMarkRead = onMarkRead,
                            onMarkUnread = onMarkUnread,
                            onDelete = onDelete
                        )
                    }
                }
            }
            } // end available item
        }
    }
}

@Composable
private fun InboxRepliedBadge() {
    Surface(
        shape = MaterialTheme.shapes.small,
        color = MaterialTheme.colorScheme.tertiaryContainer,
        contentColor = MaterialTheme.colorScheme.onTertiaryContainer
    ) {
        Text(
            text = "Replied",
            style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold),
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
    onMarkRead: () -> Unit,
    onMarkUnread: () -> Unit,
    onDelete: () -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { expanded = true }, enabled = enabled) {
            Icon(
                Icons.Outlined.MoreVert,
                contentDescription = "More actions for ${item.commenterName}'s inbox comment"
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
                            "Delete From Inbox",
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

@Composable
private fun InboxPaginationControls(
    page: Int,
    totalPages: Int,
    enabled: Boolean,
    onLoadPage: (Int) -> Unit
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        OutlinedButton(
            enabled = enabled && page > 1,
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
            enabled = enabled && page < totalPages,
            onClick = { onLoadPage(page + 1) },
            modifier = Modifier.weight(1f)
        ) {
            Text("Next")
        }
    }
}
