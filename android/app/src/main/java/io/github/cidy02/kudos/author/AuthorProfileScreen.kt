package io.github.cidy02.kudos.author

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorAbout
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorBookmarksPage
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorHeader
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorRepository
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorRoute
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorSeriesPage
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.ui.components.AO3WorkCard
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.components.MetadataChipRow
import kotlinx.coroutines.launch
import io.github.cidy02.kudos.network.ao3.displayMessage

private enum class AuthorTab(val label: String) {
    Works("Works"),
    Series("Series"),
    Bookmarks("Bookmarks"),
    About("About")
}

/**
 * Native AO3 author profile: hero, pseud scope, 4 tabs.
 * Port of iOS `AuthorProfileView`.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AuthorProfileScreen(
    username: String,
    initialPseud: String? = null,
    authorRepository: AO3AuthorRepository,
    onOpenWork: (AO3WorkSummary) -> Unit,
    onOpenSeries: (String) -> Unit = {},
    onOpenWeb: (String) -> Unit = {}
) {
    var route by remember(username, initialPseud) {
        mutableStateOf(AO3AuthorRoute(username.trim(), initialPseud?.trim()?.takeIf { it.isNotBlank() }))
    }
    var header by remember { mutableStateOf<AO3AuthorHeader?>(null) }
    var headerError by remember { mutableStateOf<String?>(null) }
    var headerLoading by remember { mutableStateOf(true) }
    var tab by remember { mutableStateOf(AuthorTab.Works) }
    var page by remember { mutableIntStateOf(1) }
    var works by remember { mutableStateOf<AO3SearchPage?>(null) }
    var series by remember { mutableStateOf<AO3AuthorSeriesPage?>(null) }
    var bookmarks by remember { mutableStateOf<AO3AuthorBookmarksPage?>(null) }
    var about by remember { mutableStateOf<AO3AuthorAbout?>(null) }
    var tabLoading by remember { mutableStateOf(false) }
    var tabError by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    fun loadHeader() {
        headerLoading = true
        headerError = null
        scope.launch {
            when (val result = authorRepository.loadDashboard(route)) {
                is AO3Result.Success -> {
                    header = result.value
                    headerError = null
                }
                is AO3Result.Failure -> {
                    headerError = result.error.displayMessage()
                }
            }
            headerLoading = false
        }
    }

    fun loadTab(target: AuthorTab, pageNum: Int = 1) {
        tabLoading = true
        tabError = null
        page = pageNum
        scope.launch {
            when (target) {
                AuthorTab.Works -> when (val r = authorRepository.loadWorks(route, pageNum)) {
                    is AO3Result.Success -> works = r.value
                    is AO3Result.Failure -> tabError = r.error.displayMessage()
                }
                AuthorTab.Series -> when (val r = authorRepository.loadSeries(route, pageNum)) {
                    is AO3Result.Success -> series = r.value
                    is AO3Result.Failure -> tabError = r.error.displayMessage()
                }
                AuthorTab.Bookmarks -> when (val r = authorRepository.loadBookmarks(route, pageNum)) {
                    is AO3Result.Success -> bookmarks = r.value
                    is AO3Result.Failure -> tabError = r.error.displayMessage()
                }
                AuthorTab.About -> when (val r = authorRepository.loadAbout(route)) {
                    is AO3Result.Success -> about = r.value
                    is AO3Result.Failure -> tabError = r.error.displayMessage()
                }
            }
            tabLoading = false
        }
    }

    LaunchedEffect(route.id) {
        loadHeader()
        loadTab(tab, 1)
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        when {
            headerLoading && header == null -> LoadingStateCard("Loading profile…")
            headerError != null && header == null -> ErrorStateCard(
                title = "Profile failed",
                message = headerError!!,
                primaryActionLabel = "Retry",
                onPrimaryAction = { loadHeader() }
            )
            else -> {
                val h = header
                Row(
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    AsyncImage(
                        model = ImageRequest.Builder(context)
                            .data(h?.avatarUrl)
                            .crossfade(true)
                            .build(),
                        contentDescription = "Avatar",
                        contentScale = ContentScale.Crop,
                        modifier = Modifier
                            .size(64.dp)
                            .clip(CircleShape)
                    )
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = h?.displayName ?: route.displayName,
                            style = MaterialTheme.typography.titleLarge
                        )
                        Text(
                            text = "@${route.username}",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        h?.userId?.let {
                            Text(
                                "User ID $it",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }

                // Pseud scope
                val pseuds = h?.pseuds.orEmpty()
                if (pseuds.size > 1) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        modifier = Modifier
                            .fillMaxWidth()
                            .horizontalScroll(rememberScrollState())
                    ) {
                        FilterChip(
                            selected = route.pseud == null,
                            onClick = {
                                route = AO3AuthorRoute(route.username, null)
                            },
                            label = { Text("All Pseuds") }
                        )
                        pseuds.forEach { pseud ->
                            FilterChip(
                                selected = route.pseud.equals(pseud.route.pseud, true),
                                onClick = { route = pseud.route },
                                label = { Text(pseud.name) }
                            )
                        }
                    }
                }

                // Actions: open works on AO3, profile, etc.
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    h?.subscriptionForm?.let { form ->
                        OutlinedButton(onClick = { onOpenWeb(form.actionUrl) }) {
                            Text(if (form.isSubscribed) "Unsubscribe" else "Subscribe")
                        }
                    }
                    h?.actions?.firstOrNull { it.kind.name == "Block" || it.kind.name == "Mute" }
                        ?.let { action ->
                            OutlinedButton(onClick = { onOpenWeb(action.url) }) {
                                Text(action.label)
                            }
                        }
                }

                SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                    AuthorTab.entries.forEachIndexed { index, t ->
                        SegmentedButton(
                            selected = tab == t,
                            onClick = {
                                tab = t
                                loadTab(t, 1)
                            },
                            shape = SegmentedButtonDefaults.itemShape(
                                index = index,
                                count = AuthorTab.entries.size
                            ),
                            label = { Text(t.label, maxLines = 1) }
                        )
                    }
                }
            }
        }

        when {
            tabLoading -> LoadingStateCard("Loading…")
            tabError != null -> ErrorStateCard(
                title = "Couldn't load ${tab.label.lowercase()}",
                message = tabError!!,
                primaryActionLabel = "Retry",
                onPrimaryAction = { loadTab(tab, page) }
            )
            tab == AuthorTab.Works -> {
                val pageData = works
                if (pageData == null || pageData.works.isEmpty()) {
                    EmptyStateCard("No works", "This author has no works here.")
                } else {
                    LazyColumn(
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                        contentPadding = PaddingValues(bottom = 24.dp),
                        modifier = Modifier.fillMaxSize()
                    ) {
                        items(pageData.works, key = { it.id }) { work ->
                            AO3WorkCard(
                                work = work,
                                onOpenWork = onOpenWork
                            )
                        }
                        item {
                            PagerRow(
                                page = pageData.currentPage,
                                total = pageData.totalPages,
                                onPrev = { loadTab(AuthorTab.Works, pageData.currentPage - 1) },
                                onNext = { loadTab(AuthorTab.Works, pageData.currentPage + 1) }
                            )
                        }
                    }
                }
            }
            tab == AuthorTab.Series -> {
                val pageData = series
                if (pageData == null || pageData.series.isEmpty()) {
                    EmptyStateCard("No series", "This author has no series here.")
                } else {
                    LazyColumn(
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        contentPadding = PaddingValues(bottom = 24.dp)
                    ) {
                        items(pageData.series, key = { it.id }) { item ->
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable { onOpenSeries(item.url) }
                                    .padding(vertical = 8.dp)
                            ) {
                                Text(item.title, style = MaterialTheme.typography.titleMedium)
                                if (item.creators.isNotEmpty()) {
                                    Text(
                                        item.creators.joinToString(),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                                val meta = buildList {
                                    item.workCount?.let { add("$it works") }
                                    item.words?.let { add("$it words") }
                                    if (item.dateUpdated.isNotBlank()) add(item.dateUpdated)
                                }.joinToString(" · ")
                                if (meta.isNotBlank()) {
                                    Text(
                                        meta,
                                        style = MaterialTheme.typography.labelMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }
                        item {
                            PagerRow(
                                page = pageData.currentPage,
                                total = pageData.totalPages,
                                onPrev = { loadTab(AuthorTab.Series, pageData.currentPage - 1) },
                                onNext = { loadTab(AuthorTab.Series, pageData.currentPage + 1) }
                            )
                        }
                    }
                }
            }
            tab == AuthorTab.Bookmarks -> {
                val pageData = bookmarks
                if (pageData == null || pageData.bookmarks.isEmpty()) {
                    EmptyStateCard("No bookmarks", "This author has no public bookmarks here.")
                } else {
                    LazyColumn(
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                        contentPadding = PaddingValues(bottom = 24.dp)
                    ) {
                        items(pageData.bookmarks, key = { it.id }) { bm ->
                            Column(modifier = Modifier.padding(bottom = 8.dp)) {
                                if (bm.isPrivate || bm.isRecommendation) {
                                    val labels = buildList {
                                        if (bm.isPrivate) add("Private")
                                        if (bm.isRecommendation) add("Recommendation")
                                    }
                                    MetadataChipRow(labels = labels, prominent = true)
                                    Spacer(Modifier.height(4.dp))
                                }
                                bm.work?.let { work ->
                                    AO3WorkCard(
                                        work = work,
                                        onOpenWork = onOpenWork
                                    )
                                } ?: Text(
                                    "Bookmark #${bm.id}",
                                    style = MaterialTheme.typography.bodyMedium
                                )
                                if (bm.notes.isNotBlank()) {
                                    Text(
                                        bm.notes,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.padding(top = 4.dp)
                                    )
                                }
                            }
                        }
                        item {
                            PagerRow(
                                page = pageData.currentPage,
                                total = pageData.totalPages,
                                onPrev = {
                                    loadTab(AuthorTab.Bookmarks, pageData.currentPage - 1)
                                },
                                onNext = {
                                    loadTab(AuthorTab.Bookmarks, pageData.currentPage + 1)
                                }
                            )
                        }
                    }
                }
            }
            tab == AuthorTab.About -> {
                val a = about
                if (a == null) {
                    EmptyStateCard("No about", "Profile details unavailable.")
                } else {
                    LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        item {
                            if (a.profileTitle.isNotBlank()) {
                                Text(a.profileTitle, style = MaterialTheme.typography.titleMedium)
                            }
                            if (a.joinedDate.isNotBlank()) {
                                Text(
                                    "Joined ${a.joinedDate}",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            a.userId?.let {
                                Text(
                                    "User ID $it",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            Spacer(Modifier.height(8.dp))
                            Text(
                                a.bioText.ifBlank { "No bio." },
                                style = MaterialTheme.typography.bodyMedium
                            )
                        }
                        if (a.pseuds.isNotEmpty()) {
                            item {
                                Text("Pseuds", style = MaterialTheme.typography.titleSmall)
                                a.pseuds.forEach { p ->
                                    Text(
                                        text = "• ${p.name}",
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = MaterialTheme.colorScheme.primary,
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .clickable {
                                                route = p.route
                                                tab = AuthorTab.Works
                                            }
                                            .padding(vertical = 4.dp)
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

@Composable
private fun PagerRow(page: Int, total: Int, onPrev: () -> Unit, onNext: () -> Unit) {
    if (total <= 1) return
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        OutlinedButton(onClick = onPrev, enabled = page > 1) { Text("Previous") }
        Text("Page $page / $total", style = MaterialTheme.typography.labelLarge)
        OutlinedButton(onClick = onNext, enabled = page < total) { Text("Next") }
    }
}
