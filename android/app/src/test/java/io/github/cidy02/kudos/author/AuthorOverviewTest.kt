package io.github.cidy02.kudos.author

import android.app.Application
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import io.github.cidy02.kudos.app.PrivacyRevealState
import io.github.cidy02.kudos.app.Routes
import io.github.cidy02.kudos.core.model.MatureContentMode
import io.github.cidy02.kudos.core.model.PrivacySettings
import io.github.cidy02.kudos.library.LibraryPrivacyVisibility
import io.github.cidy02.kudos.network.ao3.author.*
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** A-468: the author profile as one overview page (iOS T-468). */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h2000dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class AuthorOverviewTest {
    @get:Rule val compose = createComposeRule()

    private val route = AO3AuthorRoute("Avery")
    private val base = "https://archiveofourown.org/users/Avery"

    private fun work(id: Long, title: String, rating: String = "General Audiences", kudos: Int = 10) = AO3WorkSummary(
        id = id, title = title, authors = listOf("Avery"), fandoms = listOf("Star Wars"), rating = rating,
        warnings = emptyList(), categories = emptyList(), kudos = kudos)

    private fun series(id: Long, title: String) = AO3AuthorSeriesSummary(
        id = id, title = title, creators = listOf("Avery"), fandoms = listOf("Star Wars"), summary = "",
        words = 1000, workCount = 3, dateUpdated = "2026-01-01", isComplete = false, url = "https://archiveofourown.org/series/$id")

    private fun bookmark(id: Long, work: AO3WorkSummary) = AO3AuthorBookmark(
        id = id, work = work, notes = "Note for ${work.title}", tags = emptyList(),
        isRecommendation = false, isPrivate = false, date = "2026-01-01")

    private val mute = AO3AuthorWebAction("Mute", "$base/muted/confirm_mute", AO3AuthorWebAction.Kind.Mute)
    private val block = AO3AuthorWebAction("Block", "$base/blocked/confirm_block", AO3AuthorWebAction.Kind.Block)
    private val subscribe = AO3AuthorSubscriptionForm("Subscribe", "$base/subscriptions", emptyList(), "token", base)

    private fun header(
        recentWorks: List<AO3WorkSummary>? = listOf(work(1, "Latest Story")),
        recentSeries: List<AO3AuthorSeriesSummary>? = listOf(series(7, "First Series"), series(8, "Second Series")),
        recentBookmarks: List<AO3AuthorBookmark>? = listOf(bookmark(1, work(20, "Bookmarked One")), bookmark(2, work(21, "Bookmarked Two")))
    ) = AO3AuthorHeader(
        username = "Avery", displayName = "Avery", avatarUrl = null, userId = null, pseuds = emptyList(),
        fandoms = listOf(AO3AuthorFandom("Star Wars", 12, "https://archiveofourown.org/tags/Star%20Wars/works")),
        subscriptionForm = subscribe,
        actions = listOf(
            AO3AuthorWebAction("Works (12)", "$base/works", AO3AuthorWebAction.Kind.Works),
            AO3AuthorWebAction("Series (3)", "$base/series", AO3AuthorWebAction.Kind.Other),
            AO3AuthorWebAction("Bookmarks (5)", "$base/bookmarks", AO3AuthorWebAction.Kind.Other),
            AO3AuthorWebAction("Gifts (2)", "$base/gifts", AO3AuthorWebAction.Kind.Other),
            mute, block),
        recentWorks = recentWorks, recentSeries = recentSeries, recentBookmarks = recentBookmarks)

    private val seeAlls = mutableListOf<AuthorSeeAll>()
    private val moderations = mutableListOf<AO3AuthorWebAction>()
    private val subscriptions = mutableListOf<AO3AuthorSubscriptionForm>()

    private fun showItems(
        header: AO3AuthorHeader,
        popular: AO3SearchPage? = AO3SearchPage(listOf(work(30, "Kudos King", kudos = 900)), 1, 4),
        popularLoad: AuthorSectionLoad = AuthorSectionLoad.Loaded
    ) {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                LazyColumn {
                    authorOverviewItems(
                        header = header, route = route, popular = popular, series = null, bookmarks = null,
                        loads = mapOf(AuthorOverviewSection.Popular to popularLoad),
                        env = null, // before settings load: the default privacy rule, fail closed
                        onSeeAll = { seeAlls += it }, onOpenWork = {}, onOpenSeries = {}, onOpenFandom = {},
                        onVisible = {}, onRetry = {})
                }
            }
        }
        compose.waitForIdle()
    }

    private fun top(text: String) = compose.onNodeWithText(text, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot.top
    private fun left(text: String) = compose.onNodeWithText(text, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot.left

    @Test fun sectionsAreInIosOrder_stripThenLatestMostKudosSeriesBookmarks() {
        showItems(header())
        assertTrue(left("Works") < left("Series"))
        assertTrue(left("Series") < left("Bookmarks"))
        assertTrue(left("Bookmarks") < left("Gifts"))
        val order = listOf("LATEST", "MOST KUDOS", "SERIES", "BOOKMARKS").map(::top)
        assertEquals(order.sorted(), order)
        assertTrue("Strip comes before Latest", top("Works") < top("LATEST"))
        assertTrue("Fandom chips follow the strip", top("Works") < top("Star Wars"))
        assertTrue(top("Star Wars") < top("LATEST"))
    }

    @Test fun seeAllAndTheStripLeadToTheExistingFullLists() {
        showItems(header())
        compose.onNodeWithContentDescription("See all Most Kudos", useUnmergedTree = true).performClick()
        compose.onNodeWithContentDescription("See all Series", useUnmergedTree = true).performClick()
        compose.onNodeWithContentDescription("See all Bookmarks", useUnmergedTree = true).performClick()
        listOf("12 works", "3 series", "5 bookmarks", "2 gifts").forEach {
            compose.onNodeWithContentDescription(it).performClick()
        }
        assertEquals(listOf(AuthorSeeAll.MostKudos, AuthorSeeAll.Series, AuthorSeeAll.Bookmarks,
            AuthorSeeAll.Works, AuthorSeeAll.Series, AuthorSeeAll.Bookmarks, AuthorSeeAll.Gifts), seeAlls)
    }

    @Test fun seeAllTargetsMapToTheExistingListsAndRoutes() {
        assertEquals(AuthorTab.Series, AuthorSeeAll.Series.tab)
        assertEquals(AuthorTab.Bookmarks, AuthorSeeAll.Bookmarks.tab)
        assertEquals(AuthorTab.Works, AuthorSeeAll.Works.tab)
        assertEquals(AO3AuthorWorksScope.Gifts, AuthorSeeAll.Gifts.scope)
        assertEquals(AuthorTab.Works, AuthorSeeAll.Gifts.tab)
        assertEquals(AuthorMostKudosSort, AuthorSeeAll.MostKudos.sort)
        assertEquals(AO3AuthorWorksSortColumn.Kudos, AuthorSeeAll.MostKudos.sort?.column)
        assertEquals(AuthorSeeAll.MostKudos, AuthorSeeAll.fromView("kudos"))
        assertEquals(AuthorSeeAll.Gifts, AuthorSeeAll.fromView("gifts"))
        assertNull(AuthorSeeAll.fromView(null))
        assertNull(AuthorSeeAll.fromView("works"))
        assertEquals("author-profile/Avery?tab=Series", Routes.authorProfile(route, AuthorSeeAll.Series.tab, AuthorSeeAll.Series.view))
        assertEquals("author-profile/Avery?tab=Works&view=kudos",
            Routes.authorProfile(route, AuthorSeeAll.MostKudos.tab, AuthorSeeAll.MostKudos.view))
        assertEquals("author-profile/Avery?tab=Works&view=gifts",
            Routes.authorProfile(route, AuthorSeeAll.Gifts.tab, AuthorSeeAll.Gifts.view))
        assertEquals("author-profile/Avery", Routes.authorProfile(route))
    }

    @Test fun seeAllIsOfferedOnlyWhenThereIsMoreThanThePreview() {
        assertTrue(AuthorOverview.isSeeAllShown(3, 12, false))
        assertTrue(AuthorOverview.isSeeAllShown(3, null, true))
        assertTrue(!AuthorOverview.isSeeAllShown(3, 3, false))
        assertTrue(!AuthorOverview.isSeeAllShown(2, null, false))
        val items = header().let { h -> listOf(AuthorSeeAll.Works, AuthorSeeAll.Series, AuthorSeeAll.Bookmarks, AuthorSeeAll.Gifts)
            .map { AuthorOverview.listCount(h, route, it) } }
        assertEquals(listOf(12, 3, 5, 2), items)
        assertEquals(12, AuthorOverview.listCount(header(), route, AuthorSeeAll.MostKudos))
        assertNull("Another account's link is not this route's", AuthorOverview.listCount(header(), AO3AuthorRoute("Other"), AuthorSeeAll.Works))
    }

    @Test fun headerButtonRowIsSubscribeMuteBlock_andBlockOnlyAsksAtTheTap() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                AuthorOverviewHeader(
                    header = header(), route = route, about = null, aboutLoad = AuthorSectionLoad.Idle,
                    isOwnProfile = false, subscriptionBusy = false, moderationBusy = false,
                    onSubscription = { subscriptions += it }, onModeration = { moderations += it },
                    onSelectScope = {}, onOpenWeb = {}, onRetryAbout = {})
            }
        }
        val order = listOf("Subscribe", "Mute", "Block").map { left(it) }
        assertEquals(order.sorted(), order)
        assertTrue("Nothing is sent before a tap", moderations.isEmpty() && subscriptions.isEmpty())
        compose.onNodeWithText("Block").performClick()
        // The screen turns this into AO3's own confirm dialog; the header itself submits nothing.
        assertEquals(listOf(block), moderations)
        compose.onNodeWithText("Mute").performClick()
        assertEquals(listOf(block, mute), moderations)
        assertTrue(subscriptions.isEmpty())
    }

    @Test fun yourOwnProfileOffersNoSubscribeMuteOrBlock() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                AuthorOverviewHeader(
                    header = header(), route = route, about = null, aboutLoad = AuthorSectionLoad.Idle,
                    isOwnProfile = true, subscriptionBusy = false, moderationBusy = false,
                    onSubscription = {}, onModeration = {}, onSelectScope = {}, onOpenWeb = {}, onRetryAbout = {})
            }
        }
        compose.onAllNodesWithText("Block").assertCountEquals(0)
        compose.onAllNodesWithText("Subscribe").assertCountEquals(0)
    }

    // --- Privacy: every section that shows works applies the lists' rule (default: Hide mature, blur unrated).

    private val concealed = "Hidden mature work. Activate to reveal."

    @Test fun latestOmitsAHiddenRatingAndKeepsASafeOne() {
        showItems(header(recentWorks = listOf(work(1, "Explicit Latest", rating = "Explicit"))))
        compose.onAllNodesWithText("Explicit Latest", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithText("LATEST", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun latestBlursAnUnratedWork() {
        showItems(header(recentWorks = listOf(work(1, "Unrated Latest", rating = ""))))
        compose.onAllNodesWithText("Unrated Latest", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithContentDescription(concealed, useUnmergedTree = true).assertCountEquals(1)
    }

    @Test fun latestShowsASafeWork() {
        showItems(header())
        compose.onAllNodesWithText("Latest Story", useUnmergedTree = true).assertCountEquals(1)
    }

    @Test fun mostKudosOmitsHiddenAndBlursUnratedButShowsSafeCovers() {
        val page = AO3SearchPage(listOf(
            work(30, "Explicit Cover", rating = "Explicit", kudos = 900),
            work(31, "Unrated Cover", rating = "", kudos = 800),
            work(32, "Safe Cover", kudos = 700)), 1, 1)
        showItems(header(recentWorks = null), popular = page)
        compose.onAllNodesWithText("Explicit Cover", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithText("Unrated Cover", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithText("Safe Cover", useUnmergedTree = true).assertCountEquals(1)
        compose.onAllNodesWithContentDescription(concealed, useUnmergedTree = true).assertCountEquals(1)
    }

    @Test fun mostKudosFallsBackToRecentWorksByKudosWhenItsPageFailed_stillUnderThePrivacyRule() {
        val recent = listOf(work(1, "Low", kudos = 1), work(2, "Hidden High", rating = "Explicit", kudos = 99), work(3, "Mid", kudos = 5))
        showItems(header(recentWorks = recent), popular = null, popularLoad = AuthorSectionLoad.Failed("Offline"))
        compose.onAllNodesWithText("Hidden High", useUnmergedTree = true).assertCountEquals(0)
        assertTrue("Most kudos first", left("Mid") < left("Low"))
    }

    @Test fun bookmarksOmitHiddenAndBlurUnratedButShowSafeNoteCards() {
        val h = header(recentBookmarks = listOf(
            bookmark(1, work(40, "Explicit Bookmark", rating = "Explicit")),
            bookmark(2, work(41, "Unrated Bookmark", rating = "")),
            bookmark(3, work(42, "Safe Bookmark"))))
        showItems(h)
        compose.onAllNodesWithText("Explicit Bookmark", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithText("Unrated Bookmark", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithText("Safe Bookmark", useUnmergedTree = true).assertCountEquals(1)
    }

    @Test fun previewDropsHiddenWorksAfterTakingTheLimit_asIosDoes_andJudgesWithTheListsRule() {
        val hide = PrivacySettings(hideMatureContent = true, matureContentMode = MatureContentMode.Hide)
        val obscure = PrivacySettings(hideMatureContent = true, matureContentMode = MatureContentMode.Obscure)
        val explicit = work(1, "E", rating = "Explicit")
        val safe = work(2, "S")
        val works = listOf(explicit, safe, work(3, "T"), work(4, "U"))
        fun visibility(privacy: PrivacySettings) = { w: AO3WorkSummary ->
            AuthorOverview.workVisibility(w, loaded = true, privacy = privacy, reveal = PrivacyRevealState(), local = null)
        }
        assertEquals(listOf("S", "T"), AuthorOverview.preview(works, 3, { it }, visibility(hide)).map { it.title })
        assertEquals(listOf("E", "S", "T"), AuthorOverview.preview(works, 3, { it }, visibility(obscure)).map { it.title })
        assertEquals(LibraryPrivacyVisibility.Hidden, visibility(hide)(explicit))
        assertEquals(LibraryPrivacyVisibility.Obscured, visibility(obscure)(explicit))
        // Before settings load, an unread rule hides rather than shows.
        assertEquals(LibraryPrivacyVisibility.Hidden,
            AuthorOverview.workVisibility(explicit, loaded = false, privacy = PrivacySettings(hideMatureContent = false),
                reveal = PrivacyRevealState(revealAll = true), local = null))
        // A work with no detail is not a card.
        assertTrue(AuthorOverview.preview(listOf(bookmark(1, work(9, "B")).copy(work = null)), 2, { it.work }, visibility(obscure)).isEmpty())
    }

    @Test fun overviewReadsTheDashboardsRecentGroupsBeforeAnyOtherPage() {
        val h = header()
        assertNotNull(h.recentSeries)
        assertEquals(listOf("First Series", "Second Series"), AuthorOverview.series(h, null).map { it.title })
        val withoutRecents = header(recentSeries = null, recentBookmarks = null)
        assertTrue(AuthorOverview.series(withoutRecents, null).isEmpty())
        assertEquals("Latest Story", AuthorOverview.latest(h)?.title)
        assertNull(AuthorOverview.latest(header(recentWorks = null)))
    }
}
