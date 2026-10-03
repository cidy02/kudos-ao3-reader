package io.github.cidy02.kudos.account

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import io.github.cidy02.kudos.author.AuthorProfileScreen
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorRepository
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary

/** Native My Dashboard hub — mirrors Apple AO3DashboardView. */
@Composable
fun AO3DashboardScreen(
    authorRepository: AO3AuthorRepository,
    onOpenWork: (AO3WorkSummary) -> Unit,
    onOpenSeries: (String) -> Unit,
    onOpenWeb: (String) -> Unit,
    username: String?,
    onOpenList: (AccountListType) -> Unit,
    onOpenAO3Collections: () -> Unit,
    modifier: Modifier = Modifier
) {
    if (username.isNullOrBlank()) {
        // Sign in required state. iOS just shows the account logged out state, but we'll show empty.
        // Actually, username should be present if they are here.
        return
    }
    
    AuthorProfileScreen(
        username = username,
        initialPseud = null,
        authorRepository = authorRepository,
        onOpenWork = onOpenWork,
        onOpenSeries = onOpenSeries,
        onOpenWeb = onOpenWeb,
        isDashboard = true,
        onOpenDashboardList = onOpenList,
        onOpenAO3Collections = onOpenAO3Collections,
        modifier = modifier
    )
}
