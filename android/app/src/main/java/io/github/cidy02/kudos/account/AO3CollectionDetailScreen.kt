package io.github.cidy02.kudos.account

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.fragment.app.FragmentActivity
import io.github.cidy02.kudos.app.PrivacyGate
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionPerson
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionPeoplePage
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionShow
import io.github.cidy02.kudos.network.ao3.displayMessage
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.ui.components.KudosPaginationBar
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.ui.components.SensitiveWorkRow
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.SubjectSegmentedControl
import io.github.cidy02.kudos.ui.subject.SubjectStatCell
import io.github.cidy02.kudos.ui.subject.SubjectStatStrip
import io.github.cidy02.kudos.ui.subject.ToolbarCircleButton
import io.github.cidy02.kudos.ui.subject.subjectPanel
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import kotlinx.coroutines.launch

@Composable
fun AO3CollectionDetailScreen(
    slug: String,
    title: String,
    repository: AO3CollectionDetailRepository,
    settingsRepository: SettingsRepository,
    privacyGate: PrivacyGate,
    onOpenWork: (AO3WorkSummary) -> Unit,
    onOpenWebFallback: (String) -> Unit,
    onOpenModeration: () -> Unit,
    onOpenSettings: () -> Unit
) {
    var show by remember(slug) { mutableStateOf<AO3CollectionShow?>(null) }
    var segment by remember(slug) { mutableStateOf(AO3CollectionSegment.Works) }
    var worksPage by remember(slug) { mutableStateOf<AO3SearchPage?>(null) }
    var bookmarksPage by remember(slug) { mutableStateOf<AO3SearchPage?>(null) }
    var peoplePage by remember(slug) { mutableStateOf<AO3CollectionPeoplePage?>(null) }
    var loadedSegments by remember(slug) { mutableStateOf(emptySet<AO3CollectionSegment>()) }
    var phase by remember(slug) { mutableStateOf<AO3CollectionDetailPhase>(AO3CollectionDetailPhase.Idle) }
    var loadGeneration by remember(slug) { mutableIntStateOf(0) }
    var showMenu by remember(slug) { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val settings by settingsRepository.settings.collectAsState(initial = KudosSettings.Defaults)
    val reveal by privacyGate.state.collectAsState()
    val activity = LocalContext.current as? FragmentActivity
    val tokens = LocalKudosTokens.current
    val paletteTitle = show?.collection?.title ?: title
    val palette = remember(paletteTitle, tokens.theme) {
        SubjectPalette.fromHue(HomeFacts.workHue(emptyList(), paletteTitle), tokens.theme)
    }

    fun currentPage(target: AO3CollectionSegment): Int = when (target) {
        AO3CollectionSegment.Works -> worksPage?.currentPage ?: 1
        AO3CollectionSegment.Bookmarks -> bookmarksPage?.currentPage ?: 1
        AO3CollectionSegment.People -> peoplePage?.currentPage ?: 1
    }

    suspend fun load(target: AO3CollectionSegment, page: Int = currentPage(target)) {
        val generation = ++loadGeneration
        phase = AO3CollectionDetailPhase.Loading
        if (show == null) {
            when (val result = repository.getCollectionShow(slug)) {
                is AO3Result.Success -> {
                    if (generation != loadGeneration) return
                    show = result.value
                }
                is AO3Result.Failure -> {
                    if (generation == loadGeneration) {
                        phase = AO3CollectionDetailPhase.Failed(result.error.displayMessage())
                    }
                    return
                }
            }
        }

        when (target) {
            AO3CollectionSegment.Works -> when (val result = repository.getCollectionWorks(slug, page)) {
                is AO3Result.Success -> if (generation == loadGeneration) worksPage = result.value
                is AO3Result.Failure -> {
                    if (generation == loadGeneration) {
                        phase = AO3CollectionDetailPhase.Failed(result.error.displayMessage())
                    }
                    return
                }
            }
            AO3CollectionSegment.Bookmarks -> when (
                val result = repository.getCollectionBookmarks(slug, page)
            ) {
                is AO3Result.Success -> if (generation == loadGeneration) bookmarksPage = result.value
                is AO3Result.Failure -> {
                    if (generation == loadGeneration) {
                        phase = AO3CollectionDetailPhase.Failed(result.error.displayMessage())
                    }
                    return
                }
            }
            AO3CollectionSegment.People -> when (val result = repository.getCollectionPeople(slug, page)) {
                is AO3Result.Success -> if (generation == loadGeneration) peoplePage = result.value
                is AO3Result.Failure -> {
                    if (generation == loadGeneration) {
                        phase = AO3CollectionDetailPhase.Failed(result.error.displayMessage())
                    }
                    return
                }
            }
        }

        if (generation == loadGeneration) {
            loadedSegments = loadedSegments + target
            phase = AO3CollectionDetailPhase.Loaded
        }
    }

    LaunchedEffect(slug, segment) {
        if (segment in loadedSegments) {
            phase = AO3CollectionDetailPhase.Loaded
        } else {
            load(segment)
        }
    }

    ProvidePushedShellChrome(
        hasSubjectHeader = true,
        trailingContent = if (settings.privacy.hideMatureContent) {
            {
                Box {
                    ToolbarCircleButton(
                        onClick = { showMenu = true },
                        accessibilityName = "More actions",
                        palette = palette
                    ) {
                        Icon(imageVector = Icons.Default.MoreVert, contentDescription = null)
                    }
                    DropdownMenu(
                        expanded = showMenu,
                        onDismissRequest = { showMenu = false }
                    ) {
                        DropdownMenuItem(
                            text = { Text(if (reveal.revealAll) "Hide mature" else "Show mature") },
                            leadingIcon = {
                                Icon(
                                    if (reveal.revealAll) Icons.Filled.VisibilityOff else Icons.Filled.Visibility,
                                    contentDescription = null
                                )
                            },
                            onClick = {
                                showMenu = false
                                privacyGate.toggleRevealAll(activity)
                            }
                        )
                    }
                }
            }
        } else {
            null
        }
    )

    KudosRefreshBox(
        onRefresh = {
            loadedSegments = loadedSegments - segment
            load(segment)
        },
        modifier = Modifier
            .fillMaxSize()
            .subjectScreenWash(palette)
    ) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = 24.dp)
        ) {
            item {
                Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
                Spacer(Modifier.height(56.dp))
                SubjectHeaderBlock(
                    kicker = "Collection",
                    title = show?.collection?.title ?: title,
                    subtitle = show?.collection?.let { collection ->
                        listOf(collection.byline, collection.summary)
                            .filter { it.isNotBlank() }
                            .joinToString(" · ")
                            .takeIf { it.isNotBlank() }
                    },
                    palette = palette,
                    gutter = SubjectMetrics.accountGutter
                )
            }

            show?.let { collectionShow ->
                item {
                    SubjectStatStrip(
                        cells = listOf(
                            SubjectStatCell(collectionShow.collection.worksCount.toString(), "Works"),
                            SubjectStatCell(collectionShow.collection.bookmarksCount.toString(), "Bookmarks")
                        ),
                        palette = palette,
                        modifier = Modifier
                            .padding(top = 12.dp)
                            .padding(horizontal = SubjectMetrics.panelGutter)
                    )
                }
            }

            item {
                SubjectSegmentedControl(
                    options = AO3CollectionSegment.entries,
                    selected = segment,
                    onSelect = { segment = it },
                    title = { it.title },
                    contentDescription = "Collection section",
                    modifier = Modifier
                        .padding(top = 14.dp)
                        .padding(horizontal = SubjectMetrics.accountGutter)
                )
            }

            show?.let { collectionShow ->
                val actions = collectionManageActions(collectionShow, slug)
                if (actions.isNotEmpty()) {
                    item {
                        SectionRuleHeader(
                            title = "Manage",
                            modifier = Modifier.padding(top = 18.dp, bottom = 8.dp)
                        )
                    }
                    item {
                        Column(
                            Modifier
                                .padding(horizontal = SubjectMetrics.accountGutter)
                                .subjectPanel()
                        ) {
                            actions.forEachIndexed { index, action ->
                                if (index > 0) SubjectRowSeparator()
                                SubjectFormRow(
                                    label = action.label,
                                    showsDisclosure = true,
                                    onClick = {
                                        if (action.label == "Moderation") onOpenModeration()
                                        else if (action.label == "Collection Settings") onOpenSettings()
                                        else onOpenWebFallback(action.url)
                                    }
                                )
                            }
                        }
                    }
                }
            }

            when (val currentPhase = phase) {
                AO3CollectionDetailPhase.Idle -> Unit
                AO3CollectionDetailPhase.Loading -> {
                    if (segmentRowsAreEmpty(segment, worksPage, bookmarksPage, peoplePage)) {
                        item {
                            Box(
                                Modifier
                                    .fillMaxWidth()
                                    .padding(top = 20.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                CircularProgressIndicator(modifier = Modifier.size(24.dp))
                            }
                        }
                    } else {
                        collectionSegmentContent(
                            segment = segment,
                            show = show,
                            worksPage = worksPage,
                            bookmarksPage = bookmarksPage,
                            peoplePage = peoplePage,
                            palette = palette,
                            onOpenWork = onOpenWork
                        )
                    }
                }
                is AO3CollectionDetailPhase.Failed -> item {
                    CollectionFailureCard(
                        message = currentPhase.message,
                        onRetry = { scope.launch { load(segment) } },
                        modifier = Modifier
                            .padding(top = 14.dp)
                            .padding(horizontal = SubjectMetrics.accountGutter)
                    )
                }
                AO3CollectionDetailPhase.Loaded -> collectionSegmentContent(
                    segment = segment,
                    show = show,
                    worksPage = worksPage,
                    bookmarksPage = bookmarksPage,
                    peoplePage = peoplePage,
                    palette = palette,
                    onOpenWork = onOpenWork
                )
            }

            val totalPages = when (segment) {
                AO3CollectionSegment.Works -> worksPage?.totalPages ?: 1
                AO3CollectionSegment.Bookmarks -> bookmarksPage?.totalPages ?: 1
                AO3CollectionSegment.People -> peoplePage?.totalPages ?: 1
            }
            if (phase !is AO3CollectionDetailPhase.Failed && totalPages > 1) {
                item {
                    KudosPaginationBar(
                        currentPage = currentPage(segment),
                        totalPages = totalPages,
                        enabled = phase != AO3CollectionDetailPhase.Loading,
                        onPageChange = { page -> scope.launch { load(segment, page) } },
                        modifier = Modifier
                            .padding(top = 14.dp)
                            .padding(horizontal = SubjectMetrics.accountGutter)
                            .subjectPanel()
                            .padding(horizontal = 4.dp)
                    )
                }
            }
        }
    }
}

private fun androidx.compose.foundation.lazy.LazyListScope.collectionSegmentContent(
    segment: AO3CollectionSegment,
    show: AO3CollectionShow?,
    worksPage: AO3SearchPage?,
    bookmarksPage: AO3SearchPage?,
    peoplePage: AO3CollectionPeoplePage?,
    palette: SubjectPalette,
    onOpenWork: (AO3WorkSummary) -> Unit
) {
    when (segment) {
        AO3CollectionSegment.Works -> workRows(
            rows = worksPage?.works.orEmpty(),
            count = show?.collection?.worksCount,
            emptyMessage = "This collection has no works yet.",
            palette = palette,
            onOpenWork = onOpenWork
        )
        AO3CollectionSegment.Bookmarks -> workRows(
            rows = bookmarksPage?.works.orEmpty(),
            count = show?.collection?.bookmarksCount,
            emptyMessage = "This collection has no bookmarks yet.",
            palette = palette,
            onOpenWork = onOpenWork
        )
        AO3CollectionSegment.People -> peopleRows(peoplePage, palette)
    }
}

private fun androidx.compose.foundation.lazy.LazyListScope.workRows(
    rows: List<AO3WorkSummary>,
    count: Int?,
    emptyMessage: String,
    palette: SubjectPalette,
    onOpenWork: (AO3WorkSummary) -> Unit
) {
    if (rows.isEmpty()) {
        item { CollectionEmptyCard(emptyMessage) }
        return
    }

    item {
        SectionRuleHeader(
            title = "Recent",
            count = count,
            modifier = Modifier.padding(top = 18.dp)
        )
    }
    items(rows, key = { it.id }) { work ->
        Box(
            Modifier
                .padding(top = 8.dp)
                .padding(horizontal = SubjectMetrics.accountGutter)
        ) {
            SensitiveWorkRow(work = work, onOpenWork = onOpenWork)
            if (work.authors.joinToString(", ").trim().equals("Anonymous", ignoreCase = true)) {
                Text(
                    text = "ANON",
                    color = palette.accentOnFill,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = FontFamily.Monospace,
                    letterSpacing = 0.6.sp,
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(10.dp)
                        .background(palette.chipFill, RoundedCornerShape(50))
                        .border(0.5.dp, palette.chipStroke, RoundedCornerShape(50))
                        .padding(horizontal = 8.dp, vertical = 4.dp)
                        .semantics { contentDescription = "Anonymous in this collection" }
                )
            }
        }
    }
}

private fun androidx.compose.foundation.lazy.LazyListScope.peopleRows(
    page: AO3CollectionPeoplePage?,
    palette: SubjectPalette
) {
    val people = page?.people.orEmpty()
    if (people.isEmpty()) {
        item { CollectionEmptyCard("Nobody has joined this collection yet.") }
        return
    }

    item {
        SectionRuleHeader(
            title = "People",
            countText = "${people.size} on this page · page ${page?.currentPage ?: 1} of ${page?.totalPages ?: 1}",
            modifier = Modifier.padding(top = 18.dp)
        )
    }
    items(people, key = { it.id }) { person ->
        CollectionPersonRow(
            person = person,
            palette = palette,
            modifier = Modifier
                .padding(top = 8.dp)
                .padding(horizontal = SubjectMetrics.accountGutter)
        )
    }
}

@Composable
private fun CollectionPersonRow(
    person: AO3CollectionPerson,
    palette: SubjectPalette,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    Row(
        modifier = modifier
            .fillMaxWidth()
            .subjectPanel(cornerRadius = 16.dp)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(30.dp)
                .background(palette.chipFill, RoundedCornerShape(8.dp)),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = person.identity.displayName.take(1).uppercase(),
                color = palette.accent,
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold
            )
        }
        Text(
            text = person.identity.displayName,
            color = tokens.primaryInk,
            fontSize = 15.sp,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.weight(1f)
        )
        person.workCount?.let { count ->
            Text(
                text = "$count work${if (count == 1) "" else "s"}",
                color = tokens.secondaryInk,
                fontSize = 11.sp,
                fontWeight = FontWeight.Medium,
                fontFamily = FontFamily.Monospace
            )
        }
    }
}

@Composable
private fun CollectionEmptyCard(message: String) {
    Text(
        text = message,
        color = LocalKudosTokens.current.secondaryInk,
        fontSize = 12.5.sp,
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 14.dp)
            .padding(horizontal = SubjectMetrics.accountGutter)
            .subjectPanel()
            .padding(horizontal = 14.dp, vertical = 12.dp)
    )
}

@Composable
private fun CollectionFailureCard(
    message: String,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    Column(
        modifier = modifier
            .fillMaxWidth()
            .subjectPanel()
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text(
            text = "Couldn't load this collection",
            color = tokens.primaryInk,
            fontSize = 15.sp,
            fontWeight = FontWeight.SemiBold
        )
        Text(message, color = tokens.secondaryInk, fontSize = 12.5.sp)
        TextButton(onClick = onRetry, contentPadding = PaddingValues(0.dp)) {
            Text("Try Again", fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

private fun segmentRowsAreEmpty(
    segment: AO3CollectionSegment,
    worksPage: AO3SearchPage?,
    bookmarksPage: AO3SearchPage?,
    peoplePage: AO3CollectionPeoplePage?
): Boolean = when (segment) {
    AO3CollectionSegment.Works -> worksPage?.works.isNullOrEmpty()
    AO3CollectionSegment.Bookmarks -> bookmarksPage?.works.isNullOrEmpty()
    AO3CollectionSegment.People -> peoplePage?.people.isNullOrEmpty()
}

private fun collectionManageActions(
    show: AO3CollectionShow,
    slug: String
): List<AO3CollectionManageAction> = buildList {
    val root = "${AO3Constants.BASE_URL}/collections/$slug"
    if (show.isMaintainer) {
        add(AO3CollectionManageAction("Maintainers", show.dashboard.participantsUrl ?: "$root/participants"))
        add(AO3CollectionManageAction("Moderation", show.dashboard.itemsUrl ?: "$root/items"))
    }
    if (show.collection.viewerIsOwner) {
        add(AO3CollectionManageAction("Collection Settings", "$root/edit"))
    }
    if (show.isMaintainer) {
        show.dashboard.signUpsUrl?.let { add(AO3CollectionManageAction("Sign-ups", it)) }
        show.dashboard.assignmentsUrl?.let { add(AO3CollectionManageAction("Assignments", it)) }
    }
    show.dashboard.promptsUrl?.let { add(AO3CollectionManageAction("Prompts", it)) }
    show.dashboard.signUpsUrl?.let { add(AO3CollectionManageAction("Your Sign-up", it)) }
    if (show.collection.viewerIsOwner) {
        show.dashboard.challengeSettingsUrl?.let {
            add(AO3CollectionManageAction("Challenge Settings", it))
        }
    }
}

private data class AO3CollectionManageAction(val label: String, val url: String)

private enum class AO3CollectionSegment(val title: String) {
    Works("Works"),
    Bookmarks("Bookmarks"),
    People("People")
}

private sealed interface AO3CollectionDetailPhase {
    data object Idle : AO3CollectionDetailPhase
    data object Loading : AO3CollectionDetailPhase
    data object Loaded : AO3CollectionDetailPhase
    data class Failed(val message: String) : AO3CollectionDetailPhase
}
