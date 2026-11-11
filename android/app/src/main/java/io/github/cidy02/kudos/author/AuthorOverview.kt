package io.github.cidy02.kudos.author

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.NotificationsOff
import androidx.compose.material.icons.outlined.PanTool
import androidx.compose.material.icons.outlined.UnfoldMore
import androidx.compose.material.icons.outlined.VolumeOff
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.app.PrivacyRevealState
import io.github.cidy02.kudos.core.model.PrivacySettings
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.library.LibraryPrivacy
import io.github.cidy02.kudos.library.LibraryPrivacyVisibility
import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.author.*
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.WorkRowEnvironment
import io.github.cidy02.kudos.ui.components.hiddenMatureWorkSemantics
import io.github.cidy02.kudos.ui.subject.HomeStatusTray
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.RevealCapsule
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectChip
import io.github.cidy02.kudos.ui.subject.SubjectChipStyle
import io.github.cidy02.kudos.ui.subject.SubjectKicker
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.SubjectRemoteCoverCard
import io.github.cidy02.kudos.ui.subject.SubjectStateBadge
import io.github.cidy02.kudos.ui.subject.cardRow
import io.github.cidy02.kudos.ui.subject.compactCount
import io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale
import io.github.cidy02.kudos.ui.subject.subjectPanel

/** iOS `AO3WorksSort.mostKudos`: kudos, highest first. */
internal val AuthorMostKudosSort = AO3AuthorWorksSort(
    AO3AuthorWorksSortColumn.Kudos, AO3AuthorWorksSortDirection.Descending
)

/**
 * Where an overview's See All and count strip lead (iOS `dashboardDestination`): one of the full
 * lists Android already has. [view] is the route's word for the two that are a Works list set up
 * a particular way.
 */
enum class AuthorSeeAll(
    val label: String,
    val tab: AuthorTab,
    val scope: AO3AuthorWorksScope,
    val sort: AO3AuthorWorksSort?,
    val view: String?
) {
    Works("Works", AuthorTab.Works, AO3AuthorWorksScope.Works, null, null),
    Series("Series", AuthorTab.Series, AO3AuthorWorksScope.Works, null, null),
    Bookmarks("Bookmarks", AuthorTab.Bookmarks, AO3AuthorWorksScope.Works, null, null),
    Gifts("Gifts", AuthorTab.Works, AO3AuthorWorksScope.Gifts, null, "gifts"),
    MostKudos("Most Kudos", AuthorTab.Works, AO3AuthorWorksScope.Works, AuthorMostKudosSort, "kudos");

    companion object {
        fun fromView(value: String?): AuthorSeeAll? = entries.firstOrNull { it.view != null && it.view == value }
    }
}

/** iOS `AuthorProfileOverviewSection`: what the overview reads beyond the dashboard, and when. */
internal enum class AuthorOverviewSection { About, Popular, Series, Bookmarks }

internal sealed interface AuthorSectionLoad {
    object Idle : AuthorSectionLoad
    object Loading : AuthorSectionLoad
    object Loaded : AuthorSectionLoad
    data class Failed(val message: String) : AuthorSectionLoad
}

/** The rules of the overview that are not drawing: iOS `AuthorProfileSeeAll` and the model's `overview*`. */
internal object AuthorOverview {
    const val WorksPreviewLimit = 3
    const val SeriesPreviewLimit = 2
    const val BookmarksPreviewLimit = 2
    const val SeriesPartsLimit = 4

    fun isSeeAllShown(visibleCount: Int, totalCount: Int?, hasMore: Boolean): Boolean =
        hasMore || (totalCount != null && totalCount > visibleCount)

    private fun path(url: String): String? = AO3Constants.baseHttpUrl.resolve(url)?.encodedPath?.lowercase()

    /** iOS `listCount(for:route:)`: the figure AO3 prints in this list's dashboard link, matched by path. */
    fun listCount(header: AO3AuthorHeader, route: AO3AuthorRoute, target: AuthorSeeAll): Int? {
        val expected = path(
            when (target) {
                AuthorSeeAll.Works, AuthorSeeAll.MostKudos -> route.worksUrl
                AuthorSeeAll.Series -> route.seriesUrl
                AuthorSeeAll.Bookmarks -> route.bookmarksUrl
                AuthorSeeAll.Gifts -> AO3AuthorUrls.userWorksUrl(route.username, 1, route.pseud, AO3AuthorWorksScope.Gifts)
                    ?: return null
            }
        ) ?: return null
        return header.actions.asSequence().filter { path(it.url) == expected }.mapNotNull { it.listCount }.firstOrNull()
    }

    /** The dashboard's own rule for a remote row: fail closed until settings load (as `keptForPrivacy`). */
    fun workVisibility(
        work: AO3WorkSummary, loaded: Boolean, privacy: PrivacySettings, reveal: PrivacyRevealState, local: SavedWork?
    ): LibraryPrivacyVisibility = LibraryPrivacy.remoteRowVisibility(
        work.id.toString(), work.rating,
        if (loaded) local else null,
        if (loaded) privacy else LibraryPrivacy.UNREAD_SETTING,
        if (loaded) reveal else PrivacyRevealState()
    )

    fun workVisibility(work: AO3WorkSummary, env: WorkRowEnvironment?): LibraryPrivacyVisibility {
        val loaded = env != null && env.loaded
        return workVisibility(work, loaded, env?.privacy ?: LibraryPrivacy.UNREAD_SETTING,
            env?.revealState ?: PrivacyRevealState(), if (loaded) env!!.index.findMatch(work) else null)
    }

    /** iOS `latestWork`: the newest of the dashboard's recent works. */
    fun latest(header: AO3AuthorHeader): AO3WorkSummary? = header.recentWorks?.firstOrNull()

    /** iOS `overviewPopularWorks`: the kudos-sorted page, or, if it failed, the recent works by kudos. */
    fun popularWorks(popular: AO3SearchPage?, load: AuthorSectionLoad, header: AO3AuthorHeader): List<AO3WorkSummary> {
        popular?.works?.takeIf { it.isNotEmpty() }?.let { return it }
        if (load is AuthorSectionLoad.Failed) return header.recentWorks.orEmpty().sortedByDescending { it.kudos ?: 0 }
        return emptyList()
    }

    /** iOS `overviewSeries`: the dashboard's recent series, else the series page. */
    fun series(header: AO3AuthorHeader, page: AO3AuthorSeriesPage?): List<AO3AuthorSeriesSummary> =
        header.recentSeries ?: page?.series.orEmpty()

    /** iOS `overviewBookmarks`: the dashboard's recent bookmarks, else the bookmarks page. */
    fun bookmarks(header: AO3AuthorHeader, page: AO3AuthorBookmarksPage?): List<AO3AuthorBookmark> =
        header.recentBookmarks ?: page?.bookmarks.orEmpty()

    /** A preview's first [limit] cards; the ones a hidden rating conceals are left out, as in the lists. */
    fun <T> preview(
        items: List<T>, limit: Int, workOf: (T) -> AO3WorkSummary?,
        visibility: (AO3WorkSummary) -> LibraryPrivacyVisibility
    ): List<T> = items.take(limit).filter { item ->
        val work = workOf(item) ?: return@filter false
        visibility(work) != LibraryPrivacyVisibility.Hidden
    }
}

/** iOS `AuthorProfileOverviewHeader`: identity, the profile's own words, then Subscribe, Mute, Block. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun AuthorOverviewHeader(
    header: AO3AuthorHeader,
    route: AO3AuthorRoute,
    about: AO3AuthorAbout?,
    aboutLoad: AuthorSectionLoad,
    isOwnProfile: Boolean,
    subscriptionBusy: Boolean,
    moderationBusy: Boolean,
    onSubscription: (AO3AuthorSubscriptionForm) -> Unit,
    onModeration: (AO3AuthorWebAction) -> Unit,
    onSelectScope: (AO3AuthorRoute) -> Unit,
    onOpenWeb: (String) -> Unit,
    onRetryAbout: () -> Unit,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val mute = header.actions.firstOrNull { it.kind == AO3AuthorWebAction.Kind.Mute }
    val block = header.actions.firstOrNull { it.kind == AO3AuthorWebAction.Kind.Block }
    val showsAccountActions = !isOwnProfile && route.username.isNotBlank() &&
        !route.username.equals("orphan_account", ignoreCase = true)
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
            AO3AuthorAvatar(url = header.avatarUrl, name = route.displayName, size = 72.dp, isCircular = true)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                AuthorNameMenu(header, route, onSelectScope)
                val subtitle = listOfNotNull(
                    about?.joinedDate?.takeIf { it.isNotBlank() }?.let { "Joined $it" },
                    "${header.pseuds.size} pseuds".takeIf { header.pseuds.size > 1 },
                    "Pseud of ${route.username}".takeIf { route.pseud != null }
                ).joinToString(" · ")
                if (subtitle.isNotEmpty()) Text(subtitle, color = tokens.secondaryInk, fontSize = 15.sp, lineHeight = 21.sp)
            }
        }
        if (about != null) {
            if (about.profileTitle.isNotBlank()) {
                Text(about.profileTitle, color = tokens.primaryInk, fontSize = 15.sp, fontWeight = FontWeight.Medium)
            }
            about.userId?.let {
                Text("User ID  ${"%,d".format(it)}", color = tokens.secondaryInk, fontSize = 12.sp)
            }
            if (about.bioHtml.isNotBlank()) {
                io.github.cidy02.kudos.ui.components.AO3RichText(about.bioHtml, onOpenAo3 = onOpenWeb)
            }
        } else if (aboutLoad is AuthorSectionLoad.Failed) {
            ErrorStateCard("Couldn't load About", aboutLoad.message, primaryActionLabel = "Retry", onPrimaryAction = onRetryAbout)
        }
        if (showsAccountActions && (header.subscriptionForm != null || mute != null || block != null)) {
            val large = isAccessibilityFontScale()
            val subscribeButton: @Composable () -> Unit = {
                header.subscriptionForm?.let { form ->
                    Button(
                        onClick = { onSubscription(form) },
                        enabled = !subscriptionBusy,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = tokens.accent, contentColor = SubjectPalette.label(tokens.accent)),
                        contentPadding = PaddingValues(horizontal = 14.dp, vertical = 8.dp),
                        modifier = Modifier.heightIn(min = 48.dp).then(if (large) Modifier.fillMaxWidth() else Modifier)
                    ) {
                        Icon(
                            if (form.isSubscribed) Icons.Outlined.NotificationsOff else Icons.Outlined.Notifications,
                            null, Modifier.size(16.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(if (form.isSubscribed) "Unsubscribe" else "Subscribe", fontSize = 14.sp)
                    }
                }
            }
            val moderationButtons: @Composable () -> Unit = {
                mute?.let { AuthorModerationButton(it, Icons.Outlined.VolumeOff, !moderationBusy) { onModeration(it) } }
                block?.let { AuthorModerationButton(it, Icons.Outlined.PanTool, !moderationBusy) { onModeration(it) } }
            }
            if (large) Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                subscribeButton()
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { moderationButtons() }
            } else Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                subscribeButton()
                moderationButtons()
            }
        }
    }
}

/** iOS `pseudNameMenu`: the name, and beside it an up-down chevron that opens the pseuds. */
@Composable
private fun AuthorNameMenu(header: AO3AuthorHeader, route: AO3AuthorRoute, onSelect: (AO3AuthorRoute) -> Unit) {
    val tokens = LocalKudosTokens.current
    val showsChooser = header.pseuds.size > 1 || route.pseud != null
    var expanded by remember(route.username) { mutableStateOf(false) }
    val name: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit = {
        Text(route.displayName, color = tokens.primaryInk, fontSize = 28.sp, lineHeight = 34.sp,
            fontWeight = FontWeight.Bold, maxLines = 3, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f, fill = false))
    }
    if (!showsChooser) {
        Row { name() }
        return
    }
    Box {
        Row(
            Modifier.heightIn(min = 48.dp).clickable { expanded = true }
                .semantics { contentDescription = "${route.displayName}. Choose a pseud" },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(5.dp)
        ) {
            name()
            Icon(Icons.Outlined.UnfoldMore, null, tint = tokens.secondaryInk, modifier = Modifier.size(18.dp))
        }
        DropdownMenu(expanded, onDismissRequest = { expanded = false }, containerColor = tokens.cardFill) {
            val choices = listOf("All Pseuds" to AO3AuthorRoute(route.username)) + header.pseuds.map { it.name to it.route }
            choices.forEach { (label, choice) ->
                DropdownMenuItem(
                    text = { Text(label, color = tokens.primaryInk) },
                    leadingIcon = if (route.id == choice.id) { { Icon(Icons.Outlined.Check, "Selected") } } else null,
                    onClick = { expanded = false; if (route.id != choice.id) onSelect(choice) }
                )
            }
        }
    }
}

/** iOS `AuthorProfileCountStrip`: Works · Series · Bookmarks · Gifts, each a way into its full list. */
@Composable
internal fun AuthorCountStrip(header: AO3AuthorHeader, route: AO3AuthorRoute, onSeeAll: (AuthorSeeAll) -> Unit) {
    val tokens = LocalKudosTokens.current
    val items = listOf(AuthorSeeAll.Works, AuthorSeeAll.Series, AuthorSeeAll.Bookmarks, AuthorSeeAll.Gifts)
    val columns = if (isAccessibilityFontScale()) 2 else items.size
    Column(Modifier.fillMaxWidth().subjectPanel()) {
        items.chunked(columns).forEach { rowItems ->
            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
                rowItems.forEachIndexed { index, item ->
                    val count = AuthorOverview.listCount(header, route, item)
                    Column(
                        Modifier.weight(1f).heightIn(min = 48.dp).clickable { onSeeAll(item) }
                            .semantics { contentDescription = count?.let { "${it.compactCount()} ${item.label.lowercase()}" } ?: item.label }
                            .padding(vertical = 10.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text(count?.compactCount() ?: "—", color = tokens.primaryInk, fontSize = 20.sp,
                            fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace)
                        Text(item.label, color = tokens.secondaryInk, fontSize = 11.sp)
                    }
                    if (index < rowItems.lastIndex) {
                        Box(Modifier.width(0.5.dp).fillMaxHeight().padding(vertical = 8.dp).background(tokens.glassStroke(0.13)))
                    }
                }
            }
        }
    }
}

@Composable
private fun OverviewMessage(text: String) {
    Text(text, color = LocalKudosTokens.current.secondaryInk, fontSize = 15.sp, lineHeight = 21.sp,
        modifier = Modifier.fillMaxWidth().subjectPanel().padding(16.dp))
}

/** What a concealed card may draw: nothing that names or describes the work (the blur is not enough for TalkBack). */
internal fun AO3WorkSummary.redacted() = copy(
    title = "Hidden work", authors = emptyList(), fandoms = emptyList(), relationships = emptyList(),
    characters = emptyList(), freeforms = emptyList(), summary = "", chapters = "", updatedDate = "",
    wordCount = null, kudos = null, hits = null, comments = null, bookmarks = null, seriesTitle = null)

/** A remote work's card under the reader's privacy rule: omitted if hidden, blurred and tap-to-reveal if obscured. */
@Composable
private fun PrivateWorkFrame(
    work: AO3WorkSummary, env: WorkRowEnvironment?, onOpen: () -> Unit, modifier: Modifier = Modifier,
    content: @Composable (obscured: Boolean, shown: AO3WorkSummary) -> Unit
) {
    when (AuthorOverview.workVisibility(work, env)) {
        LibraryPrivacyVisibility.Hidden -> Unit
        LibraryPrivacyVisibility.Visible -> Box(modifier.clickable(onClick = onOpen)) { content(false, work) }
        LibraryPrivacyVisibility.Obscured -> Box(modifier.clickable {
            env?.let { e ->
                e.revealIds(buildSet {
                    e.index.findMatch(work)?.let { add(it.id) }
                    add(work.id.toString())
                })
            }
        }) { content(true, work.redacted()) }
    }
}

/**
 * The overview's sections after the header, in iOS's order: the strip, fandoms, Latest, Most Kudos,
 * Series, Bookmarks. A lazy section asks for its page only when it first scrolls into view
 * ([onVisible]); nothing here fetches.
 */
@OptIn(ExperimentalLayoutApi::class)
internal fun LazyListScope.authorOverviewItems(
    header: AO3AuthorHeader,
    route: AO3AuthorRoute,
    popular: AO3SearchPage?,
    series: AO3AuthorSeriesPage?,
    bookmarks: AO3AuthorBookmarksPage?,
    loads: Map<AuthorOverviewSection, AuthorSectionLoad>,
    env: WorkRowEnvironment?,
    onSeeAll: (AuthorSeeAll) -> Unit,
    onOpenWork: (AO3WorkSummary) -> Unit,
    onOpenSeries: (AO3AuthorSeriesSummary) -> Unit,
    onOpenFandom: (AO3AuthorFandom) -> Unit,
    onVisible: (AuthorOverviewSection) -> Unit,
    onRetry: (AuthorOverviewSection) -> Unit
) {
    fun load(section: AuthorOverviewSection) = loads[section] ?: AuthorSectionLoad.Idle
    val visibility: (AO3WorkSummary) -> LibraryPrivacyVisibility = { AuthorOverview.workVisibility(it, env) }

    item(key = "overview-strip") { AuthorCountStrip(header, route, onSeeAll) }

    if (header.fandoms.isNotEmpty()) item(key = "overview-fandoms") {
        val tokens = LocalKudosTokens.current
        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(header.fandoms, key = { it.url + it.name }) { fandom ->
                val hue = HomeFacts.coverHue(fandom.name)
                val dot = SubjectPalette.fromHue(hue, tokens.theme).accent
                Row(
                    Modifier.heightIn(min = 44.dp).clickable(enabled = fandom.url.isNotBlank()) { onOpenFandom(fandom) }
                        .background(tokens.glassFill(0.12), CircleShape).padding(horizontal = 12.dp, vertical = 7.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Box(Modifier.size(8.dp).background(dot, CircleShape))
                    Text(HomeFacts.bareFandomTitle(fandom.name), color = tokens.primaryInk, fontSize = 15.sp, maxLines = 1)
                    fandom.workCount?.let { Text(it.compactCount(), color = tokens.secondaryInk, fontSize = 15.sp) }
                }
            }
        }
    }

    // Latest
    item(key = "overview-latest") {
        val latest = AuthorOverview.latest(header)
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            when {
                latest != null -> {
                    if (visibility(latest) != LibraryPrivacyVisibility.Hidden) {
                        SectionRuleHeader("Latest", gutter = 0.dp)
                        PrivateWorkFrame(latest, env, { onOpenWork(latest) }) { obscured, shown -> AuthorLatestCard(shown, obscured) }
                    }
                }
                header.recentWorks == null -> {
                    SectionRuleHeader("Latest", gutter = 0.dp)
                    OverviewMessage("Couldn't read the latest work. Open Works to try again.")
                }
                else -> {
                    SectionRuleHeader("Latest", gutter = 0.dp)
                    OverviewMessage("No recent works visible on AO3.")
                }
            }
        }
    }

    // Most Kudos
    item(key = "overview-popular") {
        val popularLoad = load(AuthorOverviewSection.Popular)
        val all = AuthorOverview.popularWorks(popular, popularLoad, header)
        val shown = AuthorOverview.preview(all, AuthorOverview.WorksPreviewLimit, { it }, visibility)
        val total = AuthorOverview.listCount(header, route, AuthorSeeAll.Works)
        val hasMore = popular?.let { it.currentPage < it.totalPages } == true || all.size > AuthorOverview.WorksPreviewLimit
        val showSeeAll = AuthorOverview.isSeeAllShown(
            all.take(AuthorOverview.WorksPreviewLimit).size, total, hasMore)
        LaunchedEffect(Unit) { onVisible(AuthorOverviewSection.Popular) }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionRuleHeader("Most Kudos", count = total, gutter = 0.dp,
                onSeeAll = if (showSeeAll) { { onSeeAll(AuthorSeeAll.MostKudos) } } else null)
            when (popularLoad) {
                AuthorSectionLoad.Idle, AuthorSectionLoad.Loading -> OverviewMessage("Loading…")
                is AuthorSectionLoad.Failed -> {
                    ErrorStateCard("Couldn't load Most Kudos", popularLoad.message, primaryActionLabel = "Retry",
                        onPrimaryAction = { onRetry(AuthorOverviewSection.Popular) })
                    if (shown.isNotEmpty()) PopularShelf(shown, env, onOpenWork)
                }
                AuthorSectionLoad.Loaded ->
                    if (all.isEmpty()) OverviewMessage("No works visible on AO3.") else PopularShelf(shown, env, onOpenWork)
            }
        }
    }

    // Series
    item(key = "overview-series") {
        val seriesLoad = load(AuthorOverviewSection.Series)
        val all = AuthorOverview.series(header, series)
        val shown = all.take(AuthorOverview.SeriesPreviewLimit)
        val total = AuthorOverview.listCount(header, route, AuthorSeeAll.Series)
        val showSeeAll = AuthorOverview.isSeeAllShown(shown.size, total, all.size > shown.size)
        LaunchedEffect(Unit) { onVisible(AuthorOverviewSection.Series) }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionRuleHeader("Series", count = total, gutter = 0.dp,
                onSeeAll = if (showSeeAll) { { onSeeAll(AuthorSeeAll.Series) } } else null)
            if (seriesLoad is AuthorSectionLoad.Failed) {
                ErrorStateCard("Couldn't load Series", seriesLoad.message, primaryActionLabel = "Retry",
                    onPrimaryAction = { onRetry(AuthorOverviewSection.Series) })
            }
            when {
                header.recentSeries == null && all.isEmpty() -> {
                    if (seriesLoad == AuthorSectionLoad.Idle || seriesLoad == AuthorSectionLoad.Loading) OverviewMessage("Loading…")
                    else if (seriesLoad == AuthorSectionLoad.Loaded) OverviewMessage("No series visible on AO3.")
                }
                shown.isEmpty() -> OverviewMessage("No series visible on AO3.")
                else -> {
                    // Two to a row; one at the largest text sizes, as iOS.
                    shown.chunked(if (isAccessibilityFontScale()) 1 else 2).forEach { rowItems ->
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            rowItems.forEach { AuthorSeriesCard(it, Modifier.weight(1f)) { onOpenSeries(it) } }
                            if (rowItems.size == 1 && !isAccessibilityFontScale()) Spacer(Modifier.weight(1f))
                        }
                    }
                }
            }
        }
    }

    // Bookmarks
    item(key = "overview-bookmarks") {
        val bookmarksLoad = load(AuthorOverviewSection.Bookmarks)
        val all = AuthorOverview.bookmarks(header, bookmarks)
        val shown = AuthorOverview.preview(all, AuthorOverview.BookmarksPreviewLimit, { it.work }, visibility)
        val total = AuthorOverview.listCount(header, route, AuthorSeeAll.Bookmarks)
        val showSeeAll = AuthorOverview.isSeeAllShown(
            all.take(AuthorOverview.BookmarksPreviewLimit).size, total, all.size > AuthorOverview.BookmarksPreviewLimit)
        LaunchedEffect(Unit) { onVisible(AuthorOverviewSection.Bookmarks) }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SectionRuleHeader("Bookmarks", count = total, gutter = 0.dp,
                onSeeAll = if (showSeeAll) { { onSeeAll(AuthorSeeAll.Bookmarks) } } else null)
            if (bookmarksLoad is AuthorSectionLoad.Failed) {
                ErrorStateCard("Couldn't load Bookmarks", bookmarksLoad.message, primaryActionLabel = "Retry",
                    onPrimaryAction = { onRetry(AuthorOverviewSection.Bookmarks) })
            }
            when {
                header.recentBookmarks == null && all.isEmpty() -> {
                    if (bookmarksLoad == AuthorSectionLoad.Idle || bookmarksLoad == AuthorSectionLoad.Loading) OverviewMessage("Loading…")
                    else if (bookmarksLoad == AuthorSectionLoad.Loaded) OverviewMessage("No bookmarks visible on AO3.")
                }
                shown.isEmpty() -> OverviewMessage("No bookmarks visible on AO3.")
                else -> LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(shown, key = { it.id }) { bookmark ->
                        bookmark.work?.let { work ->
                            PrivateWorkFrame(work, env, { onOpenWork(work) }) { obscured, shown ->
                                AuthorBookmarkNoteCard(if (obscured) bookmark.copy(notes = "") else bookmark, shown, obscured)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PopularShelf(works: List<AO3WorkSummary>, env: WorkRowEnvironment?, onOpenWork: (AO3WorkSummary) -> Unit) {
    LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        items(works, key = { it.id }) { work ->
            PrivateWorkFrame(work, env, { onOpenWork(work) }) { obscured, shown ->
                SubjectRemoteCoverCard(shown, obscured = obscured)
            }
        }
    }
}

/** iOS `AuthorProfileLatestCard`: the newest work as one feature card. */
@Composable
private fun AuthorLatestCard(work: AO3WorkSummary, obscured: Boolean) {
    val tokens = LocalKudosTokens.current
    val palette = remember(work.fandoms, work.title, tokens.theme) {
        SubjectPalette.fromHue(HomeFacts.workHue(work.fandoms, work.title), tokens.theme)
    }
    val shape = RoundedCornerShape(SubjectMetrics.panelRadius)
    val kicker = listOfNotNull(
        HomeFacts.primaryFandom(work.fandoms),
        work.chapters.takeIf { it.isNotBlank() }?.let { if (it.contains("/")) "Ch. $it" else it }
    ).joinToString(" · ")
    val stats = listOfNotNull(
        work.updatedDate.takeIf { it.isNotBlank() }?.let { "Updated $it" },
        work.wordCount?.let { "%,d words".format(it) },
        work.kudos?.let { "♥ ${it.compactCount()}" },
        work.hits?.let { "${it.compactCount()} hits" }
    ).joinToString(" · ")
    Box(Modifier.fillMaxWidth()) {
        Column(
            Modifier.fillMaxWidth()
                .then(if (obscured) Modifier.blur(10.dp).hiddenMatureWorkSemantics(true) else Modifier)
                .background(tokens.theme.cardSurface, shape).background(palette.cardWash, shape)
                .border(0.5.dp, palette.cardBorder, shape).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Column(Modifier.weight(1f).padding(end = 44.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    if (kicker.isNotEmpty()) SubjectKicker(kicker, palette = palette)
                    Text(work.title, color = tokens.primaryInk, fontSize = 22.sp, lineHeight = 28.sp,
                        fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Serif,
                        maxLines = if (isAccessibilityFontScale()) Int.MAX_VALUE else 3, overflow = TextOverflow.Ellipsis)
                }
            }
            if (work.summary.isNotBlank()) {
                Text(work.summary, color = tokens.primaryInk.copy(alpha = 0.92f), fontSize = 15.sp, lineHeight = 21.sp,
                    maxLines = if (isAccessibilityFontScale()) Int.MAX_VALUE else 3, overflow = TextOverflow.Ellipsis)
            }
            HomeStatusTray(work.rating, work.categories, work.warnings, work.isComplete, tileSize = 24.dp, announces = !obscured)
            if (stats.isNotEmpty()) Text(stats, color = tokens.secondaryInk, fontSize = 12.sp, lineHeight = 17.sp)
        }
        if (!obscured) Box(
            Modifier.align(Alignment.TopEnd).padding(14.dp).size(40.dp).background(Color.White, CircleShape),
            contentAlignment = Alignment.Center
        ) { Icon(Icons.Filled.PlayArrow, null, tint = tokens.accent, modifier = Modifier.size(20.dp)) }
        else RevealCapsule(Modifier.align(Alignment.Center))
    }
}

/** iOS `AuthorProfileSeriesCard`: the series with a tile for each of its first parts. */
@Composable
private fun AuthorSeriesCard(
    series: AO3AuthorSeriesSummary, modifier: Modifier = Modifier, onClick: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    val palette = remember(series.fandoms, series.title, tokens.theme) {
        SubjectPalette.fromHue(HomeFacts.workHue(series.fandoms, series.title), tokens.theme)
    }
    val parts = (series.workCount ?: 1).coerceIn(1, AuthorOverview.SeriesPartsLimit)
    val meta = listOfNotNull(
        series.workCount?.let { if (it == 1) "1 part" else "$it parts" },
        series.words?.let { "%,d words".format(it) },
        if (series.isComplete == true) "complete" else series.dateUpdated.takeIf { it.isNotBlank() }
    ).joinToString(" · ")
    Column(
        modifier.subjectPanel().clickable(onClick = onClick).padding(12.dp)
            .semantics(mergeDescendants = true) { contentDescription = series.title },
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            for (index in 1..parts) {
                val tile = SubjectPalette.fromHue(HomeFacts.coverHue("${series.title}#$index"), tokens.theme)
                Box(
                    Modifier.weight(1f).heightIn(min = 54.dp).background(tile.cardWash, RoundedCornerShape(5.dp)),
                    contentAlignment = Alignment.BottomStart
                ) {
                    Text("$index", color = tokens.primaryInk.copy(alpha = 0.92f), fontSize = 12.sp,
                        fontWeight = FontWeight.Bold, modifier = Modifier.padding(start = 5.dp, bottom = 3.dp))
                }
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
            HomeFacts.primaryFandom(series.fandoms)?.let {
                Text(it.uppercase(), color = palette.accent, fontSize = 10.sp, fontWeight = FontWeight.SemiBold,
                    letterSpacing = 0.6.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Text(series.title, color = tokens.primaryInk, fontSize = 17.sp, lineHeight = 22.sp,
                fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Serif, maxLines = 3, overflow = TextOverflow.Ellipsis)
            if (meta.isNotEmpty()) Text(meta, color = tokens.secondaryInk, fontSize = 12.sp, lineHeight = 17.sp)
        }
    }
}

/** iOS `AuthorProfileBookmarkNoteCard`: the bookmark's note, then the work it is about. */
@Composable
private fun AuthorBookmarkNoteCard(bookmark: AO3AuthorBookmark, work: AO3WorkSummary, obscured: Boolean) {
    val tokens = LocalKudosTokens.current
    val palette = remember(work.fandoms, work.title, tokens.theme) {
        SubjectPalette.fromHue(HomeFacts.workHue(work.fandoms, work.title), tokens.theme)
    }
    val meta = listOfNotNull(
        work.authors.firstOrNull()?.takeIf { it.isNotBlank() },
        HomeFacts.primaryFandom(work.fandoms),
        work.wordCount?.let { "%,d words".format(it) }
    ).joinToString(" · ")
    Box {
        Column(
            Modifier.width(262.dp)
                .then(if (obscured) Modifier.blur(10.dp).hiddenMatureWorkSemantics(true) else Modifier)
                .subjectPanel().padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            if (bookmark.notes.isNotBlank()) {
                Text("“${bookmark.notes.trim()}”", color = tokens.primaryInk, fontSize = 16.sp, lineHeight = 22.sp,
                    fontFamily = FontFamily.Serif, fontStyle = FontStyle.Italic, maxLines = 6, overflow = TextOverflow.Ellipsis)
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.size(28.dp, 38.dp).background(palette.cardWash, RoundedCornerShape(4.dp)))
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(work.title, color = tokens.primaryInk, fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
                            maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                        if (bookmark.isRecommendation) SubjectStateBadge("Rec", palette.accent)
                    }
                    if (meta.isNotEmpty()) Text(meta, color = tokens.secondaryInk, fontSize = 12.sp, maxLines = 1,
                        overflow = TextOverflow.Ellipsis)
                }
            }
        }
        if (obscured) RevealCapsule(Modifier.align(Alignment.Center))
    }
}
