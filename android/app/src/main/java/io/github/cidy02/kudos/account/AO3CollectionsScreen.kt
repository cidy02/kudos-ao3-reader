package io.github.cidy02.kudos.account

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.cidy02.kudos.network.ao3.account.AO3Collection
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.LoadingStateCard

/**
 * Signed-in user's AO3 collections (native, read-only). Tapping a collection
 * opens its works via [AccountListType.Collection].
 */
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

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Text(
            text = "My Collections",
            style = MaterialTheme.typography.titleLarge
        )
        Text(
            text = "Collections you create or maintain on AO3.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        when (val current = state) {
            AO3CollectionsUiState.Loading -> LoadingStateCard("Loading collections")
            AO3CollectionsUiState.AuthRequired -> EmptyStateCard(
                title = "AO3 session required",
                message = "Log in to AO3 to see your collections.",
                primaryActionLabel = "Log In to AO3",
                onPrimaryAction = onLogin
            )
            is AO3CollectionsUiState.Failed -> {
                ErrorStateCard(
                    title = "Couldn't load collections",
                    message = current.message,
                    primaryActionLabel = "Retry",
                    onPrimaryAction = viewModel::load
                )
            }
            is AO3CollectionsUiState.Loaded -> {
                if (current.collections.isEmpty()) {
                    EmptyStateCard(
                        title = "No collections",
                        message = "Collections you create or maintain on AO3 show up here."
                    )
                } else {
                    CollectionsListContent(
                        collections = current.collections,
                        onOpenCollection = onOpenCollection
                    )
                }
            }
        }
    }
}

@Composable
private fun CollectionsListContent(
    collections: List<AO3Collection>,
    onOpenCollection: (AO3Collection) -> Unit
) {
    LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        items(collections, key = { it.name }) { collection ->
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainerLow
                )
            ) {
                ListItem(
                    headlineContent = {
                        Text(collection.title)
                    },
                    supportingContent = if (collection.byline.isNotBlank()) {
                        {
                            Text(
                                text = collection.byline,
                                maxLines = 1
                            )
                        }
                    } else {
                        null
                    },
                    trailingContent = {
                        Icon(
                            imageVector = Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    },
                    colors = ListItemDefaults.colors(
                        containerColor = MaterialTheme.colorScheme.surfaceContainerLow
                    ),
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onOpenCollection(collection) }
                )
            }
        }
    }
}
