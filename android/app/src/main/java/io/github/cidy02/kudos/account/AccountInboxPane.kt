package io.github.cidy02.kudos.account

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.MarkEmailRead
import androidx.compose.material.icons.outlined.MarkEmailUnread
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
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
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.TextUnit
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentParticipantRole
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentRepository
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentWorkAuthor
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxBulkAction
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxFilterField
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxFilterForm
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxItem
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxRepository
import io.github.cidy02.kudos.ui.components.CommentAvatar
import io.github.cidy02.kudos.ui.components.CommentParticipantBadge
import io.github.cidy02.kudos.ui.components.DestructiveConfirmation
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.subject.FilterButton
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.LocalSubjectPalette
import io.github.cidy02.kudos.ui.subject.SubjectChip
import io.github.cidy02.kudos.ui.subject.SubjectChipStyle
import io.github.cidy02.kudos.ui.subject.SubjectFieldLabel
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.ToolbarCircleButton
import io.github.cidy02.kudos.ui.subject.WorkSelectionBubble
import io.github.cidy02.kudos.ui.subject.subjectPanel
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale
import java.text.NumberFormat

/** Account › Activity › Inbox, drawn with the shared subject-page language. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccountInboxPane(
    inboxRepository: AO3InboxRepository,
    commentRepository: AO3CommentRepository,
    currentUsername: String?,
    onOpenWorkComments: (workId: Long, focusedId: Long?) -> Unit,
    /** iOS's "Chapter Comments": the comments of the chapter an inbox comment was left on. */
    onOpenChapterComments: (workId: Long, commentId: Long, chapterPosition: Int) -> Unit = { _, _, _ -> },
    settingsRepository: SettingsRepository? = null,
    modifier: Modifier = Modifier,
    viewModel: AccountInboxViewModel = viewModel(
        key = "account-inbox",
        factory = AccountInboxViewModel.factory(inboxRepository, commentRepository)
    )
) {
    val state by viewModel.uiState.collectAsState()
    val settingsFlow = settingsRepository?.settings
        ?: kotlinx.coroutines.flow.flowOf(KudosSettings.Defaults)
    val settings by settingsFlow.collectAsState(initial = KudosSettings.Defaults)
    val palette = LocalSubjectPalette.current
    var showingFilters by remember { mutableStateOf(false) }
    var pendingDelete by remember { mutableStateOf<PendingInboxDelete?>(null) }

    ProvidePushedShellChrome(
        hasSubjectHeader = true,
        hideTabBar = state.isSelecting
    )

    DestructiveConfirmation(
        show = pendingDelete != null,
        title = if (pendingDelete?.items?.size == 1) {
            "Delete this notification from your AO3 Inbox?"
        } else {
            "Delete ${pendingDelete?.items?.size ?: 0} notifications from your AO3 Inbox?"
        },
        text = if (pendingDelete?.items?.size == 1) {
            "This removes the notification from your AO3 Inbox. The comment stays on AO3."
        } else {
            "This removes the selected notifications from your AO3 Inbox. " +
                "Your works in Kudos aren't deleted."
        },
        confirmText = "Delete From Inbox",
        confirmBeforeDelete = settings.app.confirmBeforeDelete,
        onConfirm = {
            val pending = pendingDelete ?: return@DestructiveConfirmation
            pendingDelete = null
            if (pending.items.size == 1) {
                viewModel.startItemAction(AO3InboxBulkAction.Delete, pending.items.first())
            } else {
                viewModel.startBulkAction(AO3InboxBulkAction.Delete)
            }
        },
        onDismissRequest = { pendingDelete = null }
    )

    if (showingFilters) {
        AccountInboxFilterSheet(
            fields = state.filterForm?.fields.orEmpty(),
            selectedValues = state.filterValues,
            palette = palette,
            onSelect = { fieldName, value ->
                viewModel.applyFilter(fieldName, value)
                showingFilters = false
            },
            onDismiss = { showingFilters = false }
        )
    }

    if (state.actionError != null &&
        !(state.phase == AccountInboxUiState.Phase.Failed && state.items.isEmpty())
    ) {
        AlertDialog(
            onDismissRequest = viewModel::clearActionError,
            title = { Text("Couldn't update Inbox") },
            text = { Text(state.actionError ?: "AO3 couldn't update your Inbox.") },
            confirmButton = {
                TextButton(onClick = viewModel::clearActionError) { Text("OK") }
            }
        )
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .subjectScreenWash(palette)
    ) {
        // The Inbox is its own route now, with nothing above it: start below the status bar, so
        // the toolbar row sits level with the shell's back button and the header below both.
        val topInset = androidx.compose.foundation.layout.WindowInsets.statusBars
            .asPaddingValues().calculateTopPadding()
        LazyColumn(
            contentPadding = PaddingValues(
                start = SubjectMetrics.accountGutter,
                end = SubjectMetrics.accountGutter,
                top = topInset,
                bottom = if (state.isSelecting) 92.dp else 24.dp
            ),
            modifier = Modifier.fillMaxSize()
        ) {
            item {
                InboxToolbar(
                    state = state,
                    palette = palette,
                    onBeginSelection = viewModel::beginSelection,
                    onToggleSelectAll = viewModel::toggleSelectAllCurrentPage,
                    onShowFilters = { showingFilters = true }
                )
            }

            item {
                SubjectHeaderBlock(
                    kicker = "AO3 Account",
                    title = "Inbox",
                    subtitle = inboxTally(state),
                    palette = palette,
                    gutter = 0.dp,
                    modifier = Modifier.padding(top = 12.dp, bottom = 4.dp)
                )
            }

            val pills = InboxQuickFilter.available(state.filterForm)
            if (pills.isNotEmpty()) {
                item {
                    InboxPillRail(
                        pills = pills,
                        selected = InboxQuickFilter.selected(state.filterValues),
                        enabled = !state.isPerformingBulkAction &&
                            state.phase != AccountInboxUiState.Phase.Loading,
                        palette = palette,
                        onFilter = viewModel::applyFilters
                    )
                }
            }

            state.actionNotice?.let { message ->
                item {
                    Surface(
                        color = LocalKudosTokens.current.glassFill(0.09),
                        shape = RoundedCornerShape(SubjectMetrics.panelRadius),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 12.dp)
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = message,
                                color = LocalKudosTokens.current.primaryInk,
                                fontSize = 14.sp,
                                modifier = Modifier.weight(1f)
                            )
                            TextButton(onClick = viewModel::clearActionNotice) { Text("OK") }
                        }
                    }
                }
            }

            when {
                state.phase == AccountInboxUiState.Phase.Loading && state.items.isEmpty() -> {
                    item {
                        Box(Modifier.padding(top = 16.dp)) {
                            LoadingStateCard("Loading Inbox")
                        }
                    }
                }
                state.phase == AccountInboxUiState.Phase.Failed && state.items.isEmpty() -> {
                    item {
                        Box(Modifier.padding(top = 16.dp)) {
                            ErrorStateCard(
                                title = "Couldn't load your inbox",
                                message = state.actionError ?: "Something went wrong.",
                                primaryActionLabel = "Try Again",
                                onPrimaryAction = viewModel::retry
                            )
                        }
                    }
                }
                state.phase == AccountInboxUiState.Phase.Loaded && state.items.isEmpty() -> {
                    item {
                        Box(Modifier.padding(top = 16.dp)) {
                            EmptyStateCard(
                                title = "No comments yet",
                                message = "Comments on your works and replies to your comments " +
                                    "appear here from your AO3 inbox."
                            )
                        }
                    }
                }
                else -> {
                    item { Spacer(Modifier.height(12.dp)) }
                    itemsIndexed(state.items, key = { _, item -> item.id }) { index, item ->
                        val authors = state.workAuthorsById[item.workId].orEmpty()
                        InboxItemCard(
                            item = item,
                            workAuthors = authors,
                            currentUsername = currentUsername,
                            isSelecting = state.isSelecting,
                            isSelected = item.id in state.selectedItemIds,
                            isSelectable = item.id in state.selectableItemIds,
                            isFirst = index == 0,
                            isLast = index == state.items.lastIndex,
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
                            onOpenChapter = item.workId?.let { workId ->
                                item.chapterPosition?.let { position -> { onOpenChapterComments(workId, item.id, position) } }
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
                    item { Spacer(Modifier.height(12.dp)) }

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

        if (state.isSelecting) {
            InboxBulkActionBar(
                enabled = state.selectedItems.isNotEmpty() && !state.isPerformingBulkAction,
                onEndSelection = viewModel::endSelection,
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
                },
                modifier = Modifier.align(Alignment.BottomCenter)
            )
        }
    }
}

private data class PendingInboxDelete(val items: List<AO3InboxItem>)

private enum class InboxQuickFilter(
    val title: String,
    val values: Map<String, String>
) {
    All(
        "All",
        mapOf("filters[read]" to "all", "filters[replied_to]" to "all")
    ),
    Unread(
        "Unread",
        mapOf("filters[read]" to "false", "filters[replied_to]" to "all")
    ),
    AwaitingReply(
        "Awaiting reply",
        mapOf("filters[read]" to "all", "filters[replied_to]" to "false")
    ),
    Replied(
        "Replied",
        mapOf("filters[read]" to "all", "filters[replied_to]" to "true")
    );

    companion object {
        fun available(form: AO3InboxFilterForm?): List<InboxQuickFilter> {
            if (form == null) return emptyList()
            return entries.filter { pill ->
                pill.values.all { (name, value) ->
                    form.fields.firstOrNull { it.name == name }
                        ?.options
                        ?.any { it.value == value } == true
                }
            }
        }

        fun selected(values: Map<String, String>): InboxQuickFilter? =
            entries.firstOrNull { pill ->
                pill.values.all { (name, value) -> values[name] == value }
            }
    }
}

@Composable
private fun InboxToolbar(
    state: AccountInboxUiState,
    palette: SubjectPalette,
    onBeginSelection: () -> Unit,
    onToggleSelectAll: () -> Unit,
    onShowFilters: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 6.dp),
        horizontalArrangement = Arrangement.End,
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (state.isSelecting) {
            TextButton(
                onClick = onToggleSelectAll,
                enabled = !state.isPerformingBulkAction && state.selectableItemIds.isNotEmpty()
            ) {
                Text(if (state.allCurrentPageSelected) "Deselect All" else "Select All")
            }
            Spacer(Modifier.weight(1f))
            Text(
                text = "${state.selectedItems.size} selected",
                color = LocalKudosTokens.current.secondaryInk,
                fontSize = 13.sp
            )
        } else {
            if (state.canFilter) {
                FilterButton(
                    filtersActive = InboxQuickFilter.selected(state.filterValues) !=
                        InboxQuickFilter.All,
                    onClick = {
                        if (!state.isPerformingBulkAction) onShowFilters()
                    },
                    badgeCount = activeFilterCount(state)
                )
            }
            if (state.canSelectItems) {
                Spacer(Modifier.width(4.dp))
                InboxMoreMenu(
                    enabled = !state.isPerformingBulkAction,
                    palette = palette,
                    onBeginSelection = onBeginSelection
                )
            }
        }
    }
}

@Composable
private fun InboxMoreMenu(
    enabled: Boolean,
    palette: SubjectPalette,
    onBeginSelection: () -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        ToolbarCircleButton(
            onClick = { if (enabled) expanded = true },
            accessibilityName = "Select Inbox Items",
            palette = palette
        ) {
            Icon(Icons.Outlined.MoreVert, contentDescription = null)
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(
                text = { Text("Select") },
                onClick = {
                    expanded = false
                    onBeginSelection()
                }
            )
        }
    }
}

@Composable
private fun InboxPillRail(
    pills: List<InboxQuickFilter>,
    selected: InboxQuickFilter?,
    enabled: Boolean,
    palette: SubjectPalette,
    onFilter: (Map<String, String>) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(top = 12.dp, bottom = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        pills.forEach { pill ->
            SubjectChip(
                text = pill.title,
                style = SubjectChipStyle.Pill(selected == pill),
                palette = palette,
                modifier = Modifier.clickable(enabled = enabled) { onFilter(pill.values) }
            )
        }
    }
}

@Composable
private fun InboxBulkActionBar(
    enabled: Boolean,
    onEndSelection: () -> Unit,
    onBulkMarkRead: () -> Unit,
    onBulkMarkUnread: () -> Unit,
    onBulkDelete: () -> Unit,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    Surface(
        color = tokens.theme.cardBackdrop,
        shadowElevation = 8.dp,
        modifier = modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            TextButton(onClick = onBulkDelete, enabled = enabled) {
                Icon(Icons.Outlined.Delete, contentDescription = null)
                Spacer(Modifier.width(6.dp))
                Text("Delete")
            }
            Spacer(Modifier.weight(1f))
            Surface(
                color = tokens.glassFill(),
                shape = CircleShape
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = onBulkMarkRead, enabled = enabled) {
                        Icon(Icons.Outlined.MarkEmailRead, contentDescription = "Mark Read")
                    }
                    Box(
                        Modifier
                            .width(0.5.dp)
                            .height(22.dp)
                            .background(tokens.separator)
                    )
                    IconButton(onClick = onBulkMarkUnread, enabled = enabled) {
                        Icon(Icons.Outlined.MarkEmailUnread, contentDescription = "Mark Unread")
                    }
                }
            }
            Spacer(Modifier.weight(1f))
            IconButton(onClick = onEndSelection) {
                Icon(Icons.Outlined.Check, contentDescription = "Done")
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AccountInboxFilterSheet(
    fields: List<AO3InboxFilterField>,
    selectedValues: Map<String, String>,
    palette: SubjectPalette,
    onSelect: (String, String) -> Unit,
    onDismiss: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Color.Transparent,
        dragHandle = { BottomSheetDefaults.DragHandle() }
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .subjectScreenWash(palette)
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Spacer(Modifier.size(48.dp))
                Text(
                    text = "Inbox Filters",
                    color = tokens.primaryInk,
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.weight(1f)
                )
                IconButton(onClick = onDismiss) {
                    Icon(Icons.Outlined.Check, contentDescription = "Done")
                }
            }

            LazyColumn(
                contentPadding = PaddingValues(
                    start = SubjectMetrics.accountGutter,
                    top = 16.dp,
                    end = SubjectMetrics.accountGutter,
                    bottom = 40.dp
                ),
                verticalArrangement = Arrangement.spacedBy(24.dp)
            ) {
                itemsIndexed(fields, key = { _, field -> field.name }) { _, field ->
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        SubjectFieldLabel(field.title)
                        Column(Modifier.fillMaxWidth().subjectPanel()) {
                            field.options.forEachIndexed { index, option ->
                                if (index > 0) SubjectRowSeparator()
                                val selected = (selectedValues[field.name]
                                    ?: field.selectedValue) == option.value
                                SubjectFormRow(
                                    label = option.label,
                                    onClick = { onSelect(field.name, option.value) }
                                ) {
                                    if (selected) {
                                        Icon(
                                            Icons.Outlined.Check,
                                            contentDescription = "Selected",
                                            tint = palette.accent,
                                            modifier = Modifier.size(18.dp)
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
internal fun InboxItemCard(
    item: AO3InboxItem,
    workAuthors: List<AO3CommentWorkAuthor>,
    currentUsername: String?,
    isSelecting: Boolean,
    isSelected: Boolean,
    isSelectable: Boolean,
    isFirst: Boolean,
    isLast: Boolean,
    isPerformingAction: Boolean,
    canMarkRead: Boolean,
    canMarkUnread: Boolean,
    canDelete: Boolean,
    onOpen: () -> Unit,
    onOpenChapter: (() -> Unit)? = null,
    onToggleSelection: () -> Unit,
    onMarkRead: () -> Unit,
    onMarkUnread: () -> Unit,
    onDelete: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    val accessibility = isAccessibilityFontScale()
    val role = item.participantRole(
        workAuthors = workAuthors.map { it.displayName },
        workAuthorUsernames = workAuthors.mapNotNull { it.username },
        currentUsername = currentUsername
    )
    val shape = RoundedCornerShape(
        topStart = if (isFirst) SubjectMetrics.panelRadius else 0.dp,
        topEnd = if (isFirst) SubjectMetrics.panelRadius else 0.dp,
        bottomEnd = if (isLast) SubjectMetrics.panelRadius else 0.dp,
        bottomStart = if (isLast) SubjectMetrics.panelRadius else 0.dp
    )
    val clickModifier = when {
        isSelecting -> Modifier.clickable(
            enabled = isSelectable && !isPerformingAction,
            onClick = onToggleSelection
        )
        !item.isUnavailable && item.workId != null -> Modifier.clickable(onClick = onOpen)
        else -> Modifier
    }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(tokens.glassFill(0.09), shape)
            .then(clickModifier)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.Top
        ) {
            if (isSelecting) {
                WorkSelectionBubble(
                    isSelected = isSelected,
                    modifier = Modifier.padding(top = 6.dp)
                )
            }

            if (item.isUnavailable) {
                Box(
                    modifier = Modifier.size(40.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        Icons.Outlined.VisibilityOff,
                        contentDescription = null,
                        tint = tokens.secondaryInk
                    )
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
                    InboxByline(item = item, role = role)

                    if (item.subjectTitle.isNotEmpty()) {
                        InboxSubjectLine(item)
                    }

                    if (item.excerpt.isNotEmpty()) {
                        Text(
                            text = item.excerpt,
                            color = tokens.primaryInk,
                            fontSize = 14.sp,
                            lineHeight = if (accessibility) 20.sp else TextUnit.Unspecified,
                            maxLines = if (accessibility) Int.MAX_VALUE else 3,
                            overflow = TextOverflow.Ellipsis
                        )
                    }

                    if (!isSelecting) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.End
                        ) {
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

        if (!isLast) {
            Box(
                Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .height(0.5.dp)
                    .background(tokens.glassStroke(0.09))
            )
        }
    }
}

@Composable
private fun InboxByline(
    item: AO3InboxItem,
    role: AO3CommentParticipantRole
) {
    val tokens = LocalKudosTokens.current
    if (isAccessibilityFontScale()) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                if (item.isUnread) {
                    Box(
                        Modifier.size(8.dp).clip(CircleShape)
                            .background(LocalSubjectPalette.current.accent)
                    )
                }
                Text(
                    text = item.commenterName,
                    color = tokens.primaryInk,
                    fontSize = 14.sp,
                    lineHeight = 20.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f)
                )
            }
            SubjectChip(
                text = role.label,
                modifier = Modifier.semantics {
                    contentDescription = when (role) {
                        AO3CommentParticipantRole.Me -> "Your comment"
                        AO3CommentParticipantRole.Author -> "Work author"
                        else -> role.label
                    }
                },
                style = if (role == AO3CommentParticipantRole.Me ||
                    role == AO3CommentParticipantRole.Author
                ) SubjectChipStyle.Tinted else SubjectChipStyle.Neutral,
                palette = LocalSubjectPalette.current
            )
            if (item.isReplied) {
                SubjectChip(
                    text = "Replied",
                    style = SubjectChipStyle.Tinted,
                    palette = LocalSubjectPalette.current
                )
            }
            if (item.postedAgo.isNotEmpty()) {
                Text(
                    text = item.postedAgo,
                    color = tokens.tertiaryInk,
                    fontSize = 11.sp,
                    lineHeight = 16.sp
                )
            }
        }
        return
    }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        if (item.isUnread) {
            Box(
                modifier = Modifier
                    .size(8.dp)
                    .clip(CircleShape)
                    .background(LocalSubjectPalette.current.accent)
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
        CommentParticipantBadge(role = role)
        Spacer(Modifier.weight(1f))
        if (item.isReplied) InboxRepliedBadge()
        if (item.postedAgo.isNotEmpty()) {
            Text(
                text = item.postedAgo,
                color = tokens.tertiaryInk,
                fontSize = 11.sp,
                maxLines = 1
            )
        }
    }
}

@Composable
private fun InboxSubjectLine(item: AO3InboxItem) {
    val tokens = LocalKudosTokens.current
    val accessibility = isAccessibilityFontScale()
    val chapter = item.chapterIndicatorTitle
    if (chapter == null) {
        Text(
            text = "on ${item.subjectTitle}",
            color = tokens.secondaryInk,
            fontSize = 12.sp,
            lineHeight = if (accessibility) 17.sp else TextUnit.Unspecified,
            maxLines = if (accessibility) Int.MAX_VALUE else 2,
            overflow = TextOverflow.Ellipsis
        )
        return
    }
    if (accessibility) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("on", color = tokens.secondaryInk, fontSize = 12.sp, lineHeight = 17.sp)
            SubjectChip(text = chapter, palette = LocalSubjectPalette.current)
            Text(
                text = "of ${item.workTitle}",
                color = tokens.secondaryInk,
                fontSize = 12.sp,
                lineHeight = 17.sp
            )
        }
        return
    }
    Row(
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text("on", color = tokens.secondaryInk, fontSize = 12.sp)
        Surface(
            shape = CircleShape,
            color = tokens.glassFill()
        ) {
            Text(
                text = chapter,
                color = tokens.secondaryInk,
                fontSize = 11.sp,
                maxLines = 1,
                modifier = Modifier.padding(horizontal = 7.dp, vertical = 2.dp)
            )
        }
        Text(
            text = "of ${item.workTitle}",
            color = tokens.secondaryInk,
            fontSize = 12.sp,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun InboxRepliedBadge() {
    val green = Color(0xFF34C759)
    Surface(
        shape = CircleShape,
        color = green.copy(alpha = 0.12f),
        contentColor = green
    ) {
        Text(
            text = "Replied",
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
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
    onOpenChapter: (() -> Unit)?,
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
            if (onOpenChapter != null) {
                DropdownMenuItem(
                    text = { Text("Chapter Comments") },
                    onClick = {
                        expanded = false
                        onOpenChapter()
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
                    text = { Text("Delete From Inbox", color = Color(0xFFD32F2F)) },
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
    val tokens = LocalKudosTokens.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .subjectPanel()
            .padding(horizontal = 8.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        TextButton(
            enabled = enabled && page > 1,
            onClick = { onLoadPage(page - 1) },
            modifier = Modifier.weight(1f)
        ) {
            Text("Previous")
        }
        Text(
            text = "Page $page of $totalPages",
            color = tokens.secondaryInk,
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium,
            textAlign = TextAlign.Center,
            modifier = Modifier.weight(1f)
        )
        TextButton(
            enabled = enabled && page < totalPages,
            onClick = { onLoadPage(page + 1) },
            modifier = Modifier.weight(1f)
        ) {
            Text("Next")
        }
    }
}

private fun inboxTally(state: AccountInboxUiState): String? {
    val total = state.totalComments ?: return null
    val formatter = NumberFormat.getIntegerInstance()
    var line = if (total == 1) "1 comment" else "${formatter.format(total)} comments"
    state.unreadCount?.takeIf { it > 0 }?.let {
        line += " · ${formatter.format(it)} unread"
    }
    val awaiting = state.items.count { it.canReply && !it.isReplied }
    if (awaiting > 0) {
        line += " · ${formatter.format(awaiting)} awaiting your reply"
        if (state.totalPages > 1) line += " on this page"
    }
    return line
}

private fun activeFilterCount(state: AccountInboxUiState): Int =
    state.filterForm?.fields.orEmpty().count { field ->
        val selected = state.filterValues[field.name] ?: field.selectedValue
        selected != field.options.firstOrNull()?.value
    }
