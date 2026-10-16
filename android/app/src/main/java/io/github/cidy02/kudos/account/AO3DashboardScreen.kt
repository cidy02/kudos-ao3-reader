package io.github.cidy02.kudos.account

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.Alignment
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
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
    onOpenAbout: (io.github.cidy02.kudos.network.ao3.author.AO3AuthorRoute) -> Unit,
    modifier: Modifier = Modifier,
    /** The session the page is the reader's own in: without it the page did not know it was. */
    authRepository: io.github.cidy02.kudos.auth.AO3AuthRepository? = null,
    onNewWork: (() -> Unit)? = null
) {
    if (username.isNullOrBlank()) {
        ProvidePushedShellChrome()
        Box(modifier.fillMaxSize().padding(SubjectMetrics.accountGutter), contentAlignment = Alignment.Center) {
            EmptyStateCard("Not signed in", "Log in to AO3 to open your dashboard.")
        }
        return
    }
    
    AuthorProfileScreen(
        username = username,
        initialPseud = null,
        authorRepository = authorRepository,
        onOpenWork = onOpenWork,
        onOpenAbout = onOpenAbout,
        onOpenSeries = onOpenSeries,
        onOpenWeb = onOpenWeb,
        isDashboard = true,
        onOpenDashboardList = onOpenList,
        onOpenAO3Collections = onOpenAO3Collections,
        modifier = modifier,
        authRepository = authRepository,
        onNewWork = onNewWork
    )
}
