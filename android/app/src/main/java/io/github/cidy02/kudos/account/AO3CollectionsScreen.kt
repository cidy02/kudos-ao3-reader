package io.github.cidy02.kudos.account

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.material.icons.Icons
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.network.ao3.account.AO3Collection
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.ui.components.KudosPaginationBar
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectChip
import io.github.cidy02.kudos.ui.subject.SubjectChipStyle
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.ToolbarAddButton
import io.github.cidy02.kudos.ui.subject.FilterButton
import io.github.cidy02.kudos.ui.subject.SubjectKicker
import io.github.cidy02.kudos.ui.subject.subjectPanel
import io.github.cidy02.kudos.ui.subject.subjectScreenWash

import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AO3CollectionsScreen(
    repository: AccountListRepository,
    onLogin: () -> Unit,
    onOpenCollection: (AO3Collection) -> Unit,
    modifier: Modifier = Modifier,
    viewModel: AO3CollectionsViewModel = viewModel(
        factory = AO3CollectionsViewModel.factory(repository)
    )
) {
    val state by viewModel.uiState.collectAsState()
    val filters by viewModel.filters.collectAsState()
    var showingFilters by remember { mutableStateOf(false) }
    val tokens = LocalKudosTokens.current
    val palette = remember(tokens.theme) { SubjectPalette.fromHue(210.0, tokens.theme) }
    DisposableEffect(viewModel) {
        viewModel.onAppear()
        onDispose { viewModel.onDisappear() }
    }
    if (showingFilters) {
        AO3CollectionsFilterPanel(initial = filters, onFinish = {
            viewModel.setFilters(it)
            showingFilters = false
        })
    }
    val loaded = state as? AO3CollectionsUiState.Loaded
    val displayed = if (filters.needsWholeIndex) loaded?.wholeIndex.orEmpty() else loaded?.collections.orEmpty()
    val visible = filters.apply(displayed)
    val showPaging = !filters.needsWholeIndex && (loaded?.totalPages ?: 1) > 1
    val tally = loaded?.takeIf { !filters.needsWholeIndex || it.wholeIndex != null }?.let {
        buildString {
            append("${visible.size} collection${if (visible.size == 1) "" else "s"}")
            if (visible.size != displayed.size) append(" · ${displayed.size} in all")
            if (showPaging) append(" · page ${it.currentPage} of ${it.totalPages}")
            if (filters.needsWholeIndex && it.wholeIndex != null) {
                it.wholeIndexPartialNote?.let { note -> append(" · $note") }
            }
        }
    }
    loaded?.pageError?.let { message ->
        AlertDialog(
            onDismissRequest = viewModel::dismissPageError,
            title = { Text("Couldn't load that page") },
            text = { Text(message) },
            confirmButton = {
                TextButton(onClick = viewModel::dismissPageError) { Text("OK") }
            }
        )
    }

    ProvidePushedShellChrome(
        hasSubjectHeader = true,
        trailingContent = {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ToolbarAddButton(
                    onClick = { /* TODO: New Collection */ },
                    accessibilityName = "New Collection",
                    palette = palette
                )
                if (loaded != null && loaded.pageError == null &&
                    (loaded.collections.isNotEmpty() || loaded.wholeIndex != null)
                ) {
                    FilterButton(
                        filtersActive = filters.hasActiveFilters,
                        onClick = { showingFilters = true },
                        onClearFilters = viewModel::clearFilters
                    )
                }
            }
        }
    )

    Column(modifier = modifier.fillMaxSize().subjectScreenWash(palette)) {
        Spacer(modifier = Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
        Spacer(modifier = Modifier.height(56.dp))
        KudosRefreshBox(onRefresh = viewModel::refresh, modifier = Modifier.weight(1f)) {
            LazyColumn(
                verticalArrangement = Arrangement.spacedBy(12.dp),
                contentPadding = PaddingValues(bottom = 32.dp)
            ) {
                item {
                    SubjectHeaderBlock(
                        kicker = "AO3 Account", title = "Collections", subtitle = tally, palette = palette
                    )
                }
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())
                            .padding(horizontal = SubjectMetrics.headerGutter),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        SubjectChip("Collections", style = SubjectChipStyle.Pill(isSelected = true), palette = palette)
                        SubjectChip("Your items", style = SubjectChipStyle.Pill(isSelected = false), palette = palette)
                    }
                }
                if (filters.hasActiveFilters) {
                    item {
                        Row(
                            Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())
                                .padding(horizontal = SubjectMetrics.headerGutter),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            filters.summaryLabels.forEach { label ->
                                SubjectChip(label, style = SubjectChipStyle.Tinted, palette = palette)
                            }
                        }
                    }
                }
                when (val current = state) {
                    AO3CollectionsUiState.Loading -> item {
                        Box(Modifier.padding(horizontal = SubjectMetrics.headerGutter)) {
                            LoadingStateCard("Loading collections")
                        }
                    }
                    AO3CollectionsUiState.AuthRequired -> item {
                        Box(Modifier.padding(horizontal = SubjectMetrics.headerGutter)) {
                            EmptyStateCard(
                                title = "AO3 session required",
                                message = "Log in to AO3 to see your collections.",
                                primaryActionLabel = "Log In to AO3",
                                onPrimaryAction = onLogin
                            )
                        }
                    }
                    is AO3CollectionsUiState.Failed -> item {
                        Box(Modifier.padding(horizontal = SubjectMetrics.headerGutter)) {
                            ErrorStateCard(
                                title = "Couldn't load collections", message = current.message,
                                primaryActionLabel = "Try Again", onPrimaryAction = viewModel::load
                            )
                        }
                    }
                    is AO3CollectionsUiState.Loaded -> {
                        if (filters.needsWholeIndex && current.wholeIndex == null) {
                            item {
                                Box(Modifier.padding(horizontal = SubjectMetrics.headerGutter)) {
                                    if (current.wholeIndexError != null) {
                                        ErrorStateCard(
                                            title = "Couldn't load all collections", message = current.wholeIndexError,
                                            primaryActionLabel = "Try Again", onPrimaryAction = viewModel::load
                                        )
                                    } else LoadingStateCard("Loading collections")
                                }
                            }
                        } else {
                            if (showPaging) item {
                                KudosPaginationBar(
                                    currentPage = current.currentPage, totalPages = current.totalPages,
                                    onPageChange = viewModel::loadPage,
                                    modifier = Modifier.padding(horizontal = SubjectMetrics.headerGutter)
                                )
                            }
                            if (visible.isEmpty()) item {
                                Column(
                                    Modifier.fillMaxWidth().padding(horizontal = SubjectMetrics.headerGutter)
                                        .subjectPanel().padding(16.dp)
                                ) {
                                    Text(
                                        if (displayed.isEmpty()) "No collections" else "No collections match",
                                        style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold
                                    )
                                    Spacer(Modifier.height(4.dp))
                                    Text(
                                        if (displayed.isEmpty()) "Collections you create or maintain on AO3 show up here."
                                        else "${displayed.size} collection${if (displayed.size == 1) "" else "s"} are hidden by the current filters.",
                                        color = tokens.secondaryInk, fontSize = 14.sp
                                    )
                                    if (displayed.isNotEmpty()) {
                                        TextButton(onClick = viewModel::clearFilters) { Text("Clear Filters") }
                                    }
                                }
                            } else {
                                // AO3's demo can repeat a slug on several pages; preserve every incoming row.
                                items(visible) { collection ->
                                    AO3CollectionCard(
                                        collection, onClick = { onOpenCollection(collection) }, palette = palette,
                                        modifier = Modifier.padding(horizontal = SubjectMetrics.headerGutter)
                                    )
                                }
                            }
                            if (showPaging) item {
                                KudosPaginationBar(
                                    currentPage = current.currentPage, totalPages = current.totalPages,
                                    onPageChange = viewModel::loadPage,
                                    modifier = Modifier.padding(horizontal = SubjectMetrics.headerGutter)
                                )
                            }
                            item {
                                Text(
                                    text = "These are your AO3 collections...", fontSize = 13.sp,
                                    color = tokens.tertiaryInk,
                                    modifier = Modifier.padding(horizontal = SubjectMetrics.headerGutter)
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun AO3CollectionCard(
    collection: AO3Collection,
    onClick: () -> Unit,
    palette: SubjectPalette,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val eyebrow = if (collection.viewerIsOwner) {
        "You own"
    } else if (collection.maintainerNames.firstOrNull { it.isNotBlank() } != null) {
        collection.maintainerNames.first { it.isNotBlank() }
    } else {
        collection.byline.trim()
    }

    val metaFacts = mutableListOf<String>()
    if ((collection.worksCount ?: 0) > 0) metaFacts.add("${collection.worksCount} work${if (collection.worksCount == 1) "" else "s"}")
    if ((collection.bookmarksCount ?: 0) > 0) metaFacts.add("${collection.bookmarksCount} bookmark${if (collection.bookmarksCount == 1) "" else "s"}")
    if (collection.isModerated) metaFacts.add("Moderated")
    if (collection.isClosed) metaFacts.add("Closed")
    collection.challengeKind?.let { metaFacts.add(it.displayName) }

    val statusLabels = AO3CollectionCardCopy.statusLabels(collection.isUnrevealed, collection.isAnonymous)

    val showsByline = collection.byline.isNotBlank() || collection.maintainerNames.isNotEmpty()

    Column(
        modifier = modifier
            .fillMaxWidth()
            .subjectPanel()
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(11.dp)) {
            Box(
                modifier = Modifier
                    .size(38.dp)
                    .background(
                        color = palette.chipFill,
                        shape = RoundedCornerShape(10.dp)
                    ),
                contentAlignment = androidx.compose.ui.Alignment.Center
            ) {
                Icon(
                    imageVector = androidx.compose.material.icons.Icons.Default.Folder,
                    contentDescription = null,
                    tint = palette.accent,
                    modifier = Modifier.size(16.dp)
                )
            }
            
            Column(verticalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.weight(1f)) {
                if (eyebrow.isNotEmpty() || statusLabels.isNotEmpty()) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically
                    ) {
                        if (eyebrow.isNotEmpty()) {
                            SubjectKicker(text = eyebrow, palette = palette)
                        }
                        statusLabels.forEach { label ->
                            SubjectChip(text = label, style = SubjectChipStyle.Neutral, palette = palette)
                        }
                    }
                }
                Text(
                    text = collection.title,
                    fontSize = 19.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = tokens.primaryInk,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            }
            
            Icon(
                imageVector = androidx.compose.material.icons.Icons.Default.KeyboardArrowRight,
                contentDescription = null,
                tint = palette.accent,
                modifier = Modifier.size(12.dp).padding(top = 4.dp)
            )
        }

        if (showsByline) {
            Text(
                text = "by ${collection.byline.ifEmpty { collection.maintainerNames.joinToString(", ") }}",
                fontSize = 12.5.sp,
                color = tokens.secondaryInk,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        
        if (collection.summary.isNotBlank()) {
            Text(
                text = collection.summary,
                fontSize = 12.5.sp,
                color = tokens.secondaryInk,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }

        if (metaFacts.isNotEmpty() || collection.updatedAtText.isNotBlank()) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                // The facts take the flexible width and may wrap; the date never wraps.
                Text(
                    text = metaFacts.joinToString(" · "),
                    fontSize = 11.5.sp,
                    color = tokens.secondaryInk,
                    modifier = Modifier.weight(1f)
                )
                if (collection.updatedAtText.isNotBlank()) {
                    Text(
                        text = collection.updatedAtText,
                        fontSize = 11.5.sp,
                        color = tokens.secondaryInk,
                        maxLines = 1,
                        softWrap = false
                    )
                }
            }
        }
    }
}
