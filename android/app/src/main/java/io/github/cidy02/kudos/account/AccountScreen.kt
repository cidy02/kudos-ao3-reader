package io.github.cidy02.kudos.account

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.AO3AuthState
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.ui.components.AO3WorkCard

@Composable
fun AccountScreen(
    authRepository: AO3AuthRepository,
    onLogin: () -> Unit,
    onOpenList: (AccountListType) -> Unit,
    onOpenBackup: () -> Unit,
    onOpenSettings: () -> Unit,
    modifier: Modifier = Modifier,
    viewModel: AccountViewModel = viewModel(factory = AccountViewModel.factory(authRepository))
) {
    val state by viewModel.uiState.collectAsState()

    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            AccountStatusCard(
                authState = state.authState,
                onLogin = onLogin,
                onLogout = viewModel::logout
            )
        }
        item {
            AccountListsCard(
                enabled = state.authState is AO3AuthState.SignedIn,
                onOpenList = onOpenList
            )
        }
        item {
            AppActionsCard(onOpenSettings = onOpenSettings, onOpenBackup = onOpenBackup)
        }
    }
}

@Composable
fun AccountListScreen(
    type: AccountListType,
    repository: AccountListRepository,
    onLogin: () -> Unit,
    onOpenWork: (AO3WorkSummary) -> Unit,
    modifier: Modifier = Modifier,
    viewModel: AccountListViewModel = viewModel(
        key = type.name,
        factory = AccountListViewModel.factory(type, repository)
    )
) {
    val state by viewModel.uiState.collectAsState()

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Text(type.title, style = MaterialTheme.typography.headlineSmall)
        when (val current = state) {
            AccountListUiState.Loading -> CircularProgressIndicator()
            AccountListUiState.AuthRequired -> {
                Text("Your AO3 session needs to be refreshed.")
                Button(onClick = onLogin) { Text("Log In Again") }
            }
            is AccountListUiState.Failed -> {
                Text(current.message, color = MaterialTheme.colorScheme.error)
                OutlinedButton(onClick = { viewModel.load(1) }) { Text("Retry") }
            }
            is AccountListUiState.Loaded -> {
                if (current.page.works.isEmpty()) {
                    Text(type.emptyTitle, style = MaterialTheme.typography.titleMedium)
                    Text(type.emptyMessage)
                } else {
                    AccountListContent(
                        type = type,
                        page = current.page.currentPage,
                        totalPages = current.page.totalPages,
                        works = current.page.works,
                        onLoadPage = viewModel::load,
                        onOpenWork = onOpenWork
                    )
                }
            }
        }
    }
}

@Composable
private fun AccountListContent(
    type: AccountListType,
    page: Int,
    totalPages: Int,
    works: List<AO3WorkSummary>,
    onLoadPage: (Int) -> Unit,
    onOpenWork: (AO3WorkSummary) -> Unit
) {
    LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            if (totalPages > 1) {
                PaginationControls(page, totalPages, onLoadPage)
            }
        }
        items(works, key = { "${type.name}-${it.id}" }) { work ->
            AO3WorkCard(work = work, onOpenWork = onOpenWork)
        }
        item {
            if (totalPages > 1) {
                PaginationControls(page, totalPages, onLoadPage)
            }
        }
    }
}

@Composable
private fun PaginationControls(page: Int, totalPages: Int, onLoadPage: (Int) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
        OutlinedButton(
            enabled = page > 1,
            onClick = { onLoadPage(page - 1) },
            modifier = Modifier.weight(1f)
        ) {
            Text("Previous")
        }
        Text(
            text = "Page $page of $totalPages",
            modifier = Modifier.weight(1f),
            style = MaterialTheme.typography.labelLarge
        )
        OutlinedButton(
            enabled = page < totalPages,
            onClick = { onLoadPage(page + 1) },
            modifier = Modifier.weight(1f)
        ) {
            Text("Next")
        }
    }
}

@Composable
private fun AccountStatusCard(
    authState: AO3AuthState,
    onLogin: () -> Unit,
    onLogout: () -> Unit
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text("AO3 Account", style = MaterialTheme.typography.titleMedium)
            when (authState) {
                AO3AuthState.Restoring -> {
                    CircularProgressIndicator()
                    Text("Checking saved AO3 session.")
                }
                AO3AuthState.SigningIn -> {
                    CircularProgressIndicator()
                    Text("Capturing AO3 session.")
                }
                is AO3AuthState.SignedIn -> {
                    Text("Signed in as ${authState.username}.")
                    Text("Session cookies stay app-private and are never included in Kudos backups.")
                    OutlinedButton(onClick = onLogout) { Text("Log Out") }
                }
                AO3AuthState.SignedOut -> SignedOutLoginCopy(onLogin)
                is AO3AuthState.Expired -> {
                    Text(authState.message, color = MaterialTheme.colorScheme.error)
                    Button(onClick = onLogin) { Text("Log In Again") }
                }
                is AO3AuthState.Error -> {
                    Text(authState.message, color = MaterialTheme.colorScheme.error)
                    Button(onClick = onLogin) { Text("Log In") }
                }
            }
        }
    }
}

@Composable
private fun SignedOutLoginCopy(onLogin: () -> Unit) {
    Text("AO3 login is optional.")
    Text("Kudos opens AO3's real login page. It never stores your AO3 password.")
    Text("Kudos is an unofficial app and is not affiliated with AO3 or OTW.")
    Button(onClick = onLogin) { Text("Log In to AO3") }
}

@Composable
private fun AccountListsCard(
    enabled: Boolean,
    onOpenList: (AccountListType) -> Unit
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text("My AO3", style = MaterialTheme.typography.titleMedium)
            AccountListType.entries.forEach { type ->
                OutlinedButton(
                    enabled = enabled,
                    onClick = { onOpenList(type) },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(type.title)
                }
            }
            if (!enabled) {
                Text("Log in to load account lists.")
            }
        }
    }
}

@Composable
private fun AppActionsCard(
    onOpenSettings: () -> Unit,
    onOpenBackup: () -> Unit
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text("App", style = MaterialTheme.typography.titleMedium)
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Button(onClick = onOpenSettings, modifier = Modifier.weight(1f)) {
                    Text("Settings")
                }
                OutlinedButton(onClick = onOpenBackup, modifier = Modifier.weight(1f)) {
                    Text("Backup")
                }
            }
            HorizontalDivider()
            Text("Authenticated writes, comments, kudos, AO3 bookmarks, subscriptions changes, and Mark for Later changes are deferred.")
        }
    }
}
