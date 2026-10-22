package io.github.cidy02.kudos.app

import android.content.Context
import androidx.navigation.compose.composable
import androidx.navigation.createGraph
import androidx.navigation.NavType
import androidx.navigation.navArgument
import androidx.navigation.testing.TestNavHostController
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.network.ao3.account.AO3ChallengeKind
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Empirical check of a specific claim from Grok's T-90 review: that
 * AndroidX Navigation already URL-decodes a string route argument when
 * populating [androidx.navigation.NavBackStackEntry.arguments], which would
 * make Routes.routeArg's own URLDecoder.decode call a second, corrupting
 * decode pass. Verified here against a real NavController/NavGraph
 * (Robolectric), not just reasoned about - this is exactly the kind of
 * navigation-internals behavior worth confirming rather than assuming.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class RoutesNavigationTest {
    private lateinit var navController: TestNavHostController

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        navController = TestNavHostController(context)
        navController.navigatorProvider.addNavigator(androidx.navigation.compose.ComposeNavigator())
        navController.graph = navController.createGraph(startDestination = "start") {
            composable("start") { }
            composable(Routes.AuthorAbout, arguments = listOf(Routes.navArgOf("authorUsername"))) { }
            composable(Routes.Reader, arguments = listOf(Routes.navArgOf("workId"))) { }
            composable(Routes.WorkDetail, arguments = listOf(Routes.navArgOf("workSource"))) { }

            composable(
                Routes.AuthorWorks,
                arguments = listOf(Routes.navArgOf("authorName"))
            ) { }
            composable(
                Routes.AccountList,
                arguments = listOf(Routes.navArgOf("listType"))
            ) { }
            composable(Routes.AO3ChallengeSettings, arguments = listOf(
                Routes.navArgOf("collectionSlug"), Routes.navArgOf("collectionTitle"),
                navArgument("owner") { type = NavType.BoolType; defaultValue = false },
                navArgument("kind") { type = NavType.StringType; nullable = true; defaultValue = null }
            )) { }
            composable(Routes.AO3ChallengeAssignments, arguments = listOf(
                Routes.navArgOf("collectionSlug"),
                navArgument("collectionTitle") { type = NavType.StringType; defaultValue = "" },
                navArgument("owner") { type = NavType.BoolType; defaultValue = false },
                navArgument("maintainer") { type = NavType.BoolType; defaultValue = false },
                navArgument("closed") { type = NavType.StringType; defaultValue = "unknown" },
                navArgument("kind") { type = NavType.StringType; nullable = true; defaultValue = null }
            )) { }
            composable(Routes.AO3ChallengeSignUps, arguments = listOf(
                Routes.navArgOf("collectionSlug"),
                navArgument("collectionTitle") { type = NavType.StringType; defaultValue = "" },
                navArgument("owner") { type = NavType.BoolType; defaultValue = false },
                navArgument("maintainer") { type = NavType.BoolType; defaultValue = false },
                navArgument("kind") { type = NavType.StringType; nullable = true; defaultValue = null }
            )) { }
            composable(Routes.AO3PromptMeme, arguments = listOf(
                Routes.navArgOf("collectionSlug"),
                navArgument("collectionTitle") { type = NavType.StringType; defaultValue = "" },
                navArgument("owner") { type = NavType.BoolType; defaultValue = false },
                navArgument("kind") { type = NavType.StringType; nullable = true; defaultValue = null }
            )) { }
            composable(Routes.AO3TagSet, arguments = listOf(
                navArgument("tagSetId") { type = NavType.IntType },
                navArgument("tagSetTitle") { type = NavType.StringType; defaultValue = "" },
                navArgument("moderator") { type = NavType.BoolType; defaultValue = false }
            )) { }
            composable(Routes.AO3CollectionModeration, arguments = listOf(
                Routes.navArgOf("collectionSlug"), Routes.navArgOf("collectionTitle"),
                navArgument("owner") { type = NavType.BoolType; defaultValue = false }
            )) { }
            composable(Routes.AO3CollectionItems, arguments = listOf(
                Routes.navArgOf("collectionSlug"), Routes.navArgOf("collectionTitle"),
                navArgument("tab") { type = NavType.StringType; nullable = true; defaultValue = null }
            )) { }
            composable(Routes.BrowseWorks, arguments = listOf(
                Routes.navArgOf("fandomName"),
                navArgument("fandoms") { type = NavType.StringType; nullable = true; defaultValue = null }
            )) { }
            composable(Routes.Comments, arguments = listOf(
                Routes.navArgOf("commentWorkId"),
                navArgument(Routes.ARG_COMMENT_FOCUSED_ID) { type = NavType.StringType; nullable = true; defaultValue = null },
                navArgument("chapterPosition") { type = NavType.StringType; nullable = true; defaultValue = null },
                navArgument("compose") { type = NavType.BoolType; defaultValue = false }
            )) { }
        }
    }

    @Test fun dashboardAboutKeepsAccountAndPseudThroughNativeNavigation() {
        val author = io.github.cidy02.kudos.network.ao3.author.AO3AuthorRoute("Avery_Archive", "A+B")
        navController.navigate(Routes.authorAbout(author))
        val entry = navController.currentBackStackEntry!!
        assertEquals(Routes.AuthorAbout, entry.destination.route)
        val decoded = io.github.cidy02.kudos.network.ao3.author.AO3AuthorRoute.fromByline(Routes.routeArg(entry, "authorUsername")!!)
        assertEquals(author, decoded)
        assertEquals("About", Routes.titleFor(entry.destination.route))
        org.junit.Assert.assertTrue(Routes.hidesTabBar(entry.destination.route))
    }

    @Test fun familyRouteKeepsEverySiblingAndSingleTagRoutesStillWork() {
        val names = listOf("Doctor Who (2005)", "A+B / 日本語 & 100%")
        navController.navigate(Routes.browseWorks("Doctor Who", names))
        val entry = navController.currentBackStackEntry!!
        assertEquals("Doctor Who", Routes.routeArg(entry, "fandomName"))
        assertEquals(names, kotlinx.serialization.json.Json.decodeFromString<List<String>>(Routes.routeArg(entry, "fandoms")!!))
        navController.navigate(Routes.browseWorks("A+B"))
        assertEquals("A+B", Routes.routeArg(navController.currentBackStackEntry!!, "fandomName"))
        org.junit.Assert.assertNull(Routes.routeArg(navController.currentBackStackEntry!!, "fandoms"))
    }

    @Test
    fun authorNameWithPlusAndSpecialCharactersRoundTripsThroughARealNavController() {
        val authorName = "A+B \"Quoted\" Author/Slash:Colon"
        navController.navigate(Routes.authorWorks(authorName))

        val readBack = Routes.routeArg(navController.currentBackStackEntry!!, "authorName")

        assertEquals(authorName, readBack)
    }

    @Test
    fun accountListCollectionTypeRoundTripsThroughARealNavController() {
        val type = io.github.cidy02.kudos.account.AccountListType.Collection(
            name = "weird:name/with-slash+plus",
            displayTitle = "Title: With a Colon / Slash + Plus"
        )
        navController.navigate(Routes.accountList(NavArgCodecs.encodeAccountListType(type)))

        val encoded = Routes.routeArg(navController.currentBackStackEntry!!, "listType")
        val decoded = encoded?.let(NavArgCodecs::decodeAccountListType)

        assertEquals(type, decoded)
    }

    @Test fun moderationCarriesOwnerAndRecentlyDecidedCarriesApprovedWithoutChangingListDefault() {
        navController.navigate(Routes.ao3CollectionModeration("winter_exchange", "Winter + Letters / 2026", true))
        val moderation = navController.currentBackStackEntry!!
        assertEquals(Routes.AO3CollectionModeration, moderation.destination.route)
        assertEquals("Winter + Letters / 2026", Routes.routeArg(moderation, "collectionTitle"))
        assertEquals(true, moderation.arguments?.getBoolean("owner"))
        assertEquals(true, Routes.hasSubjectHeader(moderation.destination.route))
        assertEquals(true, Routes.hidesTabBar(moderation.destination.route))
        navController.navigate(Routes.ao3CollectionItems("winter_exchange", "Winter + Letters / 2026", "approved"))
        assertEquals("approved", Routes.routeArg(navController.currentBackStackEntry!!, "tab"))
        navController.navigate(Routes.ao3CollectionItems("winter_exchange", "Winter + Letters / 2026"))
        assertEquals(null, Routes.routeArg(navController.currentBackStackEntry!!, "tab"))
    }

    @Test fun challengeSettingsArgumentsRoundTripWithOwnerAndSubjectChrome() {
        navController.navigate(Routes.ao3ChallengeSettings("snow/letters", "Winter + Letters / 2026", true))
        val entry = navController.currentBackStackEntry!!
        assertEquals(Routes.AO3ChallengeSettings, entry.destination.route)
        assertEquals("snow/letters", Routes.routeArg(entry, "collectionSlug"))
        assertEquals("Winter + Letters / 2026", Routes.routeArg(entry, "collectionTitle"))
        assertEquals(true, entry.arguments?.getBoolean("owner"))
        assertEquals("Challenge", Routes.titleFor(entry.destination.route))
        assertEquals(true, Routes.hasSubjectHeader(entry.destination.route))
        assertEquals(true, Routes.hidesTabBar(entry.destination.route))
    }

    @Test fun knownChallengeKindRoundTripsOnEverySettingsRoute() {
        val kind = AO3ChallengeKind.PromptMeme
        val routes = listOf(
            Routes.ao3ChallengeSettings("summer_meme", "Summer", true, kind),
            Routes.ao3ChallengeAssignments("summer_meme", "Summer", true, true, false, kind),
            Routes.ao3ChallengeSignUps("summer_meme", "Summer", true, true, kind),
            Routes.ao3PromptMeme("summer_meme", "Summer", true, kind)
        )
        for (route in routes) {
            navController.navigate(route)
            val entry = navController.currentBackStackEntry!!
            assertEquals("prompt_meme", Routes.routeArg(entry, "kind"))
            assertEquals(AO3ChallengeKind.PromptMeme, Routes.challengeKindFromRoute(Routes.routeArg(entry, "kind")))
        }
        navController.navigate(Routes.ao3ChallengeSettings("summer_meme", "Summer", true))
        assertEquals(null, Routes.routeArg(navController.currentBackStackEntry!!, "kind"))
    }

    @Test fun tagSetUsesItsOwnNumberTitleAndModeratorFlagWithSubjectChrome() {
        navController.navigate(Routes.ao3TagSet(44, "Summer + Postcards / 2026", true))
        val entry = navController.currentBackStackEntry!!
        assertEquals(Routes.AO3TagSet, entry.destination.route)
        assertEquals(44, entry.arguments?.getInt("tagSetId"))
        assertEquals("Summer + Postcards / 2026", Routes.routeArg(entry, "tagSetTitle"))
        assertEquals(true, entry.arguments?.getBoolean("moderator"))
        assertEquals("Tag set", Routes.titleFor(entry.destination.route))
        assertEquals(true, Routes.hasSubjectHeader(entry.destination.route))
        assertEquals(true, Routes.hidesTabBar(entry.destination.route))
        navController.navigate(Routes.ao3TagSet(43))
        assertEquals(false, navController.currentBackStackEntry!!.arguments?.getBoolean("moderator"))
        assertEquals("", Routes.routeArg(navController.currentBackStackEntry!!, "tagSetTitle"))
    }

    @Test fun messageCreatorOpensNativeCommentsWithComposerRequested() {
        navController.navigate(Routes.comments(123, composes = true))
        assertEquals("123", Routes.routeArg(navController.currentBackStackEntry!!, "commentWorkId"))
        assertEquals(true, navController.currentBackStackEntry!!.arguments?.getBoolean("compose"))
        navController.navigate(Routes.comments(124))
        assertEquals(false, navController.currentBackStackEntry!!.arguments?.getBoolean("compose"))
    }

    @Test fun continueReadingReturnsToTheSameReaderAndAnotherWorkStillOpensItsOwn() {
        navController.navigate(Routes.reader("one"))
        val original = navController.currentBackStackEntry!!.id
        navController.navigate(Routes.workDetail("local-one"))
        navController.openReaderFromWorkDetail("one")
        assertEquals(original, navController.currentBackStackEntry!!.id)
        assertEquals("start", navController.previousBackStackEntry!!.destination.route)
        navController.navigate(Routes.workDetail("local-two"))
        navController.openReaderFromWorkDetail("two")
        assertEquals("two", Routes.routeArg(navController.currentBackStackEntry!!, "workId"))
        assertEquals(Routes.WorkDetail, navController.previousBackStackEntry!!.destination.route)
    }

    @Test fun chapterCommentsRequestsChapterOneWithoutRequestingAComposer() {
        navController.navigate(Routes.comments(123, chapterPosition = 1))
        assertEquals("1", Routes.routeArg(navController.currentBackStackEntry!!, "chapterPosition"))
        assertEquals(false, navController.currentBackStackEntry!!.arguments?.getBoolean("compose"))
    }
}
