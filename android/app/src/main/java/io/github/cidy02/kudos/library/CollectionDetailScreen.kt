package io.github.cidy02.kudos.library

import androidx.compose.ui.semantics.Role
import androidx.compose.foundation.selection.toggleable
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.CollectionsBookmark
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.SwapVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.fragment.app.FragmentActivity
import io.github.cidy02.kudos.app.PrivacyGate
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.core.model.PrivacySettings
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.core.strippingHtml
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.ui.components.DestructiveConfirmation
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.components.coverHue
import io.github.cidy02.kudos.ui.subject.FilterButton
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectKicker
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.SwipeAction
import io.github.cidy02.kudos.ui.subject.SwipeActionRow
import io.github.cidy02.kudos.ui.subject.ToolbarAddButton
import io.github.cidy02.kudos.ui.subject.ToolbarCircleButton
import io.github.cidy02.kudos.ui.components.SensitiveWorkRow
import io.github.cidy02.kudos.ui.subject.WorkSelectionBubble
import io.github.cidy02.kudos.ui.subject.defaultWorkSignals
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import io.github.cidy02.kudos.works.DownloadQueue
import io.github.cidy02.kudos.works.WorkMetadataRefresh
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.works.WorkTags
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

enum class CollectionDisplayMode {
    Detailed,
    Ledger
}

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun CollectionDetailScreen(
    collectionId: String,
    workRepository: WorkRepository,
    settingsRepository: SettingsRepository? = null,
    privacyGate: PrivacyGate = PrivacyGate(),
    downloadQueue: DownloadQueue? = null,
    metadataRefresh: WorkMetadataRefresh? = null,
    onOpenWork: (String) -> Unit,
    onOpenReader: (String) -> Unit,
    onCollectionDeleted: () -> Unit
) {
    val privacy by (settingsRepository?.settings?.map { it.privacy }
        ?: flowOf(PrivacySettings()))
        .collectAsState(initial = PrivacySettings())
    val reveal by privacyGate.state.collectAsState()
    val confirmBeforeDelete by (settingsRepository?.settings?.map { it.app.confirmBeforeDelete }
        ?: flowOf(true))
        .collectAsState(initial = true)

    val tokens = LocalKudosTokens.current
    var loading by remember(collectionId) { mutableStateOf(true) }
    var working by remember(collectionId) { mutableStateOf(false) }
    var error by remember(collectionId) { mutableStateOf<String?>(null) }
    var collection by remember(collectionId) { mutableStateOf<WorkCollection?>(null) }
    var works by remember(collectionId) { mutableStateOf<List<SavedWork>>(emptyList()) }
    var displayMode by rememberSaveable(collectionId) { mutableStateOf(CollectionDisplayMode.Detailed) }
    var isSelecting by remember(collectionId) { mutableStateOf(false) }
    var selectedIds by remember(collectionId) { mutableStateOf<Set<String>>(emptySet()) }
    var menuOpen by remember { mutableStateOf(false) }
    var showRename by remember(collectionId) { mutableStateOf(false) }
    var renameText by remember(collectionId) { mutableStateOf("") }
    var showDetails by remember(collectionId) { mutableStateOf(false) }
    var showReorder by remember(collectionId) { mutableStateOf(false) }
    var showAddPicker by remember(collectionId) { mutableStateOf(false) }
    var confirmDeleteCollection by remember(collectionId) { mutableStateOf(false) }
    var pendingRemoveWork by remember(collectionId) { mutableStateOf<SavedWork?>(null) }
    var confirmBulkRemove by remember(collectionId) { mutableStateOf(false) }
    var filterText by remember(collectionId) { mutableStateOf("") }
    var showFilterDialog by remember(collectionId) { mutableStateOf(false) }

    val scope = rememberCoroutineScope()
    val activity = LocalContext.current as? FragmentActivity

    val palette = remember(collection?.hue, collection?.colorHex, collection?.name, tokens.theme) {
        val col = collection
        if (col != null) {
            collectionDraftPalette(col.name, col.hue, col.colorHex, tokens.theme)
        } else {
            tokens.scopePalette
        }
    }

    suspend fun refresh() {
        loading = true
        error = null
        try {
            collection = workRepository.getCollection(collectionId)
            works = if (collection != null) {
                workRepository.worksForCollection(collectionId)
            } else {
                emptyList()
            }
            if (collection == null) {
                error = "This collection no longer exists."
            }
        } catch (e: Exception) {
            error = e.message ?: "Could not load collection."
        } finally {
            loading = false
        }
    }

    LaunchedEffect(collectionId) { refresh() }

    val orderedWorks = remember(collection?.workOrderRaw, works) {
        val col = collection
        if (col != null) {
            HomeFacts.inReadingOrder(
                col.workOrderRaw,
                works,
                { it.id },
                { it.dateAdded }
            )
        } else {
            works
        }
    }

    val visibleWorks = remember(orderedWorks, filterText, privacy, reveal) {
        val base = orderedWorks.filter { work ->
            LibraryPrivacy.visibility(work, privacy, reveal) != LibraryPrivacyVisibility.Hidden
        }
        if (filterText.isBlank()) base
        else base.filter {
            it.title.contains(filterText, ignoreCase = true) ||
                it.author.contains(filterText, ignoreCase = true) ||
                it.workFandoms.any { fandom -> fandom.contains(filterText, ignoreCase = true) }
        }
    }

    // Remove acts on what the filter still shows (audit A12-5, the same fault on iOS).
    val visibleIds = remember(visibleWorks) { visibleWorks.mapTo(linkedSetOf()) { it.id } }
    LaunchedEffect(visibleIds, selectedIds) {
        val seen = LibrarySelection.visible(selectedIds, visibleIds)
        if (seen.size != selectedIds.size) selectedIds = seen
    }

    val tallyLine = remember(works.size, collection?.keepsWorksOffline) {
        val count = works.size
        val base = "$count ${if (count == 1) "work" else "works"}"
        if (collection?.keepsWorksOffline == true) "$base · kept offline" else base
    }

    fun addWorks(workIds: Set<String>) {
        scope.launch {
            working = true
            error = null
            try {
                workIds.forEach { workRepository.addWorkToCollection(it, collectionId) }
                val current = collection
                if (current?.keepsWorksOffline == true && downloadQueue != null) {
                    for (id in workIds) {
                        val work = workRepository.getWork(id) ?: continue
                        if (!work.hasEpub) {
                            val ao3Id = WorkTags.ao3WorkIdFromUrl(work.sourceUrl)
                            if (ao3Id != null) {
                                downloadQueue.enqueueLocal(ao3Id, work.title, work.sourceUrl, force = false)
                            }
                        }
                    }
                }
                refresh()
            } catch (e: Exception) {
                error = e.message ?: "Could not add works."
            } finally {
                working = false
            }
        }
    }

    fun removeWork(workId: String) {
        scope.launch {
            working = true
            error = null
            try {
                workRepository.removeFromCollection(workId, collectionId)
                refresh()
            } catch (e: Exception) {
                error = e.message ?: "Could not remove work."
            } finally {
                working = false
            }
        }
    }

    fun bulkRemove(ids: Set<String>) {
        scope.launch {
            working = true
            error = null
            try {
                ids.forEach { workRepository.removeFromCollection(it, collectionId) }
                isSelecting = false
                selectedIds = emptySet()
                refresh()
            } catch (e: Exception) {
                error = e.message ?: "Could not remove works."
            } finally {
                working = false
            }
        }
    }

    fun renameCollection() {
        val name = renameText.trim()
        if (name.isEmpty() || working) return
        scope.launch {
            working = true
            error = null
            try {
                val updated = workRepository.renameCollection(collectionId, name)
                if (updated != null) {
                    collection = updated
                    showRename = false
                } else {
                    error = "Could not rename collection."
                }
            } catch (e: Exception) {
                error = e.message ?: "Could not rename collection."
            } finally {
                working = false
            }
        }
    }

    fun deleteCollection() {
        scope.launch {
            working = true
            error = null
            try {
                workRepository.softDeleteCollection(collectionId)
                confirmDeleteCollection = false
                onCollectionDeleted()
            } catch (e: Exception) {
                error = e.message ?: "Could not delete collection."
                working = false
            }
        }
    }

    BackHandler(enabled = isSelecting) {
        isSelecting = false
        selectedIds = emptySet()
    }

    ProvidePushedShellChrome(
        hasSubjectHeader = true,
        hideTabBar = isSelecting,
        customTitle = if (isSelecting) "${selectedIds.size} selected" else null,
        onBack = if (isSelecting) {
            {
                isSelecting = false
                selectedIds = emptySet()
            }
        } else null,
        trailingContent = {
            if (isSelecting) {
                val allSelected = visibleWorks.isNotEmpty() && visibleWorks.all { it.id in selectedIds }
                TextButton(
                    onClick = {
                        selectedIds = if (allSelected) emptySet() else visibleWorks.map { it.id }.toSet()
                    }
                ) {
                    Text(
                        if (allSelected) "Deselect All" else "Select All",
                        color = palette.accent
                    )
                }
                IconButton(
                    onClick = {
                        isSelecting = false
                        selectedIds = emptySet()
                    }
                ) {
                    Icon(Icons.Filled.Check, contentDescription = "Done", tint = palette.accent)
                }
            } else {
                ToolbarAddButton(
                    onClick = { showAddPicker = true },
                    accessibilityName = "Add Works",
                    palette = palette
                )
                if (works.isNotEmpty()) {
                    FilterButton(
                        filtersActive = filterText.isNotBlank(),
                        badgeCount = if (filterText.isNotBlank()) 1 else 0,
                        onClick = { showFilterDialog = true },
                        onClearFilters = { filterText = "" }
                    )
                }
                Box {
                    ToolbarCircleButton(
                        onClick = { menuOpen = true },
                        accessibilityName = "More"
                    ) {
                        Icon(Icons.Filled.MoreVert, contentDescription = null)
                    }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        if (privacy.hideMatureContent) {
                            DropdownMenuItem(
                                text = { Text(if (reveal.revealAll) "Hide mature" else "Show mature") },
                                leadingIcon = {
                                    Icon(
                                        if (reveal.revealAll) Icons.Filled.VisibilityOff else Icons.Filled.Visibility,
                                        contentDescription = null
                                    )
                                },
                                onClick = {
                                    menuOpen = false
                                    privacyGate.toggleRevealAll(activity)
                                }
                            )
                        }
                        if (works.isNotEmpty()) {
                            DropdownMenuItem(
                                text = { Text("Select") },
                                leadingIcon = { Icon(Icons.Outlined.Checklist, contentDescription = null) },
                                onClick = {
                                    menuOpen = false
                                    isSelecting = true
                                }
                            )
                            if (works.size > 1) {
                                val canReorder = filterText.isBlank()
                                DropdownMenuItem(
                                    text = { Text(if (canReorder) "Reorder" else "Clear Filters to Reorder") },
                                    leadingIcon = { Icon(Icons.Outlined.SwapVert, contentDescription = null) },
                                    enabled = canReorder,
                                    onClick = {
                                        menuOpen = false
                                        showReorder = true
                                    }
                                )
                            }
                            DropdownMenuItem(
                                text = {
                                    Text(if (displayMode == CollectionDisplayMode.Ledger) "Display · Detailed" else "Display · Ledger")
                                },
                                onClick = {
                                    menuOpen = false
                                    displayMode = if (displayMode == CollectionDisplayMode.Ledger) {
                                        CollectionDisplayMode.Detailed
                                    } else {
                                        CollectionDisplayMode.Ledger
                                    }
                                }
                            )
                            HorizontalDivider()
                        }
                        DropdownMenuItem(
                            text = { Text("Rename") },
                            leadingIcon = { Icon(Icons.Outlined.Edit, contentDescription = null) },
                            onClick = {
                                menuOpen = false
                                renameText = collection?.name.orEmpty()
                                showRename = true
                            }
                        )
                        DropdownMenuItem(
                            text = { Text("Details") },
                            onClick = {
                                menuOpen = false
                                showDetails = true
                            }
                        )
                        HorizontalDivider()
                        DropdownMenuItem(
                            text = { Text("Delete Collection", color = MaterialTheme.colorScheme.error) },
                            leadingIcon = {
                                Icon(Icons.Outlined.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                            },
                            onClick = {
                                menuOpen = false
                                confirmDeleteCollection = true
                            }
                        )
                    }
                }
            }
        }
    )

    DestructiveConfirmation(
        show = confirmDeleteCollection,
        title = "Delete “${collection?.name}”?",
        text = "Kudos will move this collection to Recently Deleted for 90 days. Its works will stay in your Library.",
        confirmText = "Delete",
        confirmBeforeDelete = confirmBeforeDelete,
        onConfirm = { deleteCollection() },
        onDismissRequest = { confirmDeleteCollection = false }
    )

    DestructiveConfirmation(
        show = pendingRemoveWork != null,
        title = "Remove this work?",
        text = "“${pendingRemoveWork?.title}” will no longer be in “${collection?.name}”. The work itself stays in your Library.",
        confirmText = "Remove",
        confirmBeforeDelete = confirmBeforeDelete,
        onConfirm = {
            val workId = pendingRemoveWork?.id ?: return@DestructiveConfirmation
            pendingRemoveWork = null
            removeWork(workId)
        },
        onDismissRequest = { pendingRemoveWork = null }
    )

    DestructiveConfirmation(
        show = confirmBulkRemove,
        title = if (selectedIds.size == 1) "Remove 1 work?" else "Remove ${selectedIds.size} works?",
        text = "Kudos will remove the selected works from this collection. They will stay in your Library.",
        confirmText = "Remove",
        confirmBeforeDelete = confirmBeforeDelete,
        onConfirm = {
            confirmBulkRemove = false
            bulkRemove(selectedIds)
        },
        onDismissRequest = { confirmBulkRemove = false }
    )

    if (showRename) {
        AlertDialog(
            onDismissRequest = {
                if (!working) {
                    showRename = false
                    renameText = ""
                }
            },
            title = { Text("Rename Collection") },
            text = {
                OutlinedTextField(
                    value = renameText,
                    onValueChange = { renameText = it },
                    label = { Text("Name") },
                    singleLine = true,
                    enabled = !working,
                    modifier = Modifier.fillMaxWidth()
                )
            },
            confirmButton = {
                TextButton(
                    enabled = !working && renameText.trim().isNotEmpty(),
                    onClick = { renameCollection() }
                ) {
                    Text("Save")
                }
            },
            dismissButton = {
                TextButton(
                    enabled = !working,
                    onClick = {
                        showRename = false
                        renameText = ""
                    }
                ) {
                    Text("Cancel")
                }
            }
        )
    }

    if (showFilterDialog) {
        AlertDialog(
            onDismissRequest = { showFilterDialog = false },
            title = { Text("Filter Collection") },
            text = {
                OutlinedTextField(
                    value = filterText,
                    onValueChange = { filterText = it },
                    label = { Text("Title, author, or fandom") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            },
            confirmButton = {
                TextButton(onClick = { showFilterDialog = false }) { Text("Done") }
            },
            dismissButton = {
                if (filterText.isNotBlank()) {
                    TextButton(onClick = { filterText = ""; showFilterDialog = false }) {
                        Text("Clear")
                    }
                }
            }
        )
    }

    if (showDetails && collection != null) {
        CollectionEditorSheet(
            workRepository = workRepository,
            existing = collection,
            downloadQueue = downloadQueue,
            onDismiss = { showDetails = false },
            onSaved = { updated ->
                collection = updated
                showDetails = false
                scope.launch { refresh() }
            }
        )
    }

    if (showReorder && collection != null) {
        CollectionReorderSheet(
            collection = collection!!,
            works = works,
            workRepository = workRepository,
            onDismiss = { showReorder = false },
            onSaved = {
                showReorder = false
                scope.launch { refresh() }
            }
        )
    }

    if (showAddPicker) {
        val allSavedWorks by workRepository.observeSavedWorks().collectAsState(initial = emptyList())
        val currentWorkIds = works.map { it.id }.toSet()
        val availableToAdd = allSavedWorks.filter { it.id !in currentWorkIds }

        AddWorksToCollectionDialog(
            availableWorks = availableToAdd,
            onDismiss = { showAddPicker = false },
            onAdd = { selected ->
                showAddPicker = false
                addWorks(selected)
            }
        )
    }

    Box(
        Modifier
            .fillMaxSize()
            .subjectScreenWash(palette)
    ) {
        KudosRefreshBox(
            onRefresh = {
                refresh()
                metadataRefresh?.let { ref ->
                    works.forEach { runCatching { ref.refresh(it) } }
                    refresh()
                }
            },
            modifier = Modifier.fillMaxSize()
        ) {
            val topInset = WindowInsets.systemBars.asPaddingValues().calculateTopPadding()

            when {
                loading && collection == null -> {
                    Box(
                        Modifier
                            .fillMaxSize()
                            .padding(top = topInset + 56.dp)
                    ) {
                        LoadingStateCard("Loading collection", Modifier.padding(16.dp))
                    }
                }
                error != null && collection == null -> {
                    Box(
                        Modifier
                            .fillMaxSize()
                            .padding(top = topInset + 56.dp)
                    ) {
                        ErrorStateCard("Collection unavailable", error.orEmpty(), Modifier.padding(16.dp))
                    }
                }
                works.isEmpty() -> {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(top = topInset + 56.dp, bottom = 16.dp)
                    ) {
                        item {
                            SubjectHeaderBlock(
                                kicker = "Library",
                                title = collection?.name ?: "Collection",
                                subtitle = tallyLine,
                                palette = palette,
                                modifier = Modifier.padding(bottom = 24.dp)
                            )
                        }
                        item {
                            EmptyStateCard(
                                title = collection?.name ?: "Collection",
                                message = "Add works from your Library here, or choose Add to Collection on a work's page.",
                                primaryActionLabel = "Add Works",
                                onPrimaryAction = { showAddPicker = true },
                                modifier = Modifier.padding(horizontal = 16.dp)
                            )
                        }
                    }
                }
                else -> {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(
                            top = topInset + 56.dp,
                            bottom = if (isSelecting) 96.dp else 24.dp
                        ),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        item {
                            SubjectHeaderBlock(
                                kicker = "Library",
                                title = collection?.name ?: "Collection",
                                subtitle = tallyLine,
                                palette = palette
                            )
                        }
                        item {
                            SectionRuleHeader(
                                title = "Works",
                                count = visibleWorks.size,
                                modifier = Modifier.padding(top = 4.dp, bottom = 2.dp)
                            )
                        }
                        if (visibleWorks.isEmpty() && filterText.isNotBlank()) {
                            item {
                                EmptyStateCard(
                                    title = "No matching works",
                                    message = "Your filters don't match any works in this collection.",
                                    primaryActionLabel = "Clear Filters",
                                    onPrimaryAction = { filterText = "" },
                                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                                )
                            }
                        } else {
                            items(visibleWorks, key = { it.id }) { work ->
                                CollectionWorkListItem(
                                    work = work,
                                    collection = collection!!,
                                    displayMode = displayMode,
                                    isSelecting = isSelecting,
                                    isSelected = work.id in selectedIds,
                                    obscured = LibraryPrivacy.visibility(work, privacy, reveal) ==
                                        LibraryPrivacyVisibility.Obscured,
                                    palette = palette,
                                    onToggleSelection = {
                                        selectedIds = if (work.id in selectedIds) {
                                            selectedIds - work.id
                                        } else {
                                            selectedIds + work.id
                                        }
                                    },
                                    onOpenWork = { onOpenWork(work.id) },
                                    onOpenReader = {
                                        if (work.hasEpub) onOpenReader(work.id) else onOpenWork(work.id)
                                    },
                                    onReveal = { privacyGate.reveal(work.id, activity) },
                                    onRemove = {
                                        if (confirmBeforeDelete) {
                                            pendingRemoveWork = work
                                        } else {
                                            removeWork(work.id)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }

        if (isSelecting) {
            Surface(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .navigationBarsPadding(),
                color = tokens.glassFill(0.85),
                tonalElevation = 8.dp,
                shadowElevation = 8.dp
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    TextButton(
                        onClick = { confirmBulkRemove = true },
                        enabled = selectedIds.isNotEmpty()
                    ) {
                        Text(
                            "Remove from Collection",
                            color = if (selectedIds.isNotEmpty()) MaterialTheme.colorScheme.error else tokens.tertiaryInk,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                    IconButton(
                        onClick = {
                            isSelecting = false
                            selectedIds = emptySet()
                        }
                    ) {
                        Icon(
                            Icons.Filled.Check,
                            contentDescription = "Done",
                            tint = palette.accent
                        )
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun CollectionWorkListItem(
    work: SavedWork,
    collection: WorkCollection,
    displayMode: CollectionDisplayMode,
    isSelecting: Boolean,
    isSelected: Boolean,
    obscured: Boolean,
    palette: SubjectPalette,
    onToggleSelection: () -> Unit,
    onOpenWork: () -> Unit,
    onOpenReader: () -> Unit,
    onReveal: () -> Unit,
    onRemove: () -> Unit
) {
    var menuOpen by remember(work.id) { mutableStateOf(false) }

    val rowContent = @Composable {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            if (isSelecting) {
                WorkSelectionBubble(
                    isSelected = isSelected,
                    palette = palette
                )
            }
            Box(Modifier.weight(1f)) {
                if (displayMode == CollectionDisplayMode.Ledger) {
                    val progress = work.readingProgressFraction() ?: 0.0
                    SensitiveWorkRow(
                        work = work,
                        onOpenWork = { 
                            if (work.hasEpub) onOpenReader() else onOpenWork()
                        },
                        selected = isSelecting && isSelected,
                        selecting = isSelecting,
                        obscured = obscured,
                        onReveal = onReveal,
                        onSelect = onToggleSelection,
                        onLongClick = {
                            if (!isSelecting) menuOpen = true
                        },
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)
                    )
                } else {
                    DetailedCollectionWorkCard(
                        work = work,
                        obscured = obscured,
                        selected = isSelecting && isSelected,
                        onClick = {
                            when {
                                isSelecting -> onToggleSelection()
                                obscured -> onReveal()
                                work.hasEpub -> onOpenReader()
                                else -> onOpenWork()
                            }
                        },
                        onLongClick = {
                            if (!isSelecting) menuOpen = true
                        }
                    )
                }
            }
        }
    }

    if (isSelecting) {
        rowContent()
    } else {
        SwipeActionRow(
            leading = emptyList(),
            trailing = listOf(
                SwipeAction(
                    label = "Remove",
                    icon = Icons.Outlined.Delete,
                    color = MaterialTheme.colorScheme.error,
                    onClick = onRemove
                )
            ),
            content = rowContent
        )
    }

    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
        DropdownMenuItem(
            text = { Text("Open Work") },
            onClick = {
                menuOpen = false
                onOpenWork()
            }
        )
        if (work.hasEpub) {
            DropdownMenuItem(
                text = { Text("Read") },
                onClick = {
                    menuOpen = false
                    onOpenReader()
                }
            )
        }
        HorizontalDivider()
        DropdownMenuItem(
            text = { Text("Remove from Collection", color = MaterialTheme.colorScheme.error) },
            leadingIcon = {
                Icon(Icons.Outlined.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error)
            },
            onClick = {
                menuOpen = false
                onRemove()
            }
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun DetailedCollectionWorkCard(
    work: SavedWork,
    obscured: Boolean,
    selected: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val subject = work.workFandoms.firstOrNull { it.isNotBlank() } ?: work.title
    val palette = remember(subject, tokens.theme) {
        SubjectPalette.fromHue(coverHue(subject).toDouble() / 360.0, tokens.theme)
    }
    val shape = RoundedCornerShape(16.dp)

    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(palette.cardWash)
            .border(
                if (selected) 2.dp else 0.5.dp,
                if (selected) tokens.accent else palette.cardBorder,
                shape
            )
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        val primaryFandom = HomeFacts.primaryFandom(work.workFandoms)
        if (primaryFandom != null) {
            SubjectKicker(
                text = primaryFandom,
                palette = palette,
                trailingCount = (work.workFandoms.count { it.isNotBlank() } - 1).coerceAtLeast(0),
                size = 9.sp,
                ruleSpacing = 4.dp
            )
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = if (obscured) "Hidden mature work" else work.title.ifBlank { "Untitled work" },
                color = tokens.primaryInk,
                fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false)
            )
            if (work.isFavorite) {
                Text("★", color = Color(0xFFFFC107), fontSize = 14.sp)
            }
        }

        if (!obscured && work.author.isNotBlank()) {
            Text(
                text = "by ${work.author}",
                color = tokens.secondaryInk,
                fontSize = 13.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }

        if (obscured) {
            Text(
                text = "Tap to reveal",
                color = tokens.secondaryInk,
                fontSize = 13.sp
            )
        } else if (work.summary.isNotBlank()) {
            Text(
                text = work.summary.strippingHtml(),
                color = tokens.secondaryInk,
                fontSize = 13.sp,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis
            )
        }

        val metadataLine = HomeFacts.localWorkMetadata(work.author, work.wordCount, work.chapters).joinToString(" · ")
        if (metadataLine.isNotBlank()) {
            Text(
                text = metadataLine,
                color = tokens.tertiaryInk,
                fontSize = 11.5.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun AddWorksToCollectionDialog(
    availableWorks: List<SavedWork>,
    onDismiss: () -> Unit,
    onAdd: (Set<String>) -> Unit
) {
    var searchQuery by remember { mutableStateOf("") }
    val selectedIds = remember { mutableStateMapOf<String, Boolean>() }
    val filteredWorks = remember(availableWorks, searchQuery) {
        if (searchQuery.isBlank()) availableWorks
        else availableWorks.filter {
            it.title.contains(searchQuery, ignoreCase = true) ||
                it.author.contains(searchQuery, ignoreCase = true)
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text("Add Works to Collection", style = MaterialTheme.typography.titleLarge)

            OutlinedTextField(
                value = searchQuery,
                onValueChange = { searchQuery = it },
                label = { Text("Search your Library") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )

            LazyColumn(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 400.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                if (filteredWorks.isEmpty()) {
                    item {
                        Text(
                            if (availableWorks.isEmpty()) "No other works in Library to add."
                            else "No matches in Library.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(vertical = 16.dp)
                        )
                    }
                } else {
                    items(filteredWorks, key = { it.id }) { work ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                // One control with a state TalkBack can say (audit A13).
                                .toggleable(value = selectedIds[work.id] ?: false, role = Role.Checkbox) {
                                    selectedIds[work.id] = it
                                }
                                .padding(vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            Checkbox(
                                checked = selectedIds[work.id] ?: false,
                                onCheckedChange = null
                            )
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    work.title,
                                    style = MaterialTheme.typography.bodyLarge,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                                Text(
                                    work.author,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                OutlinedButton(onClick = onDismiss, modifier = Modifier.weight(1f)) {
                    Text("Cancel")
                }
                androidx.compose.material3.Button(
                    onClick = { onAdd(selectedIds.filterValues { it }.keys) },
                    modifier = Modifier.weight(1f),
                    enabled = selectedIds.any { it.value }
                ) {
                    val count = selectedIds.count { it.value }
                    Text(if (count > 0) "Add $count work${if (count > 1) "s" else ""}" else "Add")
                }
            }
        }
    }
}
