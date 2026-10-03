package io.github.cidy02.kudos.account

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
    val tokens = LocalKudosTokens.current
    val palette = androidx.compose.runtime.remember(tokens.theme) { io.github.cidy02.kudos.ui.subject.SubjectPalette.fromHue(210.0, tokens.theme) }

    ProvidePushedShellChrome(
        hasSubjectHeader = true,
        trailingContent = {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ToolbarAddButton(
                    onClick = { /* TODO: New Collection */ },
                    accessibilityName = "New Collection",
                    palette = palette
                )
                FilterButton(
                    filtersActive = false,
                    onClick = { /* TODO: Filter */ },
                    onClearFilters = { }
                )
            }
        }
    )

    Column(modifier = modifier.fillMaxSize().subjectScreenWash(palette)) {
            Spacer(modifier = Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
            Spacer(modifier = Modifier.height(56.dp))

            SubjectHeaderBlock(
                kicker = "AO3 Account",
                title = "Collections",
                subtitle = when (val current = state) {
                    is AO3CollectionsUiState.Loaded -> "${current.collections.size} collection${if (current.collections.size == 1) "" else "s"}"
                    else -> null
                },
                palette = palette
            )
            
            Spacer(modifier = Modifier.height(16.dp))
            
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .padding(horizontal = SubjectMetrics.headerGutter),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                SubjectChip("Collections", style = SubjectChipStyle.Pill(isSelected = true), palette = palette)
                SubjectChip("Your items", style = SubjectChipStyle.Pill(isSelected = false), palette = palette)
            }
            
            Spacer(modifier = Modifier.height(16.dp))

            when (val current = state) {
                AO3CollectionsUiState.Loading -> {
                    Box(modifier = Modifier.padding(SubjectMetrics.headerGutter)) {
                        LoadingStateCard("Loading collections")
                    }
                }
                AO3CollectionsUiState.AuthRequired -> {
                    Box(modifier = Modifier.padding(SubjectMetrics.headerGutter)) {
                        EmptyStateCard(
                            title = "AO3 session required",
                            message = "Log in to AO3 to see your collections.",
                            primaryActionLabel = "Log In to AO3",
                            onPrimaryAction = onLogin
                        )
                    }
                }
                is AO3CollectionsUiState.Failed -> {
                    Box(modifier = Modifier.padding(SubjectMetrics.headerGutter)) {
                        ErrorStateCard(
                            title = "Couldn't load collections",
                            message = current.message,
                            primaryActionLabel = "Try Again",
                            onPrimaryAction = viewModel::load
                        )
                    }
                }
                is AO3CollectionsUiState.Loaded -> {
                    if (current.collections.isEmpty()) {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = SubjectMetrics.headerGutter)
                                .subjectPanel()
                                .padding(16.dp)
                        ) {
                            Text("No collections", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                            Spacer(Modifier.height(4.dp))
                            Text("Collections you create or maintain on AO3 show up here.", color = LocalKudosTokens.current.secondaryInk, fontSize = 14.sp)
                        }
                    } else {
                        CollectionsListContent(
                            collections = current.collections,
                            onOpenCollection = onOpenCollection,
                            palette = palette
                        )
                    }
                    
                    Spacer(Modifier.height(16.dp))
                    Text(
                        text = "These are your AO3 collections...",
                        fontSize = 13.sp,
                        color = LocalKudosTokens.current.tertiaryInk,
                        modifier = Modifier.padding(horizontal = SubjectMetrics.headerGutter)
                    )
                    Spacer(Modifier.height(32.dp))
                }
            }
        }
}

@Composable
private fun CollectionsListContent(
    collections: List<AO3Collection>,
    onOpenCollection: (AO3Collection) -> Unit,
    palette: SubjectPalette
) {
    LazyColumn(
        verticalArrangement = Arrangement.spacedBy(12.dp),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = SubjectMetrics.headerGutter)
    ) {
        items(collections, key = { it.name }) { collection ->
            AO3CollectionCard(
                collection = collection,
                onClick = { onOpenCollection(collection) },
                palette = palette
            )
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
    if (collection.worksCount > 0) metaFacts.add("${collection.worksCount} work${if (collection.worksCount == 1) "" else "s"}")
    if (collection.bookmarksCount > 0) metaFacts.add("${collection.bookmarksCount} bookmark${if (collection.bookmarksCount == 1) "" else "s"}")
    if (collection.isModerated) metaFacts.add("Moderated")
    if (collection.isClosed) metaFacts.add("Closed")
    collection.challengeKind?.let { metaFacts.add(it.displayName) }

    val statusLabels = mutableListOf<String>()
    if (collection.isUnrevealed) statusLabels.add("Unrevealed")
    if (collection.isAnonymous) statusLabels.add("Anonymous")

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
