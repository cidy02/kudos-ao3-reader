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
import io.github.cidy02.kudos.ui.subject.ToolbarCircleButton
import io.github.cidy02.kudos.ui.subject.subjectPanel

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
                ToolbarCircleButton(
                    onClick = { /* TODO: New Collection */ },
                    accessibilityName = "New Collection",
                    palette = palette
                ) {
                    Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(18.dp))
                }
                ToolbarCircleButton(
                    onClick = { /* TODO: Filter */ },
                    accessibilityName = "Sort and filter",
                    palette = palette
                ) {
                    Icon(Icons.Default.FilterList, contentDescription = null, modifier = Modifier.size(18.dp))
                }
            }
        }
    )

    Column(modifier = modifier.fillMaxSize()) {
            Spacer(modifier = Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
            Spacer(modifier = Modifier.height(56.dp))

            SubjectHeaderBlock(
                kicker = "AO3 Account",
                title = "Collections",
                subtitle = when (val current = state) {
                    is AO3CollectionsUiState.Loaded -> "${current.collections.size}"
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
    Column(
        modifier = modifier
            .fillMaxWidth()
            .subjectPanel()
            .clickable(onClick = onClick)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text(
            text = collection.title,
            fontSize = 19.sp,
            fontWeight = FontWeight.Bold,
            color = tokens.primaryInk,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
        if (collection.byline.isNotBlank()) {
            Text(
                text = collection.byline,
                fontSize = 12.5.sp,
                color = tokens.secondaryInk,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        Text(
            text = collection.name,
            fontSize = 11.5.sp,
            color = tokens.tertiaryInk,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}
